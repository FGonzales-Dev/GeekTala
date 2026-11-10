import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Debounced saves that haven't reached the database yet — the note
/// editor writes 500 ms after the last keystroke. Upload and download
/// flush these first, so the last few keystrokes aren't left out of an
/// upload or written over the top of a download.
class PendingWrites {
  final _flushers = <Future<void> Function()>{};

  void register(Future<void> Function() flush) => _flushers.add(flush);

  void unregister(Future<void> Function() flush) => _flushers.remove(flush);

  Future<void> flushAll() async {
    await Future.wait([for (final flush in _flushers.toList()) flush()]);
  }
}

final pendingWritesProvider = Provider<PendingWrites>((ref) => PendingWrites());
