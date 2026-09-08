import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../repositories/notes_repository.dart';
import 'database_provider.dart';

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(ref.watch(appDatabaseProvider));
});

final allNotesProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(notesRepositoryProvider).watchAllNotes();
});

final notesInFolderProvider = StreamProvider.family<List<Note>, String?>((
  ref,
  folderId,
) {
  return ref.watch(notesRepositoryProvider).watchNotesInFolder(folderId);
});

final noteByIdProvider = StreamProvider.family<Note?, String>((ref, id) {
  return ref.watch(notesRepositoryProvider).watchNoteById(id);
});

final noteCountsByFolderProvider = StreamProvider<Map<String, int>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNoteCountsByFolder();
});

final deletedNotesProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(notesRepositoryProvider).watchDeletedNotes();
});
