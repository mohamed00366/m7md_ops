import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'job_title_profile_screen.dart';

/// 🧩 شاشة المصفوفة الجماعيّة للصلاحيّات (Bulk Permissions Matrix)
///
/// تعرض كل المسمّيات الوظيفيّة (Rows) × كل الصلاحيّات (Cols) في شبكة واحدة:
///   - مرّر أفقياً لرؤية كل الصلاحيّات
///   - مرّر عموديّاً لرؤية كل المسمّيات
///   - انقر على خليّة لتبديل صلاحيّة لمسمّى
///   - انقر على رأس عمود لتطبيق صلاحيّة على **كل المسمّيات**
///   - انقر على رأس صف لرؤية ملخّص ذلك المسمّى
///
/// المميّزات الذكيّة:
///   - فلتر بالموديول (employees / camp / buses ...)
///   - فلتر «أظهر فقط الفجوات» (مسمّيات ينقصها صلاحيّات أساسيّة)
///   - فلتر بنوع لوحة التحكم (manager / supervisor / employee ...)
///   - حفظ جماعي بنقرة واحدة (يحفظ كل التغييرات في كل المسمّيات)
class BulkPermissionsMatrixScreen extends StatefulWidget {
  const BulkPermissionsMatrixScreen({super.key});

  @override
  State<BulkPermissionsMatrixScreen> createState() =>
      _BulkPermissionsMatrixScreenState();
}

class _BulkPermissionsMatrixScreenState
    extends State<BulkPermissionsMatrixScreen> {
  /// خرائط داخليّة: jobTitleId → Set<permissionKey>
  /// كلّ تغيير ينعكس هنا أوّلاً، ثم يُحفظ دفعة واحدة عند الضغط على Save
  final Map<String, Set<String>> _matrix = {};
  final Set<String> _dirtyJobTitleIds = {};
  String? _moduleFilter;
  String? _domainFilter; // 🆕 فِلتَر فِئة عُليا (org/hr/roster/etc.)
  DashboardType? _dashboardFilter;
  String _search = '';
  bool _onlyGaps = false;
  bool _saving = false;

  // 🆕 خَريطة المُوديولات إلى فِئات domain (لِلتَنظيم البَصَريّ)
  // كُلّ سَطر: module name → (domain key, domain label ar/en, icon)
  static const Map<String, _Domain> _moduleDomains = {
    // 🏢 Organization
    'departments':    _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'job_titles':     _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'customers':      _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'sites':          _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'org':            _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'site_onboarding':_Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    'countries':      _Domain('org', '🏢 المُؤَسَّسة', '🏢 Organization'),
    // 👥 HR
    'employees':      _Domain('hr', '👥 HR', '👥 HR'),
    'employee':       _Domain('hr', '👥 HR', '👥 HR'),
    'documents':      _Domain('hr', '👥 HR', '👥 HR'),
    'employee_documents': _Domain('hr', '👥 HR', '👥 HR'),
    'evaluations':    _Domain('hr', '👥 HR', '👥 HR'),
    'evaluation_criteria': _Domain('hr', '👥 HR', '👥 HR'),
    'training':       _Domain('hr', '👥 HR', '👥 HR'),
    'attendance':     _Domain('hr', '👥 HR', '👥 HR'),
    'leaves':         _Domain('hr', '👥 HR', '👥 HR'),
    'deductions':     _Domain('hr', '👥 HR', '👥 HR'),
    'entitlements':   _Domain('hr', '👥 HR', '👥 HR'),
    'hr':             _Domain('hr', '👥 HR', '👥 HR'),
    // 📅 Rosters
    'rosters':        _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    'roster_creator': _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    'rosters_center': _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    'roster_approvals': _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    'approved_roster': _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    'my_roster':      _Domain('roster', '📅 الرواتِر', '📅 Rosters'),
    // 🚌 Transport
    'buses':          _Domain('transport', '🚌 النَقل', '🚌 Transport'),
    'drivers':        _Domain('transport', '🚌 النَقل', '🚌 Transport'),
    'tracking':       _Domain('transport', '🚌 النَقل', '🚌 Transport'),
    'fleet':          _Domain('transport', '🚌 النَقل', '🚌 Transport'),
    'gps_devices':    _Domain('transport', '🚌 النَقل', '🚌 Transport'),
    // 🏕 Camp
    'camp_rooms':     _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_uniform':   _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_buses':     _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_violations':_Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_laundry':   _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_amana':     _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'camp_inventory': _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'uniform_catalog':_Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'uniform_issue':  _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'uniform_requests': _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'uniform_reports': _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'uniform_purchases': _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    'laundry':        _Domain('camp', '🏕 الكَمب', '🏕 Camp'),
    // 📋 Forms & Workflows
    'forms':          _Domain('forms', '📋 النَماذِج', '📋 Forms'),
    'workflows':      _Domain('forms', '📋 النَماذِج', '📋 Forms'),
    'form_approvals': _Domain('forms', '📋 النَماذِج', '📋 Forms'),
    // 📊 Reports
    'reports':        _Domain('reports', '📊 التَقارير', '📊 Reports'),
    'dashboard':      _Domain('reports', '📊 التَقارير', '📊 Reports'),
    // 🔔 Notifications
    'notifications':  _Domain('notif', '🔔 الإشعارات', '🔔 Notifications'),
    // 🔐 Security
    'face':           _Domain('security', '🔐 الأَمان', '🔐 Security'),
    'device_sessions':_Domain('security', '🔐 الأَمان', '🔐 Security'),
    'geo_fence':      _Domain('security', '🔐 الأَمان', '🔐 Security'),
    'login_method':   _Domain('security', '🔐 الأَمان', '🔐 Security'),
    'pin':            _Domain('security', '🔐 الأَمان', '🔐 Security'),
    'audit':          _Domain('security', '🔐 الأَمان', '🔐 Security'),
    'point_terminal': _Domain('security', '🔐 الأَمان', '🔐 Security'),
    // ⚙ Admin / System
    'admin':          _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'users':          _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'roles':          _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'settings':       _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'system':         _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'policies':       _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'company_events': _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
    'tasks':          _Domain('admin', '⚙ الإدارة', '⚙ Admin'),
  };

  _Domain _domainOf(String module) =>
      _moduleDomains[module] ??
      const _Domain('other', '📦 أُخرى', '📦 Other');

  @override
  void initState() {
    super.initState();
    _loadInitial();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _loadInitial() {
    final repo = MockRepository();
    _matrix.clear();
    for (final jt in repo.jobTitles) {
      if (jt.roleId == null) {
        _matrix[jt.id] = <String>{};
      } else {
        _matrix[jt.id] = repo.permissionKeysForRole(jt.roleId!);
      }
    }
  }

  /// ✅ تبديل صلاحيّة لمسمّى — يضع التغيير في الذاكرة فقط
  void _toggle(String jobTitleId, String permKey) {
    setState(() {
      final set = _matrix[jobTitleId] ??= <String>{};
      if (set.contains(permKey)) {
        set.remove(permKey);
      } else {
        set.add(permKey);
      }
      _dirtyJobTitleIds.add(jobTitleId);
    });
  }

  /// ✅ تبديل صلاحيّة لكلّ المسمّيات (column-wide)
  void _toggleColumn(String permKey, List<JobTitle> visibleRows) {
    final allHave = visibleRows.every((jt) =>
        (_matrix[jt.id] ?? const <String>{}).contains(permKey));
    setState(() {
      for (final jt in visibleRows) {
        final set = _matrix[jt.id] ??= <String>{};
        if (allHave) {
          set.remove(permKey);
        } else {
          set.add(permKey);
        }
        _dirtyJobTitleIds.add(jt.id);
      }
    });
  }

  /// ✅ حفظ جماعي
  Future<void> _saveAll() async {
    if (_dirtyJobTitleIds.isEmpty) return;
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
    setState(() => _saving = true);

    var savedCount = 0;
    for (final jtId in _dirtyJobTitleIds) {
      final jt = repo.jobTitleById(jtId);
      if (jt == null) continue;
      String? roleId = jt.roleId;
      // إنشاء دور تلقائياً إن لم يوجد
      if (roleId == null) {
        if (supaReady) {
          final r = await ds.createRole(
              nameAr: jt.nameAr, nameEn: jt.nameEn, priority: 10);
          roleId = r?.id;
        } else {
          final newId = repo.generateId();
          repo.roleDefs.add(RoleDef(
            id: newId,
            key: jt.nameEn
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
            nameAr: jt.nameAr,
            nameEn: jt.nameEn,
            priority: 10,
          ));
          roleId = newId;
        }
        if (roleId == null) continue;
        jt.roleId = roleId;
        if (supaReady) {
          try {
            await ds.client
                .from('job_titles')
                .update({'role_id': roleId}).eq('id', jt.id);
          } catch (_) {}
        }
      }
      final keys = _matrix[jtId] ?? <String>{};
      if (supaReady) {
        final ids = repo.permissionDefs
            .where((p) => keys.contains(p.key))
            .map((p) => p.id)
            .toList();
        await ds.setRolePermissions(roleId, ids);
      }
      repo.setRolePermissionsByKeys(roleId, keys, '');
      savedCount++;
    }

    // 🆕 تَحديث صَلاحيّات المُستَخدِم الحاليّ فَوريّاً (لَو كان دَوره ضِمن المُغَيَّر)
    if (mounted) {
      try {
        await context.read<AuthProvider>().refreshPermissions();
      } catch (_) {/* غَير حاسِم */}
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _dirtyJobTitleIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade600,
        content: Text(s.isAr
            ? 'تم حفظ $savedCount مسمّى'
            : 'Saved $savedCount job titles'),
      ));
    }
  }

  /// ✅ كشف فجوات: مسمّيات ينقصها صلاحيّات لوحة التحكم الخاصّة بها
  /// مثال: مسمّى dashboard=supervisor لكن لا يملك أيّ صلاحية ضمن دور المشرف
  bool _hasGaps(JobTitle jt) {
    final keys = _matrix[jt.id] ?? const <String>{};
    if (keys.isEmpty) return true;
    // قاعدة بسيطة: لو كان مدير وعدد الصلاحيّات أقل من 5 → فجوة
    if (jt.dashboardType == DashboardType.manager && keys.length < 5) {
      return true;
    }
    if (jt.dashboardType == DashboardType.supervisor && keys.length < 3) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isAr = s.isAr;

    // الصفوف (المسمّيات) بعد الفلاتر
    var rows = repo.jobTitles.toList();
    if (_dashboardFilter != null) {
      rows = rows.where((j) => j.dashboardType == _dashboardFilter).toList();
    }
    if (_onlyGaps) {
      rows = rows.where(_hasGaps).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      rows = rows
          .where((j) =>
              j.nameAr.toLowerCase().contains(q) ||
              j.nameEn.toLowerCase().contains(q))
          .toList();
    }
    rows.sort((a, b) {
      final lc = a.level.compareTo(b.level);
      if (lc != 0) return lc;
      return a.nameAr.compareTo(b.nameAr);
    });

    // الأعمدة (الصلاحيّات) بعد الفلاتر
    var cols = repo.permissionDefs.toList();
    // 🆕 فِلتَر domain أَوَّلاً (أَوسَع), ثُمَّ module
    if (_domainFilter != null) {
      cols = cols.where((p) => _domainOf(p.module).key == _domainFilter).toList();
    }
    if (_moduleFilter != null) {
      cols = cols.where((p) => p.module == _moduleFilter).toList();
    }
    cols.sort((a, b) {
      final mc = a.module.compareTo(b.module);
      if (mc != 0) return mc;
      return a.key.compareTo(b.key);
    });

    final modules =
        repo.permissionDefs.map((p) => p.module).toSet().toList()..sort();

    // 🆕 المُوديولات المَرئيّة حَسَب الـdomain المُختار (لِفِلتَر الـchips الثاني)
    final visibleModules = _domainFilter == null
        ? modules
        : modules.where((m) => _domainOf(m).key == _domainFilter).toList();

    // 🆕 قائِمة الـdomains الفَريدة (لِشَريط الفِلتَر العُلويّ)
    final domains = <String, _Domain>{};
    for (final m in modules) {
      final d = _domainOf(m);
      domains[d.key] = d;
    }
    final domainList = domains.values.toList();
    domainList.sort((a, b) => _domainOrder(a.key).compareTo(_domainOrder(b.key)));

    return Column(
      children: [
        // ===== Top toolbar =====
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: isAr
                            ? '🔍 بحث في المسمّيات...'
                            : '🔍 Search job titles...',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dirtyJobTitleIds.isNotEmpty
                          ? AppColors.success
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (_dirtyJobTitleIds.isEmpty || _saving)
                        ? null
                        : _saveAll,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 14),
                    label: Text(
                      isAr
                          ? 'حفظ (${_dirtyJobTitleIds.length})'
                          : 'Save (${_dirtyJobTitleIds.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              // 🆕 شَريط فِلتَر الـDomain (أَوسَع — يَجمَع عِدّة مُوديولات)
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: isAr ? 'كُلّ الأَقسام' : 'All sections',
                      selected: _domainFilter == null,
                      onTap: () => setState(() {
                        _domainFilter = null;
                        _moduleFilter = null;
                      }),
                    ),
                    for (final d in domainList) ...[
                      const SizedBox(width: 4),
                      _filterChip(
                        label: isAr ? d.labelAr : d.labelEn,
                        selected: _domainFilter == d.key,
                        onTap: () => setState(() {
                          _domainFilter = _domainFilter == d.key ? null : d.key;
                          _moduleFilter = null; // أَعِد ضَبط الفِلتَر الفَرعيّ
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              // 🆕 شَريط فِلتَر الـModule (تَفاصيل ضِمن الـdomain)
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: isAr ? 'كل الموديولات' : 'All modules',
                      selected: _moduleFilter == null,
                      onTap: () => setState(() => _moduleFilter = null),
                    ),
                    for (final m in visibleModules) ...[
                      const SizedBox(width: 4),
                      _filterChip(
                        label: m,
                        selected: _moduleFilter == m,
                        onTap: () => setState(() => _moduleFilter = m),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 22,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(width: 12),
                    _toggleChip(
                      icon: Icons.warning_amber_outlined,
                      label: isAr ? 'الفجوات فقط' : 'Gaps only',
                      selected: _onlyGaps,
                      color: AppColors.danger,
                      onTap: () => setState(() => _onlyGaps = !_onlyGaps),
                    ),
                    const SizedBox(width: 6),
                    _dashboardFilterChip(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ===== Stats bar =====
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.grey[100],
          child: Row(
            children: [
              Text(
                isAr
                    ? '${rows.length} مسمّى × ${cols.length} صلاحية'
                    : '${rows.length} job titles × ${cols.length} perms',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_dirtyJobTitleIds.isNotEmpty)
                Text(
                  isAr
                      ? '✏️ ${_dirtyJobTitleIds.length} غير محفوظ'
                      : '✏️ ${_dirtyJobTitleIds.length} unsaved',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ===== Matrix =====
        Expanded(
          child: rows.isEmpty || cols.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      isAr ? 'لا توجد بيانات' : 'No data',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                )
              : _MatrixGrid(
                  rows: rows,
                  cols: cols,
                  matrix: _matrix,
                  onToggle: _toggle,
                  onToggleColumn: (k) => _toggleColumn(k, rows),
                  isAr: isAr,
                  hasGaps: _hasGaps,
                ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardFilterChip() {
    final s = AppStrings.of(context);
    return PopupMenuButton<DashboardType?>(
      offset: const Offset(0, 26),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _dashboardFilter == null
              ? Colors.grey.withValues(alpha: 0.10)
              : AppColors.info.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _dashboardFilter == null
                ? Colors.grey.withValues(alpha: 0.4)
                : AppColors.info,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_outlined,
                size: 12,
                color: _dashboardFilter == null
                    ? Colors.grey[800]
                    : AppColors.info),
            const SizedBox(width: 4),
            Text(
              _dashboardFilter == null
                  ? (s.isAr ? 'كل الـ Dashboards' : 'All dashboards')
                  : _dashboardFilter!.label(s.isAr),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _dashboardFilter == null
                    ? Colors.grey[800]
                    : AppColors.info,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 14,
                color: _dashboardFilter == null
                    ? Colors.grey[800]
                    : AppColors.info),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: null,
          child: Text(s.isAr ? 'كل الـ Dashboards' : 'All dashboards'),
        ),
        for (final t in DashboardType.values)
          PopupMenuItem(
            value: t,
            child: Text(t.label(s.isAr)),
          ),
      ],
      onSelected: (v) => setState(() => _dashboardFilter = v),
    );
  }

  /// 🆕 تَرتيب فِئات الـDomain (1 = أَوَّل)
  int _domainOrder(String key) {
    const order = {
      'org': 1,
      'hr': 2,
      'roster': 3,
      'transport': 4,
      'camp': 5,
      'forms': 6,
      'reports': 7,
      'notif': 8,
      'security': 9,
      'admin': 10,
      'other': 99,
    };
    return order[key] ?? 50;
  }
}

/// 🆕 فِئة Domain — تَجميع لِعِدّة modules تَحت قِسم واحِد بَصَريّ
class _Domain {
  final String key;       // 'org', 'hr', 'roster', 'camp', etc.
  final String labelAr;   // '🏢 المُؤَسَّسة'
  final String labelEn;   // '🏢 Organization'
  const _Domain(this.key, this.labelAr, this.labelEn);
}

// ============================================================
// المصفوفة الفعليّة (مع تثبيت رأس الصف والعمود)
// ============================================================

class _MatrixGrid extends StatefulWidget {
  final List<JobTitle> rows;
  final List<PermissionDef> cols;
  final Map<String, Set<String>> matrix;
  final void Function(String jtId, String permKey) onToggle;
  final ValueChanged<String> onToggleColumn;
  final bool isAr;
  final bool Function(JobTitle) hasGaps;

  const _MatrixGrid({
    required this.rows,
    required this.cols,
    required this.matrix,
    required this.onToggle,
    required this.onToggleColumn,
    required this.isAr,
    required this.hasGaps,
  });

  @override
  State<_MatrixGrid> createState() => _MatrixGridState();
}

class _MatrixGridState extends State<_MatrixGrid> {
  late ScrollController _hController;
  late ScrollController _hHeaderController;
  late ScrollController _vController;
  late ScrollController _vRowsController;

  @override
  void initState() {
    super.initState();
    _hController = ScrollController();
    _hHeaderController = ScrollController();
    _vController = ScrollController();
    _vRowsController = ScrollController();

    _hController.addListener(() {
      if (_hHeaderController.hasClients &&
          _hHeaderController.offset != _hController.offset) {
        _hHeaderController.jumpTo(_hController.offset);
      }
    });
    _vController.addListener(() {
      if (_vRowsController.hasClients &&
          _vRowsController.offset != _vController.offset) {
        _vRowsController.jumpTo(_vController.offset);
      }
    });
  }

  @override
  void dispose() {
    _hController.dispose();
    _hHeaderController.dispose();
    _vController.dispose();
    _vRowsController.dispose();
    super.dispose();
  }

  static const double _rowH = 36;
  static const double _colW = 38;
  static const double _firstColW = 180;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ===== Header row =====
        Row(
          children: [
            Container(
              width: _firstColW,
              height: _rowH,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                border: Border(
                  right: BorderSide(color: Colors.grey[400]!),
                  bottom: BorderSide(color: Colors.grey[400]!),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                widget.isAr ? 'المسمّى ↓ / الصلاحيّة →' : 'Job ↓ / Perm →',
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hHeaderController,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: widget.cols
                      .map((p) => _ColumnHeader(
                            permission: p,
                            width: _colW,
                            height: _rowH,
                            onTap: () => widget.onToggleColumn(p.key),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
        // ===== Body =====
        Expanded(
          child: Row(
            children: [
              // First column (job titles, vertical scroll synced)
              SizedBox(
                width: _firstColW,
                child: SingleChildScrollView(
                  controller: _vRowsController,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: widget.rows
                        .map((jt) => _RowHeader(
                              jobTitle: jt,
                              width: _firstColW,
                              height: _rowH,
                              isAr: widget.isAr,
                              hasGaps: widget.hasGaps(jt),
                            ))
                        .toList(),
                  ),
                ),
              ),
              // Cell area (both directions)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hController,
                  child: SingleChildScrollView(
                    controller: _vController,
                    child: Column(
                      children: widget.rows.map((jt) {
                        final keys =
                            widget.matrix[jt.id] ?? const <String>{};
                        return Row(
                          children: widget.cols.map((p) {
                            final has = keys.contains(p.key);
                            return _Cell(
                              has: has,
                              width: _colW,
                              height: _rowH,
                              onTap: () => widget.onToggle(jt.id, p.key),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final PermissionDef permission;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _ColumnHeader({
    required this.permission,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Tooltip(
        message: '${permission.module}.${permission.key}\n${permission.nameAr}',
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border(
              right: BorderSide(color: Colors.grey[400]!),
              bottom: BorderSide(color: Colors.grey[400]!),
            ),
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              permission.key.split('.').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowHeader extends StatelessWidget {
  final JobTitle jobTitle;
  final double width;
  final double height;
  final bool isAr;
  final bool hasGaps;

  const _RowHeader({
    required this.jobTitle,
    required this.width,
    required this.height,
    required this.isAr,
    required this.hasGaps,
  });

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(jobTitle.color);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => JobTitleProfileScreen(jobTitle: jobTitle),
      )),
      child: Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: hasGaps ? AppColors.danger.withValues(alpha: 0.06) : Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey[400]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: height,
            color: color ?? Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobTitle.displayName(isAr),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
                if (jobTitle.level > 0)
                  Text(
                    'L${jobTitle.level} • ${jobTitle.dashboardType.label(isAr)}',
                    style: const TextStyle(fontSize: 8.5, color: Colors.grey),
                  ),
              ],
            ),
          ),
          if (hasGaps)
            const Icon(Icons.warning_amber_outlined,
                size: 12, color: AppColors.danger),
        ],
      ),
      ),
    );
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

class _Cell extends StatelessWidget {
  final bool has;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _Cell({
    required this.has,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: has ? AppColors.success.withValues(alpha: 0.18) : Colors.white,
          border: Border(
            right: BorderSide(color: Colors.grey[300]!),
            bottom: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: has
            ? const Icon(Icons.check, size: 14, color: AppColors.success)
            : Container(),
      ),
    );
  }
}
