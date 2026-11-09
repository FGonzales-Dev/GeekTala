import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

/// `.sidebar-search` / `.m-search` — filters notes by title and body text
/// (see [searchQueryProvider] / `searchNotes`).
class SearchField extends ConsumerStatefulWidget {
  const SearchField({super.key, required this.hint});

  final String hint;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).set('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final hasQuery = ref.watch(searchQueryProvider).isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(AppRadius.small + 1),
      ),
      child: Row(
        children: [
          AppIcon(AppIconName.search, size: 13, color: colors.textFaint),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).set(value),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: colors.textFaint,
                ),
              ),
            ),
          ),
          if (hasQuery)
            InkWell(
              onTap: _clear,
              borderRadius: BorderRadius.circular(20),
              child: Icon(Icons.close, size: 13, color: colors.textFaint),
            ),
        ],
      ),
    );
  }
}
