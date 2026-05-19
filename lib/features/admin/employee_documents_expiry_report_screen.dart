import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/employee_documents_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import 'employee_documents_screen.dart';

/// 📅 تَقرير الوَثائِق المُنتَهية / المُقتَرِبة من الانتِهاء
///
/// يَعرِض لِلـHR جَميع الوَثائِق التي:
///   🔴 مُنتَهية بِالفِعل
///   🟠 تَنتَهي خِلال ٧ أَيّام
///   🟡 تَنتَهي خِلال ٣٠ يَوم
///   🟢 تَنتَهي خِلال ٩٠ يَوم
///
/// مُجَمَّعة بِحَسَب الإلحاحيّة. كُلّ صَفّ يَفتَح شاشة وَثائِق الموظَّف.
class EmployeeDocumentsExpiryReportScreen extends StatefulWidget {
  const EmployeeDocumentsExpiryReportScreen({super.key});

  @override
  State<EmployeeDocumentsExpiryReportScreen> createState() =>
      _EmployeeDocumentsExpiryReportScreenState();
}

class _EmployeeDocumentsExpiryReportScreenState
    extends State<EmployeeDocumentsExpiryReportScreen> {
  bool _loading = true;
  List<_ExpiryRow> _rows = [];
  String _filter = '';
  // أَيّام النَظَر إلى الأَمام (افتِراضيّ ٩٠)
  int _lookaheadDays = 90;
  // 🆕 العَدَد الإجماليّ لِلوَثائِق في النِظام (لِلتَمييز بَين "لا بَيانات" وَ"كُلّها سارية")
  int _totalDocsInSystem = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      // 🆕 اقرَأ العَدَد الإجماليّ أَوَّلاً لِنَعرِف الفَرق بَين:
      //   - "لا وَثائِق في النِظام بَعد" (يَحتاج الإدارة لِبَدء رَفع)
      //   - "كُلّ الوَثائِق سارية" (الإدارة تَعمَل بِشَكل جَيّد)
      try {
        final allRows = await supa.client
            .from('employee_documents')
            .select('id')
            .eq('status', 'active')
            .limit(1);
        _totalDocsInSystem = (allRows as List).isEmpty ? 0 : 1;
        // العَدَد الفِعليّ مَعروف فَقَط إذا كان فيها بَيانات
        if ((allRows).isNotEmpty) {
          final cnt = await supa.client
              .from('employee_documents')
              .select('id')
              .eq('status', 'active');
          _totalDocsInSystem = (cnt as List).length;
        }
      } catch (_) {
        _totalDocsInSystem = 0;
      }

      // اقرَأ كُلّ الوَثائِق النَشِطة التي لَدَيها تاريخ انتِهاء
      // ضِمن النَطاق المُحَدَّد (المُنتَهية + المُقتَرِبة)
      final upperBound = DateTime.now()
          .add(Duration(days: _lookaheadDays))
          .toIso8601String()
          .substring(0, 10);
      final rows = await supa.client
          .from('employee_documents')
          .select(
              'id, employee_id, doc_type, doc_type_label, version_number, '
              'document_number, expiry_date, status')
          .eq('status', 'active')
          .not('expiry_date', 'is', null)
          .lte('expiry_date', upperBound)
          .order('expiry_date', ascending: true);
      final repo = MockRepository();
      final list = (rows as List).cast<Map<String, dynamic>>();
      _rows = list.map((r) {
        final emp = repo.employeeById(r['employee_id'] as String?);
        final expiry =
            DateTime.tryParse((r['expiry_date'] as String?) ?? '');
        final days = expiry == null
            ? 9999
            : expiry.difference(DateTime.now()).inDays;
        return _ExpiryRow(
          documentId: r['id'] as String,
          employeeId: r['employee_id'] as String,
          employee: emp,
          docType: EmpDocTypeX.fromKey(r['doc_type'] as String?),
          docTypeLabel: r['doc_type_label'] as String?,
          versionNumber: (r['version_number'] as num?)?.toInt() ?? 1,
          documentNumber: r['document_number'] as String?,
          expiryDate: expiry,
          daysToExpiry: days,
        );
      }).where((r) => r.employee != null).toList();
    } catch (e) {
      M7Log.error('ExpiryReport', 'load', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openEmployee(_ExpiryRow row) {
    final emp = row.employee;
    if (emp == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeeDocumentsScreen(employee: emp),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final query = _filter.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _rows
        : _rows.where((r) {
            final name = r.employee?.fullName.toLowerCase() ?? '';
            final code = r.employee?.code.toLowerCase() ?? '';
            return name.contains(query) || code.contains(query);
          }).toList();

    // اجمَعها حَسَب الإلحاحيّة
    final expired = filtered.where((r) => r.daysToExpiry < 0).toList();
    final week = filtered
        .where((r) => r.daysToExpiry >= 0 && r.daysToExpiry <= 7)
        .toList();
    final month = filtered
        .where((r) => r.daysToExpiry > 7 && r.daysToExpiry <= 30)
        .toList();
    final later = filtered.where((r) => r.daysToExpiry > 30).toList();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr
            ? '📅 تَقرير وَثائِق المُوَظَّفين'
            : '📅 Documents Expiry Report',
        subtitle: isAr
            ? '${filtered.length} وَثيقة'
            : '${filtered.length} documents',
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_alt, color: AppColors.gold),
            onSelected: (v) {
              setState(() => _lookaheadDays = v);
              _load();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 30,
                child: Text(isAr ? '٣٠ يَوم' : '30 days'),
              ),
              PopupMenuItem(
                value: 60,
                child: Text(isAr ? '٦٠ يَوم' : '60 days'),
              ),
              PopupMenuItem(
                value: 90,
                child: Text(isAr ? '٩٠ يَوم' : '90 days'),
              ),
              PopupMenuItem(
                value: 180,
                child: Text(isAr ? '٦ أَشهُر' : '6 months'),
              ),
            ],
          ),
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // إحصاءات سَريعة
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _statBox(
                    isAr ? 'مُنتَهية' : 'Expired',
                    expired.length,
                    AppColors.danger,
                    Icons.error),
                const SizedBox(width: 6),
                _statBox(
                    isAr ? 'خِلال أُسبوع' : 'This week',
                    week.length,
                    AppColors.warning,
                    Icons.warning_amber),
                const SizedBox(width: 6),
                _statBox(
                    isAr ? 'خِلال شَهر' : 'This month',
                    month.length,
                    AppColors.gold,
                    Icons.event_busy),
                const SizedBox(width: 6),
                _statBox(
                    isAr ? 'لاحِقاً' : 'Later',
                    later.length,
                    AppColors.info,
                    Icons.schedule),
              ],
            ),
          ),
          // البَحث
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr
                    ? 'ابحَث بِاسم أَو كود المُوَظَّف…'
                    : 'Search by name or code…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          // القائِمة
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              if (_totalDocsInSystem == 0) ...[
                                // 🆕 لا وَثائِق مُسَجَّلة في النِظام بَعد
                                Icon(Icons.folder_open,
                                    size: 80,
                                    color: AppColors.warning
                                        .withOpacity(0.50)),
                                const SizedBox(height: 12),
                                Text(
                                  isAr
                                      ? '📋 لا وَثائِق مُسَجَّلة بَعد'
                                      : '📋 No documents registered yet',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16),
                                  child: Text(
                                    isAr
                                        ? 'ابدَأ بِفَتح أَحَد المُوَظَّفين، ثُمَّ اضغَط بِطاقة "📄 وَثائِق الموظَّف" لِرَفع وَثيقة جَديدة.'
                                        : 'Open any employee, then tap "📄 Employee Documents" card to upload a new document.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        height: 1.5),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  icon: const Icon(Icons.people),
                                  label: Text(isAr
                                      ? 'فَتح قائِمة المُوَظَّفين'
                                      : 'Open Employees'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brand,
                                    foregroundColor: Colors.white,
                                    minimumSize:
                                        const Size(220, 44),
                                  ),
                                ),
                              ] else ...[
                                const Icon(Icons.check_circle,
                                    size: 80,
                                    color: AppColors.success),
                                const SizedBox(height: 12),
                                Text(
                                  isAr
                                      ? '✅ كُلّ الوَثائِق سارية'
                                      : '✅ All documents are valid',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isAr
                                      ? '$_totalDocsInSystem وَثيقة · لا انتِهاء خِلال $_lookaheadDays يَوم'
                                      : '$_totalDocsInSystem docs · None expiring in $_lookaheadDays days',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            if (expired.isNotEmpty)
                              _sectionHeader(
                                  isAr
                                      ? '🔴 مُنتَهية الصَلاحيّة'
                                      : '🔴 Expired',
                                  expired.length,
                                  AppColors.danger),
                            ...expired
                                .map((r) => _row(r, AppColors.danger)),
                            if (week.isNotEmpty)
                              _sectionHeader(
                                  isAr
                                      ? '🟠 تَنتَهي خِلال أُسبوع'
                                      : '🟠 Expires within a week',
                                  week.length,
                                  AppColors.warning),
                            ...week.map((r) => _row(r, AppColors.warning)),
                            if (month.isNotEmpty)
                              _sectionHeader(
                                  isAr
                                      ? '🟡 تَنتَهي خِلال شَهر'
                                      : '🟡 Expires within a month',
                                  month.length,
                                  AppColors.gold),
                            ...month.map((r) => _row(r, AppColors.gold)),
                            if (later.isNotEmpty)
                              _sectionHeader(
                                  isAr ? '🟢 لاحِقاً' : '🟢 Later',
                                  later.length,
                                  AppColors.info),
                            ...later.map((r) => _row(r, AppColors.info)),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text('$value',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            Text(label,
                style:
                    const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: color)),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _row(_ExpiryRow r, Color color) {
    final isAr = AppStrings.of(context).isAr;
    final emp = r.employee!;
    final daysLabel = r.daysToExpiry < 0
        ? (isAr
            ? 'مَضى ${(-r.daysToExpiry)} يَوم'
            : '${(-r.daysToExpiry)}d ago')
        : (isAr
            ? 'بَعد ${r.daysToExpiry} يَوم'
            : 'in ${r.daysToExpiry}d');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: ListTile(
        onTap: () => _openEmployee(r),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Text(
            emp.fullName.isNotEmpty
                ? emp.fullName.substring(0, 1).toUpperCase()
                : '?',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(emp.fullName,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emp.code,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontFamily: 'monospace')),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAr
                          ? r.docType.labelAr()
                          : r.docType.labelEn(),
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (r.documentNumber != null) ...[
                    const SizedBox(width: 4),
                    Text('· ${r.documentNumber}',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              r.expiryDate == null
                  ? '—'
                  : '${r.expiryDate!.year}-${r.expiryDate!.month.toString().padLeft(2, '0')}-${r.expiryDate!.day.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700),
            ),
            Text(daysLabel,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _ExpiryRow {
  final String documentId;
  final String employeeId;
  final Employee? employee;
  final EmpDocType docType;
  final String? docTypeLabel;
  final int versionNumber;
  final String? documentNumber;
  final DateTime? expiryDate;
  final int daysToExpiry;
  const _ExpiryRow({
    required this.documentId,
    required this.employeeId,
    required this.employee,
    required this.docType,
    required this.docTypeLabel,
    required this.versionNumber,
    required this.documentNumber,
    required this.expiryDate,
    required this.daysToExpiry,
  });
}
