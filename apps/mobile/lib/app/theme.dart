import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF27212D);
  static const muted = Color(0xFF756D7B);
  static const rose = Color(0xFFD95F87);
  static const blush = Color(0xFFFFE8EF);
  static const lavender = Color(0xFFEDE7FF);
  static const cream = Color(0xFFFFFAF7);
  static const line = Color(0xFFEAE3E8);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.rose,
    onPrimary: Colors.white,
    primaryContainer: AppColors.blush,
    onPrimaryContainer: Color(0xFF6D2941),
    secondary: Color(0xFF8066B2),
    secondaryContainer: AppColors.lavender,
    onSecondaryContainer: Color(0xFF3D2C62),
    surface: Colors.white,
    onSurface: AppColors.ink,
    surfaceContainerHighest: Color(0xFFF5F0F4),
    outline: AppColors.line,
    outlineVariant: Color(0xFFF2EBEF),
    error: Color(0xFFBA3A49),
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.cream,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC'],
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: AppColors.ink),
      headlineMedium: const TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.ink),
      titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
      bodyLarge: const TextStyle(fontSize: 16, height: 1.55, color: AppColors.muted),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppColors.rose, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AppColors.blush,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.blush,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        color: states.contains(WidgetState.selected) ? AppColors.rose : AppColors.muted,
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? AppColors.rose : AppColors.muted,
      )),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line),
  );
}
