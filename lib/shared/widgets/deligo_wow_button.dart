import 'package:flutter/material.dart';

import '../../config/theme/app_colors.dart';
import 'deligo_pressable.dart';

class DeligoWowButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;
  final BorderRadius borderRadius;

  const DeligoWowButton({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.height = 56,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  @override
  Widget build(BuildContext context) {
    final isActive = enabled && onTap != null;

    return AnimatedOpacity(
      opacity: isActive ? 1 : 0.6,
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryGreen,
              AppColors.primaryRed,
              AppColors.accentYellow,
            ],
            stops: [0, 0.7, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.accentYellow.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: DeligoPressable(
          onTap: isActive ? onTap : null,
          borderRadius: borderRadius,
          pressedScale: 0.96,
          splashColor: AppColors.accentYellow.withValues(alpha: 0.24),
          overlayColor: AppColors.cleanWhite.withValues(alpha: 0.14),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: AppColors.cleanWhite.withValues(alpha: 0.14),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
