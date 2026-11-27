import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'assets.dart';
import 'canvas.dart';
import 'model.dart';

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
          size: Size(1200, 800),
          minimumSize: Size(690, 470),
          center: true,
        ),
        () async {
          await windowManager.show();
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: brightness,
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
  final _pens = <PenKind, (Color, double, bool)>{
    PenKind.ballpoint: (_initialInk, 2.8, false),
    PenKind.pencil: (const Color(0xff4b637c), 2.0, false),
    PenKind.highlighter: (const Color(0xffefb531), 15.0, false),
  };

  InkStore? _store;
  Object? _startupError;
  String? _activeId;
  GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();
  Timer? _saveTimer;
  Future<void> _pendingSave = Future<void>.value();
  int _revision = 0;
  int _idSuffix = 0;
  _SaveStatus _status = _SaveStatus.saved;
  Tool _tool = Tool.pen;
  PenKind _pen = PenKind.ballpoint;
  ShapeKind _shape = ShapeKind.line;
  bool _rail = true;
  bool _present = false;
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
    _filter.dispose();
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  void _onFilter() => setState(() {});

  Future<void> _openLibrary() async {
    try {
      final store = await InkStore.open();
      final notes = await store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _notes
          ..clear()
          ..addAll(notes);
        _activeId = _notes.firstOrNull?.id;
        _startupError = null;
      });
      if (_notes.isEmpty) _addNote('Ghi chú mới', 'Sổ học tập');
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

  void _addNote(String title, String notebook) {
    final note = InkNote(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idSuffix++}',
      title: title,
      notebook: notebook,
    );
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
    await _save();
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

  Future<void> _presentation() async {
    final presenting = !_present;
    setState(() {
      _present = presenting;
      _tool = presenting ? Tool.laser : Tool.pen;
    });
    if (Platform.isWindows) {
      try {
        await windowManager.setFullScreen(presenting);
      } catch (_) {
        _toast('Không thể đổi chế độ toàn màn hình.');
      }
    }
  }

  void _setTool(Tool tool) => setState(() => _tool = tool);

  void _setPen(PenKind? pen, {Color? color, double? width, bool? dashed}) {
    setState(() {
      _pen = pen ?? _pen;
      final (oldColor, oldWidth, oldDash) = _pens[_pen]!;
      _pens[_pen] = (color ?? oldColor, width ?? oldWidth, dashed ?? oldDash);
      _tool = Tool.pen;
    });
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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: widget.dark
              ? const Color(0xff151d24)
              : const Color(0xffedf1f4),
          body: SafeArea(
            child: _store == null
                ? _loading()
                : Column(
                    children: [
                      _titleBar(note),
                      if (note != null && !_present) _tools(note),
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: Row(
                          children: [
                            if (_rail && !_present)
                              SizedBox(width: 238, child: _sidebar()),
                            Expanded(
                              child: note == null ? _empty() : _paper(note),
                            ),
                          ],
                        ),
                      ),
                      if (!_present && note != null) _statusBar(note),
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

  Widget _titleBar(InkNote? note) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!_present) ...[
            IconButton(
              onPressed: () => setState(() => _rail = !_rail),
              tooltip: _rail ? 'Ẩn thư viện' : 'Hiện thư viện',
              icon: const Icon(Icons.view_sidebar_outlined, size: 21),
            ),
            const SizedBox(width: 4),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.draw_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Ink Study',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            if (note != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11),
                child: Text('/'),
              ),
            ],
          ],
          Expanded(
            child: Text(
              note?.title ?? 'Thư viện',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_present) ...[
            _toolButton(
              Icons.lens_blur,
              'Laser',
              _tool == Tool.laser,
              () => _setTool(Tool.laser),
            ),
            _toolButton(
              Icons.pan_tool_outlined,
              'Cuộn',
              _tool == Tool.hand,
              () => _setTool(Tool.hand),
            ),
            TextButton.icon(
              onPressed: _presentation,
              icon: const Icon(Icons.fullscreen_exit),
              label: const Text('Thoát'),
            ),
          ] else ...[
            if (note != null) ...[
              IconButton(
                tooltip: 'Trình bày toàn màn hình',
                onPressed: _presentation,
                icon: const Icon(Icons.fullscreen_rounded),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                label: const Text('Xuất PDF'),
              ),
            ],
            IconButton(
              tooltip: widget.dark ? 'Giao diện sáng' : 'Giao diện tối',
              onPressed: widget.onTheme,
              icon: Icon(
                widget.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 19,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
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
                              onSelected: (action) => action == 'rename'
                                  ? _rename(note)
                                  : _delete(note),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Đổi tên'),
                                ),
                                PopupMenuItem(
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

  Widget _tools(InkNote note) {
    final scheme = Theme.of(context).colorScheme;
    final (_, width, dashed) = _pens[_pen]!;
    return Container(
      height: 53,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (final kind in PenKind.values) _penButton(kind),
            const VerticalDivider(width: 14, indent: 5, endIndent: 5),
            _toolButton(
              Icons.auto_fix_normal_outlined,
              'Tẩy một phần',
              _tool == Tool.eraser,
              () => _setTool(Tool.eraser),
            ),
            if (_tool == Tool.eraser)
              SizedBox(
                width: 85,
                child: Slider(
                  min: 6,
                  max: 54,
                  value: _eraserSize,
                  label: _eraserSize.round().toString(),
                  onChanged: (size) => setState(() => _eraserSize = size),
                ),
              ),
            _toolButton(
              Icons.select_all_rounded,
              'Chọn',
              _tool == Tool.select,
              () => _setTool(Tool.select),
            ),
            _toolButton(
              Icons.pan_tool_outlined,
              'Dịch giấy · Space + kéo',
              _tool == Tool.hand,
              () => _setTool(Tool.hand),
            ),
            _toolButton(
              Icons.lens_blur,
              'Laser',
              _tool == Tool.laser,
              () => _setTool(Tool.laser),
            ),
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
                selected: _tool == Tool.shape,
              ),
            ),
            if (_tool == Tool.shape)
              IconButton(
                tooltip: dashed ? 'Dùng nét liền' : 'Dùng nét đứt',
                onPressed: () {
                  final (color, oldWidth, _) = _pens[_pen]!;
                  setState(() => _pens[_pen] = (color, oldWidth, !dashed));
                },
                isSelected: dashed,
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
              ),
            const VerticalDivider(width: 14, indent: 5, endIndent: 5),
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
                const PopupMenuItem(
                  value: 'paste',
                  child: Text('Dán ảnh · Ctrl+V'),
                ),
              ],
              child: _menuLabel(
                Icons.add_circle_outline_rounded,
                'Chèn',
                selected: _tool == Tool.pdfCrop,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Nền giấy',
              onSelected: (value) {
                if (value == 'color') {
                  unawaited(
                    _customColor(note.document.paperColor, (color) {
                      final current = _active;
                      if (current != null && current.id == note.id) {
                        _document(current.document.copyWith(paperColor: color));
                      }
                    }),
                  );
                } else {
                  _document(
                    note.document.copyWith(
                      paper: PaperKind.values.byName(value),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                for (final kind in PaperKind.values)
                  CheckedPopupMenuItem(
                    value: kind.name,
                    checked: note.document.paper == kind,
                    child: Text(_paperLabel(kind)),
                  ),
                const PopupMenuItem(
                  value: 'color',
                  child: Text('Màu nền tùy chỉnh'),
                ),
              ],
              child: _menuLabel(Icons.grid_on_outlined, 'Nền'),
            ),
            const VerticalDivider(width: 14, indent: 5, endIndent: 5),
            IconButton(
              tooltip: 'Hoàn tác · Ctrl+Z',
              onPressed: _history?.undo.isNotEmpty == true ? _undo : null,
              icon: const Icon(Icons.undo_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Làm lại · Ctrl+Y',
              onPressed: _history?.redo.isNotEmpty == true
                  ? () => _undo(redo: true)
                  : null,
              icon: const Icon(Icons.redo_rounded, size: 20),
            ),
            if (_tool == Tool.pen)
              Text(
                '${width.toStringAsFixed(1)} px',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  double _eraserSize = 20;

  Widget _penButton(PenKind kind) {
    final scheme = Theme.of(context).colorScheme;
    final (color, width, dashed) = _pens[kind]!;
    final use = _tool == Tool.pen && _pen == kind;
    final label = switch (kind) {
      PenKind.ballpoint => 'Bút bi',
      PenKind.pencil => 'Bút chì',
      PenKind.highlighter => 'Dạ quang',
    };
    return PopupMenuButton<String>(
      tooltip: '$label · màu và độ dày',
      onOpened: () => _setPen(kind),
      onSelected: (choice) {
        if (choice == 'custom') {
          unawaited(
            _customColor(color, (value) => _setPen(kind, color: value)),
          );
        } else if (choice == 'dash') {
          _setPen(kind, dashed: !dashed);
        } else if (choice.startsWith('width:')) {
          _setPen(kind, width: double.parse(choice.substring(6)));
        } else {
          _setPen(kind, color: _palette[int.parse(choice)]);
        }
      },
      itemBuilder: (_) => [
        for (var index = 0; index < _palette.length; index++)
          PopupMenuItem(
            value: '$index',
            child: Row(
              children: [
                Icon(Icons.circle, color: _palette[index], size: 17),
                const SizedBox(width: 9),
                Text(
                  const [
                    'Xanh đen',
                    'Xanh ngọc',
                    'Xanh lam',
                    'Tím',
                    'Đỏ',
                    'Cam',
                    'Vàng',
                    'Than',
                  ][index],
                ),
                if (_palette[index] == color)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16),
                  ),
              ],
            ),
          ),
        const PopupMenuItem(value: 'custom', child: Text('Màu tùy chỉnh')),
        const PopupMenuDivider(),
        for (final size
            in (kind == PenKind.highlighter
                ? [8, 12, 15, 22, 32]
                : [1, 2, 3, 5, 8, 12]))
          CheckedPopupMenuItem(
            value: 'width:$size',
            checked: size == width,
            child: Text('$size px'),
          ),
        CheckedPopupMenuItem(
          value: 'dash',
          checked: dashed,
          child: const Text('Nét đứt'),
        ),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: use ? scheme.primaryContainer.withValues(alpha: 0.7) : null,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: use
                ? scheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == PenKind.highlighter
                  ? Icons.border_color_rounded
                  : Icons.edit_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _menuLabel(IconData icon, String label, {bool selected = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 5),
            Text(label),
            const Icon(Icons.arrow_drop_down, size: 17),
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

  Widget _statusBar(InkNote note) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, text) = switch (_status) {
      _SaveStatus.saving => (Icons.sync, 'Đang lưu'),
      _SaveStatus.saved => (
        Icons.check_circle_outline_rounded,
        'Đã lưu trên máy',
      ),
      _SaveStatus.failed => (Icons.error_outline_rounded, 'Lưu thất bại'),
    };
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (_status == _SaveStatus.failed)
            TextButton(onPressed: _save, child: const Text('Thử lại')),
          const Spacer(),
          IconButton(
            tooltip: 'Thu nhỏ',
            onPressed: () => _changeZoom(note, note.zoom / 1.18),
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(note.zoom * 100).round()}%',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Phóng to',
            onPressed: () => _changeZoom(note, note.zoom * 1.18),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
          TextButton(
            onPressed: () => _changeZoom(note, 1),
            child: const Text('100%'),
          ),
        ],
      ),
    );
  }

  void _changeZoom(InkNote note, double zoom) =>
      _view(zoom.clamp(0.25, 4.0).toDouble(), note.scroll);

  Widget _paper(InkNote note) {
    final (color, width, dashed) = _pens[_pen]!;
    return Stack(
      fit: StackFit.expand,
      children: [
        InkCanvas(
          key: _canvas,
          document: note.document,
          store: _store!,
          onChange: _document,
          tool: _tool,
          color: color,
          width: _tool == Tool.eraser ? _eraserSize : width,
          penKind: _pen,
          dashed: dashed,
          shapeKind: _shape,
          zoom: note.zoom,
          scroll: note.scroll,
          onViewportChanged: _view,
          onError: _toast,
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
    } else if (_present) {
      unawaited(_presentation());
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
