// =============================================================================
// 🎨 ألوان نِظام "أَمانة"
// =============================================================================
import 'package:flutter/material.dart';

class LaundryColors {
  LaundryColors._();

  // حالات
  static const statusPending = Color(0xFFF5B860);
  static const statusConfirmed = Color(0xFF7DD3C0);
  static const statusInLaundry = Color(0xFF7AA9F5);
  static const statusReady = Color(0xFF7DD3C0);
  static const statusMissing = Color(0xFFEC6F7C);
  static const statusDelivered = Color(0xFF5A6485);

  // رَئيسيّة
  static const primary = Color(0xFF7DD3C0);
  static const info = Color(0xFF7AA9F5);
  static const warning = Color(0xFFF5B860);
  static const danger = Color(0xFFEC6F7C);
  static const success = Color(0xFF10B981);

  // تَوَفُّر
  static const availOpen = Color(0xFF10B981);
  static const availClosingSoon = Color(0xFFF5B860);
  static const availClosed = Color(0xFF6B7280);
  static const availHoliday = Color(0xFFEC6F7C);
  static const availEmergency = Color(0xFFDC2626);
}
