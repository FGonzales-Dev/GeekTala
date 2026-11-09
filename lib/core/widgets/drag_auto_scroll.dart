import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scrolls a [DragAutoScrollRegion] while something is dragged near its top
/// or bottom edge — Flutter's `Draggable` doesn't do this by itself. Every
/// draggable in the app reports its pointer here (`onDragUpdate`) and calls
/// [stop] when the drag ends.
class DragAutoScroll {
  final _regions = <_DragAutoScrollRegionState>{};

  void update(Offset globalPosition) {
    for (final region in _regions) {
      region._update(globalPosition);
    }
  }

  void stop() {
    for (final region in _regions) {
      region._stop();
    }
  }
}

final dragAutoScrollProvider = Provider<DragAutoScroll>(
  (ref) => DragAutoScroll(),
);

/// A scroll view that [DragAutoScroll] can scroll. [builder] must give
/// `controller` to the scroll view it builds.
class DragAutoScrollRegion extends ConsumerStatefulWidget {
  const DragAutoScrollRegion({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  ConsumerState<DragAutoScrollRegion> createState() =>
      _DragAutoScrollRegionState();
}

class _DragAutoScrollRegionState extends ConsumerState<DragAutoScrollRegion>
    with SingleTickerProviderStateMixin {
  /// How close to the edge (px) the pointer must be to start scrolling.
  static const _edge = 40.0;

  /// Speed (px/s) with the pointer at, or past, the edge.
  static const _maxSpeed = 700.0;

  final _controller = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  late final DragAutoScroll _autoScroll;
  double _speed = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _autoScroll = ref.read(dragAutoScrollProvider).._regions.add(this);
  }

  @override
  void dispose() {
    _autoScroll._regions.remove(this);
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _update(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !_controller.hasClients) {
      _stop();
      return;
    }
    final local = box.globalToLocal(globalPosition);
    final size = box.size;
    var speed = 0.0;
    if (local.dx >= 0 && local.dx <= size.width) {
      if (local.dy < _edge) {
        speed = -_maxSpeed * ((_edge - local.dy) / _edge).clamp(0.0, 1.0);
      } else if (local.dy > size.height - _edge) {
        speed =
            _maxSpeed *
            ((local.dy - (size.height - _edge)) / _edge).clamp(0.0, 1.0);
      }
    }
    _speed = speed;
    if (speed != 0 && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (speed == 0 && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + _speed * seconds).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) _controller.jumpTo(target);
  }

  void _stop() {
    _speed = 0;
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
