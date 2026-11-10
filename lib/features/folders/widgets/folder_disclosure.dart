import 'package:flutter/material.dart';

/// The ▸/▾ arrow before a folder that shows or hides its subfolders. For a
/// folder without subfolders ([expanded] null) it's an empty space of the
/// same width, so folder icons line up.
class FolderDisclosure extends StatelessWidget {
  const FolderDisclosure({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.color,
    this.size = 14,
  });

  final bool? expanded;
  final VoidCallback? onToggle;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final box = size + 4;
    final open = expanded;
    if (open == null) return SizedBox(width: box);
    return Tooltip(
      message: open ? 'Hide subfolders' : 'Show subfolders',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: box,
          height: box,
          child: AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(Icons.chevron_right, size: size, color: color),
          ),
        ),
      ),
    );
  }
}
