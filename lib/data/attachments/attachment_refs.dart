/// How a note's body refers to an attachment: an image block — or a file
/// block ([FileBlockKeys]) for anything else, like a PDF — whose `url` is
/// `attachment://<id>`, where `<id>` is `<uuid>.<ext>`: the file's name on
/// the device and (under the owner's folder) in Supabase Storage.
const attachmentScheme = 'attachment://';

/// A file (PDF, recording, …) in a note. Its data carries what's needed to
/// show it before it's downloaded: the name it was added with and its size.
abstract final class FileBlockKeys {
  static const type = 'file';
  static const url = 'url';
  static const name = 'name';

  /// In bytes.
  static const size = 'size';

  /// How a PDF is shown: its first page ([viewPreview], the default) or
  /// just the name card ([viewCard]) — like Apple Notes' "View As".
  static const view = 'view';
  static const viewPreview = 'preview';
  static const viewCard = 'card';
}

String attachmentRef(String id) => '$attachmentScheme$id';

bool isAttachmentRef(Object? url) =>
    url is String && url.startsWith(attachmentScheme);

/// The id in an `attachment://` reference, or null.
String? attachmentIdOf(Object? url) {
  if (!isAttachmentRef(url)) return null;
  final id = (url! as String).substring(attachmentScheme.length);
  return _validId.hasMatch(id) ? id : null;
}

final _validId = RegExp(r'^[0-9a-f-]{36}\.[a-z0-9]{1,8}$');

/// Image types — shown in the note as images rather than as file blocks.
const imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

bool isImageExtension(String extension) =>
    imageExtensions.contains(extension.toLowerCase());

/// The extension an attachment is stored with: from [fileName] if it has a
/// sensible one, otherwise recognised from the first [bytes] (Apple Notes'
/// "New Recording" has no extension), otherwise `bin`.
String fileExtensionFor(String fileName, List<int> bytes) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0) {
    final extension = fileName.substring(dot + 1).toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) {
      return extension == 'jpeg' ? 'jpg' : extension;
    }
  }
  final image = imageExtensionOf(bytes);
  if (image != null) return image;
  bool starts(String magic, [int at = 0]) =>
      bytes.length >= at + magic.length &&
      String.fromCharCodes(bytes.sublist(at, at + magic.length)) == magic;
  if (starts('%PDF')) return 'pdf';
  if (starts('ftyp', 4)) return starts('M4A', 8) ? 'm4a' : 'mp4';
  if (starts('ID3')) return 'mp3';
  if (starts('RIFF') && starts('WAVE', 8)) return 'wav';
  if (starts('PK')) return 'zip';
  return 'bin';
}

/// Supabase's free plan allows 50 MB per file.
const maxAttachmentBytes = 50 * 1024 * 1024;

/// The image type from the first bytes (for pasted images, which have no
/// file name), or null if unrecognised.
String? imageExtensionOf(List<int> bytes) {
  bool starts(List<int> magic) =>
      bytes.length >= magic.length &&
      Iterable.generate(magic.length).every((i) => bytes[i] == magic[i]);
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (starts(const [0x42, 0x4D])) return 'bmp';
  if (bytes.length >= 12 &&
      starts(const [0x52, 0x49, 0x46, 0x46]) &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

String mimeTypeFor(String extension) => switch (extension.toLowerCase()) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  'heic' => 'image/heic',
  'pdf' => 'application/pdf',
  'm4a' => 'audio/mp4',
  'mp3' => 'audio/mpeg',
  'wav' => 'audio/wav',
  'mp4' => 'video/mp4',
  'mov' => 'video/quicktime',
  'txt' => 'text/plain',
  'md' => 'text/markdown',
  'csv' => 'text/csv',
  'json' => 'application/json',
  'zip' => 'application/zip',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  _ => 'application/octet-stream',
};

/// "1.2 MB" — for file blocks.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
}

/// Every attachment id a note body (appflowy document JSON) refers to.
Set<String> attachmentIdsIn(Map<String, dynamic> body) {
  final ids = <String>{};
  void walk(Object? node) {
    if (node is! Map) return;
    final data = node['data'];
    if (data is Map) {
      final id = attachmentIdOf(data['url']);
      if (id != null) ids.add(id);
    }
    final children = node['children'];
    if (children is List) children.forEach(walk);
  }

  walk(body['document']);
  return ids;
}

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException(this.name);

  final String name;

  @override
  String toString() => '"$name" is over 50 MB, too large to add.';
}
