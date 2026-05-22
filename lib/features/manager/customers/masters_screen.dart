import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../shared/permission_gate.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_toolbar.dart';
import 'clients_screen.dart' show showClientEditor;
import 'customers_excel_io.dart';
import 'master_report_screen.dart';
import 'sites_excel_io.dart';

/// شاشة إدارة العملاء - عرض شجري:
///   Master (الاسم التجاري) ← قابل للتوسعة
///     └─ Client 1 (فرع)
///     └─ Client 2 (فرع)
class MastersScreen extends StatefulWidget {
  const MastersScreen({super.key});

  @override
  State<MastersScreen> createState() => _MastersScreenState();
}

enum _StatusFilter { all, active, inactive }

class _MastersScreenState extends State<MastersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _expanded = {};
  _StatusFilter _statusFilter = _StatusFilter.all;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    var list = auth.activeCountryId == null
        ? [...repo.masters]
        : repo.masters
            .where((m) => m.countryId == auth.activeCountryId)
            .toList();
    // 🆕 فِلتَر الحالة
    if (_statusFilter == _StatusFilter.active) {
      list = list.where((m) => m.status == EntityStatus.active).toList();
    } else if (_statusFilter == _StatusFilter.inactive) {
      list = list.where((m) => m.status != EntityStatus.active).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((m) {
        if (m.name.toLowerCase().contains(q)) return true;
        if (m.code.toLowerCase().contains(q)) return true;
        // ابحث أيضاً في عملاء هذا Master
        final clients = repo.sites.where((c) => c.masterId == m.id);
        return clients.any((c) =>
            c.companyName.toLowerCase().contains(q) ||
            c.shortName.toLowerCase().contains(q));
      }).toList();
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    // 🆕 إحصائيّات لِشَريط الرَأس (بَعد فِلتَر الدَولة، قَبل فِلتَر الحالة)
    final scopedMasters = auth.activeCountryId == null
        ? repo.masters
        : repo.masters.where((m) => m.countryId == auth.activeCountryId);
    final activeMasters =
        scopedMasters.where((m) => m.status == EntityStatus.active).length;
    final inactiveMasters = scopedMasters.length - activeMasters;
    final allClients = repo.sites
        .where((c) => scopedMasters.any((m) => m.id == c.masterId))
        .toList();
    final allPoints = repo.points.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ===== 🆕 شَريط الإحصائيّات =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _StatsBanner(
              total: scopedMasters.length,
              active: activeMasters,
              inactive: inactiveMasters,
              clients: allClients.length,
              points: allPoints,
            ),
          ),
          // ===== 🆕 شَريط الأَدَوات لِلعُملاء (Masters) =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: _Toolbar(
              busy: _busy,
              onImport: _onImport,
              onExport: () => _onExport(list),
              onTemplate: _onTemplate,
              isAr: s.isAr,
            ),
          ),
          // ===== 🆕 شَريط أَدَوات الفُروع (Sites/Branches) =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    s.isAr ? 'فُروع:' : 'Branches:',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w900,
                        fontSize: 10),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: M7Toolbar(
                    busy: _busy,
                    actions: M7StandardActions.ioActions(
                      isAr: s.isAr,
                      onTemplate: _onBranchesTemplate,
                      onImport: _onBranchesImport,
                      onExport: () => _onBranchesExport(allClients),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ===== شَريط البَحث + الفِلتَر =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: s.isAr
                        ? 'بحث في الأسماء التجارية والفروع...'
                        : 'Search masters and branches...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.surface2Dark
                        : AppColors.surface2Light,
                  ),
                ),
                const SizedBox(height: 8),
                // 🆕 فِلتَر الحالة
                Row(
                  children: [
                    M7FilterPill(
                      label: s.isAr ? 'الكُلّ' : 'All',
                      count: scopedMasters.length,
                      selected: _statusFilter == _StatusFilter.all,
                      color: AppColors.brand,
                      onTap: () => setState(
                          () => _statusFilter = _StatusFilter.all),
                    ),
                    const SizedBox(width: 6),
                    M7FilterPill(
                      label: s.isAr ? 'نَشِط' : 'Active',
                      count: activeMasters,
                      selected: _statusFilter == _StatusFilter.active,
                      color: AppColors.success,
                      onTap: () => setState(
                          () => _statusFilter = _StatusFilter.active),
                    ),
                    const SizedBox(width: 6),
                    M7FilterPill(
                      label: s.isAr ? 'مُعَطَّل' : 'Inactive',
                      count: inactiveMasters,
                      selected: _statusFilter == _StatusFilter.inactive,
                      color: Colors.red,
                      onTap: () => setState(
                          () => _statusFilter = _StatusFilter.inactive),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ===== List شجري =====
          Expanded(
            child: list.isEmpty
                ? _empty(s, isDark)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final m = list[i];
                      final isExpanded = _expanded.contains(m.id) ||
                          _query.trim().isNotEmpty;
                      return _MasterTile(
                        master: m,
                        expanded: isExpanded,
                        isDark: isDark,
                        onToggle: () => setState(() {
                          if (_expanded.contains(m.id)) {
                            _expanded.remove(m.id);
                          } else {
                            _expanded.add(m.id);
                          }
                        }),
                        onEdit: () => _openMasterEditor(existing: m),
                        onDelete: () => _confirmDeleteMaster(m),
                        onAddClient: () => _addClientForMaster(m),
                        onReport: () => _openReport(m),
                        onToggleStatus: () => _toggleMasterStatus(m),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.sitesCreate,
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.brand,
          onPressed: () => _openMasterEditor(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            s.isAr ? 'اسم تجاري جديد' : 'New Master',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _empty(AppStrings s, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined,
              size: 56,
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight),
          const SizedBox(height: 12),
          Text(
            s.isAr ? 'لا توجد أسماء تجارية' : 'No masters yet',
            style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight),
          ),
          const SizedBox(height: 6),
          Text(
            s.isAr
                ? 'ابدأ بإضافة اسم تجاري، ثم أضف الفروع تحته'
                : 'Start by adding a Master, then branches under it',
            style: TextStyle(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
                fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _openMasterEditor({Master? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MasterEditor(existing: existing),
    );
  }

  void _addClientForMaster(Master master) {
    showClientEditor(context, prefilledMaster: master);
  }

  Future<void> _confirmDeleteMaster(Master m) async {
    final s = AppStrings.of(context);
    final clientsCount =
        MockRepository().sites.where((c) => c.masterId == m.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'حذف الاسم التجاري' : 'Delete Master'),
        content: Text(s.isAr
            ? 'سيتم حذف ${m.name}${clientsCount > 0 ? "\n$clientsCount فرع/عميل سيُفقَد ربطه" : ""}. متابعة؟'
            : 'Will delete ${m.name}${clientsCount > 0 ? "\n$clientsCount client(s) will lose link" : ""}. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok == true) {
      if (SupabaseService().isReady) {
        await SupabaseDataService().deleteMaster(m.id);
      } else {
        MockRepository().masters.removeWhere((x) => x.id == m.id);
        MockRepository().notifyListeners();
      }
      // 🆕 سِجِلّ التَدقيق
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      AuditLogService.instance.log(
        action: AuditAction.delete,
        entityType: 'master',
        entityId: m.id,
        entityName: m.name,
        actorId: auth.account?.id,
        actorName: auth.account?.fullName,
        summary: 'Master deleted',
        countryId: m.countryId,
      );
    }
  }

  // ============================================================
  // 🆕 فَتح تَقرير اسم تِجاريّ
  // ============================================================
  void _openReport(Master m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MasterReportScreen(master: m),
    ));
  }

  // ============================================================
  // 🆕 تَفعيل/إيقاف اسم تِجاريّ
  // ============================================================
  Future<void> _toggleMasterStatus(Master m) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final willActivate = m.status != EntityStatus.active;
    final newStatus =
        willActivate ? EntityStatus.active : EntityStatus.inactive;
    // عَدّ الفُروع المُتأَثِّرة
    final clientsCount =
        MockRepository().sites.where((c) => c.masterId == m.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          willActivate ? Icons.check_circle : Icons.cancel,
          color: willActivate ? AppColors.success : Colors.red,
          size: 36,
        ),
        title: Text(willActivate
            ? (isAr ? 'تَفعيل الاسم التِجاريّ' : 'Activate Master')
            : (isAr ? 'إيقاف الاسم التِجاريّ' : 'Deactivate Master')),
        content: Text(
          willActivate
              ? (isAr
                  ? 'سيُعاد تَفعيل ${m.name}. هَل أَنت مُتأَكِّد؟'
                  : 'Will reactivate ${m.name}. Confirm?')
              : (isAr
                  ? 'سيُوقَف ${m.name}${clientsCount > 0 ? "\nقَد يُؤَثِّر عَلى $clientsCount فَرع/عَميل" : ""}. هَل أَنت مُتأَكِّد؟'
                  : 'Will deactivate ${m.name}${clientsCount > 0 ? "\nMay affect $clientsCount client(s)" : ""}. Confirm?'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  willActivate ? AppColors.success : Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(willActivate
                ? (isAr ? 'تَفعيل' : 'Activate')
                : (isAr ? 'إيقاف' : 'Deactivate')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final oldStatus = m.status;
    m.status = newStatus;
    if (SupabaseService().isReady) {
      await SupabaseDataService().updateMaster(m);
    }
    MockRepository().notifyListeners();
    // 🆕 سَجِّل في سِجِلّ التَدقيق
    final auth = context.read<AuthProvider>();
    AuditLogService.instance.log(
      action: willActivate ? AuditAction.activate : AuditAction.deactivate,
      entityType: 'master',
      entityId: m.id,
      entityName: m.name,
      actorId: auth.account?.id,
      actorName: auth.account?.fullName,
      summary: willActivate
          ? 'Master activated'
          : 'Master deactivated',
      diff: {'status': '${oldStatus.name} → ${newStatus.name}'},
      countryId: m.countryId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          willActivate ? AppColors.success : Colors.red,
      content: Text(willActivate
          ? (isAr ? '✅ تَمّ التَفعيل' : '✅ Activated')
          : (isAr ? '⛔ تَمّ الإيقاف' : '⛔ Deactivated')),
    ));
  }

  // ============================================================
  // 🆕 استيراد/تَصدير/قالَب
  // ============================================================
  Future<void> _onImport() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    setState(() => _busy = true);
    final result = await CustomersExcelIO.importMasters();
    if (!mounted) return;
    setState(() => _busy = false);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          result.imported > 0 ? Icons.check_circle : Icons.warning_amber,
          color: result.imported > 0 ? AppColors.success : Colors.orange,
          size: 36,
        ),
        title:
            Text(isAr ? 'نَتيجة الاستيراد' : 'Import Result'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  isAr
                      ? 'تَمّ استيراد ${result.imported} اسم تِجاريّ'
                      : 'Imported: ${result.imported}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  isAr
                      ? 'تَجاوُز: ${result.skipped}'
                      : 'Skipped: ${result.skipped}',
                  style: const TextStyle(color: Colors.grey)),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(isAr ? 'الأَخطاء:' : 'Errors:',
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w800)),
                ...result.errors.take(10).map((e) => Text('• $e',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.red))),
                if (result.errors.length > 10)
                  Text('… +${result.errors.length - 10}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isAr ? 'حَسَناً' : 'OK')),
        ],
      ),
    );
  }

  Future<void> _onExport(List<Master> masters) async {
    if (masters.isEmpty) {
      final s = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(s.isAr ? 'لا تُوجَد بَيانات لِلتَصدير' : 'No data to export'),
      ));
      return;
    }
    setState(() => _busy = true);
    await CustomersExcelIO.exportMasters(masters);
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تَمّ التَصدير (${masters.length} عَميل)'
          : '✅ Exported (${masters.length} masters)'),
    ));
  }

  Future<void> _onTemplate() async {
    setState(() => _busy = true);
    await CustomersExcelIO.downloadTemplate();
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      content: Text(s.isAr ? '📋 تَمّ تَنزيل القالَب' : '📋 Template downloaded'),
    ));
  }

  // ============================================================
  // 🆕 Branches Import / Export / Template
  // ============================================================
  Future<void> _onBranchesTemplate() async {
    setState(() => _busy = true);
    await SitesExcelIO.downloadTemplate();
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      content: Text(
          s.isAr ? '📋 تَمّ تَنزيل قالَب الفُروع' : '📋 Branches template'),
    ));
  }

  Future<void> _onBranchesImport() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final result =
        await SitesExcelIO.importSites(countryId: auth.activeCountryId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.cancelled) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          result.imported > 0 ? Icons.check_circle : Icons.warning_amber,
          color: result.imported > 0 ? AppColors.success : Colors.orange,
          size: 36,
        ),
        title: Text(isAr ? 'استيراد الفُروع' : 'Import Branches'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAr ? 'تَمّ: ${result.imported}' : 'Imported: ${result.imported}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(isAr ? 'تَجاوُز: ${result.skipped}' : 'Skipped: ${result.skipped}',
                style: const TextStyle(color: Colors.grey)),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...result.errors.take(8).map((e) => Text('• $e',
                  style: const TextStyle(fontSize: 11, color: Colors.red))),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isAr ? 'حَسَناً' : 'OK')),
        ],
      ),
    );
  }

  Future<void> _onBranchesExport(List<Site> sites) async {
    final s = AppStrings.of(context);
    if (sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(s.isAr ? 'لا تُوجَد فُروع' : 'No branches'),
      ));
      return;
    }
    setState(() => _busy = true);
    await SitesExcelIO.exportSites(sites);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تَمّ تَصدير ${sites.length} فَرع'
          : '✅ Exported ${sites.length} branches'),
    ));
  }
}

// ============================================================
// كارد Master قابل للتوسعة + قائمة فروعه (Clients)
// ============================================================
class _MasterTile extends StatelessWidget {
  final Master master;
  final bool expanded;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddClient;
  final VoidCallback onReport;
  final VoidCallback onToggleStatus;

  const _MasterTile({
    required this.master,
    required this.expanded,
    required this.isDark,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onAddClient,
    required this.onReport,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final country = repo.countryById(master.countryId);
    final clients = repo.sites
        .where((c) => c.masterId == master.id)
        .toList()
      ..sort((a, b) => a.companyName.compareTo(b.companyName));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: expanded
                ? AppColors.brand.withValues(alpha: 0.5)
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: expanded ? 1.2 : 0.5),
      ),
      child: Column(
        children: [
          // ===== رأس الـ Master =====
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // أيقونة + سهم
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.business,
                          color: AppColors.brand, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            master.name,
                            style: TextStyle(
                                color: isDark
                                    ? AppColors.textDark
                                    : AppColors.textLight,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (master.code.isNotEmpty)
                                _Chip(
                                    text: master.code,
                                    color: AppColors.brand,
                                    mono: true),
                              if (country != null)
                                _Chip(
                                    text: country.code,
                                    color: AppColors.success),
                              _Chip(
                                  text: s.isAr
                                      ? '${clients.length} فرع'
                                      : '${clients.length} branches',
                                  color: AppColors.info),
                              // 🆕 شارة الحالة
                              _Chip(
                                text: master.status == EntityStatus.active
                                    ? (s.isAr ? 'نَشِط' : 'Active')
                                    : (s.isAr ? 'مُعَطَّل' : 'Inactive'),
                                color: master.status == EntityStatus.active
                                    ? AppColors.success
                                    : Colors.red,
                              ),
                              if (master.autoCreated)
                                _Chip(
                                    text: s.isAr ? 'تلقائي' : 'auto',
                                    color: AppColors.warning),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: AppColors.brand, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ===== المحتوى المفتوح =====
          if (expanded) ...[
            const Divider(height: 1),
            // أَزرار سَريعة
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit, size: 14),
                    label: Text(
                      s.isAr ? 'تَعديل' : 'Edit',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: onEdit,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(
                      s.isAr ? 'فَرع جَديد' : 'Add Branch',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: onAddClient,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                  // 🆕 تَقرير
                  OutlinedButton.icon(
                    icon: const Icon(Icons.assessment, size: 14),
                    label: Text(
                      s.isAr ? 'تَقرير' : 'Report',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: onReport,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                    ),
                  ),
                  // 🆕 تَفعيل/إيقاف
                  OutlinedButton.icon(
                    icon: Icon(
                      master.status == EntityStatus.active
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      size: 14,
                    ),
                    label: Text(
                      master.status == EntityStatus.active
                          ? (s.isAr ? 'إيقاف' : 'Deactivate')
                          : (s.isAr ? 'تَفعيل' : 'Activate'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: onToggleStatus,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          master.status == EntityStatus.active
                              ? Colors.red
                              : AppColors.success,
                      side: BorderSide(
                          color: master.status == EntityStatus.active
                              ? Colors.red
                              : AppColors.success),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.danger),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // قائمة الفروع
            if (clients.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                        width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.isAr
                              ? 'لا توجد فروع لهذا الاسم التجاري بعد. اضغط "فرع جديد" لإضافة أول فرع.'
                              : 'No branches yet. Tap "Add Branch" to create the first one.',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  children: clients.map((c) => _ClientRow(client: c)).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// صف عميل (داخل Master)
// ============================================================
class _ClientRow extends StatelessWidget {
  final Site client;
  const _ClientRow({required this.client});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // عدد النقاط المرتبطة بهذا العميل
    final pointsCount = repo.points
        .where((p) =>
            p.linkedClients.any((l) => l.clientId == client.id))
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surface2Dark.withValues(alpha: 0.5)
            : AppColors.surface2Light,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showClientEditor(context, existing: client),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: (client.status == EntityStatus.active
                            ? AppColors.success
                            : Colors.red)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.storefront,
                      color: client.status == EntityStatus.active
                          ? AppColors.success
                          : Colors.red,
                      size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              client.companyName,
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.textDark
                                      : AppColors.textLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  decoration: client.status ==
                                          EntityStatus.active
                                      ? null
                                      : TextDecoration.lineThrough),
                            ),
                          ),
                          if (client.status != EntityStatus.active) ...[
                            const SizedBox(width: 4),
                            const _Chip(
                                text: 'OFF', color: Colors.red, mono: true),
                          ],
                        ],
                      ),
                      if (client.shortName.isNotEmpty)
                        Text(
                          client.shortName,
                          style: const TextStyle(
                              color: AppColors.textTertiaryLight,
                              fontFamily: 'monospace',
                              fontSize: 10),
                        ),
                    ],
                  ),
                ),
                if (pointsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place,
                            size: 10, color: AppColors.warning),
                        const SizedBox(width: 3),
                        Text(
                          s.isAr
                              ? '$pointsCount نقطة'
                              : '$pointsCount points',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 16,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool mono;
  const _Chip({
    required this.text,
    required this.color,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    );
  }
}

// ============================================================
// شيت إنشاء/تعديل Master
// ============================================================
class _MasterEditor extends StatefulWidget {
  final Master? existing;
  const _MasterEditor({this.existing});

  @override
  State<_MasterEditor> createState() => _MasterEditorState();
}

class _MasterEditorState extends State<_MasterEditor> {
  final _name = TextEditingController();
  final _tradeLicense = TextEditingController();
  final _taxVat = TextEditingController();
  final _notes = TextEditingController();
  String? _businessTypeId;
  String? _countryId;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (widget.existing != null) {
      final m = widget.existing!;
      _name.text = m.name;
      _tradeLicense.text = m.tradeLicense;
      _taxVat.text = m.taxVat;
      _notes.text = m.notes;
      _businessTypeId = m.industryId;
      _countryId = m.countryId;
    } else {
      _countryId = auth.activeCountryId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tradeLicense.dispose();
    _taxVat.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_name.text.trim().isEmpty) {
      _toast(s.isAr ? 'الاسم مطلوب' : 'Name is required');
      return;
    }
    if (_countryId == null) {
      _toast(s.isAr ? 'الدولة مطلوبة' : 'Country is required');
      return;
    }
    final repo = MockRepository();
    final dataService = SupabaseDataService();
    final supaReady = SupabaseService().isReady;

    if (isEdit) {
      final m = widget.existing!;
      m.name = _name.text.trim();
      m.tradeLicense = _tradeLicense.text.trim();
      m.taxVat = _taxVat.text.trim();
      m.notes = _notes.text.trim();
      m.industryId = _businessTypeId;
      m.countryId = _countryId!;
      if (supaReady) {
        final ok = await dataService.updateMaster(m);
        if (!ok) {
          _toast(dataService.lastError ?? 'Failed', isError: true);
          return;
        }
      }
      repo.notifyListeners();
    } else {
      String? code;
      if (supaReady) {
        code = await dataService.consumeNextCode(
            technicalId: 'master', countryId: _countryId!);
      }
      code ??= 'M-?';

      final m = Master(
        id: repo.generateId(),
        code: code,
        name: _name.text.trim(),
        tradeLicense: _tradeLicense.text.trim(),
        taxVat: _taxVat.text.trim(),
        notes: _notes.text.trim(),
        industryId: _businessTypeId,
        countryId: _countryId!,
      );
      if (supaReady) {
        final created = await dataService.createMaster(m);
        if (created == null) {
          _toast(dataService.lastError ?? 'Failed', isError: true);
          return;
        }
      } else {
        repo.addMaster(m);
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (s.isAr
                              ? 'تعديل اسم تجاري'
                              : 'Edit Master')
                          : (s.isAr
                              ? 'اسم تجاري جديد'
                              : 'New Master'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'الاسم التجاري *'
                          : 'Trade Name *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _countryId,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'الدولة *' : 'Country *',
                      border: const OutlineInputBorder(),
                    ),
                    items: repo.countries
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(s.isAr ? c.nameAr : c.nameEn),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _countryId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _businessTypeId,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'نوع النشاط (اختياري)'
                          : 'Business Type (optional)',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          s.isAr ? 'بدون' : 'None',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                      ...repo.businessTypes.map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(s.isAr ? b.nameAr : b.nameEn),
                          )),
                    ],
                    onChanged: (v) => setState(() => _businessTypeId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tradeLicense,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'رخصة تجارية'
                          : 'Trade License',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxVat,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'الرقم الضريبي'
                          : 'Tax / VAT',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'ملاحظات' : 'Notes',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'حفظ' : 'Save')
                          : (s.isAr
                              ? 'إنشاء الاسم التجاري'
                              : 'Create Master'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 شَريط الإحصائيّات (Stats Banner)
// ============================================================
class _StatsBanner extends StatelessWidget {
  final int total;
  final int active;
  final int inactive;
  final int clients;
  final int points;
  const _StatsBanner({
    required this.total,
    required this.active,
    required this.inactive,
    required this.clients,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.10),
            AppColors.gold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatBox(
                icon: Icons.business,
                label: isAr ? 'إجمالي' : 'Total',
                value: total,
                color: AppColors.brand),
          ),
          Container(
              width: 1, height: 38, color: Colors.grey.withValues(alpha: 0.2)),
          Expanded(
            child: _StatBox(
                icon: Icons.check_circle,
                label: isAr ? 'نَشِط' : 'Active',
                value: active,
                color: AppColors.success),
          ),
          Container(
              width: 1, height: 38, color: Colors.grey.withValues(alpha: 0.2)),
          Expanded(
            child: _StatBox(
                icon: Icons.cancel,
                label: isAr ? 'مُعَطَّل' : 'Inactive',
                value: inactive,
                color: Colors.red),
          ),
          Container(
              width: 1, height: 38, color: Colors.grey.withValues(alpha: 0.2)),
          Expanded(
            child: _StatBox(
                icon: Icons.storefront,
                label: isAr ? 'فُروع' : 'Branches',
                value: clients,
                color: AppColors.info),
          ),
          Container(
              width: 1, height: 38, color: Colors.grey.withValues(alpha: 0.2)),
          Expanded(
            child: _StatBox(
                icon: Icons.place,
                label: isAr ? 'نُقاط' : 'Points',
                value: points,
                color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text('$value',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                fontFamily: 'monospace')),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ============================================================
// 🆕 شَريط الأَدَوات (Toolbar)
// ============================================================
class _Toolbar extends StatelessWidget {
  final bool busy;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onTemplate;
  final bool isAr;
  const _Toolbar({
    required this.busy,
    required this.onImport,
    required this.onExport,
    required this.onTemplate,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
          height: 32, child: Center(child: LinearProgressIndicator()));
    }
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _ToolBtn(
              icon: Icons.file_download,
              label: isAr ? 'تَنزيل القالَب' : 'Template',
              color: AppColors.info,
              onTap: onTemplate),
          const SizedBox(width: 6),
          _ToolBtn(
              icon: Icons.upload_file,
              label: isAr ? 'استيراد' : 'Import',
              color: AppColors.brand,
              onTap: onImport),
          const SizedBox(width: 6),
          _ToolBtn(
              icon: Icons.file_open,
              label: isAr ? 'تَصدير Excel' : 'Export Excel',
              color: AppColors.success,
              onTap: onExport),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// 💡 _FilterChip أُزيلَت — استُبدِلَت بِـ M7FilterPill في lib/shared/m7_toolbar.dart
