import 'package:flutter/material.dart';

import '../../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;

/// 📦 فئات الأقسام — مرتّبة حسب التدفّق المنطقي للعمل.
///
/// الترتيب الرسمي (يُفضَّل ألّا يُغيَّر دون مراجعة):
///   1. home          — الرئيسيّة (Smart Home + Dashboards)
///   2. organization  — الدول، الأقسام، النقاط، العملاء
///   3. hr            — الموظّفون + الحضور + التقييم + الخصومات + التدريب
///   4. roster        — الروسترات (إنشاء/اعتماد/عرض)
///   5. transport     — الباصات + السائقون + التتبّع + الخرائط
///   6. camp          — الغرف + المغسلة + اليونيفورم + المخالفات
///   7. driver        — شاشات السائق
///   8. employee      — شاشاتي (الموظف العادي)
///   9. forms         — النماذج والموافقات
///  10. reports       — التقارير
///  11. admin         — الإدارة + الإعدادات
enum ModuleCategory {
  // 1) الرئيسيّة
  home,
  // 2) المؤسّسة والهيكل
  organization,
  // 3) الموارد البشرية (يضمّ الحضور والتقييم والخصومات والتدريب)
  hr,
  // 4) الروسترات
  roster,
  // 5) الكمب — يَضُمّ الآن الباصات والسائقين والتتبُّع (كانَ transport)
  camp,
  // 6) السائق (شاشات مخصّصة)
  driver,
  // 7) الموظف (شاشاتي)
  employee,
  // 8) النماذج والـ workflows
  forms,
  // 9) التقارير
  reports,
  // 10) الإدارة + الإعدادات
  admin,

  // ============================================================
  // ⚠️ Legacy — لا تُستخدم في تعريفات جديدة، باقية للتوافق.
  // ============================================================
  transport,  // legacy → camp (مَدموج هُناك)
  operations, // legacy alias → opsSub
  sales,      // legacy → organization
  opsSub,     // legacy → camp (للتتبّع/الباصات)
  training,   // legacy → hr (تحت HR الآن)
  system,     // legacy → admin (الإدارة + الإعدادات)
}

extension ModuleCategoryX on ModuleCategory {
  String labelAr() {
    switch (this) {
      case ModuleCategory.home:         return 'الرئيسية';
      case ModuleCategory.organization: return 'المؤسّسة';
      case ModuleCategory.hr:           return 'الموارد البشرية';
      case ModuleCategory.roster:       return 'الروستر';
      case ModuleCategory.transport:    return 'النقل';
      case ModuleCategory.camp:         return 'الكمب';
      case ModuleCategory.driver:       return 'السائق';
      case ModuleCategory.employee:     return 'شاشاتي';
      case ModuleCategory.forms:        return 'النماذج';
      case ModuleCategory.reports:      return 'التقارير';
      case ModuleCategory.admin:        return 'الإدارة';
      // legacy aliases
      case ModuleCategory.operations:   return 'العمليات';
      case ModuleCategory.sales:        return 'المؤسّسة';
      case ModuleCategory.opsSub:       return 'النقل';
      case ModuleCategory.training:     return 'الموارد البشرية';
      case ModuleCategory.system:       return 'الإدارة';
    }
  }

  String labelEn() {
    switch (this) {
      case ModuleCategory.home:         return 'Home';
      case ModuleCategory.organization: return 'Organization';
      case ModuleCategory.hr:           return 'HR';
      case ModuleCategory.roster:       return 'Roster';
      case ModuleCategory.transport:    return 'Transport';
      case ModuleCategory.camp:         return 'Camp';
      case ModuleCategory.driver:       return 'Driver';
      case ModuleCategory.employee:     return 'My Screens';
      case ModuleCategory.forms:        return 'Forms';
      case ModuleCategory.reports:      return 'Reports';
      case ModuleCategory.admin:        return 'Admin';
      // legacy aliases
      case ModuleCategory.operations:   return 'Operations';
      case ModuleCategory.sales:        return 'Organization';
      case ModuleCategory.opsSub:       return 'Transport';
      case ModuleCategory.training:     return 'HR';
      case ModuleCategory.system:       return 'Admin';
    }
  }

  IconData icon() {
    switch (this) {
      case ModuleCategory.home:         return Icons.home;
      case ModuleCategory.organization: return Icons.account_tree_outlined;
      case ModuleCategory.hr:           return Icons.people_alt_outlined;
      case ModuleCategory.roster:       return Icons.calendar_today;
      case ModuleCategory.transport:    return Icons.directions_bus;
      case ModuleCategory.camp:         return Icons.holiday_village;
      case ModuleCategory.driver:       return Icons.local_taxi;
      case ModuleCategory.employee:     return Icons.badge;
      case ModuleCategory.forms:        return Icons.assignment_outlined;
      case ModuleCategory.reports:      return Icons.bar_chart;
      case ModuleCategory.admin:        return Icons.shield_moon;
      // legacy aliases
      case ModuleCategory.operations:   return Icons.business_center;
      case ModuleCategory.sales:        return Icons.handshake_outlined;
      case ModuleCategory.opsSub:       return Icons.directions_bus;
      case ModuleCategory.training:     return Icons.school_outlined;
      case ModuleCategory.system:       return Icons.settings;
    }
  }

  Color color() {
    switch (this) {
      case ModuleCategory.home:         return const Color(0xFF2F6FED); // أزرق
      case ModuleCategory.organization: return const Color(0xFF1F2937); // كحلي
      case ModuleCategory.hr:           return const Color(0xFF7C3AED); // بنفسجي
      case ModuleCategory.roster:       return const Color(0xFFF59E0B); // كهرماني
      case ModuleCategory.transport:    return const Color(0xFF2563EB); // أزرق غامق
      case ModuleCategory.camp:         return const Color(0xFF8B5CF6); // بنفسجي فاتح
      case ModuleCategory.driver:       return const Color(0xFF10B981); // أخضر
      case ModuleCategory.employee:     return const Color(0xFF64748B); // رمادي
      case ModuleCategory.forms:        return const Color(0xFF7C3AED); // بنفسجي
      case ModuleCategory.reports:      return const Color(0xFF14B8A6); // تركواز
      case ModuleCategory.admin:        return const Color(0xFFE24B4A); // أحمر
      // legacy aliases
      case ModuleCategory.operations:   return const Color(0xFF6366F1);
      case ModuleCategory.sales:        return const Color(0xFF059669);
      case ModuleCategory.opsSub:       return const Color(0xFF2563EB);
      case ModuleCategory.training:     return const Color(0xFF7C3AED);
      case ModuleCategory.system:       return const Color(0xFFE24B4A);
    }
  }

  /// 🆕 الترتيب الرسمي للقسم في الـ Drawer/Smart Home (الأصغر يظهر أوّلاً).
  int get displayOrder {
    switch (this) {
      case ModuleCategory.home:         return 0;
      case ModuleCategory.organization: return 1;
      case ModuleCategory.hr:           return 2;
      case ModuleCategory.roster:       return 3;
      case ModuleCategory.transport:    return 4;
      case ModuleCategory.camp:         return 5;
      case ModuleCategory.driver:       return 6;
      case ModuleCategory.employee:     return 7;
      case ModuleCategory.forms:        return 8;
      case ModuleCategory.reports:      return 9;
      case ModuleCategory.admin:        return 10;
      // legacy → نهاية القائمة
      case ModuleCategory.operations:   return 90;
      case ModuleCategory.sales:        return 91;
      case ModuleCategory.opsSub:       return 92;
      case ModuleCategory.training:     return 93;
      case ModuleCategory.system:       return 94;
    }
  }
}

/// وحدة بناء أساسية: قسم في التطبيق
/// كل ما يراه المستخدم في الـ Drawer هو قائمة AppModules مفلترة بصلاحياته
class AppModule {
  /// مفتاح فريد (للحفظ في URL/preferences)
  final String key;

  /// العنوان بلغتين
  final String titleAr;
  final String titleEn;

  /// أيقونة القسم (داخل الـ Drawer + AppBar)
  final IconData icon;

  /// لون القسم (شارة)
  final Color color;

  /// الفئة - تُجمّع بها الأقسام في Drawer
  final ModuleCategory category;

  /// الصلاحية المطلوبة لرؤية هذا القسم (null = للجميع)
  final String? requiredPermission;

  /// إذا true، يحتاج المستخدم لاختيار دولة قبل دخول هذا القسم
  final bool requiresCountry;

  /// المُنشئ (يُستدعى عند الفتح)
  final WidgetBuilder builder;

  const AppModule({
    required this.key,
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.category,
    this.requiredPermission,
    this.requiresCountry = false,
    required this.builder,
  });

  String title(bool isAr) => isAr ? ar2ur.tr(titleAr) : titleEn;
}
