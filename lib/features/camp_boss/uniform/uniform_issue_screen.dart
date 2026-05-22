import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/camp_uniform_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/country_guard.dart';
import '../../../shared/permission_gate.dart';
import '../camp_palette.dart';
import 'uniform_employee_card.dart';
import 'uniform_issue_voucher.dart';
import 'uniform_shared.dart';

/// 🤝 شاشة سندات الصرف للموظفين
class UniformIssueScreen extends StatefulWidget {
  /// 🆕 لَو مُرِّر — تُعَبَّأ شاشة "صَرف جَديد" بِهذا المُوَظَّف تِلقائيّاً
  /// (يُستَخدَم من تابِ "يَنتَظِرون التَجهيز")
  final String? initialEmployeeId;

  /// 🆕 الأَصناف المُعَبَّأة مُسبَقاً — قائِمة [{item_id, qty}]
  /// (يُستَخدَم مِن تابِ "طَلَبات" لِيَنسَخ أَصناف الطَلَب)
  final List<Map<String, dynamic>>? initialItems;

  /// 🆕 ربط بِالطَلَب الأَصلِيّ (form_submission.id)
  final String? sourceFormSubmissionId;

  /// 🆕 رَقَم الطَلَب لِلعَرض في AppBar وَالنَسخ في notes
  final String? sourceFormNo;

  const UniformIssueScreen({
    super.key,
    this.initialEmployeeId,
    this.initialItems,
    this.sourceFormSubmissionId,
    this.sourceFormNo,
  });

  @override
  State<UniformIssueScreen> createState() => _UniformIssueScreenState();
}

class _UniformIssueScreenState extends State<UniformIssueScreen> {
  String _query = '';
  String _filter = 'all'; // all | pending | returned

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    // 🆕 إذا فُتِحَت بِمُوَظَّف مُحَدَّد:
    //   - فَلتِر القائِمة بِاسمه
    //   - افتَح مُحَرِّر الصَرف تِلقائيّاً وَالمُوَظَّف مُعَبَّأ
    if (widget.initialEmployeeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final emp = MockRepository().employeeById(widget.initialEmployeeId);
        if (emp != null) {
          setState(() => _query = emp.fullName);
          // 🆕 اِفتَح المُحَرِّر تِلقائيّاً فَقَط إذا الإعداد مُفَعَّل
          await CampUniformSettings.instance.load();
          if (!CampUniformSettings.instance.autoOpenEditorOnSetup) return;
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              _openEditor(
                preselectedEmployeeId: emp.id,
                preFilledItems: widget.initialItems,
                sourceFormSubmissionId: widget.sourceFormSubmissionId,
                sourceFormNo: widget.sourceFormNo,
              );
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
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

    final all = auth
        .filterByCountry(repo.employeeUniforms, (u) => u.countryId)
        .where((u) {
      if (_filter == 'pending' && u.isFullyReturned) return false;
      if (_filter == 'returned' && !u.isFullyReturned) return false;
      if (_query.trim().isNotEmpty) {
        final emp = repo.employeeById(u.employeeId);
        String itemName = '';
        try {
          final ui = repo.uniformCatalog
              .firstWhere((x) => x.id == u.uniformItemId);
          itemName = '${ui.nameAr} ${ui.nameEn}';
        } catch (_) {}
        return uniformMatchesQuery(_query, [
          u.issueNo,
          emp?.fullName ?? '',
          emp?.code ?? '',
          itemName,
        ]);
      }
      return true;
    }).toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));

    final pendingCount = repo.employeeUniforms.where((u) =>
        auth.isInScope(u.countryId) && !u.isFullyReturned).length;
    final returnedCount = repo.employeeUniforms.where((u) =>
        auth.isInScope(u.countryId) && u.isFullyReturned).length;

    return Scaffold(
      backgroundColor: CampPalette.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: UniformSearchBar(
              hint: s.isAr
                  ? 'بحث: رقم السند، الموظف، الصنف...'
                  : 'Search: issue no, employee, item...',
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                UniformFilterChip(
                  label: s.isAr ? 'الكل' : 'All',
                  count: all.length,
                  selected: _filter == 'all',
                  color: UniformPalette.primary,
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                UniformFilterChip(
                  label: s.isAr ? 'لم يُرجَع' : 'Pending',
                  count: pendingCount,
                  selected: _filter == 'pending',
                  color: UniformPalette.stockOut,
                  icon: Icons.pending_outlined,
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                const SizedBox(width: 6),
                UniformFilterChip(
                  label: s.isAr ? 'مُرجَع' : 'Returned',
                  count: returnedCount,
                  selected: _filter == 'returned',
                  color: UniformPalette.stockIn,
                  icon: Icons.check_circle_outline,
                  onTap: () => setState(() => _filter = 'returned'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: all.isEmpty
                ? UniformEmpty(
                    icon: Icons.handshake_outlined,
                    title: _query.isNotEmpty
                        ? (s.isAr ? 'لا نتائج' : 'No results')
                        : (s.isAr ? 'لا يوجد سندات صرف' : 'No issues'),
                    action: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UniformPalette.stockOut,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openEditor,
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(s.isAr ? 'صرف جديد' : 'New Issue'),
                    ),
                  )
                : Builder(builder: (_) {
                    // 🆕 تَجميع السُطور حَسَب رَقَم السَند
                    final groups = <String, List<EmployeeUniform>>{};
                    for (final u in all) {
                      final key = u.issueNo.isEmpty ? u.id : u.issueNo;
                      groups.putIfAbsent(key, () => []).add(u);
                    }
                    final keys = groups.keys.toList();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                      itemCount: keys.length,
                      itemBuilder: (_, i) => _IssueGroupCard(
                        issueNo: keys[i],
                        rows: groups[keys[i]]!,
                      ),
                    );
                  }),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.uniformIssueCreate,
        child: FloatingActionButton.extended(
          backgroundColor: UniformPalette.stockOut,
          onPressed: _openEditor,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(s.isAr ? 'صرف جديد' : 'New Issue',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  void _openEditor({
    String? preselectedEmployeeId,
    List<Map<String, dynamic>>? preFilledItems,
    String? sourceFormSubmissionId,
    String? sourceFormNo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IssueEditorSheet(
        initialEmployeeId: preselectedEmployeeId,
        initialItems: preFilledItems,
        sourceFormSubmissionId: sourceFormSubmissionId,
        sourceFormNo: sourceFormNo,
      ),
    );
  }
}

// ============================================================
// بطاقة سند صرف
// ============================================================
/// 🆕 بِطاقة سَند صَرف — تَجمَع كُلّ الأَصناف ذات نَفس issueNo في كارت واحِد
class _IssueGroupCard extends StatelessWidget {
  final String issueNo;
  final List<EmployeeUniform> rows;
  const _IssueGroupCard({required this.issueNo, required this.rows});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final first = rows.first;
    final emp = repo.employeeById(first.employeeId);

    final totalQty = rows.fold<int>(0, (a, r) => a + r.quantity);
    final returnedQty =
        rows.fold<int>(0, (a, r) => a + (r.returnQuantity ?? 0));
    final allReturned = rows.every((r) => r.isFullyReturned);
    final anyReturned = returnedQty > 0;
    final hasSig = first.signatureData != null &&
        first.signatureData!.isNotEmpty;

    final color = allReturned
        ? UniformPalette.stockIn
        : anyReturned
            ? UniformPalette.info
            : UniformPalette.stockOut;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UniformIssueVoucher(issueNo: issueNo),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الصَفّ العُلويّ
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              allReturned
                                  ? Icons.check_circle
                                  : Icons.handshake_outlined,
                              color: Colors.white,
                              size: 12),
                          const SizedBox(width: 4),
                          Text(issueNo,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    if (anyReturned && !allReturned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: UniformPalette.info.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                            isAr ? 'إرجاع جُزئيّ' : 'Partial Return',
                            style: const TextStyle(
                                color: UniformPalette.info,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                    if (hasSig) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.draw,
                                size: 9, color: AppColors.success),
                            SizedBox(width: 2),
                            Text('✓',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    const Icon(Icons.calendar_today,
                        size: 11, color: CampPalette.textSecondary),
                    const SizedBox(width: 3),
                    Text(formatDateShort(first.issueDate),
                        style: const TextStyle(
                            fontSize: 10,
                            color: CampPalette.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                // المُوَظَّف
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          UniformPalette.primary.withValues(alpha: 0.15),
                      child: Text(emp?.initials ?? '?',
                          style: const TextStyle(
                              color: UniformPalette.primary,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp?.fullName ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          if (emp != null)
                            Text(emp.code,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: CampPalette.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                          '${rows.length} ${isAr ? "صَنف" : "items"} · $totalQty',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // قائِمة الأَصناف
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: CampPalette.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 6, indent: 6, endIndent: 6),
                        _itemRow(repo, rows[i], isAr),
                      ],
                    ],
                  ),
                ),
                if ((first.issuedByName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 11, color: CampPalette.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                          '${isAr ? "صَرفها" : "By"}: ${first.issuedByName}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: CampPalette.textSecondary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // ===== أَزرار: سَند + تَعديل + حَذف (دائِماً) =====
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UniformPalette.primary,
                          side: BorderSide(
                              color:
                                  UniformPalette.primary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () => _openVoucher(context),
                        icon: const Icon(Icons.print_outlined, size: 14),
                        label: Text(isAr ? 'سَند + PDF' : 'Voucher',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PermissionGate(
                      permission: P.uniformIssueEdit,
                      child: IconButton(
                        tooltip: isAr ? 'تَعديل' : 'Edit',
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.info,
                          backgroundColor:
                              AppColors.info.withValues(alpha: 0.08),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(38, 32),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        onPressed: () => _openEdit(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PermissionGate(
                      permission: P.uniformIssueDelete,
                      child: IconButton(
                        tooltip: isAr ? 'حَذف' : 'Delete',
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          backgroundColor:
                              AppColors.danger.withValues(alpha: 0.08),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(38, 32),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        onPressed: () => _confirmDelete(context),
                      ),
                    ),
                    if (!allReturned) ...[
                      const SizedBox(width: 6),
                      PermissionGate(
                        permission: P.uniformIssueReturn,
                        child: IconButton(
                          tooltip: isAr ? 'إرجاع' : 'Return',
                          style: IconButton.styleFrom(
                            foregroundColor: UniformPalette.stockIn,
                            backgroundColor:
                                UniformPalette.stockIn.withValues(alpha: 0.08),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(38, 32),
                          ),
                          icon: const Icon(Icons.keyboard_return, size: 16),
                          onPressed: () => _openVoucher(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openVoucher(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UniformIssueVoucher(issueNo: issueNo),
    ));
  }

  /// تَعديل السَند: حَذف الحاليّ ثُمّ فَتح المُحَرِّر بِالبَيانات لِإعادة الحِفظ
  Future<void> _openEdit(BuildContext context) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.edit_note, color: AppColors.info, size: 36),
        title: Text(s.isAr ? 'تَعديل السَند' : 'Edit Voucher'),
        content: Text(
          s.isAr
              ? 'سَيُحذَف السَند الحاليّ ($issueNo) وَيُفتَح المُحَرِّر بِبَياناته لِتُعَدِّلها وَتَحفَظ سَنداً جَديداً.\n\nالمَخزون يُعاد تَلقائيّاً.'
              : 'Current voucher ($issueNo) will be deleted and the editor will open pre-filled. Stock auto-reverts.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            label: Text(s.isAr ? 'مُتابَعة' : 'Continue',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // اِجمَع البَيانات قَبل الحَذف
    final items = rows
        .map((r) => {'item_id': r.uniformItemId, 'qty': r.quantity})
        .toList();
    final empId = rows.first.employeeId;
    final notes = rows.first.notes;
    final sourceFormId = rows.first.sourceFormSubmissionId;

    // احذِف السَند الحاليّ
    final delOk = await SupabaseDataService().deleteIssueByNo(issueNo);
    if (!context.mounted) return;
    if (!delOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(SupabaseDataService().lastError ?? 'Delete failed'),
      ));
      return;
    }

    // افتَح شاشة الصَرف مَعَ البَيانات مُعَبَّأة
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UniformIssueScreen(
        initialEmployeeId: empId,
        initialItems: items,
        sourceFormSubmissionId: sourceFormId,
        sourceFormNo: notes,
      ),
    ));
  }

  /// حَذف السَند بَعد تَأكيد
  Future<void> _confirmDelete(BuildContext context) async {
    final s = AppStrings.of(context);
    final totalQty = rows.fold<int>(0, (a, r) => a + r.quantity);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber,
            color: AppColors.danger, size: 36),
        title: Text(s.isAr ? 'حَذف السَند؟' : 'Delete voucher?'),
        content: Text(
          s.isAr
              ? 'سَيُحذَف السَند $issueNo (${rows.length} صَنف، $totalQty قِطعة) وَتُعاد الكَمّيّات لِلمَخزون.\n\nهَل أَنت مُتَأَكِّد؟'
              : 'Will delete $issueNo (${rows.length} items, $totalQty pcs) and restore stock.\n\nAre you sure?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
            label: Text(s.isAr ? 'حَذف' : 'Delete',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success =
        await SupabaseDataService().deleteIssueByNo(issueNo);
    if (!context.mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(SupabaseDataService().lastError ?? 'Delete failed'),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✓ تَمّ حَذف السَند + إرجاع المَخزون'
          : '✓ Voucher deleted + stock restored'),
    ));
  }

  Widget _itemRow(MockRepository repo, EmployeeUniform line, bool isAr) {
    String name = '—';
    String size = '';
    try {
      final ui =
          repo.uniformCatalog.firstWhere((x) => x.id == line.uniformItemId);
      name = isAr ? ui.nameAr : ui.nameEn;
      size = ui.size;
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.checkroom,
              color: UniformPalette.primary, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (size.isNotEmpty || line.size.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: CampPalette.textSecondary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(line.size.isNotEmpty ? line.size : size,
                  style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: line.isFullyReturned
                  ? UniformPalette.stockIn
                  : line.isReturned
                      ? UniformPalette.info
                      : UniformPalette.stockOut,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
                line.isFullyReturned
                    ? '✓'
                    : line.isReturned
                        ? '${line.returnQuantity}/${line.quantity}'
                        : '× ${line.quantity}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final EmployeeUniform issue;
  const _IssueCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final emp = repo.employeeById(issue.employeeId);
    String itemName = '—';
    String itemSize = '';
    try {
      final ui = repo.uniformCatalog
          .firstWhere((x) => x.id == issue.uniformItemId);
      itemName = s.isAr ? ui.nameAr : ui.nameEn;
      itemSize = ui.size;
    } catch (_) {}

    final color = issue.isFullyReturned
        ? UniformPalette.stockIn
        : UniformPalette.stockOut;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UniformIssueVoucher(issueId: issue.id),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            issue.isFullyReturned
                                ? Icons.check_circle
                                : Icons.handshake_outlined,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                              issue.issueNo.isEmpty
                                  ? '—'
                                  : issue.issueNo,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    if (issue.isReturned && !issue.isFullyReturned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: UniformPalette.info.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                            s.isAr
                                ? 'إرجاع جزئي'
                                : 'Partial Return',
                            style: const TextStyle(
                                color: UniformPalette.info,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const Spacer(),
                    const Icon(Icons.calendar_today,
                        size: 11, color: CampPalette.textSecondary),
                    const SizedBox(width: 3),
                    Text(formatDateShort(issue.issueDate),
                        style: const TextStyle(
                            fontSize: 10,
                            color: CampPalette.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (emp != null) {
                          Navigator.of(context)
                              .push(MaterialPageRoute(
                            builder: (_) =>
                                UniformEmployeeCard(employeeId: emp.id),
                          ));
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            UniformPalette.primary.withValues(alpha: 0.15),
                        child: Text(emp?.initials ?? '?',
                            style: const TextStyle(
                                color: UniformPalette.primary,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp?.fullName ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          if (emp != null)
                            Text(emp.code,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: CampPalette.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CampPalette.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.checkroom,
                          color: UniformPalette.primary, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (issue.size.isNotEmpty || itemSize.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CampPalette.textSecondary
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                              issue.size.isNotEmpty ? issue.size : itemSize,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('×${issue.quantity}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                if ((issue.issuedByName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 11, color: CampPalette.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                          '${s.isAr ? "صرفها" : "By"}: ${issue.issuedByName}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: CampPalette.textSecondary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
                if (!issue.isFullyReturned) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: UniformPalette.stockIn,
                            side: BorderSide(
                                color: UniformPalette.stockIn
                                    .withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 6),
                          ),
                          onPressed: () =>
                              _openReturnDialog(context, issue),
                          icon:
                              const Icon(Icons.keyboard_return, size: 14),
                          label: Text(
                              s.isAr ? 'إرجاع' : 'Return',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: UniformPalette.primary,
                            side: BorderSide(
                                color: UniformPalette.primary
                                    .withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 6),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => UniformIssueVoucher(
                                  issueId: issue.id),
                            ));
                          },
                          icon: const Icon(Icons.print_outlined,
                              size: 14),
                          label: Text(
                              s.isAr ? 'سند' : 'Voucher',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openReturnDialog(
      BuildContext context, EmployeeUniform issue) async {
    final s = AppStrings.of(context);
    final qtyCtrl =
        TextEditingController(text: issue.pendingQuantity.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'إرجاع يونيفورم' : 'Return Uniform'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                s.isAr
                    ? 'الكمية المُصروفة: ${issue.quantity} · المُرجَعة سابقاً: ${issue.returnQuantity ?? 0}'
                    : 'Issued: ${issue.quantity} · Returned: ${issue.returnQuantity ?? 0}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: s.isAr ? 'الكمية المُرجَعة' : 'Return Quantity',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: UniformPalette.stockIn),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.isAr ? 'تأكيد الإرجاع' : 'Confirm Return'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final auth = context.read<AuthProvider>();
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    final total = (issue.returnQuantity ?? 0) + qty;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      await SupabaseDataService().returnEmployeeUniform(
        id: issue.id,
        returnQuantity: total > issue.quantity ? issue.quantity : total,
        returnedById: auth.account?.id,
        returnedByName: auth.account?.fullName,
      );
    } else {
      issue.returnDate = DateTime.now();
      issue.returnQuantity = total > issue.quantity ? issue.quantity : total;
      issue.returnedById = auth.account?.id;
      issue.returnedByName = auth.account?.fullName;
      MockRepository().notifyListeners();
    }
  }
}

// ============================================================
// مُحَرِّر سَند صَرف — مُتَعَدِّد الأَصناف (عُهدة الكَمب)
// ============================================================
class _IssueEditorSheet extends StatefulWidget {
  /// لَو مُرَّر، يُعَبِّأ المُوَظَّف تِلقائيّاً وَيُخفي شاشة اختِيار المُوَظَّف
  final String? initialEmployeeId;
  /// 🆕 أَصناف مُعَبَّأة مُسبَقاً [{item_id, qty}]
  final List<Map<String, dynamic>>? initialItems;
  /// 🆕 ربط بِنَموذَج طَلَب الزِيّ
  final String? sourceFormSubmissionId;
  final String? sourceFormNo;

  const _IssueEditorSheet({
    this.initialEmployeeId,
    this.initialItems,
    this.sourceFormSubmissionId,
    this.sourceFormNo,
  });

  @override
  State<_IssueEditorSheet> createState() => _IssueEditorSheetState();
}

/// سَطر صَنف داخِل سَند الصَرف
class _IssueLine {
  String? itemId;
  int quantity = 1;
  final TextEditingController qtyCtrl = TextEditingController(text: '1');

  void dispose() => qtyCtrl.dispose();
}

class _IssueEditorSheetState extends State<_IssueEditorSheet> {
  String? _employeeId;
  final _notes = TextEditingController();
  String _empSearch = '';
  bool _saving = false;
  final List<_IssueLine> _lines = [];

  @override
  void initState() {
    super.initState();
    // 🆕 لَو فُتِحَت الشاشة مَع مُوَظَّف مُحَدَّد، عَبِّئه تِلقائيّاً
    if (widget.initialEmployeeId != null) {
      _employeeId = widget.initialEmployeeId;
    }
    // 🆕 لَو فُتِحَت مَع أَصناف مُعَبَّأة مُسبَقاً (مِن طَلَب زِيّ)
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      for (final raw in widget.initialItems!) {
        final id = raw['item_id']?.toString();
        if (id == null) continue;
        final qty = (raw['qty'] as num?)?.toInt() ?? 1;
        final line = _IssueLine()
          ..itemId = id
          ..quantity = qty;
        line.qtyCtrl.text = qty.toString();
        _lines.add(line);
      }
      // أَضِف notes تِلقائيّاً مَع رَقَم الطَلَب
      if (widget.sourceFormNo != null) {
        _notes.text = 'صَرف طَلَب: ${widget.sourceFormNo}';
      }
    }
    // ضَمان وُجود سَطر فارِغ عَلى الأَقَلّ
    if (_lines.isEmpty) {
      _lines.add(_IssueLine());
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_IssueLine()));
  void _removeLine(int i) {
    setState(() {
      final l = _lines.removeAt(i);
      l.dispose();
    });
  }

  /// عَرض مُحَرِّر سَطر صَنف داخِل سَند الصَرف
  Widget _buildLineEditor(
    _IssueLine line,
    int index,
    List<UniformItem> items,
    MockRepository repo,
    String? countryId,
    bool isAr,
  ) {
    final stock = line.itemId == null
        ? 0
        : repo.uniformCurrentStock(line.itemId!, countryId: countryId);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: line.itemId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الصَنف *' : 'Item *',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: items
                      .map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(
                              '${isAr ? u.nameAr : u.nameEn}${u.size.isEmpty ? "" : " · ${u.size}"} (${repo.uniformCurrentStock(u.id, countryId: countryId)})',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => line.itemId = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: line.qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الكَمّيّة' : 'Qty',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() {
                    line.quantity = int.tryParse(v) ?? 0;
                  }),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
                onPressed: () => _removeLine(index),
              ),
            ],
          ),
          if (line.itemId != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  stock <= 0 ? Icons.error_outline : Icons.inventory_2,
                  size: 12,
                  color: stock <= 0
                      ? UniformPalette.danger
                      : UniformPalette.stockIn,
                ),
                const SizedBox(width: 4),
                Text(
                  isAr
                      ? 'مُتَوَفِّر: $stock'
                      : 'In stock: $stock',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: stock <= 0
                        ? UniformPalette.danger
                        : UniformPalette.stockIn,
                  ),
                ),
                if (line.quantity > stock) ...[
                  const Spacer(),
                  Text(
                    isAr
                        ? '⚠️ كَمّيّة أَكبَر مِن المُتَوَفِّر'
                        : '⚠️ Exceeds stock',
                    style: const TextStyle(
                        fontSize: 10,
                        color: UniformPalette.danger,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.isAr ? 'اختَر المُوَظَّف' : 'Select employee')));
      return;
    }
    final validLines = _lines
        .where((l) => l.itemId != null && l.quantity > 0)
        .toList();
    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: UniformPalette.danger,
          content: Text(s.isAr
              ? 'أَضِف صَنفاً واحِداً على الأَقَلّ بِكَمّيّة > 0'
              : 'Add at least one item with quantity > 0')));
      return;
    }
    // التَحَقُّق مِن تَوَفُّر المَخزون لِكُلّ صَنف
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    for (final l in validLines) {
      final stock = repo.uniformCurrentStock(l.itemId!,
          countryId: auth.activeCountryId);
      if (l.quantity > stock) {
        final item = repo.uniformCatalog
            .firstWhere((x) => x.id == l.itemId, orElse: () =>
                UniformItem(id: '', nameAr: '?', nameEn: '?'));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: UniformPalette.danger,
          content: Text(s.isAr
              ? '${item.nameAr}: المُتَوَفِّر $stock فَقَط'
              : '${item.nameEn}: only $stock available'),
        ));
        return;
      }
    }
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'صَرف عُهدة الكَمب' : 'camp custody issue')) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);

    final activeCountry = auth.activeCountryId!;
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;

    // رَقَم سَند مُشتَرَك لِكُلّ سُطور هَذا الصَرف
    String batchCode = '';
    if (supaReady) {
      final c = await ds.consumeNextCode(
          technicalId: 'uniform_issue', countryId: activeCountry);
      if (c != null) batchCode = c;
    }
    if (batchCode.isEmpty) {
      batchCode = 'UIS-${DateTime.now().millisecondsSinceEpoch}';
    }

    EmployeeUniform? firstSaved;
    for (final l in validLines) {
      final issue = EmployeeUniform(
        id: repo.generateId(),
        issueNo: batchCode, // نَفس الرَقم لِكُلّ السُطور
        employeeId: _employeeId!,
        uniformItemId: l.itemId!,
        quantity: l.quantity,
        size: '', // المَقاس مَوجود في الصَنف نَفسه — لا نَنسَخه هُنا
        issuedById: auth.account?.id,
        issuedByName: auth.account?.fullName,
        countryId: activeCountry,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        sourceFormSubmissionId: widget.sourceFormSubmissionId,
      );

      if (supaReady) {
        final created =
            await ds.createEmployeeUniform(issue, countryId: activeCountry);
        if (created == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          setState(() => _saving = false);
          return;
        }
      } else {
        repo.employeeUniforms.insert(0, issue);
      }
      firstSaved ??= issue;
    }
    if (!supaReady) repo.notifyListeners();
    if (!mounted) return;
    Navigator.of(context).pop();
    // افتَح سَند الصَرف (لِأَوَّل صَنف — السَند مُشتَرَك)
    if (firstSaved != null) {
      Navigator.of(context).push(MaterialPageRoute(
        // 🆕 استَخدِم issueNo لِيَعرِض كُلّ الأَصناف في السَند
        builder: (_) => UniformIssueVoucher(issueNo: firstSaved!.issueNo),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    // 🆕 المُوَظَّفون: عُمَلِيات/عُمّال فَقَط (بِدون admin) + يَسكُنون في الكَمب
    final empCandidates = auth
        .filterByCountry(repo.employees, (e) => e.countryId)
        .where((e) => e.status == EntityStatus.active)
        .where((e) => e.category != 'admin') // مَربوطين بِالعَمَليّات
        .where((e) =>
            uniformMatchesQuery(_empSearch, [e.fullName, e.code]))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    final selectedEmp = _employeeId == null
        ? null
        : repo.employees.firstWhere(
            (e) => e.id == _employeeId,
            orElse: () => Employee(id: '', code: '', fullName: ''),
          );

    final items = auth
        .filterByCountry(repo.uniformCatalog, (u) => u.countryId)
        .where((u) => u.status == EntityStatus.active)
        .toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: CampPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: UniformPalette.stockOut.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.handshake,
                    color: UniformPalette.stockOut, size: 18),
              ),
              const SizedBox(width: 10),
              Text(s.isAr ? 'صَرف عُهدة الكَمب' : 'Camp Custody Issue',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: UniformPalette.info.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: UniformPalette.info, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? 'سيتم توليد رقم السند تلقائياً (UIS-XX-####)'
                                : 'Issue no will be auto-generated',
                            style: const TextStyle(
                                color: UniformPalette.info,
                                fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ===== الموظف =====
                  Text(s.employee,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (selectedEmp != null && selectedEmp.id.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: UniformPalette.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                UniformPalette.primary.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: UniformPalette.primary
                                .withValues(alpha: 0.15),
                            child: Text(selectedEmp.initials,
                                style: const TextStyle(
                                    color: UniformPalette.primary,
                                    fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(selectedEmp.fullName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)),
                                Text(selectedEmp.code,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: CampPalette
                                            .textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.swap_horiz,
                                color: UniformPalette.primary),
                            onPressed: () => setState(() {
                              _employeeId = null;
                              _empSearch = '';
                            }),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    UniformSearchBar(
                      hint: s.isAr
                          ? 'بحث: اسم/كود الموظف...'
                          : 'Search: name/code...',
                      value: _empSearch,
                      onChanged: (v) => setState(() => _empSearch = v),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CampPalette.border),
                      ),
                      child: empCandidates.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  s.isAr
                                      ? 'لا نتائج'
                                      : 'No results',
                                  style: const TextStyle(
                                      color: CampPalette.textSecondary,
                                      fontSize: 12)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: empCandidates.length,
                              itemBuilder: (_, i) {
                                final e = empCandidates[i];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: UniformPalette
                                        .primary
                                        .withValues(alpha: 0.15),
                                    child: Text(e.initials,
                                        style: const TextStyle(
                                            color:
                                                UniformPalette.primary,
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight.w900)),
                                  ),
                                  title: Text(e.fullName,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.w700)),
                                  subtitle: Text(e.code,
                                      style: const TextStyle(
                                          fontSize: 10)),
                                  onTap: () => setState(
                                      () => _employeeId = e.id),
                                );
                              },
                            ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // ===== 🆕 الأَصناف (مُتَعَدِّدة) =====
                  Row(
                    children: [
                      Text(s.isAr ? '📦 الأَصناف' : '📦 Items',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addLine,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(s.isAr ? 'إضافة صَنف' : 'Add Item'),
                      ),
                    ],
                  ),
                  if (_lines.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          s.isAr
                              ? 'اضغَط "إضافة صَنف" لِتَبدأ'
                              : 'Tap "Add Item" to start',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ..._lines.asMap().entries.map((entry) {
                    final i = entry.key;
                    final line = entry.value;
                    return _buildLineEditor(line, i, items, repo,
                        auth.activeCountryId, s.isAr);
                  }),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'ملاحظات' : 'Notes',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CampPalette.input,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.outbound,
                            size: 16,
                            color: UniformPalette.stockOut),
                        const SizedBox(width: 6),
                        Text(
                          '${s.isAr ? "المُسلِّم: " : "Issuer: "}${auth.account?.fullName ?? "—"}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: CampPalette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: CampPalette.card,
              border:
                  Border(top: BorderSide(color: CampPalette.borderLight)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UniformPalette.stockOut,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(s.isAr ? 'صرف وطباعة' : 'Issue & Print'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
