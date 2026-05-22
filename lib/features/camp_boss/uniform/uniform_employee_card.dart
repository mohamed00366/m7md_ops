import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../camp_palette.dart';
import 'uniform_issue_voucher.dart';
import 'uniform_shared.dart';

/// 👤 بطاقة موظف - كل اليونيفورم المسلَّم له
class UniformEmployeeCard extends StatefulWidget {
  final String employeeId;
  const UniformEmployeeCard({super.key, required this.employeeId});

  @override
  State<UniformEmployeeCard> createState() => _UniformEmployeeCardState();
}

class _UniformEmployeeCardState extends State<UniformEmployeeCard> {
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final emp = repo.employeeById(widget.employeeId);
    if (emp == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: UniformPalette.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leadingWidth: 100,
          leading: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(s.isAr ? 'رجوع' : 'Back',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
          title: Text(s.isAr ? 'بطاقة الموظف' : 'Employee Card'),
        ),
        body: Center(child: Text(s.isAr ? 'الموظف غير موجود' : 'Not found')),
      );
    }

    final issues = repo.employeeUniforms
        .where((u) => u.employeeId == emp.id)
        .toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));

    final activeIssues =
        issues.where((u) => !u.isFullyReturned).toList();
    final returnedIssues =
        issues.where((u) => u.isFullyReturned).toList();
    final totalIssued = issues.fold<int>(0, (a, u) => a + u.quantity);
    final totalReturned = issues.fold<int>(
        0, (a, u) => a + (u.returnQuantity ?? 0));
    final totalActive = totalIssued - totalReturned;
    final totalValue = issues.fold<double>(0, (a, u) {
      try {
        final ui = repo.uniformCatalog
            .firstWhere((x) => x.id == u.uniformItemId);
        return a + ui.price * u.pendingQuantity;
      } catch (_) {
        return a;
      }
    });

    // تجميع حسب الصنف
    final byItem = <String, int>{};
    for (final u in issues) {
      byItem[u.uniformItemId] =
          (byItem[u.uniformItemId] ?? 0) + u.pendingQuantity;
    }

    return Scaffold(
      backgroundColor: CampPalette.bg,
      appBar: AppBar(
        backgroundColor: UniformPalette.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        leading: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: Colors.white.withValues(alpha: 0.15),
            ),
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(s.isAr ? 'رجوع' : 'Back',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(emp.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // ===== ترويسة الموظف =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: UniformPalette.primary.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      UniformPalette.primary.withValues(alpha: 0.15),
                  child: Text(emp.initials,
                      style: const TextStyle(
                          color: UniformPalette.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp.fullName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined,
                              size: 12,
                              color: CampPalette.textSecondary),
                          const SizedBox(width: 4),
                          Text(emp.code,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: CampPalette.textSecondary,
                                  fontWeight: FontWeight.w700)),
                          if (emp.jobTitle.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.work_outline,
                                size: 12,
                                color: CampPalette.textSecondary),
                            const SizedBox(width: 4),
                            Text(emp.jobTitle,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: CampPalette.textSecondary)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== KPIs =====
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.outbound,
                  label: s.isAr ? 'مُصروفة' : 'Issued',
                  value: '$totalIssued',
                  color: UniformPalette.stockOut,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Kpi(
                  icon: Icons.keyboard_return,
                  label: s.isAr ? 'مُرجَعة' : 'Returned',
                  value: '$totalReturned',
                  color: UniformPalette.stockIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Kpi(
                  icon: Icons.inventory_2,
                  label: s.isAr ? 'في عهدته' : 'On Hand',
                  value: '$totalActive',
                  color: UniformPalette.primary,
                ),
              ),
              if (totalValue > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _Kpi(
                    icon: Icons.attach_money,
                    label: s.isAr ? 'القيمة' : 'Value',
                    value: AppCurrency.formatInt(context, totalValue),
                    color: UniformPalette.info,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // ===== ملخّص بالأصناف =====
          if (byItem.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.checkroom,
              label: s.isAr ? 'في عهدته (مُلخَّص)' : 'On-Hand Summary',
              color: UniformPalette.primary,
            ),
            Container(
              decoration: BoxDecoration(
                color: CampPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CampPalette.border),
              ),
              child: Column(
                children: [
                  for (final entry in byItem.entries)
                    if (entry.value > 0) _SummaryRow(
                        itemId: entry.key, quantity: entry.value),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ===== السندات النشطة =====
          if (activeIssues.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.pending_outlined,
              label: s.isAr ? 'سندات نشطة' : 'Active Issues',
              color: UniformPalette.stockOut,
              count: activeIssues.length,
            ),
            for (final i in activeIssues)
              _IssueRow(
                issue: i,
                onReturn: () => _openReturnDialog(context, i),
              ),
            const SizedBox(height: 14),
          ],

          // ===== السندات المُرجَعة =====
          if (returnedIssues.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.check_circle_outline,
              label: s.isAr ? 'سندات مُرجَعة' : 'Returned',
              color: UniformPalette.stockIn,
              count: returnedIssues.length,
            ),
            for (final i in returnedIssues)
              _IssueRow(issue: i, onReturn: null),
          ],

          if (issues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: UniformEmpty(
                icon: Icons.checkroom_outlined,
                title:
                    s.isAr ? 'لم يُصرف للموظف يونيفورم بعد' : 'No issues yet',
              ),
            ),
        ],
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
                    ? 'في عهدته: ${issue.pendingQuantity} قطعة'
                    : 'On hand: ${issue.pendingQuantity}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: s.isAr ? 'الكمية المُرجَعة' : 'Return Qty',
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
            child: Text(s.isAr ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    final total = (issue.returnQuantity ?? 0) + qty;
    final auth = context.read<AuthProvider>();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      await SupabaseDataService().returnEmployeeUniform(
        id: issue.id,
        returnQuantity:
            total > issue.quantity ? issue.quantity : total,
        returnedById: auth.account?.id,
        returnedByName: auth.account?.fullName,
      );
    } else {
      issue.returnDate = DateTime.now();
      issue.returnQuantity =
          total > issue.quantity ? issue.quantity : total;
      issue.returnedById = auth.account?.id;
      issue.returnedByName = auth.account?.fullName;
      MockRepository().notifyListeners();
    }
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? count;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String itemId;
  final int quantity;
  const _SummaryRow({required this.itemId, required this.quantity});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    String name = '—';
    String size = '';
    try {
      final u = repo.uniformCatalog.firstWhere((x) => x.id == itemId);
      name = s.isAr ? u.nameAr : u.nameEn;
      size = u.size;
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampPalette.borderLight)),
      ),
      child: Row(
        children: [
          const Icon(Icons.checkroom,
              size: 14, color: UniformPalette.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          if (size.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: CampPalette.input,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(size,
                  style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: UniformPalette.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('×$quantity',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final EmployeeUniform issue;
  final VoidCallback? onReturn;
  const _IssueRow({required this.issue, this.onReturn});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    String itemName = '—';
    try {
      final u = repo.uniformCatalog
          .firstWhere((x) => x.id == issue.uniformItemId);
      itemName = s.isAr ? u.nameAr : u.nameEn;
    } catch (_) {}
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CampPalette.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => UniformIssueVoucher(issueId: issue.id),
              ));
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: issue.isFullyReturned
                    ? UniformPalette.stockIn
                    : UniformPalette.stockOut,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                  issue.issueNo.isEmpty ? '—' : issue.issueNo,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                    formatDateShort(issue.issueDate),
                    style: const TextStyle(
                        fontSize: 10,
                        color: CampPalette.textSecondary)),
              ],
            ),
          ),
          Text('${issue.quantity}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: UniformPalette.primary)),
          if (onReturn != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: s.isAr ? 'إرجاع' : 'Return',
              icon: const Icon(Icons.keyboard_return,
                  color: UniformPalette.stockIn, size: 18),
              onPressed: onReturn,
            ),
          ],
        ],
      ),
    );
  }
}
