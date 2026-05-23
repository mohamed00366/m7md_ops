// =============================================================================
// 💰 شاشة تَتَبُّع البَقاشيش (Driver Tips)
// =============================================================================
// تَعرِض:
//   - Leaderboard (أَعلى السائِقين بَقاشيش هذا الشَهر)
//   - زِرّ إضافة بَقشيش جَديد
//   - فِلتَر بِالفَترة
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/driver_tips_service.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_empty_state.dart';

class DriverTipsScreen extends StatefulWidget {
  const DriverTipsScreen({super.key});

  @override
  State<DriverTipsScreen> createState() => _DriverTipsScreenState();
}

enum _Period { today, week, month, all }

class _DriverTipsScreenState extends State<DriverTipsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _leaderboard = const [];
  _Period _period = _Period.month;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({DateTime? from, DateTime? to}) _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return (from: DateTime(now.year, now.month, now.day), to: now);
      case _Period.week:
        return (from: now.subtract(const Duration(days: 7)), to: now);
      case _Period.month:
        return (from: DateTime(now.year, now.month, 1), to: now);
      case _Period.all:
        return (from: null, to: null);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = _range();
    final data = await DriverTipsService.instance.leaderboard(
      from: r.from,
      to: r.to,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _leaderboard = data;
      _loading = false;
    });
  }

  Future<void> _addTipDialog() async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final drivers = repo.employees.where((e) => e.licenseNumber.isNotEmpty).toList();
    String? selectedDriverId;
    final amountCtrl = TextEditingController();
    String source = 'cash';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isAr ? '💰 تَسجيل بَقشيش' : '💰 Record Tip'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedDriverId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'السائِق' : 'Driver',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: drivers.map((d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(d.fullName,
                            overflow: TextOverflow.ellipsis),
                      )).toList(),
                  onChanged: (v) => setLocal(() => selectedDriverId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isAr ? 'المَبلَغ (AED)' : 'Amount (AED)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(isAr ? 'نَقد' : 'Cash',
                          style: const TextStyle(fontSize: 12)),
                      value: 'cash',
                      groupValue: source,
                      onChanged: (v) => setLocal(() => source = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(isAr ? 'بِطاقة' : 'Card',
                          style: const TextStyle(fontSize: 12)),
                      value: 'card',
                      groupValue: source,
                      onChanged: (v) => setLocal(() => source = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(isAr ? 'تَطبيق' : 'App',
                          style: const TextStyle(fontSize: 12)),
                      value: 'app',
                      groupValue: source,
                      onChanged: (v) => setLocal(() => source = v!),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isAr ? 'إلغاء' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (selectedDriverId == null || amt == null || amt <= 0) {
                  return;
                }
                final auth = context.read<AuthProvider>();
                final ok = await DriverTipsService.instance.add(
                  employeeId: selectedDriverId!,
                  amount: amt,
                  source: source,
                  recordedBy: auth.account?.id,
                  countryId: auth.activeCountryId,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted && ok != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.success,
                    content: Text(isAr
                        ? '✅ تَمّ تَسجيل البَقشيش'
                        : '✅ Tip recorded'),
                  ));
                  _load();
                }
              },
              child: Text(isAr ? 'حِفظ' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final totalTips = _leaderboard.fold<double>(
        0, (sum, m) => sum + ((m['total_tips'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '💰 البَقاشيش' : '💰 Tips',
        subtitle: isAr
            ? 'إجماليّ ${totalTips.toStringAsFixed(0)} AED'
            : 'Total ${totalTips.toStringAsFixed(0)} AED',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTipDialog,
        icon: const Icon(Icons.add),
        label: Text(isAr ? 'بَقشيش' : 'Tip'),
        backgroundColor: AppColors.brand,
      ),
      body: Column(
        children: [
          // ===== فِلتَر الفَترة =====
          Padding(
            padding: const EdgeInsets.all(10),
            child: SegmentedButton<_Period>(
              segments: [
                ButtonSegment(
                    value: _Period.today,
                    label: Text(isAr ? 'اليَوم' : 'Today')),
                ButtonSegment(
                    value: _Period.week,
                    label: Text(isAr ? 'أُسبوع' : 'Week')),
                ButtonSegment(
                    value: _Period.month,
                    label: Text(isAr ? 'شَهر' : 'Month')),
                ButtonSegment(
                    value: _Period.all, label: Text(isAr ? 'الكُلّ' : 'All')),
              ],
              selected: {_period},
              onSelectionChanged: (v) {
                setState(() => _period = v.first);
                _load();
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _leaderboard.isEmpty
                    ? M7EmptyState(
                        icon: Icons.attach_money,
                        titleAr: 'لا تَوجَد بَقاشيش بَعد',
                        titleEn: 'No tips recorded yet',
                        subtitleAr:
                            'اضغَط الزِرّ الأَخضَر لِتَسجيل أَوَّل بَقشيش',
                        subtitleEn:
                            'Tap the + button to record the first tip',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _leaderboard.length,
                        itemBuilder: (_, i) => _LeaderTile(
                          rank: i + 1,
                          data: _leaderboard[i],
                          isAr: isAr,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LeaderTile extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> data;
  final bool isAr;
  const _LeaderTile({
    required this.rank,
    required this.data,
    required this.isAr,
  });

  Color get _rankColor {
    if (rank == 1) return Colors.amber;
    if (rank == 2) return Colors.grey;
    if (rank == 3) return Colors.brown;
    return AppColors.brand;
  }

  IconData get _rankIcon {
    if (rank <= 3) return Icons.emoji_events;
    return Icons.person;
  }

  @override
  Widget build(BuildContext context) {
    final total = (data['total_tips'] as num?)?.toDouble() ?? 0;
    final count = (data['tip_count'] as num?)?.toInt() ?? 0;
    final name = data['full_name'] as String? ?? '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _rankColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _rankColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: rank <= 3
                ? Icon(_rankIcon, color: _rankColor, size: 22)
                : Center(
                    child: Text('#$rank',
                        style: TextStyle(
                          color: _rankColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        )),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  isAr ? '$count بَقشيش' : '$count tips',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${total.toStringAsFixed(0)} AED',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.success,
                ),
              ),
              Text(
                isAr ? 'الإجماليّ' : 'Total',
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
