import 'package:flutter/material.dart';

import '../domain/l10n.dart';

/// AURA brand palette.
class Aura {
  static const ink = Color(0xFF101A28);
  static const gold = Color(0xFFD19104);
  static const goldLight = Color(0xFFEAB02E);
  static const goldBg = Color(0xFFFBF1D9);
  static const paper = Color(0xFFF6F4EE);
  static const line = Color(0xFFE4E1D9);
  static const muted = Color(0xFF5E6878);
  static const ok = Color(0xFF0F7A4A);
  static const okBg = Color(0xFFE2F4EA);
  static const warn = Color(0xFFB3321F);
  static const warnBg = Color(0xFFFDE7E3);
  static const blue = Color(0xFF1C4587);
  static const blueBg = Color(0xFFE8EEF8);
}

ThemeData auraTheme([AppLang lang = AppLang.he]) {
  final font = lang == AppLang.ar ? 'Cairo' : 'Rubik';
  final scheme = ColorScheme.fromSeed(seedColor: Aura.goldLight, brightness: Brightness.light).copyWith(
    primary: Aura.ink,
    onPrimary: Colors.white,
    secondary: Aura.goldLight,
    onSecondary: Aura.ink,
    surface: Colors.white,
    onSurface: Aura.ink,
    error: Aura.warn,
    outlineVariant: Aura.line,
  );
  // Cairo has no Hebrew letters or ₪ sign, so names and amounts fall back to Rubik.
  final fb = font == 'Rubik' ? null : const ['Rubik'];
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: font, fontFamilyFallback: fb);
  return base.copyWith(
    splashFactory: InkRipple.splashFactory,
    scaffoldBackgroundColor: Aura.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: Aura.paper,
      foregroundColor: Aura.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 18, fontWeight: FontWeight.w600, color: Aura.ink),
    ),
    textTheme: base.textTheme.apply(bodyColor: Aura.ink, displayColor: Aura.ink, fontFamily: font, fontFamilyFallback: fb),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Aura.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        textStyle: TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Aura.ink,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Aura.line),
        textStyle: TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 15, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: Aura.ink,
      labelStyle: TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 13.5, color: Aura.ink),
      secondaryLabelStyle: TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 13.5, color: Colors.white),
      side: const BorderSide(color: Aura.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Aura.line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Aura.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Aura.gold, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Aura.goldBg,
      labelTextStyle: WidgetStateProperty.all(TextStyle(fontFamily: font, fontFamilyFallback: fb, fontSize: 12, fontWeight: FontWeight.w500)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor:
          WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Aura.ok : const Color(0xFFCBC8C0)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(color: Aura.line, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Aura.ink),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true),
  );
}
