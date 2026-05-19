import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../repositories/rbac_seed.dart';
import 'audit_logger.dart';
import 'm7_log.dart';
import 'supabase_service.dart';

/// 🆕 نتيجة عمليّة الإدراج الجماعي (bulk insert)
class BulkInsertResult {
  final int added;
  final int skipped;
  final int failed;
  final List<String> failedReasons;
  const BulkInsertResult({
    required this.added,
    required this.skipped,
    required this.failed,
    required this.failedReasons,
  });

  int get total => added + skipped + failed;
}

/// خدمة موحّدة لمزامنة البيانات بين Supabase والـ MockRepository
///
/// المنطق:
/// - عند الإقلاع: نسحب الدول/المدن/المناطق من Supabase ونعبّئ MockRepository
/// - عند الإنشاء/التحديث/الحذف: نكتب أولاً لـ Supabase، ثم نُحدّث MockRepository
///
/// بهذا الشكل، الواجهات الحالية (التي تقرأ من repo.countries/repo.points) لا تتغيّر،
/// لكن البيانات أصبحت محفوظة فعلياً في Supabase
class SupabaseDataService {
  static SupabaseDataService? _instance;
  factory SupabaseDataService() => _instance ??= SupabaseDataService._();
  SupabaseDataService._();

  final _supabase = SupabaseService();
  final _repo = MockRepository();

  bool _initialSynced = false;
  bool get isSynced => _initialSynced;

  /// مزامنة كاملة عند الإقلاع
  Future<void> initialSync() async {
    if (!_supabase.isReady) return;
    try {
      await syncCountries();
      await syncCities();
      await syncAreas();
      await syncBusinessTypes();
      await syncJobTitles();
      await syncDepartments();
      await syncMaritalStatuses();
      await syncNationalities();
      await syncVisaTypes();
      await syncNumberingRules();
      await syncNumberingCounters();
      await syncMasters();
      await syncPoints();
      await syncSites();
      await syncPointClientLinks();
      await syncEmployees();
      await syncBuses();
      await syncBusEmployees();         // 🆕
      await syncBusDriverShifts();      // 🆕
      await syncEmployeeBusAssignments(); // 🆕 overrides اليوميّة (موظّف/أسبوع/يوم)
      await syncEmployeeDailyMemos();     // 🆕 مذكّرة الموظّف اليوميّة
      await syncRosters();
      await syncBusPlans();
      await syncTransportModes();       // 🆕 قبل syncEmployees غير ضروري لكن مفيد
      await syncRoomTypes();            // 🆕 قبل syncRooms (references room_type_id)
      await syncRooms();
      await syncViolations();
      await syncLaundryBatches();       // 🆕 قبل التذاكر
      await syncLaundryTickets();
      await syncUniformItems();         // 🆕 يونيفورم
      await syncUniformReceipts();      // 🆕
      await syncEmployeeUniforms();     // 🆕
      await syncMorningChecklists();
      await syncRoles();
      await syncPermissions();
      await syncRolePermissions();
      await syncRoomEvaluations();      // 🆕
      await syncEmployeeEvaluations();  // 🆕
      await syncDriverEvaluations();    // 🆕
      await syncAccounts();
      _initialSynced = true;
      // ignore: avoid_print
      M7Log.info('DataService', 'initial sync done');
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DataService', 'sync failed', error: e);
    }
  }

  // ==========================================================
  // Business Types & Other Simple Lookups
  // ==========================================================

  Future<void> syncBusinessTypes() async {
    final rows = await _c.from('business_types').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.businessTypes.clear();
    for (final r in list) {
      _repo.businessTypes.add(BusinessType(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
      ));
    }
    _repo.notifyListeners();
  }

  Future<void> syncJobTitles() async {
    final rows = await _c.from('job_titles').select();
    final list = (rows as List).cast<Map<String, dynamic>>();

    // 🆕 Phase A: اقرأ علاقات reports_to من الجدول الفرعي
    Map<String, List<Map<String, dynamic>>> reportsBy = {};
    try {
      final reportsRows = await _c.from('job_title_reports_to').select();
      final reportsList = (reportsRows as List).cast<Map<String, dynamic>>();
      for (final r in reportsList) {
        final src = r['job_title_id'] as String?;
        if (src == null) continue;
        reportsBy.putIfAbsent(src, () => []).add(r);
      }
    } catch (_) {
      // الجدول قد لا يكون مُنشأً بعد
      reportsBy = {};
    }

    _repo.jobTitles.clear();
    for (final r in list) {
      final id = r['id'] as String;
      final reportsRows = reportsBy[id] ?? const <Map<String, dynamic>>[];
      final reportsToIds = reportsRows
          .map((m) => m['reports_to_id'] as String?)
          .whereType<String>()
          .toList();
      String? primaryReportsToId;
      for (final m in reportsRows) {
        if ((m['is_primary'] as bool?) == true) {
          primaryReportsToId = m['reports_to_id'] as String?;
          break;
        }
      }
      _repo.jobTitles.add(JobTitle(
        id: id,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
        category: JobTitleCategoryX.fromKey(r['category'] as String?),
        roleId: r['role_id'] as String?,
        isSupervisor: (r['is_supervisor'] as bool?) ?? false,
        // 🆕 Phase A: حقول الهيكل الغنيّة
        level: (r['level'] as int?) ?? 0,
        reportsToIds: reportsToIds,
        primaryReportsToId: primaryReportsToId,
        color: r['color'] as String?,
        dashboardType: DashboardTypeX.fromKey(r['dashboard_type'] as String?),
        allowedScreens: (r['allowed_screens'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        approvalPower: (r['approval_power'] as int?) ?? 0,
        kpiTargets:
            Map<String, dynamic>.from(r['kpi_targets'] as Map? ?? const {}),
        notificationRules: Map<String, dynamic>.from(
            r['notification_rules'] as Map? ?? const {}),
      ));
    }
    _repo.notifyListeners();
  }

  Future<void> syncDepartments() async {
    final rows = await _c.from('departments').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.departments.clear();
    for (final r in list) {
      _repo.departments.add(Department(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
        category: JobTitleCategoryX.fromKey(r['category'] as String?),
        // 🆕 Phase A: حقول الهيكل
        parentId: r['parent_id'] as String?,
        level: (r['level'] as int?) ?? 0,
      ));
    }
    _repo.notifyListeners();
  }

  Future<void> syncMaritalStatuses() async {
    final rows = await _c.from('marital_statuses').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.maritalStatuses.clear();
    for (final r in list) {
      _repo.maritalStatuses.add(MaritalStatusItem(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
      ));
    }
    _repo.notifyListeners();
  }

  Future<void> syncNationalities() async {
    final rows = await _c.from('nationalities').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.nationalities.clear();
    for (final r in list) {
      _repo.nationalities.add(Nationality(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
      ));
    }
    _repo.notifyListeners();
  }

  Future<void> syncVisaTypes() async {
    final rows = await _c.from('visa_types').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.visaTypes.clear();
    for (final r in list) {
      _repo.visaTypes.add(VisaType(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
      ));
    }
    _repo.notifyListeners();
  }

  // ============================================================
  // 🆕 CRUD مشترك للقوائم البسيطة (Job Titles, Departments, ...)
  // ============================================================
  /// إنشاء عنصر بسيط (name_ar, name_en) في أي جدول lookup
  /// 🆕 يدعم extras اختيارية (مثل category للـ job_titles)
  Future<String?> createSimpleLookup({
    required String table,
    required String nameAr,
    required String nameEn,
    Map<String, dynamic>? extras,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'name_ar': nameAr,
        'name_en': nameEn,
        if (extras != null) ...extras,
      };
      final r = await _c
          .from(table)
          .insert(payload)
          .select()
          .single();
      lastError = null;
      return r['id'] as String?;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createSimpleLookup($table)', error: e);
      return null;
    }
  }

  Future<bool> updateSimpleLookup({
    required String table,
    required String id,
    required String nameAr,
    required String nameEn,
    Map<String, dynamic>? extras,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{
        'name_ar': nameAr,
        'name_en': nameEn,
        if (extras != null) ...extras,
      };
      await _c
          .from(table)
          .update(payload)
          .eq('id', id);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateSimpleLookup($table)', error: e);
      return false;
    }
  }

  // ============================================================
  // 🆕 Phase A: حقول JobTitle الغنيّة + reports_to
  // ============================================================
  /// يحدّث الحقول الغنيّة لمسمّى وظيفي في Supabase
  Future<bool> updateJobTitleRichFields({
    required String id,
    int? level,
    String? color,
    String? dashboardType,
    int? approvalPower,
    List<String>? allowedScreens,
    Map<String, dynamic>? kpiTargets,
    Map<String, dynamic>? notificationRules,
    bool? isSupervisor,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{
        if (level != null) 'level': level,
        if (color != null) 'color': color,
        if (dashboardType != null) 'dashboard_type': dashboardType,
        if (approvalPower != null) 'approval_power': approvalPower,
        if (allowedScreens != null) 'allowed_screens': allowedScreens,
        if (kpiTargets != null) 'kpi_targets': kpiTargets,
        if (notificationRules != null) 'notification_rules': notificationRules,
        if (isSupervisor != null) 'is_supervisor': isSupervisor,
      };
      if (payload.isEmpty) return true;
      await _c.from('job_titles').update(payload).eq('id', id);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateJobTitleRichFields', error: e);
      return false;
    }
  }

  /// يحدّث parent_id و level لقسم
  Future<bool> updateDepartmentHierarchy({
    required String id,
    String? parentId,
    int? level,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{
        'parent_id': parentId, // قد تكون null لرفع القسم للجذر
        if (level != null) 'level': level,
      };
      await _c.from('departments').update(payload).eq('id', id);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateDepartmentHierarchy', error: e);
      return false;
    }
  }

  /// يستبدل علاقات reports_to لمسمّى وظيفي بقائمة جديدة (delete+insert)
  Future<bool> setJobTitleReportsTo({
    required String jobTitleId,
    required List<String> reportsToIds,
    String? primaryReportsToId,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      // حذف الموجود
      await _c
          .from('job_title_reports_to')
          .delete()
          .eq('job_title_id', jobTitleId);
      // إدراج الجديد
      if (reportsToIds.isNotEmpty) {
        final payload = reportsToIds.map((rid) => {
              'job_title_id': jobTitleId,
              'reports_to_id': rid,
              'is_primary': rid == primaryReportsToId,
            }).toList();
        await _c.from('job_title_reports_to').insert(payload);
      }
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'setJobTitleReportsTo', error: e);
      return false;
    }
  }

  Future<bool> deleteSimpleLookup({
    required String table,
    required String id,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from(table).delete().eq('id', id);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteSimpleLookup($table)', error: e);
      return false;
    }
  }

  SupabaseClient get _c => _supabase.client;
  /// 🆕 وصول مباشر للعميل من الكود الخارجي (لاستخدامات نادرة)
  SupabaseClient get client => _supabase.client;

  // ============================================================
  // 🖼️ رفع الصور إلى Supabase Storage (موحّد للتطبيق كلّه)
  // ============================================================
  /// يرفع `bytes` إلى bucket محدّد ويُرجع الـ publicUrl.
  /// لو فشل: يضع رسالة في `lastError` ويُرجع null.
  ///
  /// مثال:
  /// ```dart
  /// final url = await SupabaseDataService().uploadImageToStorage(
  ///   bucket: 'employee_photos',
  ///   filename: 'emp_${empId}_${ts}.jpg',
  ///   bytes: imageBytes,
  ///   contentType: 'image/jpeg',
  /// );
  /// ```
  Future<String?> uploadImageToStorage({
    required String bucket,
    required String filename,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    bool upsert = true,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      // 1) محاولة الرفع
      await _supabase.client.storage.from(bucket).uploadBinary(
            filename,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: upsert,
            ),
          );
      // 2) تحقّق أنّ الملف فعلاً مُسجَّل (وإلا الـ bucket لم يكن موجوداً)
      try {
        final files = await _supabase.client.storage
            .from(bucket)
            .list(searchOptions: SearchOptions(search: filename));
        final found = files.any((f) => f.name == filename);
        if (!found) {
          lastError =
              'Bucket "$bucket" does not exist or upload silently failed. '
              'Run setup_storage_buckets.sql first.';
          return null;
        }
      } catch (_) {
        // قد لا يدعم list — نتجاوز
      }
      // 3) الحصول على public URL
      final url =
          _supabase.client.storage.from(bucket).getPublicUrl(filename);
      return url;
    } catch (e) {
      lastError = e.toString();
      // ignore: avoid_print
      M7Log.error('DataService', 'uploadImageToStorage($bucket)', error: e);
      return null;
    }
  }

  /// يحذف صورة من Supabase Storage
  Future<bool> deleteImageFromStorage(String bucket, String path) async {
    if (!_supabase.isReady) return false;
    try {
      await _supabase.client.storage.from(bucket).remove([path]);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ==========================================================
  // Countries
  // ==========================================================

  /// تحميل الدول من Supabase وتعبئة MockRepository
  Future<void> syncCountries() async {
    final rows = await _c.from('countries').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.countries.clear();
    for (final r in list) {
      _repo.countries.add(_countryFromRow(r));
    }
    _repo.notifyListeners();
  }

  Country _countryFromRow(Map<String, dynamic> r) => Country(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
        code: (r['code'] as String?) ?? '',
        phoneCode: (r['phone_code'] as String?) ?? '',
        currency: (r['currency'] as String?) ?? '',
        flagEmoji: (r['flag_emoji'] as String?) ?? '',
      );

  Future<Country?> createCountry({
    required String nameAr,
    required String nameEn,
    required String code,
    String phoneCode = '',
    String currency = '',
    String flagEmoji = '',
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final r = await _c.from('countries').insert({
        'name_ar': nameAr,
        'name_en': nameEn,
        'code': code,
        'phone_code': phoneCode,
        'currency': currency,
        'flag_emoji': flagEmoji,
      }).select().single();
      final c = _countryFromRow(r);
      _repo.countries.add(c);
      _repo.notifyListeners();
      return c;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DataService', 'createCountry', error: e);
      return null;
    }
  }

  Future<bool> updateCountry(Country c) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('countries').update({
        'name_ar': c.nameAr,
        'name_en': c.nameEn,
        'code': c.code,
        'phone_code': c.phoneCode,
        'currency': c.currency,
        'flag_emoji': c.flagEmoji,
      }).eq('id', c.id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateCountry', error: e);
      return false;
    }
  }

  Future<bool> deleteCountry(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('countries').delete().eq('id', id);
      _repo.countries.removeWhere((c) => c.id == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteCountry', error: e);
      return false;
    }
  }

  // ==========================================================
  // Cities
  // ==========================================================

  Future<void> syncCities() async {
    final rows = await _c.from('cities').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.cities.clear();
    for (final r in list) {
      _repo.cities.add(_cityFromRow(r));
    }
    _repo.notifyListeners();
  }

  City _cityFromRow(Map<String, dynamic> r) => City(
        id: r['id'] as String,
        countryId: r['country_id'] as String,
        nameAr: r['name_ar'] as String,
        nameEn: r['name_en'] as String,
      );

  Future<City?> createCity({
    required String countryId,
    required String nameAr,
    required String nameEn,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final r = await _c.from('cities').insert({
        'country_id': countryId,
        'name_ar': nameAr,
        'name_en': nameEn,
      }).select().single();
      final c = _cityFromRow(r);
      _repo.cities.add(c);
      _repo.notifyListeners();
      return c;
    } catch (e) {
      M7Log.error('DataService', 'createCity', error: e);
      return null;
    }
  }

  Future<bool> updateCity(City c) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('cities').update({
        'name_ar': c.nameAr,
        'name_en': c.nameEn,
      }).eq('id', c.id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateCity', error: e);
      return false;
    }
  }

  Future<bool> deleteCity(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('cities').delete().eq('id', id);
      _repo.cities.removeWhere((c) => c.id == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteCity', error: e);
      return false;
    }
  }

  // ==========================================================
  // Areas
  // ==========================================================

  Future<void> syncAreas() async {
    final rows = await _c.from('areas').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.areas.clear();
    for (final r in list) {
      _repo.areas.add(_areaFromRow(r));
    }
    _repo.notifyListeners();
  }

  Area _areaFromRow(Map<String, dynamic> r) {
    // تحتاج لمعرفة countryId — نأخذه من المدينة المرتبطة
    final cityId = r['city_id'] as String;
    final city = _repo.cities.firstWhere(
      (c) => c.id == cityId,
      orElse: () => City(id: '', countryId: '', nameAr: '', nameEn: ''),
    );
    return Area(
      id: r['id'] as String,
      countryId: city.countryId,
      cityId: cityId,
      nameAr: r['name_ar'] as String,
      nameEn: r['name_en'] as String,
    );
  }

  Future<Area?> createArea({
    required String cityId,
    required String nameAr,
    required String nameEn,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final r = await _c.from('areas').insert({
        'city_id': cityId,
        'name_ar': nameAr,
        'name_en': nameEn,
      }).select().single();
      final a = _areaFromRow(r);
      _repo.areas.add(a);
      _repo.notifyListeners();
      return a;
    } catch (e) {
      M7Log.error('DataService', 'createArea', error: e);
      return null;
    }
  }

  Future<bool> updateArea(Area a) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('areas').update({
        'name_ar': a.nameAr,
        'name_en': a.nameEn,
      }).eq('id', a.id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateArea', error: e);
      return false;
    }
  }

  Future<bool> deleteArea(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('areas').delete().eq('id', id);
      _repo.areas.removeWhere((a) => a.id == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteArea', error: e);
      return false;
    }
  }

  // ==========================================================
  // Numbering Rules
  // ==========================================================

  Future<void> syncNumberingRules() async {
    final rows = await _c.from('entity_numbering_rules').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.numberingRules.clear();
    for (final r in list) {
      _repo.numberingRules.add(_ruleFromRow(r));
    }
    _repo.notifyListeners();
  }

  EntityNumberingRule _ruleFromRow(Map<String, dynamic> r) =>
      EntityNumberingRule(
        id: r['id'] as String,
        technicalId: r['technical_id'] as String,
        entityNameAr: r['entity_name_ar'] as String,
        entityNameEn: r['entity_name_en'] as String,
        prefix: r['prefix'] as String,
        separator: (r['separator'] as String?) ?? '-',
        digits: (r['digits'] as int?) ?? 4,
        startNumber: (r['start_number'] as int?) ?? 1,
        includeCountryCode: (r['include_country_code'] as bool?) ?? true,
      );

  Future<EntityNumberingRule?> createNumberingRule({
    required String technicalId,
    required String entityNameAr,
    required String entityNameEn,
    required String prefix,
    String separator = '-',
    int digits = 4,
    int startNumber = 1,
    bool includeCountryCode = true,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final r = await _c.from('entity_numbering_rules').insert({
        'technical_id': technicalId,
        'entity_name_ar': entityNameAr,
        'entity_name_en': entityNameEn,
        'prefix': prefix,
        'separator': separator,
        'digits': digits,
        'start_number': startNumber,
        'include_country_code': includeCountryCode,
      }).select().single();
      final rule = _ruleFromRow(r);
      _repo.numberingRules.add(rule);
      _repo.notifyListeners();
      return rule;
    } catch (e) {
      M7Log.error('DataService', 'createNumberingRule', error: e);
      return null;
    }
  }

  Future<bool> updateNumberingRule(EntityNumberingRule rule) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('entity_numbering_rules').update({
        'technical_id': rule.technicalId,
        'entity_name_ar': rule.entityNameAr,
        'entity_name_en': rule.entityNameEn,
        'prefix': rule.prefix,
        'separator': rule.separator,
        'digits': rule.digits,
        'start_number': rule.startNumber,
        'include_country_code': rule.includeCountryCode,
      }).eq('id', rule.id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateNumberingRule', error: e);
      return false;
    }
  }

  Future<bool> deleteNumberingRule(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('entity_numbering_rules').delete().eq('id', id);
      _repo.numberingRules.removeWhere((r) => r.id == id);
      _repo.numberingCounters.removeWhere((c) => c.ruleId == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteNumberingRule', error: e);
      return false;
    }
  }

  // ==========================================================
  // Numbering Counters
  // ==========================================================

  Future<void> syncNumberingCounters() async {
    final rows = await _c.from('country_numbering_counters').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.numberingCounters.clear();
    for (final r in list) {
      _repo.numberingCounters.add(CountryNumberingCounter(
        ruleId: r['rule_id'] as String,
        countryId: r['country_id'] as String,
        currentNumber: r['current_number'] as int,
      ));
    }
    _repo.notifyListeners();
  }

  /// استهلاك كود من خلال RPC في Supabase (atomic - يمنع التكرار)
  Future<String?> consumeNextCode({
    required String technicalId,
    required String countryId,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final code = await _c.rpc('consume_next_code', params: {
        'p_technical_id': technicalId,
        'p_country_id': countryId,
      });
      // أعد مزامنة العدّاد ليعكس القيمة الجديدة
      await syncNumberingCounters();
      return code as String?;
    } catch (e) {
      M7Log.error('DataService', 'consumeNextCode', error: e);
      return null;
    }
  }

  /// إعادة تعيين عدّاد دولة لقاعدة
  Future<bool> resetCounter({
    required String ruleId,
    required String countryId,
    required int startNumber,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      // upsert
      await _c.from('country_numbering_counters').upsert({
        'rule_id': ruleId,
        'country_id': countryId,
        'current_number': startNumber,
      });
      // حدّث الذاكرة
      final idx = _repo.numberingCounters.indexWhere(
          (c) => c.ruleId == ruleId && c.countryId == countryId);
      if (idx >= 0) {
        _repo.numberingCounters[idx].currentNumber = startNumber;
      } else {
        _repo.numberingCounters.add(CountryNumberingCounter(
          ruleId: ruleId,
          countryId: countryId,
          currentNumber: startNumber,
        ));
      }
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'resetCounter', error: e);
      return false;
    }
  }

  // ==========================================================
  // Masters (الشركات الأم)
  // ==========================================================

  Future<void> syncMasters() async {
    final rows = await _c.from('masters').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.masters.clear();
    for (final r in list) {
      _repo.masters.add(_masterFromRow(r));
    }
    _repo.notifyListeners();
  }

  Master _masterFromRow(Map<String, dynamic> r) => Master(
        id: r['id'] as String,
        code: (r['code'] as String?) ?? '',
        // العمود في Supabase اسمه name_ar/name_en، نأخذ name_ar كاسم رئيسي
        name: (r['name_ar'] as String?) ??
            (r['name_en'] as String?) ??
            '',
        tradeLicense: (r['trade_license'] as String?) ?? '',
        taxVat: (r['tax_vat'] as String?) ?? '',
        industryId: r['business_type_id'] as String?,
        startDate: r['start_date'] == null
            ? null
            : DateTime.tryParse(r['start_date'] as String),
        notes: (r['notes'] as String?) ?? '',
        countryId: (r['country_id'] as String?) ?? '',
        status: ((r['status'] as String?) ?? 'active') == 'active'
            ? EntityStatus.active
            : EntityStatus.inactive,
        autoCreated: (r['auto_created'] as bool?) ?? false,
      );

  String? lastError; // آخر رسالة خطأ من Supabase (للتشخيص)

  Future<Master?> createMaster(Master m) async {
    if (!_supabase.isReady) return null;
    try {
      // ترتيب البيانات بحذر - حذف الحقول الفارغة بدلاً من إرسال null إذا أدت لمشكلة
      final payload = <String, dynamic>{
        'code': m.code,
        'name_ar': m.name.trim().isEmpty ? '-' : m.name,
        'name_en': m.name.trim().isEmpty ? '-' : m.name,
        'notes': m.notes,
        'status': m.status == EntityStatus.active ? 'active' : 'inactive',
        'auto_created': m.autoCreated,
        'trade_license': m.tradeLicense,
        'tax_vat': m.taxVat,
      };
      // إضافة الحقول الاختيارية فقط إذا فيها قيمة
      if (m.countryId.isNotEmpty) payload['country_id'] = m.countryId;
      if (m.industryId != null && m.industryId!.isNotEmpty) {
        payload['business_type_id'] = m.industryId;
      }
      if (m.startDate != null) {
        payload['start_date'] =
            m.startDate!.toIso8601String().substring(0, 10);
      }

      final r = await _c
          .from('masters')
          .insert(payload)
          .select()
          .single();
      final created = _masterFromRow(r);
      _repo.masters.add(created);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'master',
        entityId: created.id,
        entityLabel: created.name,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createMaster', error: e);
      return null;
    }
  }

  Future<bool> updateMaster(Master m) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.masters.firstWhere((x) => x.id == m.id);
        before = {
          'code': old.code,
          'name_ar': old.name,
          'country_id': old.countryId,
          'business_type_id': old.industryId,
          'trade_license': old.tradeLicense,
          'tax_vat': old.taxVat,
          'notes': old.notes,
          'status': old.status == EntityStatus.active ? 'active' : 'inactive',
        };
      } catch (_) {}
      final after = {
        'code': m.code,
        'name_ar': m.name,
        'name_en': m.name,
        'country_id': m.countryId.isEmpty ? null : m.countryId,
        'business_type_id': m.industryId,
        'trade_license': m.tradeLicense,
        'tax_vat': m.taxVat,
        'start_date': m.startDate?.toIso8601String().substring(0, 10),
        'notes': m.notes,
        'status': m.status == EntityStatus.active ? 'active' : 'inactive',
        'auto_created': m.autoCreated,
      };
      await _c.from('masters').update(after).eq('id', m.id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'master',
        entityId: m.id,
        entityLabel: m.name,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateMaster', error: e);
      return false;
    }
  }

  Future<bool> deleteMaster(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.masters.firstWhere((m) => m.id == id);
        label = old.name;
        before = {
          'code': old.code,
          'name': old.name,
          'country_id': old.countryId,
        };
      } catch (_) {}
      await _c.from('masters').delete().eq('id', id);
      _repo.masters.removeWhere((m) => m.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'master',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteMaster', error: e);
      return false;
    }
  }

  // ==========================================================
  // Points (نقاط البيع الجغرافية)
  // ==========================================================

  Future<void> syncPoints() async {
    final rows = await _c.from('points').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.points.clear();
    for (final r in list) {
      _repo.points.add(_pointFromRow(r));
    }
    _repo.notifyListeners();
  }

  Point _pointFromRow(Map<String, dynamic> r) => Point(
        id: r['id'] as String,
        code: (r['code'] as String?) ?? '',
        name: (r['name'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        countryId: r['country_id'] as String?,
        cityId: r['city_id'] as String?,
        areaId: r['area_id'] as String?,
        fullAddress: (r['address'] as String?) ?? '',
        latitude: (r['lat'] as num?)?.toDouble(),
        longitude: (r['lng'] as num?)?.toDouble(),
        status: ((r['status'] as String?) ?? 'active') == 'active'
            ? EntityStatus.active
            : EntityStatus.inactive,
      );

  Map<String, dynamic> _pointToMap(Point p) => {
        'code': p.code,
        'name': p.name,
        'description': p.description,
        'country_id': p.countryId,
        'city_id': p.cityId,
        'area_id': p.areaId,
        'address': p.fullAddress,
        'lat': p.latitude,
        'lng': p.longitude,
        'status': p.status == EntityStatus.active ? 'active' : 'inactive',
      };

  Future<Point?> createPoint(Point p) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _pointToMap(p);
      final r = await _c.from('points').insert(payload).select().single();
      final created = _pointFromRow(r);
      _repo.points.add(created);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'point',
        entityId: created.id,
        entityLabel: created.name,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      M7Log.error('DataService', 'createPoint', error: e);
      return null;
    }
  }

  Future<bool> updatePoint(Point p) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.points.firstWhere((x) => x.id == p.id);
        before = _pointToMap(old);
      } catch (_) {}
      final after = _pointToMap(p);
      await _c.from('points').update(after).eq('id', p.id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'point',
        entityId: p.id,
        entityLabel: p.name,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updatePoint', error: e);
      return false;
    }
  }

  Future<bool> deletePoint(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.points.firstWhere((p) => p.id == id);
        before = _pointToMap(old);
        label = old.name;
      } catch (_) {}
      await _c.from('points').delete().eq('id', id);
      _repo.points.removeWhere((p) => p.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'point',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deletePoint', error: e);
      return false;
    }
  }

  // ==========================================================
  // Sites (العملاء = Master @ Point)
  // ==========================================================

  Future<void> syncSites() async {
    final rows = await _c.from('sites').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.sites.clear();
    for (final r in list) {
      _repo.sites.add(_siteFromRow(r));
    }
    _repo.notifyListeners();
  }

  Site _siteFromRow(Map<String, dynamic> r) => Site(
        id: r['id'] as String,
        companyName: (r['company_name'] as String?) ?? '',
        shortName: (r['short_name'] as String?) ?? '',
        masterId: r['master_id'] as String?,
        businessTypeId: r['business_type_id'] as String?,
        countryId: r['country_id'] as String?,
        cityId: r['city_id'] as String?,
        areaId: r['area_id'] as String?,
        accountingName: (r['accounting_name'] as String?) ?? '',
        email: (r['email'] as String?) ?? '',
        phone: (r['phone'] as String?) ?? '',
        fullAddress: (r['full_address'] as String?) ?? '',
        taxId: (r['tax_id'] as String?) ?? '',
        latitude: (r['latitude'] as num?)?.toDouble(),
        longitude: (r['longitude'] as num?)?.toDouble(),
        status: ((r['status'] as String?) ?? 'active') == 'active'
            ? EntityStatus.active
            : EntityStatus.inactive,
        notes: r['notes'] as String?,
      );

  Map<String, dynamic> _siteToMap(Site s) => {
        'company_name': s.companyName,
        'short_name': s.shortName,
        'master_id': s.masterId,
        'business_type_id': s.businessTypeId,
        'country_id': s.countryId,
        'city_id': s.cityId,
        'area_id': s.areaId,
        'accounting_name': s.accountingName,
        'email': s.email,
        'phone': s.phone,
        'full_address': s.fullAddress,
        'tax_id': s.taxId,
        'latitude': s.latitude,
        'longitude': s.longitude,
        'status': s.status == EntityStatus.active ? 'active' : 'inactive',
        'notes': s.notes,
      };

  Future<Site?> createSite(Site s) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _siteToMap(s);
      final r = await _c.from('sites').insert(payload).select().single();
      final created = _siteFromRow(r);
      _repo.sites.add(created);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'site',
        entityId: created.id,
        entityLabel: created.companyName,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      M7Log.error('DataService', 'createSite', error: e);
      return null;
    }
  }

  Future<bool> updateSite(Site s) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.sites.firstWhere((x) => x.id == s.id);
        before = _siteToMap(old);
      } catch (_) {}
      final after = _siteToMap(s);
      await _c.from('sites').update(after).eq('id', s.id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'site',
        entityId: s.id,
        entityLabel: s.companyName,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'updateSite', error: e);
      return false;
    }
  }

  Future<bool> deleteSite(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.sites.firstWhere((s) => s.id == id);
        before = _siteToMap(old);
        label = old.companyName;
      } catch (_) {}
      await _c.from('sites').delete().eq('id', id);
      _repo.sites.removeWhere((s) => s.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'site',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      M7Log.error('DataService', 'deleteSite', error: e);
      return false;
    }
  }

  // ==========================================================
  // Point-Client Links
  // ==========================================================

  Future<void> syncPointClientLinks() async {
    final rows = await _c.from('point_client_links').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    // امسح الروابط القديمة من كل النقاط
    for (final p in _repo.points) {
      p.linkedClients.clear();
    }
    // عبّئ الجديدة
    for (final r in list) {
      final pointId = r['point_id'] as String;
      try {
        final point = _repo.points.firstWhere((p) => p.id == pointId);
        point.linkedClients.add(PointClientLink(
          clientId: r['site_id'] as String,
          unit: (r['unit'] as String?) ?? '',
          floor: (r['floor'] as String?) ?? '',
        ));
      } catch (_) {
        // النقطة غير موجودة - تجاهل
      }
    }
    _repo.notifyListeners();
  }

  Future<bool> linkSiteToPoint({
    required String pointId,
    required String siteId,
    String unit = '',
    String floor = '',
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('point_client_links').insert({
        'point_id': pointId,
        'site_id': siteId,
        'unit': unit,
        'floor': floor,
      });
      // حدّث الذاكرة
      try {
        final point = _repo.points.firstWhere((p) => p.id == pointId);
        if (!point.linkedClients.any((l) => l.clientId == siteId)) {
          point.linkedClients.add(PointClientLink(
              clientId: siteId, unit: unit, floor: floor));
        }
      } catch (_) {}
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'linkSiteToPoint', error: e);
      return false;
    }
  }

  Future<bool> unlinkSiteFromPoint({
    required String pointId,
    required String siteId,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c
          .from('point_client_links')
          .delete()
          .eq('point_id', pointId)
          .eq('site_id', siteId);
      try {
        final point = _repo.points.firstWhere((p) => p.id == pointId);
        point.linkedClients.removeWhere((l) => l.clientId == siteId);
      } catch (_) {}
      _repo.notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('DataService', 'unlinkSiteFromPoint', error: e);
      return false;
    }
  }

  // ==========================================================
  // Employees
  // ==========================================================

  Future<void> syncEmployees() async {
    final rows = await _c.from('employees').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.employees.clear();
    for (final r in list) {
      _repo.employees.add(_employeeFromRow(r));
    }
    _repo.notifyListeners();
  }

  Employee _employeeFromRow(Map<String, dynamic> r) => Employee(
        id: r['id'] as String,
        code: (r['code'] as String?) ?? '',
        fullName: r['full_name'] as String,
        email: (r['email'] as String?) ?? '',
        mobile: (r['mobile'] as String?) ?? '',
        birthDate: r['birth_date'] == null
            ? null
            : DateTime.tryParse(r['birth_date'] as String),
        joiningDate: r['joining_date'] == null
            ? null
            : DateTime.tryParse(r['joining_date'] as String),
        jobTitleId: r['job_title_id'] as String?,
        departmentId: r['department_id'] as String?,
        maritalStatusId: r['marital_status_id'] as String?,
        nationalityId: r['nationality_id'] as String?,
        visaTypeId: r['visa_type_id'] as String?,
        transportModeId: r['transport_mode_id'] as String?, // 🆕
        category: (r['category'] as String?) ?? 'worker', // 🆕
        passportNumber: (r['passport_number'] as String?) ?? '',
        passportExpiry: r['passport_expiry'] == null
            ? null
            : DateTime.tryParse(r['passport_expiry'] as String),
        idNumber: (r['id_number'] as String?) ?? '',
        licenseNumber: (r['license_number'] as String?) ?? '',
        licenseIssue: r['license_issue'] == null
            ? null
            : DateTime.tryParse(r['license_issue'] as String),
        licenseExpiry: r['license_expiry'] == null
            ? null
            : DateTime.tryParse(r['license_expiry'] as String),
        basicSalary: (r['basic_salary'] as num?)?.toDouble() ?? 0,
        overtime: (r['overtime'] as num?)?.toDouble() ?? 0,
        trainingFee: (r['training_fee'] as num?)?.toDouble() ?? 0,
        others: (r['others'] as num?)?.toDouble() ?? 0,
        iban: (r['iban'] as String?) ?? '',
        emergencyContactName: (r['emergency_contact_name'] as String?) ?? '',
        emergencyContactPhone:
            (r['emergency_contact_phone'] as String?) ?? '',
        education: (r['education'] as String?) ?? '',
        address: (r['address'] as String?) ?? '',
        status: ((r['status'] as String?) ?? 'active') == 'active'
            ? EntityStatus.active
            : EntityStatus.inactive,
        activationDate: r['activation_date'] == null
            ? null
            : DateTime.tryParse(r['activation_date'] as String),
        deactivationDate: r['deactivation_date'] == null
            ? null
            : DateTime.tryParse(r['deactivation_date'] as String),
        siteId: r['site_id'] as String?,
        pointId: r['point_id'] as String?,
        countryId: r['country_id'] as String?,
        photoFileId: r['photo_file_id'] as String?,
        idCardFileId: r['id_file_id'] as String?,
        licenseFileId: r['license_file_id'] as String?,
        // 🆕 housing + hire type + uniform sizes
        housingType: (r['housing_type'] as String?) == 'on_camp'
            ? HousingType.onCamp
            : HousingType.offCamp,
        hireType: EmployeeHireTypeX.fromKey(r['hire_type'] as String?),
        shirtSize: (r['shirt_size'] as String?) ?? '',
        pantSize: (r['pant_size'] as String?) ?? '',
        shoeSize: (r['shoe_size'] as String?) ?? '',
        // 🆕 الباص الافتراضي للموظّف
        defaultBusId: r['default_bus_id'] as String?,
      );

  Map<String, dynamic> _employeeToPayload(Employee e) {
    final payload = <String, dynamic>{
      'code': e.code,
      'full_name': e.fullName,
      'basic_salary': e.basicSalary,
      'overtime': e.overtime,
      'training_fee': e.trainingFee,
      'others': e.others,
      'status': e.status == EntityStatus.active ? 'active' : 'inactive',
      'category': e.category, // 🆕 worker | admin
    };
    // الحقول النصية الاختيارية - نضيفها فقط إن لم تكن فارغة
    if (e.email.isNotEmpty) payload['email'] = e.email;
    if (e.mobile.isNotEmpty) payload['mobile'] = e.mobile;
    if (e.passportNumber.isNotEmpty) payload['passport_number'] = e.passportNumber;
    if (e.idNumber.isNotEmpty) payload['id_number'] = e.idNumber;
    if (e.licenseNumber.isNotEmpty) payload['license_number'] = e.licenseNumber;
    if (e.iban.isNotEmpty) payload['iban'] = e.iban;
    if (e.emergencyContactName.isNotEmpty) {
      payload['emergency_contact_name'] = e.emergencyContactName;
    }
    if (e.emergencyContactPhone.isNotEmpty) {
      payload['emergency_contact_phone'] = e.emergencyContactPhone;
    }
    if (e.education.isNotEmpty) payload['education'] = e.education;
    if (e.address.isNotEmpty) payload['address'] = e.address;
    // الـ FKs الاختيارية
    if (e.jobTitleId != null) payload['job_title_id'] = e.jobTitleId;
    if (e.departmentId != null) payload['department_id'] = e.departmentId;
    if (e.maritalStatusId != null) {
      payload['marital_status_id'] = e.maritalStatusId;
    }
    if (e.nationalityId != null) payload['nationality_id'] = e.nationalityId;
    if (e.visaTypeId != null) payload['visa_type_id'] = e.visaTypeId;
    if (e.transportModeId != null) {
      payload['transport_mode_id'] = e.transportModeId; // 🆕
    }
    if (e.pointId != null) payload['point_id'] = e.pointId;
    if (e.countryId != null) payload['country_id'] = e.countryId;
    // التواريخ
    if (e.birthDate != null) {
      payload['birth_date'] = e.birthDate!.toIso8601String().substring(0, 10);
    }
    if (e.joiningDate != null) {
      payload['joining_date'] =
          e.joiningDate!.toIso8601String().substring(0, 10);
    }
    if (e.passportExpiry != null) {
      payload['passport_expiry'] =
          e.passportExpiry!.toIso8601String().substring(0, 10);
    }
    if (e.licenseIssue != null) {
      payload['license_issue'] =
          e.licenseIssue!.toIso8601String().substring(0, 10);
    }
    if (e.licenseExpiry != null) {
      payload['license_expiry'] =
          e.licenseExpiry!.toIso8601String().substring(0, 10);
    }
    if (e.activationDate != null) {
      payload['activation_date'] = e.activationDate!.toIso8601String();
    }
    if (e.deactivationDate != null) {
      payload['deactivation_date'] = e.deactivationDate!.toIso8601String();
    }
    // 🆕 housing + hire type + uniform sizes
    payload['housing_type'] =
        e.housingType == HousingType.onCamp ? 'on_camp' : 'off_camp';
    payload['hire_type'] = e.hireType.key; // trainee | professional
    if (e.shirtSize.isNotEmpty) payload['shirt_size'] = e.shirtSize;
    if (e.pantSize.isNotEmpty) payload['pant_size'] = e.pantSize;
    if (e.shoeSize.isNotEmpty) payload['shoe_size'] = e.shoeSize;
    // 🆕 الباص الافتراضي
    if (e.defaultBusId != null) {
      payload['default_bus_id'] = e.defaultBusId;
    }
    // 🖼️ مرفقات الصور والوثائق (URLs من Supabase Storage)
    if (e.photoFileId != null) payload['photo_file_id'] = e.photoFileId;
    if (e.idCardFileId != null) payload['id_file_id'] = e.idCardFileId;
    if (e.licenseFileId != null) {
      payload['license_file_id'] = e.licenseFileId;
    }
    if (e.workLetterFileId != null) {
      payload['work_letter_file_id'] = e.workLetterFileId;
    }
    if (e.workLetterDate != null) {
      payload['work_letter_date'] =
          e.workLetterDate!.toIso8601String().substring(0, 10);
    }
    return payload;
  }

  Future<Employee?> createEmployee(Employee e, {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _employeeToPayload(e);
      if (countryId != null) payload['country_id'] = countryId;
      final r = await _c
          .from('employees')
          .insert(payload)
          .select()
          .single();
      final created = _employeeFromRow(r);
      _repo.employees.add(created);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'employee',
        entityId: created.id,
        entityLabel: created.fullName,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (ex) {
      lastError = ex.toString();
      M7Log.error('DataService', 'createEmployee', error: ex);
      return null;
    }
  }

  Future<bool> updateEmployee(Employee e) async {
    if (!_supabase.isReady) return false;
    try {
      // التقط الحالة قبل
      Map<String, dynamic>? before;
      EntityStatus? oldStatus;
      try {
        final old = _repo.employees.firstWhere((x) => x.id == e.id);
        before = _employeeToPayload(old);
        oldStatus = old.status;
      } catch (_) {}
      final after = _employeeToPayload(e);
      await _c
          .from('employees')
          .update(after)
          .eq('id', e.id);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'employee',
        entityId: e.id,
        entityLabel: e.fullName,
        action: AuditAction.update,
        before: before,
        after: after,
      );

      // 🆕 مزامنة حالة الحساب المَربوط:
      // عند تَغيير حالة الموظّف active ↔ inactive، نَنقُل التَغيير
      // إلى الحساب المَربوط (إن وُجد) كي يَتعطّل الدُخول تلقائيّاً.
      if (oldStatus != null && oldStatus != e.status) {
        await syncLinkedAccountActiveState(
          employeeId: e.id,
          newActive: e.status == EntityStatus.active,
        );
      }
      return true;
    } catch (ex) {
      lastError = ex.toString();
      M7Log.error('DataService', 'updateEmployee', error: ex);
      return false;
    }
  }

  /// 🆕 يُزامِن حالة الحساب المَربوط بِموظّف عند تَغيير حالة الموظّف.
  /// - active → الحساب يَعود نَشطاً (يَستَطيع الدُخول)
  /// - inactive → الحساب يُعَطَّل (login يَرفُضه)
  /// يَفحص أيضاً المُطابَقة الضِمنيّة (username ↔ code/full_name)
  /// لِلْحسابات غير المَربوطة صَراحةً بـemployee_id.
  Future<int> syncLinkedAccountActiveState({
    required String employeeId,
    required bool newActive,
  }) async {
    if (!_supabase.isReady) return 0;
    try {
      // 1) ابحث عن الموظّف للمُطابَقة الضِمنيّة
      Employee? emp;
      try {
        emp = _repo.employees.firstWhere((x) => x.id == employeeId);
      } catch (_) {}
      // 2) جَمِّع كلّ الحسابات المُتَأَثِّرة:
      //    أ) المَربوطة صَراحةً بـemployee_id
      //    ب) المُتَطابِقة بـcode/full_name إن لم تَكن مَربوطة
      final affected = <AppAccount>{};
      for (final a in _repo.accounts) {
        if (a.employeeId == employeeId) {
          affected.add(a);
          continue;
        }
        if (emp != null && a.employeeId == null) {
          final un = a.username.trim().toLowerCase();
          final fn = a.fullName.trim().toLowerCase();
          if (un.isEmpty && fn.isEmpty) continue;
          final empCode = emp.code.trim().toLowerCase();
          final empName = emp.fullName.trim().toLowerCase();
          if (un == empCode || un == empName || fn == empName) {
            affected.add(a);
          }
        }
      }
      if (affected.isEmpty) return 0;
      var updated = 0;
      for (final a in affected) {
        if (a.isActive == newActive) continue;
        try {
          await _c
              .from('accounts')
              .update({'is_active': newActive})
              .eq('id', a.id);
          a.isActive = newActive;
          updated++;
          await AuditLogger.instance.log(
            entityType: 'account',
            entityId: a.id,
            entityLabel: a.fullName,
            action: AuditAction.update,
            description: newActive
                ? 'تَفعيل تلقائيّ — الموظّف عاد نَشطاً'
                : 'تَعطيل تلقائيّ — الموظّف غير نَشط',
            after: {'is_active': newActive},
          );
        } catch (e) {
          M7Log.error('DataService',
              'syncLinkedAccountActiveState[${a.username}]',
              error: e);
        }
      }
      _repo.notifyListeners();
      return updated;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'syncLinkedAccountActiveState', error: e);
      return 0;
    }
  }

  /// 🆕 إضافة عدد من الموظّفين دفعة واحدة من ملف Excel/CSV.
  /// يتخطّى الصفوف التي يطابق كودها موظّفاً موجوداً (لا تحديث).
  Future<BulkInsertResult> bulkInsertNewEmployees(
    List<Employee> employees, {
    String? countryId,
  }) async {
    var added = 0;
    var skipped = 0;
    var failed = 0;
    final failedReasons = <String>[];
    final supaReady = _supabase.isReady;

    for (final e in employees) {
      // تخطّى لو الكود موجود مسبقاً
      if (e.code.isNotEmpty &&
          _repo.employees.any((x) => x.code == e.code)) {
        skipped++;
        continue;
      }
      try {
        if (supaReady) {
          // استهلك كود من نظام الترقيم لو الكود فارغ
          var emp = e;
          if (emp.code.isEmpty && countryId != null) {
            final code = await consumeNextCode(
                technicalId: 'employee', countryId: countryId);
            if (code != null) {
              emp = Employee(
                id: emp.id,
                code: code,
                fullName: emp.fullName,
                jobTitle: emp.jobTitle,
                department: emp.department,
                maritalStatus: emp.maritalStatus,
                mobile: emp.mobile,
                email: emp.email,
                birthDate: emp.birthDate,
                nationality: emp.nationality,
                joiningDate: emp.joiningDate,
                address: emp.address,
                passportNumber: emp.passportNumber,
                passportExpiry: emp.passportExpiry,
                idNumber: emp.idNumber,
                visaType: emp.visaType,
                licenseNumber: emp.licenseNumber,
                licenseIssue: emp.licenseIssue,
                licenseExpiry: emp.licenseExpiry,
                basicSalary: emp.basicSalary,
                overtime: emp.overtime,
                trainingFee: emp.trainingFee,
                others: emp.others,
                iban: emp.iban,
                emergencyContactName: emp.emergencyContactName,
                emergencyContactPhone: emp.emergencyContactPhone,
                education: emp.education,
                status: emp.status,
                jobTitleId: emp.jobTitleId,
                departmentId: emp.departmentId,
                maritalStatusId: emp.maritalStatusId,
                nationalityId: emp.nationalityId,
                visaTypeId: emp.visaTypeId,
                housingType: emp.housingType,
                hireType: emp.hireType,
                shirtSize: emp.shirtSize,
                pantSize: emp.pantSize,
                shoeSize: emp.shoeSize,
                defaultBusId: emp.defaultBusId,
              );
            }
          }
          final created = await createEmployee(emp, countryId: countryId);
          if (created != null) {
            added++;
          } else {
            failed++;
            failedReasons.add('${emp.fullName}: ${lastError ?? "unknown"}');
          }
        } else {
          // وضع Mock فقط
          var emp = e;
          if (emp.code.isEmpty) {
            emp = Employee(
              id: _repo.generateId(),
              code: _repo.generateEmployeeCode(),
              fullName: emp.fullName,
              jobTitle: emp.jobTitle,
              department: emp.department,
              maritalStatus: emp.maritalStatus,
              mobile: emp.mobile,
              email: emp.email,
              birthDate: emp.birthDate,
              nationality: emp.nationality,
              joiningDate: emp.joiningDate,
              address: emp.address,
              passportNumber: emp.passportNumber,
              passportExpiry: emp.passportExpiry,
              idNumber: emp.idNumber,
              visaType: emp.visaType,
              licenseNumber: emp.licenseNumber,
              licenseIssue: emp.licenseIssue,
              licenseExpiry: emp.licenseExpiry,
              basicSalary: emp.basicSalary,
              overtime: emp.overtime,
              trainingFee: emp.trainingFee,
              others: emp.others,
              iban: emp.iban,
              emergencyContactName: emp.emergencyContactName,
              emergencyContactPhone: emp.emergencyContactPhone,
              education: emp.education,
              status: emp.status,
              jobTitleId: emp.jobTitleId,
              departmentId: emp.departmentId,
              maritalStatusId: emp.maritalStatusId,
              nationalityId: emp.nationalityId,
              visaTypeId: emp.visaTypeId,
              housingType: emp.housingType,
              hireType: emp.hireType,
              shirtSize: emp.shirtSize,
              pantSize: emp.pantSize,
              shoeSize: emp.shoeSize,
              defaultBusId: emp.defaultBusId,
            );
          } else {
            emp = Employee(
              id: _repo.generateId(),
              code: emp.code,
              fullName: emp.fullName,
              jobTitle: emp.jobTitle,
              department: emp.department,
              maritalStatus: emp.maritalStatus,
              mobile: emp.mobile,
              email: emp.email,
              birthDate: emp.birthDate,
              nationality: emp.nationality,
              joiningDate: emp.joiningDate,
              address: emp.address,
              passportNumber: emp.passportNumber,
              passportExpiry: emp.passportExpiry,
              idNumber: emp.idNumber,
              visaType: emp.visaType,
              licenseNumber: emp.licenseNumber,
              licenseIssue: emp.licenseIssue,
              licenseExpiry: emp.licenseExpiry,
              basicSalary: emp.basicSalary,
              overtime: emp.overtime,
              trainingFee: emp.trainingFee,
              others: emp.others,
              iban: emp.iban,
              emergencyContactName: emp.emergencyContactName,
              emergencyContactPhone: emp.emergencyContactPhone,
              education: emp.education,
              status: emp.status,
              jobTitleId: emp.jobTitleId,
              departmentId: emp.departmentId,
              maritalStatusId: emp.maritalStatusId,
              nationalityId: emp.nationalityId,
              visaTypeId: emp.visaTypeId,
              housingType: emp.housingType,
              hireType: emp.hireType,
              shirtSize: emp.shirtSize,
              pantSize: emp.pantSize,
              shoeSize: emp.shoeSize,
              defaultBusId: emp.defaultBusId,
            );
          }
          _repo.employees.add(emp);
          added++;
        }
      } catch (ex) {
        failed++;
        failedReasons.add('${e.fullName}: $ex');
      }
    }
    if (!supaReady) _repo.notifyListeners();
    return BulkInsertResult(
      added: added,
      skipped: skipped,
      failed: failed,
      failedReasons: failedReasons,
    );
  }

  Future<bool> deleteEmployee(String id) async {
    if (!_supabase.isReady) return false;
    try {
      // التقط الحالة قبل الحذف
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.employees.firstWhere((x) => x.id == id);
        before = _employeeToPayload(old);
        label = old.fullName;
      } catch (_) {}
      await _c.from('employees').delete().eq('id', id);
      _repo.employees.removeWhere((e) => e.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'employee',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteEmployee', error: e);
      return false;
    }
  }

  /// تحديث ربط موظف بنقطة (Operation تستخدمها لإسناد المشرفين)
  /// مرّر [pointId = null] لإلغاء الربط
  /// (الاسم القديم احتفظنا به للتوافق - فعلياً يحدّث point_id)
  Future<bool> assignEmployeeToSite(String empId, String? pointId) async {
    if (!_supabase.isReady) return false;
    try {
      String? oldPointId;
      String? empName;
      try {
        final e = _repo.employees.firstWhere((x) => x.id == empId);
        oldPointId = e.pointId;
        empName = e.fullName;
      } catch (_) {}
      await _c
          .from('employees')
          .update({'point_id': pointId})
          .eq('id', empId);
      // حدّث الذاكرة
      try {
        final e = _repo.employees.firstWhere((x) => x.id == empId);
        e.pointId = pointId;
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'employee_assignment',
        entityId: empId,
        entityLabel: empName,
        action: pointId == null ? AuditAction.unassign : AuditAction.assign,
        before: {'point_id': oldPointId},
        after: {'point_id': pointId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'assignEmployeeToSite', error: e);
      return false;
    }
  }

  // ==========================================================
  // Buses
  // ==========================================================

  Future<void> syncBuses() async {
    final rows = await _c.from('buses').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    _repo.buses.clear();
    for (final r in list) {
      _repo.buses.add(_busFromRow(r));
    }
    _repo.notifyListeners();
  }

  Bus _busFromRow(Map<String, dynamic> r) {
    final daysRaw = r['schedule_days'];
    List<int> days = const [0, 1, 2, 3, 4];
    if (daysRaw is List) {
      days = daysRaw
          .map((e) => (e as num).toInt())
          .toList(growable: false);
    }
    final tripsRaw = r['trip_times'];
    List<String> trips = <String>[];
    if (tripsRaw is List) {
      trips = tripsRaw.map((e) => e?.toString() ?? '').toList()
        ..removeWhere((s) => s.isEmpty);
    }
    return Bus(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      plateNumber: (r['plate_number'] as String?) ?? '',
      capacity: (r['capacity'] as int?) ?? 30,
      driverId: r['driver_id'] as String?,
      status: ((r['status'] as String?) ?? 'active') == 'active'
          ? EntityStatus.active
          : EntityStatus.inactive,
      model: (r['model'] as String?) ?? '',
      year: r['year'] as int?,
      color: (r['color'] as String?) ?? '',
      licenseExpiry: r['license_expiry'] == null
          ? null
          : DateTime.tryParse(r['license_expiry'] as String),
      insuranceExpiry: r['insurance_expiry'] == null
          ? null
          : DateTime.tryParse(r['insurance_expiry'] as String),
      notes: r['notes'] as String?,
      countryId: r['country_id'] as String?,
      ownership:
          BusOwnershipX.fromKey(r['ownership'] as String?), // 🆕
      displayName: r['display_name'] as String?,            // 🆕
      assignedPointId: r['assigned_point_id'] as String?,
      tripTimes: trips,                                      // 🆕
      scheduleDays: days,
      homeLat: (r['home_lat'] as num?)?.toDouble(),         // 🆕
      homeLng: (r['home_lng'] as num?)?.toDouble(),         // 🆕
      scheduleMode: BusScheduleModeX.fromKey(
          r['schedule_mode'] as String?),                    // 🆕
      intervalHours: (r['interval_hours'] as num?)?.toInt() ?? 4, // 🆕
    );
  }

  Map<String, dynamic> _busToPayload(Bus b) {
    final payload = <String, dynamic>{
      'name': b.name,
      'capacity': b.capacity,
      'status': b.status == EntityStatus.active ? 'active' : 'inactive',
    };
    if (b.plateNumber.isNotEmpty) payload['plate_number'] = b.plateNumber;
    if (b.driverId != null) payload['driver_id'] = b.driverId;
    if (b.model.isNotEmpty) payload['model'] = b.model;
    if (b.year != null) payload['year'] = b.year;
    if (b.color.isNotEmpty) payload['color'] = b.color;
    if (b.licenseExpiry != null) {
      payload['license_expiry'] =
          b.licenseExpiry!.toIso8601String().substring(0, 10);
    }
    if (b.insuranceExpiry != null) {
      payload['insurance_expiry'] =
          b.insuranceExpiry!.toIso8601String().substring(0, 10);
    }
    if (b.notes != null && b.notes!.isNotEmpty) payload['notes'] = b.notes;
    if (b.countryId != null) payload['country_id'] = b.countryId;
    // 🆕 الملكية والاسم والنقطة والمواعيد
    payload['ownership'] = b.ownership.key;
    if (b.displayName != null) payload['display_name'] = b.displayName;
    if (b.assignedPointId != null) {
      payload['assigned_point_id'] = b.assignedPointId;
    }
    payload['trip_times'] = b.tripTimes;
    payload['schedule_days'] = b.scheduleDays;
    // 🆕 الموقع
    if (b.homeLat != null) payload['home_lat'] = b.homeLat;
    if (b.homeLng != null) payload['home_lng'] = b.homeLng;
    // 🆕 وضع الجدول
    payload['schedule_mode'] = b.scheduleMode.key;
    payload['interval_hours'] = b.intervalHours;
    return payload;
  }

  // ==========================================================
  // 🆕 ورديات السائقين على الباص (bus_drivers)
  // ==========================================================
  Future<void> syncBusDriverShifts() async {
    try {
      final rows = await _c.from('bus_drivers').select();
      _repo.busDriverShifts.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.busDriverShifts.add(BusDriverShift(
          id: r['id'] as String,
          busId: r['bus_id'] as String,
          driverId: r['driver_id'] as String,
          startTime: r['start_time'] as String?,
          endTime: r['end_time'] as String?,
          notes: r['notes'] as String?,
          createdAt: r['created_at'] == null
              ? null
              : DateTime.tryParse(r['created_at'] as String),
          effectiveFrom: r['effective_from'] == null
              ? null
              : DateTime.tryParse(r['effective_from'].toString()),
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncBusDriverShifts', error: e);
    }
  }

  Future<BusDriverShift?> addBusDriverShift({
    required String busId,
    required String driverId,
    String? startTime,
    String? endTime,
    String? notes,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final payload = <String, dynamic>{
        'bus_id': busId,
        'driver_id': driverId,
        'effective_from': todayDate.toIso8601String().substring(0, 10), // 🆕
        if (startTime != null && startTime.isNotEmpty)
          'start_time': startTime,
        if (endTime != null && endTime.isNotEmpty) 'end_time': endTime,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final r = await _c
          .from('bus_drivers')
          .insert(payload)
          .select()
          .single();
      final shift = BusDriverShift(
        id: r['id'] as String,
        busId: busId,
        driverId: driverId,
        startTime: startTime,
        endTime: endTime,
        notes: notes,
        effectiveFrom: r['effective_from'] != null
            ? DateTime.parse(r['effective_from'].toString())
            : todayDate,
      );
      _repo.busDriverShifts.add(shift);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'bus_driver_shift',
        entityId: shift.id,
        action: AuditAction.assign,
        after: payload,
      );
      return shift;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'addBusDriverShift', error: e);
      return null;
    }
  }

  /// 🆕 تَحديث وَردِيّة سائِق — يُنشِئ صَفّاً جَديداً بِـeffective_from = اليَوم
  /// بَدَل تَعديل الصَفّ الحاليّ. هذا يَحفَظ سِجِلّ التَغييرات وَيَمنَع تَأثير
  /// التَعديل على الرَحَلات السابِقة.
  ///
  /// النَتيجة: الصَفّ القَديم يَبقى كَما هو (يَنطَبِق على الأَيّام قَبل اليَوم)،
  /// الصَفّ الجَديد يَنطَبِق من اليَوم وَما بَعد.
  Future<bool> updateBusDriverShift(BusDriverShift s) async {
    if (!_supabase.isReady) return false;
    try {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final todayStr = todayDate.toIso8601String().substring(0, 10);

      // تَحَقَّق هَل صَفّ بِنَفس effective_from مَوجود (نَفس اليَوم)
      // إن وُجِد → نُحَدِّثه (تَعديل قَبل اليَوم انتَهَى)
      // وإلّا → نُنشِئ صَفّاً جَديداً
      final existingToday = await _c
          .from('bus_drivers')
          .select('id')
          .eq('bus_id', s.busId)
          .eq('driver_id', s.driverId)
          .eq('effective_from', todayStr)
          .maybeSingle();

      final payload = <String, dynamic>{
        'bus_id': s.busId,
        'driver_id': s.driverId,
        'start_time': s.startTime,
        'end_time': s.endTime,
        'notes': s.notes,
        'effective_from': todayStr,
      };

      Map<String, dynamic>? row;
      if (existingToday != null && existingToday['id'] != null) {
        // صَفّ اليَوم مَوجود — نُحَدِّثه
        row = await _c
            .from('bus_drivers')
            .update(payload)
            .eq('id', existingToday['id'])
            .select()
            .single();
      } else {
        // أَنشِئ صَفّاً جَديداً (يَحفَظ السِجِلّ القَديم)
        row = await _c
            .from('bus_drivers')
            .insert(payload)
            .select()
            .single();
      }

      // حَدِّث الـcache المَحَلّيّ
      if (row != null) {
        final newShift = BusDriverShift(
          id: row['id'].toString(),
          busId: row['bus_id'].toString(),
          driverId: row['driver_id'].toString(),
          startTime: row['start_time']?.toString(),
          endTime: row['end_time']?.toString(),
          notes: row['notes']?.toString(),
          effectiveFrom: row['effective_from'] != null
              ? DateTime.parse(row['effective_from'].toString())
              : todayDate,
        );
        // أَزِل أَيّ صَفّ بِنَفس الـid (إن وُجِد)
        _repo.busDriverShifts.removeWhere((x) => x.id == newShift.id);
        _repo.busDriverShifts.add(newShift);
        _repo.notifyListeners();
      }

      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateBusDriverShift', error: e);
      return false;
    }
  }

  Future<bool> removeBusDriverShift(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('bus_drivers').delete().eq('id', id);
      _repo.busDriverShifts.removeWhere((s) => s.id == id);
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'removeBusDriverShift', error: e);
      return false;
    }
  }

  // ==========================================================
  // 🆕 ربط الباصات بالموظفين (bus_employees)
  // ==========================================================
  Future<void> syncBusEmployees() async {
    try {
      final rows = await _c.from('bus_employees').select();
      _repo.busEmployees.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.busEmployees.add(BusEmployee(
          busId: r['bus_id'] as String,
          employeeId: r['employee_id'] as String,
          assignedAt: r['assigned_at'] == null
              ? null
              : DateTime.tryParse(r['assigned_at'] as String),
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncBusEmployees', error: e);
    }
  }

  Future<bool> assignEmployeeToBus(String busId, String employeeId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('bus_employees').insert({
        'bus_id': busId,
        'employee_id': employeeId,
      });
      if (!_repo.busEmployees.any(
          (e) => e.busId == busId && e.employeeId == employeeId)) {
        _repo.busEmployees
            .add(BusEmployee(busId: busId, employeeId: employeeId));
      }
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'bus_employee',
        entityId: '${busId}_$employeeId',
        action: AuditAction.assign,
        after: {'bus_id': busId, 'employee_id': employeeId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'assignEmployeeToBus', error: e);
      return false;
    }
  }

  Future<bool> unassignEmployeeFromBus(
      String busId, String employeeId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c
          .from('bus_employees')
          .delete()
          .eq('bus_id', busId)
          .eq('employee_id', employeeId);
      _repo.busEmployees.removeWhere(
          (e) => e.busId == busId && e.employeeId == employeeId);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'bus_employee',
        entityId: '${busId}_$employeeId',
        action: AuditAction.unassign,
        before: {'bus_id': busId, 'employee_id': employeeId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'unassignEmployeeFromBus', error: e);
      return false;
    }
  }

  Future<Bus?> createBus(Bus b, {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _busToPayload(b);
      if (countryId != null) payload['country_id'] = countryId;
      final r = await _c
          .from('buses')
          .insert(payload)
          .select()
          .single();
      final created = _busFromRow(r);
      _repo.buses.add(created);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'bus',
        entityId: created.id,
        entityLabel: '${created.name} (${created.plateNumber})',
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createBus', error: e);
      return null;
    }
  }

  Future<bool> updateBus(Bus b) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.buses.firstWhere((x) => x.id == b.id);
        before = _busToPayload(old);
      } catch (_) {}
      final after = _busToPayload(b);
      await _c.from('buses').update(after).eq('id', b.id);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'bus',
        entityId: b.id,
        entityLabel: '${b.name} (${b.plateNumber})',
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateBus', error: e);
      return false;
    }
  }

  Future<bool> deleteBus(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.buses.firstWhere((x) => x.id == id);
        before = _busToPayload(old);
        label = '${old.name} (${old.plateNumber})';
      } catch (_) {}
      await _c.from('buses').delete().eq('id', id);
      _repo.buses.removeWhere((b) => b.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'bus',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteBus', error: e);
      return false;
    }
  }

  // ==========================================================
  // Rosters (مع Assignments)
  // ==========================================================

  /// مزامنة الروسترات والـ assignments من Supabase
  /// نسحبها معاً ونعبّئ كل روستر بقائمة assignments الخاصة به
  Future<void> syncRosters() async {
    final rosterRows = await _c.from('weekly_rosters').select();
    final asgnRows = await _c.from('roster_assignments').select();

    _repo.rosters.clear();

    for (final r in (rosterRows as List).cast<Map<String, dynamic>>()) {
      _repo.rosters.add(_rosterFromRow(r));
    }

    // عبّئ كل روستر بـ assignments
    for (final a in (asgnRows as List).cast<Map<String, dynamic>>()) {
      final rosterId = a['roster_id'] as String;
      try {
        final roster = _repo.rosters.firstWhere((x) => x.id == rosterId);
        roster.assignments.add(_assignmentFromRow(a));
      } catch (_) {}
    }
    _repo.notifyListeners();
  }

  WeeklyRoster _rosterFromRow(Map<String, dynamic> r) {
    final statusStr = (r['status'] as String?) ?? 'draft';
    // الأولوية لـ point_id (الجديد)، ثم site_id (القديم)
    final pid = (r['point_id'] as String?) ?? (r['site_id'] as String?) ?? '';
    return WeeklyRoster(
      id: r['id'] as String,
      siteId: pid,
      supervisorId: (r['supervisor_id'] as String?) ?? '',
      weekStart: DateTime.parse(r['week_start'] as String),
      status: _parseRosterStatus(statusStr),
      rejectionReason: r['rejection_reason'] as String?,
      notes: r['notes'] as String?,
      createdAt: r['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(r['created_at'] as String),
      submittedAt: r['submitted_at'] == null
          ? null
          : DateTime.tryParse(r['submitted_at'] as String),
      reviewedAt: r['reviewed_at'] == null
          ? null
          : DateTime.tryParse(r['reviewed_at'] as String),
      reviewedBy: r['reviewed_by'] as String?,
      jobTitleIds: (r['job_title_ids'] as List?)?.map((e) => e.toString()).toList() ?? [], // 🆕
    );
  }

  RosterAssignment _assignmentFromRow(Map<String, dynamic> r) =>
      RosterAssignment(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        dayIndex: r['day_index'] as int,
        startTime: (r['start_time'] as String?) ?? '00:00',
        endTime: (r['end_time'] as String?) ?? '00:00',
        shiftType: _parseShiftType((r['shift_type'] as String?) ?? 'morning'),
        notes: r['notes'] as String?,
      );

  RosterStatus _parseRosterStatus(String s) {
    switch (s) {
      case 'submitted':
        return RosterStatus.submitted;
      case 'underReview':
      case 'under_review':
        return RosterStatus.underReview;
      case 'approved':
        return RosterStatus.approved;
      case 'rejected':
        return RosterStatus.rejected;
      default:
        return RosterStatus.draft;
    }
  }

  String _rosterStatusToStr(RosterStatus s) {
    switch (s) {
      case RosterStatus.draft:
        return 'draft';
      case RosterStatus.submitted:
        return 'submitted';
      case RosterStatus.underReview:
        return 'underReview';
      case RosterStatus.approved:
        return 'approved';
      case RosterStatus.rejected:
        return 'rejected';
    }
  }

  ShiftType _parseShiftType(String s) {
    switch (s) {
      case 'evening':
        return ShiftType.evening;
      case 'night':
        return ShiftType.night;
      case 'custom':
      case 'split':
        return ShiftType.custom;
      case 'off':
        return ShiftType.off;
      default:
        return ShiftType.morning;
    }
  }

  /// 🆕 تحديث المسميات الوظيفية المسموح بها في روستر
  Future<bool> updateRosterJobTitleIds(String rosterId, List<String> ids) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('weekly_rosters')
          .update({'job_title_ids': ids})
          .eq('id', rosterId);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateRosterJobTitleIds', error: e);
      return false;
    }
  }

  /// إنشاء روستر مع كل assignments دفعة واحدة
  /// يستخدم transaction logic بسيط: ينشئ الـ roster ثم يضيف assignments
  Future<WeeklyRoster?> createRoster(WeeklyRoster r) async {
    if (!_supabase.isReady) return null;
    try {
      // 1) Insert الـ Roster
      // ملاحظة: r.siteId يحمل معرف النقطة (Point) - نخزّنه في point_id
      final rosterPayload = <String, dynamic>{
        'point_id': r.siteId,
        'week_start': r.weekStart.toIso8601String().substring(0, 10),
        'status': _rosterStatusToStr(r.status),
      };
      if (r.supervisorId.isNotEmpty) {
        rosterPayload['supervisor_id'] = r.supervisorId;
      }
      if (r.rejectionReason != null) {
        rosterPayload['rejection_reason'] = r.rejectionReason;
      }
      if (r.jobTitleIds.isNotEmpty) {
        rosterPayload['job_title_ids'] = r.jobTitleIds;
      }

      final rosterResp = await _c
          .from('weekly_rosters')
          .insert(rosterPayload)
          .select()
          .single();
      final created = _rosterFromRow(rosterResp);

      // 2) Insert الـ Assignments (إن وُجدت)
      if (r.assignments.isNotEmpty) {
        final asgnPayloads = r.assignments
            .map((a) => {
                  'roster_id': created.id,
                  'employee_id': a.employeeId,
                  'day_index': a.dayIndex,
                  'shift_type': _shiftTypeToStr(a.shiftType),
                  'start_time': a.startTime,
                  'end_time': a.endTime,
                  if (a.notes != null) 'notes': a.notes,
                })
            .toList();
        final asgnResp = await _c
            .from('roster_assignments')
            .insert(asgnPayloads)
            .select();
        for (final ar in (asgnResp as List).cast<Map<String, dynamic>>()) {
          created.assignments.add(_assignmentFromRow(ar));
        }
      }

      _repo.rosters.add(created);
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'roster',
        entityId: created.id,
        entityLabel: 'Week ${r.weekStart.toIso8601String().substring(0, 10)}',
        action: AuditAction.create,
        after: rosterPayload,
      );
      return created;
    } catch (e) {
      // 🆕 ترجمة الأخطاء الفنّيّة لرسائل واضحة للمستخدم
      final raw = e.toString();
      if (raw.contains('weekly_rosters_point_week_unique') ||
          (raw.contains('duplicate key') && raw.contains('weekly_rosters'))) {
        // unique violation على (point_id, week_start) — يوجد روستر سابق
        lastError = 'يوجد روستر سابق لهذه النقطة في نفس الأسبوع. '
            'افتح الروستر الموجود وعدّله بدل إنشاء واحد جديد، '
            'أو امسح الموجود من شاشة "حذف كل الروسترات".\n'
            '(A roster already exists for this point in the selected week — '
            'open & edit it, or delete it first.)';
      } else if (raw.contains('code: 23505')) {
        // أيّ unique violation أخرى
        lastError = 'سجلّ مكرّر — هذا العنصر موجود مسبقاً.\n'
            '(Duplicate record — this entry already exists.)';
      } else if (raw.contains('code: 23503')) {
        // foreign key violation
        lastError = 'خطأ في الربط: عنصر مرتبط غير موجود (FK).\n'
            '(Foreign-key violation — referenced record missing.)';
      } else if (raw.contains('22P02')) {
        lastError = 'صيغة UUID غير صحيحة في أحد الحقول.\n'
            '(Invalid UUID format in one of the fields.)';
      } else {
        lastError = raw;
      }
      M7Log.error('DataService', 'createRoster', error: e);
      return null;
    }
  }

  String _shiftTypeToStr(ShiftType s) {
    switch (s) {
      case ShiftType.morning:
        return 'morning';
      case ShiftType.evening:
        return 'evening';
      case ShiftType.night:
        return 'night';
      case ShiftType.custom:
        return 'custom';
      case ShiftType.off:
        return 'off';
    }
  }

  /// تحديث حالة روستر (Submit/Approve/Reject)
  Future<bool> updateRosterStatus({
    required String rosterId,
    required RosterStatus status,
    String? rejectionReason,
    String? reviewedBy,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{
        'status': _rosterStatusToStr(status),
      };
      if (status == RosterStatus.submitted) {
        payload['submitted_at'] = DateTime.now().toIso8601String();
      }
      if (status == RosterStatus.approved ||
          status == RosterStatus.rejected) {
        payload['reviewed_at'] = DateTime.now().toIso8601String();
        if (reviewedBy != null) payload['reviewed_by'] = reviewedBy;
      }
      if (rejectionReason != null) {
        payload['rejection_reason'] = rejectionReason;
      } else if (status == RosterStatus.draft ||
          status == RosterStatus.approved) {
        // امسح سبب الرفض عند العودة للمسودة أو الاعتماد
        payload['rejection_reason'] = null;
      }
      // التقط حالة قبل
      RosterStatus? oldStatus;
      String? rosterLabel;
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == rosterId);
        oldStatus = r.status;
        rosterLabel = 'Week ${r.weekStart.toIso8601String().substring(0, 10)}';
      } catch (_) {}
      await _c.from('weekly_rosters').update(payload).eq('id', rosterId);

      // حدّث الذاكرة
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == rosterId);
        r.status = status;
        if (status == RosterStatus.submitted) r.submittedAt = DateTime.now();
        if (status == RosterStatus.approved ||
            status == RosterStatus.rejected) {
          r.reviewedAt = DateTime.now();
          r.reviewedBy = reviewedBy;
        }
        if (rejectionReason != null) {
          r.rejectionReason = rejectionReason;
        } else if (status == RosterStatus.draft ||
            status == RosterStatus.approved) {
          r.rejectionReason = null;
        }
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      // ===== Audit =====
      String auditAction;
      switch (status) {
        case RosterStatus.submitted:
          auditAction = AuditAction.submit;
          break;
        case RosterStatus.approved:
          auditAction = AuditAction.approve;
          break;
        case RosterStatus.rejected:
          auditAction = AuditAction.reject;
          break;
        case RosterStatus.draft:
          auditAction = AuditAction.reEdit;
          break;
        default:
          auditAction = AuditAction.update;
      }
      await AuditLogger.instance.log(
        entityType: 'roster',
        entityId: rosterId,
        entityLabel: rosterLabel,
        action: auditAction,
        before: {'status': _rosterStatusToStr(oldStatus ?? RosterStatus.draft)},
        after: payload,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateRosterStatus', error: e);
      return false;
    }
  }

  /// تحديث ملاحظات الروستر
  Future<bool> updateRosterNotes(String rosterId, String? notes) async {
    if (!_supabase.isReady) return false;
    try {
      String? oldNotes;
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == rosterId);
        oldNotes = r.notes;
      } catch (_) {}
      await _c.from('weekly_rosters').update({'notes': notes}).eq('id', rosterId);
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == rosterId);
        r.notes = notes;
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'roster',
        entityId: rosterId,
        action: AuditAction.update,
        before: {'notes': oldNotes},
        after: {'notes': notes},
        description: 'تحديث ملاحظات الروستر',
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateRosterNotes', error: e);
      return false;
    }
  }

  /// استبدال assignments في روستر موجود (للحالة draft فقط)
  /// يحذف القديم ويُدخل الجديد
  Future<bool> replaceRosterAssignments(
    String rosterId,
    List<RosterAssignment> newAssignments,
  ) async {
    if (!_supabase.isReady) return false;
    try {
      // ⚠️ نسخة دفاعية: قد يمرّر المستدعي r.assignments نفسه،
      // وإذا فعلنا r.assignments.clear() لاحقاً ستُمسح القائمة المُمرّرة
      final snapshot = List<RosterAssignment>.from(newAssignments);

      await _c
          .from('roster_assignments')
          .delete()
          .eq('roster_id', rosterId);
      if (snapshot.isNotEmpty) {
        final payloads = snapshot
            .map((a) => {
                  'roster_id': rosterId,
                  'employee_id': a.employeeId,
                  'day_index': a.dayIndex,
                  'shift_type': _shiftTypeToStr(a.shiftType),
                  'start_time': a.startTime,
                  'end_time': a.endTime,
                  if (a.notes != null) 'notes': a.notes,
                })
            .toList();
        // أعد جلب الـ rows المُدخلة لنحصل على المعرّفات الحقيقية من Supabase
        final inserted = await _c
            .from('roster_assignments')
            .insert(payloads)
            .select();
        // استبدل الـ snapshot بالـ rows اللي رجعت (فيها UUID صحيحة)
        snapshot
          ..clear()
          ..addAll((inserted as List)
              .cast<Map<String, dynamic>>()
              .map(_assignmentFromRow));
      }
      // حدّث الذاكرة
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == rosterId);
        r.assignments
          ..clear()
          ..addAll(snapshot);
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'replaceRosterAssignments', error: e);
      return false;
    }
  }

  /// 🆕 يحذف كلّ الروسترات (مع كلّ الـ assignments) من Supabase
  /// والذاكرة المحلّية. عمليّة لا رجعة فيها — استخدمها بحذر.
  /// تُرجع: عدد الروسترات المحذوفة (حتى لو فشلت Supabase نحذف محلّياً).
  Future<int> clearAllRosters() async {
    final localCount = _repo.rosters.length;

    if (_supabase.isReady) {
      try {
        // الترتيب: assignments أوّلاً (FK)، ثمّ الروسترات.
        // 🧹 نَستَخدِم _zeroUuid على مستوى الكِلاس (مَوجود في المَنطِقة المُشتَرَكة).
        await _c.from('roster_assignments').delete().neq('id', _zeroUuid);
        await _c.from('weekly_rosters').delete().neq('id', _zeroUuid);
        lastError = null;
      } catch (e) {
        lastError = e.toString();
        M7Log.error('DataService', 'clearAllRosters', error: e);
      }
    }

    // امسح من الذاكرة (حتى لو Supabase فشلت)
    _repo.rosters.clear();
    // الـ BusPlanDetails مشتقّة من الروسترات — امسحها أيضاً
    for (final p in _repo.busPlans) {
      p.details.clear();
    }
    _repo.notifyListeners();

    // ===== Audit =====
    // ملاحظة: AuditLogger يحوّل entityId غير-UUID (مثل "BULK") تلقائيّاً
    // إلى UUID-صفر ويحفظ القيمة الأصليّة في entity_label/before_data.
    await AuditLogger.instance.log(
      entityType: 'roster',
      entityId: 'BULK',
      entityLabel: 'All rosters',
      action: AuditAction.delete,
      before: {'deleted_count': localCount},
    );

    return localCount;
  }

  Future<bool> deleteRoster(String id) async {
    if (!_supabase.isReady) return false;
    try {
      String? label;
      Map<String, dynamic>? before;
      try {
        final r = _repo.rosters.firstWhere((x) => x.id == id);
        label = 'Week ${r.weekStart.toIso8601String().substring(0, 10)}';
        before = {
          'site_id': r.siteId,
          'week_start': r.weekStart.toIso8601String().substring(0, 10),
          'status': _rosterStatusToStr(r.status),
          'assignments_count': r.assignments.length,
        };
      } catch (_) {}
      await _c.from('weekly_rosters').delete().eq('id', id);
      _repo.rosters.removeWhere((r) => r.id == id);
      _repo.notifyListeners();
      // ===== Audit =====
      await AuditLogger.instance.log(
        entityType: 'roster',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteRoster', error: e);
      return false;
    }
  }

  // ==========================================================
  // 🗑️ Bulk wipe helpers — used by DataResetScreen
  // ==========================================================
  // Each method follows the same pattern as clearAllRosters:
  //   1) Try to delete from Supabase (records lastError on failure)
  //   2) Audit-log the bulk delete
  //   3) Returns the number of rows that the caller can show
  // ==========================================================

  static const String _zeroUuid = '00000000-0000-0000-0000-000000000000';

  Future<int> _wipeTables({
    required List<String> tables,
    required String auditEntityType,
    required String auditLabel,
  }) async {
    int total = 0;
    lastError = null;
    if (!_supabase.isReady) {
      lastError = 'Supabase not ready';
      return 0;
    }
    // 🔧 Batched DELETE-by-IDs (50 per request) — single DELETE-all calls
    //    occasionally fail on Web with "Failed to fetch" (CORS preflight
    //    timeout / proxy size limit). Looping with IDs is reliable.
    const batchSize = 50;
    for (final t in tables) {
      try {
        final rows = await _c.from(t).select('id').limit(10000);
        final ids = (rows as List)
            .map((r) => (r as Map)['id'] as String?)
            .whereType<String>()
            .toList();
        for (var i = 0; i < ids.length; i += batchSize) {
          final slice = ids.sublist(
            i,
            (i + batchSize > ids.length) ? ids.length : i + batchSize,
          );
          try {
            await _c.from(t).delete().inFilter('id', slice);
            total += slice.length;
          } catch (e) {
            lastError = '$t batch ${i ~/ batchSize}: $e';
            M7Log.error('DataService', '_wipeTables.$t.batch', error: e);
            // keep going — partial wipe is better than nothing
          }
        }
      } catch (e) {
        // 🆕 PGRST205 = جَدوَل غَير مَوجود — تَجاوَزه بِهُدوء (deployments قَد
        //   لا تَحوي كُلّ الجَداوِل).
        final msg = e.toString();
        if (msg.contains('PGRST205') ||
            msg.contains('not find the table')) {
          M7Log.info('DataService', '_wipeTables: skipped missing table "$t"');
        } else {
          lastError = '$t: $e';
          M7Log.error('DataService', '_wipeTables.$t', error: e);
        }
      }
    }
    await AuditLogger.instance.log(
      entityType: auditEntityType,
      entityId: 'BULK',
      entityLabel: auditLabel,
      action: AuditAction.delete,
      before: {'deleted_count': total, 'tables': tables},
    );
    return total;
  }

  Future<int> clearAllSites() => _wipeTables(
        tables: ['sites_onboarding'],
        auditEntityType: 'site',
        auditLabel: 'All sites onboarding',
      );

  Future<int> clearAllFormSubmissions() => _wipeTables(
        tables: ['form_submission_actions', 'form_submissions'],
        auditEntityType: 'form_submission',
        auditLabel: 'All form submissions',
      );

  Future<int> clearAllLeaves() => _wipeTables(
        tables: ['employee_leave_requests', 'employee_leave_balances'],
        auditEntityType: 'leave',
        auditLabel: 'All leave requests + balances',
      );

  Future<int> clearAllUniformData() => _wipeTables(
        tables: [
          'employee_uniforms',
          'uniform_purchases',
        ],
        auditEntityType: 'uniform',
        auditLabel: 'All uniform issues + purchases',
      );

  Future<int> clearAllAmana() => _wipeTables(
        tables: [
          'missing_reports',
          'laundry_vouchers',
          'laundry_batches_v2',
          'laundry_requests',
        ],
        auditEntityType: 'amana',
        auditLabel: 'All Amana laundry data',
      );

  Future<int> clearAllNotifications() => _wipeTables(
        tables: ['notifications'],
        auditEntityType: 'notification',
        auditLabel: 'All in-app notifications',
      );

  Future<int> clearAllAttendance() => _wipeTables(
        tables: ['attendance_records'],
        auditEntityType: 'attendance',
        auditLabel: 'All attendance records',
      );

  Future<int> clearAllBusLogs() => _wipeTables(
        // ⚠ bus_trip_logs قَد لا يَكون مَوجوداً في كُلّ deployments (PGRST205).
        //   _wipeTables يَتَجاوَز الجَداوِل المَفقودة بِهُدوء.
        tables: ['bus_shift_logs', 'bus_locations'],
        auditEntityType: 'bus_log',
        auditLabel: 'All bus shift logs + locations',
      );

  /// 👥 Delete every employee + cascade-clean all dependent transactional data.
  ///
  /// 🔥 EXTREMELY DESTRUCTIVE — wipes:
  ///   1. All face enrollments (rows + photos)
  ///   2. All roster assignments + rosters
  ///   3. All bus driver shifts + bus assignments
  ///   4. All leave requests + balances
  ///   5. All attendance records
  ///   6. All employee documents
  ///   7. NULLs out accounts.employee_id (preserves user logins!)
  ///   8. Finally deletes all employees
  ///
  /// Accounts are PRESERVED so admins remain able to log in.
  Future<int> clearAllEmployees() async {
    lastError = null;
    if (!_supabase.isReady) {
      lastError = 'Supabase not ready';
      return 0;
    }

    final summary = <String, int>{};
    // 1) Wipe everything that references employees, in dependency order
    summary['face_enrollments'] = await clearAllFaceEnrollments();
    summary['rosters'] = await clearAllRosters();
    summary['leaves'] = await clearAllLeaves();
    summary['attendance'] = await clearAllAttendance();
    summary['bus_logs'] = await clearAllBusLogs();

    // 2) Tables that reference employees but aren't in the cascade helpers
    final extraTables = [
      'bus_driver_shifts',
      'employee_bus_assignments',
      'employee_documents',
      'point_terminal_clock_logs',
      'point_terminal_sessions',
    ];
    int extraDeleted = 0;
    for (final t in extraTables) {
      try {
        final rows = await _c.from(t).select('id').limit(10000);
        final ids = (rows as List)
            .map((r) => (r as Map)['id'] as String?)
            .whereType<String>()
            .toList();
        for (var i = 0; i < ids.length; i += 50) {
          final slice = ids.sublist(
            i,
            (i + 50 > ids.length) ? ids.length : i + 50,
          );
          try {
            await _c.from(t).delete().inFilter('id', slice);
            extraDeleted += slice.length;
          } catch (_) {/* table may not exist */}
        }
      } catch (_) {/* table may not exist */}
    }
    summary['extra_tables'] = extraDeleted;

    // 3) Decouple accounts from employees (keeps logins intact)
    try {
      await _c.from('accounts').update({
        'employee_id': null,
      }).neq('id', _zeroUuid);
    } catch (e) {
      M7Log.error('DataService', 'clearAllEmployees.unlink_accounts', error: e);
    }

    // 4) Finally, delete the employees themselves (batched)
    int empDeleted = 0;
    try {
      final rows = await _c.from('employees').select('id').limit(10000);
      final ids = (rows as List)
          .map((r) => (r as Map)['id'] as String?)
          .whereType<String>()
          .toList();
      for (var i = 0; i < ids.length; i += 50) {
        final slice = ids.sublist(
          i,
          (i + 50 > ids.length) ? ids.length : i + 50,
        );
        try {
          await _c.from('employees').delete().inFilter('id', slice);
          empDeleted += slice.length;
        } catch (e) {
          lastError = 'employees batch ${i ~/ 50}: $e';
          M7Log.error('DataService', 'clearAllEmployees.delete.batch',
              error: e);
        }
      }
    } catch (e) {
      lastError = 'employees: $e';
      M7Log.error('DataService', 'clearAllEmployees.select', error: e);
    }
    summary['employees'] = empDeleted;

    // 5) Clear local memory
    _repo.employees.clear();
    _repo.notifyListeners();

    await AuditLogger.instance.log(
      entityType: 'employee',
      entityId: 'BULK',
      entityLabel: 'All employees + dependent data',
      action: AuditAction.delete,
      before: {'summary': summary},
    );
    return empDeleted;
  }

  Future<int> clearAllDeviceTokens() => _wipeTables(
        tables: ['device_tokens'],
        auditEntityType: 'device_token',
        auditLabel: 'All FCM device tokens',
      );

  /// 👤 Delete every face enrollment row AND the photos in the storage bucket.
  /// Also resets the `mustEnrollFace` / `faceEnrolledCount` flags on accounts
  /// so the mandatory-enrollment gate fires again on next login.
  /// Fixes the "duplicate face" false positives caused by orphaned rows that
  /// belonged to deleted employees.
  ///
  /// 🔧 Uses batched deletes (50 at a time) instead of a single
  /// `delete().neq(...)` because that pattern occasionally fails with
  /// `ClientException: Failed to fetch` on Web — large unfiltered DELETEs
  /// hit a CORS preflight timeout or proxy limit. Batched DELETE-by-IDs is
  /// reliable everywhere.
  Future<int> clearAllFaceEnrollments() async {
    lastError = null;
    if (!_supabase.isReady) {
      lastError = 'Supabase not ready';
      return 0;
    }
    int total = 0;
    int deletedRows = 0;

    // 1) Collect rows + photo paths
    List<String> ids = [];
    List<String> photoPaths = [];
    try {
      final rows = await _c
          .from('employee_face_enrollments')
          .select('id, photo_path')
          .limit(10000);
      total = (rows as List).length;
      for (final r in rows.cast<Map<String, dynamic>>()) {
        final id = r['id'] as String?;
        if (id != null) ids.add(id);
        final p = r['photo_path'] as String?;
        if (p != null && p.isNotEmpty) photoPaths.add(p);
      }
    } catch (e) {
      lastError = 'select: $e';
      M7Log.error('DataService', 'clearAllFaceEnrollments.select', error: e);
      return 0;
    }

    if (ids.isEmpty) {
      // nothing to delete — still reset account flags + log
    } else {
      // 2) Delete DB rows in batches of 50 (DELETE-by-IDs is reliable)
      const batchSize = 50;
      for (var i = 0; i < ids.length; i += batchSize) {
        final slice = ids.sublist(
          i,
          (i + batchSize > ids.length) ? ids.length : i + batchSize,
        );
        try {
          await _c
              .from('employee_face_enrollments')
              .delete()
              .inFilter('id', slice);
          deletedRows += slice.length;
        } catch (e) {
          lastError = 'delete batch ${i ~/ batchSize}: $e';
          M7Log.error('DataService',
              'clearAllFaceEnrollments.delete.batch${i ~/ batchSize}',
              error: e);
          // keep going — partial delete is better than none
        }
      }
    }

    // 3) Delete photo files from storage (also batched to be safe)
    if (photoPaths.isNotEmpty) {
      const storageBatch = 100;
      for (var i = 0; i < photoPaths.length; i += storageBatch) {
        final slice = photoPaths.sublist(
          i,
          (i + storageBatch > photoPaths.length)
              ? photoPaths.length
              : i + storageBatch,
        );
        try {
          await _c.storage.from('employee_faces').remove(slice);
        } catch (e) {
          M7Log.error(
              'DataService', 'clearAllFaceEnrollments.storage', error: e);
          // not fatal — DB rows are gone
        }
      }
    }

    // 4) Reset enrollment flags on accounts (also batched-safe — UPDATE on
    //    a small column set should not timeout, but we still handle errors)
    try {
      await _c.from('accounts').update({
        'must_enroll_face': true,
        'face_enrolled_count': 0,
        'face_first_enrolled_at': null,
      }).neq('id', _zeroUuid);
    } catch (e) {
      M7Log.error(
          'DataService', 'clearAllFaceEnrollments.accountsReset', error: e);
    }

    await AuditLogger.instance.log(
      entityType: 'face_enrollment',
      entityId: 'BULK',
      entityLabel: 'All face enrollments + photos',
      action: AuditAction.delete,
      before: {
        'requested': total,
        'deleted': deletedRows,
        'photos_purged': photoPaths.length,
      },
    );
    return deletedRows;
  }

  /// 🔢 Reset all auto-numbering counters back to zero.
  /// Affects: country_numbering_counters (used by consume_next_code RPC for
  /// employee codes, voucher numbers, etc.). The next code generated will
  /// start fresh from 1.
  Future<int> resetAllNumberingCounters() async {
    lastError = null;
    if (!_supabase.isReady) {
      lastError = 'Supabase not ready';
      return 0;
    }
    int total = 0;
    try {
      final rows = await _c
          .from('country_numbering_counters')
          .select('rule_id');
      total = (rows as List).length;
      await _c
          .from('country_numbering_counters')
          .update({'current_number': 0})
          .neq('rule_id', _zeroUuid);
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'resetAllNumberingCounters', error: e);
    }
    await AuditLogger.instance.log(
      entityType: 'numbering',
      entityId: 'BULK',
      entityLabel: 'Reset all counters to zero',
      action: AuditAction.update,
      before: {'reset_count': total},
    );
    return total;
  }

  // ==========================================================
  // Accounts (المستخدمون)
  // ==========================================================

  /// مزامنة الحسابات + الأدوار + الدول من Supabase
  Future<void> syncAccounts() async {
    try {
      final accs = await _c.from('accounts').select();
      _repo.accounts.clear();
      for (final r in (accs as List).cast<Map<String, dynamic>>()) {
        _repo.accounts.add(AppAccount(
          id: r['id'] as String,
          username: r['username'] as String,
          passwordHash: '',
          fullName: r['full_name'] as String,
          email: r['email'] as String?,
          phone: r['phone'] as String?,
          employeeId: r['employee_id'] as String?,
          isActive: r['is_active'] as bool? ?? true,
          isSuperAdmin: r['is_super_admin'] as bool? ?? false,
          mustChangePassword:
              r['must_change_password'] as bool? ?? false,
          // 🆕 سياسة تَسجيل بَصمة الوَجه الإجباريّ
          mustEnrollFace: r['must_enroll_face'] as bool? ?? false,
          firstLoginAt: r['first_login_at'] == null
              ? null
              : DateTime.tryParse(r['first_login_at'] as String),
          faceEnrolledAt: r['face_enrolled_at'] == null
              ? null
              : DateTime.tryParse(r['face_enrolled_at'] as String),
          // 🆕 نَوع الحِساب وَالنُقطة وَالجِهاز المَربوط
          accountType:
              AccountTypeX.fromKey(r['account_type'] as String?),
          pointId: r['point_id'] as String?,
          linkedDeviceId: r['linked_device_id'] as String?,
          // 🆕 الحَدّ الأَقصى لِعَدَد الأَجهِزة (0 = بِدون حَدّ)
          maxDevices: (r['max_devices'] as num?)?.toInt() ?? 0,
          createdAt: r['created_at'] == null
              ? null
              : DateTime.tryParse(r['created_at'] as String),
        ));
      }
      // الأدوار المربوطة بالحسابات
      try {
        final ar = await _c.from('user_roles').select();
        _repo.userRoleAssignments.clear();
        for (final r in (ar as List).cast<Map<String, dynamic>>()) {
          _repo.userRoleAssignments.add(UserRoleAssignment(
            id: '${r['user_id']}_${r['role_id']}',
            userId: r['user_id'] as String,
            roleId: r['role_id'] as String,
          ));
        }
      } catch (_) {}
      // الدول المربوطة بالحسابات
      try {
        final uc = await _c.from('user_countries').select();
        _repo.userCountryAccess.clear();
        for (final r in (uc as List).cast<Map<String, dynamic>>()) {
          _repo.userCountryAccess.add(UserCountryAccess(
            userId: r['user_id'] as String,
            countryId: r['country_id'] as String,
          ));
        }
      } catch (_) {}
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncAccounts', error: e);
    }
  }

  Map<String, dynamic> _accountToPayload(AppAccount a,
      {String? createdByUserId}) {
    final p = <String, dynamic>{
      'username': a.username,
      'full_name': a.fullName,
      'is_super_admin': a.isSuperAdmin,
      'is_active': a.isActive,
      // 🆕 عَلَم إجبار تَغيير كلمة المرور
      'must_change_password': a.mustChangePassword,
      // 🆕 عَلَم إجبار تَسجيل بَصمة الوَجه + الوَقت
      'must_enroll_face': a.mustEnrollFace,
      if (a.firstLoginAt != null)
        'first_login_at': a.firstLoginAt!.toUtc().toIso8601String(),
      if (a.faceEnrolledAt != null)
        'face_enrolled_at': a.faceEnrolledAt!.toUtc().toIso8601String(),
      // 🆕 نَوع الحِساب وَالنُقطة وَالجِهاز
      'account_type': a.accountType.key,
      if (a.pointId != null) 'point_id': a.pointId,
      if (a.linkedDeviceId != null) 'linked_device_id': a.linkedDeviceId,
      // 🆕 الحَدّ الأَقصى لِعَدَد الأَجهِزة (Terminal)
      'max_devices': a.maxDevices,
    };
    // 🆕 لِلْـtrigger الهَرَميّ
    if (createdByUserId != null) {
      p['created_by_user_id'] = createdByUserId;
    }
    if (a.passwordHash.isNotEmpty) {
      p['password_hash'] = a.passwordHash;
      // 🆕 عند تغيير كلمة السر، امسح auth_user_id ليستخدم
      // النظام password_hash المحدَّث في Login بدلاً من Supabase Auth القديم
      p['auth_user_id'] = null;
    }
    if (a.email != null && a.email!.isNotEmpty) p['email'] = a.email;
    if (a.phone != null && a.phone!.isNotEmpty) p['phone'] = a.phone;
    if (a.employeeId != null) p['employee_id'] = a.employeeId;
    return p;
  }

  /// إنشاء حساب جديد + ربط أدوار + ربط دول
  Future<AppAccount?> createAccount(
    AppAccount a, {
    required List<String> roleIds,
    required List<String> countryIds,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _accountToPayload(a);
      final r = await _c.from('accounts').insert(payload).select().single();
      final created = AppAccount(
        id: r['id'] as String,
        username: r['username'] as String,
        passwordHash: '',
        fullName: r['full_name'] as String,
        email: r['email'] as String?,
        phone: r['phone'] as String?,
        employeeId: r['employee_id'] as String?,
        isActive: r['is_active'] as bool? ?? true,
        isSuperAdmin: r['is_super_admin'] as bool? ?? false,
        mustChangePassword:
            r['must_change_password'] as bool? ?? a.mustChangePassword,
        // 🆕 تَمرير عَلَم تَسجيل البَصمة من الإدخال إلى الكائِن المُنشَأ
        mustEnrollFace: r['must_enroll_face'] as bool? ?? a.mustEnrollFace,
        // 🆕 نَوع الحِساب وَالنُقطة (يَهُمّ لِحِسابات Point Terminal)
        accountType:
            AccountTypeX.fromKey(r['account_type'] as String?),
        pointId: r['point_id'] as String?,
        linkedDeviceId: r['linked_device_id'] as String?,
        maxDevices: (r['max_devices'] as num?)?.toInt() ?? a.maxDevices,
      );
      // الأدوار
      if (roleIds.isNotEmpty) {
        await _c.from('user_roles').insert(
              roleIds
                  .map((rid) =>
                      {'user_id': created.id, 'role_id': rid})
                  .toList(),
            );
      }
      // الدول
      if (countryIds.isNotEmpty) {
        await _c.from('user_countries').insert(
              countryIds
                  .map((cid) =>
                      {'user_id': created.id, 'country_id': cid})
                  .toList(),
            );
      }
      _repo.accounts.add(created);
      // 🆕 حدّث الذاكرة المحلّيّة لِلأدوار والدول
      for (final rid in roleIds) {
        _repo.userRoleAssignments.add(UserRoleAssignment(
          id: _repo.generateId(),
          userId: created.id,
          roleId: rid,
        ));
      }
      for (final cid in countryIds) {
        _repo.userCountryAccess
            .add(UserCountryAccess(userId: created.id, countryId: cid));
      }
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'account',
        entityId: created.id,
        entityLabel: created.fullName,
        action: AuditAction.create,
        after: {...payload, 'roles': roleIds, 'countries': countryIds},
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createAccount', error: e);
      return null;
    }
  }

  /// تحديث حساب موجود + استبدال الأدوار والدول
  Future<bool> updateAccount(
    AppAccount a, {
    required List<String> roleIds,
    required List<String> countryIds,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.accounts.firstWhere((x) => x.id == a.id);
        before = _accountToPayload(old);
      } catch (_) {}
      final payload = _accountToPayload(a);
      await _c.from('accounts').update(payload).eq('id', a.id);

      // استبدال الأدوار
      await _c.from('user_roles').delete().eq('user_id', a.id);
      if (roleIds.isNotEmpty) {
        await _c.from('user_roles').insert(
              roleIds
                  .map((rid) => {'user_id': a.id, 'role_id': rid})
                  .toList(),
            );
      }
      // 🆕 حدّث الذاكرة المحلّيّة لِلأدوار (وإلّا الواجهة ستُظهر القديم)
      _repo.userRoleAssignments.removeWhere((u) => u.userId == a.id);
      for (final rid in roleIds) {
        _repo.userRoleAssignments.add(UserRoleAssignment(
          id: _repo.generateId(),
          userId: a.id,
          roleId: rid,
        ));
      }

      // استبدال الدول
      await _c.from('user_countries').delete().eq('user_id', a.id);
      if (countryIds.isNotEmpty) {
        await _c.from('user_countries').insert(
              countryIds
                  .map((cid) => {'user_id': a.id, 'country_id': cid})
                  .toList(),
            );
      }
      // 🆕 حدّث الذاكرة المحلّيّة لِلدول
      _repo.userCountryAccess.removeWhere((u) => u.userId == a.id);
      for (final cid in countryIds) {
        _repo.userCountryAccess
            .add(UserCountryAccess(userId: a.id, countryId: cid));
      }

      // 🆕 حدّث الحساب نَفسه في الذاكرة (الاسم/الإيميل/الهاتف/الـactive)
      final idx = _repo.accounts.indexWhere((x) => x.id == a.id);
      if (idx >= 0) {
        _repo.accounts[idx] = a;
      }

      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'account',
        entityId: a.id,
        entityLabel: a.fullName,
        action: AuditAction.update,
        before: before,
        after: {...payload, 'roles': roleIds, 'countries': countryIds},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateAccount', error: e);
      return false;
    }
  }

  Future<bool> deleteAccount(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.accounts.firstWhere((x) => x.id == id);
        before = _accountToPayload(old);
        label = old.fullName;
      } catch (_) {}
      await _c.from('accounts').delete().eq('id', id);
      _repo.accounts.removeWhere((a) => a.id == id);
      _repo.notifyListeners();
      // Audit
      await AuditLogger.instance.log(
        entityType: 'account',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteAccount', error: e);
      return false;
    }
  }

  // ==========================================================
  // Bus Plans (تخطيط الباصات الأسبوعي)
  // ==========================================================

  /// مزامنة كل خطط الباصات + التفاصيل
  Future<void> syncBusPlans() async {
    try {
      final plans = await _c.from('bus_plans').select();
      final details = await _c.from('bus_plan_details').select();

      _repo.busPlans.clear();
      for (final r in (plans as List).cast<Map<String, dynamic>>()) {
        _repo.busPlans.add(BusPlan(
          id: r['id'] as String,
          weekStart: DateTime.parse(r['week_start'] as String),
        ));
      }
      // عبّئ التفاصيل
      for (final d in (details as List).cast<Map<String, dynamic>>()) {
        final planId = d['plan_id'] as String;
        try {
          final plan = _repo.busPlans.firstWhere((p) => p.id == planId);
          plan.details.add(_busPlanDetailFromRow(d));
        } catch (_) {}
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncBusPlans', error: e);
    }
  }

  BusPlanDetail _busPlanDetailFromRow(Map<String, dynamic> r) {
    // الأولوية لـ point_id الجديد، ثم site_id (legacy)
    final pid =
        (r['point_id'] as String?) ?? (r['site_id'] as String?) ?? '';
    final empIds = <String>[];
    final raw = r['employee_ids'];
    if (raw is List) {
      for (final id in raw) {
        if (id is String) empIds.add(id);
      }
    }
    return BusPlanDetail(
      id: r['id'] as String,
      busId: (r['bus_id'] as String?) ?? '',
      siteId: pid,
      dayIndex: (r['day_index'] as num).toInt(),
      time: r['time'] as String,
      employeeIds: empIds,
      direction: tripDirectionFromKey(r['direction'] as String?),
    );
  }

  /// إنشاء BusPlan جديد لأسبوع معيّن
  Future<BusPlan?> createBusPlan(DateTime weekStart) async {
    if (!_supabase.isReady) return null;
    try {
      final wsStr = weekStart.toIso8601String().substring(0, 10);
      // فحص إذا موجود مسبقاً
      final existing = await _c
          .from('bus_plans')
          .select()
          .eq('week_start', wsStr);
      if ((existing as List).isNotEmpty) {
        final r = (existing).cast<Map<String, dynamic>>().first;
        try {
          return _repo.busPlans.firstWhere((p) => p.id == r['id']);
        } catch (_) {
          final plan = BusPlan(
              id: r['id'] as String,
              weekStart: DateTime.parse(r['week_start'] as String));
          _repo.busPlans.add(plan);
          _repo.notifyListeners();
          return plan;
        }
      }
      final r = await _c
          .from('bus_plans')
          .insert({'week_start': wsStr})
          .select()
          .single();
      final created = BusPlan(
        id: r['id'] as String,
        weekStart: DateTime.parse(r['week_start'] as String),
      );
      _repo.busPlans.add(created);
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'bus_plan',
        entityId: created.id,
        entityLabel: 'Week $wsStr',
        action: AuditAction.create,
        after: {'week_start': wsStr},
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createBusPlan', error: e);
      return null;
    }
  }

  /// إضافة تفصيل (وردية باص) لخطة
  Future<BusPlanDetail?> addBusPlanDetail({
    required String planId,
    required String busId,
    required String pointId,
    required int dayIndex,
    required String time,
    required List<String> employeeIds,
    TripDirection direction = TripDirection.tripIn,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'plan_id': planId,
        'bus_id': busId,
        'point_id': pointId,
        'day_index': dayIndex,
        'time': time,
        'employee_ids': employeeIds,
        'direction': direction.key,
      };
      final r = await _c
          .from('bus_plan_details')
          .insert(payload)
          .select()
          .single();
      final detail = _busPlanDetailFromRow(r);
      try {
        final plan = _repo.busPlans.firstWhere((p) => p.id == planId);
        plan.details.add(detail);
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'bus_plan_detail',
        entityId: detail.id,
        action: AuditAction.create,
        after: payload,
      );
      return detail;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'addBusPlanDetail', error: e);
      return null;
    }
  }

  /// حذف تفصيل من خطة
  Future<bool> deleteBusPlanDetail(String detailId) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        for (final p in _repo.busPlans) {
          final d = p.details.firstWhere((x) => x.id == detailId);
          before = {
            'bus_id': d.busId,
            'point_id': d.siteId,
            'day_index': d.dayIndex,
            'time': d.time,
            'employee_ids': d.employeeIds,
          };
          break;
        }
      } catch (_) {}
      await _c.from('bus_plan_details').delete().eq('id', detailId);
      for (final p in _repo.busPlans) {
        p.details.removeWhere((d) => d.id == detailId);
      }
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'bus_plan_detail',
        entityId: detailId,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteBusPlanDetail', error: e);
      return false;
    }
  }

  /// تعديل تفصيل (الباص أو الموظفين)
  Future<bool> updateBusPlanDetail(BusPlanDetail d) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        for (final p in _repo.busPlans) {
          final old = p.details.firstWhere((x) => x.id == d.id);
          before = {
            'bus_id': old.busId,
            'employee_ids': old.employeeIds,
          };
          break;
        }
      } catch (_) {}
      final after = {
        'bus_id': d.busId,
        'point_id': d.siteId,
        'day_index': d.dayIndex,
        'time': d.time,
        'employee_ids': d.employeeIds,
        'direction': d.direction.key,
      };
      await _c.from('bus_plan_details').update(after).eq('id', d.id);
      _repo.notifyListeners();
      lastError = null;
      // Audit
      await AuditLogger.instance.log(
        entityType: 'bus_plan_detail',
        entityId: d.id,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateBusPlanDetail', error: e);
      return false;
    }
  }

  // ==========================================================
  // 🆕 Employee Bus Assignments (إسناد الباص لموظّف ليوم محدّد)
  // ==========================================================

  /// مزامنة كل الـ overrides اليوميّة من Supabase
  Future<void> syncEmployeeBusAssignments() async {
    if (!_supabase.isReady) return;
    try {
      final rows = await _c.from('employee_bus_assignments').select();
      _repo.employeeBusAssignments.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.employeeBusAssignments.add(EmployeeBusAssignment(
          id: r['id'] as String,
          employeeId: r['employee_id'] as String,
          weekStart: DateTime.parse(r['week_start'] as String),
          dayIndex: (r['day_index'] as num).toInt(),
          busId: r['bus_id'] as String,
          notes: r['notes'] as String?,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncEmployeeBusAssignments', error: e);
    }
  }

  /// upsert: إن وُجد override للموظّف/الأسبوع/اليوم → تحديث، وإلّا إنشاء
  Future<EmployeeBusAssignment?> upsertEmployeeBusAssignment({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
    required String busId,
    String? notes,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final ws = weekStart.toIso8601String().substring(0, 10);
      final payload = {
        'employee_id': employeeId,
        'week_start': ws,
        'day_index': dayIndex,
        'bus_id': busId,
        if (notes != null) 'notes': notes,
      };
      final row = await _c
          .from('employee_bus_assignments')
          .upsert(payload, onConflict: 'employee_id,week_start,day_index')
          .select()
          .single();
      final assignment = EmployeeBusAssignment(
        id: row['id'] as String,
        employeeId: row['employee_id'] as String,
        weekStart: DateTime.parse(row['week_start'] as String),
        dayIndex: (row['day_index'] as num).toInt(),
        busId: row['bus_id'] as String,
        notes: row['notes'] as String?,
      );
      // حدّث الذاكرة المحلّية
      final existingIdx = _repo.employeeBusAssignments.indexWhere((a) =>
          a.employeeId == employeeId &&
          a.dayIndex == dayIndex &&
          a.weekStart.year == weekStart.year &&
          a.weekStart.month == weekStart.month &&
          a.weekStart.day == weekStart.day);
      if (existingIdx >= 0) {
        _repo.employeeBusAssignments[existingIdx] = assignment;
      } else {
        _repo.employeeBusAssignments.add(assignment);
      }
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_bus_assignment',
        entityId: assignment.id,
        action: AuditAction.update,
        after: payload,
      );
      return assignment;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'upsertEmployeeBusAssignment', error: e);
      return null;
    }
  }

  /// يحذف override للموظّف/الأسبوع/اليوم — يعود لاستخدام الباص الافتراضي
  Future<bool> deleteEmployeeBusAssignment({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final ws = weekStart.toIso8601String().substring(0, 10);
      await _c
          .from('employee_bus_assignments')
          .delete()
          .eq('employee_id', employeeId)
          .eq('week_start', ws)
          .eq('day_index', dayIndex);
      _repo.employeeBusAssignments.removeWhere((a) =>
          a.employeeId == employeeId &&
          a.dayIndex == dayIndex &&
          a.weekStart.year == weekStart.year &&
          a.weekStart.month == weekStart.month &&
          a.weekStart.day == weekStart.day);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_bus_assignment',
        entityId: '$employeeId|$ws|$dayIndex',
        action: AuditAction.delete,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteEmployeeBusAssignment', error: e);
      return false;
    }
  }

  /// يحدّث الباص الافتراضي لموظّف (يحفظ في employees.default_bus_id)
  Future<bool> updateEmployeeDefaultBus({
    required String employeeId,
    required String? busId,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c
          .from('employees')
          .update({'default_bus_id': busId})
          .eq('id', employeeId);
      _repo.setEmployeeDefaultBus(employeeId, busId);
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee',
        entityId: employeeId,
        action: AuditAction.update,
        after: {'default_bus_id': busId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateEmployeeDefaultBus', error: e);
      return false;
    }
  }

  // ==========================================================
  // 🆕 Employee Daily Memos (مذكّرة الموظّف اليوميّة)
  // ==========================================================

  /// مزامنة كلّ المذكّرات + سُطورها من Supabase
  Future<void> syncEmployeeDailyMemos() async {
    if (!_supabase.isReady) return;
    try {
      final memoRows = await _c.from('employee_daily_memos').select();
      final entryRows =
          await _c.from('employee_daily_memo_entries').select();

      final memos = (memoRows as List).cast<Map<String, dynamic>>();
      final entries = (entryRows as List).cast<Map<String, dynamic>>();

      // group entries by memo_id
      final byMemo = <String, List<EmployeeDailyMemoEntry>>{};
      for (final r in entries) {
        final memoId = r['memo_id'] as String;
        byMemo.putIfAbsent(memoId, () => []).add(EmployeeDailyMemoEntry(
              id: r['id'] as String,
              pointId: r['point_id'] as String,
              startTime: r['start_time'] as String,
              endTime: r['end_time'] as String,
              notes: r['notes'] as String?,
            ));
      }

      _repo.employeeDailyMemos.clear();
      for (final r in memos) {
        final id = r['id'] as String;
        _repo.employeeDailyMemos.add(EmployeeDailyMemo(
          id: id,
          employeeId: r['employee_id'] as String,
          date: DateTime.parse(r['date'] as String),
          notes: r['notes'] as String?,
          entries: byMemo[id] ?? [],
          createdAt: r['created_at'] != null
              ? DateTime.parse(r['created_at'] as String)
              : null,
          updatedAt: r['updated_at'] != null
              ? DateTime.parse(r['updated_at'] as String)
              : null,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncEmployeeDailyMemos', error: e);
    }
  }

  /// upsert للمذكّرة (يُنشئها أو يُحدّث ملاحظاتها).
  Future<EmployeeDailyMemo?> upsertDailyMemo({
    required String employeeId,
    required DateTime date,
    String? notes,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final ds = date.toIso8601String().substring(0, 10);
      final payload = {
        'employee_id': employeeId,
        'date': ds,
        if (notes != null) 'notes': notes,
      };
      final row = await _c
          .from('employee_daily_memos')
          .upsert(payload, onConflict: 'employee_id,date')
          .select()
          .single();
      // حدّث الذاكرة
      var existing = _repo.findDailyMemo(employeeId: employeeId, date: date);
      if (existing == null) {
        existing = EmployeeDailyMemo(
          id: row['id'] as String,
          employeeId: employeeId,
          date: DateTime.parse(row['date'] as String),
          notes: row['notes'] as String?,
        );
        _repo.employeeDailyMemos.add(existing);
      } else {
        existing.notes = row['notes'] as String?;
        existing.updatedAt = DateTime.now();
      }
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_daily_memo',
        entityId: existing.id,
        action: AuditAction.update,
        after: payload,
      );
      return existing;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'upsertDailyMemo', error: e);
      return null;
    }
  }

  /// إضافة سطر للمذكّرة (يُنشئها إذا لم تَكن موجودة).
  Future<EmployeeDailyMemoEntry?> addDailyMemoEntryRemote({
    required String employeeId,
    required DateTime date,
    required String pointId,
    required String startTime,
    required String endTime,
    String? notes,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final memo = await upsertDailyMemo(employeeId: employeeId, date: date);
      if (memo == null) return null;

      final payload = {
        'memo_id': memo.id,
        'point_id': pointId,
        'start_time': startTime,
        'end_time': endTime,
        if (notes != null) 'notes': notes,
      };
      final row = await _c
          .from('employee_daily_memo_entries')
          .insert(payload)
          .select()
          .single();
      final entry = EmployeeDailyMemoEntry(
        id: row['id'] as String,
        pointId: row['point_id'] as String,
        startTime: row['start_time'] as String,
        endTime: row['end_time'] as String,
        notes: row['notes'] as String?,
      );
      memo.entries.add(entry);
      memo.updatedAt = DateTime.now();
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_daily_memo_entry',
        entityId: entry.id,
        action: AuditAction.create,
        after: payload,
      );
      return entry;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'addDailyMemoEntry', error: e);
      return null;
    }
  }

  /// تَعديل سطر مذكّرة.
  Future<bool> updateDailyMemoEntryRemote({
    required String memoId,
    required String entryId,
    String? pointId,
    String? startTime,
    String? endTime,
    String? notes,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{};
      if (pointId != null) payload['point_id'] = pointId;
      if (startTime != null) payload['start_time'] = startTime;
      if (endTime != null) payload['end_time'] = endTime;
      if (notes != null) payload['notes'] = notes;
      if (payload.isEmpty) return true;

      await _c
          .from('employee_daily_memo_entries')
          .update(payload)
          .eq('id', entryId);

      _repo.updateDailyMemoEntry(
        memoId: memoId,
        entryId: entryId,
        pointId: pointId,
        startTime: startTime,
        endTime: endTime,
        notes: notes,
      );
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_daily_memo_entry',
        entityId: entryId,
        action: AuditAction.update,
        after: payload,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateDailyMemoEntry', error: e);
      return false;
    }
  }

  /// حذف سطر مذكّرة.
  Future<bool> deleteDailyMemoEntryRemote({
    required String memoId,
    required String entryId,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c
          .from('employee_daily_memo_entries')
          .delete()
          .eq('id', entryId);
      _repo.deleteDailyMemoEntry(memoId: memoId, entryId: entryId);
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_daily_memo_entry',
        entityId: entryId,
        action: AuditAction.delete,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteDailyMemoEntry', error: e);
      return false;
    }
  }

  /// حذف مذكّرة كاملة (مع كلّ سطورها — cascade).
  Future<bool> deleteDailyMemoRemote(String memoId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('employee_daily_memos').delete().eq('id', memoId);
      _repo.deleteDailyMemo(memoId);
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_daily_memo',
        entityId: memoId,
        action: AuditAction.delete,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteDailyMemo', error: e);
      return false;
    }
  }

  // ==========================================================
  // Rooms (إدارة الغرف + تعيين الموظفين)
  // ==========================================================

  /// مزامنة وسائل النقل من Supabase
  Future<void> syncTransportModes() async {
    try {
      final rows = await _c
          .from('transport_modes')
          .select()
          .order('display_order');
      _repo.transportModes.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.transportModes.add(TransportMode(
          id: r['id'] as String,
          key: r['key'] as String,
          nameAr: r['name_ar'] as String,
          nameEn: r['name_en'] as String,
          icon: r['icon'] as String?,
          isActive: r['is_active'] as bool? ?? true,
          displayOrder: (r['display_order'] as num?)?.toInt() ?? 0,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncTransportModes', error: e);
    }
  }

  /// مزامنة أنواع الغرف من Supabase
  Future<void> syncRoomTypes() async {
    try {
      final rows = await _c
          .from('room_types')
          .select()
          .order('display_order');
      _repo.roomTypes.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.roomTypes.add(RoomType(
          id: r['id'] as String,
          key: r['key'] as String,
          nameAr: r['name_ar'] as String,
          nameEn: r['name_en'] as String,
          icon: r['icon'] as String?,
          isActive: r['is_active'] as bool? ?? true,
          displayOrder: (r['display_order'] as num?)?.toInt() ?? 0,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncRoomTypes', error: e);
    }
  }

  Future<void> syncRooms() async {
    try {
      final rows = await _c.from('rooms').select();
      final emps = await _c.from('room_employees').select();
      _repo.rooms.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.rooms.add(Room(
          id: r['id'] as String,
          name: (r['name'] as String?) ?? '',
          floor: (r['floor'] as String?) ?? '',
          capacity: (r['capacity'] as num?)?.toInt() ?? 0,
          type: (r['type'] as String?) ?? '',
          roomTypeId: r['room_type_id'] as String?,
          status: ((r['status'] as String?) ?? 'active') == 'active'
              ? EntityStatus.active
              : EntityStatus.inactive,
          notes: r['notes'] as String?,
          countryId: r['country_id'] as String?,
          cleanRating: (r['clean_rating'] as num?)?.toInt() ?? 0,
          orderRating: (r['order_rating'] as num?)?.toInt() ?? 0,
        ));
      }
      // التعيينات
      for (final e in (emps as List).cast<Map<String, dynamic>>()) {
        final roomId = e['room_id'] as String;
        final empId = e['employee_id'] as String;
        try {
          final room = _repo.rooms.firstWhere((r) => r.id == roomId);
          if (!room.employeeIds.contains(empId)) {
            room.employeeIds.add(empId);
          }
        } catch (_) {}
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncRooms', error: e);
    }
  }

  Map<String, dynamic> _roomToPayload(Room r) => {
        'name': r.name,
        'floor': r.floor,
        'capacity': r.capacity,
        'type': r.type,
        if (r.roomTypeId != null) 'room_type_id': r.roomTypeId,
        'status': r.status == EntityStatus.active ? 'active' : 'inactive',
        if (r.notes != null) 'notes': r.notes,
        if (r.countryId != null) 'country_id': r.countryId,
        'clean_rating': r.cleanRating,
        'order_rating': r.orderRating,
      };

  Future<Room?> createRoom(Room r, {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _roomToPayload(r);
      if (countryId != null) payload['country_id'] = countryId;
      final res =
          await _c.from('rooms').insert(payload).select().single();
      final created = Room(
        id: res['id'] as String,
        name: r.name,
        floor: r.floor,
        capacity: r.capacity,
        type: r.type,
        roomTypeId: r.roomTypeId,                       // 🆕
        status: r.status,
        notes: r.notes,
        countryId: countryId ?? r.countryId,            // 🆕 ضروري للفلترة
        cleanRating: r.cleanRating,
        orderRating: r.orderRating,
      );
      _repo.rooms.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'room',
        entityId: created.id,
        entityLabel: created.name,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createRoom', error: e);
      return null;
    }
  }

  Future<bool> updateRoom(Room r) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.rooms.firstWhere((x) => x.id == r.id);
        before = _roomToPayload(old);
      } catch (_) {}
      final after = _roomToPayload(r);
      await _c.from('rooms').update(after).eq('id', r.id);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'room',
        entityId: r.id,
        entityLabel: r.name,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateRoom', error: e);
      return false;
    }
  }

  Future<bool> deleteRoom(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      String? label;
      try {
        final old = _repo.rooms.firstWhere((r) => r.id == id);
        before = _roomToPayload(old);
        label = old.name;
      } catch (_) {}
      await _c.from('rooms').delete().eq('id', id);
      _repo.rooms.removeWhere((r) => r.id == id);
      _repo.notifyListeners();
      await AuditLogger.instance.log(
        entityType: 'room',
        entityId: id,
        entityLabel: label,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteRoom', error: e);
      return false;
    }
  }

  Future<bool> assignEmployeeToRoom(
      String roomId, String employeeId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('room_employees').insert({
        'room_id': roomId,
        'employee_id': employeeId,
      });
      try {
        final room = _repo.rooms.firstWhere((r) => r.id == roomId);
        if (!room.employeeIds.contains(employeeId)) {
          room.employeeIds.add(employeeId);
        }
      } catch (_) {}
      _repo.notifyListeners();
      await AuditLogger.instance.log(
        entityType: 'room_assignment',
        entityId: '${roomId}_$employeeId',
        action: AuditAction.assign,
        after: {'room_id': roomId, 'employee_id': employeeId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'assignEmployeeToRoom', error: e);
      return false;
    }
  }

  Future<bool> unassignEmployeeFromRoom(
      String roomId, String employeeId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c
          .from('room_employees')
          .delete()
          .eq('room_id', roomId)
          .eq('employee_id', employeeId);
      try {
        final room = _repo.rooms.firstWhere((r) => r.id == roomId);
        room.employeeIds.remove(employeeId);
      } catch (_) {}
      _repo.notifyListeners();
      await AuditLogger.instance.log(
        entityType: 'room_assignment',
        entityId: '${roomId}_$employeeId',
        action: AuditAction.unassign,
        before: {'room_id': roomId, 'employee_id': employeeId},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'unassignEmployeeFromRoom', error: e);
      return false;
    }
  }

  // ==========================================================
  // Violations (المخالفات)
  // ==========================================================

  Future<void> syncViolations() async {
    try {
      final rows = await _c.from('violations').select();
      _repo.violations.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.violations.add(Violation(
          id: r['id'] as String,
          employeeId: r['employee_id'] as String,
          type: _parseViolationType((r['type'] as String?) ?? 'other'),
          date: DateTime.parse(r['date'] as String),
          status: _parseViolationStatus(
              (r['status'] as String?) ?? 'pending'),
          deduction: (r['deduction'] as num?)?.toDouble() ?? 0,
          notes: r['notes'] as String?,
          addedBy: (r['added_by'] as String?) ?? '',
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncViolations', error: e);
    }
  }

  ViolationType _parseViolationType(String s) {
    switch (s) {
      case 'late_':
      case 'late':
        return ViolationType.late_;
      case 'cleanliness':
        return ViolationType.cleanliness;
      case 'dressCode':
      case 'dress_code':
        return ViolationType.dressCode;
      case 'absence':
        return ViolationType.absence;
      case 'behavior':
        return ViolationType.behavior;
      default:
        return ViolationType.other;
    }
  }

  String _violationTypeToStr(ViolationType t) {
    switch (t) {
      case ViolationType.late_:
        return 'late_';
      case ViolationType.cleanliness:
        return 'cleanliness';
      case ViolationType.dressCode:
        return 'dressCode';
      case ViolationType.absence:
        return 'absence';
      case ViolationType.behavior:
        return 'behavior';
      case ViolationType.other:
        return 'other';
    }
  }

  ViolationStatus _parseViolationStatus(String s) {
    switch (s) {
      case 'approved':
        return ViolationStatus.approved;
      case 'resolved':
        return ViolationStatus.resolved;
      default:
        return ViolationStatus.pending;
    }
  }

  Map<String, dynamic> _violationToPayload(Violation v) => {
        'employee_id': v.employeeId,
        'type': _violationTypeToStr(v.type),
        'status': v.status.toString().split('.').last,
        'date': v.date.toIso8601String(),
        'deduction': v.deduction,
        if (v.notes != null) 'notes': v.notes,
        if (v.addedBy.isNotEmpty) 'added_by': v.addedBy,
      };

  Future<Violation?> createViolation(Violation v) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = _violationToPayload(v);
      final r = await _c
          .from('violations')
          .insert(payload)
          .select()
          .single();
      final created = Violation(
        id: r['id'] as String,
        employeeId: v.employeeId,
        type: v.type,
        date: v.date,
        status: v.status,
        deduction: v.deduction,
        notes: v.notes,
        addedBy: v.addedBy,
      );
      _repo.violations.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'violation',
        entityId: created.id,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createViolation', error: e);
      return null;
    }
  }

  Future<bool> updateViolation(Violation v) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.violations.firstWhere((x) => x.id == v.id);
        before = _violationToPayload(old);
      } catch (_) {}
      final after = _violationToPayload(v);
      await _c.from('violations').update(after).eq('id', v.id);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'violation',
        entityId: v.id,
        action: AuditAction.update,
        before: before,
        after: after,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateViolation', error: e);
      return false;
    }
  }

  Future<bool> deleteViolation(String id) async {
    if (!_supabase.isReady) return false;
    try {
      Map<String, dynamic>? before;
      try {
        final old = _repo.violations.firstWhere((v) => v.id == id);
        before = _violationToPayload(old);
      } catch (_) {}
      await _c.from('violations').delete().eq('id', id);
      _repo.violations.removeWhere((v) => v.id == id);
      _repo.notifyListeners();
      await AuditLogger.instance.log(
        entityType: 'violation',
        entityId: id,
        action: AuditAction.delete,
        before: before,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteViolation', error: e);
      return false;
    }
  }

  // ==========================================================
  // Laundry Tickets (تذاكر الغسيل)
  // ==========================================================

  Future<void> syncLaundryTickets() async {
    try {
      final rows = await _c.from('laundry_tickets').select();
      _repo.laundryTickets.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.laundryTickets.add(_laundryFromRow(r));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncLaundryTickets', error: e);
    }
  }

  LaundryTicket _laundryFromRow(Map<String, dynamic> r) {
    final items = <LaundryItem>[];
    final rawItems = r['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          items.add(LaundryItem(
            id: item['id']?.toString() ?? '',
            uniformItemId: item['uniformItemId']?.toString() ?? '',
            quantity: (item['quantity'] as num?)?.toInt() ?? 1,
          ));
        }
      }
    }
    final missing = <String>[];
    final rawMissing = r['missing_items'];
    if (rawMissing is List) {
      for (final m in rawMissing) {
        if (m is String) missing.add(m);
      }
    }
    return LaundryTicket(
      id: r['id'] as String,
      ticketNumber: (r['ticket_no'] as String?) ?? '',
      employeeId: r['employee_id'] as String,
      stage: LaundryStageX.fromKey((r['stage'] as String?) ?? 'receivedFromEmployee'),
      createdAt: r['created_at'] == null
          ? null
          : DateTime.tryParse(r['created_at'] as String),
      sentAt: r['sent_at'] == null
          ? null
          : DateTime.tryParse(r['sent_at'] as String),
      receivedAt: r['returned_at'] == null
          ? null
          : DateTime.tryParse(r['returned_at'] as String),
      deliveredAt: r['delivered_at'] == null
          ? null
          : DateTime.tryParse(r['delivered_at'] as String),
      items: items,
      missingItems: missing,
      notes: r['notes'] as String?,
      batchId: r['batch_id'] as String?, // 🆕
    );
  }

  // ==========================================================
  // 🆕 فواتير المغسلة (Laundry Batches)
  // ==========================================================
  Future<void> syncLaundryBatches() async {
    try {
      final rows = await _c
          .from('laundry_batches')
          .select()
          .order('created_at', ascending: false);
      _repo.laundryBatches.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.laundryBatches.add(LaundryBatch(
          id: r['id'] as String,
          batchNo: (r['batch_no'] as String?) ?? '',
          countryId: r['country_id'] as String?,
          status: LaundryBatchStatusX.fromKey(
              (r['status'] as String?) ?? 'sent'),
          createdAt: r['created_at'] == null
              ? null
              : DateTime.tryParse(r['created_at'] as String),
          sentAt: r['sent_at'] == null
              ? null
              : DateTime.tryParse(r['sent_at'] as String),
          receivedAt: r['received_at'] == null
              ? null
              : DateTime.tryParse(r['received_at'] as String),
          notes: r['notes'] as String?,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncLaundryBatches', error: e);
    }
  }

  /// إنشاء فاتورة جديدة + تحديث التذاكر المختارة لتكون مرسلة
  /// يستخدم ترقيم آلي عبر RPC
  Future<LaundryBatch?> createBatchAndShip({
    required List<String> ticketIds,
    required String countryId,
    String? notes,
    String? supplierId, // 🆕 المورّد
  }) async {
    if (!_supabase.isReady) return null;
    if (ticketIds.isEmpty) {
      lastError = 'No tickets selected';
      return null;
    }
    try {
      // 1) ولّد رقم الفاتورة عبر RPC
      String batchNo = '';
      final code = await consumeNextCode(
          technicalId: 'laundry_batch', countryId: countryId);
      if (code != null) batchNo = code;
      if (batchNo.isEmpty) {
        batchNo = 'LBT-${DateTime.now().millisecondsSinceEpoch}';
      }

      // 2) أنشئ الفاتورة
      final now = DateTime.now().toIso8601String();
      final created = await _c
          .from('laundry_batches')
          .insert({
            'batch_no': batchNo,
            'country_id': countryId,
            if (supplierId != null) 'supplier_id': supplierId, // 🆕
            'status': 'sent',
            'sent_at': now,
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          })
          .select()
          .single();
      final batchId = created['id'] as String;

      // 3) حدّث التذاكر: stage=sentToLaundry + batch_id
      await _c
          .from('laundry_tickets')
          .update({
            'stage': LaundryStage.sentToLaundry.key,
            'sent_at': now,
            'batch_id': batchId,
          })
          .inFilter('id', ticketIds);

      // 4) حدّث الذاكرة المحلية
      final batch = LaundryBatch(
        id: batchId,
        batchNo: batchNo,
        countryId: countryId,
        supplierId: supplierId, // 🆕
        status: LaundryBatchStatus.sent,
        sentAt: DateTime.now(),
        notes: notes,
      );
      _repo.laundryBatches.insert(0, batch);
      for (final t in _repo.laundryTickets
          .where((t) => ticketIds.contains(t.id))) {
        t.stage = LaundryStage.sentToLaundry;
        t.sentAt = DateTime.now();
        t.batchId = batchId;
      }
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'laundry_batch',
        entityId: batchId,
        entityLabel: batchNo,
        action: AuditAction.create,
        after: {
          'batch_no': batchNo,
          'tickets': ticketIds,
        },
      );
      return batch;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createBatchAndShip', error: e);
      return null;
    }
  }

  /// استلام الفاتورة من المغسلة - تحدّث الفاتورة وكل تذاكرها
  Future<bool> receiveBatch(String batchId) async {
    if (!_supabase.isReady) return false;
    try {
      final now = DateTime.now().toIso8601String();
      await _c.from('laundry_batches').update({
        'status': 'received',
        'received_at': now,
      }).eq('id', batchId);

      await _c
          .from('laundry_tickets')
          .update({
            'stage': LaundryStage.receivedFromLaundry.key,
            'returned_at': now,
          })
          .eq('batch_id', batchId);

      // تحديث الذاكرة المحلية
      try {
        final b = _repo.laundryBatches.firstWhere((x) => x.id == batchId);
        b.status = LaundryBatchStatus.received;
        b.receivedAt = DateTime.now();
      } catch (_) {}
      for (final t in _repo.laundryTickets
          .where((t) => t.batchId == batchId)) {
        t.stage = LaundryStage.receivedFromLaundry;
        t.receivedAt = DateTime.now();
      }
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'laundry_batch',
        entityId: batchId,
        action: AuditAction.update,
        after: {'status': 'received'},
        description: 'استلام الفاتورة من المغسلة',
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'receiveBatch', error: e);
      return false;
    }
  }

  Future<LaundryTicket?> createLaundryTicket(LaundryTicket t) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'ticket_no': t.ticketNumber,
        'employee_id': t.employeeId,
        'stage': t.stage.key,
        'items': t.items
            .map((i) => {
                  'id': i.id,
                  'uniformItemId': i.uniformItemId,
                  'quantity': i.quantity,
                })
            .toList(),
        'missing_items': t.missingItems,
        if (t.notes != null) 'notes': t.notes,
      };
      final r = await _c
          .from('laundry_tickets')
          .insert(payload)
          .select()
          .single();
      final created = _laundryFromRow(r);
      _repo.laundryTickets.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'laundry_ticket',
        entityId: created.id,
        entityLabel: created.ticketNumber,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createLaundryTicket', error: e);
      return null;
    }
  }

  /// تطوير حالة التذكرة (مع تحديث الـ timestamp المناسب)
  Future<bool> advanceLaundryStage(String id, LaundryStage stage) async {
    if (!_supabase.isReady) return false;
    try {
      final now = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{'stage': stage.key};
      switch (stage) {
        case LaundryStage.sentToLaundry:
          payload['sent_at'] = now;
          break;
        case LaundryStage.receivedFromLaundry:
          payload['returned_at'] = now;
          break;
        case LaundryStage.deliveredToEmployee:
          payload['delivered_at'] = now;
          break;
        default:
          break;
      }
      LaundryStage? oldStage;
      try {
        oldStage = _repo.laundryTickets.firstWhere((t) => t.id == id).stage;
      } catch (_) {}
      await _c.from('laundry_tickets').update(payload).eq('id', id);
      try {
        final t = _repo.laundryTickets.firstWhere((x) => x.id == id);
        t.stage = stage;
        if (stage == LaundryStage.sentToLaundry) t.sentAt = DateTime.now();
        if (stage == LaundryStage.receivedFromLaundry) {
          t.receivedAt = DateTime.now();
        }
        if (stage == LaundryStage.deliveredToEmployee) {
          t.deliveredAt = DateTime.now();
        }
      } catch (_) {}
      // 🆕 إنشاء إشعار للموظف
      _repo.createLaundryStageNotification(id, stage);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'laundry_ticket',
        entityId: id,
        action: AuditAction.update,
        before: {'stage': oldStage?.key},
        after: payload,
        description: 'تغيير حالة الغسيل إلى ${stage.key}',
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'advanceLaundryStage', error: e);
      return false;
    }
  }

  // ============================================================
  // 🎓 OnPoint Training (تدريب الموظفين الجدد على نقطة)
  // ============================================================
  OnPointTraining _onPointFromRow(Map<String, dynamic> r) {
    final expRaw = r['experience'];
    final exp = <OnPointExperienceEntry>[];
    if (expRaw is List) {
      for (final item in expRaw) {
        if (item is Map) {
          exp.add(OnPointExperienceEntry(
            company: (item['company'] ?? '').toString(),
            duration: (item['duration'] ?? '').toString(),
            position: (item['position'] ?? '').toString(),
          ));
        }
      }
    }
    return OnPointTraining(
      id: r['id'].toString(),
      employeeId: r['employee_id'].toString(),
      pointId: r['point_id'].toString(),
      trainerEmployeeId: r['trainer_employee_id']?.toString(),
      countryId: r['country_id']?.toString(),
      startDate: r['start_date'] == null
          ? null
          : DateTime.tryParse(r['start_date'].toString()),
      plannedDays: (r['planned_days'] as num?)?.toInt() ?? 7,
      actualEndDate: r['actual_end_date'] == null
          ? null
          : DateTime.tryParse(r['actual_end_date'].toString()),
      langEnglish: r['lang_english'] == true,
      langUrdu: r['lang_urdu'] == true,
      langArabic: r['lang_arabic'] == true,
      langOther: r['lang_other']?.toString(),
      experience: exp,
      stage: OnPointStageX.fromKey(_stageDbToKey(r['stage']?.toString())),
      level: OnPointLevelX.fromKey(r['level']?.toString()),
      approved: r['approved'] as bool?,
      operationComments: r['operation_comments']?.toString(),
      employeeSignedBy: r['employee_signed_by']?.toString(),
      employeeSignedAt: r['employee_signed_at'] == null
          ? null
          : DateTime.tryParse(r['employee_signed_at'].toString()),
      opSupervisorSignedBy: r['op_supervisor_signed_by']?.toString(),
      opSupervisorSignedAt: r['op_supervisor_signed_at'] == null
          ? null
          : DateTime.tryParse(r['op_supervisor_signed_at'].toString()),
      campBossSignedBy: r['camp_boss_signed_by']?.toString(),
      campBossSignedAt: r['camp_boss_signed_at'] == null
          ? null
          : DateTime.tryParse(r['camp_boss_signed_at'].toString()),
      hrSignedBy: r['hr_signed_by']?.toString(),
      hrSignedAt: r['hr_signed_at'] == null
          ? null
          : DateTime.tryParse(r['hr_signed_at'].toString()),
      notes: r['notes']?.toString(),
      attachmentUrl: r['attachment_url']?.toString(),
      createdAt: r['created_at'] == null
          ? DateTime.now()
          : (DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now()),
      updatedAt: r['updated_at'] == null
          ? DateTime.now()
          : (DateTime.tryParse(r['updated_at'].toString()) ?? DateTime.now()),
    );
  }

  /// SQL stage 'in_progress' → enum key 'inProgress' / etc.
  String? _stageDbToKey(String? s) {
    if (s == null) return null;
    switch (s) {
      case 'not_started':
        return 'notStarted';
      case 'in_progress':
        return 'inProgress';
      case 'awaiting_review':
        return 'awaitingReview';
      case 'passed':
        return 'passed';
      case 'rejected':
        return 'rejected';
    }
    return s;
  }

  /// enum key 'inProgress' → SQL 'in_progress'
  String _stageKeyToDb(OnPointStage st) {
    switch (st) {
      case OnPointStage.notStarted:
        return 'not_started';
      case OnPointStage.inProgress:
        return 'in_progress';
      case OnPointStage.awaitingReview:
        return 'awaiting_review';
      case OnPointStage.passed:
        return 'passed';
      case OnPointStage.rejected:
        return 'rejected';
    }
  }

  Map<String, dynamic> _onPointToPayload(OnPointTraining t) {
    return <String, dynamic>{
      'id': t.id,
      'employee_id': t.employeeId,
      'point_id': t.pointId,
      'trainer_employee_id': t.trainerEmployeeId,
      'country_id': t.countryId,
      'start_date':
          t.startDate?.toIso8601String().substring(0, 10),
      'planned_days': t.plannedDays,
      'actual_end_date':
          t.actualEndDate?.toIso8601String().substring(0, 10),
      'lang_english': t.langEnglish,
      'lang_urdu': t.langUrdu,
      'lang_arabic': t.langArabic,
      'lang_other': t.langOther,
      'experience': t.experience
          .map((e) => {
                'company': e.company,
                'duration': e.duration,
                'position': e.position,
              })
          .toList(),
      'stage': _stageKeyToDb(t.stage),
      'level': t.level?.key, // 'a' / 'b' / 'c'
      'approved': t.approved,
      'operation_comments': t.operationComments,
      'employee_signed_by': t.employeeSignedBy,
      'employee_signed_at': t.employeeSignedAt?.toIso8601String(),
      'op_supervisor_signed_by': t.opSupervisorSignedBy,
      'op_supervisor_signed_at': t.opSupervisorSignedAt?.toIso8601String(),
      'camp_boss_signed_by': t.campBossSignedBy,
      'camp_boss_signed_at': t.campBossSignedAt?.toIso8601String(),
      'hr_signed_by': t.hrSignedBy,
      'hr_signed_at': t.hrSignedAt?.toIso8601String(),
      'notes': t.notes,
      'attachment_url': t.attachmentUrl,
    };
  }

  Future<List<OnPointTraining>> loadOnPointTrainings({
    String? countryId,
  }) async {
    if (!_supabase.isReady) return [];
    try {
      var query = _c.from('on_point_trainings').select();
      if (countryId != null) {
        query = query.eq('country_id', countryId);
      }
      final rows =
          await query.order('updated_at', ascending: false);
      final list = <OnPointTraining>[];
      for (final r in (rows as List)) {
        list.add(_onPointFromRow(r as Map<String, dynamic>));
      }
      _repo.onPointTrainings
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<OnPointTraining?> upsertOnPointTraining(OnPointTraining t) async {
    if (!_supabase.isReady) {
      _repo.upsertOnPointTraining(t);
      return t;
    }
    try {
      final payload = _onPointToPayload(t);
      await _c.from('on_point_trainings').upsert(payload);
      _repo.upsertOnPointTraining(t);
      return t;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> deleteOnPointTraining(String id) async {
    if (!_supabase.isReady) {
      _repo.deleteOnPointTraining(id);
      return true;
    }
    try {
      await _c.from('on_point_trainings').delete().eq('id', id);
      _repo.deleteOnPointTraining(id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ============================================================
  // 📋 نظام النماذج (Forms)
  // ============================================================
  Future<List<FormTemplate>> loadFormTemplates() async {
    if (!_supabase.isReady) return [];
    try {
      final rows = await _c
          .from('form_templates')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final list = <FormTemplate>[];
      for (final r in (rows as List)) {
        list.add(FormTemplate(
          id: r['id'].toString(),
          code: (r['code'] ?? '').toString(),
          nameAr: (r['name_ar'] ?? '').toString(),
          nameEn: (r['name_en'] ?? '').toString(),
          descriptionAr: r['description_ar']?.toString(),
          descriptionEn: r['description_en']?.toString(),
          category: (r['category'] ?? 'general').toString(),
          icon: r['icon']?.toString(),
          referenceFileUrl: r['reference_file_url']?.toString(),
          schema: _parseListMap(r['schema_json']),
          workflow: _parseListMap(r['workflow_json']),
          permissions: _parseMap(r['permissions_json']),
          countryId: r['country_id']?.toString(),
          isActive: r['is_active'] != false,
          sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
        ));
      }
      _repo.formTemplates
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<FormTemplate?> upsertFormTemplate(FormTemplate t) async {
    if (!_supabase.isReady) {
      // وضع غير متصل
      final i = _repo.formTemplates.indexWhere((x) => x.id == t.id);
      if (i == -1) {
        _repo.formTemplates.add(t);
      } else {
        _repo.formTemplates[i] = t;
      }
      _repo.notifyListeners();
      return t;
    }
    try {
      final payload = {
        'id': t.id,
        'code': t.code,
        'name_ar': t.nameAr,
        'name_en': t.nameEn,
        'description_ar': t.descriptionAr,
        'description_en': t.descriptionEn,
        'category': t.category,
        'icon': t.icon,
        'reference_file_url': t.referenceFileUrl,
        'schema_json': t.schema,
        'workflow_json': t.workflow,
        'permissions_json': t.permissions,
        'country_id': t.countryId,
        'is_active': t.isActive,
        'sort_order': t.sortOrder,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _c.from('form_templates').upsert(payload);
      final i = _repo.formTemplates.indexWhere((x) => x.id == t.id);
      if (i == -1) {
        _repo.formTemplates.add(t);
      } else {
        _repo.formTemplates[i] = t;
      }
      _repo.notifyListeners();
      return t;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> deleteFormTemplate(String id) async {
    if (!_supabase.isReady) {
      _repo.formTemplates.removeWhere((t) => t.id == id);
      _repo.notifyListeners();
      return true;
    }
    try {
      await _c.from('form_templates').delete().eq('id', id);
      _repo.formTemplates.removeWhere((t) => t.id == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<List<FormSubmission>> loadFormSubmissions({String? employeeId}) async {
    if (!_supabase.isReady) return [];
    try {
      var q = _c.from('form_submissions').select();
      if (employeeId != null) {
        q = q.eq('employee_id', employeeId);
      }
      final rows = await q;
      final list = <FormSubmission>[];
      for (final r in (rows as List)) {
        list.add(FormSubmission(
          id: r['id'].toString(),
          formNo: (r['form_no'] ?? '').toString(),
          templateId: r['template_id'].toString(),
          employeeId: r['employee_id']?.toString(),
          submittedBy: r['submitted_by']?.toString(),
          countryId: r['country_id']?.toString(),
          data: _parseMap(r['data_json']),
          status: FormSubmissionStatusX.fromKey(r['status']?.toString()),
          currentStep: (r['current_step'] as num?)?.toInt() ?? 0,
          totalSteps: (r['total_steps'] as num?)?.toInt() ?? 0,
          rejectionReason: r['rejection_reason']?.toString(),
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
              DateTime.now(),
          submittedAt: r['submitted_at'] != null
              ? DateTime.tryParse(r['submitted_at'].toString())
              : null,
          completedAt: r['completed_at'] != null
              ? DateTime.tryParse(r['completed_at'].toString())
              : null,
        ));
      }
      // دمج مع المحلي (replace)
      _repo.formSubmissions
        ..removeWhere((s) =>
            employeeId == null ? true : s.employeeId == employeeId)
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<FormSubmission?> createFormSubmission(
      FormSubmission submission) async {
    if (!_supabase.isReady) return null;
    try {
      // ولّد رقم تسلسلي
      final code = await consumeNextCode(
          technicalId: 'form_submission',
          countryId: submission.countryId ?? '');
      submission.formNo = code ?? submission.formNo;
      final payload = {
        'form_no': submission.formNo,
        'template_id': submission.templateId,
        'employee_id': submission.employeeId,
        'submitted_by': submission.submittedBy,
        'country_id': submission.countryId,
        'data_json': submission.data,
        'status': submission.status.key,
        'current_step': submission.currentStep,
        'total_steps': submission.totalSteps,
      };
      final r = await _c
          .from('form_submissions')
          .insert(payload)
          .select()
          .single();
      submission = FormSubmission(
        id: r['id'].toString(),
        formNo: submission.formNo,
        templateId: submission.templateId,
        employeeId: submission.employeeId,
        submittedBy: submission.submittedBy,
        countryId: submission.countryId,
        data: submission.data,
        status: submission.status,
        currentStep: submission.currentStep,
        totalSteps: submission.totalSteps,
      );
      _repo.formSubmissions.insert(0, submission);
      _repo.notifyListeners();
      return submission;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  // ============================================================
  // 🆕 Uniform Purchases (المَشتَريات)
  // ============================================================
  Future<List<UniformPurchase>> loadUniformPurchases() async {
    if (!_supabase.isReady) return [];
    try {
      final rows = await _c
          .from('uniform_purchases')
          .select()
          .order('purchase_date', ascending: false);
      final list = <UniformPurchase>[];
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final itemsRaw = m['items'];
        final lines = <UniformPurchaseLine>[];
        if (itemsRaw is List) {
          for (final l in itemsRaw) {
            if (l is Map) {
              lines.add(UniformPurchaseLine.fromJson(
                  Map<String, dynamic>.from(l)));
            }
          }
        }
        list.add(UniformPurchase(
          id: m['id'].toString(),
          purchaseNo: (m['purchase_no'] ?? '').toString(),
          purchaseDate: DateTime.tryParse(m['purchase_date']?.toString() ?? '') ??
              DateTime.now(),
          supplierName: m['supplier_name']?.toString(),
          supplierPhone: m['supplier_phone']?.toString(),
          invoiceNo: m['invoice_no']?.toString(),
          invoiceUrl: m['invoice_url']?.toString(),
          items: lines,
          subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
          vatAmount: (m['vat_amount'] as num?)?.toDouble() ?? 0,
          totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0,
          currency: (m['currency'] ?? 'AED').toString(),
          countryId: m['country_id']?.toString(),
          recordedById: m['recorded_by_id']?.toString(),
          recordedByName: m['recorded_by_name']?.toString(),
          notes: m['notes']?.toString(),
          createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
              DateTime.now(),
        ));
      }
      _repo.uniformPurchases
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<UniformPurchase?> createUniformPurchase(UniformPurchase p) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = {
        if (p.purchaseNo.isNotEmpty) 'purchase_no': p.purchaseNo,
        'purchase_date': p.purchaseDate.toIso8601String().substring(0, 10),
        if (p.supplierName != null) 'supplier_name': p.supplierName,
        if (p.supplierPhone != null) 'supplier_phone': p.supplierPhone,
        if (p.invoiceNo != null) 'invoice_no': p.invoiceNo,
        if (p.invoiceUrl != null) 'invoice_url': p.invoiceUrl,
        'items': p.items.map((l) => l.toJson()).toList(),
        'subtotal': p.subtotal,
        'vat_amount': p.vatAmount,
        'total_amount': p.totalAmount,
        'currency': p.currency,
        if (p.countryId != null) 'country_id': p.countryId,
        if (p.recordedById != null) 'recorded_by_id': p.recordedById,
        if (p.recordedByName != null) 'recorded_by_name': p.recordedByName,
        if (p.notes != null) 'notes': p.notes,
      };
      final r = await _c
          .from('uniform_purchases')
          .insert(payload)
          .select()
          .single();
      final saved = UniformPurchase(
        id: r['id'].toString(),
        purchaseNo: (r['purchase_no'] ?? p.purchaseNo).toString(),
        purchaseDate: p.purchaseDate,
        supplierName: p.supplierName,
        supplierPhone: p.supplierPhone,
        invoiceNo: p.invoiceNo,
        invoiceUrl: p.invoiceUrl,
        items: p.items,
        subtotal: p.subtotal,
        vatAmount: p.vatAmount,
        totalAmount: p.totalAmount,
        currency: p.currency,
        countryId: p.countryId,
        recordedById: p.recordedById,
        recordedByName: p.recordedByName,
        notes: p.notes,
      );
      _repo.uniformPurchases.insert(0, saved);
      // الـtrigger في DB سَيُحَدِّث uniform_items.quantity — أَعِد تَحميل الكاتالوج
      await syncUniformItems();
      _repo.notifyListeners();
      return saved;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// 🆕 حَذف كُلّ سُطور سَند صَرف بِنَفس issueNo
  /// (يَخصِم الكَمّيّات مِن المَخزون تِلقائيّاً عَبر trigger الـDB)
  Future<bool> deleteIssueByNo(String issueNo) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('employee_uniforms').delete().eq('issue_no', issueNo);
      _repo.employeeUniforms.removeWhere((u) => u.issueNo == issueNo);
      await syncUniformItems();
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteIssueByNo', error: e);
      return false;
    }
  }

  /// 🆕 حِفظ تَوقيع المُوَظَّف لِكُلّ سُطور سَند صَرف بِنَفس issueNo
  /// (السَند الواحِد قَد يَحوي عِدّة employee_uniforms records)
  Future<bool> saveIssueSignature({
    required String issueNo,
    required String signatureBase64,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final now = DateTime.now().toIso8601String();
      await _c.from('employee_uniforms').update({
        'signature_data': signatureBase64,
        'signed_at': now,
      }).eq('issue_no', issueNo);
      // حَدِّث الكاش المَحَلِّيّ
      for (final u in _repo.employeeUniforms) {
        if (u.issueNo == issueNo) {
          u.signatureData = signatureBase64;
          u.signedAt = DateTime.parse(now);
        }
      }
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'saveIssueSignature', error: e);
      return false;
    }
  }

  /// 🆕 يُولِّد رَقَم فاتورة استِلام تالٍ بِالاستِعلام مِن DB مُباشَرَةً
  /// لِتَفادي تَكرار الأَرقام عَنَدَ كاش غَير مُحَدَّث.
  /// التَنسيق: REC-{YEAR}-{NNNN}
  Future<String> nextReceiptNo() async {
    final year = DateTime.now().year;
    final prefix = 'REC-$year-';
    if (!_supabase.isReady) {
      // Fallback: استَخدِم الكاش المَحَلِّيّ
      var maxSeq = 0;
      for (final p in _repo.uniformPurchases) {
        if (p.purchaseNo.startsWith(prefix)) {
          final n = int.tryParse(p.purchaseNo.substring(prefix.length));
          if (n != null && n > maxSeq) maxSeq = n;
        }
      }
      return '$prefix${(maxSeq + 1).toString().padLeft(4, '0')}';
    }
    try {
      final rows = await _c
          .from('uniform_purchases')
          .select('purchase_no')
          .like('purchase_no', '$prefix%')
          .order('purchase_no', ascending: false)
          .limit(1);
      var maxSeq = 0;
      if (rows is List && rows.isNotEmpty) {
        final last = (rows.first as Map)['purchase_no']?.toString() ?? '';
        if (last.startsWith(prefix)) {
          maxSeq = int.tryParse(last.substring(prefix.length)) ?? 0;
        }
      }
      return '$prefix${(maxSeq + 1).toString().padLeft(4, '0')}';
    } catch (e) {
      M7Log.error('DataService', 'nextReceiptNo', error: e);
      // Fallback: timestamp مَع pad
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      return 'REC-$year-${ts.substring(ts.length - 4)}';
    }
  }

  /// 🆕 تَعديل فاتورة استِلام مَوجودة. الـtrigger في DB يُعيد فَرق المَخزون.
  Future<bool> updateUniformPurchase(UniformPurchase p) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = {
        'purchase_date': p.purchaseDate.toIso8601String().substring(0, 10),
        if (p.invoiceNo != null) 'invoice_no': p.invoiceNo,
        'items': p.items.map((l) => l.toJson()).toList(),
        'notes': p.notes,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _c.from('uniform_purchases').update(payload).eq('id', p.id);
      // حَدِّث الكاش المَحَلِّيّ
      final idx = _repo.uniformPurchases.indexWhere((x) => x.id == p.id);
      if (idx >= 0) _repo.uniformPurchases[idx] = p;
      await syncUniformItems(); // الـtrigger عَدَّل uniform_items.quantity
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// 🆕 حَذف فاتورة استِلام. الـtrigger في DB يَخصِم كَمّيّاتها مِن المَخزون.
  Future<bool> deleteUniformPurchase(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('uniform_purchases').delete().eq('id', id);
      _repo.uniformPurchases.removeWhere((x) => x.id == id);
      await syncUniformItems();
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// 🆕 تَحديث بَيانات (data_json) لِنَموذَج مَوجود — يُستَخدَم عَنَدما يُعَدِّل
  /// المُوافِق على الطَلَب قَبل اعتِماده.
  Future<bool> updateFormSubmissionData(FormSubmission submission) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('form_submissions').update({
        'data_json': submission.data,
      }).eq('id', submission.id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // Helpers
  List<Map<String, dynamic>> _parseListMap(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Map<String, dynamic> _parseMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  // ============================================================
  // 🆕 موردو المغاسل (Laundry Suppliers)
  // ============================================================
  Future<List<LaundrySupplier>> loadLaundrySuppliers() async {
    if (!_supabase.isReady) return [];
    try {
      final rows = await _c.from('laundry_suppliers').select();
      final list = <LaundrySupplier>[];
      for (final r in (rows as List)) {
        list.add(LaundrySupplier(
          id: r['id'].toString(),
          nameAr: (r['name_ar'] ?? '').toString(),
          nameEn: (r['name_en'] ?? '').toString(),
          contactPerson: r['contact_person']?.toString(),
          contactPhone: r['contact_phone']?.toString(),
          notes: r['notes']?.toString(),
          countryId: r['country_id']?.toString(),
          isActive: r['is_active'] != false,
        ));
      }
      _repo.laundrySuppliers
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<LaundrySupplier?> upsertLaundrySupplier(LaundrySupplier sup) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = {
        'id': sup.id,
        'name_ar': sup.nameAr,
        'name_en': sup.nameEn,
        'contact_person': sup.contactPerson,
        'contact_phone': sup.contactPhone,
        'notes': sup.notes,
        'country_id': sup.countryId,
        'is_active': sup.isActive,
      };
      await _c.from('laundry_suppliers').upsert(payload);
      // sync local
      final i = _repo.laundrySuppliers.indexWhere((x) => x.id == sup.id);
      if (i == -1) {
        _repo.laundrySuppliers.add(sup);
      } else {
        _repo.laundrySuppliers[i] = sup;
      }
      _repo.notifyListeners();
      return sup;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> deleteLaundrySupplier(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('laundry_suppliers').delete().eq('id', id);
      _repo.laundrySuppliers.removeWhere((s) => s.id == id);
      _repo.notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ============================================================
  // 🆕 بنود المغسلة (Laundry Item Types) — قائمة مستقلّة
  // ============================================================
  Future<List<LaundryItemType>> loadLaundryItemTypes() async {
    if (!_supabase.isReady) {
      // وضع غير متصل: زرع البنود الافتراضية إن كانت فارغة
      _repo.seedDefaultLaundryItemTypes();
      return _repo.laundryItemTypes;
    }
    try {
      final rows = await _c
          .from('laundry_item_types')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final list = <LaundryItemType>[];
      for (final r in (rows as List)) {
        list.add(LaundryItemType(
          id: r['id'].toString(),
          nameAr: (r['name_ar'] ?? '').toString(),
          nameEn: (r['name_en'] ?? '').toString(),
          icon: r['icon']?.toString(),
          sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
          isActive: r['is_active'] == true,
        ));
      }
      _repo.laundryItemTypes
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      // fallback: بنود افتراضية
      _repo.seedDefaultLaundryItemTypes();
      return _repo.laundryItemTypes;
    }
  }

  // ============================================================
  // 🆕 نافذة وقت استلام الملابس
  // ============================================================
  Future<List<LaundryPickupWindow>> loadLaundryPickupWindows() async {
    if (!_supabase.isReady) return [];
    try {
      final rows = await _c.from('laundry_pickup_windows').select();
      final list = <LaundryPickupWindow>[];
      for (final r in (rows as List)) {
        final start = (r['start_time'] ?? '00:00:00').toString();
        final end = (r['end_time'] ?? '00:00:00').toString();
        final sParts = start.split(':');
        final eParts = end.split(':');
        list.add(LaundryPickupWindow(
          id: r['id'].toString(),
          countryId: r['country_id']?.toString(),
          startHour: int.tryParse(sParts.elementAt(0)) ?? 0,
          startMinute:
              sParts.length > 1 ? int.tryParse(sParts[1]) ?? 0 : 0,
          endHour: int.tryParse(eParts.elementAt(0)) ?? 0,
          endMinute: eParts.length > 1 ? int.tryParse(eParts[1]) ?? 0 : 0,
          message: r['message']?.toString(),
          updatedBy: r['updated_by']?.toString(),
          updatedAt: r['updated_at'] != null
              ? DateTime.tryParse(r['updated_at'].toString()) ??
                  DateTime.now()
              : DateTime.now(),
        ));
      }
      _repo.laundryPickupWindows
        ..clear()
        ..addAll(list);
      _repo.notifyListeners();
      return list;
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<LaundryPickupWindow?> upsertLaundryPickupWindow({
    required String? countryId,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    String? message,
    String? updatedBy,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      final start =
          '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}:00';
      final endT =
          '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';
      final payload = <String, dynamic>{
        'country_id': countryId,
        'start_time': start,
        'end_time': endT,
        'message': message,
        'updated_by': updatedBy,
        'updated_at': DateTime.now().toIso8601String(),
      };
      final res = await _c
          .from('laundry_pickup_windows')
          .upsert(payload, onConflict: 'country_id')
          .select()
          .single();
      final w = LaundryPickupWindow(
        id: res['id'].toString(),
        countryId: res['country_id']?.toString(),
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
        message: message,
        updatedBy: updatedBy,
      );
      _repo.upsertPickupWindow(w);
      lastError = null;
      return w;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> deleteLaundryTicket(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('laundry_tickets').delete().eq('id', id);
      _repo.laundryTickets.removeWhere((t) => t.id == id);
      _repo.notifyListeners();
      await AuditLogger.instance.log(
        entityType: 'laundry_ticket',
        entityId: id,
        action: AuditAction.delete,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteLaundryTicket', error: e);
      return false;
    }
  }

  // ==========================================================
  // Morning Checklists (قوائم الفحص الصباحي)
  // ==========================================================

  Future<void> syncMorningChecklists() async {
    try {
      final rows = await _c.from('morning_checklists').select();
      _repo.morningChecklists.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.morningChecklists.add(MorningChecklist(
          id: r['id'] as String,
          pointId: (r['site_id'] as String?) ?? '',
          supervisorId: (r['created_by'] as String?) ?? '',
          date: DateTime.parse(r['date'] as String),
          podium: ChecklistPhoto(
            kind: ChecklistPhotoKind.podium,
            fileId: r['podium_photo_url'] as String?,
          ),
          employees: ChecklistPhoto(
            kind: ChecklistPhotoKind.employees,
            fileId: r['employees_photo_url'] as String?,
          ),
          parking: ChecklistPhoto(
            kind: ChecklistPhotoKind.parking,
            fileId: r['parking_photo_url'] as String?,
          ),
          generalNotes: r['notes'] as String?,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncMorningChecklists', error: e);
    }
  }

  Future<MorningChecklist?> createMorningChecklist(
      MorningChecklist c) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'site_id': c.pointId,
        'date': c.date.toIso8601String().substring(0, 10),
        'created_by': c.supervisorId,
        if (c.generalNotes != null) 'notes': c.generalNotes,
        if (c.podium.fileId != null) 'podium_photo_url': c.podium.fileId,
        if (c.employees.fileId != null)
          'employees_photo_url': c.employees.fileId,
        if (c.parking.fileId != null) 'parking_photo_url': c.parking.fileId,
      };
      final r = await _c
          .from('morning_checklists')
          .insert(payload)
          .select()
          .single();
      final created = MorningChecklist(
        id: r['id'] as String,
        pointId: c.pointId,
        supervisorId: c.supervisorId,
        date: c.date,
        podium: c.podium,
        employees: c.employees,
        parking: c.parking,
        generalNotes: c.generalNotes,
      );
      _repo.morningChecklists.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'morning_checklist',
        entityId: created.id,
        entityLabel: created.dateKey,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createMorningChecklist', error: e);
      return null;
    }
  }

  // ==========================================================
  // Roles + Permissions (مزامنة من Supabase)
  // ==========================================================

  /// 🆕 إنشاء دور (يُستخدم تلقائياً عند إنشاء مسمى وظيفي)
  Future<RoleDef?> createRole({
    required String nameAr,
    required String nameEn,
    int priority = 10,
  }) async {
    if (!_supabase.isReady) return null;
    try {
      // اشتقاق key بسيط من الاسم الإنجليزي
      final key = nameEn
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final payload = {
        'key': key.isEmpty ? 'role_${DateTime.now().millisecondsSinceEpoch}' : key,
        'name_ar': nameAr,
        'name_en': nameEn,
        'priority': priority,
      };
      final r = await _c
          .from('roles')
          .insert(payload)
          .select()
          .single();
      final role = RoleDef(
        id: r['id'] as String,
        key: r['key'] as String,
        nameAr: nameAr,
        nameEn: nameEn,
        priority: priority,
      );
      _repo.roleDefs.add(role);
      _repo.notifyListeners();
      lastError = null;
      return role;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createRole', error: e);
      return null;
    }
  }

  Future<bool> updateRoleNames({
    required String roleId,
    required String nameAr,
    required String nameEn,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('roles').update({
        'name_ar': nameAr,
        'name_en': nameEn,
      }).eq('id', roleId);
      try {
        final r = _repo.roleDefs.firstWhere((x) => x.id == roleId);
        r.nameAr = nameAr;
        r.nameEn = nameEn;
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateRoleNames', error: e);
      return false;
    }
  }

  Future<bool> deleteRole(String roleId) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('roles').delete().eq('id', roleId);
      _repo.roleDefs.removeWhere((r) => r.id == roleId);
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteRole', error: e);
      return false;
    }
  }

  /// مزامنة الأدوار من Supabase (تستبدل الـ seed المحلي)
  Future<void> syncRoles() async {
    try {
      final rows = await _c.from('roles').select();
      _repo.roleDefs.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.roleDefs.add(RoleDef(
          id: r['id'] as String,
          key: r['key'] as String,
          nameAr: r['name_ar'] as String,
          nameEn: r['name_en'] as String,
          priority: (r['priority'] as num?)?.toInt() ?? 0,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncRoles', error: e);
    }
  }

  /// مزامنة الصلاحيات من Supabase
  Future<void> syncPermissions() async {
    try {
      final rows = await _c.from('permissions').select();
      _repo.permissionDefs.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.permissionDefs.add(PermissionDef(
          id: r['id'] as String,
          key: r['key'] as String,
          nameAr: (r['name_ar'] as String?) ?? '',
          nameEn: (r['name_en'] as String?) ?? '',
          module: (r['module'] as String?) ?? 'general',
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncPermissions', error: e);
    }
  }

  /// 🆕 رفع الصلاحيّات الجديدة من الـ seed المحلّي إلى Supabase.
  ///
  /// يُقارن قائمة الصلاحيّات في `seed_permissions` المُولَّدة من
  /// `seedRbac()` مع جدول `permissions` على السيرفر، وأيّ مفتاح مفقود
  /// يُدرَج. لا يُحدّث الموجود أو يحذف شيئاً.
  ///
  /// يُرجِع `(added, skipped)` — كم مفتاحاً تمّ إدراجه وكم تمّ تخطّيه
  /// لأنّه موجود مسبقاً.
  Future<({int added, int skipped, String? error})>
      pushSeedPermissionsToSupabase() async {
    try {
      // 1) اقرأ المفاتيح الموجودة حاليّاً على السيرفر
      final existing = await _c.from('permissions').select('key');
      final existingKeys = <String>{
        for (final r in (existing as List).cast<Map<String, dynamic>>())
          r['key'] as String
      };

      // 2) ولّد الصلاحيّات من seedRbac() — هي المصدر الموثوق
      // ملاحظة: لا نستخدم `_repo.permissionDefs` لأنّ syncPermissions
      // يكون قد محاها واستبدلها بما هو في Supabase.
      final localCountryIds =
          _repo.countries.map((c) => c.id).toList();
      final seed = seedRbac(
        () => 'tmp', // الـ id لن يُستخدم لأنّ Supabase سيولّد UUIDs
        countryIds: localCountryIds,
      );

      // 3) ابنِ قائمة الإضافات
      final toInsert = <Map<String, dynamic>>[];
      for (final p in seed.permissions) {
        if (existingKeys.contains(p.key)) continue;
        toInsert.add({
          'key': p.key,
          'module': p.module,
          'name_ar': p.nameAr,
          'name_en': p.nameEn,
        });
      }

      if (toInsert.isEmpty) {
        return (added: 0, skipped: existingKeys.length, error: null);
      }

      // 4) نفّذ INSERT — Supabase يولّد id تلقائيّاً (DEFAULT gen_random_uuid())
      await _c.from('permissions').insert(toInsert);

      // 5) أعِد المزامنة لتصل إلى الذاكرة المحليّة
      await syncPermissions();

      return (
        added: toInsert.length,
        skipped: existingKeys.length,
        error: null,
      );
    } catch (e, st) {
      M7Log.error('DataService', 'pushSeedPermissionsToSupabase',
          error: e, stack: st);
      return (added: 0, skipped: 0, error: e.toString());
    }
  }

  /// مزامنة ربط الأدوار بالصلاحيات
  Future<void> syncRolePermissions() async {
    try {
      final rows = await _c.from('role_permissions').select();
      _repo.rolePermissions.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.rolePermissions.add(RolePermissionLink(
          roleId: r['role_id'] as String,
          permissionId: r['permission_id'] as String,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncRolePermissions', error: e);
    }
  }

  // ==========================================================
  // Evaluations (تقييمات الغرف + الموظفين + السائقين)
  // ==========================================================

  Future<void> syncRoomEvaluations() async {
    try {
      final rows = await _c.from('room_evaluations').select();
      _repo.roomEvaluations.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.roomEvaluations.add(RoomEvaluation(
          id: r['id'] as String,
          roomId: r['room_id'] as String,
          evaluatedBy: (r['evaluated_by'] as String?) ?? '',
          cleanRating: (r['clean_rating'] as num).toInt(),
          orderRating: (r['order_rating'] as num).toInt(),
          notes: r['notes'] as String?,
          date: DateTime.parse(r['date'] as String),
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncRoomEvaluations', error: e);
    }
  }

  Future<RoomEvaluation?> createRoomEvaluation(RoomEvaluation e) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = {
        'room_id': e.roomId,
        'evaluated_by': e.evaluatedBy.isEmpty ? null : e.evaluatedBy,
        'clean_rating': e.cleanRating,
        'order_rating': e.orderRating,
        if (e.notes != null) 'notes': e.notes,
        'date': e.date.toIso8601String(),
      };
      final r = await _c
          .from('room_evaluations')
          .insert(payload)
          .select()
          .single();
      final created = RoomEvaluation(
        id: r['id'] as String,
        roomId: e.roomId,
        evaluatedBy: e.evaluatedBy,
        cleanRating: e.cleanRating,
        orderRating: e.orderRating,
        notes: e.notes,
        date: e.date,
      );
      _repo.roomEvaluations.add(created);
      // حدّث Room.cleanRating + orderRating بآخر قيمة
      try {
        final room = _repo.rooms.firstWhere((rm) => rm.id == e.roomId);
        room.cleanRating = e.cleanRating;
        room.orderRating = e.orderRating;
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'room_evaluation',
        entityId: created.id,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (ex) {
      lastError = ex.toString();
      M7Log.error('DataService', 'createRoomEvaluation', error: ex);
      return null;
    }
  }

  Future<void> syncEmployeeEvaluations() async {
    try {
      final rows = await _c.from('employee_evaluations').select();
      _repo.employeeEvaluations.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final subRaw = r['sub_ratings'];
        final subMap = <String, int>{};
        if (subRaw is Map) {
          for (final entry in subRaw.entries) {
            if (entry.value is num) {
              subMap[entry.key.toString()] = (entry.value as num).toInt();
            }
          }
        }
        _repo.employeeEvaluations.add(EmployeeEvaluation(
          id: r['id'] as String,
          employeeId: r['employee_id'] as String,
          evaluatedBy: (r['evaluated_by'] as String?) ?? '',
          siteId: r['site_id'] as String?,
          rating: (r['rating'] as num).toInt(),
          notes: r['notes'] as String?,
          date: DateTime.parse(r['date'] as String),
          subRatings: subMap,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncEmployeeEvaluations', error: e);
    }
  }

  Future<EmployeeEvaluation?> createEmployeeEvaluation(
      EmployeeEvaluation e) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'employee_id': e.employeeId,
        'evaluated_by': e.evaluatedBy.isEmpty ? null : e.evaluatedBy,
        if (e.siteId != null) 'site_id': e.siteId,
        'rating': e.rating,
        'sub_ratings': e.subRatings,
        if (e.notes != null) 'notes': e.notes,
        'date': e.date.toIso8601String(),
      };
      final r = await _c
          .from('employee_evaluations')
          .insert(payload)
          .select()
          .single();
      final created = EmployeeEvaluation(
        id: r['id'] as String,
        employeeId: e.employeeId,
        evaluatedBy: e.evaluatedBy,
        siteId: e.siteId,
        rating: e.rating,
        notes: e.notes,
        date: e.date,
        subRatings: e.subRatings,
      );
      _repo.employeeEvaluations.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_evaluation',
        entityId: created.id,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (ex) {
      lastError = ex.toString();
      M7Log.error('DataService', 'createEmployeeEvaluation', error: ex);
      return null;
    }
  }

  Future<void> syncDriverEvaluations() async {
    try {
      final rows = await _c.from('driver_evaluations').select();
      _repo.driverEvaluations.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.driverEvaluations.add(DriverEvaluation(
          id: r['id'] as String,
          driverId: r['driver_id'] as String,
          busId: r['bus_id'] as String?,
          evaluatedBy: (r['evaluated_by'] as String?) ?? '',
          rating: (r['rating'] as num).toInt(),
          notes: r['notes'] as String?,
          date: DateTime.parse(r['date'] as String),
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncDriverEvaluations', error: e);
    }
  }

  Future<DriverEvaluation?> createDriverEvaluation(
      DriverEvaluation e) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'driver_id': e.driverId,
        if (e.busId != null) 'bus_id': e.busId,
        'evaluated_by': e.evaluatedBy.isEmpty ? null : e.evaluatedBy,
        'rating': e.rating,
        if (e.notes != null) 'notes': e.notes,
        'date': e.date.toIso8601String(),
      };
      final r = await _c
          .from('driver_evaluations')
          .insert(payload)
          .select()
          .single();
      final created = DriverEvaluation(
        id: r['id'] as String,
        driverId: e.driverId,
        busId: e.busId,
        evaluatedBy: e.evaluatedBy,
        rating: e.rating,
        notes: e.notes,
        date: e.date,
      );
      _repo.driverEvaluations.add(created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'driver_evaluation',
        entityId: created.id,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (ex) {
      lastError = ex.toString();
      M7Log.error('DataService', 'createDriverEvaluation', error: ex);
      return null;
    }
  }

  // ==========================================================
  // Role Permissions (إدارة صلاحيات الأدوار)
  // ==========================================================

  /// استبدال كل صلاحيات الدور بقائمة جديدة
  Future<bool> setRolePermissions(
    String roleId,
    List<String> permissionIds,
  ) async {
    if (!_supabase.isReady) return false;
    try {
      // التقط القديم
      List<String>? before;
      try {
        before = _repo.rolePermissions
            .where((rp) => rp.roleId == roleId)
            .map((rp) => rp.permissionId)
            .toList();
      } catch (_) {}
      // احذف القديم
      await _c.from('role_permissions').delete().eq('role_id', roleId);
      // أضف الجديد
      if (permissionIds.isNotEmpty) {
        await _c.from('role_permissions').insert(
              permissionIds
                  .map((pid) =>
                      {'role_id': roleId, 'permission_id': pid})
                  .toList(),
            );
      }
      // حدّث الذاكرة
      try {
        _repo.setRolePermissions(roleId, permissionIds, '');
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      // Audit
      String? roleLabel;
      try {
        roleLabel = _repo.roleDefs.firstWhere((r) => r.id == roleId).nameAr;
      } catch (_) {}
      await AuditLogger.instance.log(
        entityType: 'role_permissions',
        entityId: roleId,
        entityLabel: roleLabel,
        action: AuditAction.update,
        before: {'permission_ids': before},
        after: {'permission_ids': permissionIds},
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'setRolePermissions', error: e);
      return false;
    }
  }

  /// تحديث قائمة فحص (الصور والملاحظات)
  Future<bool> updateMorningChecklist(MorningChecklist c) async {
    if (!_supabase.isReady) return false;
    try {
      final payload = <String, dynamic>{
        'podium_photo_url': c.podium.fileId,
        'employees_photo_url': c.employees.fileId,
        'parking_photo_url': c.parking.fileId,
        'notes': c.generalNotes,
      };
      await _c.from('morning_checklists').update(payload).eq('id', c.id);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'morning_checklist',
        entityId: c.id,
        entityLabel: c.dateKey,
        action: AuditAction.update,
        after: payload,
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateMorningChecklist', error: e);
      return false;
    }
  }

  // ==========================================================
  // 🆕 إدارة اليونيفورم - Catalog / Receipts / Issues
  // ==========================================================

  // ===== كتالوج اليونيفورم =====
  Future<void> syncUniformItems() async {
    try {
      final rows = await _c.from('uniform_items').select();
      _repo.uniformCatalog.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.uniformCatalog.add(UniformItem(
          id: r['id'] as String,
          nameAr: (r['name_ar'] as String?) ?? '',
          nameEn: (r['name_en'] as String?) ?? '',
          size: (r['size'] as String?) ?? '',
          color: (r['color'] as String?) ?? '',
          // 🆕 قِراءة الكَمّيّة من DB (يَتِمّ تَحديثها تِلقائيّاً عَبر triggers)
          quantity: (r['quantity'] as num?)?.toInt() ?? 0,
          price: (r['price'] as num?)?.toDouble() ?? 0,
          minStock: (r['min_stock'] as num?)?.toInt() ?? 5,
          countryId: r['country_id'] as String?,
          status: ((r['status'] as String?) ?? 'active') == 'active'
              ? EntityStatus.active
              : EntityStatus.inactive,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncUniformItems', error: e);
    }
  }

  Future<UniformItem?> createUniformItem(
      UniformItem u, {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'name_ar': u.nameAr,
        'name_en': u.nameEn,
        if (u.size.isNotEmpty) 'size': u.size,
        if (u.color.isNotEmpty) 'color': u.color,
        // 🆕 الكَمّيّة الافتِتاحيّة — تَنتَقِل لِـDB
        'quantity': u.quantity,
        'price': u.price,
        'min_stock': u.minStock,
        'status': u.status == EntityStatus.active ? 'active' : 'inactive',
        if (countryId != null) 'country_id': countryId,
      };
      final r = await _c
          .from('uniform_items')
          .insert(payload)
          .select()
          .single();
      final created = UniformItem(
        id: r['id'] as String,
        nameAr: u.nameAr,
        nameEn: u.nameEn,
        size: u.size,
        color: u.color,
        // 🆕 احفَظ الـquantity في الـmodel أَيضاً
        quantity: u.quantity,
        price: u.price,
        minStock: u.minStock,
        countryId: countryId,
        status: u.status,
      );
      _repo.uniformCatalog.add(created);
      _repo.notifyListeners();
      lastError = null;
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createUniformItem', error: e);
      return null;
    }
  }

  Future<bool> updateUniformItem(UniformItem u) async {
    if (!_supabase.isReady) return false;
    try {
      // ⚠️ مُهِمّ: لا نَكتُب `quantity` أَبَداً — تُديره triggers DB فَقَط
      // (عَنَدَ INSERT/UPDATE/DELETE لِفاتورة الاستِلام أَو الصَرف أَو الإرجاع)
      await _c.from('uniform_items').update({
        'name_ar': u.nameAr,
        'name_en': u.nameEn,
        'size': u.size,
        'color': u.color,
        'price': u.price,
        'min_stock': u.minStock,
        'status': u.status == EntityStatus.active ? 'active' : 'inactive',
      }).eq('id', u.id);
      // حَدِّث الـcache المَحَلِّيّ أَيضاً
      final i = _repo.uniformCatalog.indexWhere((x) => x.id == u.id);
      if (i != -1) _repo.uniformCatalog[i] = u;
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'updateUniformItem', error: e);
      return false;
    }
  }

  Future<bool> deleteUniformItem(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('uniform_items').delete().eq('id', id);
      _repo.uniformCatalog.removeWhere((u) => u.id == id);
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteUniformItem', error: e);
      return false;
    }
  }

  // ===== إيصالات استلام المخزون =====
  Future<void> syncUniformReceipts() async {
    try {
      final rows = await _c
          .from('uniform_receipts')
          .select()
          .order('date', ascending: false);
      _repo.uniformReceipts.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.uniformReceipts.add(UniformReceipt(
          id: r['id'] as String,
          receiptNo: (r['receipt_no'] as String?) ?? '',
          date: r['date'] == null
              ? null
              : DateTime.tryParse(r['date'] as String),
          uniformItemId: r['uniform_item_id'] as String,
          quantity: (r['quantity'] as num).toInt(),
          supplier: r['supplier'] as String?,
          receivedById: r['received_by'] as String?,
          receivedByName: r['received_by_name'] as String?,
          countryId: r['country_id'] as String?,
          notes: r['notes'] as String?,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncUniformReceipts', error: e);
    }
  }

  Future<UniformReceipt?> createUniformReceipt(UniformReceipt r,
      {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'receipt_no': r.receiptNo,
        'date': r.date.toIso8601String(),
        'uniform_item_id': r.uniformItemId,
        'quantity': r.quantity,
        if (r.supplier != null) 'supplier': r.supplier,
        if (r.receivedById != null) 'received_by': r.receivedById,
        if (r.receivedByName != null)
          'received_by_name': r.receivedByName,
        if (r.notes != null) 'notes': r.notes,
        if (countryId != null) 'country_id': countryId,
      };
      final res = await _c
          .from('uniform_receipts')
          .insert(payload)
          .select()
          .single();
      final created = UniformReceipt(
        id: res['id'] as String,
        receiptNo: r.receiptNo,
        date: r.date,
        uniformItemId: r.uniformItemId,
        quantity: r.quantity,
        supplier: r.supplier,
        receivedById: r.receivedById,
        receivedByName: r.receivedByName,
        countryId: countryId,
        notes: r.notes,
      );
      _repo.uniformReceipts.insert(0, created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'uniform_receipt',
        entityId: created.id,
        entityLabel: created.receiptNo,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createUniformReceipt', error: e);
      return null;
    }
  }

  Future<bool> deleteUniformReceipt(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('uniform_receipts').delete().eq('id', id);
      _repo.uniformReceipts.removeWhere((r) => r.id == id);
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteUniformReceipt', error: e);
      return false;
    }
  }

  // ===== صرف اليونيفورم للموظفين =====
  Future<void> syncEmployeeUniforms() async {
    try {
      final rows = await _c
          .from('employee_uniforms')
          .select()
          .order('issue_date', ascending: false);
      _repo.employeeUniforms.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _repo.employeeUniforms.add(EmployeeUniform(
          id: r['id'] as String,
          issueNo: (r['issue_no'] as String?) ?? '',
          employeeId: r['employee_id'] as String,
          // العَمود في DB اسمه item_id — مَع fallback لِـuniform_item_id (legacy)
          uniformItemId: (r['item_id'] ?? r['uniform_item_id']) as String,
          quantity: (r['quantity'] as num).toInt(),
          size: (r['size'] as String?) ?? '',
          issueDate: r['issue_date'] == null
              ? null
              : DateTime.tryParse(r['issue_date'] as String),
          returnDate: r['return_date'] == null
              ? null
              : DateTime.tryParse(r['return_date'] as String),
          returnQuantity: (r['return_quantity'] as num?)?.toInt(),
          issuedById: r['issued_by'] as String?,
          issuedByName: r['issued_by_name'] as String?,
          returnedById: r['returned_by'] as String?,
          returnedByName: r['returned_by_name'] as String?,
          countryId: r['country_id'] as String?,
          notes: r['notes'] as String?,
          // 🆕 المَرحَلة 2
          signatureData: r['signature_data'] as String?,
          signedAt: r['signed_at'] == null
              ? null
              : DateTime.tryParse(r['signed_at'] as String),
          sourceFormSubmissionId:
              r['source_form_submission_id'] as String?,
          totalValue: (r['total_value'] as num?)?.toDouble() ?? 0,
        ));
      }
      _repo.notifyListeners();
    } catch (e) {
      M7Log.error('DataService', 'syncEmployeeUniforms', error: e);
    }
  }

  Future<EmployeeUniform?> createEmployeeUniform(EmployeeUniform u,
      {String? countryId}) async {
    if (!_supabase.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'issue_no': u.issueNo,
        'employee_id': u.employeeId,
        // العَمود في DB اسمه item_id (وَلَيس uniform_item_id)
        'item_id': u.uniformItemId,
        'quantity': u.quantity,
        if (u.size.isNotEmpty) 'size': u.size,
        'issue_date': u.issueDate.toIso8601String(),
        if (u.issuedById != null) 'issued_by': u.issuedById,
        if (u.issuedByName != null) 'issued_by_name': u.issuedByName,
        if (u.notes != null) 'notes': u.notes,
        if (countryId != null) 'country_id': countryId,
        // 🆕 المَرحَلة 2
        if (u.signatureData != null) 'signature_data': u.signatureData,
        if (u.signedAt != null) 'signed_at': u.signedAt!.toIso8601String(),
        if (u.sourceFormSubmissionId != null)
          'source_form_submission_id': u.sourceFormSubmissionId,
      };
      final res = await _c
          .from('employee_uniforms')
          .insert(payload)
          .select()
          .single();
      final created = EmployeeUniform(
        id: res['id'] as String,
        issueNo: u.issueNo,
        employeeId: u.employeeId,
        uniformItemId: u.uniformItemId,
        quantity: u.quantity,
        size: u.size,
        issueDate: u.issueDate,
        issuedById: u.issuedById,
        issuedByName: u.issuedByName,
        countryId: countryId,
        notes: u.notes,
      );
      _repo.employeeUniforms.insert(0, created);
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_uniform',
        entityId: created.id,
        entityLabel: created.issueNo,
        action: AuditAction.create,
        after: payload,
      );
      return created;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'createEmployeeUniform', error: e);
      return null;
    }
  }

  /// إرجاع كمية من يونيفورم تم صرفه
  Future<bool> returnEmployeeUniform({
    required String id,
    required int returnQuantity,
    String? returnedById,
    String? returnedByName,
  }) async {
    if (!_supabase.isReady) return false;
    try {
      final now = DateTime.now().toIso8601String();
      await _c.from('employee_uniforms').update({
        'return_date': now,
        'return_quantity': returnQuantity,
        if (returnedById != null) 'returned_by': returnedById,
        if (returnedByName != null) 'returned_by_name': returnedByName,
      }).eq('id', id);
      try {
        final eu = _repo.employeeUniforms.firstWhere((x) => x.id == id);
        eu.returnDate = DateTime.now();
        eu.returnQuantity = returnQuantity;
        eu.returnedById = returnedById;
        eu.returnedByName = returnedByName;
      } catch (_) {}
      _repo.notifyListeners();
      lastError = null;
      await AuditLogger.instance.log(
        entityType: 'employee_uniform',
        entityId: id,
        action: AuditAction.update,
        after: {'return_quantity': returnQuantity},
        description: 'إرجاع يونيفورم',
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'returnEmployeeUniform', error: e);
      return false;
    }
  }

  Future<bool> deleteEmployeeUniform(String id) async {
    if (!_supabase.isReady) return false;
    try {
      await _c.from('employee_uniforms').delete().eq('id', id);
      _repo.employeeUniforms.removeWhere((u) => u.id == id);
      _repo.notifyListeners();
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('DataService', 'deleteEmployeeUniform', error: e);
      return false;
    }
  }
}
