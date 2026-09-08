import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/providers/notes_providers.dart';
import '../notes_list/widgets/mobile_note_card.dart';

/// Mobile "Shared" tab — notes with collaborators, as a stand-in until
/// real `note_shares`/`folder_shares` data exists (Build Order step 7).
/// Always empty right now: [NotesRepository] hardcodes `collaboratorInitials`
/// to `[]` until those tables exist.
class SharedScreen extends ConsumerWidget {
  const SharedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allNotes = ref.watch(allNotesProvider).value ?? const [];
    final shared = allNotes
        .where((n) => n.collaboratorInitials.isNotEmpty)
        .toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Text(
              'Shared with me',
              style: AppTextStyles.mobileScreenTitle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: shared.isEmpty
                ? Center(
                    child: Text(
                      'No shared notes yet',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: context.nooteColors.textFaint,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final note in shared)
                        MobileNoteCard(note: note, onTap: () {}),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
