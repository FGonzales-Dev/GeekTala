import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tag.dart';
import '../repositories/tags_repository.dart';
import 'database_provider.dart';

final tagsRepositoryProvider = Provider<TagsRepository>((ref) {
  return TagsRepository(ref.watch(appDatabaseProvider));
});

final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagsRepositoryProvider).watchAllTags();
});
