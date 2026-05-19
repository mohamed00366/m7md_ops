import '../../core/providers/auth_provider.dart';
import '../../models/models.dart';

/// 🔐 نِظام صَلاحيّات النَماذج — 5 مُستَوَيات لِكُلّ قالِب
///
/// يُحفَظ في `form_templates.permissions_json` كـMap:
/// ```json
/// {
///   "submit_roles":     ["supervisor", "operation"],
///   "view_all_roles":   ["hr", "manager", "admin", "super_admin"],
///   "view_table_roles": ["manager", "admin", "super_admin"],
///   "export_roles":     ["manager", "admin", "super_admin"],
///   "manage_roles":     ["admin", "super_admin"]
/// }
/// ```
///
/// Super Admin يَتَجاوَز كُلّ القُيود دائِماً.
class FormPermissions {
  final List<String> submitRoles;
  final List<String> viewAllRoles;
  final List<String> viewTableRoles;
  final List<String> exportRoles;
  final List<String> manageRoles;

  const FormPermissions({
    this.submitRoles = const [],
    this.viewAllRoles = const [],
    this.viewTableRoles = const [],
    this.exportRoles = const [],
    this.manageRoles = const [],
  });

  /// من Map (permissions_json)
  factory FormPermissions.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const FormPermissions();
    List<String> listOf(String k) {
      final v = m[k];
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      return [];
    }

    return FormPermissions(
      submitRoles: listOf('submit_roles'),
      viewAllRoles: listOf('view_all_roles'),
      viewTableRoles: listOf('view_table_roles'),
      exportRoles: listOf('export_roles'),
      manageRoles: listOf('manage_roles'),
    );
  }

  /// مِن قالِب
  factory FormPermissions.fromTemplate(FormTemplate t) =>
      FormPermissions.fromMap(t.permissions);

  /// تَحويل لـMap لِلحِفظ
  Map<String, dynamic> toMap() => {
        'submit_roles': submitRoles,
        'view_all_roles': viewAllRoles,
        'view_table_roles': viewTableRoles,
        'export_roles': exportRoles,
        'manage_roles': manageRoles,
      };

  /// قيم افتِراضيّة عاقِلة لِقالِب جَديد
  static const sensibleDefaults = FormPermissions(
    submitRoles: ['employee', 'supervisor', 'operation'],
    viewAllRoles: ['hr', 'manager', 'admin', 'super_admin'],
    viewTableRoles: ['manager', 'admin', 'super_admin'],
    exportRoles: ['manager', 'admin', 'super_admin'],
    manageRoles: ['admin', 'super_admin'],
  );

  // ============================================================
  // فُحوصات
  // ============================================================

  /// هَل يُمكِنه تَقديم النَموذج؟
  bool canSubmit(AuthProvider auth) {
    if (auth.isSuperAdmin) return true;
    if (submitRoles.isEmpty) return true; // مَفتوح لِلكُلّ
    return _userHasAnyRole(auth, submitRoles);
  }

  /// هَل يَرى كُلّ التَقديمات (وَلَيس فَقَط الخاصّة بِه)؟
  bool canViewAll(AuthProvider auth) {
    if (auth.isSuperAdmin) return true;
    return _userHasAnyRole(auth, viewAllRoles);
  }

  /// هَل يَرى عَرض الجَدول (Data Table)؟
  bool canViewTable(AuthProvider auth) {
    if (auth.isSuperAdmin) return true;
    return _userHasAnyRole(auth, viewTableRoles);
  }

  /// هَل يُمكِنه تَصدير البَيانات (Excel/CSV)؟
  bool canExport(AuthProvider auth) {
    if (auth.isSuperAdmin) return true;
    return _userHasAnyRole(auth, exportRoles);
  }

  /// هَل يُمكِنه تَعديل/حَذف القالِب؟
  bool canManage(AuthProvider auth) {
    if (auth.isSuperAdmin) return true;
    if (manageRoles.isEmpty) return false; // مُغلَق بِشَكل افتِراضيّ
    return _userHasAnyRole(auth, manageRoles);
  }

  /// مُساعِد داخِليّ — يَفحَص أَدوار المُستَخدِم
  bool _userHasAnyRole(AuthProvider auth, List<String> required) {
    final userRoles = auth.userRoleKeys;
    for (final r in required) {
      if (userRoles.contains(r)) return true;
    }
    return false;
  }

  // ============================================================
  // فَلاتِر قَوائِم
  // ============================================================

  /// فَلتَرة قَوالِب يُمكِن لِلمُستَخدِم تَقديمها
  static List<FormTemplate> filterSubmittable(
    List<FormTemplate> templates,
    AuthProvider auth,
  ) {
    if (auth.isSuperAdmin) {
      return templates.where((t) => t.isActive).toList();
    }
    return templates.where((t) {
      if (!t.isActive) return false;
      return FormPermissions.fromTemplate(t).canSubmit(auth);
    }).toList();
  }

  /// فَلتَرة قَوالِب يُمكِن لِلمُستَخدِم رُؤية تَقديماتها الكامِلة
  static List<FormTemplate> filterViewable(
    List<FormTemplate> templates,
    AuthProvider auth,
  ) {
    if (auth.isSuperAdmin) return templates;
    return templates.where((t) {
      return FormPermissions.fromTemplate(t).canViewAll(auth);
    }).toList();
  }
}

// ============================================================
// AuthProvider helper — يَستَخرِج keys الأَدوار من قائِمة RoleDef
// ============================================================
extension AuthProviderRolesExt on AuthProvider {
  /// قائِمة keys الأَدوار المُسنَدة لِلمُستَخدِم
  List<String> get userRoleKeys {
    if (isSuperAdmin) {
      return [
        'super_admin', 'admin', 'manager', 'operation', 'supervisor',
        'camp_boss', 'driver', 'employee', 'hr',
      ];
    }
    return roles.map((r) => r.key).toList();
  }
}
