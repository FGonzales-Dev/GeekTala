import 'package:flutter/material.dart';

import '../shell/widgets/mobile_nav_bar.dart';
import 'widgets/trash_list.dart';

/// Phones: Recently Deleted, pushed from Folders (`/trash`). Desktop shows
/// [TrashList] inline instead (see `DesktopShell`).
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MobileNavBar(backLabel: 'Folders'),
            Expanded(child: TrashList()),
          ],
        ),
      ),
    );
  }
}
