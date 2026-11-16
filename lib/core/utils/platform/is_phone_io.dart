import 'dart:io';

/// Running on an Android or iOS device (or emulator) — not a narrow
/// desktop window, and not `flutter test` (which runs on the computer).
bool get runningOnPhone => Platform.isAndroid || Platform.isIOS;
