import 'package:flutter/material.dart';

import 'widgets/settings_body.dart';

/// Mobile "Settings" tab — see `SettingsBody` for the actual content,
/// shared with the desktop `SettingsDialog`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: SingleChildScrollView(child: SettingsBody()),
    );
  }
}
