import 'package:flutter/material.dart';

import '../../config/theme/app_colors.dart';

class DeligoPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? splashColor;
  final Color? overlayColor;
  final double pressedScale;
  final Duration duration;

  const DeligoPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.splashColor,
    this.overlayColor,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  State<DeligoPressable> createState() => _DeligoPressableState();
}

class _DeligoPressableState extends State<DeligoPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final splash = widget.splashColor ?? AppColors.rippleBase;
    final overlay = widget.overlayColor ?? AppColors.rippleInteractive;

    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius,
          splashColor: splash,
          highlightColor: overlay.withValues(alpha: 0.10),
          onHighlightChanged: _setPressed,
          child: widget.child,
        ),
      ),
    );
  }
}
