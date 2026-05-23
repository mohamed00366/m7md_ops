import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 🎨 AppColors - الآن يشير إلى AppPalette الموحّد (M7 NEXUS branding)
/// (الأسماء محفوظة للتوافق مع الكود القديم)
class AppColors {
  AppColors._();

  // ===== Brand =====
  static const brand = AppPalette.brand;
  static const brandDark = AppPalette.brandDark;
  static const brandAccent = AppPalette.brandLight;

  // ===== Gold =====
  static const gold = AppPalette.gold;
  static const goldLight = AppPalette.goldLight;

  // ===== Semantic =====
  static const success = AppPalette.success;
  static const warning = AppPalette.amberDark;
  static const danger = AppPalette.danger;
  static const info = AppPalette.info;
  static const purple = AppPalette.purple;
  static const teal = AppPalette.teal;

  // ===== Light theme =====
  static const bgLight = AppPalette.surface;
  static const surfaceLight = AppPalette.card;
  static const surface2Light = AppPalette.input;
  static const borderLight = AppPalette.border;
  static const textLight = AppPalette.text;
  static const textSecondaryLight = AppPalette.textSecondary;
  static const textTertiaryLight = AppPalette.textTertiary;

  // ===== Dark theme =====
  static const bgDark = AppPalette.surfaceDark;
  static const surfaceDark = AppPalette.cardDark;
  static const surface2Dark = AppPalette.inputDark;
  static const borderDark = AppPalette.borderDark;
  static const textDark = AppPalette.textDark;
  static const textSecondaryDark = AppPalette.textSecondaryDark;
  static const textTertiaryDark = AppPalette.textTertiaryDark;

  // ===== Role colors =====
  static const roleManager = AppPalette.roleManager;
  static const roleOperation = AppPalette.roleOperation;
  static const roleSupervisor = AppPalette.roleSupervisor;
  static const roleCampBoss = AppPalette.roleCampBoss;
  static const roleDriver = AppPalette.roleDriver;
  static const roleEmployee = AppPalette.roleEmployee;
}
