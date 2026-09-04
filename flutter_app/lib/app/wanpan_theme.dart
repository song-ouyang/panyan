import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class WanpanColors {
  static const canvas = Color(0xFFFFF8E9);
  static const surface = Color(0xFFFFFDF7);
  static const surfaceSoft = Color(0xFFFFF5E7);
  static const surfaceMuted = Color(0xFFF5E8D6);
  static const ink = Color(0xFF24343C);
  static const catBlack = Color(0xFF171A1E);
  static const inkSecondary = Color(0xFF69777E);
  static const muted = Color(0xFF8B969B);
  static const coral = Color(0xFFFF6B52);
  static const coralStrong = Color(0xFFD94F3A);
  static const coralSoft = Color(0xFFFFE5DC);
  static const sky = Color(0xFF70C9E8);
  static const skySoft = Color(0xFFDDF4FA);
  static const grape = Color(0xFF9A78E8);
  static const grapeSoft = Color(0xFFEDE5FF);
  static const sunflower = Color(0xFFFFC943);
  static const sunflowerSoft = Color(0xFFFFF1BF);
  static const mint = Color(0xFF9DD5B0);
  static const mintSoft = Color(0xFFE2F3E7);
  static const gold = sunflower;
  static const goldSoft = sunflowerSoft;
  static const success = Color(0xFF4C9A6A);
  static const danger = Color(0xFFC84D43);
  static const border = Color(0xFFE9DCC7);
  static const borderStrong = Color(0xFFD9C7AF);
}

abstract final class WanpanRadii {
  static const small = 14.0;
  static const medium = 18.0;
  static const large = 24.0;
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
      onPrimary: WanpanColors.ink,
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
      highlightColor: Colors.transparent,
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
        height: 76,
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: WanpanColors.surface,
        selectedColor: WanpanColors.coralSoft,
        disabledColor: WanpanColors.surfaceMuted,
        side: BorderSide(color: WanpanColors.border),
        shape: StadiumBorder(),
        labelStyle: TextStyle(
          color: WanpanColors.inkSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: WanpanColors.coral,
        selectionColor: WanpanColors.coralSoft,
        selectionHandleColor: WanpanColors.coral,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: WanpanColors.coral,
        linearTrackColor: WanpanColors.coralSoft,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    displaySmall: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 32,
      height: 1.08,
      fontWeight: FontWeight.w900,
      letterSpacing: -1,
    ),
    headlineMedium: const TextStyle(
      color: WanpanColors.ink,
      fontSize: 24,
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
      fontWeight: FontWeight.w600,
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
