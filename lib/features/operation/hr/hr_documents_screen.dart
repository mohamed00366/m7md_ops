import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import 'hr_palette.dart';

/// 📋 متابعة الوثائق - جوازات/تأشيرات/رخص قاربت أو انتهت صلاحيتها
class HrDocumentsScreen extends StatefulWidget {
  const HrDocumentsScreen({super.key});

  @override
  State<HrDocumentsScreen> createState() => _HrDocumentsScreenState();
}

class _HrDocumentsScreenState extends State<HrDocumentsScreen> {
  String _filter = 'all'; // all | expired | expiring | valid
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// تصنيف انتهاء وثيقة: expired (سالب) / expiring (≤ 60 يوم) / valid
  static String _statusFor(DateTime? d) {
    if (d == null) return 'none';
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return 'expired';
    if (days <= 60) return 'expiring';
    return 'valid';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final cid = context.watch<AuthProvider>().selectedCountryId;

    var employees = repo.employees.toList();
    if (cid != null) {
      employees = employees.where((e) => e.countryId == cid).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      employees = employees
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q))
          .toList();
    }

    // اجمع كل الوثائق ذات تواريخ
    final rows = <_DocRow>[];
    for (final e in employees) {
      if (e.passportExpiry != null) {
        rows.add(_DocRow(e, s.isAr ? 'جواز السفر' : 'Passport',
            e.passportNumber, e.passportExpiry, Icons.book_outlined));
      }
      if (e.licenseExpiry != null) {
        rows.add(_DocRow(e, s.isAr ? 'رخصة القيادة' : 'License',
            e.licenseNumber, e.licenseExpiry, Icons.credit_card_outlined));
      }
    }
    if (_filter != 'all') {
      rows.removeWhere((r) => _statusFor(r.expiry) != _filter);
    }
    rows.sort((a, b) => (a.expiry ?? DateTime(2100))
        .compareTo(b.expiry ?? DateTime(2100)));

    final expiredCount =
        rows.where((r) => _statusFor(r.expiry) == 'expired').length;
    final expiringCount =
        rows.where((r) => _statusFor(r.expiry) == 'expiring').length;

    return Scaffold(
      backgroundColor: HrPalette.bg,
      body: Column(
        children: [
          // KPIs
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(children: [
              _Kpi(
                  count: rows.length,
                  label: s.isAr ? 'إجمالي' : 'Total',
                  color: HrPalette.primary),
              const SizedBox(width: 8),
              _Kpi(
                  count: expiredCount,
                  label: s.isAr ? 'منتهية' : 'Expired',
                  color: HrPalette.expired),
              const SizedBox(width: 8),
              _Kpi(
                  count: expiringCount,
                  label: s.isAr ? 'قاربت' : 'Soon',
                  color: HrPalette.expiring),
            ]),
          ),

          // Search + Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.isAr ? 'بحث (اسم/كود)' : 'Search (name/code)',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _FilterChip('all', s.isAr ? 'الكل' : 'All', _filter,
                  () => setState(() => _filter = 'all')),
              const SizedBox(width: 6),
              _FilterChip('expired', s.isAr ? 'منتهية' : 'Expired', _filter,
                  () => setState(() => _filter = 'expired'),
                  color: HrPalette.expired),
              const SizedBox(width: 6),
              _FilterChip('expiring', s.isAr ? 'قاربت' : 'Soon', _filter,
                  () => setState(() => _filter = 'expiring'),
                  color: HrPalette.expiring),
              const SizedBox(width: 6),
              _FilterChip('valid', s.isAr ? 'سارية' : 'Valid', _filter,
                  () => setState(() => _filter = 'valid'),
                  color: HrPalette.valid),
            ]),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      s.isAr
                          ? 'لا توجد وثائق مطابقة'
                          : 'No matching documents',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _DocCard(row: rows[i], isAr: s.isAr),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DocRow {
  final Employee employee;
  final String docType;
  final String docNumber;
  final DateTime? expiry;
  final IconData icon;
  _DocRow(this.employee, this.docType, this.docNumber, this.expiry, this.icon);
}

class _Kpi extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _Kpi(
      {required this.count, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(children: [
            Text(count.toString(),
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  final String value;
  final String label;
  final String current;
  final VoidCallback onTap;
  final Color? color;
  const _FilterChip(this.value, this.label, this.current, this.onTap,
      {this.color});

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    final c = color ?? HrPalette.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : c,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final _DocRow row;
  final bool isAr;
  const _DocCard({required this.row, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final status = _HrDocumentsScreenState._statusFor(row.expiry);
    final color = status == 'expired'
        ? HrPalette.expired
        : status == 'expiring'
            ? HrPalette.expiring
            : HrPalette.valid;
    final dateStr = row.expiry == null
        ? '—'
        : '${row.expiry!.year}-${row.expiry!.month.toString().padLeft(2, '0')}-${row.expiry!.day.toString().padLeft(2, '0')}';
    final days = row.expiry?.difference(DateTime.now()).inDays;
    final daysLabel = days == null
        ? ''
        : (days < 0
            ? (isAr ? 'منذ ${-days} يوم' : '$days d ago')
            : (isAr ? 'بعد $days يوم' : 'in $days d'));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(row.icon, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.employee.fullName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  '${row.employee.code}  •  ${row.docType}  •  ${row.docNumber.isEmpty ? '—' : row.docNumber}',
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 11)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dateStr,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            if (daysLabel.isNotEmpty)
              Text(daysLabel,
                  style: const TextStyle(
                      color: Colors.black45, fontSize: 10)),
          ],
        ),
      ]),
    );
  }
}
