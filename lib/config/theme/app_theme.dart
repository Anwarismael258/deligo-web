import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration emphasis = Duration(milliseconds: 340);

  static ThemeData get lightTheme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primaryRed,
          onPrimary: AppColors.cleanWhite,
          secondary: AppColors.primaryGreen,
          onSecondary: AppColors.cleanWhite,
          error: AppColors.alertRed,
          onError: AppColors.cleanWhite,
          surface: AppColors.cleanWhite,
          onSurface: AppColors.deepBlack,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.clientBackground,
      splashFactory: InkRipple.splashFactory,
      splashColor: AppColors.rippleBase,
      highlightColor: AppColors.rippleInteractive.withValues(alpha: 0.10),
      dividerColor: AppColors.borderGray,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _DeligoPageTransitionsBuilder(),
          TargetPlatform.iOS: _DeligoPageTransitionsBuilder(),
          TargetPlatform.linux: _DeligoPageTransitionsBuilder(),
          TargetPlatform.macOS: _DeligoPageTransitionsBuilder(),
          TargetPlatform.windows: _DeligoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.cleanWhite,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        shadowColor: AppColors.deepBlack.withValues(alpha: 0.08),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          animationDuration: normal,
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(54)),
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          elevation: const MaterialStatePropertyAll(0),
          shadowColor: MaterialStatePropertyAll(
            AppColors.primaryRed.withValues(alpha: 0.20),
          ),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return AppColors.primaryGreen.withValues(alpha: 0.45);
            }
            if (states.contains(MaterialState.pressed)) {
              return const Color(0xFFC62828);
            }
            return AppColors.primaryRed;
          }),
          foregroundColor: const MaterialStatePropertyAll(AppColors.cleanWhite),
          overlayColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return AppColors.accentYellow.withValues(alpha: 0.18);
            }
            if (states.contains(MaterialState.hovered)) {
              return AppColors.cleanWhite.withValues(alpha: 0.06);
            }
            return null;
          }),
          shape: MaterialStateProperty.resolveWith((states) {
            final radius = states.contains(MaterialState.pressed) ? 12.0 : 16.0;
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            );
          }),
          textStyle: const MaterialStatePropertyAll(
            TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: AppColors.primaryRed,
          foregroundColor: AppColors.cleanWhite,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: normal,
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(52)),
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          foregroundColor: const MaterialStatePropertyAll(AppColors.primaryRed),
          side: MaterialStateProperty.resolveWith((states) {
            final color = states.contains(MaterialState.pressed)
                ? AppColors.primaryRed
                : AppColors.primaryRed.withValues(alpha: 0.72);
            return BorderSide(color: color, width: 1.2);
          }),
          overlayColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return AppColors.primaryRed.withValues(alpha: 0.10);
            }
            return null;
          }),
          shape: const MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          textStyle: const MaterialStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: AppColors.cleanWhite,
        selectedTileColor: AppColors.primaryGreen.withValues(alpha: 0.08),
        iconColor: AppColors.deepBlack,
        textColor: AppColors.deepBlack,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cleanWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _inputBorder(AppColors.borderGray),
        enabledBorder: _inputBorder(AppColors.borderGray),
        focusedBorder: _inputBorder(AppColors.primaryRed, width: 1.6),
        errorBorder: _inputBorder(AppColors.alertRed),
        focusedErrorBorder: _inputBorder(AppColors.alertRed, width: 1.6),
        labelStyle: const TextStyle(color: AppColors.neutralGray),
        hintStyle: TextStyle(
          color: AppColors.neutralGray.withValues(alpha: 0.88),
        ),
        prefixIconColor: AppColors.neutralGray,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.deepBlack,
          height: 1.05,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.deepBlack,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.deepBlack,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.deepBlack,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppColors.deepBlack,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.neutralGray,
          height: 1.35,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.cleanWhite,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryGreen,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.deepBlack,
        contentTextStyle: const TextStyle(
          color: AppColors.cleanWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.accentYellow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cleanWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );

    final manrope = GoogleFonts.manropeTextTheme(base.textTheme);
    // DeliGo typography scale: keep content compact and predictable across
    // client, restaurant and courier surfaces. Components should use these
    // semantic styles instead of inventing larger local sizes.
    final deligoTypography = manrope.copyWith(
      displayLarge: manrope.displayLarge?.copyWith(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: manrope.headlineMedium?.copyWith(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: manrope.titleLarge?.copyWith(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: manrope.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: manrope.titleSmall?.copyWith(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: manrope.bodyLarge?.copyWith(
        fontSize: 14,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: manrope.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: manrope.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: manrope.labelLarge?.copyWith(
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: manrope.labelMedium?.copyWith(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: manrope.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.25,
        fontWeight: FontWeight.w400,
      ),
    );
    final spaceGroteskTitle = GoogleFonts.spaceGrotesk(
      color: AppColors.cleanWhite,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );

    return base.copyWith(
      textTheme: deligoTypography,
      appBarTheme: base.appBarTheme.copyWith(titleTextStyle: spaceGroteskTitle),
      extensions: const <ThemeExtension<dynamic>>[],
    );
  }

  /// Web-only presentation theme shared by Guest, Client, Restaurant and
  /// Courier surfaces. Native builds keep the established light theme.
  static ThemeData get webTheme {
    final base = lightTheme;
    final darkScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D0A),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFFF4D0A),
          secondary: const Color(0xFFFFB000),
          surface: const Color(0xFF07152D),
          onSurface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: darkScheme,
      scaffoldBackgroundColor: const Color(0xFF020817),
      canvasColor: const Color(0xFF020817),
      cardColor: const Color(0xFF07152D),
      dialogBackgroundColor: const Color(0xFF07152D),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF020817),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xFF07152D),
        labelStyle: const TextStyle(color: Colors.white),
        hintStyle: const TextStyle(color: Color(0xFF8BA4C6)),
        prefixIconColor: const Color(0xFFB9D7FF),
        enabledBorder: _inputBorder(const Color(0xFF2D5A91)),
        focusedBorder: _inputBorder(const Color(0xFFFF4D0A), width: 1.8),
      ),
      dividerColor: const Color(0xFF234875),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _DeligoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _DeligoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final slide = Tween<Offset>(
      begin: const Offset(0.03, 0.02),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
