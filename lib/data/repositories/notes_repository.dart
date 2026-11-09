import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/notes_dao.dart' show NoteWithTags;
import '../models/note.dart';
import '../models/title_style_run.dart';

const _uuid = Uuid();

/// Wraps [NotesDao], exposing the app's [Note] model instead of Drift's
/// generated [NoteRow]. `collaboratorInitials` is hardcoded to `[]` here —
/// there's no `note_shares`/`folder_shares` backing it yet (Build Order
/// step 7 in noote-plan.md).
class NotesRepository {
  NotesRepository(this._db);

  final AppDatabase _db;

  /// Stamped onto every locally-created row for reference only — the
  /// server's `push_changes` (see supabase/migrations/) always uses
  /// `auth.uid()`, so a stale/empty value here can't leak a row to the
  /// wrong owner.
  String get _ownerId => Supabase.instance.client.auth.currentUser?.id ?? '';

  Stream<List<Note>> watchAllNotes() {
    return _db.notesDao.watchAllNotes().map(
          (rows) => rows.map(_toNote).toList(),
        );
  }

  Stream<List<Note>> watchNotesInFolder(String? folderId) {
    return _db.notesDao
        .watchNotesInFolder(folderId)
        .map((rows) => rows.map(_toNote).toList());
  }

  Stream<Note?> watchNoteById(String id) {
    return _db.notesDao.watchNoteById(id).map((row) => row == null ? null : _toNote(row));
  }

  Stream<List<Note>> watchDeletedNotes() {
    return _db.notesDao.watchDeletedNotes().map(
          (rows) => rows.map(_toNote).toList(),
        );
  }

  Future<void> addTag(String noteId, String tagId) =>
      _db.notesDao.addTagToNote(noteId, tagId, _ownerId);

  Future<void> removeTag(String noteId, String tagId) =>
      _db.notesDao.removeTagFromNote(noteId, tagId);

  Stream<Map<String, int>> watchNoteCountsByFolder() =>
      _db.notesDao.watchNoteCountsByFolder();

  Future<String> createNote({
    String? folderId,
    String title = '',
    Map<String, dynamic>? body,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.notesDao.insertNote(
      NotesTableCompanion.insert(
        id: id,
        ownerId: Value(_ownerId),
        folderId: Value(folderId),
        title: Value(title),
        bodyJson: Value(body ?? Document.blank(withInitialText: true).toJson()),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> updateTitle(
    String id,
    String title, {
    List<TitleStyleRun> style = const [],
  }) {
    return _db.notesDao.updateNote(
      id,
      NotesTableCompanion(
        title: Value(title),
        titleStyleJson: Value(style),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateBody(String id, Map<String, dynamic> body) {
    return _db.notesDao.updateNote(
      id,
      NotesTableCompanion(
        bodyJson: Value(body),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNote(String id) => _db.notesDao.softDeleteNote(id);

  /// Moves [ids] into [folderId]. Returns each moved note's previous
  /// folder, for [undoMoveNotes]; notes already in [folderId] are skipped.
  Future<Map<String, String?>> moveNotes(
    Iterable<String> ids,
    String folderId,
  ) {
    return _db.transaction(() async {
      final previous = <String, String?>{};
      for (final row in await _db.notesDao.getNotesByIds(ids)) {
        if (row.folderId == folderId) continue;
        previous[row.id] = row.folderId;
        await _setFolder(row.id, folderId);
      }
      return previous;
    });
  }

  Future<void> undoMoveNotes(Map<String, String?> previous) {
    return _db.transaction(() async {
      for (final MapEntry(key: id, value: folderId) in previous.entries) {
        await _setFolder(id, folderId);
      }
    });
  }

  // A move counts as an edit: sync keeps whichever copy is newer.
  Future<void> _setFolder(String id, String? folderId) {
    return _db.notesDao.updateNote(
      id,
      NotesTableCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Moves several notes to Recently Deleted at once.
  Future<void> deleteNotes(Iterable<String> ids) {
    return _db.transaction(() async {
      for (final id in ids) {
        await _db.notesDao.softDeleteNote(id);
      }
    });
  }

  Future<void> restoreNotes(Iterable<String> ids) {
    return _db.transaction(() async {
      for (final id in ids) {
        await _db.notesDao.restoreNote(id);
      }
    });
  }

  Future<void> restoreNote(String id) => _db.notesDao.restoreNote(id);

  Future<void> permanentlyDeleteNote(String id) =>
      _db.notesDao.permanentlyDeleteNote(id);

  Note _toNote(NoteWithTags row) {
    final note = row.note;
    return Note(
      id: note.id,
      title: note.title,
      titleStyle: note.titleStyleJson,
      folderId: note.folderId,
      body: note.bodyJson,
      tagIds: row.tagIds,
      collaboratorInitials: const [],
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
    );
  }
}
