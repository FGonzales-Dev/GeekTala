import 'package:freezed_annotation/freezed_annotation.dart';

part 'folder.freezed.dart';

@freezed
sealed class Folder with _$Folder {
  const factory Folder({
    required String id,
    required String name,
    String? parentId,
  }) = _Folder;
}
