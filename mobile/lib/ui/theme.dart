import 'package:flutter/material.dart';

abstract final class MutColors {
  static const background = Color(0xff151718);
  static const surface = Color(0xff222527);
  static const raised = Color(0xff2a2d2f);
  static const dock = Color(0xff202325);
  static const text = Color(0xffe8eaeb);
  static const muted = Color(0xffa6acaf);
  static const accent = Color(0xffb8bec1);
  static const edge = Color(0x26e8eaeb);
  static const paper = Color(0xffe8e8e3);
  static const ink = Color(0xff303331);
  static const covers = [
    Color(0xff383e41),
    Color(0xff798184),
    Color(0xff5f666a),
    Color(0xff878d90),
    Color(0xff737b7f),
    Color(0xff52595d),
  ];
}

ThemeData mutTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: MutColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: MutColors.surface,
        primary: MutColors.accent,
        onPrimary: MutColors.background,
        onSurface: MutColors.text,
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Onest',
    colorScheme: scheme,
    scaffoldBackgroundColor: MutColors.background,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: MutColors.text),
      bodySmall: TextStyle(fontSize: 13, color: MutColors.muted),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.18,
        fontWeight: FontWeight.w600,
        letterSpacing: -.84,
      ),
    ),
    dividerColor: MutColors.edge,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MutColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MutColors.surface,
      hintStyle: const TextStyle(color: MutColors.muted, fontSize: 15),
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: MutColors.edge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: MutColors.edge),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MutColors.accent,
        foregroundColor: MutColors.background,
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MutColors.surface,
      selectedColor: MutColors.accent,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
