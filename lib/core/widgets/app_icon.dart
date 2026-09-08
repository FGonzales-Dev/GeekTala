import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Names match the files under `assets/icons/` (without extension).
enum AppIconName {
  search,
  add,
  folder,
  people,
  tag,
  share,
  chevronLeft,
  sun,
  moon,
  listLines,
  grid,
  clock,
  bulletList,
  code,
  table,
  image,
  bold,
  textLines,
}

extension on AppIconName {
  String get _fileName => switch (this) {
        AppIconName.search => 'ic_search',
        AppIconName.add => 'ic_add',
        AppIconName.folder => 'ic_folder',
        AppIconName.people => 'ic_people',
        AppIconName.tag => 'ic_tag',
        AppIconName.share => 'ic_share',
        AppIconName.chevronLeft => 'ic_chevron_left',
        AppIconName.sun => 'ic_sun',
        AppIconName.moon => 'ic_moon',
        AppIconName.listLines => 'ic_list_lines',
        AppIconName.grid => 'ic_grid',
        AppIconName.clock => 'ic_clock',
        AppIconName.bulletList => 'ic_bullet_list',
        AppIconName.code => 'ic_code',
        AppIconName.table => 'ic_table',
        AppIconName.image => 'ic_image',
        AppIconName.bold => 'ic_bold',
        AppIconName.textLines => 'ic_text_lines',
      };
}

/// Renders one of the mockup's extracted SVGs (`assets/icons/`), tinted to
/// [color] via a colorFilter — equivalent to the mockup's `stroke:currentColor`.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 16, this.color});

  final AppIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color;
    return SvgPicture.asset(
      'assets/icons/${name._fileName}.svg',
      width: size,
      height: size,
      colorFilter:
          tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
