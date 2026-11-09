import 'package:freezed_annotation/freezed_annotation.dart';

part 'folder.freezed.dart';

/// Personal and Shared always exist, can't be deleted, and stay at the top
/// level (they can be reordered there, not moved into another folder).
const protectedFolderIds = {'personal', 'shared'};

@freezed
sealed class Folder with _$Folder {
  const factory Folder({
    required String id,
    required String name,
    String? parentId,
    @Default(0.0) double sortOrder,
  }) = _Folder;
}
