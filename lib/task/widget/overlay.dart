import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class TasksOverlayHost extends StatefulWidget {
  const TasksOverlayHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<TasksOverlayHost> createState() => _TasksOverlayHostState();
}

class _TasksOverlayHostState extends State<TasksOverlayHost>
    with TickerProviderStateMixin {
  static const double _margin = 16;
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 220,
    ratio: 0.85,
  );

  late final AnimationController _xCtrl;
  late final AnimationController _yCtrl;
  Offset? _position;

  @override
  void initState() {
    super.initState();
    _xCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() => _setPosition(x: _xCtrl.value));
    _yCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() => _setPosition(y: _yCtrl.value));
  }

  @override
  void dispose() {
    _xCtrl.dispose();
    _yCtrl.dispose();
    super.dispose();
  }

  void _setPosition({double? x, double? y}) {
    final Offset current = _position ?? Offset.zero;
    setState(() {
      _position = Offset(x ?? current.dx, y ?? current.dy);
    });
  }

  Offset _defaultPosition(BoxConstraints constraints, EdgeInsets padding) =>
      Offset(
        constraints.maxWidth - TaskBubble.size - _margin,
        (constraints.maxHeight - TaskBubble.size) / 2,
      );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TasksController>();
    return ListenableBuilder(
      listenable: controller.suppressBubble,
      builder: (context, _) => _buildOverlay(
        context,
        controller,
        controller.kind != TaskKind.none && !controller.suppressBubble.value,
      ),
    );
  }

  Widget _buildOverlay(
    BuildContext context,
    TasksController controller,
    bool visible,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final EdgeInsets padding = MediaQuery.paddingOf(context);
        final Offset pos = _position ?? _defaultPosition(constraints, padding);

        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (visible)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (_) {
                    _xCtrl.stop();
                    _yCtrl.stop();
                    _position ??= _defaultPosition(constraints, padding);
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final Offset current =
                          _position ?? _defaultPosition(constraints, padding);
                      _position = current + details.delta;
                    });
                  },
                  onPanEnd: (details) {
                    final Offset current =
                        _position ?? _defaultPosition(constraints, padding);
                    final double centerX = current.dx + TaskBubble.size / 2;
                    final bool snapRight = centerX > constraints.maxWidth / 2;
                    final double targetX = snapRight
                        ? constraints.maxWidth - TaskBubble.size - _margin
                        : _margin;
                    final double targetY = current.dy.clamp(
                      padding.top + _margin,
                      constraints.maxHeight -
                          TaskBubble.size -
                          padding.bottom -
                          _margin,
                    );
                    _xCtrl.animateWith(
                      SpringSimulation(
                        _spring,
                        current.dx,
                        targetX,
                        details.velocity.pixelsPerSecond.dx,
                      ),
                    );
                    _yCtrl.animateWith(
                      SpringSimulation(
                        _spring,
                        current.dy,
                        targetY,
                        details.velocity.pixelsPerSecond.dy,
                      ),
                    );
                  },
                  child: TaskBubble(
                    onTap: () {
                      final BuildContext? ctx =
                          widget.navigatorKey.currentContext;
                      if (ctx != null) showTasksPrompt(ctx);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
