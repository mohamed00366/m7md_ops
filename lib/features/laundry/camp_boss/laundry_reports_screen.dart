// =============================================================================
// ⚠️ شاشة بَلاغات المَفقودات (Missing Reports)
// =============================================================================
import 'package:flutter/material.dart';
import '../../../shared/m7_app_bar.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/status_badge.dart';

class LaundryReportsScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const LaundryReportsScreen({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<LaundryReportsScreen> createState() => _LaundryReportsScreenState();
}

class _LaundryReportsScreenState extends State<LaundryReportsScreen> {
  List<MissingReport> _reports = [];
  bool _loading = true;
  MissingReportStatus? _filter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await LaundryDataSource.instance.listReports(status: _filter);
    if (!mounted) return;
    setState(() {
      _reports = r;
      _loading = false;
    });
  }

  int _count(MissingReportStatus s) =>
      _reports.where((r) => r.status == s).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.danger,
        foregroundColor: Colors.white,
        title: '⚠️ بَلاغات المَفقودات',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _filterBar(),
                Expanded(
                  child: _reports.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('لا تُوجَد بَلاغات',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _reports.length,
                            itemBuilder: (_, i) => _reportTile(_reports[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: LaundryColors.danger.withValues(alpha: 0.08),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('الكُلّ', null, _reports.length),
            const SizedBox(width: 6),
            _filterChip('مَفتوح', MissingReportStatus.open,
                _count(MissingReportStatus.open)),
            const SizedBox(width: 6),
            _filterChip('قَيد المُراجَعة', MissingReportStatus.underReview,
                _count(MissingReportStatus.underReview)),
            const SizedBox(width: 6),
            _filterChip('تَعويض', MissingReportStatus.compensated,
                _count(MissingReportStatus.compensated)),
            const SizedBox(width: 6),
            _filterChip('وُجِدَ', MissingReportStatus.found,
                _count(MissingReportStatus.found)),
            const SizedBox(width: 6),
            _filterChip('مُغلَق', MissingReportStatus.closed,
                _count(MissingReportStatus.closed)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, MissingReportStatus? s, int count) {
    final selected = _filter == s;
    return ChoiceChip(
      label: Text('$label ($count)',
          style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = s;
          _loading = true;
        });
        _load();
      },
      selectedColor: LaundryColors.danger,
      labelStyle: TextStyle(
        color: selected ? Colors.white : LaundryColors.danger,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _reportTile(MissingReport r) {
    final emp = MockRepository().employeeById(r.employeeId);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              _MissingReportDetailScreen(report: r, campBossId: widget.campBossId),
        )).then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LaundryStatusBadge.forReport(r.status),
                  const Spacer(),
                  Text(r.reportNumber,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 8),
              Text(emp?.fullName ?? '—',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 14, color: LaundryColors.danger),
                  const SizedBox(width: 4),
                  Text('${r.totalMissingItems} قِطعة مَفقودة',
                      style: const TextStyle(
                          fontSize: 12,
                          color: LaundryColors.danger,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(_fmtDate(r.createdAt),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

// =============================================================================
// شاشة تَفاصيل بَلاغ + الحَلّ
// =============================================================================
class _MissingReportDetailScreen extends StatefulWidget {
  final MissingReport report;
  final String campBossId;

  const _MissingReportDetailScreen({
    required this.report,
    required this.campBossId,
  });

  @override
  State<_MissingReportDetailScreen> createState() =>
      _MissingReportDetailScreenState();
}

class _MissingReportDetailScreenState
    extends State<_MissingReportDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _resolutionCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _resolutionCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve(MissingReportStatus newStatus) async {
    if (_resolutionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتُب القَرار/الحَلّ أَوّلاً'),
      ));
      return;
    }
    setState(() => _busy = true);
    final ok = await LaundryDataSource.instance.resolveReport(
      reportId: widget.report.id,
      newStatus: newStatus,
      note: _resolutionCtrl.text.trim(),
      resolvedBy: widget.campBossId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✓ تَمّ تَحديث البَلاغ إلى "${newStatus.labelAr}"'),
      ));
      Navigator.of(context).pop();
    }
  }

  Future<void> _addComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await LaundryDataSource.instance.addReportComment(
      reportId: widget.report.id,
      userId: widget.campBossId,
      comment: _commentCtrl.text.trim(),
    );
    if (!mounted) return;
    _commentCtrl.clear();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      backgroundColor: LaundryColors.success,
      content: Text('✓ تَمّت إضافة تَعليقك'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final emp = MockRepository().employeeById(r.employeeId);

    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.danger,
        foregroundColor: Colors.white,
        title: 'بَلاغ ${r.reportNumber}',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // رَأس البَلاغ
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LaundryColors.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LaundryColors.danger.withValues(alpha: 0.40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(emp?.fullName ?? '—',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                    LaundryStatusBadge.forReport(r.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text('الكود: ${emp?.code ?? "—"}',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.inventory_2,
                        color: LaundryColors.danger),
                    const SizedBox(width: 8),
                    Text('${r.totalMissingItems} قِطعة مَفقودة',
                        style: const TextStyle(
                            fontSize: 20,
                            color: LaundryColors.danger,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // إضافة تَعليق
          const Text('💬 إضافة تَعليق',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _commentCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'اكتُب مُلاحَظة أَو تَحديث...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.send, size: 14),
              label: const Text('إرسال التَعليق'),
              onPressed: _busy ? null : _addComment,
            ),
          ),
          const SizedBox(height: 16),

          // حَلّ البَلاغ
          if (r.status == MissingReportStatus.open ||
              r.status == MissingReportStatus.underReview) ...[
            const Divider(),
            const Text('✅ حَلّ البَلاغ',
                style:
                    TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _resolutionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'القَرار / الحَلّ *',
                hintText: 'مَثَلاً: تَمّ خَصم مِن المَغسلة · المَلابِس وُجِدَت...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LaundryColors.info,
                    side: const BorderSide(color: LaundryColors.info),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('وُجِدَت'),
                  onPressed: _busy
                      ? null
                      : () => _resolve(MissingReportStatus.found),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LaundryColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.payments, size: 16),
                  label: const Text('تَعويض'),
                  onPressed: _busy
                      ? null
                      : () => _resolve(MissingReportStatus.compensated),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('إغلاق'),
                  onPressed: _busy
                      ? null
                      : () => _resolve(MissingReportStatus.closed),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
