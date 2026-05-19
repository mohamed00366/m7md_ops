import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/currency.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../camp_palette.dart';
import 'uniform_employee_card.dart';
import 'uniform_shared.dart';

/// 📊 شاشة تقارير اليونيفورم
class UniformReportsScreen extends StatefulWidget {
  const UniformReportsScreen({super.key});

  @override
  State<UniformReportsScreen> createState() =>
      _UniformReportsScreenState();
}

class _UniformReportsScreenState extends State<UniformReportsScreen> {
  String _periodFilter = 'all';
  String _empSearch = '';
  String _itemSearch = '';
  String _activitySearch = '';

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

  bool _inPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_periodFilter) {
      case 'today':
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case 'week':
        return now.difference(d).inDays <= 7;
      case 'month':
        return now.difference(d).inDays <= 30;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    // ===== جمع البيانات بنطاق الدولة + الفترة =====
    final issues = repo.employeeUniforms
        .where((u) => auth.isInScope(u.countryId))
        .where((u) => _inPeriod(u.issueDate))
        .toList();

    // 🆕 المَصدَر الحَديث: uniform_purchases (يَستَبدِل uniform_receipts المَهجور)
    final purchases = repo.uniformPurchases
        .where((p) =>
            p.countryId == null || auth.isInScope(p.countryId))
        .where((p) => _inPeriod(p.purchaseDate))
        .toList();

    // ===== KPIs =====
    final totalItems = repo.uniformCatalog
        .where((u) => auth.isInScope(u.countryId))
        .where((u) => u.status == EntityStatus.active)
        .length;

    int totalStock = 0;
    int lowStockItems = 0;
    int outOfStockItems = 0;
    double totalStockValue = 0;
    for (final u in repo.uniformCatalog
        .where((u) => auth.isInScope(u.countryId))) {
      final stock =
          repo.uniformCurrentStock(u.id, countryId: auth.activeCountryId);
      totalStock += stock;
      totalStockValue += stock * u.price;
      if (stock <= 0) {
        outOfStockItems++;
      } else if (stock < u.minStock) lowStockItems++;
    }

    final totalIssued = issues.fold<int>(0, (a, u) => a + u.quantity);
    final totalReturned =
        issues.fold<int>(0, (a, u) => a + (u.returnQuantity ?? 0));
    final totalReceived =
        purchases.fold<int>(0, (a, p) => a + p.totalQuantity);
    // 🆕 إجمالي قِيمة الصَرف المالِيّة (مِن عَمود total_value الجَديد)
    final totalIssuedValue =
        issues.fold<double>(0, (a, u) => a + u.totalValue);

    // ===== أعلى الموظفين =====
    final empMap = <String, int>{};
    for (final u in issues) {
      empMap[u.employeeId] = (empMap[u.employeeId] ?? 0) + u.quantity;
    }
    final topEmployees = empMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final filteredEmployees = topEmployees.where((e) {
      if (_empSearch.trim().isEmpty) return true;
      final emp = repo.employeeById(e.key);
      return uniformMatchesQuery(_empSearch,
          [emp?.fullName ?? '', emp?.code ?? '']);
    }).toList();

    // ===== أعلى الأصناف =====
    final itemMap = <String, int>{};
    for (final u in issues) {
      itemMap[u.uniformItemId] =
          (itemMap[u.uniformItemId] ?? 0) + u.quantity;
    }
    final topItems = itemMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final filteredItems = topItems.where((e) {
      if (_itemSearch.trim().isEmpty) return true;
      try {
        final ui = repo.uniformCatalog.firstWhere((x) => x.id == e.key);
        return uniformMatchesQuery(
            _itemSearch, [ui.nameAr, ui.nameEn]);
      } catch (_) {
        return false;
      }
    }).toList();

    // ===== سجل النشاط =====
    final activity = <_Activity>[];
    for (final u in issues) {
      activity.add(_Activity(
          kind: 'issue', date: u.issueDate, issue: u));
      if (u.returnDate != null) {
        activity.add(_Activity(
            kind: 'return', date: u.returnDate!, issue: u));
      }
    }
    for (final p in purchases) {
      activity.add(_Activity(
          kind: 'purchase', date: p.purchaseDate, purchase: p));
    }
    activity.sort((a, b) => b.date.compareTo(a.date));
    final filteredActivity = activity.where((a) {
      if (_activitySearch.trim().isEmpty) return true;
      final fields = <String>[];
      if (a.issue != null) {
        fields.add(a.issue!.issueNo);
        final emp = repo.employeeById(a.issue!.employeeId);
        if (emp != null) {
          fields.addAll([emp.fullName, emp.code]);
        }
      }
      if (a.purchase != null) {
        fields.add(a.purchase!.purchaseNo);
        if (a.purchase!.invoiceNo != null) fields.add(a.purchase!.invoiceNo!);
        if (a.purchase!.supplierName != null) {
          fields.add(a.purchase!.supplierName!);
        }
      }
      return uniformMatchesQuery(_activitySearch, fields);
    }).take(60).toList();

    return Scaffold(
      backgroundColor: CampPalette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range,
                    size: 16, color: CampPalette.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final p in [
                          ['all', s.isAr ? 'الكل' : 'All'],
                          ['today', s.isAr ? 'اليوم' : 'Today'],
                          ['week', s.isAr ? 'أسبوع' : 'Week'],
                          ['month', s.isAr ? 'شهر' : 'Month'],
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(p[1],
                                  style: const TextStyle(fontSize: 11)),
                              selected: _periodFilter == p[0],
                              onSelected: (_) => setState(
                                  () => _periodFilter = p[0]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== KPIs =====
          _SectionHeader(
              icon: Icons.dashboard,
              label: s.isAr ? 'نظرة عامة' : 'Overview',
              color: UniformPalette.primary),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Kpi(
                  icon: Icons.checkroom,
                  color: UniformPalette.primary,
                  label: s.isAr ? 'الأصناف' : 'Items',
                  value: '$totalItems'),
              _Kpi(
                  icon: Icons.inventory_2,
                  color: UniformPalette.stockIn,
                  label: s.isAr ? 'الكمية بالمخزون' : 'In Stock',
                  value: '$totalStock'),
              if (totalStockValue > 0)
                _Kpi(
                    icon: Icons.attach_money,
                    color: UniformPalette.info,
                    label: s.isAr ? 'قيمة المخزون' : 'Stock Value',
                    value: AppCurrency.formatInt(context, totalStockValue)),
              _Kpi(
                  icon: Icons.outbound,
                  color: UniformPalette.stockOut,
                  label: s.isAr ? 'مُصروف بالفترة' : 'Issued',
                  value: '$totalIssued'),
              // 🆕 قِيمة الصَرف المالِيّة (مِن total_value column)
              if (totalIssuedValue > 0)
                _Kpi(
                    icon: Icons.payments_outlined,
                    color: UniformPalette.stockOut,
                    label: s.isAr ? 'قِيمة الصَرف' : 'Issued Value',
                    value:
                        AppCurrency.formatInt(context, totalIssuedValue)),
              _Kpi(
                  icon: Icons.keyboard_return,
                  color: UniformPalette.stockIn,
                  label: s.isAr ? 'مُرجَع بالفترة' : 'Returned',
                  value: '$totalReturned'),
              _Kpi(
                  icon: Icons.inbox,
                  color: UniformPalette.stockIn,
                  label: s.isAr ? 'مستلَم بالفترة' : 'Received',
                  value: '$totalReceived'),
              if (lowStockItems > 0)
                _Kpi(
                    icon: Icons.warning_amber,
                    color: UniformPalette.stockOut,
                    label: s.isAr ? 'منخفض' : 'Low Stock',
                    value: '$lowStockItems'),
              if (outOfStockItems > 0)
                _Kpi(
                    icon: Icons.error_outline,
                    color: UniformPalette.danger,
                    label: s.isAr ? 'نفد' : 'Out of Stock',
                    value: '$outOfStockItems'),
            ],
          ),
          const SizedBox(height: 16),

          // ===== أعلى الموظفين =====
          _SectionHeader(
              icon: Icons.leaderboard,
              label:
                  s.isAr ? 'أعلى الموظفين صرفاً' : 'Top Employees',
              color: UniformPalette.primary,
              count: topEmployees.length),
          Container(
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: UniformSearchBar(
                    hint: s.isAr
                        ? 'بحث الموظف بالاسم/الكود...'
                        : 'Search employee...',
                    value: _empSearch,
                    onChanged: (v) => setState(() => _empSearch = v),
                  ),
                ),
                if (filteredEmployees.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(s.isAr ? 'لا نتائج' : 'No results',
                        style: const TextStyle(
                            color: CampPalette.textSecondary)),
                  )
                else
                  ...filteredEmployees.take(15).map((e) {
                    final emp = repo.employeeById(e.key);
                    final pct = totalIssued == 0
                        ? 0.0
                        : (e.value / totalIssued).clamp(0.0, 1.0);
                    return _EmployeeRow(
                        emp: emp,
                        count: e.value,
                        pct: pct,
                        onTap: () {
                          if (emp != null) {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => UniformEmployeeCard(
                                  employeeId: emp.id),
                            ));
                          }
                        });
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== أعلى الأصناف =====
          _SectionHeader(
              icon: Icons.bar_chart,
              label: s.isAr ? 'أكثر الأصناف صرفاً' : 'Top Items',
              color: UniformPalette.stockOut,
              count: topItems.length),
          Container(
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: UniformSearchBar(
                    hint: s.isAr ? 'بحث: اسم الصنف...' : 'Search item...',
                    value: _itemSearch,
                    onChanged: (v) => setState(() => _itemSearch = v),
                  ),
                ),
                if (filteredItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(s.isAr ? 'لا نتائج' : 'No results',
                        style: const TextStyle(
                            color: CampPalette.textSecondary)),
                  )
                else
                  ...filteredItems.map((e) {
                    String name = '—';
                    try {
                      final u = repo.uniformCatalog
                          .firstWhere((x) => x.id == e.key);
                      name = s.isAr ? u.nameAr : u.nameEn;
                    } catch (_) {}
                    final maxVal =
                        topItems.isEmpty ? 1 : topItems.first.value;
                    return _ItemBarRow(
                      name: name,
                      count: e.value,
                      pct: maxVal == 0 ? 0.0 : e.value / maxVal,
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== سجل النشاط =====
          _SectionHeader(
              icon: Icons.history,
              label: s.isAr ? 'سجل الحركات' : 'Activity Log',
              color: UniformPalette.info),
          Container(
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: UniformSearchBar(
                    hint: s.isAr
                        ? 'بحث: موظف، رقم سند، إيصال...'
                        : 'Search: employee, no, receipt...',
                    value: _activitySearch,
                    onChanged: (v) =>
                        setState(() => _activitySearch = v),
                  ),
                ),
                if (filteredActivity.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(s.isAr ? 'لا نتائج' : 'No results',
                        style: const TextStyle(
                            color: CampPalette.textSecondary)),
                  )
                else
                  ...filteredActivity
                      .map((a) => _ActivityRow(activity: a)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _Kpi(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Container(
        decoration: BoxDecoration(
          color: CampPalette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CampPalette.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: CampPalette.text)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: CampPalette.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? count;
  const _SectionHeader(
      {required this.icon,
      required this.label,
      required this.color,
      this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
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
                color: color.withOpacity(0.15),
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

class _EmployeeRow extends StatelessWidget {
  final Employee? emp;
  final int count;
  final double pct;
  final VoidCallback onTap;
  const _EmployeeRow(
      {required this.emp,
      required this.count,
      required this.pct,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CampPalette.borderLight)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  UniformPalette.primary.withOpacity(0.15),
              child: Text(emp?.initials ?? '?',
                  style: const TextStyle(
                      color: UniformPalette.primary,
                      fontSize: 10,
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
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  if (emp != null)
                    Text(emp!.code,
                        style: const TextStyle(
                            fontSize: 10,
                            color: CampPalette.textSecondary)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor:
                          UniformPalette.primary.withOpacity(0.10),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          UniformPalette.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: UniformPalette.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: UniformPalette.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: CampPalette.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ItemBarRow extends StatelessWidget {
  final String name;
  final int count;
  final double pct;
  const _ItemBarRow(
      {required this.name, required this.count, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampPalette.borderLight)),
      ),
      child: Row(
        children: [
          const Icon(Icons.checkroom,
              size: 14, color: UniformPalette.stockOut),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor:
                        UniformPalette.stockOut.withOpacity(0.10),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        UniformPalette.stockOut),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: UniformPalette.stockOut.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: UniformPalette.stockOut,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _Activity {
  final String kind;
  final DateTime date;
  final EmployeeUniform? issue;
  final UniformPurchase? purchase;
  _Activity(
      {required this.kind, required this.date, this.issue, this.purchase});
}

class _ActivityRow extends StatelessWidget {
  final _Activity activity;
  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    Color color = UniformPalette.primary;
    IconData icon = Icons.circle;
    String text = '';

    if (activity.kind == 'issue') {
      color = UniformPalette.stockOut;
      icon = Icons.outbound;
      final emp = repo.employeeById(activity.issue!.employeeId);
      text = s.isAr
          ? 'صرف ${activity.issue!.issueNo} لـ ${emp?.fullName ?? "—"}'
          : 'Issued ${activity.issue!.issueNo} to ${emp?.fullName ?? "—"}';
    } else if (activity.kind == 'return') {
      color = UniformPalette.stockIn;
      icon = Icons.keyboard_return;
      final emp = repo.employeeById(activity.issue!.employeeId);
      text = s.isAr
          ? 'إرجاع ${activity.issue!.issueNo} من ${emp?.fullName ?? "—"}'
          : 'Returned ${activity.issue!.issueNo} from ${emp?.fullName ?? "—"}';
    } else if (activity.kind == 'purchase') {
      color = UniformPalette.stockIn;
      icon = Icons.receipt_long;
      final p = activity.purchase!;
      text = s.isAr
          ? 'فاتورة استِلام ${p.purchaseNo} (${p.totalQuantity} قِطعة)'
          : 'Receipt ${p.purchaseNo} (${p.totalQuantity} items)';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampPalette.borderLight)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: CampPalette.text)),
          ),
          const SizedBox(width: 8),
          Text(_relTime(activity.date, s.isAr),
              style: const TextStyle(
                  fontSize: 10, color: CampPalette.textSecondary)),
        ],
      ),
    );
  }

  String _relTime(DateTime d, bool isAr) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (diff.inHours < 1) {
      return isAr ? 'قبل ${diff.inMinutes} د' : '${diff.inMinutes}m';
    }
    if (diff.inDays < 1) {
      return isAr ? 'قبل ${diff.inHours} س' : '${diff.inHours}h';
    }
    if (diff.inDays < 30) {
      return isAr ? 'قبل ${diff.inDays} يوم' : '${diff.inDays}d';
    }
    return formatDateShort(d);
  }
}
