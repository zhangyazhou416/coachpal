import 'package:flutter/material.dart';

/// 与网页看板一致的配色（dataviz 校验过的系列色）。
class AppPalette {
  static const series1 = Color(0xFF2A78D6);
  static const series2 = Color(0xFFEB6834);
  static const series3 = Color(0xFF1BAF7A);
  static const series4 = Color(0xFFEDA100);
  static const statusGood = Color(0xFF0CA30C);
  static const statusWarn = Color(0xFFFAB219);
  static const statusBad = Color(0xFFD03B3B);
}

ThemeData buildLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppPalette.series1,
      secondary: AppPalette.series2,
      surface: const Color(0xFFFCFCFB),
    ),
    scaffoldBackgroundColor: const Color(0xFFF9F9F7),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFFFCFCFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFF3987E5),
      secondary: const Color(0xFFD95926),
      surface: const Color(0xFF1A1A19),
    ),
    scaffoldBackgroundColor: const Color(0xFF0D0D0D),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF1A1A19),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
    ),
  );
}
