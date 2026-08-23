import 'package:flutter/material.dart';

import 'awan_mascot_controller.dart';
import 'awan_mascot_state.dart';
import 'awan_sprite_metadata.dart';

class AwanMascot extends StatefulWidget {
  const AwanMascot({
    super.key,
    this.controller,
    this.state = AwanMascotState.idle,
    this.size = 112,
    this.loop = true,
    this.returnToIdle = true,
    this.onOneShotCompleted,
    this.semanticLabel = 'Awan',
  });

  final AwanMascotController? controller;
  final AwanMascotState state;
  final double size;
  final bool loop;
  final bool returnToIdle;
  final VoidCallback? onOneShotCompleted;
  final String semanticLabel;

  @override
  State<AwanMascot> createState() => _AwanMascotState();
}

class _AwanMascotState extends State<AwanMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late AwanMascotController _controller;
  late bool _ownsController;
  AwanMascotState _activeState = AwanMascotState.idle;

  bool get _isWidgetTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgets');

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this)
      ..addStatusListener(_onAnimationStatus);
    _bindController();
  }

  @override
  void didUpdateWidget(covariant AwanMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_updateAnimation);
      if (_ownsController) _controller.dispose();
      _bindController();
    } else if (widget.controller == null && oldWidget.state != widget.state) {
      _setActiveState(widget.state);
    }
  }

  void _bindController() {
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? AwanMascotController(initialState: widget.state);
    _controller.addListener(_updateAnimation);
    _updateAnimation();
  }

  void _updateAnimation() {
    _setActiveState(_controller.state);
    if (mounted) setState(() {});
  }

  void _setActiveState(AwanMascotState state) {
    _activeState = state;
    final data = AwanSpriteMetadata.forState(_activeState);
    _animation
      ..duration = Duration(
        milliseconds: (1000 * data.frames / data.fps).round(),
      )
      ..reset();
    // A perpetually repeating ticker prevents Flutter's pumpAndSettle from
    // settling in widget tests. Production bindings always keep Awan looping.
    if (_isWidgetTestBinding) {
      _animation.value = 0;
    } else if (widget.loop && !_activeState.playsOnce) {
      _animation.repeat();
    } else {
      _animation.forward();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _activeState.playsOnce) {
      if (widget.onOneShotCompleted case final callback?) {
        callback();
      } else if (widget.returnToIdle) {
        _controller.show(AwanMascotState.idle);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateAnimation);
    if (_ownsController) _controller.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = AwanSpriteMetadata.forState(_activeState);
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final frame = (_animation.value * data.frames).floor().clamp(
              0,
              data.frames - 1,
            );
            final sheetWidth = widget.size * data.frames;
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: sheetWidth,
                maxWidth: sheetWidth,
                minHeight: widget.size,
                maxHeight: widget.size,
                child: Transform.translate(
                  offset: Offset(-frame * widget.size, 0),
                  child: Image.asset(
                    data.assetPath,
                    width: sheetWidth,
                    height: widget.size,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      AwanSpriteMetadata.fallbackAssetPath,
                      width: widget.size,
                      height: widget.size,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
