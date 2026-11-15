
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/core/theme/app_theme.dart';
import 'package:noote/data/attachments/attachment_refs.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/attachments_provider.dart';
import 'package:noote/features/note_editor/insert_attachments.dart';
import 'package:noote/features/note_editor/widgets/attachment_file_block.dart';

import 'support/fake_attachments.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets(
    'a file block shows the file and opens it; a missing one says so',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.runAsync(() async {
        final (store, _, dir) = await testAttachmentStore(db);
        addTearDown(() => dir.delete(recursive: true));
        final pdf = Uint8List.fromList('%PDF-1.4 kit'.codeUnits);
        final ref = await store.addFile(pdf, fileName: 'Emergency Kit.pdf');
        final opened = <String>[];

        final editorState = EditorState(
          document: Document.blank()
            ..insert(
              [0],
              [
                fileNode(url: ref, name: 'Emergency Kit.pdf', size: pdf.length),
                fileNode(
                  url: 'attachment://0d7a3f7e-9999-4c5e-9f00-000000000009.m4a',
                  name: 'New Recording',
                  size: 2048,
                ),
                paragraphNode(),
              ],
            ),
        );
        addTearDown(editorState.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              attachmentStoreProvider.overrideWithValue(store),
              openFileProvider.overrideWithValue((path) async {
                opened.add(path);
                return true;
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: AppFlowyEditor(
                  editorState: editorState,
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    FileBlockKeys.type: AttachmentFileBlockComponentBuilder(),
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Emergency Kit.pdf'), findsOneWidget);
        expect(find.text('PDF · 12 B'), findsOneWidget);
        expect(find.text('M4A · 2.0 KB'), findsOneWidget); // type from the id

        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        await tester.tap(find.byTooltip('Open').first);
        await settle();
        expect(opened, hasLength(1));
        expect(opened.single, endsWith(attachmentIdOf(ref)!));

        await tester.tap(find.byTooltip('Open').last);
        await settle();
        expect(opened, hasLength(1));
        expect(
          find.textContaining('isn\'t available right now'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}
