import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF050506);
  static const Color backgroundElevated = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF101013);
  static const Color surfaceSoft = Color(0xFF151519);
  static const Color surfaceMuted = Color(0xFF1C1B21);
  static const Color surfaceRaised = Color(0xFF222027);
  static const Color surfaceHighest = Color(0xFF2A2228);
  static const Color stroke = Color(0xFF2C2A31);
  static const Color strokeSoft = Color(0xFF44343A);
  static const Color accent = Color(0xFFE51B2D);
  static const Color accent2 = Color(0xFFFF3F4F);
  static const Color accentWarm = Color(0xFFFF6A3D);
  static const Color textPrimary = Color(0xFFF7F7F8);
  static const Color textSecondary = Color(0xFFC4C0C5);
  static const Color textMuted = Color(0xFF858089);
  static const Color danger = Color(0xFFFF5C70);

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;

  static List<BoxShadow> premiumShadow({Color? color, double alpha = 0.18}) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.34),
        blurRadius: 34,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: (color ?? accent).withValues(alpha: alpha),
        blurRadius: 32,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      surface: surface,
      error: danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      hoverColor: accent.withValues(alpha: 0.05),
      focusColor: accent.withValues(alpha: 0.08),
      highlightColor: accent.withValues(alpha: 0.06),
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 46,
          fontWeight: FontWeight.w800,
          height: 1.02,
          letterSpacing: 0,
          color: textPrimary,
        ),
        displaySmall: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: 0,
          color: textPrimary,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: 0,
          color: textPrimary,
        ),
        headlineSmall: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.45,
          color: textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: textSecondary,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: textMuted,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: textPrimary,
        ),
        labelMedium: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: stroke),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: stroke,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHighest,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(color: strokeSoft),
        ),
        textStyle: const TextStyle(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoft.withValues(alpha: 0.96),
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: danger),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
          minimumSize: WidgetStateProperty.all(const Size(0, 52)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return accent.withValues(alpha: 0.4);
            }
            if (states.contains(WidgetState.hovered)) {
              return accent2;
            }
            return accent;
          }),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          overlayColor: WidgetStateProperty.all(
            accentWarm.withValues(alpha: 0.08),
          ),
          foregroundColor: WidgetStateProperty.all(textPrimary),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 54)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          foregroundColor: WidgetStateProperty.all(textPrimary),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return const BorderSide(color: strokeSoft);
            }
            return const BorderSide(color: stroke);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return surfaceMuted.withValues(alpha: 0.76);
            }
            return surfaceSoft.withValues(alpha: 0.62);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(textSecondary),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceSoft,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(surfaceSoft),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
          side: WidgetStateProperty.all(const BorderSide(color: stroke)),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent2,
        inactiveTrackColor: Color(0xFF2A262B),
        thumbColor: Colors.white,
        overlayColor: Color(0x33FF2332),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 3,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: stroke,
        circularTrackColor: stroke,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
