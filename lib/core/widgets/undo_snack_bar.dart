import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Moved to Work · Undo". Takes the messenger rather than a context so
/// callers can look it up before an `await` (the widget that started the
/// action may be gone by the time it finishes, e.g. a folder that moved).
void showUndoSnackBar(
  ScaffoldMessengerState messenger,
  String message,
  Future<void> Function() onUndo,
) {
  final width = math.min(
    420.0,
    MediaQuery.sizeOf(messenger.context).width - 32,
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: width,
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}
