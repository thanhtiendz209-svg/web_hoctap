import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:super_clipboard/super_clipboard.dart';

import 'model.dart';

class InkStore {
  InkStore._(this._directory);

  final Directory _directory;
  static const _schemaVersion = 1;
  static const _printMargin = 24.0;
  static const _maxRasterSide = 4096;
  static final _assetName = RegExp(r'^[a-z0-9_-]+\.[a-z0-9]+$');
  static final _invalidFilename = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
  static final _random = math.Random.secure();
  static const _pdfType = XTypeGroup(label: 'PDF', extensions: <String>['pdf']);
  static const _imageType = XTypeGroup(
    label: 'Ảnh',
    extensions: <String>['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'],
  );

  int _revision = 0;
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _pdfInitialization;

  static Future<InkStore> open({Directory? directory}) async {
    final Directory target;
    if (directory == null) {
      final support = await getApplicationSupportDirectory();
      target = Directory('${support.path}${Platform.pathSeparator}Ink Study');
    } else {
      target = directory;
    }
    await target.create(recursive: true);
    final store = InkStore._(target);
    await store._assetsDirectory.create(recursive: true);
    return store;
  }

  Directory get _assetsDirectory =>
      Directory('${_directory.path}${Platform.pathSeparator}assets');

  File _snapshotFile(int slot) =>
      File('${_directory.path}${Platform.pathSeparator}notes-$slot.json');

  Future<List<InkNote>> load() async {
    await _writeTail;
    final candidates = <({int revision, List<InkNote> notes})>[];
    var hasSnapshot = false;
    for (var slot = 0; slot < 2; slot++) {
      final snapshot = _snapshotFile(slot);
      if (!await snapshot.exists()) continue;
      hasSnapshot = true;
      try {
        final data = jsonDecode(await snapshot.readAsString()) as Map;
        final revision = data['revision'] as int;
        if (data['version'] != _schemaVersion ||
            revision < 1 ||
            revision % 2 != slot) {
          continue;
        }
        final notes = (data['notes'] as List).map((entry) {
          return InkNote.fromJson(Map<String, dynamic>.from(entry as Map));
        }).toList();
        candidates.add((revision: revision, notes: notes));
      } on FormatException {
        // The previous complete snapshot can still be opened.
      } on TypeError {
        // The previous complete snapshot can still be opened.
      } on ArgumentError {
        // The previous complete snapshot can still be opened.
      }
    }
    if (candidates.isEmpty) {
      if (hasSnapshot) {
        throw const FormatException(
          'Không đọc được dữ liệu đã lưu của Ink Study.',
        );
      }
      return <InkNote>[];
    }
    candidates.sort((a, b) => b.revision.compareTo(a.revision));
    _revision = candidates.first.revision;
    return candidates.first.notes;
  }

  Future<void> save(List<InkNote> notes) {
    final snapshot = notes.map((note) => note.toJson()).toList();
    final next = _writeTail.then((_) async {
      final revision = _revision + 1;
      final slot = _snapshotFile(revision % 2);
      final bytes = utf8.encode(
        jsonEncode(<String, Object>{
          'version': _schemaVersion,
          'revision': revision,
          'notes': snapshot,
        }),
      );
      await _writeAtomically(slot, bytes);
      _revision = revision;
    });
    // A failed write must not prevent later saves in the same session.
    _writeTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<({String asset, List<PdfPageInfo> pages})?> importPdf() async {
    final source = await openFile(acceptedTypeGroups: <XTypeGroup>[_pdfType]);
    if (source == null) return null;
    await _initializePdf();
    final asset = '${_token()}.pdf';
    final target = _assetFile(asset);
    try {
      await File(source.path).copy(target.path);
      final document = await pdfrx.PdfDocument.openFile(target.path);
      try {
        final pages = document.pages.map((page) {
          if (!page.width.isFinite ||
              !page.height.isFinite ||
              page.width <= 0 ||
              page.height <= 0) {
            throw const FormatException('Kích thước trang PDF không hợp lệ.');
          }
          return PdfPageInfo(width: page.width, height: page.height);
        }).toList();
        if (pages.isEmpty) {
          throw const FormatException('PDF không có trang để nhập.');
        }
        return (asset: asset, pages: pages);
      } finally {
        await document.dispose();
      }
    } on Object {
      if (await target.exists()) await target.delete();
      throw const FormatException(
        'Không nhập được PDF. Hãy kiểm tra tệp có bị khóa hoặc bị hỏng.',
      );
    }
  }

  Future<InkImage?> importImage(ui.Rect desiredBounds) async {
    final image = await openFile(acceptedTypeGroups: <XTypeGroup>[_imageType]);
    if (image == null) return null;
    final extension = image.name.split('.').last.toLowerCase();
    return _storeImage(await image.readAsBytes(), extension, desiredBounds);
  }

  Future<InkImage?> pasteImage(ui.Rect desiredBounds) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();
    for (final (format, extension) in <(FileFormat, String)>[
      (Formats.png, 'png'),
      (Formats.jpeg, 'jpg'),
    ]) {
      if (!reader.canProvide(format)) continue;
      final result = Completer<Uint8List>();
      final progress = reader.getFile(format, (file) async {
        try {
          final data = await file.getStream().fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          result.complete(data.takeBytes());
        } on Object catch (error, stack) {
          result.completeError(error, stack);
        }
      }, onError: result.completeError);
      if (progress != null) {
        return _storeImage(await result.future, extension, desiredBounds);
      }
    }
    return null;
  }

  Future<ui.Image> image(String asset) async =>
      _decodeImage(await _assetFile(asset).readAsBytes());

  Future<ui.Image> pdfPage(String asset, int page, int pixelWidth) async {
    await _initializePdf();
    final document = await pdfrx.PdfDocument.openFile(_assetFile(asset).path);
    try {
      final sourcePage = document.pages[page];
      final ratio = sourcePage.height / sourcePage.width;
      final width = math
          .min(
            pixelWidth.clamp(1, _maxRasterSide),
            math.max(1, (_maxRasterSide / ratio).floor()),
          )
          .toInt();
      final height = (width * ratio).round().clamp(1, _maxRasterSide).toInt();
      final raster = await sourcePage.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xffffffff,
      );
      if (raster == null) {
        throw const FormatException('Không hiển thị được trang PDF.');
      }
      try {
        return await raster.createImage();
      } finally {
        raster.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  /// The exact document rectangles that become individual printed pages.
  static List<ui.Rect> pdfSlices(ui.Rect region, {required bool landscape}) {
    if (!region.isFinite || region.isEmpty) return const <ui.Rect>[];
    final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final width = format.width - (2 * _printMargin);
    final height = format.height - (2 * _printMargin);
    final pageHeightInDocument = region.width * height / width;
    final count = math.max(
      1,
      ((region.height / pageHeightInDocument) - 1e-10).ceil(),
    );
    return List<ui.Rect>.generate(count, (index) {
      final top = region.top + pageHeightInDocument * index;
      return ui.Rect.fromLTRB(
        region.left,
        top,
        region.right,
        index == count - 1 ? region.bottom : top + pageHeightInDocument,
      );
    }, growable: false);
  }

  Future<bool> exportPdf(
    InkDocument doc,
    ui.Rect region, {
    required bool landscape,
    required Future<Uint8List> Function(ui.Rect region, double scale) render,
    String suggestedName = 'Ink Study.pdf',
  }) async {
    final slices = pdfSlices(region, landscape: landscape);
    if (slices.isEmpty) {
      throw const FormatException('Vùng xuất PDF không hợp lệ.');
    }
    var name = suggestedName.replaceAll(_invalidFilename, '-').trim();
    if (name.isEmpty) name = 'Ink Study';
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: <XTypeGroup>[_pdfType],
    );
    if (location == null) return false;

    final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final document = pw.Document(title: name, creator: 'Ink Study');
    final width = format.width - (2 * _printMargin);
    final exportScale = math.min(4.0, (width * 3) / region.width);
    for (final slice in slices) {
      final image = pw.MemoryImage(await render(slice, exportScale));
      final height = width * slice.height / slice.width;
      document.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(_printMargin),
          build: (_) => pw.Align(
            alignment: pw.Alignment.topLeft,
            child: pw.Image(
              image,
              width: width,
              height: height,
              fit: pw.BoxFit.fill,
            ),
          ),
        ),
      );
    }
    final path = location.path.toLowerCase().endsWith('.pdf')
        ? location.path
        : '${location.path}.pdf';
    await _writeAtomically(File(path), await document.save());
    return true;
  }

  Future<void> _initializePdf() async {
    try {
      await (_pdfInitialization ??= pdfrx.pdfrxFlutterInitialize());
    } on Object {
      _pdfInitialization = null;
      rethrow;
    }
  }

  File _assetFile(String asset) {
    if (!_assetName.hasMatch(asset)) {
      throw const FormatException('Tên tài nguyên không hợp lệ.');
    }
    return File('${_assetsDirectory.path}${Platform.pathSeparator}$asset');
  }

  Future<InkImage> _storeImage(
    Uint8List bytes,
    String extension,
    ui.Rect desiredBounds,
  ) async {
    final image = await _decodeImage(bytes);
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    final scale = math.min(
      desiredBounds.width / size.width,
      desiredBounds.height / size.height,
    );
    final asset = '${_token()}.$extension';
    await _writeAtomically(_assetFile(asset), bytes);
    return InkImage(
      asset: asset,
      bounds: ui.Rect.fromCenter(
        center: desiredBounds.center,
        width: size.width * scale,
        height: size.height * scale,
      ),
    );
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final maxSide = math.max(descriptor.width, descriptor.height);
        final scale = math.min(1.0, _maxRasterSide / maxSide);
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  static String _token() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}';

  static Future<void> _writeAtomically(File target, List<int> bytes) async {
    final temporary = File('${target.path}.${_token()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
