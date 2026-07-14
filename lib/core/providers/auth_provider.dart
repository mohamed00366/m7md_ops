import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/leave.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../services/active_duty_settings.dart';
import '../services/audit_logger.dart';
import '../services/device_session_service.dart';
import '../services/error_tracking_service.dart';
import '../services/fcm_service.dart';
import '../services/tenant_context.dart';
import '../services/point_terminal_session_service.dart';
import '../services/device_session_settings.dart';
import '../services/face_attempt_tracker.dart';
import '../services/geo_fence_service.dart';
import '../services/geo_fence_settings.dart';
import '../services/leave_service.dart';
import '../services/login_method_settings.dart';
import '../services/notifications_service.dart';
import '../services/point_assignment_settings.dart';
import '../services/realtime_sync_service.dart';
import '../services/remember_me_service.dart';
import '../services/session_settings.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../services/m7_log.dart';

/// نتيجة تسجيل الدخول
enum LoginResult {
  success,
  invalidCredentials,
  inactiveAccount,
  noRoles,
  networkError,
  deviceBlocked, // 🆕 جلسة فعّالة من جهاز آخر (سياسة جهاز واحد متشدّدة)
  geoFenceRejected, // 🆕 الموقع خارج المنطقة المسموحة
  geoFenceMockLocation, // 🆕 كشف تطبيق تزييف الموقع
  geoFencePermissionDenied, // 🆕 الموظّف رفض إذن الموقع
  // 🆕 Face login
  faceRequired,        // الحساب يستخدم بصمة الوجه — التبويبة الخاطئة
  faceNotEnrolled,     // لم تُسجَّل بصمة الوجه بعد
  faceCooldown,        // تهدئة بعد فشل عدّة محاولات
  faceLocked,          // الحساب مقفل — راجع الإدارة
  // إنّما المطابقة فشلت تُعالج بزيادة العدّاد ثمّ إعادة المحاولة
  passwordRequired,    // الحساب يستخدم كلمة المرور — اختار التبويبة الخاطئة
  // 🆕 Active-Duty-Only Policy
  onApprovedLeave,     // الموظّف في إجازة معتمدة سارية اليوم
  accountSuspended,    // حساب/موظّف معلّق
}

/// نتيجة الفحص قبل فتح شاشة بصمة الوجه
class FacePreflightResult {
  final bool ok;
  final LoginResult? error;
  final String? accountId;
  final String? fullName;
  final DateTime? cooldownUntil;

  const FacePreflightResult._({
    required this.ok,
    this.error,
    this.accountId,
    this.fullName,
    this.cooldownUntil,
  });

  factory FacePreflightResult.ok({
    required String accountId,
    required String fullName,
  }) =>
      FacePreflightResult._(
        ok: true,
        accountId: accountId,
        fullName: fullName,
      );

  factory FacePreflightResult.error(
    LoginResult err, {
    DateTime? cooldownUntil,
  }) =>
      FacePreflightResult._(
        ok: false,
        error: err,
        cooldownUntil: cooldownUntil,
      );
}

/// تفاصيل نتيجة Geo-fence (للعرض في شاشة الدخول)
class GeoFenceFailDetails {
  final LoginResult result;
  final String? matchedZoneName;
  final String? warning;
  final double? latitude;
  final double? longitude;
  GeoFenceFailDetails({
    required this.result,
    this.matchedZoneName,
    this.warning,
    this.latitude,
    this.longitude,
  });
}

/// مزوّد المصادقة + الصلاحيات
/// يحاول أولاً Supabase، ثم Mock fallback
class AuthProvider extends ChangeNotifier {
  final MockRepository _repo = MockRepository();
  final SupabaseService _supabase = SupabaseService();

  // ==== الحالة ====
  AppAccount? _account; // حساب RBAC الجديد (مع username/password)
  AppUser? _legacyUser; // للتوافق مع الكود القديم
  List<RoleDef> _roles = [];
  Set<String> _permissions = {};
  List<String> _countryIds = [];

  RoleDef? _activeRole; // الدور النشط حالياً (للأدوار المتعددة)
  String? _activeCountryId; // الدولة الحالية
  String? _activeSiteId; // الموقع المختار (للمشرف)

  // 🆕 Impersonate: حفظ الجلسة الأصليّة للعودة إليها
  AppAccount? _origAccount;
  AppUser? _origLegacyUser;
  List<RoleDef>? _origRoles;
  Set<String>? _origPermissions;
  List<String>? _origCountryIds;
  RoleDef? _origActiveRole;
  String? _origActiveCountryId;
  String? _origActiveSiteId;

  // ==== Getters ====
  AppAccount? get account => _account;
  AppUser? get currentUser => _legacyUser;
  List<RoleDef> get roles => List.unmodifiable(_roles);
  RoleDef? get activeRole => _activeRole;
  Set<String> get permissions => Set.unmodifiable(_permissions);
  List<String> get countryIds => List.unmodifiable(_countryIds);
  String? get activeCountryId => _activeCountryId;
  String? get activeSiteId => _activeSiteId;
  bool get isLoggedIn => _account != null;
  bool get isSuperAdmin => _account?.isSuperAdmin ?? false;
  bool get hasMultipleRoles => _roles.length > 1;

  // 🆕 Impersonate state
  bool get isImpersonating => _origAccount != null;
  String? get impersonatedAs => isImpersonating ? _account?.fullName : null;
  String? get realIdentity => _origAccount?.fullName;

  // ==== Setters ====
  void setActiveRole(RoleDef role) {
    _activeRole = role;
    _legacyUser = _buildLegacyUser();
    _refreshAuditContext();
    notifyListeners();
  }

  void setActiveCountry(String? countryId) {
    _activeCountryId = countryId;
    _refreshAuditContext();
    notifyListeners();
  }

  void _refreshAuditContext() {
    if (_account == null) {
      AuditLogger.instance.clearContext();
      return;
    }
    AuditLogger.instance.setContext(
      actorId: _account!.id,
      actorName: _account!.fullName,
      actorRole: _activeRole?.key ??
          (_account!.isSuperAdmin ? SystemRoles.superAdmin : null),
      countryId: _activeCountryId,
    );
  }

  void setActiveSite(String? siteId) {
    _activeSiteId = siteId;
    notifyListeners();
  }

  // ==== التوافق مع الكود القديم ====
  UserRole? get selectedAppRole {
    if (_activeRole == null) return null;
    return _legacyRoleFromKey(_activeRole!.key);
  }

  String? get selectedCountryId => _activeCountryId;

  /// 🆕 يُرجع النقطة المختارة، أو نقطة الموظف المرتبط تلقائياً (للمشرفين)
  String? get selectedSiteId {
    if (_activeSiteId != null) return _activeSiteId;
    // Fallback: نقطة الموظف المرتبط بالحساب (للمشرف الذي ربطه Operation بنقطة)
    final empId = _account?.employeeId;
    if (empId == null) return null;
    try {
      final emp = _repo.employees.firstWhere((e) => e.id == empId);
      return emp.pointId ?? emp.siteId; // pointId الجديد أو siteId القديم
    } catch (_) {
      return null;
    }
  }

  void selectApp(UserRole role) {
    final r = _roles.firstWhere(
      (x) => _legacyRoleFromKey(x.key) == role,
      orElse: () => _roles.isEmpty
          ? RoleDef(id: '', key: '', nameAr: '', nameEn: '')
          : _roles.first,
    );
    if (r.id.isNotEmpty) setActiveRole(r);
  }

  void clearAppSelection() {
    _activeRole = null;
    _legacyUser = null;
    notifyListeners();
  }

  void setCountry(String? id) => setActiveCountry(id);
  void setSite(String? id) => setActiveSite(id);

  // ==== Country Scope (فلترة بالدولة الموحّدة) ====

  /// يحدّد إن كان كيان (له countryId) يقع ضمن نطاق المستخدم الحالي
  ///
  /// المنطق:
  /// - لو [activeCountryId] محدّدة → يظهر فقط الكيانات في تلك الدولة
  /// - لو null + Super Admin → يرى كل الدول
  /// - لو null + ليس Super Admin → لا يرى شيء (يجب اختيار دولة)
  bool isInScope(String? entityCountryId) {
    if (_activeCountryId != null) {
      return entityCountryId == _activeCountryId;
    }
    return _account?.isSuperAdmin == true;
  }

  /// يفلتر قائمة بحسب نطاق الدولة الحالي
  ///
  /// مثال:
  /// ```dart
  /// final emps = auth.filterByCountry(
  ///   repo.employees, (e) => e.countryId);
  /// ```
  List<T> filterByCountry<T>(
    List<T> items,
    String? Function(T) getCountryId,
  ) {
    return items.where((item) => isInScope(getCountryId(item))).toList();
  }

  /// قائمة الدول المسموح للمستخدم الوصول إليها
  /// - Super Admin: كل الدول الموجودة في النظام
  /// - مستخدم عادي: فقط الدول المربوطة عبر user_country_access
  List<String> accessibleCountryIds(MockRepository repo) {
    if (_account == null) return const [];
    if (_account!.isSuperAdmin) {
      return repo.countries.map((c) => c.id).toList();
    }
    return repo.userCountryAccess
        .where((a) => a.userId == _account!.id)
        .map((a) => a.countryId)
        .toSet()
        .toList();
  }

  /// هل يحتاج المستخدم لاختيار دولة قبل الاستمرار؟
  /// (يصلها لأكثر من دولة و لم يختر بعد)
  bool needsCountrySelection(MockRepository repo) {
    if (_activeCountryId != null) return false;
    final accessible = accessibleCountryIds(repo);
    return accessible.length > 1;
  }

  // ==== Permissions ====
  bool hasPermission(String key) {
    if (_account?.isSuperAdmin == true) return true;
    return _permissions.contains(key);
  }

  bool hasAnyPermission(List<String> keys) {
    if (_account?.isSuperAdmin == true) return true;
    return keys.any(_permissions.contains);
  }

  /// 🔄 إعادة تَحميل صَلاحيّات المُستَخدِم الحاليّ مِن المَخزَن
  ///
  /// تُستَدعى عِندَ تَغيير أَدوار/صَلاحيّات المُستَخدِم في صَفحة الإدارة
  /// لِيَنعَكِس التَغيير فَوراً بِدون تَسجيل خُروج/دُخول.
  ///
  /// مَثَلاً: عِندَ تَوكيل permission جَديد في `BulkPermissionsMatrixScreen`،
  /// نادِ هذه الدالّة لِتَحديث `_permissions` + `notifyListeners()`.
  Future<void> refreshPermissions() async {
    final acc = _account;
    if (acc == null) return;
    try {
      _permissions = _repo.effectivePermissionKeys(acc.id);
      notifyListeners();
    } catch (e) {
      // مُتَجاهَل — احتِفاظ بِالصَلاحيّات الحاليّة لَو فَشِل التَحديث
    }
  }

  bool hasRole(String roleKey) =>
      _roles.any((r) => r.key == roleKey);

  /// أعلى أولوية بين أدوار المستخدم الحالي
  int get topPriority {
    if (_account?.isSuperAdmin == true) return 1000; // أعلى من أي دور
    if (_roles.isEmpty) return 0;
    return _roles.map((r) => r.priority).reduce((a, b) => a > b ? a : b);
  }

  /// يمكن للمستخدم الحالي إدارة (إنشاء/تعديل) هذا الدور؟
  /// المنطق: لا يستطيع المستخدم منح/إدارة دور أعلى أو مساوٍ لدوره الأعلى
  /// Super Admin يستثنى - يستطيع كل شيء
  bool canManageRole(RoleDef role) {
    if (_account?.isSuperAdmin == true) return true;
    // Admin لا يستطيع لمس Super Admin أبداً
    if (role.key == SystemRoles.superAdmin) return false;
    // الباقي: يجب أن تكون الأولوية أقل من أعلى دور للمستخدم الحالي
    return role.priority < topPriority;
  }

  /// يمكن للمستخدم الحالي إدارة هذا الحساب؟
  /// لا يستطيع غير Super Admin إدارة حسابات Super Admin أخرى
  bool canManageAccount(AppAccount target) {
    if (_account?.isSuperAdmin == true) return true;
    // غير Super Admin لا يستطيع إدارة Super Admin
    if (target.isSuperAdmin) return false;
    return true;
  }

  // ==== Login ====

  /// محاولة تسجيل الدخول
  /// 1) إذا Supabase مُفعّل ومتصل: نجرّب Supabase
  /// 2) إذا فشل أو غير مُفعّل: نجرّب Mock
  /// [rememberMe] إذا true → نحفظ token محلّي للجلسة الطويلة
  Future<LoginResult> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {
    final cleanUser = username.trim();
    if (cleanUser.isEmpty || password.isEmpty) {
      return LoginResult.invalidCredentials;
    }

    LoginResult result;
    // ==== 1) Supabase ====
    if (_supabase.isReady) {
      try {
        final userId = await _supabase.signInWithUsername(
          username: cleanUser,
          password: password,
        );
        if (userId != null) {
          result = await _loadFromSupabase(userId);
          await _saveRememberMeIfRequested(rememberMe);
          return result;
        }
      } catch (e) {
        // ignore: avoid_print
        M7Log.info('Auth', 'Supabase login error, fallback to mock: $e');
      }
    }

    // ==== 2) Mock fallback ====
    result = await _loginMock(cleanUser, password);
    await _saveRememberMeIfRequested(rememberMe);
    return result;
  }

  /// إن طُلب "تذكّرني" والسياسة تسمح، احفظ token
  Future<void> _saveRememberMeIfRequested(bool requested) async {
    if (!requested) return;
    if (_account == null) return; // الدخول لم ينجح
    await SessionSettings.instance.load();
    if (!SessionSettings.instance.isAllowedFor(_account!.id)) return;
    try {
      await RememberMeService.instance.save(
        accountId: _account!.id,
        username: _account!.username,
        deviceId: '', // device_id يُملأ من DeviceSessionService
      );
    } catch (_) {}
  }

  /// 🆕 محاولة استرجاع الجلسة المحفوظة (يُستدعى عند فتح التطبيق)
  Future<bool> tryRestoreSession() async {
    final saved = await RememberMeService.instance.tryLoad();
    if (saved == null) return false;

    // 🆕 إذا Supabase مُتاح، اقرَأ الحِساب مُباشَرة (لا تَنتَظِر مُزامَنة MockRepository)
    if (_supabase.isReady) {
      try {
        final result = await _loadFromSupabase(saved.accountId);
        if (result == LoginResult.success) {
          AuditLogger.instance.log(
            entityType: 'session',
            action: AuditAction.login,
            description:
                'استرجاع جلسة محفوظة: ${_account?.username ?? saved.username} (تنتهي ${saved.expiresAt})',
          );
          return true;
        }
        // فَشَل → امسَح وَأَخرِج
        await RememberMeService.instance.clear();
        return false;
      } catch (e) {
        M7Log.error('Auth', 'restoreSession (Supabase)', error: e);
        // اسقُط إلى مَنطِق MockRepository أَدناه
      }
    }

    // ===== Fallback: ابحَث في MockRepository (إذا تَمَّ مُزامَنَتُه) =====
    AppAccount? acc;
    try {
      acc = _repo.accounts
          .firstWhere((a) => a.id == saved.accountId);
    } catch (_) {}
    if (acc == null) {
      // 🆕 لا تَمسَح الـtoken عَلى الفَور — قَد يَكون MockRepository
      // غَير مُحَمَّل بَعد. اسمَح بِإعادة المُحاوَلة لاحِقاً.
      return false;
    }
    if (!acc.isActive) {
      await RememberMeService.instance.clear();
      return false;
    }

    // حمّل الجلسة كأنّها login عادي
    _account = acc;
    _roles = _repo.rolesOfAccount(acc.id);
    // 🆕 تَأكَّد أنّ إعدادات الترقية مُحَمَّلة قَبل حساب الصلاحيّات
    await PointAssignmentSettings.instance.load();
    _permissions = _repo.effectivePermissionKeys(acc.id);
    _countryIds = _repo.countryIdsOfAccount(acc.id);
    if (_roles.isEmpty && !acc.isSuperAdmin) {
      _account = null;
      await RememberMeService.instance.clear();
      return false;
    }
    _activeRole = _roles.isNotEmpty
        ? _roles.first
        : RoleDef(
            id: 'super',
            key: SystemRoles.superAdmin,
            nameAr: 'مدير عام',
            nameEn: 'Super Admin');
    _activeCountryId =
        _countryIds.isNotEmpty ? _countryIds.first : null;
    _legacyUser = _buildLegacyUser();
    _refreshAuditContext();
    // 🆕 حَمِّل تَفضيلات هذا المُستَخدِم (لُغة/theme/دَولة)
    await _loadUserPreferences(acc.id);
    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.login,
      description:
          'استرجاع جلسة محفوظة: ${acc.username} (تنتهي ${saved.expiresAt})',
    );
    // 🆕 رَبط FCM token (لِتَلَقّي Push Notifications)
    try {
      await FcmService.instance.bindToUser(acc.id);
    } catch (e) {
      M7Log.error('AuthProvider', 'bindToUser', error: e);
    }
    notifyListeners();
    return true;
  }

  /// 🆕 يَقرَأ تَفضيلات المُستَخدِم وَيُطَبِّقها (لُغة، theme، دَولة افتِراضيّة)
  Future<void> _loadUserPreferences(String accountId) async {
    try {
      await UserPreferencesService.instance.loadForUser(accountId);
      // طَبِّق الدَولة الافتِراضيّة لَو مَوجودة وَمَسموحة
      final defaultCountry =
          UserPreferencesService.instance.defaultCountryId;
      if (defaultCountry != null &&
          (_countryIds.contains(defaultCountry) || isSuperAdmin)) {
        _activeCountryId = defaultCountry;
      }
    } catch (e) {
      M7Log.error('AuthProvider', '_loadUserPreferences', error: e);
    }
  }

  /// تحميل بيانات المستخدم من Supabase
  Future<LoginResult> _loadFromSupabase(String userId) async {
    final acc = await _supabase.fetchAccount(userId);
    if (acc == null) return LoginResult.invalidCredentials;
    if (acc['is_active'] != true) return LoginResult.inactiveAccount;

    _account = AppAccount(
      id: acc['id'] as String,
      username: acc['username'] as String,
      passwordHash: '', // لا نخزّنها
      fullName: acc['full_name'] as String,
      email: acc['email'] as String?,
      phone: acc['phone'] as String?,
      employeeId: acc['employee_id'] as String?,
      isActive: acc['is_active'] as bool,
      isSuperAdmin: acc['is_super_admin'] as bool? ?? false,
      // 🆕 عَلَم إجبار تَغيير كلمة المرور
      mustChangePassword:
          (acc['must_change_password'] as bool?) ?? false,
      // 🆕 سياسة تَسجيل بَصمة الوَجه الإجباريّ
      mustEnrollFace: (acc['must_enroll_face'] as bool?) ?? false,
      firstLoginAt: acc['first_login_at'] == null
          ? null
          : DateTime.tryParse(acc['first_login_at'] as String),
      faceEnrolledAt: acc['face_enrolled_at'] == null
          ? null
          : DateTime.tryParse(acc['face_enrolled_at'] as String),
      // 🆕 نَوع الحِساب + النُقطة + الجِهاز المَربوط (لِـPoint Terminal)
      accountType: AccountTypeX.fromKey(acc['account_type'] as String?),
      pointId: acc['point_id'] as String?,
      linkedDeviceId: acc['linked_device_id'] as String?,
      // 🆕 الحَدّ الأَقصى لِعَدَد الأَجهِزة (0 = بِدون حَدّ)
      maxDevices: (acc['max_devices'] as num?)?.toInt() ?? 0,
    );

    // الأدوار
    final urs = await _supabase.fetchUserRoles(userId);
    _roles = urs.map((ur) {
      final r = ur['roles'] as Map<String, dynamic>;
      return RoleDef(
        id: ur['role_id'] as String,
        key: r['key'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
        priority: (r['priority'] as int?) ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    // الصلاحيات
    final permKeys = await _supabase.fetchEffectivePermissions(userId);
    // 🆕 تَأكَّد أنّ إعدادات الترقية مُحَمَّلة قَبل الدمج
    await PointAssignmentSettings.instance.load();
    // 🆕 ادمج صلاحيّات الترقية — يَستعمل المُطابقة الضِمنيّة (username ↔ code/name)
    // حَتّى لو account.employee_id غير مَضبوط.
    _permissions = _repo.mergePromotedPermissionsForAccount(
      permKeys.toSet(),
      _account,
    );

    // الدول
    _countryIds = await _supabase.fetchUserCountries(userId);

    // 🆕 حِسابات Point Terminal: تَحقُّق رَبط الجِهاز (Device Binding)
    //   • أَوَّل دُخول: ربط الجِهاز الحاليّ بِالحِساب
    //   • دُخول لاحِق: يَجِب أَن يُطابِق نَفس الجِهاز، وإلّا يُرفَض
    //   • Terminal لا يَحتاج أَدوار → نَتَجاوَز فَحص noRoles
    if (_account!.accountType == AccountType.pointTerminal) {
      final currentDevice =
          await DeviceSessionService.instance.ensureDeviceId();

      // 🆕 الفَحص الجَديد بِاستِخدام `point_terminal_sessions`:
      //   - إذا الجِهاز لَه جَلسة سابِقة → اسمَح (هو جِهاز مَعروف)
      //   - وَإلا → عُدّ الأَجهِزة المُتَّصِلة، إذا < max_devices أَو
      //     max_devices == 0 (بِدون حَدّ) → اسمَح، وَإلا → ارفُض.
      try {
        final existingSession = await _supabase.client
            .from('point_terminal_sessions')
            .select('id')
            .eq('account_id', _account!.id)
            .eq('device_id', currentDevice)
            .eq('is_active', true)
            .maybeSingle();
        if (existingSession == null) {
          // جِهاز جَديد — تَحَقَّق من الحَدّ الأَقصى
          final max = _account!.maxDevices;
          if (max > 0) {
            final activeRows = await _supabase.client
                .from('point_terminal_sessions')
                .select('device_id')
                .eq('account_id', _account!.id)
                .eq('is_active', true);
            final activeDevices =
                (activeRows as List).map((r) => r['device_id']).toSet();
            if (activeDevices.length >= max) {
              _account = null;
              _roles = [];
              _permissions = {};
              _countryIds = [];
              return LoginResult.deviceBlocked;
            }
          }
        }
        // اربِط الجِهاز كَأَوَّل جِهاز (لِلتَوافُق الخَلفيّ — أَوَّل واحِد فَقَط)
        if (_account!.linkedDeviceId == null ||
            _account!.linkedDeviceId!.isEmpty) {
          try {
            await _supabase.client.from('accounts').update({
              'linked_device_id': currentDevice,
            }).eq('id', _account!.id);
            _account!.linkedDeviceId = currentDevice;
          } catch (_) {}
        }
      } catch (e) {
        M7Log.error('Auth', 'pointTerminal multi-device check',
            error: e);
      }

      // 🆕 سَجِّل جَلسة Terminal في الجَدول المُخَصَّص `point_terminal_sessions`
      // (لا نَستَخدِم employee_device_sessions لِأَنّ Terminal لا مُوَظَّف لَه)
      try {
        if (_account!.pointId != null) {
          await PointTerminalSessionService.instance.registerOnLogin(
            accountId: _account!.id,
            pointId: _account!.pointId!,
          );
        }
      } catch (e) {
        M7Log.error('Auth', 'terminal session register', error: e);
      }

      // 🆕 سَجِّل في السِجِلّ التَدقيقيّ
      _refreshAuditContext();
      try {
        AuditLogger.instance.log(
          entityType: 'session',
          action: AuditAction.login,
          description:
              'دُخول جِهاز نُقطة: ${_account!.username} (point: ${_account!.pointId})',
        );
      } catch (_) {}

      // 🆕 حَدِّث آخِر دُخول عَلى الحِساب
      try {
        await _supabase.client.from('accounts').update({
          'last_login_at':
              DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _account!.id);
        _account!.lastLoginAt = DateTime.now();
      } catch (_) {}

      // Terminal: لَيس بِحاجة لِأَدوار — تَخَطّى الفَحص
      _activeRole = null;
      _activeCountryId = _countryIds.isNotEmpty ? _countryIds.first : null;
      notifyListeners();
      return LoginResult.success;
    }

    if (_roles.isEmpty && !_account!.isSuperAdmin) {
      return LoginResult.noRoles;
    }

    // 🆕 فحص Geo-fence (قبل تسجيل الجهاز)
    final geoResult = await _runGeoFenceCheck(_account!.id);
    if (geoResult != null) {
      _account = null;
      _roles = [];
      _permissions = {};
      _countryIds = [];
      return geoResult;
    }

    // 🆕 سجّل جلسة الجهاز (مع احترام إعدادات السياسة المتشدّدة)
    await DeviceSessionSettings.instance.load();
    final strict =
        DeviceSessionSettings.instance.appliesTo(_account!.id);
    final dev = await DeviceSessionService.instance.registerOnLogin(
      accountId: _account!.id,
      employeeId: _account!.employeeId,
      strictOneDevice: strict,
    );
    if (dev.blocked) {
      // المستخدم حاول الدخول من جهاز جديد بينما سياسة "جهاز واحد متشدّدة" مفعّلة
      _account = null;
      _roles = [];
      _permissions = {};
      _countryIds = [];
      return LoginResult.deviceBlocked;
    }

    // الدور الافتراضي = الأعلى أولوية
    _activeRole = _roles.isEmpty
        ? RoleDef(
            id: 'super',
            key: SystemRoles.superAdmin,
            nameAr: 'مدير عام',
            nameEn: 'Super Admin')
        : _roles.first;

    // إذا دولة واحدة فقط: نختارها تلقائياً
    // إذا متعددة: تبقى null حتى يختار المستخدم
    _activeCountryId =
        _countryIds.length == 1 ? _countryIds.first : null;

    _legacyUser = _buildLegacyUser();
    // 🆕 تَهيئة خِدمة الإشعارات لِلْمُستخدِم الحاليّ
    NotificationsService.instance.initForUser(_account!.id);
    // 🆕 تَشغيل المُزامَنة الحَيّة (Realtime)
    RealtimeSyncService.instance.start(_account!.id);
    // 🆕 رَبط FCM token (لِتَلَقّي Push Notifications)
    debugPrint('🟢 Login (Supabase) succeeded — calling FCM bindToUser for ${_account!.id}');
    try {
      await FcmService.instance.bindToUser(_account!.id);
    } catch (e) {
      debugPrint('⚠ FCM bindToUser failed: $e');
    }
    notifyListeners();
    return LoginResult.success;
  }

  /// Mock login - يستخدم accounts من MockRepository
  Future<LoginResult> _loginMock(String username, String password) async {
    final acc = _repo.authenticate(username, password);
    if (acc == null) {
      // 🔒 SECURITY: تَمّت إزالة الباب الخلفي القديم (أي مستخدم + كلمة المرور
      // "123456" كان يُسجِّل الدخول). لا يوجد الآن مسار دخول بلا كلمة مرور صحيحة.
      return LoginResult.invalidCredentials;
    }

    if (!acc.isActive) return LoginResult.inactiveAccount;

    // 🆕 فحص "على رأس العمل فقط" — قبل أي شيء آخر
    final dutyResult = await _runActiveDutyCheck(acc);
    if (dutyResult != null) return dutyResult;

    // 🆕 لو الحساب مُعدّ لبصمة الوجه فقط، ارفض الدخول بكلمة المرور
    await LoginMethodSettings.instance.load();
    if (LoginMethodSettings.instance.methodFor(acc.id) == LoginMethod.face) {
      // إلّا إذا كانت "كلمة المرور كنسخة احتياطيّة" مفعّلة
      if (!LoginMethodSettings.instance.allowPwdFallback) {
        return LoginResult.faceRequired;
      }
    }

    _account = acc;
    _roles = _repo.rolesOfAccount(acc.id);
    _permissions = _repo.effectivePermissionKeys(acc.id);
    _countryIds = _repo.countryIdsOfAccount(acc.id);

    if (_roles.isEmpty && !acc.isSuperAdmin) {
      return LoginResult.noRoles;
    }

    // 🆕 فحص Geo-fence
    final geoResult = await _runGeoFenceCheck(acc.id);
    if (geoResult != null) {
      _account = null;
      _legacyUser = null;
      _roles = [];
      _permissions = {};
      _countryIds = [];
      AuditLogger.instance.clearContext();
      return geoResult;
    }

    _activeRole = _roles.isNotEmpty
        ? _roles.first
        : RoleDef(
            id: 'super',
            key: SystemRoles.superAdmin,
            nameAr: 'مدير عام',
            nameEn: 'Super Admin');
    _activeCountryId =
        _countryIds.isNotEmpty ? _countryIds.first : null;

    _legacyUser = _buildLegacyUser();
    _refreshAuditContext();
    // 🆕 حَمِّل تَفضيلات هذا المُستَخدِم
    await _loadUserPreferences(acc.id);
    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.login,
      description: 'تسجيل دخول: ${_account?.username ?? ''}',
    );
    // 🆕 سجّل جلسة الجهاز (تنجح فقط لو Supabase متّصل)
    try {
      await DeviceSessionSettings.instance.load();
      final strict = DeviceSessionSettings.instance.appliesTo(acc.id);
      final dev = await DeviceSessionService.instance.registerOnLogin(
        accountId: acc.id,
        employeeId: acc.employeeId,
        strictOneDevice: strict,
      );
      if (dev.blocked) {
        // Mock fallback لا يفترض الوصول لهنا، لكن نحترم السياسة
        _account = null;
        _legacyUser = null;
        _roles = [];
        _permissions = {};
        _countryIds = [];
        AuditLogger.instance.clearContext();
        return LoginResult.deviceBlocked;
      }
    } catch (_) {}

    // 🆕 رَبط FCM token بِالمُستَخدِم (لِتَلَقّي Push Notifications)
    try {
      await FcmService.instance.bindToUser(acc.id);
    } catch (e) {
      debugPrint('⚠ FCM bindToUser failed (non-fatal): $e');
    }

    // 🐛 عَيِّن المُستَخدِم في Sentry (لا اسم/email — فَقَط ID وَدَور)
    try {
      ErrorTrackingService.instance.setUser(
        accountId: acc.id,
        employeeId: acc.employeeId,
        role: _activeRole?.key,
        accountType: acc.accountType.name,
      );
      ErrorTrackingService.instance.addBreadcrumb(
        message: 'login_success',
        category: 'auth',
        data: {'account_type': acc.accountType.name},
      );
    } catch (_) {/* غَير حاسِم */}

    // 🏢 حَمِّل tenant context (Multi-tenancy Phase 1)
    try {
      await TenantContext.instance.loadFor(acc.id);
      if (TenantContext.instance.tenantId != null) {
        ErrorTrackingService.instance
            .setTag('tenant_id', TenantContext.instance.tenantId!);
      }
    } catch (_) {/* غَير حاسِم — backward compat */}

    notifyListeners();
    return LoginResult.success;
  }

  /// Logout
  // ============================================================
  // 🆕 Impersonate (Super Admin only)
  // ============================================================
  /// يبدأ "العرض كحساب فلان" — يحفظ الجلسة الحاليّة ويبدّلها بحساب الهدف.
  /// يجب أن يكون المستخدم الحالي Super Admin.
  void startImpersonate(String targetAccountId) {
    if (!isSuperAdmin) return;
    if (isImpersonating) return; // لا تتداخل العمليّات
    final target = _repo.accounts.firstWhere(
      (a) => a.id == targetAccountId,
      orElse: () => AppAccount(
        id: '',
        username: '',
        passwordHash: '',
        fullName: '',
      ),
    );
    if (target.id.isEmpty) return;

    // 1) احفظ الأصلي
    _origAccount = _account;
    _origLegacyUser = _legacyUser;
    _origRoles = List<RoleDef>.from(_roles);
    _origPermissions = Set<String>.from(_permissions);
    _origCountryIds = List<String>.from(_countryIds);
    _origActiveRole = _activeRole;
    _origActiveCountryId = _activeCountryId;
    _origActiveSiteId = _activeSiteId;

    // 2) بدّل إلى الهدف
    _account = target;
    _roles = _repo.rolesOfAccount(target.id);
    // اجمع كل صلاحيّات الأدوار → permissions
    final permKeys = <String>{};
    for (final r in _roles) {
      permKeys.addAll(_repo.permissionKeysForRole(r.id));
    }
    _permissions = permKeys;
    _countryIds = _repo.countryIdsOfAccount(target.id);
    _activeRole = _roles.isEmpty
        ? _origActiveRole
        : (_repo.defaultRoleForAccount(target.id) ?? _roles.first);
    _activeCountryId =
        _countryIds.length == 1 ? _countryIds.first : null;
    _activeSiteId = null;
    _legacyUser = _buildLegacyUser();

    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.update,
      description:
          'بدأ العرض كحساب: ${_origAccount?.username} → ${target.username}',
    );
    _refreshAuditContext();
    notifyListeners();
  }

  /// ينهي "العرض كحساب فلان" ويعيد الجلسة الأصليّة.
  void stopImpersonate() {
    if (!isImpersonating) return;
    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.update,
      description:
          'انتهى العرض كحساب: ${_account?.username} → عاد إلى ${_origAccount?.username}',
    );
    _account = _origAccount;
    _legacyUser = _origLegacyUser;
    _roles = _origRoles ?? [];
    _permissions = _origPermissions ?? <String>{};
    _countryIds = _origCountryIds ?? [];
    _activeRole = _origActiveRole;
    _activeCountryId = _origActiveCountryId;
    _activeSiteId = _origActiveSiteId;

    _origAccount = null;
    _origLegacyUser = null;
    _origRoles = null;
    _origPermissions = null;
    _origCountryIds = null;
    _origActiveRole = null;
    _origActiveCountryId = null;
    _origActiveSiteId = null;

    _refreshAuditContext();
    notifyListeners();
  }

  /// 🆕 يُستَدعى بَعد نَجاح تَغيير كلمة المرور لإجبار إعادة بِناء الواجهة
  /// (تَختَفي شاشة force change password).
  void notifyPasswordChanged() {
    notifyListeners();
  }

  Future<void> logout() async {
    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.logout,
      description: 'تسجيل خروج: ${_account?.username ?? ''}',
    );
    // 🆕 عطّل جلسة الجهاز الحاليّة قبل المسح
    final accId = _account?.id;
    final isTerminal =
        _account?.accountType == AccountType.pointTerminal;
    if (accId != null) {
      try {
        if (isTerminal) {
          await PointTerminalSessionService.instance
              .deactivateOnLogout(accountId: accId);
        } else {
          await DeviceSessionService.instance
              .deactivateOnLogout(accountId: accId);
        }
      } catch (_) {}
    }
    // 🆕 امسح token "تذكّرني"
    try {
      await RememberMeService.instance.clear();
    } catch (_) {}
    // 🆕 فُكّ ربط FCM token (لا يَستَلِم إشعارات بَعد الخُروج)
    try {
      await FcmService.instance.unbind();
    } catch (_) {}
    // 🆕 امسح تَفضيلات المُستَخدِم الحاليّ مِن الـmemory (الكاش المَحَلِّيّ يَبقى)
    try {
      UserPreferencesService.instance.clearOnLogout();
    } catch (_) {}
    _account = null;
    _legacyUser = null;
    _roles = [];
    _permissions = {};
    _countryIds = [];
    _activeRole = null;
    _activeCountryId = null;
    _activeSiteId = null;
    AuditLogger.instance.clearContext();
    // 🆕 امسح cache الإشعارات
    NotificationsService.instance.clear();
    // 🆕 أَوقِف المُزامَنة الحَيّة
    RealtimeSyncService.instance.stop();
    // تسجيل خروج من Supabase Auth أيضاً
    try {
      await _supabase.signOut();
    } catch (_) {}
    // 🐛 امسَح المُستَخدِم مِن Sentry (لا تَرتَبِط أَخطاء مُستَقبَليّة بِهذا الحِساب)
    try {
      ErrorTrackingService.instance.clearUser();
      ErrorTrackingService.instance.addBreadcrumb(
        message: 'logout',
        category: 'auth',
      );
    } catch (_) {/* غَير حاسِم */}
    // 🏢 امسَح tenant context
    try {
      TenantContext.instance.clear();
    } catch (_) {/* غَير حاسِم */}
    notifyListeners();
  }

  // ==== Helpers ====

  AppUser? _buildLegacyUser() {
    if (_account == null) return null;
    final role = _activeRole == null
        ? UserRole.employee
        : _legacyRoleFromKey(_activeRole!.key);
    return AppUser(
      id: _account!.id,
      username: _account!.username,
      fullName: _account!.fullName,
      role: role,
      employeeId: _account!.employeeId,
    );
  }

  UserRole _legacyRoleFromKey(String key) {
    switch (key) {
      case SystemRoles.superAdmin:
      case SystemRoles.admin:
      case SystemRoles.manager:
        return UserRole.manager;
      case SystemRoles.operation:
        return UserRole.operation;
      case SystemRoles.supervisor:
        return UserRole.supervisor;
      case SystemRoles.campBoss:
        return UserRole.campBoss;
      case SystemRoles.driver:
        return UserRole.driver;
      case SystemRoles.employee:
      default:
        return UserRole.employee;
    }
  }

  // 🔒 SECURITY: أُزيلت الدالة _legacyKeyFromRole (كانت تُستخدَم فقط في الباب
  // الخلفي القديم الذي حُذف).

  // ============================================================
  // 👤 Face login pre-flight + finalize
  // ============================================================

  /// قبل فتح شاشة بصمة الوجه: نعرف هل الحساب موجود + ما طريقته
  /// + هل في cooldown/قفل.
  /// يُرجع تفاصيل أو خطأ.
  Future<FacePreflightResult> faceLoginPreflight(String username) async {
    final cleanUser = username.trim();
    if (cleanUser.isEmpty) {
      return FacePreflightResult.error(LoginResult.invalidCredentials);
    }

    // 1) جد الحساب
    AppAccount? account;
    try {
      account =
          _repo.accounts.firstWhere((a) => a.username.toLowerCase() == cleanUser.toLowerCase());
    } catch (_) {}

    // إن لم يوجد محلياً جرّب Supabase
    if (account == null && _supabase.isReady) {
      try {
        final r = await _supabase.client
            .from('accounts')
            .select('id, username, full_name, employee_id, is_active')
            .eq('username', cleanUser)
            .maybeSingle();
        if (r != null) {
          account = AppAccount(
            id: r['id'] as String,
            username: r['username'] as String,
            passwordHash: '',
            fullName: r['full_name'] as String? ?? cleanUser,
            employeeId: r['employee_id'] as String?,
            isActive: r['is_active'] as bool? ?? true,
          );
        }
      } catch (_) {}
    }

    if (account == null) {
      return FacePreflightResult.error(LoginResult.invalidCredentials);
    }
    if (!account.isActive) {
      return FacePreflightResult.error(LoginResult.inactiveAccount);
    }

    // 2) تحقّق من طريقة الدخول
    await LoginMethodSettings.instance.load();
    final method = LoginMethodSettings.instance.methodFor(account.id);
    if (method != LoginMethod.face) {
      return FacePreflightResult.error(LoginResult.passwordRequired);
    }

    // 3) فحص حالة العدّاد (تهدئة/قفل)
    final status = await FaceAttemptTracker.instance.currentStatus(account.id);
    if (status.outcome == FaceAttemptOutcome.locked) {
      return FacePreflightResult.error(LoginResult.faceLocked);
    }
    if (status.outcome == FaceAttemptOutcome.cooldown) {
      return FacePreflightResult.error(
        LoginResult.faceCooldown,
        cooldownUntil: status.cooldownUntil,
      );
    }

    return FacePreflightResult.ok(
      accountId: account.id,
      fullName: account.fullName,
    );
  }

  /// إنهاء تسجيل الدخول بعد نجاح المطابقة في شاشة الوجه
  Future<LoginResult> finalizeFaceLogin({
    required String accountId,
    required double matchScore,
  }) async {
    AppAccount? acc;
    try {
      acc = _repo.accounts.firstWhere((a) => a.id == accountId);
    } catch (_) {}
    if (acc == null) return LoginResult.invalidCredentials;
    if (!acc.isActive) return LoginResult.inactiveAccount;

    // ضبط الجلسة كاملة (نفس Mock login لكن بدون كلمة مرور)
    _account = acc;
    _roles = _repo.rolesOfAccount(acc.id);
    _permissions = _repo.effectivePermissionKeys(acc.id);
    _countryIds = _repo.countryIdsOfAccount(acc.id);
    if (_roles.isEmpty && !acc.isSuperAdmin) {
      _account = null;
      return LoginResult.noRoles;
    }

    // 🆕 2026-05-25: نَجاح الدُخول بِالوَجه يُثبِت وُجود تَسجيل صالِح
    // → اِرفَع علم mustEnrollFace + ضَع faceEnrolledAt إذا لَم يَكُن مَوجوداً
    // (يَمنَع التَوجيه إلى MandatoryFaceEnrollmentScreen بَعد الدُخول)
    if (acc.mustEnrollFace || acc.faceEnrolledAt == null) {
      acc.mustEnrollFace = false;
      acc.faceEnrolledAt ??= DateTime.now();
      try {
        final supa = SupabaseService();
        if (supa.isReady) {
          // ignore: discarded_futures
          supa.client.from('accounts').update({
            'must_enroll_face': false,
            'face_enrolled_at':
                (acc.faceEnrolledAt ?? DateTime.now()).toUtc().toIso8601String(),
          }).eq('id', acc.id);
        }
      } catch (e) {
        M7Log.warn('FaceLogin', 'failed to clear mustEnrollFace: $e');
      }
    }

    // فحص Geo-fence
    final geoResult = await _runGeoFenceCheck(acc.id);
    if (geoResult != null) {
      _account = null;
      _roles = [];
      _permissions = {};
      _countryIds = [];
      return geoResult;
    }

    _activeRole = _roles.isNotEmpty
        ? _roles.first
        : RoleDef(
            id: 'super',
            key: SystemRoles.superAdmin,
            nameAr: 'مدير عام',
            nameEn: 'Super Admin');
    _activeCountryId =
        _countryIds.isNotEmpty ? _countryIds.first : null;

    _legacyUser = _buildLegacyUser();
    _refreshAuditContext();

    // ✓ صفّر عدّاد الفشل
    await FaceAttemptTracker.instance.recordSuccess(acc.id);

    AuditLogger.instance.log(
      entityType: 'session',
      action: AuditAction.login,
      description:
          'تسجيل دخول ببصمة الوجه: ${acc.username} (تطابق ${(matchScore * 100).toStringAsFixed(0)}%)',
    );

    // سجّل الجهاز
    try {
      await DeviceSessionSettings.instance.load();
      final strict = DeviceSessionSettings.instance.appliesTo(acc.id);
      final dev = await DeviceSessionService.instance.registerOnLogin(
        accountId: acc.id,
        employeeId: acc.employeeId,
        strictOneDevice: strict,
      );
      if (dev.blocked) {
        _account = null;
        _legacyUser = null;
        _roles = [];
        _permissions = {};
        _countryIds = [];
        AuditLogger.instance.clearContext();
        return LoginResult.deviceBlocked;
      }
    } catch (_) {}

    notifyListeners();
    return LoginResult.success;
  }

  /// تسجيل فشل في المطابقة (يستدعى من شاشة بصمة الوجه)
  /// يُرجع الحالة الجديدة (قد تنتقل إلى تهدئة أو قفل).
  Future<FaceAttemptStatus> recordFaceFailure(String accountId) async {
    return FaceAttemptTracker.instance.recordFailure(accountId);
  }

  // ============================================================
  // 🌍 Geo-fence check (returns null if OK, otherwise LoginResult.*)
  // ============================================================
  /// آخر تفاصيل فشل Geo-fence (لعرضها في شاشة الدخول)
  GeoFenceFailDetails? _lastGeoFenceFail;
  GeoFenceFailDetails? get lastGeoFenceFail => _lastGeoFenceFail;

  /// 🆕 آخر رسالة من فحص "على رأس العمل فقط"
  String? _lastDutyBlockMessageAr;
  String? _lastDutyBlockMessageEn;
  String? get lastDutyBlockMessageAr => _lastDutyBlockMessageAr;
  String? get lastDutyBlockMessageEn => _lastDutyBlockMessageEn;

  /// 🆕 فحص سياسة "التطبيق على رأس العمل فقط"
  /// يُرجع null إذا الدخول مسموح، أو LoginResult مع تفاصيل المنع
  Future<LoginResult?> _runActiveDutyCheck(AppAccount acc) async {
    try {
      await ActiveDutySettings.instance.load();
      final settings = ActiveDutySettings.instance;

      // الأَدوار التي يَملِكها المُستَخدِم
      final roleKeys = _repo.rolesOfAccount(acc.id).map((r) => r.key).toList();

      // هل تَنطَبِق السياسة على هذا الحِساب؟
      if (!settings.appliesTo(acc.id, userRoleKeys: roleKeys)) {
        _lastDutyBlockMessageAr = null;
        _lastDutyBlockMessageEn = null;
        return null;
      }

      // 1) فحص التعليق (suspended)
      if (settings.checkSuspension) {
        final empId = acc.employeeId;
        if (empId != null) {
          try {
            final emp = _repo.employees.firstWhere((e) => e.id == empId);
            if (emp.status != EntityStatus.active) {
              _lastDutyBlockMessageAr = settings.messageSuspendedAr;
              _lastDutyBlockMessageEn = settings.messageSuspendedEn;
              return LoginResult.accountSuspended;
            }
          } catch (_) {
            // الموظف غير موجود → نَتَجاوَز
          }
        }
      }

      // 2) فحص الإجازة المُعتَمَدة السارِية اليَوم
      if (settings.checkLeave) {
        final empId = acc.employeeId;
        if (empId != null) {
          final today = DateTime.now();
          final todayDateOnly =
              DateTime(today.year, today.month, today.day);
          // نَقرَأ من LeaveService الذي يَحفَظ كُلّ الطَلَبات
          final onLeave = LeaveService.instance.requests.any((lr) {
            if (lr.employeeId != empId) return false;
            if (lr.status != LeaveStatus.approved) return false;
            // تَحَقَّق أَنّ اليَوم بَين start_date وend_date
            final s = DateTime(
                lr.startDate.year, lr.startDate.month, lr.startDate.day);
            final e = DateTime(
                lr.endDate.year, lr.endDate.month, lr.endDate.day);
            return !todayDateOnly.isBefore(s) && !todayDateOnly.isAfter(e);
          });
          if (onLeave) {
            _lastDutyBlockMessageAr = settings.messageLeaveAr;
            _lastDutyBlockMessageEn = settings.messageLeaveEn;
            return LoginResult.onApprovedLeave;
          }
        }
      }

      _lastDutyBlockMessageAr = null;
      _lastDutyBlockMessageEn = null;
      return null;
    } catch (_) {
      // أَيّ خَطَأ → لا نَمنَع الدُخول (fail-open لِلسَلامة)
      return null;
    }
  }

  Future<LoginResult?> _runGeoFenceCheck(String accountId) async {
    try {
      await GeoFenceSettings.instance.load();
      final settings = GeoFenceSettings.instance;
      final enforce = settings.appliesTo(accountId);
      final result = await GeoFenceService.instance.check(enforce: enforce);
      if (result.allowed) {
        _lastGeoFenceFail = null;
        return null;
      }
      LoginResult code;
      switch (result.rejection) {
        case GeoFenceRejection.mockLocationDetected:
          code = LoginResult.geoFenceMockLocation;
          break;
        case GeoFenceRejection.permissionDenied:
        case GeoFenceRejection.serviceDisabled:
          code = LoginResult.geoFencePermissionDenied;
          break;
        case GeoFenceRejection.outsideZone:
        case GeoFenceRejection.unknown:
        default:
          code = LoginResult.geoFenceRejected;
      }
      _lastGeoFenceFail = GeoFenceFailDetails(
        result: code,
        warning: result.warning,
        latitude: result.latitude,
        longitude: result.longitude,
      );
      AuditLogger.instance.log(
        entityType: 'session',
        action: AuditAction.update,
        description:
            'رفض دخول (geo-fence): $accountId — ${result.rejection?.name}',
      );
      return code;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('Auth', 'geo-fence check', error: e);
      // إذا حصل خطأ غير متوقّع، نسمح (فشل آمن)
      return null;
    }
  }
}

