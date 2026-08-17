// lib/theme.dart
//
// 제공해주신 HTML 목업(디자인)의 색상값을 그대로 옮긴 테마 상수입니다.

import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF735BF2);
  static const primaryDark = Color(0xFF6046E8);
  static const background = Color(0xFFFAFAFE);
  static const inputBg = Color(0xFFF0F1FD);
  static const inputBorder = Color(0xFFDFE2FA);
  static const inputHint = Color(0xFF9AA0C2);
  static const cardBorder = Color(0xFFECEEF9);
  static const textDark = Color(0xFF1E202B);
  static const textMuted = Color(0xFF8C90A8);
  static const textFaint = Color(0xFF9295AA);
  static const saturday = Color(0xFF5B72F2);
  static const sunday = Color(0xFFE66767);
  static const danger = Color(0xFFDE4C4C);
  static const dangerBorder = Color(0xFFF6D6D6);
  static const dangerText = Color(0xFFE66767);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    ),
    fontFamily: 'Pretendard',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textDark,
      elevation: 0,
    ),
  );
}

InputDecoration appInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.inputHint),
    filled: true,
    fillColor: AppColors.inputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}

ButtonStyle primaryButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(56),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
    elevation: 4,
    shadowColor: AppColors.primary.withOpacity(0.3),
  );
}
