import 'dart:math' as math;
import 'dart:ui';

enum PaperKind { blank, ruled, grid, dots }

enum PenKind { ballpoint, pencil, highlighter }

enum ShapeKind {
  line,
  arrow,
  triangle,
  rectangle,
  circle,
  box,
  pyramid,
  cylinder,
}

enum Tool { pen, eraser, select, shape, laser, hand, pdfCrop }

class InkPoint {
  const InkPoint(this.position, [this.pressure = 1]);

  final Offset position;
  final double pressure;

  List<double> toJson() => [position.dx, position.dy, pressure];

  factory InkPoint.fromJson(Object? value) {
    final values = value as List;
    return InkPoint(
      _offset(values),
      values.length > 2 ? (values[2] as num).toDouble() : 1,
    );
  }
}

/// Captures rounded ink samples once, so painting, saving and cutting share
/// the same geometry. Each new event only changes the unfinished corner.
class InkStrokeInput {
  InkStrokeInput(InkPoint first) : points = [first], _latest = first;

  final List<InkPoint> points;
  InkPoint? _previous;
  InkPoint _latest;

  double get lastPressure => _latest.pressure;

  void add(InkPoint next) {
    final outgoing = next.position - _latest.position;
    if (outgoing.distanceSquared < 0.0144) return;
    final previous = _previous;
    if (previous != null) _roundCorner(previous, _latest, next);
    points.add(next);
    _previous = _latest;
    _latest = next;
  }

  void _roundCorner(InkPoint previous, InkPoint corner, InkPoint next) {
    final incoming = corner.position - previous.position;
    final outgoing = next.position - corner.position;
    final before = incoming.distance;
    final after = outgoing.distance;
    final turn = _dot(incoming, outgoing) / (before * after);
    if (turn >= 0.995 || turn <= -0.80) return;
    final trim = math.min(6.0, math.min(before, after) / 3);
    final start = _lerpPoint(previous, corner, 1 - trim / before);
    final end = _lerpPoint(corner, next, trim / after);
    final steps = (trim * 1.2).ceil().clamp(2, 8);
    points.removeLast();
    points.add(start);
    for (var index = 1; index < steps; index++) {
      final fraction = index / steps;
      points.add(
        _lerpPoint(
          _lerpPoint(start, corner, fraction),
          _lerpPoint(corner, end, fraction),
          fraction,
        ),
      );
    }
    points.add(end);
  }
}

class InkStroke {
  const InkStroke({
    required this.points,
    required this.color,
    required this.width,
    this.kind = PenKind.ballpoint,
    this.dashed = false,
    this.phase = 0,
  });

  final List<InkPoint> points;
  final Color color;
  final double width;
  final PenKind kind;
  final bool dashed;

  /// Distance along the original stroke before the first point of this piece.
  final double phase;

  InkStroke copyWith({
    List<InkPoint>? points,
    Color? color,
    double? width,
    PenKind? kind,
    bool? dashed,
    double? phase,
  }) => InkStroke(
    points: points == null ? this.points : List.unmodifiable(points),
    color: color ?? this.color,
    width: width ?? this.width,
    kind: kind ?? this.kind,
    dashed: dashed ?? this.dashed,
    phase: phase ?? this.phase,
  );

  Map<String, Object?> toJson() => {
    'points': points.map((point) => point.toJson()).toList(),
    'color': color.toARGB32(),
    'width': width,
    'kind': kind.name,
    'dashed': dashed,
    'phase': phase,
  };

  factory InkStroke.fromJson(Map<String, dynamic> data) => InkStroke(
    points: _list(data['points'], InkPoint.fromJson),
    color: _color(data['color'], const Color(0xff1e2534)),
    width: _number(data['width'], 2),
    kind: _enum(PenKind.values, data['kind'], PenKind.ballpoint),
    dashed: data['dashed'] == true,
    phase: _number(data['phase'], 0),
  );
}

class InkShape {
  const InkShape({
    required this.kind,
    required this.start,
    required this.end,
    required this.color,
    required this.width,
    this.dashedEdges = const {},
    this.dashed = false,
  });

  final ShapeKind kind;
  final Offset start;
  final Offset end;
  final Color color;
  final double width;

  /// Edges whose dash setting is toggled from the shape template.
  final Set<int> dashedEdges;
  final bool dashed;

  Rect get bounds => Rect.fromPoints(start, end);

  InkShape copyWith({
    ShapeKind? kind,
    Offset? start,
    Offset? end,
    Color? color,
    double? width,
    Set<int>? dashedEdges,
    bool? dashed,
  }) => InkShape(
    kind: kind ?? this.kind,
    start: start ?? this.start,
    end: end ?? this.end,
    color: color ?? this.color,
    width: width ?? this.width,
    dashedEdges: dashedEdges == null
        ? this.dashedEdges
        : Set.unmodifiable(dashedEdges),
    dashed: dashed ?? this.dashed,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'start': _offsetData(start),
    'end': _offsetData(end),
    'color': color.toARGB32(),
    'width': width,
    'dashed': dashed,
    'dashedEdges': dashedEdges.toList(),
  };

  factory InkShape.fromJson(Map<String, dynamic> data) => InkShape(
    kind: _enum(ShapeKind.values, data['kind'], ShapeKind.line),
    start: _offset(data['start']),
    end: _offset(data['end']),
    color: _color(data['color'], const Color(0xff1e2534)),
    width: _number(data['width'], 2),
    dashed: data['dashed'] == true,
    dashedEdges: Set<int>.unmodifiable(
      (data['dashedEdges'] as List? ?? const []).whereType<int>(),
    ),
  );
}

class InkImage {
  const InkImage({
    required this.asset,
    required this.bounds,
    this.rotation = 0,
  });

  final String asset;
  final Rect bounds;
  final double rotation;

  InkImage copyWith({String? asset, Rect? bounds, double? rotation}) =>
      InkImage(
        asset: asset ?? this.asset,
        bounds: bounds ?? this.bounds,
        rotation: rotation ?? this.rotation,
      );

  Map<String, Object?> toJson() => {
    'asset': asset,
    'bounds': _rectData(bounds),
    'rotation': rotation,
  };

  factory InkImage.fromJson(Map<String, dynamic> data) => InkImage(
    asset: data['asset'] as String,
    bounds: _rect(data['bounds']),
    rotation: _number(data['rotation'], 0),
  );
}

class PdfPageInfo {
  const PdfPageInfo({required this.width, required this.height});

  final double width;
  final double height;

  Map<String, Object?> toJson() => {'width': width, 'height': height};

  factory PdfPageInfo.fromJson(Map<String, dynamic> data) => PdfPageInfo(
    width: (data['width'] as num).toDouble(),
    height: (data['height'] as num).toDouble(),
  );
}

class PdfRegion {
  const PdfRegion({
    required this.page,
    required this.source,
    required this.bounds,
  });

  /// Zero-based page number in the source PDF.
  final int page;

  /// Rectangle in PDF points, measured from the top-left of the page.
  final Rect source;
  final Rect bounds;

  PdfRegion copyWith({int? page, Rect? source, Rect? bounds}) => PdfRegion(
    page: page ?? this.page,
    source: source ?? this.source,
    bounds: bounds ?? this.bounds,
  );

  Map<String, Object?> toJson() => {
    'page': page,
    'source': _rectData(source),
    'bounds': _rectData(bounds),
  };

  factory PdfRegion.fromJson(Map<String, dynamic> data) => PdfRegion(
    page: data['page'] as int,
    source: _rect(data['source']),
    bounds: _rect(data['bounds']),
  );
}

const _unchanged = Object();

class InkDocument {
  const InkDocument({
    this.strokes = const [],
    this.shapes = const [],
    this.images = const [],
    this.pdfAsset,
    this.pdfPages = const [],
    this.pdfRegions = const [],
    this.paper = PaperKind.grid,
    this.paperColor = const Color(0xfff9fafc),
  });

  final List<InkStroke> strokes;
  final List<InkShape> shapes;
  final List<InkImage> images;
  final String? pdfAsset;
  final List<PdfPageInfo> pdfPages;
  final List<PdfRegion> pdfRegions;
  final PaperKind paper;
  final Color paperColor;

  InkDocument copyWith({
    List<InkStroke>? strokes,
    List<InkShape>? shapes,
    List<InkImage>? images,
    Object? pdfAsset = _unchanged,
    List<PdfPageInfo>? pdfPages,
    List<PdfRegion>? pdfRegions,
    PaperKind? paper,
    Color? paperColor,
  }) => InkDocument(
    strokes: strokes == null ? this.strokes : List.unmodifiable(strokes),
    shapes: shapes == null ? this.shapes : List.unmodifiable(shapes),
    images: images == null ? this.images : List.unmodifiable(images),
    pdfAsset: identical(pdfAsset, _unchanged)
        ? this.pdfAsset
        : pdfAsset as String?,
    pdfPages: pdfPages == null ? this.pdfPages : List.unmodifiable(pdfPages),
    pdfRegions: pdfRegions == null
        ? this.pdfRegions
        : List.unmodifiable(pdfRegions),
    paper: paper ?? this.paper,
    paperColor: paperColor ?? this.paperColor,
  );

  Map<String, Object?> toJson() => {
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    'shapes': shapes.map((shape) => shape.toJson()).toList(),
    'images': images.map((image) => image.toJson()).toList(),
    'pdfAsset': pdfAsset,
    'pdfPages': pdfPages.map((page) => page.toJson()).toList(),
    'pdfRegions': pdfRegions.map((region) => region.toJson()).toList(),
    'paper': paper.name,
    'paperColor': paperColor.toARGB32(),
  };

  factory InkDocument.fromJson(Map<String, dynamic> data) => InkDocument(
    strokes: _objects(data['strokes'], InkStroke.fromJson),
    shapes: _objects(data['shapes'], InkShape.fromJson),
    images: _objects(data['images'], InkImage.fromJson),
    pdfAsset: data['pdfAsset'] as String?,
    pdfPages: _objects(data['pdfPages'], PdfPageInfo.fromJson),
    pdfRegions: _objects(data['pdfRegions'], PdfRegion.fromJson),
    paper: _enum(PaperKind.values, data['paper'], PaperKind.grid),
    paperColor: _color(data['paperColor'], const Color(0xfff9fafc)),
  );
}

class InkNote {
  const InkNote({
    required this.id,
    required this.title,
    this.notebook = 'Sổ học tập',
    this.document = const InkDocument(),
    this.scroll = 0,
    this.zoom = 1,
  });

  final String id;
  final String title;
  final String notebook;
  final InkDocument document;
  final double scroll;
  final double zoom;

  InkNote copyWith({
    String? id,
    String? title,
    String? notebook,
    InkDocument? document,
    double? scroll,
    double? zoom,
  }) => InkNote(
    id: id ?? this.id,
    title: title ?? this.title,
    notebook: notebook ?? this.notebook,
    document: document ?? this.document,
    scroll: scroll ?? this.scroll,
    zoom: zoom ?? this.zoom,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'notebook': notebook,
    'document': document.toJson(),
    'scroll': scroll,
    'zoom': zoom,
  };

  factory InkNote.fromJson(Map<String, dynamic> data) => InkNote(
    id: data['id'] as String,
    title: data['title'] as String,
    notebook: data['notebook'] as String? ?? 'Sổ học tập',
    document: InkDocument.fromJson(
      data['document'] as Map<String, dynamic>? ?? const {},
    ),
    scroll: _number(data['scroll'], 0),
    zoom: _number(data['zoom'], 1),
  );
}

double _number(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

Color _color(Object? value, Color fallback) =>
    value is num ? Color(value.toInt()) : fallback;

T _enum<T extends Enum>(List<T> options, Object? value, T fallback) {
  for (final option in options) {
    if (option.name == value) return option;
  }
  return fallback;
}

List<T> _list<T>(Object? values, T Function(Object?) read) =>
    List<T>.unmodifiable((values as List? ?? const []).map(read));

List<T> _objects<T>(Object? values, T Function(Map<String, dynamic>) read) =>
    _list(values, (value) => read(value as Map<String, dynamic>));

Offset _offset(Object? value) {
  final items = value as List;
  return Offset((items[0] as num).toDouble(), (items[1] as num).toDouble());
}

Rect _rect(Object? value) {
  final items = value as List;
  return Rect.fromLTRB(
    (items[0] as num).toDouble(),
    (items[1] as num).toDouble(),
    (items[2] as num).toDouble(),
    (items[3] as num).toDouble(),
  );
}

List<double> _offsetData(Offset point) => [point.dx, point.dy];

List<double> _rectData(Rect rect) => [
  rect.left,
  rect.top,
  rect.right,
  rect.bottom,
];

/// Shared by the renderer and eraser so they agree on the ink footprint.
double inkWidth(InkStroke stroke, double pressure) {
  if (stroke.kind == PenKind.highlighter) return stroke.width;
  final force = pressure.isFinite ? pressure.clamp(0.0, 1.0).toDouble() : 1.0;
  return stroke.width * (0.35 + 0.65 * force);
}

class ShapeEdge {
  const ShapeEdge(this.points, {this.hidden = false});

  final List<Offset> points;
  final bool hidden;
}

bool _isHiddenEdge(ShapeKind kind, int index) => switch (kind) {
  ShapeKind.box => index == 6 || index == 7 || index == 11,
  ShapeKind.pyramid => index == 0 || index == 4,
  ShapeKind.cylinder => index == 2,
  _ => false,
};

bool isShapeEdgeDashed(InkShape shape, int edgeIndex) =>
    (shape.dashed || _isHiddenEdge(shape.kind, edgeIndex)) !=
    shape.dashedEdges.contains(edgeIndex);

List<ShapeEdge> shapeEdges(InkShape shape) {
  final bounds = shape.bounds;
  Offset at(double x, double y) =>
      Offset(bounds.left + x * bounds.width, bounds.top + y * bounds.height);

  List<ShapeEdge> edges(List<List<Offset>> lines) => [
    for (var index = 0; index < lines.length; index++)
      ShapeEdge(lines[index], hidden: _isHiddenEdge(shape.kind, index)),
  ];

  switch (shape.kind) {
    case ShapeKind.line:
      return edges([
        [shape.start, shape.end],
      ]);
    case ShapeKind.arrow:
      final delta = shape.end - shape.start;
      final length = delta.distance;
      if (length == 0) {
        return edges([
          [shape.start, shape.end],
        ]);
      }
      final unit = delta / length;
      final normal = Offset(-unit.dy, unit.dx);
      final headLength = math.min(
        length * 0.32,
        math.max(12.0, shape.width * 5),
      );
      final base = shape.end - unit * headLength;
      return edges([
        [shape.start, shape.end],
        [base - normal * (headLength * 0.46), shape.end],
        [shape.end, base + normal * (headLength * 0.46)],
      ]);
    case ShapeKind.triangle:
      final points = [at(0.5, 0), at(1, 1), at(0, 1)];
      return edges(_polygonEdges(points));
    case ShapeKind.rectangle:
      final points = [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomRight,
        bounds.bottomLeft,
      ];
      return edges(_polygonEdges(points));
    case ShapeKind.circle:
      final radius = math.min(bounds.width, bounds.height) * 0.5;
      final circle = Rect.fromCircle(center: bounds.center, radius: radius);
      return edges([_arc(circle, 0, math.pi * 2, 48)]);
    case ShapeKind.box:
      final front = [at(0, 0.22), at(0.76, 0.22), at(0.76, 1), at(0, 1)];
      final back = [at(0.24, 0), at(1, 0), at(1, 0.78), at(0.24, 0.78)];
      return edges([
        ..._polygonEdges(front),
        ..._polygonEdges(back),
        for (var index = 0; index < front.length; index++)
          [front[index], back[index]],
      ]);
    case ShapeKind.pyramid:
      final base = [at(0.2, 0.62), at(1, 0.62), at(0.8, 1), at(0, 1)];
      final top = at(0.5, 0);
      return edges([
        ..._polygonEdges(base),
        for (final point in base) [top, point],
      ]);
    case ShapeKind.cylinder:
      final lid = Rect.fromPoints(at(0, 0), at(1, 0.28));
      final bottom = Rect.fromPoints(at(0, 0.72), at(1, 1));
      return edges([
        _arc(lid, 0, math.pi * 2, 48),
        _arc(bottom, 0, math.pi, 24),
        _arc(bottom, math.pi, 2 * math.pi, 24),
        [at(0, 0.14), at(0, 0.86)],
        [at(1, 0.14), at(1, 0.86)],
      ]);
  }
}

List<List<Offset>> _polygonEdges(List<Offset> points) => [
  for (var index = 0; index < points.length; index++)
    [points[index], points[(index + 1) % points.length]],
];

List<Offset> _arc(Rect bounds, double from, double to, int steps) => [
  for (var index = 0; index <= steps; index++)
    bounds.center +
        Offset(
          math.cos(from + (to - from) * index / steps) * bounds.width * 0.5,
          math.sin(from + (to - from) * index / steps) * bounds.height * 0.5,
        ),
];

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

double distanceToSegmentSquared(Offset point, Offset start, Offset end) {
  final axis = end - start;
  final lengthSquared = axis.distanceSquared;
  if (lengthSquared == 0) return (point - start).distanceSquared;
  final ratio = (_dot(point - start, axis) / lengthSquared)
      .clamp(0.0, 1.0)
      .toDouble();
  return (point - (start + axis * ratio)).distanceSquared;
}

const _epsilon = 1e-9;
typedef _Interval = ({double start, double end});

final _strokeBounds = Expando<Rect>();

Rect inkStrokeBounds(InkStroke stroke) {
  if (stroke.points.isEmpty) return Rect.zero;
  return _strokeBounds[stroke] ??= _calculateStrokeBounds(stroke);
}

Rect _calculateStrokeBounds(InkStroke stroke) {
  final first = stroke.points.first.position;
  var left = first.dx;
  var right = first.dx;
  var top = first.dy;
  var bottom = first.dy;
  for (final point in stroke.points.skip(1)) {
    left = math.min(left, point.position.dx);
    right = math.max(right, point.position.dx);
    top = math.min(top, point.position.dy);
    bottom = math.max(bottom, point.position.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom).inflate(stroke.width * 0.5);
}

bool _intersects(Rect a, Rect b) =>
    a.left <= b.right &&
    a.right >= b.left &&
    a.top <= b.bottom &&
    a.bottom >= b.top;

/// Cuts the intersections of each ink polyline with the capsule swept from
/// [begin] to [end]. Interpolated endpoints preserve pressure and dash phase.
List<InkStroke> eraseStrokes(
  List<InkStroke> strokes,
  Offset begin,
  Offset end,
  double radius,
) {
  if (radius <= 0 || strokes.isEmpty) return strokes;
  final output = <InkStroke>[];
  var changed = false;
  final sweep = Rect.fromPoints(begin, end).inflate(radius);
  for (final stroke in strokes) {
    if (!_intersects(sweep, inkStrokeBounds(stroke))) {
      output.add(stroke);
      continue;
    }
    final pieces = _eraseStroke(stroke, begin, end, radius, sweep);
    output.addAll(pieces);
    if (pieces.length != 1 || !identical(pieces.single, stroke)) changed = true;
  }
  return changed ? List.unmodifiable(output) : strokes;
}

/// Visible fractions of a segment within a continuous ink dash pattern.
Iterable<({double start, double end})> inkDashSpans(
  double distance,
  double offset,
  double width,
) sync* {
  if (distance <= _epsilon) return;
  final dash = math.max(5.0, width * 3);
  final cycle = dash + math.max(3.0, width * 2);
  var phase = offset % cycle;
  var start = 0.0;
  while (start < distance) {
    final painted = phase < dash;
    final end = math.min(start + (painted ? dash : cycle) - phase, distance);
    if (end <= start) break;
    if (painted) yield (start: start / distance, end: end / distance);
    start = end;
    phase = painted ? dash : 0.0;
  }
}

/// Removes a shape only if the eraser sweeps a rendered part of its outline.
List<InkShape> eraseShapes(
  List<InkShape> shapes,
  Offset begin,
  Offset end,
  double radius,
) {
  if (radius <= 0 || shapes.isEmpty) return shapes;
  final sweep = Rect.fromPoints(begin, end).inflate(radius);
  final kept = <InkShape>[];
  for (final shape in shapes) {
    final allowance = shape.width / 2;
    // An arrowhead may extend outside the bounds indicated by its endpoints.
    final outer = shape.bounds.inflate(
      shape.kind == ShapeKind.arrow
          ? math.max(12.0, shape.width * 5) + allowance
          : allowance,
    );
    if (!_intersects(sweep, outer) ||
        !_erasesShape(shape, begin, end, radius)) {
      kept.add(shape);
    }
  }
  return kept.length == shapes.length ? shapes : List.unmodifiable(kept);
}

bool _erasesShape(InkShape shape, Offset begin, Offset end, double radius) {
  final edges = shapeEdges(shape);
  final threshold = radius + shape.width / 2;
  for (final (edgeIndex, edge) in edges.indexed) {
    final dashed = isShapeEdgeDashed(shape, edgeIndex);
    var length = 0.0;
    for (var index = 1; index < edge.points.length; index++) {
      final start = edge.points[index - 1];
      final delta = edge.points[index] - start;
      final distance = delta.distance;
      if (distance <= _epsilon) continue;
      final removed = _removedIntervals(
        start,
        delta,
        begin,
        end,
        threshold,
        threshold,
      );
      if (removed.isNotEmpty &&
          (!dashed || _hitsDash(removed, distance, length, shape.width))) {
        return true;
      }
      length += distance;
    }
  }
  return false;
}

bool _hitsDash(
  List<_Interval> removed,
  double length,
  double phase,
  double width,
) => inkDashSpans(length, phase, width).any(
  (dash) => removed.any(
    (interval) =>
        math.min(dash.end, interval.end) -
            math.max(dash.start, interval.start) >
        _epsilon,
  ),
);

List<InkStroke> _eraseStroke(
  InkStroke stroke,
  Offset begin,
  Offset end,
  double radius,
  Rect sweep,
) {
  final points = stroke.points;
  if (points.isEmpty) return [stroke];

  bool erasesPoint(InkPoint point) {
    final threshold = radius + inkWidth(stroke, point.pressure) * 0.5;
    return distanceToSegmentSquared(point.position, begin, end) <=
        threshold * threshold;
  }

  if (points.length == 1) return erasesPoint(points.single) ? [] : [stroke];

  final fragments = <InkStroke>[];
  var current = <InkPoint>[];
  var currentPhase = stroke.phase;
  var distance = 0.0;
  var touched = false;
  final candidateArea = sweep.inflate(stroke.width * 0.5);

  void flush() {
    if (current.isEmpty) return;
    fragments.add(stroke.copyWith(points: current, phase: currentPhase));
    current = <InkPoint>[];
  }

  for (var index = 1; index < points.length; index++) {
    final first = points[index - 1];
    final second = points[index];
    final delta = second.position - first.position;
    final length = delta.distance;
    if (length <= _epsilon) {
      if (erasesPoint(first)) {
        touched = true;
        flush();
      } else if (current.isEmpty) {
        current.add(first);
        currentPhase = stroke.phase + distance;
      }
      continue;
    }

    final segment = Rect.fromPoints(first.position, second.position);
    var removed = _intersects(candidateArea, segment)
        ? _removedIntervals(
            first.position,
            delta,
            begin,
            end,
            radius + inkWidth(stroke, first.pressure) * 0.5,
            radius + inkWidth(stroke, second.pressure) * 0.5,
          )
        : const <_Interval>[];
    if (stroke.dashed &&
        removed.isNotEmpty &&
        !_hitsDash(removed, length, stroke.phase + distance, stroke.width)) {
      removed = const [];
    }

    void keep(double start, double end) {
      if (end - start <= _epsilon) return;
      if (current.isEmpty) {
        currentPhase = stroke.phase + distance + length * start;
        current.add(_lerpPoint(first, second, start));
      }
      current.add(_lerpPoint(first, second, end));
    }

    var cursor = 0.0;
    for (final interval in removed) {
      touched = true;
      keep(cursor, interval.start);
      flush();
      cursor = interval.end;
    }
    keep(cursor, 1);
    distance += length;
  }
  if (!touched) return [stroke];
  flush();
  return fragments;
}

InkPoint _lerpPoint(InkPoint a, InkPoint b, double t) {
  if (t == 0) return a;
  if (t == 1) return b;
  return InkPoint(
    a.position + (b.position - a.position) * t,
    a.pressure + (b.pressure - a.pressure) * t,
  );
}

List<_Interval> _removedIntervals(
  Offset point,
  Offset travel,
  Offset begin,
  Offset end,
  double initialRadius,
  double finalRadius,
) {
  final growth = finalRadius - initialRadius;
  List<_Interval> circle(Offset center) {
    final offset = point - center;
    return _quadraticIntervals(
      travel.distanceSquared - growth * growth,
      2 * (_dot(offset, travel) - initialRadius * growth),
      offset.distanceSquared - initialRadius * initialRadius,
    );
  }

  final intervals = circle(begin);
  final sweep = end - begin;
  final length = sweep.distance;
  if (length > _epsilon) {
    intervals.addAll(circle(end));

    final axis = sweep / length;
    final normal = Offset(-axis.dy, axis.dx);
    final delta = point - begin;
    final u = _dot(delta, axis);
    final du = _dot(travel, axis);
    final v = _dot(delta, normal);
    final dv = _dot(travel, normal);
    var start = 0.0;
    var finish = 1.0;

    bool restrict(double slope, double offset) {
      // Keep the part where slope * t + offset <= 0.
      if (slope.abs() < _epsilon) return offset <= 0;
      final boundary = -offset / slope;
      if (slope > 0) {
        finish = math.min(finish, boundary);
      } else {
        start = math.max(start, boundary);
      }
      return finish - start > _epsilon;
    }

    if (restrict(-du, -u) &&
        restrict(du, u - length) &&
        restrict(dv - growth, v - initialRadius) &&
        restrict(-dv - growth, -v - initialRadius)) {
      intervals.add((start: start, end: finish));
    }
  }

  intervals.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Interval>[];
  for (final interval in intervals) {
    if (merged.isEmpty || interval.start > merged.last.end + _epsilon) {
      merged.add(interval);
    } else {
      final last = merged.removeLast();
      merged.add((start: last.start, end: math.max(last.end, interval.end)));
    }
  }
  return merged;
}

List<_Interval> _quadraticIntervals(double a, double b, double c) {
  final breaks = <double>[0, 1];
  void addRoot(double root) {
    if (root > _epsilon && root < 1 - _epsilon) breaks.add(root);
  }

  if (a.abs() < _epsilon) {
    if (b.abs() >= _epsilon) addRoot(-c / b);
  } else {
    final discriminant = b * b - 4 * a * c;
    if (discriminant == 0) {
      addRoot(-b / (2 * a));
    } else if (discriminant > 0) {
      final root = math.sqrt(discriminant);
      // Avoid cancellation in one quadratic root for distant intersections.
      final stable = -0.5 * (b + (b < 0 ? -root : root));
      addRoot(stable / a);
      if (stable != 0) addRoot(c / stable);
    }
  }
  breaks.sort();

  final result = <_Interval>[];
  for (var index = 1; index < breaks.length; index++) {
    final start = breaks[index - 1];
    final end = breaks[index];
    if (end - start <= _epsilon) continue;
    final sample = (start + end) * 0.5;
    if ((a * sample + b) * sample + c <= 0) {
      result.add((start: start, end: end));
    }
  }
  return result;
}
