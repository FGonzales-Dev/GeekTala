import 'folder.dart';

/// The folder hierarchy as the app shows it, with the rules for moving
/// folders around in it.
///
/// A folder whose parent is missing (e.g. deleted on another device), or
/// that is part of a parent loop (two devices moved folders into each
/// other before syncing), is shown at the top level instead of vanishing
/// from the tree along with its notes.
class FolderTree {
  FolderTree(List<Folder> folders) {
    final byId = {for (final f in folders) f.id: f};

    bool inLoop(Folder folder) {
      final seen = <String>{};
      for (var p = folder.parentId; p != null; p = byId[p]?.parentId) {
        if (p == folder.id) return true;
        // A loop further up that this folder isn't part of.
        if (!seen.add(p)) return false;
      }
      return false;
    }

    for (final folder in folders) {
      final parent = folder.parentId;
      final shownUnder =
          parent != null && byId.containsKey(parent) && !inLoop(folder)
          ? parent
          : null;
      _parentOf[folder.id] = shownUnder;
      (_children[shownUnder] ??= []).add(folder);
    }
    for (final list in _children.values) {
      list.sort(_compare);
    }
    _byId.addAll(byId);
  }

  final _byId = <String, Folder>{};
  final _parentOf = <String, String?>{};
  final _children = <String?, List<Folder>>{};

  static int _compare(Folder a, Folder b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }

  static bool isProtected(String id) => protectedFolderIds.contains(id);

  bool get isEmpty => _byId.isEmpty;

  Folder? operator [](String id) => _byId[id];

  bool contains(String id) => _byId.containsKey(id);

  List<Folder> get roots => childrenOf(null);

  /// In display order. [id] null means the top level.
  List<Folder> childrenOf(String? id) => _children[id] ?? const [];

  /// The folder [id] is shown under (null = top level).
  String? parentOf(String id) => _parentOf[id];

  /// Whether [id] is [ancestorId] or somewhere inside it.
  bool isSameOrInside(String id, String ancestorId) {
    for (String? f = id; f != null; f = _parentOf[f]) {
      if (f == ancestorId) return true;
    }
    return false;
  }

  /// Whether folder [id] may be moved into [into] (null = top level).
  /// Not into itself or anything inside it; Personal and Shared stay at
  /// the top level.
  bool canMove(String id, {required String? into}) {
    if (!contains(id)) return false;
    if (into == null) return true;
    if (!contains(into) || isProtected(id)) return false;
    return !isSameOrInside(into, id);
  }

  /// Every folder in display order (depth-first), with its depth.
  List<({Folder folder, int depth})> flatten() {
    final result = <({Folder folder, int depth})>[];
    void visit(String? parent, int depth) {
      for (final folder in childrenOf(parent)) {
        result.add((folder: folder, depth: depth));
        visit(folder.id, depth + 1);
      }
    }

    visit(null, 0);
    return result;
  }
}
