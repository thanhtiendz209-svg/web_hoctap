import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'assets.dart';
import 'canvas.dart';
import 'model.dart';
import 'tool_shelf.dart';
import 'window_controls.dart';

const _accent = Color(0xff08796e);
const _initialInk = Color(0xff253750);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    unawaited(
      windowManager.waitUntilReadyToShow(
        const WindowOptions(
          title: 'Ink Study',
          size: Size(1040, 680),
          minimumSize: Size(690, 470),
          center: true,
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        ),
        () async {
          await windowManager.show();
          await windowManager.maximize();
          await windowManager.focus();
        },
      ),
    );
  }
  runApp(const InkStudyApp());
}

class InkStudyApp extends StatefulWidget {
  const InkStudyApp({super.key});

  @override
  State<InkStudyApp> createState() => _InkStudyAppState();
}

class _InkStudyAppState extends State<InkStudyApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: _accent,
            brightness: brightness,
          ).copyWith(
            surface: brightness == Brightness.light
                ? const Color(0xfffcfdff)
                : const Color(0xff19232f),
            onSurface: brightness == Brightness.light
                ? const Color(0xff172740)
                : const Color(0xffe8eff7),
            onSurfaceVariant: brightness == Brightness.light
                ? const Color(0xff52647b)
                : const Color(0xffb4c4d5),
            outlineVariant: brightness == Brightness.light
                ? const Color(0xffdce5ee)
                : const Color(0xff354455),
            surfaceContainerLow: brightness == Brightness.light
                ? const Color(0xfff6f8fb)
                : const Color(0xff202c3a),
            surfaceContainerHighest: brightness == Brightness.light
                ? const Color(0xffe8eff6)
                : const Color(0xff2c3b4c),
          ),
      fontFamily: Platform.isWindows ? 'Segoe UI' : null,
      visualDensity: VisualDensity.compact,
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 420),
      ),
    );
    return MaterialApp(
      title: 'Ink Study',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: StudyDesk(
        onTheme: () => setState(() => _dark = !_dark),
        dark: _dark,
      ),
    );
  }
}

enum _SaveStatus { saving, saved, failed }

enum _DeskMode { windowed, writingFullScreen, presentation }

class _History {
  final undo = <InkDocument>[];
  final redo = <InkDocument>[];

  void add(InkDocument previous) {
    undo.add(previous);
    if (undo.length > 80) undo.removeAt(0);
    redo.clear();
  }
}

class StudyDesk extends StatefulWidget {
  const StudyDesk({super.key, required this.onTheme, required this.dark});

  final VoidCallback onTheme;
  final bool dark;

  @override
  State<StudyDesk> createState() => _StudyDeskState();
}

class _StudyDeskState extends State<StudyDesk> with WindowListener {
  final _notes = <InkNote>[];
  final _histories = <String, _History>{};
  final _filter = TextEditingController();
  final _pens = <PenPreset>[
    const PenPreset(color: _initialInk),
    const PenPreset(kind: PenKind.fountain, color: Color(0xff3474cf), width: 6),
    const PenPreset(color: Color(0xffd54260)),
  ];
  final _penScroll = ScrollController();

  InkStore? _store;
  Object? _startupError;
  String? _activeId;
  GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();
  Timer? _saveTimer;
  Timer? _penSaveTimer;
  Future<void> _pendingSave = Future<void>.value();
  int _revision = 0;
  int _idSuffix = 0;
  _SaveStatus _status = _SaveStatus.saved;
  Tool _tool = Tool.pen;
  int _penIndex = 0;
  ShapeKind _shape = ShapeKind.line;
  PenPreset _shapeStyle = const PenPreset(color: _initialInk);
  bool _rail = true;
  _DeskMode _mode = _DeskMode.windowed;
  Tool _beforePresentation = Tool.pen;
  bool _switchingMode = false;
  bool get _present => _mode == _DeskMode.presentation;
  bool _busy = false;
  bool _closing = false;

  static const _palette = [
    _initialInk,
    _accent,
    Color(0xff3474cf),
    Color(0xff9863d4),
    Color(0xffd54260),
    Color(0xffdf7c3d),
    Color(0xffefb531),
    Color(0xff24282c),
  ];

  InkNote? get _active {
    final index = _notes.indexWhere((note) => note.id == _activeId);
    return index < 0 ? null : _notes[index];
  }

  _History? get _history => _histories[_activeId];

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilter);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    unawaited(_openLibrary());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _penSaveTimer?.cancel();
    _penScroll.dispose();
    _filter.dispose();
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  void _onFilter() => setState(() {});

  Future<void> _openLibrary() async {
    try {
      final store = await InkStore.open();
      final notes = await store.load();
      final palette = await store.loadPens();
      if (!mounted) return;
      setState(() {
        _store = store;
        _notes
          ..clear()
          ..addAll(notes);
        _activeId = _notes.firstOrNull?.id;
        if (palette != null) {
          _pens
            ..clear()
            ..addAll(palette.pens);
          _penIndex = palette.active;
        }
        _startupError = null;
      });
      if (_notes.isEmpty) _addNote('Ghi chú mới', 'Sổ học tập');
      _revealActivePen();
    } catch (error) {
      if (mounted) setState(() => _startupError = error);
    }
  }

  void _activate(String id) {
    if (id == _activeId) return;
    _finishRegion(null);
    setState(() {
      _activeId = id;
      _canvas = GlobalKey<InkCanvasState>();
      if (_tool == Tool.pdfCrop) _tool = Tool.pen;
    });
    _scheduleSave();
  }

  String _newNoteId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idSuffix++}';

  void _addNote(String title, String notebook) =>
      _openNewNote(InkNote(id: _newNoteId(), title: title, notebook: notebook));

  void _openNewNote(InkNote note) {
    _finishRegion(null);
    _filter.clear();
    setState(() {
      _notes.insert(0, note);
      _activeId = note.id;
      _canvas = GlobalKey<InkCanvasState>();
      _tool = Tool.pen;
    });
    _scheduleSave();
  }

  void _replaceNote(InkNote note, {bool record = false, bool repaint = true}) {
    final index = _notes.indexWhere((entry) => entry.id == note.id);
    if (index < 0) return;
    if (record) {
      (_histories[note.id] ??= _History()).add(_notes[index].document);
    }
    _notes[index] = note;
    if (repaint) setState(() {});
    _scheduleSave(notify: repaint);
  }

  void _document(InkDocument next) {
    final note = _active;
    if (note != null) _replaceNote(note.copyWith(document: next), record: true);
  }

  void _view(double zoom, double scroll) {
    final note = _active;
    if (note == null || (note.zoom == zoom && note.scroll == scroll)) return;
    // Canvas handles the live transform. Rebuild the title/zoom controls.
    _replaceNote(note.copyWith(zoom: zoom, scroll: scroll));
  }

  void _undo({bool redo = false}) {
    final note = _active;
    final history = _history;
    if (note == null || history == null) return;
    final from = redo ? history.redo : history.undo;
    if (from.isEmpty) return;
    final to = redo ? history.undo : history.redo;
    to.add(note.document);
    _replaceNote(note.copyWith(document: from.removeLast()));
  }

  void _scheduleSave({bool notify = true}) {
    _revision++;
    _saveTimer?.cancel();
    if (_status != _SaveStatus.saving) {
      _status = _SaveStatus.saving;
      if (notify && mounted) setState(() {});
    }
    _saveTimer = Timer(const Duration(milliseconds: 360), _save);
  }

  Future<void> _save() {
    _saveTimer?.cancel();
    final store = _store;
    if (store == null) return Future.value();
    final revision = _revision;
    final snapshot = List<InkNote>.of(_notes);
    final active = snapshot.indexWhere((value) => value.id == _activeId);
    if (active > 0) snapshot.insert(0, snapshot.removeAt(active));
    _pendingSave = _pendingSave.then((_) async {
      try {
        await store.save(snapshot);
        if (mounted && revision == _revision) {
          setState(() => _status = _SaveStatus.saved);
        }
      } catch (error) {
        if (mounted && revision == _revision) {
          setState(() => _status = _SaveStatus.failed);
          _toast('Lưu thất bại. Hãy chọn Thử lại.');
        }
      }
    });
    return _pendingSave;
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await Future.wait([_save(), _savePens()]);
    if (!mounted) return;
    if (_status == _SaveStatus.failed) {
      _closing = false;
      return;
    }
    await windowManager.destroy();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initial.length,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void accept() {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(dialogContext, value);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            controller: controller,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Tên'),
            onSubmitted: (_) => accept(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(onPressed: accept, child: const Text('Xong')),
          ],
        );
      },
    );
    // The dialog may still be animating out when the result completes.
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        controller.dispose,
      ),
    );
    return value;
  }

  Future<void> _newNote([String? notebook]) async {
    final name = await _askName('Tạo ghi chú', 'Ghi chú mới');
    if (mounted && name != null) {
      _filter.clear();
      _addNote(name, notebook ?? _active?.notebook ?? 'Sổ học tập');
    }
  }

  Future<void> _newNotebook() async {
    final name = await _askName('Tạo sổ', '');
    if (!mounted || name == null) return;
    if (_notes.any(
      (note) => note.notebook.toLowerCase() == name.toLowerCase(),
    )) {
      _toast('Tên sổ này đã có trong thư viện.');
      return;
    }
    _filter.clear();
    _addNote('Ghi chú mới', name);
  }

  Future<void> _rename(InkNote note) async {
    final name = await _askName('Đổi tên ghi chú', note.title);
    if (!mounted || name == null) return;
    final index = _notes.indexWhere((entry) => entry.id == note.id);
    if (index >= 0) _replaceNote(_notes[index].copyWith(title: name));
  }

  void _duplicate(InkNote note) {
    _openNewNote(
      note.copyWith(id: _newNoteId(), title: '${note.title} (bản sao)'),
    );
  }

  Future<void> _backup({InkNote? note}) async {
    final store = _store;
    if (_busy || store == null) return;
    setState(() => _busy = true);
    try {
      if (note != null) {
        if (await store.exportNote(note)) _toast('Đã lưu tệp .inkstudy.');
      } else {
        final imported = await store.importNote();
        if (!mounted || imported == null) return;
        _openNewNote(imported);
        await _save();
        if (_status == _SaveStatus.saved) {
          _toast('Đã nhập ghi chú vào thư viện.');
        }
      }
    } catch (error) {
      _toast(
        error is FormatException
            ? error.message
            : note == null
            ? 'Không mở được bản sao lưu. Kiểm tra tệp .inkstudy rồi thử lại.'
            : 'Không lưu được bản sao lưu. Kiểm tra thư mục đích rồi thử lại.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(InkNote note) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text('Ghi chú “${note.title}” sẽ bị xóa khỏi thư viện.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() {
      _notes.removeWhere((value) => value.id == note.id);
      _histories.remove(note.id);
      if (_activeId == note.id) {
        _activeId = _notes.firstOrNull?.id;
        _canvas = GlobalKey<InkCanvasState>();
      }
    });
    _scheduleSave();
  }

  Future<void> _insert({required String action}) async {
    final note = _active;
    final store = _store;
    final canvas = _canvas.currentState;
    if (_busy || note == null || store == null || canvas == null) return;
    setState(() => _busy = true);
    try {
      final view = canvas.visibleBounds;
      final desired = Rect.fromCenter(
        center: view.center,
        width: view.width * 0.64,
        height: view.height * 0.64,
      );
      final pdf = action == 'pdf' ? await store.importPdf() : null;
      final image = switch (action) {
        'image' => await store.importImage(desired),
        'paste' => await store.pasteImage(desired),
        _ => null,
      };
      if (!mounted) return;
      final index = _notes.indexWhere((entry) => entry.id == note.id);
      if (index < 0) return;
      final latest = _notes[index];
      if (pdf != null) {
        _replaceNote(
          latest.copyWith(
            document: latest.document.copyWith(
              pdfAsset: pdf.asset,
              pdfPages: pdf.pages,
              pdfRegions: const [],
            ),
          ),
          record: true,
        );
        _toast('Đã chèn PDF. Chọn Chèn → Chỉnh vùng PDF để kéo giãn một vùng.');
      } else if (image != null) {
        _replaceNote(
          latest.copyWith(
            document: latest.document.copyWith(
              images: [...latest.document.images, image],
            ),
          ),
          record: true,
        );
        if (_activeId == note.id) setState(() => _tool = Tool.select);
      } else if (action == 'paste') {
        _toast('Clipboard chưa có ảnh. Bạn có thể chọn Chèn → Ảnh từ tệp.');
      }
    } catch (error) {
      _toast(
        error is FormatException
            ? error.message
            : 'Không thể chèn nội dung. Kiểm tra tệp rồi thử lại.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final note = _active;
    final store = _store;
    final canvas = _canvas.currentState;
    if (_busy || note == null || store == null || canvas == null) return;
    final choice = await _exportOptions();
    if (!mounted || choice == null || _activeId != note.id) return;
    final (scope, landscape) = choice;
    final region = switch (scope) {
      'visible' => canvas.visibleBounds,
      'select' => await _pickExportRegion(),
      _ => canvas.contentBounds,
    };
    if (!mounted || region == null || _activeId != note.id) return;
    final pages = InkStore.pdfSlices(region, landscape: landscape);
    if (pages.isEmpty) {
      _toast('Chọn một vùng giấy để xuất.');
      return;
    }
    final accept = await _previewExport(canvas, pages, landscape);
    if (!mounted || accept != true || _activeId != note.id) return;
    setState(() => _busy = true);
    try {
      final saved = await store.exportPdf(
        note.document,
        region,
        landscape: landscape,
        render: canvas.render,
        suggestedName:
            '${note.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf',
      );
      if (saved) _toast('Đã xuất PDF.');
    } catch (error) {
      _toast(
        error is FormatException
            ? error.message
            : 'Không thể xuất PDF. Hãy thử lại.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, bool)?> _exportOptions() {
    var scope = 'all';
    var landscape = false;
    return showDialog<(String, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Xuất PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: scope,
                decoration: const InputDecoration(labelText: 'Vùng xuất'),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Toàn bộ nội dung'),
                  ),
                  DropdownMenuItem(
                    value: 'visible',
                    child: Text('Vùng đang xem'),
                  ),
                  DropdownMenuItem(
                    value: 'select',
                    child: Text('Khoanh vùng trên giấy'),
                  ),
                ],
                onChanged: (value) => setDialog(() => scope = value ?? scope),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: landscape,
                decoration: const InputDecoration(labelText: 'Khổ giấy'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('A4 dọc')),
                  DropdownMenuItem(value: true, child: Text('A4 ngang')),
                ],
                onChanged: (value) =>
                    setDialog(() => landscape = value ?? landscape),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (scope, landscape)),
              child: const Text('Xem trước'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _previewExport(
    InkCanvasState canvas,
    List<Rect> pages,
    bool landscape,
  ) {
    final first = canvas.render(pages.first, 0.34);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xem trước PDF'),
        content: SizedBox(
          width: 370,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${pages.length} trang A4 ${landscape ? 'ngang' : 'dọc'}'),
              const SizedBox(height: 14),
              FutureBuilder(
                future: first,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Không thể vẽ trước trang đầu.');
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text('Trang 1'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Lưu PDF'),
          ),
        ],
      ),
    );
  }

  void _applyMode(_DeskMode next) {
    if (!mounted || next == _mode) return;
    setState(() {
      if (_present) _tool = _beforePresentation;
      if (next == _DeskMode.presentation) {
        _beforePresentation = _tool;
        _tool = Tool.laser;
      }
      _mode = next;
    });
  }

  Future<void> _changeMode(_DeskMode next) async {
    if (_switchingMode || next == _mode) return;
    _switchingMode = true;
    try {
      if (Platform.isWindows &&
          (_mode == _DeskMode.windowed || next == _DeskMode.windowed)) {
        await windowManager.setFullScreen(next != _DeskMode.windowed);
      }
      _applyMode(next);
    } catch (_) {
      _toast('Không thể đổi chế độ toàn màn hình.');
    } finally {
      _switchingMode = false;
    }
  }

  @override
  void onWindowLeaveFullScreen() => _applyMode(_DeskMode.windowed);

  void _toggleFullScreen() => unawaited(
    _changeMode(
      _mode == _DeskMode.windowed
          ? _DeskMode.writingFullScreen
          : _DeskMode.windowed,
    ),
  );

  void _setTool(Tool tool) => setState(() => _tool = tool);

  void _choosePen(int index) {
    if (_tool == Tool.pen && _penIndex == index) return;
    setState(() {
      _penIndex = index;
      _tool = Tool.pen;
    });
    _queuePenSave();
  }

  void _updatePen(
    int index, {
    PenKind? kind,
    Color? color,
    double? width,
    bool? dashed,
  }) {
    setState(() {
      _pens[index] = _pens[index].copyWith(
        kind: kind,
        color: color,
        width: width,
        dashed: dashed,
      );
      _penIndex = index;
      _tool = Tool.pen;
    });
    _queuePenSave();
  }

  void _addPen() {
    setState(() {
      _pens.add(PenPreset(color: _palette[_pens.length % _palette.length]));
      _penIndex = _pens.length - 1;
      _tool = Tool.pen;
    });
    _queuePenSave();
    _revealActivePen();
  }

  void _revealActivePen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _penScroll.hasClients) {
        final position = _penScroll.position;
        final left = _penIndex * 34.0;
        final right = left + 34.0;
        final next = position.pixels
            .clamp(right - position.viewportDimension, left)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble();
        if (next != position.pixels) _penScroll.jumpTo(next);
      }
    });
  }

  void _queuePenSave() {
    _penSaveTimer?.cancel();
    _penSaveTimer = Timer(const Duration(milliseconds: 320), _savePens);
  }

  Future<void> _savePens() async {
    _penSaveTimer?.cancel();
    try {
      await _store?.savePens(_pens, _penIndex);
    } catch (_) {
      _toast('Không thể lưu bộ bút. Hãy kiểm tra dung lượng ổ đĩa.');
    }
  }

  Future<void> _customColor(Color current, ValueChanged<Color> onColor) async {
    final hex = current
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2);
    final value = await _askName(
      'Màu tùy chỉnh · mã HEX',
      '#${hex.toUpperCase()}',
    );
    if (value == null || !mounted) return;
    final clean = value.replaceFirst('#', '');
    final rgb = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
    if (rgb == null) {
      _toast('Dùng 6 ký tự HEX, ví dụ #08796E.');
      return;
    }
    onColor(Color(0xff000000 | rgb));
  }

  bool get _typing {
    final node = FocusManager.instance.primaryFocus?.context;
    return node?.widget is EditableText ||
        node?.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final note = _active;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (!_typing && _store != null) unawaited(_newNote());
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (!_typing) unawaited(_insert(action: 'paste'));
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (!_typing) _undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (!_typing) _undo(redo: true);
        },
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () {
          if (!_typing) _undo(redo: true);
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (!_typing) _canvas.currentState?.deleteSelection();
        },
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: widget.dark
              ? const Color(0xff141f2b)
              : const Color(0xffedf2f7),
          body: SafeArea(
            child: Column(
              children: [
                if (!_present) _tools(note),
                if (_store == null)
                  Expanded(child: _loading())
                else ...[
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: Row(
                      children: [
                        if (_rail && _mode == _DeskMode.windowed)
                          SizedBox(width: 238, child: _sidebar()),
                        Expanded(child: note == null ? _empty() : _paper(note)),
                      ],
                    ),
                  ),
                  _statusBar(note),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() => Center(
    child: _startupError == null
        ? const CircularProgressIndicator()
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 38),
              const SizedBox(height: 14),
              const Text('Không thể mở thư viện ghi chú.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openLibrary,
                child: const Text('Thử lại'),
              ),
            ],
          ),
  );

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.edit_note_rounded, size: 50),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _newNote,
          icon: const Icon(Icons.add),
          label: const Text('Tạo ghi chú'),
        ),
      ],
    ),
  );

  Widget _sidebar() {
    final scheme = Theme.of(context).colorScheme;
    final filter = _filter.text.trim().toLowerCase();
    final grouped = <String, List<InkNote>>{};
    for (final note in _notes) {
      if (filter.isEmpty ||
          note.title.toLowerCase().contains(filter) ||
          note.notebook.toLowerCase().contains(filter)) {
        (grouped[note.notebook] ??= []).add(note);
      }
    }
    return Material(
      color: scheme.surfaceContainerLow,
      shape: Border(right: BorderSide(color: scheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 10, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Thư viện',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: 'Tạo sổ',
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  onPressed: _newNotebook,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Tìm ghi chú',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: FilledButton.icon(
              onPressed: _newNote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ghi chú mới'),
            ),
          ),
          Expanded(
            child: grouped.isEmpty
                ? Center(
                    child: Text(
                      filter.isEmpty
                          ? 'Chưa có ghi chú'
                          : 'Không tìm thấy ghi chú',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 12),
                    children: [
                      for (final group in grouped.entries) ...[
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.folder_open_outlined,
                            size: 17,
                            color: scheme.primary,
                          ),
                          title: Text(
                            group.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          trailing: IconButton(
                            tooltip: 'Thêm ghi chú vào sổ',
                            icon: const Icon(Icons.add, size: 17),
                            onPressed: () => _newNote(group.key),
                          ),
                          contentPadding: const EdgeInsets.only(left: 9),
                          minLeadingWidth: 12,
                        ),
                        for (final note in group.value)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            onTap: () => _activate(note.id),
                            selected: note.id == _activeId,
                            selectedTileColor: scheme.primaryContainer
                                .withValues(alpha: 0.65),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                            leading: const Icon(
                              Icons.article_outlined,
                              size: 16,
                            ),
                            minLeadingWidth: 12,
                            contentPadding: const EdgeInsets.only(left: 15),
                            title: Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Tùy chọn ghi chú',
                              onSelected: (action) {
                                switch (action) {
                                  case 'rename':
                                    unawaited(_rename(note));
                                  case 'duplicate':
                                    _duplicate(note);
                                  case 'backup':
                                    unawaited(_backup(note: note));
                                  case 'delete':
                                    unawaited(_delete(note));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Đổi tên'),
                                ),
                                const PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Nhân bản ghi chú'),
                                ),
                                PopupMenuItem(
                                  value: 'backup',
                                  enabled: !_busy,
                                  child: const Text('Sao lưu ghi chú'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Xóa'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tools(InkNote? note) {
    final scheme = Theme.of(context).colorScheme;
    final windowed = _mode == _DeskMode.windowed;
    final caption = windowed && defaultTargetPlatform == TargetPlatform.windows;
    final canToggleSidebar = windowed && _store != null;
    if (note == null && !caption && !canToggleSidebar) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 46,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the caption buttons and a draggable strip outside the
            // scrolling tools so they're available even at minimum width.
            final reserved =
                (caption ? 154.0 : 0) + (canToggleSidebar ? 35.0 : 0);
            final toolWidth = (constraints.maxWidth - reserved)
                .clamp(0.0, double.infinity)
                .toDouble();
            final showLabels = toolWidth >= 760;
            final compact = toolWidth < 615;
            return Row(
              children: [
                if (canToggleSidebar)
                  _shelfIcon(
                    IconButton(
                      onPressed: () => setState(() => _rail = !_rail),
                      tooltip: _rail ? 'Ẩn thư viện' : 'Hiện thư viện',
                      icon: const Icon(Icons.view_sidebar_outlined, size: 19),
                    ),
                  ),
                if (note != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: toolWidth),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 2 : 7,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          _penStrip(note, compact: compact),
                          _shelfDivider(),
                          _eraserButton(compact: compact),
                          if (compact)
                            _shelfIcon(
                              _toolButton(
                                Icons.crop_free_rounded,
                                'Chọn vùng · Shift + kéo để chọn nhanh',
                                _tool == Tool.select,
                                () => _setTool(Tool.select),
                              ),
                            )
                          else
                            _shelfAction(
                              Icons.crop_free_rounded,
                              'Chọn vùng',
                              'Chọn vùng · Shift + kéo để chọn nhanh',
                              _tool == Tool.select,
                              () => _setTool(Tool.select),
                            ),
                          _shelfIcon(
                            _toolButton(
                              Icons.lens_blur,
                              'Laser',
                              _tool == Tool.laser,
                              () => _setTool(Tool.laser),
                            ),
                          ),
                          _shelfDivider(),
                          ..._shelfActions(note, showLabels: showLabels),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: caption
                      ? const DragToMoveArea(
                          child: SizedBox.expand(
                            key: ValueKey('window-drag-area'),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (caption) const InkWindowControls(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _shelfDivider() => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );

  static const _inkNames = [
    'Xanh đen',
    'Xanh ngọc',
    'Xanh lam',
    'Tím',
    'Đỏ',
    'Cam',
    'Vàng',
    'Than',
  ];

  double _eraserSize = defaultEraserWidth;

  Widget _penStrip(InkNote note, {required bool compact}) => Row(
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 102 : 204),
        child: Scrollbar(
          controller: _penScroll,
          child: SingleChildScrollView(
            controller: _penScroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < _pens.length; index++)
                  _penButton(note, index),
              ],
            ),
          ),
        ),
      ),
      _shelfIcon(
        IconButton(
          tooltip: 'Thêm bút',
          icon: const Icon(Icons.add_rounded, size: 19),
          onPressed: _addPen,
        ),
      ),
    ],
  );

  Widget _penButton(InkNote note, int index) {
    final scheme = Theme.of(context).colorScheme;
    final pen = _pens[index];
    final selected = _tool == Tool.pen && _penIndex == index;
    return ToolOptionsMenu(
      key: ValueKey('pen-$index'),
      label: 'Bút ${index + 1}',
      selected: selected,
      onOpen: () => _choosePen(index),
      trigger: SizedBox(
        width: 34,
        height: 36,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pen.color,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
          ),
        ),
      ),
      panel: PenOptionsPanel(
        preset: pen,
        colors: _palette,
        colorNames: _inkNames,
        paperColor: note.document.paperColor,
        onChange: (kind, {color, width, dashed}) => _updatePen(
          index,
          kind: kind,
          color: color,
          width: width,
          dashed: dashed,
        ),
        onCustomColor: (_, current) => unawaited(
          _customColor(current, (value) => _updatePen(index, color: value)),
        ),
      ),
    );
  }

  Widget _eraserButton({required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    return _shelfSplitTool(
      label: 'Gôm',
      tooltip: 'Tẩy một phần nét',
      selected: _tool == Tool.eraser,
      showLabel: !compact,
      compact: compact,
      preview: ToolNibPreview(color: scheme.primary, outline: scheme.onSurface),
      onPressed: () => _setTool(Tool.eraser),
      options: ToolOptionsMenu(
        label: 'Độ rộng gôm',
        panel: EraserOptionsPanel(
          width: _eraserSize,
          onChanged: (value) => setState(() {
            _eraserSize = value;
            _tool = Tool.eraser;
          }),
        ),
      ),
    );
  }

  Widget _shelfSplitTool({
    required String label,
    required String tooltip,
    required bool selected,
    required bool showLabel,
    required bool compact,
    required Widget preview,
    required VoidCallback onPressed,
    required Widget options,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: 0.52)
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: tooltip,
              child: Semantics(
                button: true,
                selected: selected,
                child: InkWell(
                  onTap: onPressed,
                  child: Padding(
                    padding: compact
                        ? EdgeInsets.zero
                        : const EdgeInsets.only(left: 5, right: 4),
                    child: SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          preview,
                          if (showLabel)
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            options,
          ],
        ),
      ),
    );
  }

  Widget _shelfAction(
    IconData icon,
    String label,
    String tooltip,
    bool selected,
    VoidCallback action,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        selected: selected,
        child: TextButton.icon(
          onPressed: action,
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurface,
            backgroundColor: selected ? scheme.primaryContainer : null,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  void _updateShapeStyle({Color? color, double? width, bool? dashed}) {
    setState(
      () => _shapeStyle = PenPreset(
        color: color ?? _shapeStyle.color,
        width: width ?? _shapeStyle.width,
        dashed: dashed ?? _shapeStyle.dashed,
      ),
    );
  }

  List<Widget> _shelfActions(InkNote note, {required bool showLabels}) {
    return [
      if (showLabels) ...[
        _shelfIcon(
          _toolButton(
            Icons.pan_tool_outlined,
            'Dịch giấy · Space + kéo',
            _tool == Tool.hand,
            () => _setTool(Tool.hand),
          ),
        ),
      ],
      PopupMenuButton<ShapeKind>(
        tooltip: 'Hình học',
        initialValue: _shape,
        onSelected: (shape) => setState(() {
          _shape = shape;
          _tool = Tool.shape;
        }),
        itemBuilder: (_) => [
          for (final shape in ShapeKind.values)
            PopupMenuItem(value: shape, child: Text(_shapeLabel(shape))),
        ],
        child: _menuLabel(
          Icons.category_outlined,
          'Hình',
          showLabel: showLabels,
          selected: _tool == Tool.shape,
        ),
      ),
      if (_tool == Tool.shape)
        ToolOptionsMenu(
          label: 'Kiểu nét hình',
          icon: Icons.tune_rounded,
          compact: false,
          panel: PenOptionsPanel(
            preset: _shapeStyle,
            colors: _palette,
            colorNames: _inkNames,
            paperColor: note.document.paperColor,
            onChange: (_, {color, width, dashed}) =>
                _updateShapeStyle(color: color, width: width, dashed: dashed),
            onCustomColor: (_, current) => unawaited(
              _customColor(current, (value) => _updateShapeStyle(color: value)),
            ),
            forShape: true,
          ),
        ),
      _shelfDivider(),
      PopupMenuButton<String>(
        tooltip: 'Chèn',
        enabled: !_busy,
        onSelected: (action) {
          if (action == 'crop') {
            _setTool(Tool.pdfCrop);
            return;
          }
          if (action == 'remove') {
            _document(
              note.document.copyWith(
                pdfAsset: null,
                pdfPages: const [],
                pdfRegions: const [],
              ),
            );
            if (_tool == Tool.pdfCrop) _setTool(Tool.pen);
            return;
          }
          unawaited(_insert(action: action));
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'pdf', child: Text('PDF làm nền')),
          PopupMenuItem(
            value: 'crop',
            enabled: note.document.pdfAsset != null,
            child: const Text('Chỉnh vùng PDF'),
          ),
          PopupMenuItem(
            value: 'remove',
            enabled: note.document.pdfAsset != null,
            child: const Text('Bỏ nền PDF'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'image', child: Text('Ảnh từ tệp')),
          const PopupMenuItem(value: 'paste', child: Text('Dán ảnh · Ctrl+V')),
        ],
        child: _menuLabel(
          Icons.add_circle_outline_rounded,
          'Chèn',
          showLabel: showLabels,
          selected: _tool == Tool.pdfCrop,
        ),
      ),
      PopupMenuButton<String>(
        tooltip: showLabels ? 'Nền giấy' : 'Nền giấy và công cụ khác',
        onSelected: (value) {
          switch (value) {
            case 'hand':
              _setTool(Tool.hand);
            case 'color':
              unawaited(
                _customColor(note.document.paperColor, (color) {
                  final current = _active;
                  if (current != null && current.id == note.id) {
                    _document(current.document.copyWith(paperColor: color));
                  }
                }),
              );
            default:
              _document(
                note.document.copyWith(paper: PaperKind.values.byName(value)),
              );
          }
        },
        itemBuilder: (_) => [
          if (!showLabels) ...[
            const PopupMenuItem(value: 'hand', child: Text('Dịch giấy')),
            const PopupMenuDivider(),
          ],
          for (final kind in PaperKind.values)
            CheckedPopupMenuItem(
              value: kind.name,
              checked: note.document.paper == kind,
              child: Text(_paperLabel(kind)),
            ),
          const PopupMenuItem(value: 'color', child: Text('Màu nền tùy chỉnh')),
        ],
        child: _menuLabel(
          showLabels ? Icons.grid_on_outlined : Icons.more_horiz_rounded,
          'Nền',
          showLabel: showLabels,
          selected: !showLabels && _tool == Tool.hand,
        ),
      ),
      _shelfDivider(),
      _shelfIcon(
        IconButton(
          tooltip: 'Hoàn tác · Ctrl+Z',
          onPressed: _history?.undo.isNotEmpty == true ? _undo : null,
          icon: const Icon(Icons.undo_rounded, size: 19),
        ),
      ),
      _shelfIcon(
        IconButton(
          tooltip: 'Làm lại · Ctrl+Y',
          onPressed: _history?.redo.isNotEmpty == true
              ? () => _undo(redo: true)
              : null,
          icon: const Icon(Icons.redo_rounded, size: 19),
        ),
      ),
    ];
  }

  Widget _shelfIcon(Widget button) =>
      SizedBox(width: 35, height: 36, child: button);

  Widget _menuLabel(
    IconData icon,
    String label, {
    required bool showLabel,
    bool selected = false,
  }) => Container(
    height: 36,
    padding: EdgeInsets.symmetric(horizontal: showLabel ? 7 : 5),
    decoration: BoxDecoration(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(label),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 13),
        ],
      ],
    ),
  );

  Widget _toolButton(
    IconData icon,
    String tooltip,
    bool selected,
    VoidCallback action,
  ) => IconButton(
    icon: Icon(icon, size: 20),
    onPressed: action,
    tooltip: tooltip,
    isSelected: selected,
    style: selected
        ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          )
        : null,
  );

  Widget _statusBar(InkNote? note) {
    final scheme = Theme.of(context).colorScheme;
    final windowed = _mode == _DeskMode.windowed;
    final (statusIcon, statusLabel) = switch (_status) {
      _SaveStatus.saving => (Icons.sync, 'Đang lưu'),
      _SaveStatus.saved => (
        Icons.check_circle_outline_rounded,
        'Đã lưu trên máy',
      ),
      _SaveStatus.failed => (Icons.error_outline_rounded, 'Lưu thất bại'),
    };
    Widget action(IconData icon, String tooltip, VoidCallback? onPressed) =>
        _shelfIcon(
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
          ),
        );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: note == null
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      if (!_present) ...[
                        if (_status == _SaveStatus.failed)
                          action(statusIcon, '$statusLabel · Thử lại', _save)
                        else
                          Tooltip(
                            message: statusLabel,
                            child: Icon(
                              statusIcon,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Tooltip(
                          message: note.title,
                          child: Text(
                            note.title,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_present) ...[
            _shelfIcon(
              _toolButton(
                Icons.lens_blur,
                'Laser',
                _tool == Tool.laser,
                () => _setTool(Tool.laser),
              ),
            ),
            _shelfIcon(
              _toolButton(
                Icons.pan_tool_outlined,
                'Cuộn',
                _tool == Tool.hand,
                () => _setTool(Tool.hand),
              ),
            ),
            action(
              Icons.fullscreen_exit_rounded,
              'Thoát trình bày (Esc)',
              () => _changeMode(_DeskMode.windowed),
            ),
          ] else ...[
            if (_store != null)
              _shelfIcon(
                PopupMenuButton<String>(
                  tooltip: 'Sao lưu và nhập ghi chú',
                  enabled: !_busy,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  onSelected: (action) => unawaited(
                    _backup(note: action == 'export' ? note : null),
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'export',
                      enabled: note != null,
                      child: const Text('Sao lưu ghi chú (.inkstudy)'),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Nhập ghi chú (.inkstudy)'),
                    ),
                  ],
                ),
              ),
            if (note != null) ...[
              action(
                Icons.remove_rounded,
                'Thu nhỏ',
                () => _changeZoom(note, note.zoom / 1.18),
              ),
              SizedBox(
                width: 43,
                child: Text(
                  '${(note.zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              action(
                Icons.add_rounded,
                'Phóng to',
                () => _changeZoom(note, note.zoom * 1.18),
              ),
              action(
                Icons.fit_screen_outlined,
                'Vừa chiều rộng',
                () => _canvas.currentState?.fitWidth(),
              ),
              _shelfDivider(),
              action(
                Icons.picture_as_pdf_outlined,
                'Xuất PDF',
                _busy ? null : _export,
              ),
              action(
                Icons.slideshow_rounded,
                'Trình bày với laser',
                () => _changeMode(_DeskMode.presentation),
              ),
              action(
                windowed
                    ? Icons.fullscreen_rounded
                    : Icons.fullscreen_exit_rounded,
                windowed
                    ? 'Viết toàn màn hình (F11)'
                    : 'Thoát toàn màn hình (F11)',
                _toggleFullScreen,
              ),
            ],
            action(
              widget.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              widget.dark ? 'Giao diện sáng' : 'Giao diện tối',
              widget.onTheme,
            ),
          ],
        ],
      ),
    );
  }

  void _changeZoom(InkNote note, double zoom) =>
      _view(zoom.clamp(0.25, 4.0).toDouble(), note.scroll);

  Widget _paper(InkNote note) {
    final style = _tool == Tool.shape ? _shapeStyle : _pens[_penIndex];
    return Stack(
      fit: StackFit.expand,
      children: [
        InkCanvas(
          key: _canvas,
          documentScope: note.id,
          document: note.document,
          store: _store!,
          onChange: _document,
          tool: _tool,
          color: style.color,
          width: style.width,
          eraserWidth: _eraserSize,
          penKind: style.kind,
          dashed: style.dashed,
          shapeKind: _shape,
          zoom: note.zoom,
          scroll: note.scroll,
          onViewportChanged: _view,
          onError: _toast,
          onQuickSelect: () => _setTool(Tool.select),
        ),
        if (_tool == Tool.pdfCrop && _exportSelection == null)
          Positioned(
            left: 12,
            top: 12,
            child: Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 3, 3, 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Kéo khung trong một trang PDF'),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => _setTool(Tool.select),
                      child: const Text('Xong'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_exportSelection != null) _regionOverlay(),
      ],
    );
  }

  Completer<Rect?>? _exportSelection;
  Offset? _regionStart;
  Offset? _regionEnd;

  Future<Rect?> _pickExportRegion() {
    final completer = Completer<Rect?>();
    setState(() {
      _regionStart = null;
      _regionEnd = null;
      _exportSelection = completer;
    });
    return completer.future;
  }

  void _finishRegion(Rect? region) {
    final completer = _exportSelection;
    if (completer == null) return;
    setState(() => _exportSelection = null);
    completer.complete(region);
  }

  void _escape() {
    if (_exportSelection != null) {
      _finishRegion(null);
    } else if (_mode != _DeskMode.windowed) {
      _canvas.currentState?.cancelGesture();
      unawaited(_changeMode(_DeskMode.windowed));
    } else {
      _canvas.currentState?.cancelGesture();
      _setTool(Tool.select);
    }
  }

  Widget _regionOverlay() => Stack(
    fit: StackFit.expand,
    children: [
      MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => setState(() {
            _regionStart = details.localPosition;
            _regionEnd = details.localPosition;
          }),
          onPanUpdate: (details) =>
              setState(() => _regionEnd = details.localPosition),
          onPanEnd: (_) {
            final canvas = _canvas.currentState;
            final start = _regionStart;
            final end = _regionEnd;
            if (canvas == null || start == null || end == null) return;
            final region = Rect.fromPoints(
              canvas.documentPoint(start),
              canvas.documentPoint(end),
            );
            if (region.width >= 8 && region.height >= 8) _finishRegion(region);
          },
          child: CustomPaint(
            painter: _ExportSelectionPainter(_regionStart, _regionEnd),
          ),
        ),
      ),
      Positioned(
        top: 12,
        left: 12,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Kéo để chọn vùng xuất PDF'),
                TextButton(
                  onPressed: () => _finishRegion(null),
                  child: const Text('Hủy'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _ExportSelectionPainter extends CustomPainter {
  const _ExportSelectionPainter(this.start, this.end);
  final Offset? start;
  final Offset? end;

  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    final selected = Rect.fromPoints(start!, end!);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(selected),
      Paint()..color = const Color(0x441e2938),
    );
    canvas.drawRect(
      selected,
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ExportSelectionPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
}

String _shapeLabel(ShapeKind shape) => switch (shape) {
  ShapeKind.line => 'Đoạn thẳng',
  ShapeKind.arrow => 'Mũi tên',
  ShapeKind.triangle => 'Tam giác',
  ShapeKind.rectangle => 'Hình chữ nhật',
  ShapeKind.circle => 'Đường tròn',
  ShapeKind.box => 'Hình hộp',
  ShapeKind.pyramid => 'Hình chóp',
  ShapeKind.cylinder => 'Hình trụ',
};

String _paperLabel(PaperKind paper) => switch (paper) {
  PaperKind.blank => 'Giấy trơn',
  PaperKind.ruled => 'Kẻ ngang',
  PaperKind.grid => 'Ô ly',
  PaperKind.dots => 'Chấm',
};
