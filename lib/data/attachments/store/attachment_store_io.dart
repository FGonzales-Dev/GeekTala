import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../attachment_refs.dart';
import '../attachment_remote.dart';

const attachmentsSupported = true;

/// The app's private data folder, `attachments/`.
Future<Directory> defaultAttachmentDirectory() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'attachments'),
);

/// Attachment files on this device, and moving them to and from Supabase
/// Storage.
///
/// A file is written here first (so it shows straight away and works
/// offline), uploaded by [uploadPending] at the start of every sync upload,
/// and downloaded by [ensureLocal] the first time a note on another device
/// needs it.
class AttachmentStore {
  AttachmentStore(
    this._db,
    this._remote, {
    Future<Directory> Function() directory = defaultAttachmentDirectory,
  }) : _directoryOf = directory;

  final AppDatabase _db;
  final AttachmentRemote _remote;
  final Future<Directory> Function() _directoryOf;
  Directory? _directory;
  final _downloads = <String, Future<File?>>{};

  static const _uuid = Uuid();

  /// Longest side, in pixels, a photo is scaled down to.
  static const maxImageSide = 2560;

  Future<Directory> _dir() async {
    final dir = _directory ??= await _directoryOf();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String id) async => File(p.join((await _dir()).path, id));

  /// Adds an image and returns the `attachment://` reference to put in the
  /// note. Photos larger than [maxImageSide] are scaled down. Throws
  /// [AttachmentTooLargeException] past [maxAttachmentBytes].
  Future<String> addImage(Uint8List bytes, {required String fileName}) async {
    var extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    if (!imageExtensions.contains(extension)) {
      extension = imageExtensionOf(bytes) ?? 'png';
    }
    if (extension == 'jpeg') extension = 'jpg';

    var data = bytes;
    if (extension != 'gif') {
      final shrunk = await Isolate.run(() => _shrink(bytes, extension));
      if (shrunk != null) {
        data = shrunk.bytes;
        extension = shrunk.extension;
      }
    }
    if (data.length > maxAttachmentBytes) {
      throw AttachmentTooLargeException(fileName);
    }

    final id = '${_uuid.v4()}.$extension';
    await (await _file(id)).writeAsBytes(data, flush: true);
    await _db.attachmentsDao.upsert(
      AttachmentsTableCompanion.insert(
        id: id,
        originalName: Value(fileName),
        mimeType: mimeTypeFor(extension),
        byteSize: data.length,
        createdAt: DateTime.now(),
      ),
    );
    return attachmentRef(id);
  }

  Future<String> addImageFile(String path) async =>
      addImage(await File(path).readAsBytes(), fileName: p.basename(path));

  /// [ensureLocal]'s file path (what the image block shows).
  Future<String?> ensureLocalPath(String id) async =>
      (await ensureLocal(id))?.path;

  /// Scaled-down copy of an oversized image (orientation applied, as the
  /// re-encoded file has no EXIF), or null if it's small enough / unreadable.
  static ({Uint8List bytes, String extension})? _shrink(
    Uint8List bytes,
    String extension,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final small = math.max(decoded.width, decoded.height) <= maxImageSide;
    // BMP (how Windows pastes images) is uncompressed: always convert.
    if (small && extension == 'bmp') {
      return (bytes: img.encodePng(decoded), extension: 'png');
    }
    if (small) return null;
    final upright = img.bakeOrientation(decoded);
    final landscape = upright.width >= upright.height;
    final resized = img.copyResize(
      upright,
      width: landscape ? maxImageSide : null,
      height: landscape ? null : maxImageSide,
      interpolation: img.Interpolation.average,
    );
    if (extension == 'png' && resized.hasAlpha) {
      return (bytes: img.encodePng(resized), extension: 'png');
    }
    return (bytes: img.encodeJpg(resized, quality: 85), extension: 'jpg');
  }

  /// The file on this device, downloading it first if needed. Null if it
  /// can't be had right now (offline, signed out, or not on the server).
  Future<File?> ensureLocal(String id) {
    // A block body, not `=> remove(id)`: that would return this very
    // future to whenComplete, which would then wait on itself forever.
    return _downloads[id] ??= _ensureLocal(id).whenComplete(() {
      _downloads.remove(id);
    });
  }

  Future<File?> _ensureLocal(String id) async {
    final file = await _file(id);
    if (await file.exists()) return file;
    try {
      final bytes = await _remote.download(id);
      final temp = File('${file.path}.download');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await _db.attachmentsDao.upsert(
        AttachmentsTableCompanion.insert(
          id: id,
          mimeType: mimeTypeFor(p.extension(id).replaceFirst('.', '')),
          byteSize: bytes.length,
          uploaded: const Value(true),
          createdAt: DateTime.now(),
        ),
      );
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Uploads files added on this device. Throws if one fails, so sync
  /// doesn't send notes that point at a file the server doesn't have.
  /// Returns how many were uploaded.
  Future<int> uploadPending() async {
    var count = 0;
    for (final row in await _db.attachmentsDao.notUploaded()) {
      final file = await _file(row.id);
      if (!await file.exists()) {
        await _db.attachmentsDao.deleteIds([row.id]);
        continue;
      }
      await _remote.upload(row.id, await file.readAsBytes(), row.mimeType);
      await _db.attachmentsDao.markUploaded(row.id);
      count++;
    }
    return count;
  }

  /// Deletes files on this device that no note (trashed ones included)
  /// refers to any more — e.g. an image removed from a note. Run when no
  /// note is open in an editor, since an undo could bring an image back.
  /// The server copy stays (a later cleanup).
  ///
  /// Anything added in the last [grace] is kept: its note may not have been
  /// saved yet (the editor saves half a second after the last change).
  Future<int> collectGarbage({
    Duration grace = const Duration(minutes: 10),
  }) async {
    final cutoff = DateTime.now().subtract(grace);
    final used = <String>{
      for (final body in await _db.attachmentsDao.allNoteBodies())
        ...attachmentIdsIn(body),
    };
    final unused = [
      for (final row in await _db.attachmentsDao.all())
        if (!used.contains(row.id) && row.createdAt.isBefore(cutoff)) row.id,
    ];
    final dir = await _dir();
    final strays = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File || used.contains(p.basename(entity.path))) continue;
      if ((await entity.lastModified()).isBefore(cutoff)) strays.add(entity);
    }
    for (final file in strays) {
      await file.delete();
    }
    await _db.attachmentsDao.deleteIds(unused);
    return math.max(unused.length, strays.length);
  }

  /// Another account signed in on this device: forget this one's files.
  Future<void> clearAll() async {
    await _db.attachmentsDao.deleteAll();
    final dir = await _dir();
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }
}
