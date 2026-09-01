import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF6750A4);
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF8F7FC),
  );
}

