import 'dart:convert';

import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// 📦 خدمة تصدير/استيراد إعدادات النظام كـ JSON
///
/// تخزّن وتستعيد كامل الإعدادات الإداريّة:
///   - الأقسام (departments) — مع parent_id و level
///   - المسمّيات الوظيفيّة (job_titles) — مع كلّ الحقول الغنيّة
///   - علاقات reports_to
///   - الأدوار (roles) — مع key + priority
///   - تطابق role ↔ permissions
///   - قوالب النماذج (form_templates) — مع schema و workflow
///
/// الفائدة:
///   - **نسخة احتياطيّة** قبل أيّ تغيير كبير
///   - **نقل** الإعدادات بين دول/بيئات
///   - **مشاركة** قوالب الإعدادات بين المسؤولين
///   - **توثيق** الحالة الحاليّة كملفّ مرجعيّ
class ConfigExportService {
  ConfigExportService._();

  /// إصدار صيغة الـ JSON (للتوافق المستقبلي)
  static const _formatVersion = '1.0';

  // ============================================================
  // EXPORT
  // ============================================================

  /// يصدّر كامل الإعدادات الإداريّة كـ JSON Map
  static Map<String, dynamic> exportAll() {
    final repo = MockRepository();
    return {
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'departments': _exportDepartments(repo),
      'job_titles': _exportJobTitles(repo),
      'reports_to': _exportReportsTo(repo),
      'roles': _exportRoles(repo),
      'role_permissions': _exportRolePermissions(repo),
      'form_templates': _exportFormTemplates(repo),
      'metadata': _exportMetadata(repo),
    };
  }

  /// يصدّر كـ JSON String (للحفظ في ملفّ)
  static String exportAsString({bool pretty = true}) {
    final data = exportAll();
    if (pretty) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    }
    return jsonEncode(data);
  }

  static List<Map<String, dynamic>> _exportDepartments(MockRepository repo) {
    return repo.departments
        .map((d) => {
              'id': d.id,
              'name_ar': d.nameAr,
              'name_en': d.nameEn,
              'category': d.category.key,
              'parent_id': d.parentId,
              'level': d.level,
            })
        .toList();
  }

  static List<Map<String, dynamic>> _exportJobTitles(MockRepository repo) {
    return repo.jobTitles
        .map((j) => {
              'id': j.id,
              'name_ar': j.nameAr,
              'name_en': j.nameEn,
              'category': j.category.key,
              'role_id': j.roleId,
              'is_supervisor': j.isSupervisor,
              'level': j.level,
              'color': j.color,
              'dashboard_type': j.dashboardType.key,
              'allowed_screens': j.allowedScreens,
              'approval_power': j.approvalPower,
              'kpi_targets': j.kpiTargets,
              'notification_rules': j.notificationRules,
            })
        .toList();
  }

  static List<Map<String, dynamic>> _exportReportsTo(MockRepository repo) {
    final result = <Map<String, dynamic>>[];
    for (final j in repo.jobTitles) {
      for (final rid in j.reportsToIds) {
        result.add({
          'job_title_id': j.id,
          'reports_to_id': rid,
          'is_primary': rid == j.primaryReportsToId,
        });
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> _exportRoles(MockRepository repo) {
    return repo.roleDefs
        .map((r) => {
              'id': r.id,
              'key': r.key,
              'name_ar': r.nameAr,
              'name_en': r.nameEn,
              'description_ar': r.descriptionAr,
              'description_en': r.descriptionEn,
              'is_system': r.isSystem,
              'priority': r.priority,
            })
        .toList();
  }

  static List<Map<String, dynamic>> _exportRolePermissions(
      MockRepository repo) {
    final result = <Map<String, dynamic>>[];
    for (final r in repo.roleDefs) {
      final keys = repo.permissionKeysForRole(r.id);
      result.add({
        'role_id': r.id,
        'role_key': r.key,
        'permission_keys': keys.toList()..sort(),
      });
    }
    return result;
  }

  static List<Map<String, dynamic>> _exportFormTemplates(
      MockRepository repo) {
    return repo.formTemplates
        .map((t) => {
              'id': t.id,
              'code': t.code,
              'name_ar': t.nameAr,
              'name_en': t.nameEn,
              'description_ar': t.descriptionAr,
              'description_en': t.descriptionEn,
              'category': t.category,
              'icon': t.icon,
              'reference_file_url': t.referenceFileUrl,
              'schema': t.schema,
              'workflow': t.workflow,
              'permissions': t.permissions,
              'country_id': t.countryId,
              'is_active': t.isActive,
              'sort_order': t.sortOrder,
            })
        .toList();
  }

  static Map<String, dynamic> _exportMetadata(MockRepository repo) {
    return {
      'departments_count': repo.departments.length,
      'job_titles_count': repo.jobTitles.length,
      'roles_count': repo.roleDefs.length,
      'permissions_count': repo.permissionDefs.length,
      'form_templates_count': repo.formTemplates.length,
    };
  }

  // ============================================================
  // IMPORT (preview only — no auto-apply)
  // ============================================================

  /// يحلّل JSON ويُرجع تقريراً عن المحتويات قبل التطبيق
  static ImportPreview previewImport(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final formatVersion = data['format_version'] as String?;
      if (formatVersion == null) {
        return ImportPreview.error('Missing format_version');
      }

      final exportedAt = data['exported_at'] as String?;

      final departments = (data['departments'] as List?) ?? [];
      final jobTitles = (data['job_titles'] as List?) ?? [];
      final reportsTo = (data['reports_to'] as List?) ?? [];
      final roles = (data['roles'] as List?) ?? [];
      final rolePerms = (data['role_permissions'] as List?) ?? [];
      final formTemplates = (data['form_templates'] as List?) ?? [];

      return ImportPreview(
        success: true,
        formatVersion: formatVersion,
        exportedAt: exportedAt == null ? null : DateTime.tryParse(exportedAt),
        departmentsCount: departments.length,
        jobTitlesCount: jobTitles.length,
        reportsToLinksCount: reportsTo.length,
        rolesCount: roles.length,
        rolePermissionsCount: rolePerms.length,
        formTemplatesCount: formTemplates.length,
        rawData: data,
      );
    } catch (e) {
      return ImportPreview.error(e.toString());
    }
  }

  /// يطبّق الاستيراد بشكل كامل (يستبدل البيانات الحاليّة)
  /// 🔥 خطر: هذه عمليّة متلفة — يجب التأكد قبل النداء.
  /// تُجرى محلّياً فقط (لا تُكتب في Supabase) ليُختبر النتيجة قبل النشر.
  static ImportResult applyImport(
    Map<String, dynamic> data, {
    bool replaceJobTitles = true,
    bool replaceDepartments = true,
    bool replaceRoles = false, // الأدوار حسّاسة — افتراضياً لا تُستبدل
    bool replaceRolePermissions = true,
    bool replaceFormTemplates = false,
  }) {
    final repo = MockRepository();
    var imported = 0;
    final errors = <String>[];

    // 1) Departments
    if (replaceDepartments) {
      final depts = (data['departments'] as List?) ?? [];
      repo.departments.clear();
      for (final d in depts) {
        try {
          final m = d as Map<String, dynamic>;
          repo.departments.add(Department(
            id: m['id'] as String,
            nameAr: m['name_ar'] as String,
            nameEn: m['name_en'] as String,
            category: JobTitleCategoryX.fromKey(m['category'] as String?),
            parentId: m['parent_id'] as String?,
            level: (m['level'] as int?) ?? 0,
          ));
          imported++;
        } catch (e) {
          errors.add('department: $e');
        }
      }
    }

    // 2) Job Titles
    if (replaceJobTitles) {
      final jts = (data['job_titles'] as List?) ?? [];
      final reportsTo = (data['reports_to'] as List?) ?? [];
      // ابنِ خرائط reports_to قبل المسح
      final reportsByJob = <String, List<String>>{};
      final primaryByJob = <String, String>{};
      for (final r in reportsTo) {
        try {
          final m = r as Map<String, dynamic>;
          final jid = m['job_title_id'] as String;
          final rid = m['reports_to_id'] as String;
          reportsByJob.putIfAbsent(jid, () => []).add(rid);
          if ((m['is_primary'] as bool?) == true) {
            primaryByJob[jid] = rid;
          }
        } catch (_) {}
      }
      repo.jobTitles.clear();
      for (final j in jts) {
        try {
          final m = j as Map<String, dynamic>;
          final id = m['id'] as String;
          repo.jobTitles.add(JobTitle(
            id: id,
            nameAr: m['name_ar'] as String,
            nameEn: m['name_en'] as String,
            category: JobTitleCategoryX.fromKey(m['category'] as String?),
            roleId: m['role_id'] as String?,
            isSupervisor: (m['is_supervisor'] as bool?) ?? false,
            level: (m['level'] as int?) ?? 0,
            reportsToIds: reportsByJob[id] ?? [],
            primaryReportsToId: primaryByJob[id],
            color: m['color'] as String?,
            dashboardType:
                DashboardTypeX.fromKey(m['dashboard_type'] as String?),
            allowedScreens: (m['allowed_screens'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            approvalPower: (m['approval_power'] as int?) ?? 0,
            kpiTargets: Map<String, dynamic>.from(
                m['kpi_targets'] as Map? ?? const {}),
            notificationRules: Map<String, dynamic>.from(
                m['notification_rules'] as Map? ?? const {}),
          ));
          imported++;
        } catch (e) {
          errors.add('job_title: $e');
        }
      }
    }

    // 3) Roles (only if explicitly requested)
    if (replaceRoles) {
      final roles = (data['roles'] as List?) ?? [];
      repo.roleDefs.clear();
      for (final r in roles) {
        try {
          final m = r as Map<String, dynamic>;
          repo.roleDefs.add(RoleDef(
            id: m['id'] as String,
            key: m['key'] as String,
            nameAr: m['name_ar'] as String,
            nameEn: m['name_en'] as String,
            descriptionAr: m['description_ar'] as String?,
            descriptionEn: m['description_en'] as String?,
            isSystem: (m['is_system'] as bool?) ?? false,
            priority: (m['priority'] as int?) ?? 0,
          ));
          imported++;
        } catch (e) {
          errors.add('role: $e');
        }
      }
    }

    // 4) Role permissions
    if (replaceRolePermissions) {
      final rps = (data['role_permissions'] as List?) ?? [];
      for (final rp in rps) {
        try {
          final m = rp as Map<String, dynamic>;
          final roleId = m['role_id'] as String;
          final keys =
              ((m['permission_keys'] as List?) ?? []).cast<String>().toSet();
          repo.setRolePermissionsByKeys(roleId, keys, '');
          imported++;
        } catch (e) {
          errors.add('role_permission: $e');
        }
      }
    }

    // 5) Form templates (only if explicitly requested)
    if (replaceFormTemplates) {
      // Form import is more delicate — skipped by default
      errors.add('form_templates import not yet implemented');
    }

    repo.notifyListeners();

    return ImportResult(
      success: errors.isEmpty,
      imported: imported,
      errors: errors,
    );
  }
}

/// نتيجة معاينة استيراد
class ImportPreview {
  final bool success;
  final String? error;
  final String? formatVersion;
  final DateTime? exportedAt;
  final int departmentsCount;
  final int jobTitlesCount;
  final int reportsToLinksCount;
  final int rolesCount;
  final int rolePermissionsCount;
  final int formTemplatesCount;
  final Map<String, dynamic>? rawData;

  ImportPreview({
    required this.success,
    this.error,
    this.formatVersion,
    this.exportedAt,
    this.departmentsCount = 0,
    this.jobTitlesCount = 0,
    this.reportsToLinksCount = 0,
    this.rolesCount = 0,
    this.rolePermissionsCount = 0,
    this.formTemplatesCount = 0,
    this.rawData,
  });

  factory ImportPreview.error(String message) =>
      ImportPreview(success: false, error: message);

  int get totalCount =>
      departmentsCount +
      jobTitlesCount +
      reportsToLinksCount +
      rolesCount +
      rolePermissionsCount +
      formTemplatesCount;
}

/// نتيجة تطبيق استيراد
class ImportResult {
  final bool success;
  final int imported;
  final List<String> errors;

  ImportResult({
    required this.success,
    required this.imported,
    required this.errors,
  });
}
