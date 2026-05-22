// =============================================================================
// 📁 Document Vault — مَكتَبة الوَثائق المُوَحَّدة
// =============================================================================
// كُلّ وَثائق المُوَظَّفين في شاشة واحِدة:
//   • فِلتَر بِنَوع الوَثيقة (هَوِيّة/جَواز/رُخصة/...)
//   • فِلتَر بِإلحاحيّة الانتِهاء (مُنتَهية / ≤30 يَوم / ≤60 يَوم / ≤90 يَوم / الكُلّ)
//   • بَحث بِاسم/كود المُوَظَّف أَو رَقم الوَثيقة
//   • صُفوف مُلَوَّنة حَسَب الإلحاحيّة
//   • نَقر يَفتَح Employee 360° لِلمُوَظَّف
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../reports/employee_aggregated_report.dart';

class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _docs = [];
  String _typeFilter = 'all';
  String _urgencyFilter = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rows = await supa.client
          .from('employee_documents')
          .select(
              'id, employee_id, doc_type, doc_type_label, document_number, '
              'issuing_authority, issued_date, expiry_date, status, '
              'file_path, version_number, '
              'employees(full_name, code)')
          .eq('status', 'active')
          .order('expiry_date', ascending: true, nullsFirst: false)
          .limit(5000);
      _docs = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('DocumentVault', 'load', error: e);
      _docs = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  // ============================================================
  // Filtering helpers
  // ============================================================

  int _daysUntilExpiry(String? expiry) {
    if (expiry == null) return 99999;
    final dt = DateTime.tryParse(expiry);
    if (dt == null) return 99999;
    return dt.difference(DateTime.now()).inDays;
  }

  bool _matchesUrgency(int days) {
    switch (_urgencyFilter) {
      case 'expired':
        return days < 0;
      case 'd30':
        return days >= 0 && days <= 30;
      case 'd60':
        return days >= 0 && days <= 60;
      case 'd90':
        return days >= 0 && days <= 90;
      default:
        return true;
    }
  }

  bool _matchesType(String? docType) {
    if (_typeFilter == 'all') return true;
    return docType == _typeFilter;
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    final emp = d['employees'];
    final name = emp is Map ? (emp['full_name'] as String? ?? '') : '';
    final code = emp is Map ? (emp['code'] as String? ?? '') : '';
    final docNum = (d['document_number'] as String?) ?? '';
    final docLabel = (d['doc_type_label'] as String?) ?? '';
    return name.toLowerCase().contains(q) ||
        code.toLowerCase().contains(q) ||
        docNum.toLowerCase().contains(q) ||
        docLabel.toLowerCase().contains(q);
  }

  List<Map<String, dynamic>> get _filtered {
    return _docs.where((d) {
      final days = _daysUntilExpiry(d['expiry_date'] as String?);
      return _matchesType(d['doc_type'] as String?) &&
          _matchesUrgency(days) &&
          _matchesSearch(d);
    }).toList();
  }

  // ============================================================
  // KPI counts (computed from full list, not filtered)
  // ============================================================
  ({int expired, int d30, int d60, int total}) _kpis() {
    int expired = 0, d30 = 0, d60 = 0;
    for (final d in _docs) {
      final days = _daysUntilExpiry(d['expiry_date'] as String?);
      if (days < 0) {
        expired++;
      } else if (days <= 30) {
        d30++;
      } else if (days <= 60) {
        d60++;
      }
    }
    return (expired: expired, d30: d30, d60: d60, total: _docs.length);
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final filtered = _filtered;
    final kpis = _kpis();
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📁 خِزانة الوَثائق' : '📁 Document Vault',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _kpiBar(kpis, isAr),
                  _searchBar(isAr),
                  _typeFilterRow(isAr),
                  _urgencyFilterRow(isAr),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '${filtered.length} ${isAr ? "وَثيقة" : "documents"}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _emptyState(isAr)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) =>
                                _docCard(filtered[i], isAr),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kpiBar(({int expired, int d30, int d60, int total}) k, bool isAr) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Row(
        children: [
          _miniKpi(isAr ? 'مُنتَهية' : 'Expired', k.expired,
              AppColors.danger, Icons.error_outline,
              onTap: () => setState(() => _urgencyFilter = 'expired')),
          const SizedBox(width: 4),
          _miniKpi(isAr ? '≤30 يَوم' : '≤30 days', k.d30,
              AppColors.warning, Icons.warning_amber,
              onTap: () => setState(() => _urgencyFilter = 'd30')),
          const SizedBox(width: 4),
          _miniKpi(isAr ? '≤60 يَوم' : '≤60 days', k.d60,
              Colors.amber.shade700, Icons.schedule,
              onTap: () => setState(() => _urgencyFilter = 'd60')),
          const SizedBox(width: 4),
          _miniKpi(isAr ? 'الإجمالي' : 'Total', k.total,
              AppColors.brand, Icons.folder_outlined,
              onTap: () => setState(() => _urgencyFilter = 'all')),
        ],
      ),
    );
  }

  Widget _miniKpi(String label, int value, Color color, IconData icon,
      {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 3),
              Text('$value',
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text(label,
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: isAr
              ? 'بَحث بِالاسم/الكود/رَقم الوَثيقة…'
              : 'Search name / code / doc number…',
          hintStyle: const TextStyle(fontSize: 12),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _typeFilterRow(bool isAr) {
    final types = <(String, String, String)>[
      ('all', isAr ? 'الكُلّ' : 'All', '📋'),
      ('passport', isAr ? 'جَواز' : 'Passport', '🛂'),
      ('visa', isAr ? 'إقامة' : 'Visa', '🪪'),
      ('emirates_id', isAr ? 'هَوِيّة' : 'ID', '🆔'),
      ('license', isAr ? 'رُخصة' : 'License', '🚗'),
      ('work_letter', isAr ? 'خِطاب عَمَل' : 'Work Letter', '📝'),
      ('custom', isAr ? 'أُخرى' : 'Custom', '📎'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final t = types[i];
          final selected = _typeFilter == t.$1;
          return ChoiceChip(
            label: Text('${t.$3} ${t.$2}',
                style: const TextStyle(fontSize: 11)),
            selected: selected,
            onSelected: (_) => setState(() => _typeFilter = t.$1),
          );
        },
      ),
    );
  }

  Widget _urgencyFilterRow(bool isAr) {
    final urgencies = <(String, String, Color)>[
      ('all', isAr ? 'الكُلّ' : 'All', AppColors.brand),
      ('expired', isAr ? '🔴 مُنتَهية' : '🔴 Expired', AppColors.danger),
      ('d30', isAr ? '⚠️ ≤30 يَوم' : '⚠️ ≤30d', AppColors.warning),
      ('d60', isAr ? '⏰ ≤60 يَوم' : '⏰ ≤60d', Colors.amber.shade700),
      ('d90', isAr ? '📅 ≤90 يَوم' : '📅 ≤90d', Colors.indigo),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: urgencies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final u = urgencies[i];
          final selected = _urgencyFilter == u.$1;
          return ChoiceChip(
            label: Text(u.$2, style: const TextStyle(fontSize: 11)),
            selected: selected,
            selectedColor: u.$3.withValues(alpha: 0.18),
            onSelected: (_) => setState(() => _urgencyFilter = u.$1),
          );
        },
      ),
    );
  }

  Widget _emptyState(bool isAr) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              isAr ? 'لا تُوجَد وَثائق بِالفِلتَر الحاليّ' : 'No documents match filters',
              style: TextStyle(
                  color: Colors.grey.shade600, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCard(Map<String, dynamic> d, bool isAr) {
    final emp = d['employees'];
    final empName = emp is Map ? (emp['full_name'] as String? ?? '?') : '?';
    final empCode = emp is Map ? (emp['code'] as String? ?? '') : '';
    final docType = (d['doc_type_label'] as String?) ??
        _docTypeLabel(d['doc_type'] as String?, isAr);
    final docNum = (d['document_number'] as String?) ?? '';
    final expiry = d['expiry_date'] as String?;
    final days = _daysUntilExpiry(expiry);

    // Color by urgency
    Color color;
    String urgencyLabel;
    IconData urgencyIcon;
    if (days < 0) {
      color = AppColors.danger;
      urgencyLabel = isAr ? '🔴 مُنتَهية مُنذ ${-days} يَوم' : '🔴 Expired ${-days}d ago';
      urgencyIcon = Icons.error;
    } else if (days <= 30) {
      color = AppColors.danger;
      urgencyLabel = isAr ? '⚠️ بَعد $days يَوم' : '⚠️ in $days days';
      urgencyIcon = Icons.warning_amber;
    } else if (days <= 60) {
      color = AppColors.warning;
      urgencyLabel = isAr ? '⏰ بَعد $days يَوم' : '⏰ in $days days';
      urgencyIcon = Icons.schedule;
    } else if (days <= 90) {
      color = Colors.indigo;
      urgencyLabel = isAr ? '📅 بَعد $days يَوم' : '📅 in $days days';
      urgencyIcon = Icons.event;
    } else {
      color = AppColors.success;
      urgencyLabel = isAr ? '✅ بَعد $days يَوم' : '✅ in $days days';
      urgencyIcon = Icons.check_circle_outline;
    }

    final empId = d['employee_id'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: empId == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EmployeeAggregatedReport(employeeId: empId),
                )),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(urgencyIcon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(empName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      '$empCode · $docType${docNum.isEmpty ? "" : " · #$docNum"}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color.withValues(alpha: 0.3)),
                          ),
                          child: Text(urgencyLabel,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (expiry != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${isAr ? "حتى" : "until"} $expiry',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _docTypeLabel(String? type, bool isAr) {
    if (type == null) return '?';
    switch (type) {
      case 'passport':
        return isAr ? 'جَواز' : 'Passport';
      case 'visa':
        return isAr ? 'إقامة' : 'Visa';
      case 'emirates_id':
        return isAr ? 'هَوِيّة' : 'Emirates ID';
      case 'license':
        return isAr ? 'رُخصة' : 'License';
      case 'work_letter':
        return isAr ? 'خِطاب عَمَل' : 'Work Letter';
      case 'custom':
        return isAr ? 'أُخرى' : 'Custom';
      default:
        return type;
    }
  }
}
