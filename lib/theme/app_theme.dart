import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF08090B);
  static const panel = Color(0xFF17191D);
  static const raised = Color(0xFF24272D);
  static const foreground = Color(0xFFF2F3F5);
  static const muted = Color(0xFFA0A4AD);
  static const recording = Color(0xFFFF626B);
  static const radius = 20.0;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: foreground,
      onPrimary: background,
      secondary: muted,
      onSecondary: background,
      surface: panel,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerHighest: raised,
      outline: Color(0xFF3A3E46),
      outlineVariant: raised,
      error: recording,
      onError: background,
    );
    const rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: panel,
      dividerColor: raised,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        showDragHandle: true,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: raised,
        disabledColor: panel,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: const TextStyle(color: foreground, fontSize: 12),
        checkmarkColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: foreground,
        inactiveTrackColor: raised,
        thumbColor: foreground,
        trackHeight: 3,
      ),
      switchTheme: const SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: raised,
          foregroundColor: foreground,
          shape: rounded,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: TextStyle(color: foreground),
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
    );
  }
}
