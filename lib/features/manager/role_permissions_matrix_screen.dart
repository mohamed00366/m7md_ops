import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/rbac/permission_templates.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// 🛡️ شاشة مصفوفة الصلاحيات لمسمى وظيفي واحد
/// تعرض كل الصلاحيات مقسّمة حسب الموديول مع checkboxes + بحث + قوالب
class RolePermissionsMatrixScreen extends StatefulWidget {
  final JobTitle jobTitle;
  const RolePermissionsMatrixScreen({super.key, required this.jobTitle});

  @override
  State<RolePermissionsMatrixScreen> createState() =>
      _RolePermissionsMatrixScreenState();
}

class _RolePermissionsMatrixScreenState
    extends State<RolePermissionsMatrixScreen> {
  Set<String> _selectedKeys = {};
  final TextEditingController _search = TextEditingController();
  bool _saving = false;
  bool _dirty = false;

  // Module → Arabic / English label
  static const _moduleLabels = <String, List<String>>{
    'admin':       ['الإدارة', 'Admin'],
    'dashboard':   ['لوحات التحكم', 'Dashboards'],
    'sites':       ['العملاء والمواقع', 'Customers & Sites'],
    'customers':   ['العملاء والفروع', 'Customers & Branches'],
    'lookups':     ['القوائم المرجعيّة', 'Lookups (Departments / Titles / Countries)'],
    'employees':   ['الموظفون', 'Employees'],
    'buses':       ['الباصات', 'Buses'],
    'rosters':     ['الروسترات', 'Rosters'],
    // 🆕 الحضور (تحت HR)
    'attendance':  ['الحضور والانصراف', 'Attendance'],
    // 🆕 التقييمات + الخصومات
    'evaluations': ['التقييمات', 'Evaluations'],
    'deductions':  ['الخصومات', 'Deductions'],
    'camp':        ['الكامب', 'Camp'],
    'driver':      ['السائق', 'Driver'],
    'employee':    ['شؤون الموظف', 'Employee Self'],
    'tracking':    ['التتبع', 'Tracking'],
    'reports':     ['التقارير', 'Reports'],
    'settings':    ['الإعدادات', 'Settings'],
    'policies':    ['السياسات', 'Policies'],
    // 🆕 النماذج والـ workflows
    'forms':       ['النماذج وسير الموافقات', 'Forms & Workflows'],
    // 🆕 التدريب (لو وُجدت permissions منفصلة)
    'training':    ['التدريب', 'Training'],
    'org':         ['الهيكل التنظيمي', 'Organization'],
    // 🆕 الزيّ (الزيّ الموحّد للموظّفين)
    'uniform':     ['الزيّ الموحّد', 'Uniforms'],
    // 🆕 شؤون الموارد البشريّة (تهيئة + وثائق + تقارير HR)
    'hr':          ['الموارد البشريّة', 'Human Resources'],
    // 🆕 مذكّرة الموظّف اليوميّة
    'daily_memo':  ['المذكّرة اليوميّة', 'Daily Memo'],
    // 🆕 الإجازات
    'leave':       ['🏖️ الإجازات', '🏖️ Leave Management'],
    // 🆕 الروستر — مَجموعات مُستَقلّة لِكلّ شاشة
    'roster_creator':    ['📅 إنشاء روستر', '📅 Create Roster'],
    'rosters_center':    ['📊 مركز الروسترات', '📊 Rosters Center'],
    'roster_approvals':  ['✅ اعتماد الروسترات', '✅ Roster Approvals'],
    'approved_roster':   ['📋 الروستر المعتمد', '📋 Approved Roster'],
    'my_roster':         ['👤 روستري', '👤 My Roster'],
  };

  static const _moduleIcons = <String, IconData>{
    'admin':       Icons.shield_outlined,
    'dashboard':   Icons.dashboard_outlined,
    'sites':       Icons.business_outlined,
    'customers':   Icons.handshake_outlined,
    'lookups':     Icons.list_alt_outlined,
    'employees':   Icons.people_alt_outlined,
    'buses':       Icons.directions_bus_outlined,
    'rosters':     Icons.fact_check_outlined,
    'attendance':  Icons.fingerprint,
    'evaluations': Icons.star_outline,
    'deductions':  Icons.money_off_outlined,
    'camp':        Icons.holiday_village_outlined,
    'driver':      Icons.local_taxi_outlined,
    'employee':    Icons.badge_outlined,
    'tracking':    Icons.location_on_outlined,
    'reports':     Icons.bar_chart,
    'settings':    Icons.settings_outlined,
    'policies':    Icons.menu_book_outlined,
    'forms':       Icons.assignment_outlined,
    'training':    Icons.school_outlined,
    'org':         Icons.account_tree_outlined,
    'uniform':     Icons.checkroom_outlined,
    'hr':          Icons.badge_outlined,
    'daily_memo':  Icons.note_alt_outlined,
    'leave':       Icons.beach_access_outlined,
    'roster_creator':   Icons.edit_calendar_outlined,
    'rosters_center':   Icons.dashboard_customize_outlined,
    'roster_approvals': Icons.fact_check_outlined,
    'approved_roster':  Icons.verified_outlined,
    'my_roster':        Icons.calendar_month_outlined,
  };

  static const _moduleColors = <String, Color>{
    'admin':       Color(0xFFE24B4A),
    'dashboard':   Color(0xFF3B82F6),
    'sites':       Color(0xFF059669),
    'customers':   Color(0xFF059669),
    'lookups':     Color(0xFF0F766E),
    'employees':   Color(0xFF7C3AED),
    'buses':       Color(0xFF2563EB),
    'rosters':     Color(0xFFF59E0B),
    'attendance':  Color(0xFF7C3AED),
    'evaluations': Color(0xFFF59E0B),
    'deductions':  Color(0xFFDC2626),
    'camp':        Color(0xFF8B5CF6),
    'driver':      Color(0xFF10B981),
    'employee':    Color(0xFF64748B),
    'tracking':    Color(0xFF14B8A6),
    'reports':     Color(0xFF14B8A6),
    'settings':    Color(0xFF6B7280),
    'policies':    Color(0xFF8B5CF6),
    'forms':       Color(0xFF7C3AED),
    'training':    Color(0xFF0EA5E9),
    'org':         Color(0xFF1F2937),
    'uniform':     Color(0xFFEC4899),
    'hr':          Color(0xFF7C3AED),
    'daily_memo':  Color(0xFF0EA5E9),
    'leave':       Color(0xFF06B6D4),
    'roster_creator':   Color(0xFFF59E0B),
    'rosters_center':   Color(0xFFEAB308),
    'roster_approvals': Color(0xFF10B981),
    'approved_roster':  Color(0xFF14B8A6),
    'my_roster':        Color(0xFF06B6D4),
  };

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  void _loadCurrent() {
    final repo = MockRepository();
    final roleId = widget.jobTitle.roleId;
    if (roleId != null) {
      _selectedKeys = repo.permissionKeysForRole(roleId);
    } else {
      _selectedKeys = {};
    }
    setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
      _dirty = true;
    });
  }

  void _toggleModule(String module, List<PermissionDef> perms) {
    final allSelected = perms.every((p) => _selectedKeys.contains(p.key));
    setState(() {
      if (allSelected) {
        for (final p in perms) {
          _selectedKeys.remove(p.key);
        }
      } else {
        for (final p in perms) {
          _selectedKeys.add(p.key);
        }
      }
      _dirty = true;
    });
  }

  /// 🆕 يجمع صلاحيّات الموديول بحسب الصفحة (resource).
  /// كلّ مفتاح بصيغة `<resource>.<op>` يصير صفحة جديدة، ولكلّ صفحة
  /// 4 شارات قياسيّة: مشاهدة / تعديل / إضافة / حذف. أيّ صلاحيّات أخرى
  /// (process, approve, export, mark…) تظهر تحت "أخرى".
  List<Widget> _buildPageRows(
    bool isAr,
    Color color,
    List<PermissionDef> perms,
  ) {
    // groupedByResource: key = الجزء قبل آخر نقطة, value = ops list
    // مثال: 'employees.view' → resource='employees', op='view'
    //       'camp.rooms.view' → resource='camp.rooms', op='view'
    final byResource = <String, List<PermissionDef>>{};
    for (final p in perms) {
      final lastDot = p.key.lastIndexOf('.');
      if (lastDot < 0) {
        byResource.putIfAbsent('_other', () => []).add(p);
        continue;
      }
      final resource = p.key.substring(0, lastDot);
      byResource.putIfAbsent(resource, () => []).add(p);
    }

    // عمليّات قياسيّة معروفة + ترجمتها
    const standardOps = ['view', 'create', 'edit', 'delete'];
    final opLabel = <String, String>{
      'view': isAr ? 'مشاهدة' : 'View',
      'create': isAr ? 'إضافة' : 'Add',
      'edit': isAr ? 'تعديل' : 'Edit',
      'delete': isAr ? 'حذف' : 'Delete',
    };
    final opIcon = <String, IconData>{
      'view': Icons.visibility_outlined,
      'create': Icons.add_circle_outline,
      'edit': Icons.edit_outlined,
      'delete': Icons.delete_outline,
    };
    final opColor = <String, Color>{
      'view': const Color(0xFF14B8A6),
      'create': const Color(0xFF10B981),
      'edit': const Color(0xFFF59E0B),
      'delete': const Color(0xFFE24B4A),
    };

    final widgets = <Widget>[];
    final sortedResources = byResource.keys.toList()..sort();
    for (final resource in sortedResources) {
      final list = byResource[resource]!;
      // اختزال عرض الـ resource (إزالة الـ module prefix إن وُجد)
      String resourceLabel;
      if (resource == '_other') {
        resourceLabel = isAr ? 'صلاحيّات أخرى' : 'Other permissions';
      } else {
        // استخدم اسم الـPermissionDef الأوّل بعد إزالة كلمة "View/Edit/..."
        // كحلّ افتراضي
        final viewPerm = list.firstWhere(
          (p) => p.key.endsWith('.view'),
          orElse: () => list.first,
        );
        resourceLabel = isAr ? viewPerm.nameAr : viewPerm.nameEn;
        // تنظيف: احذف "عرض"/"View" من البداية
        for (final w in [
          'عرض ',
          'إدارة ',
          'View ',
          'Manage '
        ]) {
          if (resourceLabel.startsWith(w)) {
            resourceLabel = resourceLabel.substring(w.length);
            break;
          }
        }
      }

      // اجمع كل الـops القياسيّة المتاحة + باقي الـops غير القياسيّة
      final standardPerms = <String, PermissionDef>{};
      final extraPerms = <PermissionDef>[];
      for (final p in list) {
        final op = p.key.substring(p.key.lastIndexOf('.') + 1);
        if (standardOps.contains(op)) {
          standardPerms[op] = p;
        } else {
          extraPerms.add(p);
        }
      }

      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resourceLabel,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              // 4 شارات قياسيّة
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final op in standardOps)
                    if (standardPerms.containsKey(op))
                      _PermChip(
                        label: opLabel[op]!,
                        icon: opIcon[op]!,
                        color: opColor[op]!,
                        selected:
                            _selectedKeys.contains(standardPerms[op]!.key),
                        onTap: () => _toggle(standardPerms[op]!.key),
                      )
                    else
                      _PermChip(
                        label: opLabel[op]!,
                        icon: opIcon[op]!,
                        color: opColor[op]!,
                        selected: false,
                        disabled: true,
                        onTap: () {},
                      ),
                  // الصلاحيّات الإضافيّة (export, approve, ...)
                  for (final p in extraPerms)
                    _PermChip(
                      label: isAr ? p.nameAr : p.nameEn,
                      icon: Icons.bolt_outlined,
                      color: color,
                      selected: _selectedKeys.contains(p.key),
                      onTap: () => _toggle(p.key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  Future<void> _applyTemplate() async {
    final s = AppStrings.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.isAr ? 'تطبيق قالب' : 'Apply Template'),
        children: [
          _templateOption(ctx, 'recommended',
              s.isAr ? 'موصى به (حسب اسم الوظيفة)' : 'Recommended (by name)'),
          _templateOption(ctx, 'worker',
              s.isAr ? 'عامل ميداني' : 'Field Worker'),
          _templateOption(ctx, 'operations',
              s.isAr ? 'موظف عمليات' : 'Operations Staff'),
          _templateOption(ctx, 'admin',
              s.isAr ? 'موظف إداري' : 'Admin Staff'),
          _templateOption(ctx, 'manager',
              s.isAr ? 'مدير (إداري + إضافات)' : 'Manager (admin + extras)'),
          _templateOption(ctx, 'supervisor',
              s.isAr ? 'مشرف' : 'Supervisor'),
          _templateOption(ctx, 'campBoss',
              s.isAr ? 'مدير الكامب' : 'Camp Boss'),
          _templateOption(ctx, 'driver',
              s.isAr ? 'سائق' : 'Driver'),
          _templateOption(ctx, 'all',
              s.isAr ? '⚠️ كل الصلاحيات' : '⚠️ All permissions'),
          _templateOption(ctx, 'none',
              s.isAr ? '🗑️ مسح كل الصلاحيات' : '🗑️ Clear all'),
        ],
      ),
    );
    if (choice == null) return;
    final all = MockRepository().permissionDefs.map((p) => p.key).toSet();
    setState(() {
      switch (choice) {
        case 'recommended':
          _selectedKeys = PermissionTemplates.recommendFor(
            category: widget.jobTitle.category,
            nameAr: widget.jobTitle.nameAr,
            nameEn: widget.jobTitle.nameEn,
          ).toSet();
          break;
        case 'worker':
          _selectedKeys = PermissionTemplates.workerBaseline.toSet();
          break;
        case 'operations':
          _selectedKeys = PermissionTemplates.operationsBaseline.toSet();
          break;
        case 'admin':
          _selectedKeys = PermissionTemplates.adminBaseline.toSet();
          break;
        case 'manager':
          _selectedKeys = {
            ...PermissionTemplates.adminBaseline,
            ...PermissionTemplates.managerExtras
          };
          break;
        case 'supervisor':
          _selectedKeys = {
            ...PermissionTemplates.workerBaseline,
            ...PermissionTemplates.supervisorExtras
          };
          break;
        case 'campBoss':
          _selectedKeys = PermissionTemplates.campBossBaseline.toSet();
          break;
        case 'driver':
          _selectedKeys = PermissionTemplates.driverBaseline.toSet();
          break;
        case 'all':
          _selectedKeys = all;
          break;
        case 'none':
          _selectedKeys = <String>{};
          break;
      }
      _dirty = true;
    });
  }

  Widget _templateOption(BuildContext ctx, String value, String label) =>
      SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      );

  // ============================================================
  // 🆕 نسخ صلاحيّات من مسمّى آخر
  // ============================================================
  Future<void> _copyFromAnother() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final candidates = repo.jobTitles
        .where((j) => j.id != widget.jobTitle.id && j.roleId != null)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            s.isAr ? 'لا توجد مسمّيات أخرى لها صلاحيّات' : 'No other configured job titles'),
      ));
      return;
    }
    final picked = await showModalBottomSheet<JobTitle>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                s.isAr
                    ? '📋 اختر مسمّى لنسخ صلاحيّاته'
                    : '📋 Pick a job title to copy permissions from',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
            for (final jt in candidates)
              ListTile(
                dense: true,
                leading: Container(
                  width: 8,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _hexToColor(jt.color) ?? Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                title: Text(s.isAr ? jt.nameAr : jt.nameEn,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${jt.level > 0 ? "L${jt.level}" : ""} • ${repo.permissionKeysForRole(jt.roleId!).length} ${s.isAr ? "صلاحية" : "perms"}',
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(ctx, jt),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final keys = repo.permissionKeysForRole(picked.roleId!);
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.isAr
            ? 'كيف تريد النسخ؟ (${keys.length} صلاحية)'
            : 'How to copy? (${keys.length} perms)'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: Text(s.isAr ? 'استبدال الكلّ' : 'Replace all'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: Text(s.isAr ? 'دمج (إضافة)' : 'Merge (add)'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    setState(() {
      if (mode == 'replace') {
        _selectedKeys = Set<String>.from(keys);
      } else {
        _selectedKeys.addAll(keys);
      }
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.indigo,
      content: Text(
        s.isAr
            ? 'تم نسخ ${keys.length} صلاحية من ${picked.nameAr}'
            : 'Copied ${keys.length} perms from ${picked.nameEn}',
      ),
    ));
  }

  // ============================================================
  // 🆕 مقارنة مع مسمّى آخر
  // ============================================================
  Future<void> _compareWithAnother() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final candidates = repo.jobTitles
        .where((j) => j.id != widget.jobTitle.id && j.roleId != null)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.isAr
            ? 'لا توجد مسمّيات أخرى للمقارنة'
            : 'No other configured job titles'),
      ));
      return;
    }
    final picked = await showModalBottomSheet<JobTitle>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                s.isAr
                    ? '🔍 قارن مع مسمّى آخر'
                    : '🔍 Compare with another job title',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
            for (final jt in candidates)
              ListTile(
                dense: true,
                title: Text(s.isAr ? jt.nameAr : jt.nameEn),
                onTap: () => Navigator.pop(ctx, jt),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final otherKeys = repo.permissionKeysForRole(picked.roleId!);
    final inMineNotOther = _selectedKeys.difference(otherKeys);
    final inOtherNotMine = otherKeys.difference(_selectedKeys);
    final inBoth = _selectedKeys.intersection(otherKeys);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr
            ? 'مقارنة: ${widget.jobTitle.nameAr} ↔ ${picked.nameAr}'
            : 'Compare: ${widget.jobTitle.nameEn} ↔ ${picked.nameEn}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _diffSection(
                  title: s.isAr
                      ? '✅ مشترك (${inBoth.length})'
                      : '✅ Both have (${inBoth.length})',
                  keys: inBoth.toList()..sort(),
                  color: Colors.green,
                ),
                _diffSection(
                  title: s.isAr
                      ? '➕ عندك فقط (${inMineNotOther.length})'
                      : '➕ Only you (${inMineNotOther.length})',
                  keys: inMineNotOther.toList()..sort(),
                  color: Colors.orange,
                ),
                _diffSection(
                  title: s.isAr
                      ? '⚠️ عند الآخر فقط (${inOtherNotMine.length})'
                      : '⚠️ Only other (${inOtherNotMine.length})',
                  keys: inOtherNotMine.toList()..sort(),
                  color: Colors.red,
                  showAddButton: inOtherNotMine.isNotEmpty,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.isAr ? 'إغلاق' : 'Close'),
          ),
          if (inOtherNotMine.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(s.isAr
                  ? 'أضِف الناقص (${inOtherNotMine.length})'
                  : 'Add missing (${inOtherNotMine.length})'),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedKeys.addAll(inOtherNotMine);
                  _dirty = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.indigo,
                  content: Text(s.isAr
                      ? 'تمّت إضافة ${inOtherNotMine.length} صلاحية'
                      : 'Added ${inOtherNotMine.length} permissions'),
                ));
              },
            ),
        ],
      ),
    );
  }

  Widget _diffSection({
    required String title,
    required List<String> keys,
    required Color color,
    bool showAddButton = false,
  }) {
    if (keys.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: keys
                .take(20)
                .map((k) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        k,
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ))
                .toList(),
          ),
          if (keys.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '... +${keys.length - 20}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
        ],
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

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    setState(() => _saving = true);

    // 🆕 إذا لم يكن للوظيفة دور مرتبط، أنشئ واحداً الآن
    String? roleId = widget.jobTitle.roleId;
    if (roleId == null) {
      // ابحث في الأدوار الموجودة بنفس الاسم أولاً
      try {
        final existing = repo.roleDefs.firstWhere(
            (r) => r.nameAr == widget.jobTitle.nameAr ||
                r.nameEn == widget.jobTitle.nameEn);
        roleId = existing.id;
      } catch (_) {}

      // إن لم يوجد، أنشئ دوراً جديداً
      if (roleId == null) {
        if (supaReady) {
          final r = await ds.createRole(
              nameAr: widget.jobTitle.nameAr,
              nameEn: widget.jobTitle.nameEn,
              priority: 10);
          roleId = r?.id;
        } else {
          final newId = repo.generateId();
          repo.roleDefs.add(RoleDef(
            id: newId,
            key: widget.jobTitle.nameEn
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
            nameAr: widget.jobTitle.nameAr,
            nameEn: widget.jobTitle.nameEn,
            priority: 10,
          ));
          roleId = newId;
        }
      }

      if (roleId == null) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(
                s.isAr ? 'فشل إنشاء الدور' : 'Failed to create role'),
          ));
        }
        return;
      }

      // اربط الـ role بالوظيفة في Supabase + Repo
      widget.jobTitle.roleId = roleId;
      if (supaReady) {
        try {
          await ds.client.from('job_titles')
              .update({'role_id': roleId}).eq('id', widget.jobTitle.id);
        } catch (e) {
          // تجاهل في حال أن الـ FK سينضبط لاحقاً
        }
      }
    }

    if (supaReady) {
      final ids = repo.permissionDefs
          .where((p) => _selectedKeys.contains(p.key))
          .map((p) => p.id)
          .toList();
      final ok = await ds.setRolePermissions(roleId, ids);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        setState(() => _saving = false);
        return;
      }
      // sync local
      repo.setRolePermissionsByKeys(roleId, _selectedKeys, '');
    } else {
      repo.setRolePermissionsByKeys(roleId, _selectedKeys, '');
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade600,
        content: Text(s.isAr
            ? 'تم حفظ الصلاحيات (${_selectedKeys.length})'
            : 'Saved (${_selectedKeys.length} permissions)'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final allPerms = repo.permissionDefs;

    // Group by module
    final byModule = <String, List<PermissionDef>>{};
    for (final p in allPerms) {
      byModule.putIfAbsent(p.module, () => []).add(p);
    }
    // Filter by search
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      for (final m in byModule.keys.toList()) {
        byModule[m] = byModule[m]!.where((p) {
          return p.key.toLowerCase().contains(q) ||
              p.nameAr.toLowerCase().contains(q) ||
              p.nameEn.toLowerCase().contains(q);
        }).toList();
        if (byModule[m]!.isEmpty) byModule.remove(m);
      }
    }

    // Order modules in our preferred order (matches the app's section grouping),
    // unknown ones go to the end.
    final orderedKeys = <String>[
      'dashboard',
      // المؤسّسة
      'org', 'sites', 'customers', 'lookups',
      // HR
      'employees', 'hr', 'attendance', 'evaluations', 'deductions',
      'training', 'uniform',
      // الروستر والنقل (مَجموعات مُستَقلّة)
      'rosters', 'roster_creator', 'rosters_center', 'roster_approvals',
      'approved_roster', 'my_roster',
      'buses', 'tracking', 'driver',
      // الكامب
      'camp',
      // الموظّف
      'employee', 'daily_memo', 'leave',
      // النماذج
      'forms',
      // التقارير
      'reports',
      // الإعدادات والسياسات والإدارة
      'settings', 'policies', 'admin',
    ];
    final keys = [
      ...orderedKeys.where(byModule.containsKey),
      ...byModule.keys.where((k) => !orderedKeys.contains(k))
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        leading: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: Colors.white.withOpacity(0.15),
            ),
            onPressed: () async {
              if (_dirty) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(s.isAr ? 'تجاهل التغييرات؟' : 'Discard changes?'),
                    content: Text(s.isAr
                        ? 'لديك تغييرات لم تُحفظ.'
                        : 'You have unsaved changes.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(s.isAr ? 'ابقَ' : 'Stay')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(s.isAr ? 'تجاهل' : 'Discard')),
                    ],
                  ),
                );
                if (ok != true) return;
              }
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(s.isAr ? 'رجوع' : 'Back',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                s.isAr
                    ? 'صلاحيات: ${widget.jobTitle.nameAr}'
                    : 'Permissions: ${widget.jobTitle.nameEn}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14)),
            Text(
                s.isAr
                    ? '${_selectedKeys.length} صلاحية محددة'
                    : '${_selectedKeys.length} selected',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.isAr ? 'نسخ من مسمّى' : 'Copy from Job Title',
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: _copyFromAnother,
          ),
          IconButton(
            tooltip: s.isAr ? 'مقارنة' : 'Compare',
            icon: const Icon(Icons.compare_arrows),
            onPressed: _compareWithAnother,
          ),
          IconButton(
            tooltip: s.isAr ? 'تطبيق قالب' : 'Apply Template',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _applyTemplate,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: s.isAr ? 'بحث في الصلاحيات...' : 'Search permissions...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            itemCount: keys.length,
            itemBuilder: (_, i) {
              final m = keys[i];
              final perms = byModule[m]!;
              final labels = _moduleLabels[m] ??
                  [m, m.substring(0, 1).toUpperCase() + m.substring(1)];
              final icon = _moduleIcons[m] ?? Icons.folder_outlined;
              final color = _moduleColors[m] ?? Colors.grey.shade700;
              final selectedInModule =
                  perms.where((p) => _selectedKeys.contains(p.key)).length;
              final allSelected = selectedInModule == perms.length;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: ExpansionTile(
                  iconColor: color,
                  collapsedIconColor: color,
                  initiallyExpanded: q.isNotEmpty,
                  shape: const RoundedRectangleBorder(),
                  collapsedShape: const RoundedRectangleBorder(),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  title: Text(s.isAr ? labels[0] : labels[1],
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      '$selectedInModule / ${perms.length} ${s.isAr ? 'محدد' : 'selected'}',
                      style: TextStyle(color: color, fontSize: 11)),
                  trailing: TextButton(
                    onPressed: () => _toggleModule(m, perms),
                    child: Text(
                        allSelected
                            ? (s.isAr ? 'إلغاء الكل' : 'Deselect All')
                            : (s.isAr ? 'تحديد الكل' : 'Select All'),
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                  children: [
                    // 🆕 الصلاحيّات مجمّعة بالصفحة — كلّ صفحة لها 4 شارات
                    // (مشاهدة / تعديل / إضافة / حذف) عند توفّرها.
                    ..._buildPageRows(s.isAr, color, perms),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: (_dirty && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(
                  _saving
                      ? (s.isAr ? 'جارٍ الحفظ...' : 'Saving...')
                      : (s.isAr
                          ? 'حفظ الصلاحيات (${_selectedKeys.length})'
                          : 'Save (${_selectedKeys.length})'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🆕 شارة صلاحيّة قابلة للضغط — تستخدم في صفحة الصلاحيّات لكلّ
/// (مشاهدة / إضافة / تعديل / حذف) تحت كلّ صفحة.
class _PermChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _PermChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = disabled ? Colors.grey.shade400 : color;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c : c.withOpacity(0.35),
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle : icon,
              size: 13,
              color: c,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c,
                decoration: disabled ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
