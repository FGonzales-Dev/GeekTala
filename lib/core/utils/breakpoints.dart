import 'package:flutter/widgets.dart';

/// Below this width, the app renders the mobile bottom-nav shell instead of
/// the desktop/web three-pane shell. Matches Material's medium/expanded
/// breakpoint, which is roughly where a three-pane layout stops having room
/// to breathe.
const double kDesktopBreakpoint = 900;

bool isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
