import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../models/folder_tree.dart';
import '../repositories/folders_repository.dart';
import 'database_provider.dart';

final foldersRepositoryProvider = Provider<FoldersRepository>((ref) {
  return FoldersRepository(ref.watch(appDatabaseProvider));
});

final allFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(foldersRepositoryProvider).watchAllFolders();
});

/// [allFoldersProvider] as the tree the sidebar and pickers show.
final folderTreeProvider = Provider<FolderTree>((ref) {
  return FolderTree(ref.watch(allFoldersProvider).value ?? const []);
});
