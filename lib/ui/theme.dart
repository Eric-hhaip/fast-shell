import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 配色：浅色工作台 + 深色终端
class AppColors {
  const AppColors._();

  static const canvas = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFF2F3F6);
  static const chrome = Color(0xFFF2F3F6);
  static const border = Color(0xFFE4E6EB);
  static const borderSoft = Color(0xFFEDEFF2);

  static const textPrimary = Color(0xFF1B1F26);
  static const textSecondary = Color(0xFF5C6470);
  static const textTertiary = Color(0xFF969DAA);

  static const accent = Color(0xFF2F6BFF);
  static const accentSoft = Color(0xFFE9F0FF);
  static const accentDeep = Color(0xFF1F51CC);

  static const success = Color(0xFF12A150);
  static const successSoft = Color(0xFFE6F6EC);
  static const warning = Color(0xFFE0A02E);
  static const danger = Color(0xFFD93B3B);
  static const dangerSoft = Color(0xFFFDECEC);

  static const terminalBackdrop = Color(0xFF0D1626);
}

class AppText {
  const AppText._();

  static const h1 = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: AppColors.textPrimary,
  );
  static const bodyStrong = TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const secondary = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.textSecondary,
  );
  static const tertiary = TextStyle(
    fontSize: 11.5,
    height: 1.4,
    color: AppColors.textTertiary,
  );
  static const mono = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontFamily: 'SF Mono',
    fontFamilyFallback: ['Menlo', 'Monaco', 'monospace'],
    color: AppColors.textSecondary,
  );
}

/// 终端配色（深蓝黑底 + 高亮 ANSI 调色板）
const appTerminalTheme = TerminalTheme(
  cursor: Color(0xFF8AB4FF),
  selection: Color(0x663B6BD8),
  foreground: Color(0xFFDCE5F2),
  background: Color(0xFF0D1626),
  black: Color(0xFF1B2230),
  red: Color(0xFFEF6B6B),
  green: Color(0xFF5ACC7E),
  yellow: Color(0xFFF0C05A),
  blue: Color(0xFF6FA8FF),
  magenta: Color(0xFFD084E8),
  cyan: Color(0xFF52C4D4),
  white: Color(0xFFDCE5F2),
  brightBlack: Color(0xFF6B7686),
  brightRed: Color(0xFFFF8F8F),
  brightGreen: Color(0xFF8FE8A2),
  brightYellow: Color(0xFFFFDD8F),
  brightBlue: Color(0xFFA3C6FF),
  brightMagenta: Color(0xFFEBB2F6),
  brightCyan: Color(0xFF84DCE8),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF3D6BD8),
  searchHitBackgroundCurrent: Color(0xFF8AB4FF),
  searchHitForeground: Color(0xFFFFFFFF),
);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF232A35),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintStyle: AppText.tertiary,
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.accent),
      errorBorder: _inputBorder(AppColors.danger),
      focusedErrorBorder: _inputBorder(AppColors.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textTertiary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
        ),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: AppText.body,
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : Colors.transparent,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.all(AppColors.border),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(7),
  borderSide: BorderSide(color: color),
);
