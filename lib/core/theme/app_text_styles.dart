import 'package:flutter/material.dart';

/// Named text styles matching the type scale in `noote-ui-concepts.html`.
/// Inter-based; color is deliberately omitted here (callers apply
/// `Theme.of(context).colorScheme` / `NooteColors` roles) so these styles
/// work unchanged across light/dark.
abstract final class AppTextStyles {
  static const _inter = 'Inter';
  static const _jetBrainsMono = 'JetBrains Mono';

  /// `.brand-name` — 14.5px / 600 / -0.01em
  static const brandName = TextStyle(
    fontFamily: _inter,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01,
  );

  /// `.editor-title` — 24px / 700 / -0.015em
  static const editorTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.015 * 24,
  );

  /// `.b-h` — block heading, 15.5px / 600
  static const blockHeading = TextStyle(
    fontFamily: _inter,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// `.b-p` — block paragraph, 13.5px / 1.65 line-height
  static const blockParagraph = TextStyle(
    fontFamily: _inter,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );

  /// `.b-ul` — bullet list item text, 13.5px / 1.75 line-height
  static const blockListItem = TextStyle(
    fontFamily: _inter,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.75,
  );

  /// `.note-title` — 12.5px / 600
  static const noteTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  /// `.note-time` — 10.5px / 400
  static const noteTime = TextStyle(
    fontFamily: _inter,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
  );

  /// `.note-preview` — 11.5px / 1.4 line-height
  static const notePreview = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// `.tag-chip` — 10px / 400
  static const tagChip = TextStyle(
    fontFamily: _inter,
    fontSize: 10,
    fontWeight: FontWeight.w400,
  );

  /// `.nav-item` — 12.5px / 400 (500 when active, applied by the caller)
  static const navItem = TextStyle(
    fontFamily: _inter,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
  );

  /// `.nav-section-label` — 10.5px uppercase, letter-spacing .06em
  static const navSectionLabel = TextStyle(
    fontFamily: _inter,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.06 * 10.5,
  );

  /// `.breadcrumb` — 11.5px / 400
  static const breadcrumb = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
  );

  /// `.sync-status` — 11px / 400
  static const syncStatus = TextStyle(
    fontFamily: _inter,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  /// `.share-btn` — 11.5px / 500
  static const shareButton = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
  );

  /// `.m-topbar h1` — 20px / 700 / -0.02em (mobile notes-list title)
  static const mobileScreenTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 20,
  );

  /// `.m-chip` — 11.5px / 400 (folder filter chips)
  static const mobileChip = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
  );

  /// `.b-code-lang` — 10px uppercase, letter-spacing .05em, JetBrains Mono
  static const codeLangLabel = TextStyle(
    fontFamily: _jetBrainsMono,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.05 * 10,
  );

  /// `.b-code pre` — 12px / 1.6 line-height, JetBrains Mono. Registered
  /// only on the code block widget, never app-wide (see §3 of noote-plan.md).
  static const code = TextStyle(
    fontFamily: _jetBrainsMono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  /// `.b-table` cell text — 12.5px / 400
  static const tableCell = TextStyle(
    fontFamily: _inter,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
  );

  /// `.b-table th` — 11.5px / 600
  static const tableHeader = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
  );
}
