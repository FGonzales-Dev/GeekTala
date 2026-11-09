import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/models/folder.dart';
import 'package:noote/data/models/folder_tree.dart';

Folder folder(String id, {String? parent, double order = 0}) =>
    Folder(id: id, name: id, parentId: parent, sortOrder: order);

List<String> ids(List<Folder> folders) => [for (final f in folders) f.id];

void main() {
  final tree = FolderTree([
    folder('shared', order: 2),
    folder('specs', parent: 'work', order: 1),
    folder('work', order: 0),
    folder('backend', parent: 'engineering'),
    folder('personal', order: 1),
    folder('engineering', parent: 'work', order: 0),
  ]);

  test('folders are listed in their sort order', () {
    expect(ids(tree.roots), ['work', 'personal', 'shared']);
    expect(ids(tree.childrenOf('work')), ['engineering', 'specs']);
    expect(
      [for (final e in tree.flatten()) '${e.folder.id}:${e.depth}'],
      [
        'work:0',
        'engineering:1',
        'backend:2',
        'specs:1',
        'personal:0',
        'shared:0',
      ],
    );
  });

  test('a folder can move anywhere except into itself', () {
    expect(tree.canMove('engineering', into: 'personal'), isTrue);
    expect(tree.canMove('engineering', into: null), isTrue);
    expect(tree.canMove('work', into: 'work'), isFalse);
    expect(tree.canMove('work', into: 'engineering'), isFalse);
    expect(tree.canMove('work', into: 'backend'), isFalse);
    expect(tree.canMove('engineering', into: 'no-such-folder'), isFalse);
  });

  test('Personal and Shared only move within the top level', () {
    expect(tree.canMove('personal', into: 'work'), isFalse);
    expect(tree.canMove('shared', into: 'engineering'), isFalse);
    expect(tree.canMove('personal', into: null), isTrue);
  });

  test('a folder whose parent is gone is shown at the top level', () {
    final t = FolderTree([folder('a'), folder('orphan', parent: 'deleted')]);
    expect(ids(t.roots), unorderedEquals(['a', 'orphan']));
  });

  test('folders moved into each other on two devices both stay visible', () {
    final t = FolderTree([
      folder('x', parent: 'y'),
      folder('y', parent: 'x'),
      folder('z', parent: 'x'),
      folder('self', parent: 'self'),
    ]);
    expect(ids(t.roots), unorderedEquals(['x', 'y', 'self']));
    expect(ids(t.childrenOf('x')), ['z']);
    // Each shown exactly once.
    expect(t.flatten(), hasLength(4));
  });
}
