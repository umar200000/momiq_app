import 'package:flutter/material.dart';

enum _ButtonKind { filled, outlined, text }

/// Native button semantics with immediate press feedback and drag-out cancel.
class PressableButton extends StatefulWidget {
  const PressableButton({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.style,
  }) : _kind = _ButtonKind.filled,
       icon = null,
       label = null;
  const PressableButton.outlinedIcon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget this.label,
    this.style,
  }) : _kind = _ButtonKind.outlined,
       child = null;
  const PressableButton.text({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.style,
  }) : _kind = _ButtonKind.text,
       icon = null,
       label = null;
  final VoidCallback? onPressed;
  final Widget? child, icon, label;
  final ButtonStyle? style;
  final _ButtonKind _kind;
  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton> {
  final _bounds = GlobalKey();
  final _states = WidgetStatesController();
  int? _pointer;
  bool _cancelled = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_stateChanged);
  }

  void _stateChanged() =>
      _setPressed(!_cancelled && _states.value.contains(WidgetState.pressed));
  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  bool _inside(Offset position) {
    final box = _bounds.currentContext?.findRenderObject() as RenderBox?;
    return box != null &&
        (Offset.zero & box.size).contains(box.globalToLocal(position));
  }

  void _end(PointerEvent event, {bool cancelled = false}) {
    if (event.pointer != _pointer) return;
    _cancelled = _cancelled || cancelled || !_inside(event.position);
    _pointer = null;
    _setPressed(false);
    // Keep cancellation latched through native onPressed dispatch this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointer == null) _cancelled = false;
    });
  }

  void _activate() {
    if (!_cancelled) widget.onPressed?.call();
  }

  @override
  void didUpdateWidget(covariant PressableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPressed == null && widget.onPressed != null) {
      _cancelled = false;
    }
    if (widget.onPressed == null) {
      _pressed = false;
      _cancelled = true;
    }
  }

  @override
  void dispose() {
    _states.removeListener(_stateChanged);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.onPressed == null ? null : _activate;
    final button = switch (widget._kind) {
      _ButtonKind.filled => FilledButton(
        onPressed: action,
        statesController: _states,
        style: widget.style,
        child: widget.child!,
      ),
      _ButtonKind.outlined => OutlinedButton.icon(
        onPressed: action,
        statesController: _states,
        style: widget.style,
        icon: widget.icon!,
        label: widget.label!,
      ),
      _ButtonKind.text => TextButton(
        onPressed: action,
        statesController: _states,
        style: widget.style,
        child: widget.child!,
      ),
    };
    return Listener(
      key: _bounds,
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (widget.onPressed == null) return;
        if (_pointer != null) {
          _cancelled = true;
          _setPressed(false);
          return;
        }
        _pointer = event.pointer;
        _cancelled = false;
        _setPressed(true);
      },
      onPointerMove: (event) {
        if (event.pointer == _pointer && !_inside(event.position)) {
          _cancelled = true;
          _setPressed(false);
        }
      },
      onPointerUp: _end,
      onPointerCancel: (event) => _end(event, cancelled: true),
      child: AnimatedScale(
        scale: _pressed && widget.onPressed != null ? .94 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Duration(milliseconds: _pressed ? 100 : 160),
        curve: Curves.easeOutCubic,
        child: button,
      ),
    );
  }
}
