import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the desktop three-pane shell's notes-list/editor region is
/// currently showing Recently Deleted instead of the normal folder/search
/// view. Mutually exclusive with folder and tag selection — see
/// `AppSidebar`'s "Recently Deleted" nav item and `DesktopShell`.
class IsViewingTrash extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;
  void exit() => state = false;
}

final isViewingTrashProvider = NotifierProvider<IsViewingTrash, bool>(
  IsViewingTrash.new,
);
