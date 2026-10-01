import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF292725);
  static const muted = Color(0xFF77716B);
  static const rose = Color(0xFF286C61);
  static const blush = Color(0xFFDCE9E2);
  static const lavender = Color(0xFFC8D8CE);
  static const cream = Color(0xFFEEF2EE);
  static const line = Color(0xFFCFD9D2);
  static const brandBackground = Color(0xFFB8C9BD);
}

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark
      ? const ColorScheme.dark(
          primary: Color(0xFF8FD5C5),
          onPrimary: Color(0xFF07372F),
          primaryContainer: Color(0xFF205048),
          onPrimaryContainer: Color(0xFFB2F1E2),
          secondary: Color(0xFFB2CCC4),
          secondaryContainer: Color(0xFF354B45),
          onSecondaryContainer: Color(0xFFD8EAE4),
          surface: Color(0xFF1A1D1C),
          onSurface: Color(0xFFE4E7E4),
          surfaceContainerHighest: Color(0xFF303432),
          outline: Color(0xFF89938F),
          outlineVariant: Color(0xFF414946),
          error: Color(0xFFFFB4AB),
        )
      : const ColorScheme.light(
          primary: AppColors.rose,
          onPrimary: Colors.white,
          primaryContainer: AppColors.blush,
          onPrimaryContainer: Color(0xFF183D37),
          secondary: Color(0xFF4F7168),
          secondaryContainer: AppColors.lavender,
          onSecondaryContainer: Color(0xFF343B34),
          surface: Colors.white,
          onSurface: AppColors.ink,
          surfaceContainerHighest: Color(0xFFF0EDE7),
          outline: AppColors.line,
          outlineVariant: Color(0xFFEDE8E1),
          error: Color(0xFFBA3A49),
        );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark ? const Color(0xFF111413) : AppColors.cream,
    fontFamilyFallback: const [
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
    ],
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.55,
        color: isDark ? const Color(0xFFB7BFBB) : AppColors.muted,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: isDark ? const Color(0xFFB7BFBB) : AppColors.muted,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF111413) : AppColors.cream,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFFB7BFBB) : AppColors.muted,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.rose,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFFB7BFBB) : AppColors.muted,
        fontSize: 14,
        height: 1.5,
      ),
      helperStyle: TextStyle(
        color: isDark ? const Color(0xFFB7BFBB) : AppColors.muted,
        fontSize: 12,
        height: 1.4,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.rose, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? scheme.primary : AppColors.ink,
        foregroundColor: isDark ? scheme.onPrimary : Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        foregroundColor: scheme.onSurface,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surface,
      selectedColor: AppColors.blush,
      disabledColor: const Color(0xFFF0EDE7),
      checkmarkColor: AppColors.rose,
      deleteIconColor: AppColors.muted,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        color: AppColors.rose,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: const IconThemeData(color: AppColors.muted, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.blush,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? AppColors.rose
              : AppColors.muted,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.rose
              : AppColors.muted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line),
  );
}
