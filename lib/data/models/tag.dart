import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag.freezed.dart';

@freezed
sealed class Tag with _$Tag {
  const factory Tag({required String id, required String name}) = _Tag;
}
