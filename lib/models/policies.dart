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


// ============================================================
// 🆕 DB (company_policies) — shared with the valet app
// ============================================================
const Map<String, IconData> policyIconKeys = {
  'access_time': Icons.access_time,
  'checklist': Icons.checklist,
  'warning': Icons.warning_amber,
  'event': Icons.event_available,
  'assignment': Icons.assignment_turned_in_outlined,
  'timer': Icons.timer_outlined,
  'home': Icons.home_outlined,
  'laundry': Icons.local_laundry_service_outlined,
  'checkroom': Icons.checkroom_outlined,
  'handshake': Icons.handshake_outlined,
  'fire': Icons.local_fire_department_outlined,
  'phone': Icons.phone_in_talk_outlined,
  'article': Icons.article_outlined,
};

String policyIconKey(IconData i) {
  for (final e in policyIconKeys.entries) {
    if (e.value.codePoint == i.codePoint) return e.key;
  }
  return 'article';
}

extension PolicyDb on Policy {
  Map<String, dynamic> toRow(int sort) => {
        'id': id,
        'category': category.name,
        'title_ar': titleAr,
        'title_en': titleEn,
        'summary_ar': summaryAr,
        'summary_en': summaryEn,
        'sort': sort,
        'sections': [
          for (final s in sections)
            {
              'title_ar': s.titleAr,
              'title_en': s.titleEn,
              'icon': policyIconKey(s.icon),
              'body_ar': s.bodyAr,
              'body_en': s.bodyEn,
              'steps_ar': s.stepsAr,
              'steps_en': s.stepsEn,
            },
        ],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  static Policy fromRow(Map<String, dynamic> r) {
    List<String> l(dynamic v) => (v as List? ?? const []).map((e) => '$e').toList();
    return Policy(
      id: r['id'] as String,
      titleAr: (r['title_ar'] as String?) ?? '',
      titleEn: (r['title_en'] as String?) ?? '',
      summaryAr: (r['summary_ar'] as String?) ?? '',
      summaryEn: (r['summary_en'] as String?) ?? '',
      category: PolicyCategory.values.firstWhere((c) => c.name == r['category'], orElse: () => PolicyCategory.other),
      updatedAt: DateTime.tryParse('${r['updated_at']}')?.toLocal() ?? DateTime.now(),
      sections: [
        for (final s in (r['sections'] as List? ?? const []).whereType<Map>())
          PolicySection(
            titleAr: (s['title_ar'] as String?) ?? '',
            titleEn: (s['title_en'] as String?) ?? '',
            icon: policyIconKeys[s['icon']] ?? Icons.article_outlined,
            bodyAr: s['body_ar'] as String?,
            bodyEn: s['body_en'] as String?,
            stepsAr: l(s['steps_ar']),
            stepsEn: l(s['steps_en']),
          ),
      ],
    );
  }
}
