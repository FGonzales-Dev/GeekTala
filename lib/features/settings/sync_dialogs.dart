import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/noote_dialog.dart';
import '../../data/providers/auth_provider.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/sync_provider.dart';

/// "this Mac", "this phone", … for sentences about the device.
String thisDevice() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => 'this Mac',
  TargetPlatform.windows || TargetPlatform.linux => 'this computer',
  TargetPlatform.iOS || TargetPlatform.android => 'this phone',
  _ => 'this device',
};

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// What's waiting to upload, as facts for a dialog: "1 note", "2 folders",
/// "1 tag change", "3 files".
Future<List<String>> pendingFacts(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final byEntity = await db.syncDao.pendingByEntity();
  final files = (await db.attachmentsDao.notUploaded()).length;
  final notes = byEntity['notes'] ?? 0;
  final folders = byEntity['folders'] ?? 0;
  final tags = (byEntity['tags'] ?? 0) + (byEntity['notes_tags'] ?? 0);
  return [
    if (notes > 0) _count(notes, 'note', 'notes'),
    if (folders > 0) _count(folders, 'folder', 'folders'),
    if (tags > 0) _count(tags, 'tag change', 'tag changes'),
    if (files > 0) _count(files, 'file', 'files'),
  ];
}

String _notUploadedTitle(int pending) => pending == 1
    ? '1 change isn\'t uploaded yet'
    : '$pending changes aren\'t uploaded yet';

enum _SignOutChoice { uploadFirst, signOut }

/// Signs out. Not-yet-uploaded changes stay on the device after sign-out,
/// but are deleted if a different account signs in here next (see
/// `SyncService.adoptAccount`) — so with changes waiting it offers to
/// upload first.
Future<void> signOutFlow(BuildContext context, WidgetRef ref) async {
  final pending = ref.read(syncStatusProvider).pendingChanges;
  if (pending > 0) {
    final facts = await pendingFacts(ref);
    if (!context.mounted) return;
    final choice = await showNooteDialog<_SignOutChoice>(
      context,
      builder: (context) => NooteDialog(
        icon: Icons.cloud_upload_outlined,
        title: _notUploadedTitle(pending),
        subtitle:
            'They upload next time you sign in — unless another account '
            'signs in on ${thisDevice()} first.',
        body: facts.isEmpty ? null : NooteFacts(facts),
        onSubmit: () => Navigator.of(context).pop(_SignOutChoice.uploadFirst),
        footerLeading: NooteButton(
          'Sign out anyway',
          style: NooteButtonStyle.quietDanger,
          onPressed: () => Navigator.of(context).pop(_SignOutChoice.signOut),
        ),
        actions: [
          NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
          NooteButton.primary(
            'Upload and sign out',
            onPressed: () =>
                Navigator.of(context).pop(_SignOutChoice.uploadFirst),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == _SignOutChoice.uploadFirst &&
        !await ref.read(syncControllerProvider.notifier).upload()) {
      return; // The error shows in Settings; stay signed in.
    }
  }
  await ref.read(supabaseClientProvider).auth.signOut();
}

enum _DownloadChoice { uploadFirst, discard }

/// Replaces this device's notes with the server copy. With changes
/// waiting to upload, asks first: upload them, or lose them.
Future<void> downloadFlow(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(syncControllerProvider.notifier);
  final pending = ref.read(syncStatusProvider).pendingChanges;
  if (pending == 0) {
    await controller.download();
    return;
  }
  final facts = await pendingFacts(ref);
  if (!context.mounted) return;
  final choice = await showNooteDialog<_DownloadChoice>(
    context,
    builder: (context) => NooteDialog(
      icon: Icons.cloud_download_outlined,
      title: 'Replace the notes on ${thisDevice()}?',
      subtitle:
          'Downloading replaces everything here with the server copy. '
          '${_notUploadedTitle(pending).replaceFirst(' yet', '')} and would '
          'be lost.',
      body: facts.isEmpty ? null : NooteFacts(facts),
      onSubmit: () => Navigator.of(context).pop(_DownloadChoice.uploadFirst),
      footerLeading: NooteButton(
        'Discard and download',
        style: NooteButtonStyle.quietDanger,
        onPressed: () => Navigator.of(context).pop(_DownloadChoice.discard),
      ),
      actions: [
        NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        NooteButton.primary(
          'Upload first',
          onPressed: () =>
              Navigator.of(context).pop(_DownloadChoice.uploadFirst),
        ),
      ],
    ),
  );
  switch (choice) {
    case _DownloadChoice.uploadFirst:
      if (await controller.upload()) await controller.download();
    case _DownloadChoice.discard:
      await controller.download(discardLocalChanges: true);
    case null:
      return;
  }
}
