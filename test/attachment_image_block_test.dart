import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noote/core/theme/app_theme.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/attachments_provider.dart';
import 'package:noote/features/note_editor/widgets/attachment_image_block.dart';

import 'support/fake_attachments.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('attachment images show from the device, or a placeholder', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.runAsync(() async {
      final (store, _, dir) = await testAttachmentStore(db);
      addTearDown(() => dir.delete(recursive: true));
      final ref = await store.addImage(
        img.encodePng(img.Image(width: 8, height: 8)),
        fileName: 'dot.png',
      );
      final editorState = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [
              imageNode(url: ref, width: 100),
              imageNode(
                url: 'attachment://0d7a3f7e-9999-4c5e-9f00-000000000009.png',
              ),
              paragraphNode(),
            ],
          ),
      );
      addTearDown(editorState.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [attachmentStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: AppFlowyEditor(
                editorState: editorState,
                blockComponentBuilders: {
                  ...standardBlockComponentBuilderMap,
                  ImageBlockKeys.type: AttachmentImageBlockComponentBuilder(),
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ResizableImage).evaluate().isNotEmpty &&
            find.text('Image not available right now').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.byType(ResizableImage), findsOneWidget);
      expect(find.text('Image not available right now'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
