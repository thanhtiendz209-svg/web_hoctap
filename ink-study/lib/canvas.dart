import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assets.dart';
import 'model.dart';

const double _paperWidth = 900;
const Color _accent = Color(0xff137683);

typedef _AssetKey = ({String asset, int page, int width});

enum _ObjectKind { image, shape, pdf }

enum _Handle {
  move,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _Selection {
  const _Selection(this.kind, this.index);

  final _ObjectKind kind;
  final int index;

  bool matches(_Selection? other) =>
      kind == other?.kind && index == other?.index;

  Rect? bounds(InkDocument document) => switch (kind) {
    _ObjectKind.image =>
      index < document.images.length ? document.images[index].bounds : null,
    _ObjectKind.shape =>
      index < document.shapes.length ? document.shapes[index].bounds : null,
    _ObjectKind.pdf =>
      index < document.pdfRegions.length
          ? document.pdfRegions[index].bounds
          : null,
  };
}

class _GroupSelection {
  const _GroupSelection({
    required this.bounds,
    required this.strokes,
    required this.shapes,
    required this.images,
    required this.regions,
  });

  final Rect bounds;
  final Set<int> strokes;
  final Set<int> shapes;
  final Set<int> images;
  final Set<int> regions;

  _Selection? get singleObject {
    if (strokes.isNotEmpty ||
        shapes.length + images.length + regions.length != 1) {
      return null;
    }
    if (shapes.isNotEmpty) return _Selection(_ObjectKind.shape, shapes.single);
    if (images.isNotEmpty) return _Selection(_ObjectKind.image, images.single);
    return _Selection(_ObjectKind.pdf, regions.single);
  }

  _GroupSelection shift(Offset delta) => _GroupSelection(
    bounds: bounds.shift(delta),
    strokes: strokes,
    shapes: shapes,
    images: images,
    regions: regions,
  );
}

_GroupSelection? _groupIn(InkDocument document, Rect rectangle) {
  final strokes = <int>{};
  final shapes = <int>{};
  final images = <int>{};
  final regions = <int>{};
  Rect? bounds;

  void include(Set<int> selected, int index, Rect objectBounds) {
    selected.add(index);
    bounds = bounds?.expandToInclude(objectBounds) ?? objectBounds;
  }

  for (final (index, stroke) in document.strokes.indexed) {
    final objectBounds = inkStrokeBounds(stroke);
    if (objectBounds.overlaps(rectangle) &&
        _pathHitsRectangle(
          stroke.points.map((point) => point.position),
          rectangle.inflate(stroke.width / 2),
        )) {
      include(strokes, index, objectBounds);
    }
  }
  for (final (index, shape) in document.shapes.indexed) {
    final target = rectangle.inflate(shape.width / 2);
    final edges = shapeEdges(shape);
    if (edges.any((edge) => _pathHitsRectangle(edge.points, target))) {
      final objectBounds = edges
          .expand((edge) => edge.points)
          .fold<Rect?>(
            null,
            (bounds, point) =>
                bounds?.expandToInclude(point & Size.zero) ??
                (point & Size.zero),
          );
      if (objectBounds != null) {
        include(shapes, index, objectBounds.inflate(shape.width / 2));
      }
    }
  }
  for (final (index, image) in document.images.indexed) {
    final sine = math.sin(image.rotation).abs();
    final cosine = math.cos(image.rotation).abs();
    final objectBounds = Rect.fromCenter(
      center: image.bounds.center,
      width: cosine * image.bounds.width + sine * image.bounds.height,
      height: sine * image.bounds.width + cosine * image.bounds.height,
    );
    if (objectBounds.overlaps(rectangle)) include(images, index, objectBounds);
  }
  for (final (index, region) in document.pdfRegions.indexed) {
    if (region.bounds.overlaps(rectangle)) {
      include(regions, index, region.bounds);
    }
  }
  final selectedBounds = bounds;
  return selectedBounds == null
      ? null
      : _GroupSelection(
          bounds: selectedBounds,
          strokes: strokes,
          shapes: shapes,
          images: images,
          regions: regions,
        );
}

bool _pathHitsRectangle(Iterable<Offset> points, Rect rectangle) {
  Offset? previous;
  for (final point in points) {
    if (rectangle.contains(point)) return true;
    if (previous != null &&
        _segmentCrossesRectangle(previous, point, rectangle)) {
      return true;
    }
    previous = point;
  }
  return false;
}

bool _segmentCrossesRectangle(Offset start, Offset end, Rect rectangle) {
  final delta = end - start;
  if (delta.dx != 0) {
    for (final x in [rectangle.left, rectangle.right]) {
      final fraction = (x - start.dx) / delta.dx;
      final y = start.dy + fraction * delta.dy;
      if (fraction >= 0 &&
          fraction <= 1 &&
          y >= rectangle.top &&
          y <= rectangle.bottom) {
        return true;
      }
    }
  }
  if (delta.dy != 0) {
    for (final y in [rectangle.top, rectangle.bottom]) {
      final fraction = (y - start.dy) / delta.dy;
      final x = start.dx + fraction * delta.dx;
      if (fraction >= 0 &&
          fraction <= 1 &&
          x >= rectangle.left &&
          x <= rectangle.right) {
        return true;
      }
    }
  }
  return false;
}

List<T> _mapSelected<T>(
  List<T> objects,
  Set<int> selected,
  T Function(T) move,
) => selected.isEmpty
    ? objects
    : [
        for (final (index, object) in objects.indexed)
          selected.contains(index) ? move(object) : object,
      ];

List<T> _withoutSelected<T>(List<T> objects, Set<int> selected) =>
    selected.isEmpty
    ? objects
    : [
        for (final (index, object) in objects.indexed)
          if (!selected.contains(index)) object,
      ];

class _Page {
  const _Page(this.index, this.info, this.bounds);

  final int index;
  final PdfPageInfo info;
  final Rect bounds;

  Rect fromSource(Rect source) {
    final scale = bounds.width / info.width;
    return Rect.fromLTWH(
      bounds.left + source.left * scale,
      bounds.top + source.top * scale,
      source.width * scale,
      source.height * scale,
    );
  }

  Rect toSource(Rect rect) {
    final scale = info.width / bounds.width;
    return Rect.fromLTWH(
      (rect.left - bounds.left) * scale,
      (rect.top - bounds.top) * scale,
      rect.width * scale,
      rect.height * scale,
    );
  }
}

List<_Page> _pages(InkDocument document) {
  var top = 0.0;
  return List<_Page>.generate(document.pdfPages.length, (index) {
    final info = document.pdfPages[index];
    final height = _paperWidth * info.height / info.width;
    final page = _Page(index, info, Rect.fromLTWH(0, top, _paperWidth, height));
    top += height;
    return page;
  });
}

class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.document,
    required this.store,
    required this.onChange,
    required this.tool,
    required this.color,
    required this.width,
    required this.penKind,
    required this.dashed,
    required this.shapeKind,
    required this.zoom,
    required this.scroll,
    required this.onViewportChanged,
    this.eraserWidth = defaultEraserWidth,
    this.panMode = false,
    this.onError,
    this.documentScope,
    this.onQuickSelect,
  });

  final InkDocument document;
  final InkStore store;
  final ValueChanged<InkDocument> onChange;
  final Tool tool;
  final Color color;
  final double width;
  final double eraserWidth;
  final PenKind penKind;
  final bool dashed;
  final ShapeKind shapeKind;
  final double zoom;
  final double scroll;
  final void Function(double zoom, double scroll) onViewportChanged;
  final bool panMode;
  final ValueChanged<String>? onError;
  final Object? documentScope;
  final VoidCallback? onQuickSelect;

  @override
  State<InkCanvas> createState() => InkCanvasState();
}

class InkCanvasState extends State<InkCanvas>
    with SingleTickerProviderStateMixin {
  static const _hardwareCacheLimit = 64 * 1024 * 1024;
  static const _handlePositions = <_Handle, Alignment>{
    _Handle.left: Alignment.centerLeft,
    _Handle.right: Alignment.centerRight,
    _Handle.top: Alignment.topCenter,
    _Handle.bottom: Alignment.bottomCenter,
    _Handle.topLeft: Alignment.topLeft,
    _Handle.topRight: Alignment.topRight,
    _Handle.bottomLeft: Alignment.bottomLeft,
    _Handle.bottomRight: Alignment.bottomRight,
  };

  final _revision = ValueNotifier<int>(0);
  final _images = <_AssetKey, ui.Image>{};
  final _queuedAssets = <_AssetKey>{};
  final _failedAssets = <_AssetKey>{};
  final _touches = <int, Offset>{};
  late AnimationController _laserFade;
  late double _zoom;
  late double _scroll;
  late Listenable _repaint;
  Size _size = const Size(900, 700);
  double _panX = 0;
  bool _assetFrameQueued = false;
  Offset? _gestureOrigin;
  Offset? _gestureLast;
  Offset? _eraserCursor;
  int? _pointer;
  Tool? _gestureTool;
  InkDocument? _working;
  InkStroke? _activeStroke;
  InkStrokeInput? _strokeInput;
  InkShape? _activeShape;
  _Selection? _selection;
  _GroupSelection? _groupSelection;
  InkDocument? _committedDocument;
  bool _selectingRectangle = false;
  bool _quickSelect = false;
  bool _movingGroup = false;
  Rect? _selectionRectangle;
  Offset _groupMove = Offset.zero;
  _Handle? _handle;
  _Page? _cropPage;
  Rect? _cropPreview;
  ({_Page page, Rect crop})? _pendingCrop;
  List<Offset> _laser = <Offset>[];
  double? _pinchSpacing;
  Offset? _pinchCenter;
  double _trackpadScale = 1;

  InkDocument get _document => _working ?? widget.document;
  double get _originX => (_size.width - _paperWidth * _zoom) / 2 + _panX;
  Offset get _origin => Offset(_originX, -_scroll * _zoom);

  Offset documentPoint(Offset local) => _onPaper(_toDocument(local));

  void fitWidth() => _setView((_size.width - 32) / _paperWidth, _scroll, 0);

  Rect get visibleBounds {
    final topLeft = _toDocument(Offset.zero);
    final bottomRight = _toDocument(Offset(_size.width, _size.height));
    return Rect.fromLTRB(
      topLeft.dx.clamp(0.0, _paperWidth).toDouble(),
      _scroll,
      bottomRight.dx.clamp(0.0, _paperWidth).toDouble(),
      bottomRight.dy,
    );
  }

  Rect get contentBounds {
    final doc = widget.document;
    var bottom = 0.0;
    final pages = _pages(doc);
    if (pages.isNotEmpty) bottom = pages.last.bounds.bottom;
    for (final stroke in doc.strokes) {
      bottom = math.max(bottom, inkStrokeBounds(stroke).bottom);
    }
    for (final shape in doc.shapes) {
      bottom = math.max(bottom, shape.bounds.bottom + shape.width);
    }
    for (final picture in doc.images) {
      final halfHeight =
          (picture.bounds.width * math.sin(picture.rotation).abs() +
              picture.bounds.height * math.cos(picture.rotation).abs()) /
          2;
      bottom = math.max(bottom, picture.bounds.center.dy + halfHeight);
    }
    for (final region in doc.pdfRegions) {
      bottom = math.max(bottom, region.bounds.bottom);
    }
    return bottom > 0
        ? Rect.fromLTWH(0, 0, _paperWidth, bottom + 12)
        : visibleBounds;
  }

  @override
  void initState() {
    super.initState();
    _zoom = _validZoom(widget.zoom);
    _scroll = math.max(0.0, widget.scroll);
    _laserFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _repaint = Listenable.merge([_revision, _laserFade]);
  }

  @override
  void didUpdateWidget(covariant InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) _zoom = _validZoom(widget.zoom);
    if (oldWidget.scroll != widget.scroll) {
      _scroll = math.max(0.0, widget.scroll);
    }
    if (oldWidget.tool != widget.tool) {
      cancelGesture(
        clearSelection:
            widget.tool != Tool.select && widget.tool != Tool.pdfCrop,
      );
    }
    final scopeChanged = oldWidget.documentScope != widget.documentScope;
    final documentChanged = !identical(oldWidget.document, widget.document);
    if (scopeChanged || documentChanged) {
      if (scopeChanged || !identical(_committedDocument, widget.document)) {
        cancelGesture();
      }
      _committedDocument = null;
      _pendingCrop = null;
    }
    if (_selection?.bounds(widget.document) == null) _selection = null;
    _queueAssets();
  }

  @override
  void dispose() {
    _laserFade.dispose();
    _revision.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  double _validZoom(double value) => value.clamp(0.20, 4.0).toDouble();
  Offset _toDocument(Offset local) => (local - _origin) / _zoom;
  bool _isOnPaper(Offset point) =>
      point.dx >= 0 && point.dx <= _paperWidth && point.dy >= 0;
  Offset _onPaper(Offset point) => Offset(
    point.dx.clamp(0.0, _paperWidth).toDouble(),
    math.max(0, point.dy),
  );
  void _refresh() => _revision.value++;

  void _setView(double zoom, double scroll, double pan) {
    _zoom = _validZoom(zoom);
    _scroll = math.max(0, scroll);
    final panLimit = math.max(0, (_paperWidth * _zoom + _size.width) / 2 - 60);
    _panX = pan.clamp(-panLimit, panLimit).toDouble();
    widget.onViewportChanged(_zoom, _scroll);
    _queueAssets();
    _refresh();
  }

  void _zoomAndPan(double factor, Offset before, Offset after) {
    final model = _toDocument(before);
    final nextZoom = _validZoom(_zoom * factor);
    final centeredOrigin = (_size.width - _paperWidth * nextZoom) / 2;
    _setView(
      nextZoom,
      model.dy - after.dy / nextZoom,
      after.dx - model.dx * nextZoom - centeredOrigin,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_pointer != null || event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) {
      _zoomAndPan(
        math.exp(-event.scrollDelta.dy * 0.003),
        event.localPosition,
        event.localPosition,
      );
    } else {
      final delta = event.scrollDelta;
      final horizontal = keyboard.isShiftPressed
          ? delta.dy + delta.dx
          : delta.dx;
      _setView(
        _zoom,
        _scroll + (keyboard.isShiftPressed ? 0 : delta.dy / _zoom),
        _panX - horizontal,
      );
    }
  }

  void _onTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (_pointer != null) return;
    final factor = event.scale / _trackpadScale;
    _trackpadScale = event.scale;
    _zoomAndPan(
      factor,
      event.localPosition,
      event.localPosition + event.panDelta,
    );
  }

  void _pinch() {
    if (_touches.length != 2 || _pointer != null) {
      _pinchCenter = null;
      _pinchSpacing = null;
      return;
    }
    final positions = _touches.values.iterator..moveNext();
    final first = positions.current;
    positions.moveNext();
    final second = positions.current;
    final spacing = (first - second).distance;
    final center = (first + second) / 2;
    final previous = _pinchCenter;
    final before = _pinchSpacing;
    _pinchCenter = center;
    _pinchSpacing = spacing;
    if (previous != null && before != null && before > 1 && spacing > 1) {
      _zoomAndPan(spacing / before, previous, center);
    }
  }

  double _pressure(PointerEvent event, {double fallback = 1}) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return 1;
    }
    final span = event.pressureMax - event.pressureMin;
    if (span <= 0 || event.pressure <= 0) return fallback;
    return ((event.pressure - event.pressureMin) / span)
        .clamp(0.10, 1.0)
        .toDouble();
  }

  void _pointerDown(PointerDownEvent event) {
    final point = _toDocument(event.localPosition);
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      _pinch();
      return;
    }
    if (_pointer != null) return;
    if (_pendingCrop != null) setState(() => _pendingCrop = null);
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kSecondaryMouseButton != 0) {
      if (widget.tool == Tool.select || widget.tool == Tool.pdfCrop) {
        if (widget.tool != Tool.select || !_inGroup(point)) {
          _groupSelection = null;
          _selection = _hitSelection(
            point,
            pdfOnly: widget.tool == Tool.pdfCrop,
          );
        }
        _refresh();
        _selectionMenu(event.position, point);
      }
      return;
    }
    final hand =
        widget.panMode ||
        widget.tool == Tool.hand ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.space,
        ) ||
        event.buttons & kMiddleMouseButton != 0;
    if (!hand && !_isOnPaper(point)) return;
    _quickSelect =
        !hand &&
        widget.onQuickSelect != null &&
        event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryMouseButton != 0) &&
        HardwareKeyboard.instance.isShiftPressed;
    final tool = hand
        ? Tool.hand
        : event.kind == PointerDeviceKind.invertedStylus
        ? Tool.eraser
        : _quickSelect
        ? Tool.select
        : widget.tool;
    _pointer = event.pointer;
    _gestureTool = tool;
    _gestureOrigin = point;
    _gestureLast = point;
    _working = null;
    switch (tool) {
      case Tool.pen:
        final input = InkStrokeInput(
          InkPoint(point, _pressure(event)),
          kind: widget.penKind,
        );
        _strokeInput = input;
        _activeStroke = InkStroke(
          points: input.points,
          color: widget.color,
          width: widget.width,
          kind: widget.penKind,
          dashed: widget.dashed,
        );
      case Tool.eraser:
        _eraserCursor = event.localPosition;
        _erase(point, point);
      case Tool.shape:
        _activeShape = InkShape(
          kind: widget.shapeKind,
          start: point,
          end: point,
          color: widget.color,
          width: widget.width,
          dashed: widget.dashed,
        );
      case Tool.laser:
        _laserFade.stop();
        _laserFade.value = 0;
        _laser = [point];
      case Tool.select:
        if (_quickSelect) {
          _startRectangleSelection();
        } else {
          _startSelect(point);
        }
      case Tool.pdfCrop:
        if (!_startSelection(point, pdfOnly: true)) {
          _cropPage = _pageAt(point);
          _cropPreview = null;
        }
      case Tool.hand:
        break;
    }
    _refresh();
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch &&
        _touches.containsKey(event.pointer)) {
      _touches[event.pointer] = event.localPosition;
      _pinch();
      return;
    }
    if (_pointer != event.pointer) return;
    final point = _onPaper(_toDocument(event.localPosition));
    final origin = _gestureOrigin;
    final last = _gestureLast;
    if (origin == null || last == null) return;
    switch (_gestureTool) {
      case Tool.hand:
        _setView(
          _zoom,
          _scroll - event.localDelta.dy / _zoom,
          _panX + event.localDelta.dx,
        );
      case Tool.pen:
        _strokeInput?.add(InkPoint(point, _pressure(event)));
      case Tool.eraser:
        _eraserCursor = event.localPosition;
        _erase(last, point);
      case Tool.shape:
        _activeShape = _activeShape?.copyWith(end: point);
      case Tool.laser:
        _laser.add(point);
      case Tool.select:
        if (_selectingRectangle) {
          _updateSelectionRectangle(origin, point);
        } else if (_movingGroup) {
          _moveGroup(point - origin);
        } else {
          _moveSelection(origin, point);
        }
      case Tool.pdfCrop:
        final page = _cropPage;
        if (page != null) {
          _cropPreview = Rect.fromPoints(origin, point).intersect(page.bounds);
        } else {
          _moveSelection(origin, point);
        }
      case null:
        break;
    }
    _gestureLast = point;
    _refresh();
  }

  void _pointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches.remove(event.pointer);
      _pinch();
      return;
    }
    if (_pointer != event.pointer) return;
    final stroke = _activeStroke;
    final shape = _activeShape;
    final last = _gestureLast;
    var selectedQuickly = false;
    final point = _onPaper(_toDocument(event.localPosition));
    if (_gestureTool == Tool.select && _gestureOrigin != null) {
      if (_selectingRectangle) {
        _updateSelectionRectangle(_gestureOrigin!, point);
        final draggedRectangle = _selectionRectangle != null;
        _finishSelection(point);
        selectedQuickly =
            _quickSelect &&
            draggedRectangle &&
            (_selection != null || _groupSelection != null);
      } else if (_movingGroup) {
        _moveGroup(point - _gestureOrigin!);
        _groupSelection = _groupSelection?.shift(_groupMove);
      }
    }
    if (_gestureTool == Tool.eraser &&
        last != null &&
        (point - last).distanceSquared > 0.0001) {
      _erase(last, point);
    }
    var update = _working;
    if (stroke != null) {
      final input = _strokeInput!;
      input.add(
        InkPoint(point, _pressure(event, fallback: input.lastPressure)),
      );
      update = widget.document.copyWith(
        strokes: [
          ...widget.document.strokes,
          stroke.copyWith(points: stroke.points),
        ],
      );
    } else if (shape != null && (shape.end - shape.start).distance > 1) {
      update = widget.document.copyWith(
        shapes: [...widget.document.shapes, shape],
      );
    }
    final page = _cropPage;
    final crop = _cropPreview;
    if (page != null && crop != null && crop.width > 4 && crop.height > 4) {
      setState(() => _pendingCrop = (page: page, crop: crop));
    }
    if (_gestureTool == Tool.laser) _laserFade.forward(from: 0);
    final showEraser =
        _gestureTool == Tool.eraser &&
        widget.tool == Tool.eraser &&
        event.kind != PointerDeviceKind.touch;
    _clearGesture();
    if (showEraser && (Offset.zero & _size).contains(event.localPosition)) {
      _eraserCursor = event.localPosition;
    }
    if (update != null) _commit(update);
    if (selectedQuickly) widget.onQuickSelect?.call();
    _refresh();
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches.remove(event.pointer);
      _pinch();
    } else if (_pointer == event.pointer) {
      cancelGesture();
    }
  }

  void _clearGesture() {
    _pointer = null;
    _gestureTool = null;
    _activeStroke = null;
    _strokeInput = null;
    _activeShape = null;
    _gestureOrigin = null;
    _gestureLast = null;
    _eraserCursor = null;
    _working = null;
    _cropPage = null;
    _cropPreview = null;
    _handle = null;
    _selectingRectangle = false;
    _quickSelect = false;
    _selectionRectangle = null;
    _movingGroup = false;
    _groupMove = Offset.zero;
  }

  void cancelGesture({bool clearSelection = true}) {
    if (_gestureTool == Tool.laser) _laserFade.forward(from: 0);
    _clearGesture();
    if (clearSelection) {
      _selection = null;
      _groupSelection = null;
    }
    if (_pendingCrop != null) setState(() => _pendingCrop = null);
    _refresh();
  }

  void _acceptCrop() {
    final pending = _pendingCrop;
    if (pending == null) return;
    final regions = [
      ...widget.document.pdfRegions,
      PdfRegion(
        page: pending.page.index,
        source: pending.page.toSource(pending.crop),
        bounds: pending.crop,
      ),
    ];
    _selection = _Selection(_ObjectKind.pdf, regions.length - 1);
    setState(() => _pendingCrop = null);
    _commit(widget.document.copyWith(pdfRegions: regions));
    _refresh();
  }

  void _commit(InkDocument document) {
    _committedDocument = document;
    widget.onChange(document);
  }

  void _erase(Offset start, Offset end) {
    final before = _document;
    final radius = widget.eraserWidth / (2 * _zoom);
    final strokes = eraseStrokes(before.strokes, start, end, radius);
    final shapes = eraseShapes(before.shapes, start, end, radius);
    if (!identical(before.strokes, strokes) ||
        !identical(before.shapes, shapes)) {
      _working = before.copyWith(strokes: strokes, shapes: shapes);
    }
  }

  _Page? _pageAt(Offset point) {
    for (final page in _pages(widget.document)) {
      if (page.bounds.contains(point)) return page;
    }
    return null;
  }

  Offset _handlePoint(Rect bounds, Alignment alignment) {
    return alignment.withinRect(bounds);
  }

  _Handle? _hitHandle(Rect bounds, Offset point) {
    for (final entry in _handlePositions.entries.toList().reversed) {
      if ((_handlePoint(bounds, entry.value) - point).distance <= 10 / _zoom) {
        return entry.key;
      }
    }
    return null;
  }

  _Selection? _hitSelection(Offset point, {required bool pdfOnly}) {
    final doc = widget.document;
    if (!pdfOnly) {
      for (var index = doc.shapes.length - 1; index >= 0; index--) {
        if (doc.shapes[index].bounds.inflate(8 / _zoom).contains(point)) {
          return _Selection(_ObjectKind.shape, index);
        }
      }
      for (var index = doc.images.length - 1; index >= 0; index--) {
        final image = doc.images[index];
        final relative = point - image.bounds.center;
        final transformed = Offset(
          relative.dx * math.cos(image.rotation) +
              relative.dy * math.sin(image.rotation),
          -relative.dx * math.sin(image.rotation) +
              relative.dy * math.cos(image.rotation),
        );
        if (image.bounds.contains(image.bounds.center + transformed)) {
          return _Selection(_ObjectKind.image, index);
        }
      }
    }
    for (var index = doc.pdfRegions.length - 1; index >= 0; index--) {
      if (doc.pdfRegions[index].bounds.contains(point)) {
        return _Selection(_ObjectKind.pdf, index);
      }
    }
    return null;
  }

  bool _startSelection(Offset point, {required bool pdfOnly}) {
    final current = _selection;
    final bounds = current?.bounds(widget.document);
    final handle = bounds == null ? null : _hitHandle(bounds, point);
    if (current != null &&
        handle != null &&
        (!pdfOnly || current.kind == _ObjectKind.pdf)) {
      _handle = handle;
      return true;
    }
    _selection = _hitSelection(point, pdfOnly: pdfOnly);
    _handle = _selection == null ? null : _Handle.move;
    return _selection != null;
  }

  bool _inGroup(Offset point) =>
      _groupSelection?.bounds.inflate(7 / _zoom).contains(point) ?? false;

  void _startSelect(Offset point) {
    if (_inGroup(point)) {
      _movingGroup = true;
      return;
    }
    final selected = _selection;
    final bounds = selected?.bounds(widget.document);
    if (selected != null && bounds != null) {
      _handle = _hitHandle(bounds, point);
      if (_handle != null) return;
      if (selected.matches(_hitSelection(point, pdfOnly: false))) {
        _handle = _Handle.move;
        return;
      }
    }
    _startRectangleSelection();
  }

  void _startRectangleSelection() {
    _selection = null;
    _groupSelection = null;
    _selectingRectangle = true;
  }

  void _updateSelectionRectangle(Offset start, Offset end) {
    final rectangle = Rect.fromPoints(start, end);
    _selectionRectangle =
        rectangle.width >= 3 / _zoom && rectangle.height >= 3 / _zoom
        ? rectangle
        : null;
  }

  void _finishSelection(Offset point) {
    final rectangle = _selectionRectangle;
    if (rectangle == null) {
      _selection = _hitSelection(point, pdfOnly: false);
      return;
    }
    final group = _groupIn(widget.document, rectangle);
    _selection = group?.singleObject;
    if (_selection == null) _groupSelection = group;
  }

  void _moveGroup(Offset delta) {
    final group = _groupSelection;
    if (group == null) return;
    final bounds = group.bounds;
    final left = math.min(0.0, bounds.left);
    final top = math.min(0.0, bounds.top);
    final right = math.max(_paperWidth, bounds.right);
    _groupMove = Offset(
      delta.dx.clamp(left - bounds.left, right - bounds.right).toDouble(),
      math.max(delta.dy, top - bounds.top),
    );
    if (_groupMove == Offset.zero) {
      _working = null;
      return;
    }
    final document = widget.document;
    _working = document.copyWith(
      strokes: _mapSelected(
        document.strokes,
        group.strokes,
        (stroke) => stroke.copyWith(
          points: [
            for (final point in stroke.points)
              InkPoint(point.position + _groupMove, point.pressure),
          ],
        ),
      ),
      shapes: _mapSelected(
        document.shapes,
        group.shapes,
        (shape) => shape.copyWith(
          start: shape.start + _groupMove,
          end: shape.end + _groupMove,
        ),
      ),
      images: _mapSelected(
        document.images,
        group.images,
        (image) => image.copyWith(bounds: image.bounds.shift(_groupMove)),
      ),
      pdfRegions: _mapSelected(
        document.pdfRegions,
        group.regions,
        (region) => region.copyWith(bounds: region.bounds.shift(_groupMove)),
      ),
    );
  }

  Rect _resize(Rect bounds, Offset delta, _Handle handle) {
    if (handle == _Handle.move) return bounds.shift(delta);
    if (handle == _Handle.left) {
      return Rect.fromLTRB(
        math.min(bounds.right - 8, bounds.left + delta.dx),
        bounds.top,
        bounds.right,
        bounds.bottom,
      );
    }
    if (handle == _Handle.right) {
      return Rect.fromLTRB(
        bounds.left,
        bounds.top,
        math.max(bounds.left + 8, bounds.right + delta.dx),
        bounds.bottom,
      );
    }
    if (handle == _Handle.top) {
      return Rect.fromLTRB(
        bounds.left,
        math.min(bounds.bottom - 8, bounds.top + delta.dy),
        bounds.right,
        bounds.bottom,
      );
    }
    if (handle == _Handle.bottom) {
      return Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        math.max(bounds.top + 8, bounds.bottom + delta.dy),
      );
    }
    final corner = _handlePositions[handle]!;
    final anchor = Alignment(-corner.x, -corner.y).withinRect(bounds);
    final vector = corner.withinRect(bounds) - anchor;
    final dot = vector.dx * delta.dx + vector.dy * delta.dy;
    final scale = math.max(0.08, 1 + dot / math.max(1, vector.distanceSquared));
    return Rect.fromPoints(anchor, anchor + vector * scale);
  }

  void _moveSelection(Offset origin, Offset point) {
    final selection = _selection;
    final handle = _handle;
    final doc = widget.document;
    final old = selection?.bounds(doc);
    if (selection == null || handle == null || old == null) return;
    final next = _resize(old, point - origin, handle);
    if (next == old) {
      _working = null;
      return;
    }
    switch (selection.kind) {
      case _ObjectKind.image:
        final images = [...doc.images];
        final image = images[selection.index];
        final keepRatio =
            handle == _Handle.left ||
            handle == _Handle.right ||
            handle == _Handle.top ||
            handle == _Handle.bottom;
        var bounds = next;
        if (keepRatio) {
          final horizontal = handle == _Handle.left || handle == _Handle.right;
          final width = horizontal
              ? next.width
              : next.height * old.width / old.height;
          final height = horizontal
              ? next.width * old.height / old.width
              : next.height;
          bounds = Rect.fromCenter(
            center: next.center,
            width: width,
            height: height,
          );
        }
        images[selection.index] = image.copyWith(bounds: bounds);
        _working = doc.copyWith(images: images);
      case _ObjectKind.shape:
        final shapes = [...doc.shapes];
        final shape = shapes[selection.index];
        Offset map(Offset input) => Offset(
          next.left +
              (input.dx - old.left) * next.width / math.max(1, old.width),
          next.top +
              (input.dy - old.top) * next.height / math.max(1, old.height),
        );
        shapes[selection.index] = shape.copyWith(
          start: map(shape.start),
          end: map(shape.end),
        );
        _working = doc.copyWith(shapes: shapes);
      case _ObjectKind.pdf:
        final regions = [...doc.pdfRegions];
        regions[selection.index] = regions[selection.index].copyWith(
          bounds: next,
        );
        _working = doc.copyWith(pdfRegions: regions);
    }
  }

  bool deleteSelection() {
    final group = _groupSelection;
    final selection = _selection;
    final doc = widget.document;
    if (group != null) {
      _groupSelection = null;
      _commit(
        doc.copyWith(
          strokes: _withoutSelected(doc.strokes, group.strokes),
          shapes: _withoutSelected(doc.shapes, group.shapes),
          images: _withoutSelected(doc.images, group.images),
          pdfRegions: _withoutSelected(doc.pdfRegions, group.regions),
        ),
      );
      _refresh();
      return true;
    }
    if (selection == null || selection.bounds(doc) == null) return false;
    _selection = null;
    final update = switch (selection.kind) {
      _ObjectKind.image => doc.copyWith(
        images: [...doc.images]..removeAt(selection.index),
      ),
      _ObjectKind.shape => doc.copyWith(
        shapes: [...doc.shapes]..removeAt(selection.index),
      ),
      _ObjectKind.pdf => doc.copyWith(
        pdfRegions: [...doc.pdfRegions]..removeAt(selection.index),
      ),
    };
    _commit(update);
    _refresh();
    return true;
  }

  double _edgeDistance(Offset point, Offset from, Offset to) {
    final vector = to - from;
    if (vector.distanceSquared < 0.01) return (point - from).distanceSquared;
    final relative = point - from;
    final amount =
        ((relative.dx * vector.dx + relative.dy * vector.dy) /
                vector.distanceSquared)
            .clamp(0.0, 1.0)
            .toDouble();
    return (relative - vector * amount).distanceSquared;
  }

  int? _nearestEdge(InkShape shape, Offset point) {
    final edges = shapeEdges(shape);
    var distance = double.infinity;
    int? closest;
    for (var index = 0; index < edges.length; index++) {
      final points = edges[index].points;
      for (var p = 1; p < points.length; p++) {
        final test = _edgeDistance(point, points[p - 1], points[p]);
        if (test < distance) {
          distance = test;
          closest = index;
        }
      }
    }
    return closest;
  }

  Future<void> _selectionMenu(Offset globalPosition, Offset point) async {
    final group = _groupSelection;
    final selection = _selection;
    final doc = widget.document;
    if (group == null && selection?.bounds(doc) == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final shape = selection?.kind == _ObjectKind.shape
        ? doc.shapes[selection!.index]
        : null;
    final edge = shape == null ? null : _nearestEdge(shape, point);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        overlay.size,
      ),
      items: [
        if (shape != null && edge != null)
          PopupMenuItem(
            value: 'dash',
            child: Text(
              isShapeEdgeDashed(shape, edge)
                  ? 'Đổi cạnh này thành nét liền'
                  : 'Đổi cạnh này thành nét đứt',
            ),
          ),
        if (selection?.kind == _ObjectKind.image)
          const PopupMenuItem(value: 'rotate', child: Text('Xoay ảnh 90°')),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            group != null
                ? 'Xóa phần đã chọn'
                : selection?.kind == _ObjectKind.pdf
                ? 'Khôi phục vùng PDF gốc'
                : 'Xóa đối tượng',
          ),
        ),
      ],
    );
    if (!mounted ||
        !identical(_groupSelection, group) ||
        !identical(_selection, selection) ||
        !identical(widget.document, doc)) {
      return;
    }
    if (action == 'delete') {
      deleteSelection();
    } else if (action == 'rotate' && selection != null) {
      final images = [...doc.images];
      final image = images[selection.index];
      images[selection.index] = image.copyWith(
        rotation: (image.rotation + math.pi / 2) % (2 * math.pi),
      );
      _commit(doc.copyWith(images: images));
    } else if (action == 'dash' &&
        shape != null &&
        edge != null &&
        selection != null) {
      final shapes = [...doc.shapes];
      final edits = {...shape.dashedEdges};
      if (!edits.remove(edge)) edits.add(edge);
      shapes[selection.index] = shape.copyWith(dashedEdges: edits);
      _commit(doc.copyWith(shapes: shapes));
    }
  }

  int get _bitmapWidth => (_paperWidth * _zoom).clamp(640, 1600).toInt();

  Set<_AssetKey> _neededAssets(InkDocument doc, Rect view, int pixelWidth) {
    final set = <_AssetKey>{};
    final pdf = doc.pdfAsset;
    if (pdf != null) {
      for (final page in _pages(doc)) {
        if (view.overlaps(page.bounds)) {
          set.add((asset: pdf, page: page.index, width: pixelWidth));
        }
      }
      for (final region in doc.pdfRegions) {
        if (view.overlaps(region.bounds)) {
          set.add((asset: pdf, page: region.page, width: pixelWidth));
        }
      }
    }
    for (final image in doc.images) {
      if (view.overlaps(
        image.bounds.inflate(
          math.max(image.bounds.width, image.bounds.height) * 0.5,
        ),
      )) {
        set.add((asset: image.asset, page: -1, width: 0));
      }
    }
    return set;
  }

  Future<ui.Image> _load(_AssetKey key) => key.page < 0
      ? widget.store.image(key.asset)
      : widget.store.pdfPage(key.asset, key.page, key.width);

  void _queueAssets() {
    if (_assetFrameQueued) return;
    _assetFrameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _assetFrameQueued = false;
      final view = visibleBounds.inflate(180);
      final keys = _neededAssets(_document, view, _bitmapWidth);
      for (final key in keys) {
        final cached = _images.remove(key);
        if (cached != null) {
          _images[key] = cached;
        } else if (!_queuedAssets.contains(key) &&
            !_failedAssets.contains(key) &&
            _queuedAssets.length < 4) {
          _request(key);
        }
      }
    });
  }

  Future<void> _request(_AssetKey key) async {
    _queuedAssets.add(key);
    try {
      final bitmap = await _load(key);
      if (!mounted) {
        bitmap.dispose();
        return;
      }
      _images[key] = bitmap;
      var bytes = _images.values.fold<int>(
        0,
        (total, value) => total + value.width * value.height * 4,
      );
      while (bytes > _hardwareCacheLimit && _images.length > 1) {
        final oldest = _images.remove(_images.keys.first)!;
        bytes -= oldest.width * oldest.height * 4;
        oldest.dispose();
      }
    } catch (error) {
      if (mounted && _failedAssets.add(key)) {
        widget.onError?.call('Không thể hiển thị tài liệu hoặc ảnh. $error');
      }
    } finally {
      _queuedAssets.remove(key);
      if (mounted) {
        _refresh();
        _queueAssets();
      }
    }
  }

  ui.Image? _cached(String asset, int page) {
    final exact =
        _images[(asset: asset, page: page, width: page < 0 ? 0 : _bitmapWidth)];
    if (exact != null || page < 0) return exact;
    for (final entry in _images.entries.toList().reversed) {
      if (entry.key.asset == asset && entry.key.page == page) {
        return entry.value;
      }
    }
    return null;
  }

  Future<Uint8List> render(Rect region, double scale) async {
    final doc = widget.document;
    final pixelsWide = math.max(1, (region.width * scale).ceil());
    final pixelsHigh = math.max(1, (region.height * scale).ceil());
    final pixelWidth = (_paperWidth * scale).ceil().clamp(640, 2400).toInt();
    final keys = _neededAssets(doc, region, pixelWidth);
    final images = <_AssetKey, ui.Image>{};
    try {
      for (final key in keys) {
        images[key] = await _load(key);
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, pixelsWide.toDouble(), pixelsHigh.toDouble()),
      );
      canvas.scale(scale);
      canvas.translate(-region.left, -region.top);
      _paintDocument(
        canvas,
        region,
        doc,
        (asset, page) =>
            images[(
              asset: asset,
              page: page,
              width: page < 0 ? 0 : pixelWidth,
            )],
      );
      final picture = recorder.endRecording();
      try {
        final bitmap = await picture.toImage(pixelsWide, pixelsHigh);
        try {
          final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Không thể tạo ảnh cho bản xuất.');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          bitmap.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  }

  void _paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(_origin.dx, _origin.dy);
    canvas.scale(_zoom);
    final view = visibleBounds;
    canvas.clipRect(Rect.fromLTRB(0, view.top, _paperWidth, view.bottom));
    final doc = _document;
    _paintDocument(canvas, view, doc, _cached);
    final shape = _activeShape;
    final stroke = _activeStroke;
    if (shape != null) _paintShape(canvas, shape);
    if (stroke != null) paintInkStroke(canvas, stroke);
    final rect = _selection?.bounds(doc);
    if (rect != null &&
        (widget.tool == Tool.select || widget.tool == Tool.pdfCrop)) {
      _paintSelection(canvas, rect, handles: true);
    }
    final group = _groupSelection;
    if (group != null && widget.tool == Tool.select) {
      _paintSelection(
        canvas,
        group.bounds.shift(_groupMove).inflate(5 / _zoom),
        handles: false,
      );
    }
    final selectionRectangle = _selectionRectangle;
    if (selectionRectangle != null) {
      _paintSelection(canvas, selectionRectangle, handles: false);
    }
    final crop = _cropPreview ?? _pendingCrop?.crop;
    if (crop != null && !crop.isEmpty) {
      _paintSelection(canvas, crop, handles: false);
    }
    if (_laser.isNotEmpty && _laserFade.value < 1) {
      final opacity = 1 - _laserFade.value;
      final path = Path()..moveTo(_laser.first.dx, _laser.first.dy);
      for (final point in _laser.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final paint = Paint()
        ..color = const Color(0xffef3058).withValues(alpha: 0.8 * opacity)
        ..strokeWidth = 7 / _zoom
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (_laser.length == 1) {
        canvas.drawCircle(
          _laser.first,
          4 / _zoom,
          Paint()..color = paint.color,
        );
      } else {
        canvas.drawPath(path, paint);
        canvas.drawPath(
          path,
          paint
            ..color = Colors.white.withValues(alpha: opacity)
            ..strokeWidth = 2 / _zoom,
        );
      }
    }
    canvas.restore();
    final eraserCursor = _eraserCursor;
    if (eraserCursor != null &&
        _isOnPaper(_toDocument(eraserCursor)) &&
        (Offset.zero & size).contains(eraserCursor)) {
      final radius = widget.eraserWidth / 2;
      canvas.drawCircle(
        eraserCursor,
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        eraserCursor,
        radius,
        Paint()
          ..color = const Color(0xff344861)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _paintSelection(Canvas canvas, Rect rect, {required bool handles}) {
    canvas.drawRect(rect, Paint()..color = _accent.withValues(alpha: 0.10));
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25 / _zoom
      ..color = _accent;
    canvas.drawRect(rect, border);
    if (handles) {
      for (final direction in _handlePositions.values) {
        final center = direction.withinRect(rect);
        canvas.drawCircle(center, 3.6 / _zoom, Paint()..color = Colors.white);
        canvas.drawCircle(center, 3.6 / _zoom, border);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        _queueAssets();
        final cursor = widget.panMode || widget.tool == Tool.hand
            ? SystemMouseCursors.grab
            : widget.tool == Tool.select
            ? SystemMouseCursors.basic
            : SystemMouseCursors.precise;
        final paper = MouseRegion(
          cursor: cursor,
          onHover: (event) {
            if (widget.tool != Tool.eraser) return;
            _eraserCursor = event.localPosition;
            _refresh();
          },
          onExit: (_) {
            if (_eraserCursor == null) return;
            _eraserCursor = null;
            if (mounted) _refresh();
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerUp,
            onPointerCancel: _pointerCancel,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: (_) => _trackpadScale = 1,
            onPointerPanZoomUpdate: _onTrackpadUpdate,
            child: Semantics(
              label: 'Giấy ghi chú liền mạch',
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _InkPainter(_paint, _repaint),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        if (_pendingCrop == null) return paper;
        return Stack(
          fit: StackFit.expand,
          children: [
            paper,
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  elevation: 5,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Vùng PDF đã chọn'),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => cancelGesture(),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: _acceptCrop,
                          child: const Text('Tách vùng'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.paintFrame, Listenable repaint) : super(repaint: repaint);

  final void Function(Canvas, Size) paintFrame;

  @override
  void paint(Canvas canvas, Size size) => paintFrame(canvas, size);

  @override
  bool shouldRepaint(_InkPainter oldDelegate) => true;
}

void _paintDocument(
  Canvas canvas,
  Rect view,
  InkDocument doc,
  ui.Image? Function(String, int) lookup,
) {
  canvas.save();
  canvas.clipRect(view);
  _paintPaper(canvas, view, doc);
  final pdf = doc.pdfAsset;
  final bitmapPaint = Paint()..filterQuality = FilterQuality.medium;
  if (pdf != null) {
    final pages = _pages(doc);
    for (final page in pages) {
      if (!view.overlaps(page.bounds)) continue;
      canvas.save();
      canvas.clipRect(page.bounds, doAntiAlias: false);
      for (final region in doc.pdfRegions) {
        if (region.page == page.index) {
          final cut = page.fromSource(region.source);
          canvas.clipPath(
            Path.combine(
              ui.PathOperation.difference,
              Path()..addRect(page.bounds),
              Path()..addRect(cut),
            ),
            doAntiAlias: false,
          );
        }
      }
      final image = lookup(pdf, page.index);
      if (image == null) {
        canvas.drawRect(page.bounds, Paint()..color = Colors.white);
      } else {
        canvas.drawImageRect(
          image,
          _imageRect(image),
          page.bounds,
          bitmapPaint,
        );
      }
      canvas.restore();
    }
    for (final region in doc.pdfRegions) {
      if (region.page < 0 ||
          region.page >= pages.length ||
          !view.overlaps(region.bounds)) {
        continue;
      }
      final image = lookup(pdf, region.page);
      if (image == null) continue;
      final page = pages[region.page];
      final source = Rect.fromLTRB(
        region.source.left * image.width / page.info.width,
        region.source.top * image.height / page.info.height,
        region.source.right * image.width / page.info.width,
        region.source.bottom * image.height / page.info.height,
      );
      canvas.drawImageRect(image, source, region.bounds, bitmapPaint);
    }
  }
  for (final picture in doc.images) {
    final image = lookup(picture.asset, -1);
    if (image == null) continue;
    canvas.save();
    final center = picture.bounds.center;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(picture.rotation);
    canvas.drawImageRect(
      image,
      _imageRect(image),
      Rect.fromCenter(
        center: Offset.zero,
        width: picture.bounds.width,
        height: picture.bounds.height,
      ),
      bitmapPaint,
    );
    canvas.restore();
  }
  for (final shape in doc.shapes) {
    if (view.overlaps(shape.bounds.inflate(shape.width))) {
      _paintShape(canvas, shape);
    }
  }
  for (final stroke in doc.strokes) {
    if (stroke.points.isEmpty) continue;
    paintInkStroke(canvas, stroke, view: view);
  }
  canvas.restore();
}

Rect _imageRect(ui.Image bitmap) =>
    Rect.fromLTWH(0, 0, bitmap.width.toDouble(), bitmap.height.toDouble());

void _paintPaper(Canvas canvas, Rect view, InkDocument doc) {
  canvas.drawRect(view, Paint()..color = doc.paperColor);
  if (doc.paper == PaperKind.blank) return;
  final spacing = doc.paper == PaperKind.ruled ? 36.0 : 24.0;
  final light = doc.paperColor.computeLuminance() >= 0.35;
  final line = Paint()
    ..color = light ? const Color(0xffdbe3ee) : const Color(0xff41495a)
    ..strokeWidth = 0.8;
  final left = (view.left / spacing).floor() * spacing;
  for (
    var y = (view.top / spacing).floor() * spacing;
    y <= view.bottom;
    y += spacing
  ) {
    if (doc.paper == PaperKind.dots) {
      for (var x = left; x <= view.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, line);
      }
    } else {
      canvas.drawLine(Offset(view.left, y), Offset(view.right, y), line);
    }
  }
  if (doc.paper == PaperKind.grid) {
    for (var x = left; x <= view.right; x += spacing) {
      canvas.drawLine(Offset(x, view.top), Offset(x, view.bottom), line);
    }
  }
}

void _paintShape(Canvas canvas, InkShape shape) {
  final edges = shapeEdges(shape);
  final paint = Paint()
    ..color = shape.color
    ..strokeWidth = shape.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (var index = 0; index < edges.length; index++) {
    final points = edges[index].points;
    if (points.length < 2) continue;
    if (!isShapeEdgeDashed(shape, index)) {
      final path = Path()..addPolygon(points, false);
      canvas.drawPath(path, paint);
    } else {
      var arc = 0.0;
      for (var step = 1; step < points.length; step++) {
        final first = points[step - 1];
        final second = points[step];
        _paintSegment(canvas, paint, first, second, arc, shape.width);
        arc += (second - first).distance;
      }
    }
  }
}

void paintInkStroke(Canvas canvas, InkStroke stroke, {Rect? view}) {
  if (stroke.points.isEmpty) return;
  final firstPoint = stroke.points.first;
  final highlighter = stroke.kind == PenKind.highlighter;
  final pencil = stroke.kind == PenKind.pencil;
  final paint = Paint()
    ..color = stroke.color.withValues(alpha: 1)
    ..strokeCap = StrokeCap.round;
  final opacity =
      stroke.color.a *
      (highlighter
          ? 0.32
          : pencil
          ? 0.78
          : 1.0);
  final bounds = view == null
      ? _activeStrokeBounds(stroke)
      : inkStrokeBounds(stroke);
  if (view != null && !view.overlaps(bounds)) return;
  if (opacity < 1) {
    canvas.saveLayer(
      bounds,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
  }
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      firstPoint.position,
      inkWidth(stroke, firstPoint.pressure) / 2,
      paint,
    );
  } else {
    var arc = stroke.phase;
    for (var index = 1; index < stroke.points.length; index++) {
      final from = stroke.points[index - 1];
      final to = stroke.points[index];
      final radiusFrom = inkWidth(stroke, from.pressure) / 2;
      final radiusTo = inkWidth(stroke, to.pressure) / 2;
      final delta = to.position - from.position;
      final distance = delta.distance;
      if (stroke.dashed) {
        for (final span in inkDashSpans(distance, arc, stroke.width)) {
          final change = radiusTo - radiusFrom;
          _paintTaperedSegment(
            canvas,
            paint,
            from.position + delta * span.start,
            from.position + delta * span.end,
            radiusFrom + change * span.start,
            radiusFrom + change * span.end,
          );
        }
      } else {
        _paintTaperedSegment(
          canvas,
          paint,
          from.position,
          to.position,
          radiusFrom,
          radiusTo,
        );
      }
      arc += distance;
    }
  }
  if (opacity < 1) canvas.restore();
}

void _paintTaperedSegment(
  Canvas canvas,
  Paint paint,
  Offset from,
  Offset to,
  double firstRadius,
  double lastRadius,
) {
  final delta = to - from;
  final distance = delta.distance;
  final radiusDifference = firstRadius - lastRadius;
  if (distance <= radiusDifference.abs()) {
    canvas.drawCircle(
      radiusDifference >= 0 ? from : to,
      math.max(firstRadius, lastRadius),
      paint,
    );
    return;
  }
  if (radiusDifference.abs() < 0.01) {
    canvas.drawLine(from, to, paint..strokeWidth = firstRadius * 2);
    return;
  }

  // Join the tangent sides of the end circles. The resulting silhouette uses
  // the same linear radius as the swept eraser calculation.
  final axis = delta / distance;
  final ratio = radiusDifference / distance;
  final perpendicular =
      Offset(-axis.dy, axis.dx) * math.sqrt(1 - ratio * ratio);
  final sideA = axis * ratio + perpendicular;
  final sideB = axis * ratio - perpendicular;
  canvas.drawPath(
    Path()..addPolygon([
      from + sideA * firstRadius,
      to + sideA * lastRadius,
      to + sideB * lastRadius,
      from + sideB * firstRadius,
    ], true),
    paint,
  );
  canvas.drawCircle(from, firstRadius, paint);
  canvas.drawCircle(to, lastRadius, paint);
}

Rect _activeStrokeBounds(InkStroke stroke) {
  final first = stroke.points.first.position;
  var bounds = Rect.fromPoints(first, first);
  for (final point in stroke.points.skip(1)) {
    bounds = bounds.expandToInclude(
      Rect.fromPoints(point.position, point.position),
    );
  }
  return bounds.inflate(math.max(2.0, stroke.width * 1.7));
}

void _paintSegment(
  Canvas canvas,
  Paint paint,
  Offset from,
  Offset to,
  double offset,
  double width,
) {
  final delta = to - from;
  for (final span in inkDashSpans(delta.distance, offset, width)) {
    canvas.drawLine(from + delta * span.start, from + delta * span.end, paint);
  }
}
