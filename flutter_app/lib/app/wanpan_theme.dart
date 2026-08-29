import 'package:flutter/material.dart';

abstract final class WanpanColors {
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF5F6F7);
  static const surfaceMuted = Color(0xFFECEEF0);
  static const ink = Color(0xFF17191C);
  static const inkSecondary = Color(0xFF5F666D);
  static const muted = Color(0xFF858B91);
  static const coral = Color(0xFFF2674F);
  static const coralStrong = Color(0xFFDC513B);
  static const coralSoft = Color(0xFFFFF1ED);
  static const gold = Color(0xFFE9B440);
  static const goldSoft = Color(0xFFFFF7DD);
  static const success = Color(0xFF3F8C67);
  static const danger = Color(0xFFC94C3F);
  static const border = Color(0x1A17191C);
  static const borderStrong = Color(0x2E17191C);
}

abstract final class WanpanRadii {
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 22.0;
  static const pill = 999.0;
}

abstract final class WanpanSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const page = 20.0;
}

abstract final class WanpanTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: WanpanColors.coral,
      onPrimary: Colors.white,
      primaryContainer: WanpanColors.coralSoft,
      onPrimaryContainer: WanpanColors.coralStrong,
      secondary: WanpanColors.gold,
      onSecondary: WanpanColors.ink,
      secondaryContainer: WanpanColors.goldSoft,
      onSecondaryContainer: WanpanColors.ink,
      surface: WanpanColors.surface,
      onSurface: WanpanColors.ink,
      error: WanpanColors.danger,
      onError: Colors.white,
      outline: WanpanColors.borderStrong,
      outlineVariant: WanpanColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: WanpanColors.canvas,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: WanpanColors.canvas,
        foregroundColor: WanpanColors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: WanpanColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: WanpanColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: WanpanColors.coralSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? WanpanColors.coralStrong : WanpanColors.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? WanpanColors.coral : WanpanColors.muted,
            size: 24,
          );
        }),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: WanpanColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: WanpanColors.border),
          borderRadius: BorderRadius.all(Radius.circular(WanpanRadii.large)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: WanpanColors.surfaceSoft,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: WanpanColors.muted),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(WanpanRadii.medium)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: WanpanColors.border),
          borderRadius: BorderRadius.all(Radius.circular(WanpanRadii.medium)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: WanpanColors.coral, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(WanpanRadii.medium)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: WanpanColors.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: const DialogThemeData(
        elevation: 0,
        backgroundColor: WanpanColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WanpanColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: WanpanColors.surface,
        modalBarrierColor: Color(0x5217191C),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    displaySmall: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 34,
      height: 1.08,
      fontWeight: FontWeight.w900,
      letterSpacing: -1,
    ),
    headlineMedium: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 25,
      height: 1.18,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    ),
    titleLarge: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.25,
    ),
    titleMedium: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w800,
    ),
    bodyLarge: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: const TextStyle(
      color: WanpanColors.inkSecondary,
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 15,
      height: 1.2,
      fontWeight: FontWeight.w900,
    ),
    labelMedium: const TextStyle(
      color: WanpanColors.muted,
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
  );
}
