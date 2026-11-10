/// How a note's body refers to an attachment: an image block whose `url`
/// is `attachment://<id>`, where `<id>` is `<uuid>.<ext>` — the file's name
/// on the device and (under the owner's folder) in Supabase Storage.
const attachmentScheme = 'attachment://';

String attachmentRef(String id) => '$attachmentScheme$id';

bool isAttachmentRef(Object? url) =>
    url is String && url.startsWith(attachmentScheme);

/// The id in an `attachment://` reference, or null.
String? attachmentIdOf(Object? url) {
  if (!isAttachmentRef(url)) return null;
  final id = (url! as String).substring(attachmentScheme.length);
  return _validId.hasMatch(id) ? id : null;
}

final _validId = RegExp(r'^[0-9a-f-]{36}\.[a-z0-9]{1,5}$');

/// Image types that can be added to a note.
const imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

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
  _ => 'application/octet-stream',
};

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
