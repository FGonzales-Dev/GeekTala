import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../core/utils/relative_time.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/sync_provider.dart';
import '../../../data/sync/app_sync_status.dart';
import '../../note_editor/markdown_paste.dart';
import '../theme_mode_provider.dart';

/// Settings content, shared by the mobile `SettingsScreen` (full screen)
/// and the desktop `SettingsDialog` (modal) — the same "shared core, thin
/// per-platform wrapper" split as `NoteEditorBody`/`TrashList`.
class SettingsBody extends ConsumerWidget {
  const SettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final mode = ref.watch(appThemeModeProvider);
    final user = ref.watch(currentUserProvider);
    final pasteFormatted = ref.watch(pasteMarkdownFormattedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Text(
            'Settings',
            style: AppTextStyles.mobileScreenTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _SectionLabel('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(AppRadius.small + 3),
            ),
            child: Row(
              children: [
                for (final entry in const {
                  ThemeMode.system: 'System',
                  ThemeMode.light: 'Light',
                  ThemeMode.dark: 'Dark',
                }.entries)
                  Expanded(
                    child: _ModeButton(
                      label: entry.value,
                      selected: mode == entry.key,
                      onTap: () =>
                          ref.read(appThemeModeProvider.notifier).select(entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SectionLabel('When pasting Markdown'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(AppRadius.small + 3),
            ),
            child: Row(
              children: [
                for (final (formatted, label) in const [
                  (true, 'Format it'),
                  (false, 'Keep as Markdown'),
                ])
                  Expanded(
                    child: _ModeButton(
                      label: label,
                      selected: pasteFormatted == formatted,
                      onTap: () => setPasteMarkdownFormatted(ref, formatted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Text(
            'Right after pasting you can switch to the other one.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11.5,
              color: colors.textFaint,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SectionLabel('Account & Sync'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(AppRadius.small + 3),
            ),
            child: user == null
                ? Text(
                    'Not signed in',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.email ?? 'Signed in',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                const SyncStatusIndicator(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _signOut(context, ref),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _SyncPanel(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

enum _SignOutChoice { uploadFirst, signOut }

/// Not-yet-uploaded changes stay on the device after sign-out, but are
/// deleted if a different account signs in here next (see
/// `SyncService.adoptAccount`) — so offer to upload first.
Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final pending = ref.read(syncStatusProvider).pendingChanges;
  if (pending > 0) {
    final choice = await showDialog<_SignOutChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload before signing out?'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
        ),
        content: Text(
          '${_changes(pending)} on this device ${_haveNot(pending)} been '
          'uploaded. They stay here and upload the next time you sign in '
          'with this account, but are deleted if a different account signs '
          'in on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_SignOutChoice.signOut),
            child: const Text('Sign Out Anyway'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_SignOutChoice.uploadFirst),
            child: const Text('Upload and Sign Out'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == _SignOutChoice.uploadFirst &&
        !await ref.read(syncControllerProvider.notifier).upload()) {
      return; // The error shows in the sync panel; stay signed in.
    }
  }
  await ref.read(supabaseClientProvider).auth.signOut();
}

enum _DownloadChoice { uploadFirst, discard }

Future<void> _download(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(syncControllerProvider.notifier);
  final pending = ref.read(syncStatusProvider).pendingChanges;
  if (pending == 0) {
    await controller.download();
    return;
  }
  final choice = await showDialog<_DownloadChoice>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Replace this device\'s notes?'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
        ),
        content: Text(
          'Downloading replaces everything on this device with the server '
          'copy. ${_changes(pending)} here ${_haveNot(pending)} been '
          'uploaded and would be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(_DownloadChoice.discard),
            child: const Text('Discard and Download'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_DownloadChoice.uploadFirst),
            child: const Text('Upload First'),
          ),
        ],
      );
    },
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

String _changes(int count) => '$count ${count == 1 ? 'change' : 'changes'}';

String _haveNot(int count) => count == 1 ? 'hasn\'t' : 'haven\'t';

String _ago(DateTime? time) {
  if (time == null) return 'never';
  final relative = formatRelativeTime(time, DateTime.now());
  if (relative == 'now') return 'just now';
  return RegExp(r'^\d+[mhd]$').hasMatch(relative) ? '$relative ago' : relative;
}

/// Manual sync controls — see lib/data/sync/sync_service.dart.
class _SyncPanel extends ConsumerWidget {
  const _SyncPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final status = ref.watch(syncStatusProvider);
    final pending = status.pendingChanges;
    final message = _message(status);

    final detailStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 1.4,
      color: colors.textFaint,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pending == 0
              ? 'Everything on this device is uploaded.'
              : '${_changes(pending)} on this device not uploaded yet.',
          style: detailStyle.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          'Last upload ${_ago(status.lastUploadedAt)} · '
          'last download ${_ago(status.lastDownloadedAt)}',
          style: detailStyle,
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message.text,
            style: detailStyle.copyWith(
              color: message.isError ? theme.colorScheme.error : null,
            ),
          ),
        ],
        const SizedBox(height: 6),
        // Automatic sync: see `_AutoSync` in sync_provider.dart.
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: ref.watch(autoSyncEnabledProvider),
          onChanged: (on) => setAutoSyncEnabled(ref, on),
          title: Text(
            'Sync automatically',
            style: detailStyle.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            'Uploads changes a few seconds after you make them, and gets '
            'the latest from the server when the app opens.',
            style: detailStyle,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: status.busy || pending == 0
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).upload(),
              child: Text(status.uploading ? 'Uploading…' : 'Upload Changes'),
            ),
            OutlinedButton(
              onPressed: status.busy ? null : () => _download(context, ref),
              child: Text(
                status.downloading ? 'Downloading…' : 'Download from Server',
              ),
            ),
          ],
        ),
      ],
    );
  }

  ({String text, bool isError})? _message(AppSyncStatus status) {
    if (status.error case final error?) return (text: error, isError: true);
    if (status.notice case final notice?) {
      return (text: notice, isError: false);
    }
    return null;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: context.nooteColors.textFaint,
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surface : null,
          borderRadius: BorderRadius.circular(AppRadius.small),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
