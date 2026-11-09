import 'package:flutter/material.dart';

/// A thin draggable strip between two panes in the desktop three-pane
/// shell — drag left/right to resize the pane next to it.
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({super.key, required this.onDrag, this.onDragEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd?.call(),
        child: const SizedBox(width: 6),
      ),
    );
  }
}
