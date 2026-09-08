import 'package:flutter/material.dart';

/// `.avatar` — circular initials avatar with a themed border, used both
/// standalone and inside [AvatarStack].
class NooteAvatar extends StatelessWidget {
  const NooteAvatar({
    super.key,
    required this.initials,
    required this.background,
    this.size = 22,
    this.borderColor,
  });

  final String initials;
  final Color background;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 2),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.43,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
