import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drag-to-resize state for the desktop three-pane shell's sidebar and
/// notes-list panes. Not persisted across restarts — resets to the
/// mockup's original widths each launch.
class _PaneWidth extends Notifier<double> {
  _PaneWidth(this._initial, this.min, this.max);

  final double _initial;
  final double min;
  final double max;

  @override
  double build() => _initial;

  void dragBy(double delta) {
    state = (state + delta).clamp(min, max);
  }
}

final sidebarWidthProvider = NotifierProvider<_PaneWidth, double>(
  () => _PaneWidth(210, 160, 400),
);

final notesListWidthProvider = NotifierProvider<_PaneWidth, double>(
  () => _PaneWidth(250, 200, 480),
);
