import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/point_assignment_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة إسناد المشرفين إلى نقاط البيع.
/// Operation تستخدمها لربط كل مشرف بنقطة معيّنة.
/// يمكن تغيير الإسناد في أي وقت.
class OperationSupervisorAssignments extends StatefulWidget {
  const OperationSupervisorAssignments({super.key});

  @override
  State<OperationSupervisorAssignments> createState() =>
      _OperationSupervisorAssignmentsState();
}

class _OperationSupervisorAssignmentsState
    extends State<OperationSupervisorAssignments>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // 🆕 قائمة المرشّحين = من قائمة الإعدادات (PointAssignmentSettings)
  // الافتراضيّ: Site Supervisor + كلّ من يتبع له (Marshal/KC/Valet)
  List<Employee> _supervisors(MockRepository repo, String? activeCountry) {
    // ابنِ القائمة الافتراضيّة
    JobTitle? siteSupervisor;
    try {
      siteSupervisor =
          repo.jobTitles.firstWhere((j) => j.nameEn == 'Site Supervisor');
    } catch (_) {
      siteSupervisor = null;
    }
    final defaultEligible = <String>{};
    if (siteSupervisor != null) {
      defaultEligible.add(siteSupervisor.id);
      for (final j in repo.jobTitles) {
        if (j.reportsToIds.contains(siteSupervisor.id)) {
          defaultEligible.add(j.id);
        }
      }
    }

    return repo.employees.where((e) {
      if (activeCountry != null && e.countryId != activeCountry) return false;
      final jt = e.jobTitleId == null ? null : repo.jobTitleById(e.jobTitleId);
      if (jt == null) {
        // fallback: استخدم الحقل النصي القديم
        final t = e.jobTitle.toLowerCase();
        return t.contains('مشرف') || t.contains('supervisor');
      }
      // 🆕 استخدم إعدادات المسؤول (إن وُجدت) أو الافتراضيّ
      return PointAssignmentSettings.instance
          .isEligible(jt.id, defaultEligible);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final activeCountry = auth.activeCountryId;

    var supervisors = _supervisors(repo, activeCountry);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      supervisors = supervisors
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q))
          .toList();
    }

    return Scaffold(
      body: Column(
        children: [
          // 🆕 شريط التبويبات
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AppColors.brand,
              labelColor: AppColors.brand,
              tabs: [
                Tab(
                  icon: const Icon(Icons.pin_drop_outlined, size: 18),
                  text: s.isAr ? 'حسب النقطة' : 'By Point',
                ),
                Tab(
                  icon: const Icon(Icons.person_outline, size: 18),
                  text: s.isAr ? 'حسب الموظف' : 'By Employee',
                ),
              ],
            ),
          ),
          // ملاحظة موحّدة لكلا التبويبَين
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.info, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.isAr
                        ? '🎖️ ربط الموظّف بِنَقطة يُرَقّيه تلقائيّاً إلى المُسمّى الهَدَف (يُضبَط من إعدادات إسناد النقاط).'
                        : '🎖️ Linking an employee to a point auto-promotes them to the configured target title.',
                    style: const TextStyle(
                        color: AppColors.info, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // ===== Tab 1: حسب النقطة =====
                _ByPointTab(query: _query, onQuery: (v) => setState(() => _query = v)),
                // ===== Tab 2: حسب الموظف (الموجود سابقاً) =====
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: s.isAr ? 'بحث عن مشرف' : 'Search supervisor',
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: supervisors.isEmpty
                          ? EmptyState(
                              icon: Icons.person_off,
                              message: s.isAr
                                  ? 'لا يوجد مشرفون في هذه الدولة'
                                  : 'No supervisors in this country',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: supervisors.length,
                              itemBuilder: (_, i) =>
                                  _SupervisorCard(supervisor: supervisors[i]),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupervisorCard extends StatelessWidget {
  final Employee supervisor;
  const _SupervisorCard({required this.supervisor});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final pid = supervisor.pointId ?? supervisor.siteId; // legacy fallback
    final point = pid == null ? null : repo.pointById(pid);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: point == null
                ? AppColors.warning.withOpacity(0.4)
                : Theme.of(context).dividerColor,
            width: point == null ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                  initials: supervisor.initials,
                  color: repo.isPromoted(supervisor)
                      ? AppColors.success
                      : AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(supervisor.fullName,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                        // 🆕 شارة الترقية الديناميكيّة (L4 → L3)
                        if (repo.isPromoted(supervisor))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.workspace_premium_outlined,
                                    color: Colors.white, size: 10),
                                const SizedBox(width: 2),
                                Text(
                                  s.isAr ? 'L3 مرقّى' : 'L3 Acting',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(supervisor.code,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: AppColors.brand)),
                        // 🆕 المسمّى الأصلي (للمرقّيين)
                        Builder(builder: (_) {
                          final base = supervisor.jobTitleId == null
                              ? null
                              : repo.jobTitleById(supervisor.jobTitleId);
                          if (base == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: Text(
                              '• ${base.displayName(s.isAr)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[700],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // النقطة المُسندة
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (point == null ? AppColors.warning : AppColors.success)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  point == null
                      ? Icons.location_off
                      : Icons.place,
                  color: point == null
                      ? AppColors.warning
                      : AppColors.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: point == null
                      ? Text(
                          s.isAr
                              ? 'غير مرتبط بنقطة'
                              : 'Not assigned to a Point',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(point.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                            if (point.code.isNotEmpty)
                              Text(point.code,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: AppColors.success)),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 🆕 الأزرار تَظهر فقط لمن يَملك صلاحيّة تعديل إسناد النقاط
          Builder(builder: (ctx) {
            final auth = ctx.watch<AuthProvider>();
            final canAssign = auth.isSuperAdmin ||
                auth.permissions.contains(P.orgPointAssignmentEdit) ||
                auth.permissions.contains(P.busesAssign);
            if (!canAssign) {
              return const SizedBox.shrink();
            }
            return Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickPoint(context),
                    icon: const Icon(Icons.edit_location, size: 16),
                    label: Text(point == null
                        ? (s.isAr ? 'ربط بنقطة' : 'Assign Point')
                        : (s.isAr ? 'تغيير النقطة' : 'Change Point')),
                  ),
                ),
                if (point != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    onPressed: () => _unassign(context),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: Text(s.isAr ? 'فك' : 'Unlink'),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  void _pickPoint(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final activeCountry = auth.activeCountryId;

    // فلترة صارمة: المشرف يُربط فقط بنقاط نفس الدولة
    // (المشرف نفسه في دولة، ولا يجوز ربطه بنقطة في دولة ثانية)
    final supervisorCountry = supervisor.countryId;
    final filterCountry = supervisorCountry ?? activeCountry;

    final points = filterCountry == null
        ? repo.points
        : repo.points
            .where((p) => p.countryId == filterCountry)
            .toList();

    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(s.isAr
            ? 'لا توجد نقاط في دولة المشرف. أضف نقطة من قسم العملاء أولاً'
            : 'No Points in supervisor\'s country. Add a Point from Customers first'),
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.isAr ? 'اختر نقطة' : 'Pick a Point',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: points.length,
                itemBuilder: (_, i) {
                  final p = points[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Theme.of(context).dividerColor),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.place,
                            color: AppColors.warning, size: 18),
                      ),
                      title: Text(p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      subtitle: p.code.isEmpty
                          ? null
                          : Text(p.code,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: AppColors.warning)),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _assignTo(context, p.id);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignTo(BuildContext context, String pointId) async {
    final s = AppStrings.of(context);
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.assignEmployeeToSite(supervisor.id, pointId);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      supervisor.pointId = pointId;
      MockRepository().notifyListeners();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.savedSuccess)),
    );
  }

  Future<void> _unassign(BuildContext context) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'فك ربط هذا المشرف عن النقطة؟'
            : 'Unlink this supervisor from the Point?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.isAr ? 'فك' : 'Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.assignEmployeeToSite(supervisor.id, null);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      supervisor.pointId = null;
      MockRepository().notifyListeners();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.savedSuccess)),
    );
  }
}

// ============================================================
// 🆕 تبويب «حسب النقطة» — Points-centric View
// ============================================================
class _ByPointTab extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQuery;
  const _ByPointTab({required this.query, required this.onQuery});

  @override
  State<_ByPointTab> createState() => _ByPointTabState();
}

class _ByPointTabState extends State<_ByPointTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final activeCountry = auth.activeCountryId;

    var points = activeCountry == null
        ? repo.points
        : repo.points.where((p) => p.countryId == activeCountry).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      points = points
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.code.toLowerCase().contains(q))
          .toList();
    }
    points.sort((a, b) => a.name.compareTo(b.name));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: isAr ? '🔍 بحث عن نقطة...' : '🔍 Search point...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: points.isEmpty
              ? EmptyState(
                  icon: Icons.location_off,
                  message: isAr ? 'لا توجد نقاط' : 'No points',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                  itemCount: points.length,
                  itemBuilder: (_, i) => _PointCard(point: points[i]),
                ),
        ),
      ],
    );
  }
}

/// بطاقة نقطة تعرض كل الموظفين المرتبطين تحتها
class _PointCard extends StatefulWidget {
  final Point point;
  const _PointCard({required this.point});

  @override
  State<_PointCard> createState() => _PointCardState();
}

class _PointCardState extends State<_PointCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final point = widget.point;

    // الموظفون المرتبطون بهذه النقطة
    final linked = repo.employees.where((e) {
      return (e.pointId == point.id) || (e.siteId == point.id);
    }).toList()
      ..sort((a, b) {
        // المرقّون L3 أولاً، ثم الباقي
        final aPro = repo.isPromoted(a) ? 0 : 1;
        final bPro = repo.isPromoted(b) ? 0 : 1;
        if (aPro != bPro) return aPro.compareTo(bPro);
        return a.fullName.compareTo(b.fullName);
      });

    final promotedCount = linked.where(repo.isPromoted).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: linked.isEmpty
              ? AppColors.warning.withOpacity(0.4)
              : AppColors.brand.withOpacity(0.25),
          width: linked.isEmpty ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — اسم النقطة + إحصاء + توسعة
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.pin_drop_outlined,
                        color: AppColors.brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            if (point.code.isNotEmpty)
                              Text(
                                point.code,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace',
                                ),
                              ),
                            const SizedBox(width: 8),
                            _statBadge(
                              icon: Icons.people_outline,
                              count: linked.length,
                              color: linked.isEmpty
                                  ? AppColors.warning
                                  : AppColors.brand,
                            ),
                            if (promotedCount > 0) ...[
                              const SizedBox(width: 4),
                              _statBadge(
                                icon: Icons.workspace_premium_outlined,
                                count: promotedCount,
                                color: AppColors.success,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey[700],
                    ),
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            // قائمة الموظفين
            if (linked.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'لا يوجد موظف مرتبط — أضِف أوّل موظف'
                            : 'No employees linked — add the first one',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final emp in linked)
                _LinkedEmployeeRow(employee: emp, point: point, isAr: isAr),
            // 🆕 زرّ الإضافة — مَحميّ بصلاحيّة تعديل الإسناد
            Builder(builder: (ctx) {
              final auth = ctx.watch<AuthProvider>();
              final canAssign = auth.isSuperAdmin ||
                  auth.permissions
                      .contains(P.orgPointAssignmentEdit) ||
                  auth.permissions.contains(P.busesAssign);
              if (!canAssign) return const SizedBox.shrink();
              return Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addEmployee(context),
                  icon: const Icon(Icons.person_add_alt_outlined, size: 16),
                  label: Text(
                    isAr
                        ? '➕ إضافة موظف لهذه النقطة'
                        : '➕ Add employee to this point',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: BorderSide(color: AppColors.brand.withOpacity(0.5)),
                  ),
                ),
              ),
            );
            }),
          ],
        ],
      ),
    );
  }

  Widget _statBadge({
    required IconData icon,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// اختيار موظف لإسناده إلى هذه النقطة
  Future<void> _addEmployee(BuildContext context) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final activeCountry = auth.activeCountryId;
    final point = widget.point;
    final pointCountry = point.countryId ?? activeCountry;

    // 🆕 المرشّحون = من قائمة الإعدادات (PointAssignmentSettings)
    // الافتراضيّ: Site Supervisor + كلّ من يتبع له (Marshal/KC/Valet)
    // المسؤول يستطيع تخصيصها من شاشة الإعدادات.
    JobTitle? siteSupervisor;
    try {
      siteSupervisor = repo.jobTitles
          .firstWhere((j) => j.nameEn == 'Site Supervisor');
    } catch (_) {
      siteSupervisor = null;
    }
    // قائمة الافتراضيّ
    final defaultEligible = <String>{};
    if (siteSupervisor != null) {
      defaultEligible.add(siteSupervisor.id);
      for (final j in repo.jobTitles) {
        if (j.reportsToIds.contains(siteSupervisor.id)) {
          defaultEligible.add(j.id);
        }
      }
    }

    final candidates = repo.employees.where((e) {
      if (pointCountry != null && e.countryId != pointCountry) return false;
      // الشرط: استبعاد كلّ موظف مرتبط بأيّ نقطة (هذه أو غيرها)
      if (e.pointId != null || e.siteId != null) return false;
      final jt = e.jobTitleId == null ? null : repo.jobTitleById(e.jobTitleId);
      if (jt == null) return false;
      // 🆕 استخدم إعدادات المسؤول (إن وُجدت) أو الافتراضيّ
      return PointAssignmentSettings.instance
          .isEligible(jt.id, defaultEligible);
    }).toList()
      ..sort((a, b) {
        final aJt = a.jobTitleId == null
            ? null
            : repo.jobTitleById(a.jobTitleId);
        final bJt = b.jobTitleId == null
            ? null
            : repo.jobTitleById(b.jobTitleId);
        // L3 أوّلاً
        final aL = aJt?.level ?? 99;
        final bL = bJt?.level ?? 99;
        if (aL != bL) return aL.compareTo(bL);
        return a.fullName.compareTo(b.fullName);
      });

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(
          isAr
              ? 'لا يوجد موظفون متاحون (L3 أو L4) في هذه الدولة'
              : 'No available L3/L4 employees in this country',
        ),
      ));
      return;
    }

    final picked = await showModalBottomSheet<Employee>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // 🔎 حَقل بَحث حَيّ بِالاسم/الكود/المُسَمّى
        String query = '';
        final searchCtrl = TextEditingController();
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            expand: false,
            builder: (_, controller) => StatefulBuilder(
              builder: (ctx2, setSt) {
                final q = query.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? candidates
                    : candidates.where((c) {
                        final jt = c.jobTitleId == null
                            ? null
                            : repo.jobTitleById(c.jobTitleId);
                        final jtName =
                            jt?.displayName(isAr).toLowerCase() ?? '';
                        return c.fullName.toLowerCase().contains(q) ||
                            c.code.toLowerCase().contains(q) ||
                            jtName.contains(q);
                      }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.person_add_alt_outlined,
                              color: AppColors.brand, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'اختر موظفاً لـ "${point.name}"'
                                  : 'Pick employee for "${point.name}"',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    // 🔎 شَريط البَحث الجَديد
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: false,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setSt(() => query = '');
                                  },
                                ),
                          hintText: isAr
                              ? 'بَحث بِالاسم أَو الكود أَو المُسَمَّى…'
                              : 'Search by name, code, or job title…',
                          hintStyle: const TextStyle(fontSize: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onChanged: (v) => setSt(() => query = v),
                      ),
                    ),
                    // مُلَخَّص: كَم نَتيجة ظَهَرَت
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            isAr
                                ? '${filtered.length} مِن ${candidates.length} مُوَظَّف'
                                : '${filtered.length} of ${candidates.length} employees',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 40,
                                        color: Colors.grey[400]),
                                    const SizedBox(height: 8),
                                    Text(
                                      isAr
                                          ? 'لا تُوجَد نَتائج'
                                          : 'No results',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: controller,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                final cJt = c.jobTitleId == null
                                    ? null
                                    : repo.jobTitleById(c.jobTitleId);
                                final isL4 = cJt?.level == 4;
                                return ListTile(
                                  leading: AppAvatar(
                                    initials: c.initials,
                                    color: isL4
                                        ? AppColors.success
                                        : AppColors.brand,
                                  ),
                                  title: Text(c.fullName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  subtitle: Text(
                                    '${c.code} • ${cJt?.displayName(isAr) ?? "?"}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[700]),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isL4
                                          ? AppColors.success.withOpacity(0.15)
                                          : AppColors.brand.withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isL4
                                          ? (isAr ? '🎖️ سيُرقّى' : '🎖️ Promote')
                                          : (isAr ? 'L3' : 'L3'),
                                      style: TextStyle(
                                        color: isL4
                                            ? AppColors.success
                                            : AppColors.brand,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, c),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (picked == null) return;
    if (!context.mounted) return;

    // 🆕 تَنفيذ الربط — Supabase أَوَّلاً ثُمّ الذاكِرة (نَفس نَمَط _assignTo)
    // 🐛 DEBUG: طَبع رَسائل لِلتَأَكُّد من تَنفيذ الكود الجَديد
    // ignore: avoid_print
    print('🔗 [LINK-DEBUG] empId=${picked.id} pointId=${point.id} '
        'code=${picked.code}');
    final supaReady = SupabaseService().isReady;
    // ignore: avoid_print
    print('🔗 [LINK-DEBUG] supaReady=$supaReady');
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.assignEmployeeToSite(picked.id, point.id);
      // ignore: avoid_print
      print('🔗 [LINK-DEBUG] assignEmployeeToSite returned: $ok '
          'lastError=${ds.lastError}');
      if (!ok) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(ds.lastError ??
              (isAr ? 'فَشِل الحِفظ في Supabase' : 'Failed to save')),
        ));
        return;
      }
    } else {
      picked.pointId = point.id;
      repo.updateEmployee(picked);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
        isAr
            ? '✅ ${picked.fullName} مرتبط بـ ${point.name}'
            : '✅ ${picked.fullName} linked to ${point.name}',
      ),
    ));
  }
}

class _LinkedEmployeeRow extends StatelessWidget {
  final Employee employee;
  final Point point;
  final bool isAr;
  const _LinkedEmployeeRow({
    required this.employee,
    required this.point,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final base = employee.jobTitleId == null
        ? null
        : repo.jobTitleById(employee.jobTitleId);
    final isPromoted = repo.isPromoted(employee);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isPromoted
            ? AppColors.success.withOpacity(0.06)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          AppAvatar(
            initials: employee.initials,
            color: isPromoted ? AppColors.success : AppColors.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        employee.fullName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPromoted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.workspace_premium_outlined,
                                color: Colors.white, size: 9),
                            SizedBox(width: 2),
                            Text('L3',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                  ],
                ),
                Text(
                  '${employee.code}${base != null ? " • ${base.displayName(isAr)}" : ""}',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey[700]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 🆕 زرّ فكّ الربط — مَحميّ بصلاحيّة تعديل الإسناد
          Builder(builder: (ctx) {
            final auth = ctx.watch<AuthProvider>();
            final canAssign = auth.isSuperAdmin ||
                auth.permissions.contains(P.orgPointAssignmentEdit) ||
                auth.permissions.contains(P.busesAssign);
            if (!canAssign) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.link_off,
                  color: AppColors.danger, size: 16),
              tooltip: isAr ? 'فك الربط' : 'Unlink',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              onPressed: () => _unlink(context),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _unlink(BuildContext context) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '↩️ فك الربط؟' : '↩️ Unlink?'),
        content: Text(
          isAr
              ? 'سيُلغى ربط ${employee.fullName} بـ ${point.name}.'
              : 'Will unlink ${employee.fullName} from ${point.name}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'فك' : 'Unlink'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // 🆕 Supabase أَوَّلاً ثُمّ الذاكِرة
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final saved = await ds.assignEmployeeToSite(employee.id, null);
      if (!saved) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(ds.lastError ??
              (isAr ? 'فَشِل الحِفظ في Supabase' : 'Failed to save')),
        ));
        return;
      }
    } else {
      employee.pointId = null;
      employee.siteId = null;
      MockRepository().updateEmployee(employee);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
          isAr ? '✓ تمّ فك الربط' : '✓ Unlinked'),
    ));
  }
}
