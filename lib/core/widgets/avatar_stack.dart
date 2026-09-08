import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'noote_avatar.dart';

/// `.avatar-stack` — overlapping collaborator avatars.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.initials, this.size = 22});

  final List<String> initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (initials.isEmpty) return const SizedBox.shrink();

    final colors = context.nooteColors;
    final palette = [colors.avatar1, colors.avatar2, colors.avatar3];
    final surface = Theme.of(context).colorScheme.surface;
    const overlap = 0.27;
    final totalWidth = size + (initials.length - 1) * size * (1 - overlap);

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < initials.length; i++)
            Positioned(
              left: i * size * (1 - overlap),
              child: NooteAvatar(
                initials: initials[i],
                background: palette[i % palette.length],
                size: size,
                borderColor: i == 0 ? null : surface,
              ),
            ),
        ],
      ),
    );
  }
}
