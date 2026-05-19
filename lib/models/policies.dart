import 'package:flutter/material.dart';

/// تصنيفات السياسات
enum PolicyCategory {
  attendance,
  vacation,
  housing,
  conduct,
  emergency,
  other;

  String labelAr() {
    switch (this) {
      case PolicyCategory.attendance:
        return 'الدوام';
      case PolicyCategory.vacation:
        return 'الإجازات';
      case PolicyCategory.housing:
        return 'السكن';
      case PolicyCategory.conduct:
        return 'السلوك';
      case PolicyCategory.emergency:
        return 'الطوارئ';
      case PolicyCategory.other:
        return 'أخرى';
    }
  }

  String labelEn() {
    switch (this) {
      case PolicyCategory.attendance:
        return 'Attendance';
      case PolicyCategory.vacation:
        return 'Vacation';
      case PolicyCategory.housing:
        return 'Housing';
      case PolicyCategory.conduct:
        return 'Conduct';
      case PolicyCategory.emergency:
        return 'Emergency';
      case PolicyCategory.other:
        return 'Other';
    }
  }

  Color color() {
    switch (this) {
      case PolicyCategory.attendance:
        return const Color(0xFF2563A8);
      case PolicyCategory.vacation:
        return const Color(0xFF1D9E75);
      case PolicyCategory.housing:
        return const Color(0xFFE4873A);
      case PolicyCategory.conduct:
        return const Color(0xFF7C5CBF);
      case PolicyCategory.emergency:
        return const Color(0xFFE24B4A);
      case PolicyCategory.other:
        return const Color(0xFF6B7280);
    }
  }

  IconData icon() {
    switch (this) {
      case PolicyCategory.attendance:
        return Icons.access_time;
      case PolicyCategory.vacation:
        return Icons.event_available;
      case PolicyCategory.housing:
        return Icons.home_outlined;
      case PolicyCategory.conduct:
        return Icons.workspace_premium_outlined;
      case PolicyCategory.emergency:
        return Icons.emergency_outlined;
      case PolicyCategory.other:
        return Icons.article_outlined;
    }
  }
}

/// قسم داخل السياسة (نص + قائمة خطوات)
class PolicySection {
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final String? bodyAr;
  final String? bodyEn;
  final List<String> stepsAr;
  final List<String> stepsEn;

  const PolicySection({
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    this.bodyAr,
    this.bodyEn,
    this.stepsAr = const [],
    this.stepsEn = const [],
  });
}

/// سياسة الشركة
class Policy {
  final String id;
  String titleAr;
  String titleEn;
  String summaryAr;
  String summaryEn;
  PolicyCategory category;
  DateTime updatedAt;
  List<PolicySection> sections;

  Policy({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.summaryAr,
    required this.summaryEn,
    required this.category,
    required this.updatedAt,
    this.sections = const [],
  });

  /// عدد إجمالي الخطوات في كل الأقسام (للعرض)
  int get totalSteps =>
      sections.fold<int>(0, (a, s) => a + s.stepsAr.length);

  /// بحث نصي
  bool matches(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    if (titleAr.toLowerCase().contains(q)) return true;
    if (titleEn.toLowerCase().contains(q)) return true;
    if (summaryAr.toLowerCase().contains(q)) return true;
    if (summaryEn.toLowerCase().contains(q)) return true;
    for (final s in sections) {
      if (s.titleAr.toLowerCase().contains(q)) return true;
      if (s.titleEn.toLowerCase().contains(q)) return true;
      if ((s.bodyAr ?? '').toLowerCase().contains(q)) return true;
      if ((s.bodyEn ?? '').toLowerCase().contains(q)) return true;
      for (final step in s.stepsAr) {
        if (step.toLowerCase().contains(q)) return true;
      }
      for (final step in s.stepsEn) {
        if (step.toLowerCase().contains(q)) return true;
      }
    }
    return false;
  }
}
