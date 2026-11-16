import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/noote_dialog.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/device_settings_provider.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/sync_provider.dart';
import '../../../data/sync/app_sync_status.dart';
import '../../note_editor/markdown_paste.dart';
import '../../shell/providers/pane_widths_provider.dart';
import '../sync_dialogs.dart';
import '../theme_mode_provider.dart';

/// The parts of Settings: a pane each in the desktop window, stacked on
/// the phone's Settings screen.
enum SettingsSection {
  appearance('Appearance', Icons.contrast, 'How Noote looks on this device.'),
  editor('Editor', Icons.edit_outlined, 'Writing and pasting.'),
  sync(
    'Sync & account',
    Icons.sync,
    'Your notes are stored on this device and in your Noote account.',
  ),
  about('About', Icons.info_outline, 'Version and where your data lives.');

  const SettingsSection(this.label, this.icon, this.lead);

  final String label;
  final IconData icon;
  final String lead;
}

/// One section's settings. [compact] (phones) puts each control under its
/// label instead of beside it, and leaves out desktop-only settings.
class SettingsSectionBody extends StatelessWidget {
  const SettingsSectionBody(this.section, {super.key, this.compact = false});

  final SettingsSection section;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      SettingsSection.appearance => _Appearance(compact: compact),
      SettingsSection.editor => _Editor(compact: compact),
      SettingsSection.sync => _Sync(compact: compact),
      SettingsSection.about => const _About(),
    };
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _Appearance extends ConsumerWidget {
  const _Appearance({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    ref.watch(sidebarWidthProvider);
    ref.watch(notesListWidthProvider);
    final defaultWidths =
        ref.read(sidebarWidthProvider.notifier).isDefault &&
        ref.read(notesListWidthProvider.notifier).isDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: 'Theme',
          description: compact
              ? 'System follows your phone\'s light or dark setting.'
              : 'System follows your computer\'s light or dark setting.',
          stacked: true,
          first: true,
          trailing: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final option in ThemeMode.values)
                _ThemeCard(
                  mode: option,
                  selected: mode == option,
                  onTap: () =>
                      ref.read(appThemeModeProvider.notifier).select(option),
                ),
            ],
          ),
        ),
        if (!compact)
          SettingsRow(
            title: 'Pane widths',
            description:
                'The sidebar and notes list remember how wide you dragged '
                'them.',
            trailing: NooteButton(
              'Reset',
              onPressed: defaultWidths
                  ? null
                  : () {
                      ref.read(sidebarWidthProvider.notifier).reset();
                      ref.read(notesListWidthProvider.notifier).reset();
                    },
            ),
          ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  static const _light = (
    sidebar: Color(0xFFF2F1EE),
    main: Color(0xFFFFFFFF),
    line: Color(0xFFE4E3DF),
    text: Color(0xFF1A1A18),
  );
  static const _dark = (
    sidebar: Color(0xFF202020),
    main: Color(0xFF1C1C1C),
    line: Color(0xFF2C2C2A),
    text: Color(0xFFEDEDEA),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
    final preview = switch (mode) {
      ThemeMode.light => _miniWindow(_light),
      ThemeMode.dark => _miniWindow(_dark),
      ThemeMode.system => Row(
        children: [
          Expanded(child: _miniWindow(_light)),
          Expanded(child: _miniWindow(_dark)),
        ],
      ),
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '$label theme',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 118,
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: preview,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _miniWindow(
    ({Color sidebar, Color main, Color line, Color text}) c,
  ) {
    Widget bar(Color color, double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: ColoredBox(color: c.sidebar)),
        Expanded(
          flex: 7,
          child: Container(
            color: c.main,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(c.text, 0.6),
                const SizedBox(height: 5),
                bar(c.line, 1),
                const SizedBox(height: 5),
                bar(c.line, 0.8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

class _Editor extends ConsumerWidget {
  const _Editor({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pasteFormatted = ref.watch(pasteMarkdownFormattedProvider);
    final pdfPreview = ref.watch(pdfPreviewByDefaultProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          first: true,
          stacked: compact,
          title: 'When pasting Markdown',
          description: 'Right after pasting you can switch to the other one.',
          trailing: SettingsSegmented<bool>(
            value: pasteFormatted,
            options: const {true: 'Format it', false: 'Keep as Markdown'},
            onChanged: (formatted) => setPasteMarkdownFormatted(ref, formatted),
          ),
        ),
        SettingsRow(
          stacked: compact,
          title: 'PDFs in notes',
          description:
              'Show a PDF\'s first page, or just its name. You can still '
              'switch one PDF with its own button.',
          trailing: SettingsSegmented<bool>(
            value: pdfPreview,
            options: const {true: 'Preview', false: 'Card'},
            onChanged: (preview) => ref.read(writeDeviceSettingProvider)(
              DeviceSettingKeys.pdfView,
              preview ? 'preview' : 'card',
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync & account
// ---------------------------------------------------------------------------

String _ago(DateTime? time) {
  if (time == null) return 'never';
  final relative = formatRelativeTime(time, DateTime.now());
  if (relative == 'now') return 'just now';
  return RegExp(r'^\d+[mhd]$').hasMatch(relative) ? '$relative ago' : relative;
}

String _changes(int n) => '$n ${n == 1 ? 'change' : 'changes'}';

/// Initials for the account avatar: from the name the account was given,
/// or the email's first letter.
String accountInitials(User user) {
  final meta = user.userMetadata ?? const {};
  final name = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isNotEmpty) {
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }
  final email = user.email ?? '';
  return email.isEmpty ? '?' : email[0].toUpperCase();
}

class _Sync extends ConsumerWidget {
  const _Sync({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final user = ref.watch(currentUserProvider);
    final status = ref.watch(syncStatusProvider);
    final pending = status.pendingChanges;
    final muted = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 1.45,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardBox(
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: NooteStatusColors.ok,
                child: Text(
                  user == null ? '?' : accountInitials(user),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.email ?? 'Not signed in',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      user == null
                          ? 'Notes stay on ${thisDevice()} only.'
                          : 'Signed in on ${thisDevice()}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              if (user != null) ...[
                const SizedBox(width: 8),
                NooteButton(
                  'Sign out',
                  onPressed: () => signOutFlow(context, ref),
                ),
              ],
            ],
          ),
        ),
        if (user != null) ...[
          _CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(status, colors),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.uploading
                            ? 'Uploading…'
                            : status.downloading
                            ? 'Downloading…'
                            : pending == 0
                            ? 'Everything is uploaded'
                            : '${_changes(pending)} not uploaded yet',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 0, 0),
                  child: Text(
                    'Last upload ${_ago(status.lastUploadedAt)} · '
                    'last download ${_ago(status.lastDownloadedAt)}',
                    style: muted,
                  ),
                ),
                if (status.error ?? status.notice case final message?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
                    child: Text(
                      message,
                      style: muted.copyWith(
                        color: status.hasError
                            ? NooteStatusColors.danger
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    NooteButton(
                      status.uploading ? 'Uploading…' : 'Upload now',
                      onPressed: status.busy || pending == 0
                          ? null
                          : () => ref
                                .read(syncControllerProvider.notifier)
                                .upload(),
                    ),
                    NooteButton(
                      status.downloading
                          ? 'Downloading…'
                          : 'Download from server…',
                      onPressed: status.busy
                          ? null
                          : () => downloadFlow(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SettingsRow(
            first: true,
            title: 'Sync automatically',
            description:
                'Uploads a few seconds after you change something and gets '
                'the latest when Noote opens.',
            trailing: Switch.adaptive(
              value: ref.watch(autoSyncEnabledProvider),
              activeTrackColor: NooteStatusColors.ok,
              onChanged: (on) => setAutoSyncEnabled(ref, on),
            ),
          ),
        ],
      ],
    );
  }

  static Color _dotColor(AppSyncStatus status, NooteColors colors) {
    if (status.busy) return colors.avatar2;
    if (status.hasError) return NooteStatusColors.danger;
    if (status.pendingChanges > 0) return Colors.amber.shade700;
    return NooteStatusColors.ok;
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

/// How many files this device keeps for its notes.
final _attachmentCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return (await ref.watch(appDatabaseProvider).attachmentsDao.all()).length;
});

/// The server's address without `https://`.
final _serverHostProvider = Provider.autoDispose<String?>((ref) {
  try {
    return Uri.parse(ref.watch(supabaseClientProvider).rest.url).host;
  } catch (_) {
    return null; // Supabase isn't set up (tests).
  }
});

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final notes = ref.watch(allNotesProvider).value?.length;
    final files = ref.watch(_attachmentCountProvider).value;
    final host = ref.watch(_serverHostProvider);
    final rows = [
      ('Version', appVersion),
      if (host != null) ('Server', host),
      (
        'On ${thisDevice()}',
        [
          if (notes != null) '$notes ${notes == 1 ? 'note' : 'notes'}',
          if (files != null)
            '$files ${files == 1 ? 'attachment' : 'attachments'}',
        ].join(' · '),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        color: colors.textFaint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// A setting: its name and a short description, with its control beside
/// it (or under it when [stacked]). Rows after the [first] get a divider.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
    this.stacked = false,
    this.first = false,
  });

  final String title;
  final String? description;
  final Widget trailing;
  final bool stacked;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              description!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: context.nooteColors.borderSoft)),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 10), trailing],
            )
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 18),
                trailing,
              ],
            ),
    );
  }
}

/// A small segmented control: one of [options] (value → label).
class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(key: option, value: label) in options.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Semantics(
                selected: option == value,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(option),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: option == value ? colors.activeBg : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: option == value
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: option == value
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border.all(color: context.nooteColors.borderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
