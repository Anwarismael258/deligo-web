import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared viewport facts derived from the space a widget actually receives.
///
/// Use this instead of making layout decisions from device-specific pixel
/// coordinates. It intentionally does not enforce an orientation.
@immutable
class DeligoViewport {
  const DeligoViewport({required this.width, required this.height});

  factory DeligoViewport.fromConstraints(BoxConstraints constraints) {
    return DeligoViewport(
      width: constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
      height: constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
    );
  }

  factory DeligoViewport.fromSize(Size size) =>
      DeligoViewport(width: size.width, height: size.height);

  final double width;
  final double height;

  bool get isLandscape => width > height;
  bool get isNarrow => width < 380;
  bool get isShort => height < 500;
  bool get isCompact => isNarrow || isShort;

  /// Caps a preferred panel height to the actual available viewport height.
  /// The optional minimum is also capped, so it can never exceed constraints.
  double boundedHeight({
    required double preferred,
    required double fraction,
    double minimum = 0,
  }) {
    final available = math.max(0.0, height * fraction).toDouble();
    return math
        .min(available, math.max(minimum, math.min(preferred, available)))
        .toDouble();
  }
}

/// A vertical region that yields space to its siblings and scrolls its content
/// instead of overflowing when the available height becomes short.
class DeligoViewportScrollArea extends StatelessWidget {
  const DeligoViewportScrollArea({
    super.key,
    required this.child,
    this.maxHeightFraction = 1,
    this.maxHeight,
    this.padding,
  }) : assert(maxHeightFraction > 0 && maxHeightFraction <= 1);

  final Widget child;
  final double maxHeightFraction;
  final double? maxHeight;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final boundedHeight = availableHeight.isFinite
            ? availableHeight
            : MediaQuery.sizeOf(context).height;
        final fractionLimit = boundedHeight * maxHeightFraction;
        final heightLimit =
            (maxHeight == null
                    ? fractionLimit
                    : math.min(fractionLimit, maxHeight!))
                .toDouble();
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: heightLimit),
          child: SingleChildScrollView(padding: padding, child: child),
        );
      },
    );
  }
}
