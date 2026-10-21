import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppTheme {
  static final light = _theme(Brightness.light);
  static final dark = _theme(Brightness.dark);

  static ThemeMode mode(String preference) => switch (preference) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String label(String preference) => switch (preference) {
    'light' => '浅色',
    'dark' => '深色',
    _ => '跟随系统',
  };

  static SystemUiOverlayStyle systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    // 深色走冷灰分层，贴近影视墙，而不是纯黑或暖灰。强调色仍用原橙色。
    final background = dark ? const Color(0xFF121416) : const Color(0xFFFAF8F6);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF664F),
      brightness: brightness,
      primary: dark ? const Color(0xFFFF765F) : const Color(0xFFAD3826),
      onPrimary: dark ? const Color(0xFF3B0E07) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF5C3027)
          : const Color(0xFFFFE0D8),
      onPrimaryContainer: dark
          ? const Color(0xFFFFE0D8)
          : const Color(0xFF4B160D),
      tertiary: dark ? const Color(0xFFF6C86B) : const Color(0xFF805500),
      surface: dark ? const Color(0xFF1A1C1F) : Colors.white,
      onSurface: dark ? const Color(0xFFF3F4F6) : const Color(0xFF252328),
      onSurfaceVariant: dark
          ? const Color(0xFFA7ADB4)
          : const Color(0xFF68636C),
      outline: dark ? const Color(0xFF8B9198) : const Color(0xFF7C757D),
      outlineVariant: dark ? const Color(0xFF2A2E33) : const Color(0xFFE3DFDC),
      surfaceContainerLowest: dark ? const Color(0xFF0E1012) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xFF17191C)
          : const Color(0xFFF7F3F0),
      surfaceContainer: dark
          ? const Color(0xFF1E2125)
          : const Color(0xFFF2EEEB),
      surfaceContainerHigh: dark
          ? const Color(0xFF262A2E)
          : const Color(0xFFEDE8E5),
      surfaceContainerHighest: dark
          ? const Color(0xFF31363B)
          : const Color(0xFFE6E0DC),
      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemBars(brightness),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        useIndicator: false,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
