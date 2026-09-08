import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Single-field name dialog, shared by "New folder", "New subfolder", and
/// "Rename" — returns the entered name, or `null` if cancelled/blank.
Future<String?> showFolderNameDialog(
  BuildContext context, {
  required String title,
  String? initialName,
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initialName);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
