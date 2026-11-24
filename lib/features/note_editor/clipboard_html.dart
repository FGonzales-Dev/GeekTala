import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// The HTML version of what's on the system clipboard, which web pages,
/// chat apps and documents put there beside the plain text (Flutter's own
/// clipboard only reads the plain text).
///
/// Windows reads it through `pasteboard`; macOS through the
/// `noote/clipboard` channel in macos/Runner/MainFlutterWindow.swift,
/// since `pasteboard` can't there. Null on other platforms, when there's
/// no HTML, or when it can't be read.
Future<String?> readClipboardHtml() async {
  if (kIsWeb) return null;
  try {
    final raw = switch (defaultTargetPlatform) {
      TargetPlatform.windows => await Pasteboard.html,
      TargetPlatform.macOS => await _macClipboard.invokeMethod<String>('html'),
      _ => null,
    };
    final html = clipboardHtmlFragment(raw);
    return html == null || html.trim().isEmpty ? null : html;
  } catch (_) {
    return null; // no clipboard access (e.g. tests): paste the text
  }
}

const _macClipboard = MethodChannel('noote/clipboard');

/// The copied part of clipboard HTML.
///
/// Windows' "HTML Format" starts with a description (`Version:0.9`,
/// `StartFragment:…`) and wraps the copied part in `<!--StartFragment-->`
/// / `<!--EndFragment-->` inside a whole page; it can also end in null
/// bytes. HTML without the markers or description (macOS) is returned as
/// it is.
@visibleForTesting
String? clipboardHtmlFragment(String? raw) {
  if (raw == null) return null;
  final html = raw.replaceAll('\u0000', '');
  final start = _startMarker.firstMatch(html);
  if (start != null) {
    final end = _endMarker.allMatches(html, start.end).lastOrNull;
    return html.substring(start.end, end?.start ?? html.length);
  }
  if (!html.startsWith('Version:')) return html;

  // A description without markers: its offsets count UTF-8 bytes.
  int? offset(String name) => int.tryParse(
    RegExp('^$name:\\s*(\\d+)', multiLine: true).firstMatch(html)?.group(1) ??
        '',
  );
  final bytes = utf8.encode(html);
  final from = offset('StartFragment') ?? offset('StartHTML');
  final to = offset('EndFragment') ?? offset('EndHTML') ?? bytes.length;
  if (from != null && from >= 0 && from <= to && to <= bytes.length) {
    return utf8.decode(bytes.sublist(from, to), allowMalformed: true);
  }
  final firstTag = html.indexOf('<');
  return firstTag < 0 ? null : html.substring(firstTag);
}

final _startMarker = RegExp(
  r'<!--\s*StartFragment\s*-->',
  caseSensitive: false,
);
final _endMarker = RegExp(r'<!--\s*EndFragment\s*-->', caseSensitive: false);
