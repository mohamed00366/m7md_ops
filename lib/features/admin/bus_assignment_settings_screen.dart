import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/bus_assignment_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🚌 شاشة إعدادات إسناد الباصات
///
/// تتيح للمسؤول تحديد:
///   1. أيّ مسمّيات وظيفيّة تظهر كسائقين عند اختيار سائق للباص
///   2. أيّ مسمّيات يُسمح لها أن تركب الباص (افتراضيّاً: الكل)
class BusAssignmentSettingsScreen extends StatefulWidget {
  const BusAssignmentSettingsScreen({super.key});

  @override
  State<BusAssignmentSettingsScreen> createState() =>
      _BusAssignmentSettingsScreenState();
}

class _BusAssignmentSettingsScreenState
    extends State<BusAssignmentSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  Set<String> _drivers = {};
  Set<String> _passengers = {};
  bool _hasDriverCustom = false;
  bool _hasPassengerCustom = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
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

  Future<void> _load() async {
    await BusAssignmentSettings.instance.load();
    if (!mounted) return;
    setState(() {
      _drivers = Set.from(BusAssignmentSettings.instance.currentDrivers);
      _passengers = Set.from(BusAssignmentSettings.instance.currentPassengers);
      _hasDriverCustom = BusAssignmentSettings.instance.hasDriverCustom;
      _hasPassengerCustom = BusAssignmentSettings.instance.hasPassengerCustom;
      _loaded = true;
      // إن لم يكن مخصّصاً → اعرض الافتراضيّ كقيم مفعّلة
      if (!_hasDriverCustom) {
        _drivers = _defaultDriverIds(MockRepository());
      }
    });
  }

  /// القاعدة الافتراضيّة للسائقين: مسمّى "Bus Driver"
  Set<String> _defaultDriverIds(MockRepository repo) {
    final result = <String>{};
    for (final j in repo.jobTitles) {
      if (j.nameEn == 'Bus Driver' || j.nameAr == 'سائق باص') {
        result.add(j.id);
      }
    }
    return result;
  }

  Future<void> _saveDrivers() async {
    await BusAssignmentSettings.instance.setDrivers(_drivers);
    if (!mounted) return;
    setState(() => _hasDriverCustom = true);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تم حفظ ${_drivers.length} مسمّى للسائقين'
          : '✅ Saved ${_drivers.length} driver titles'),
    ));
  }

  Future<void> _savePassengers() async {
    await BusAssignmentSettings.instance.setPassengers(_passengers);
    if (!mounted) return;
    setState(() => _hasPassengerCustom = true);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تم حفظ ${_passengers.length} مسمّى للركّاب'
          : '✅ Saved ${_passengers.length} passenger titles'),
    ));
  }

  Future<void> _resetDrivers() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'استعادة الافتراضيّ: مسمّى "Bus Driver" فقط؟'
            : 'Reset to default: "Bus Driver" only?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.isAr ? 'استعادة' : 'Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await BusAssignmentSettings.instance.resetDrivers();
    setState(() {
      _hasDriverCustom = false;
      _drivers = _defaultDriverIds(MockRepository());
    });
  }

  Future<void> _resetPassengers() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'استعادة الافتراضيّ: كل المسمّيات مؤهّلة كركّاب؟'
            : 'Reset to default: all titles eligible as passengers?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.isAr ? 'استعادة' : 'Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await BusAssignmentSettings.instance.resetPassengers();
    setState(() {
      _hasPassengerCustom = false;
      _passengers = {};
    });
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إعدادات إسناد الباصات' : 'Bus Assignment Settings',
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
                icon: const Icon(Icons.local_taxi, size: 16),
                text: isAr ? 'السائقون' : 'Drivers'),
            Tab(
                icon: const Icon(Icons.airline_seat_recline_normal, size: 16),
                text: isAr ? 'الركّاب' : 'Passengers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DriversTab(
            selected: _drivers,
            hasCustom: _hasDriverCustom,
            isAr: isAr,
            onToggle: (id) {
              setState(() {
                if (_drivers.contains(id)) {
                  _drivers.remove(id);
                } else {
                  _drivers.add(id);
                }
              });
            },
            onSave: _saveDrivers,
            onReset: _resetDrivers,
            dirty: !_setEquals(
              _drivers,
              _hasDriverCustom
                  ? BusAssignmentSettings.instance.currentDrivers
                  : _defaultDriverIds(MockRepository()),
            ),
          ),
          _PassengersTab(
            selected: _passengers,
            hasCustom: _hasPassengerCustom,
            isAr: isAr,
            onToggle: (id) {
              setState(() {
                if (_passengers.contains(id)) {
                  _passengers.remove(id);
                } else {
                  _passengers.add(id);
                }
              });
            },
            onSave: _savePassengers,
            onReset: _resetPassengers,
            dirty: _hasPassengerCustom
                ? !_setEquals(
                    _passengers,
                    BusAssignmentSettings.instance.currentPassengers)
                : _passengers.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب السائقين
// ============================================================
class _DriversTab extends StatelessWidget {
  final Set<String> selected;
  final bool hasCustom;
  final bool isAr;
  final ValueChanged<String> onToggle;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final bool dirty;

  const _DriversTab({
    required this.selected,
    required this.hasCustom,
    required this.isAr,
    required this.onToggle,
    required this.onSave,
    required this.onReset,
    required this.dirty,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final allTitles = repo.jobTitles.toList()
      ..sort((a, b) {
        final lc = a.level.compareTo(b.level);
        if (lc != 0) return lc;
        return a.nameAr.compareTo(b.nameAr);
      });

    return Column(
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_taxi,
                  color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'مَن يظهر في شاشة "اختر سائقاً" للباص؟'
                          : 'Who appears in "Pick a Driver" for buses?',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? 'فعّل المسمّيات التي يحقّ لحامليها قيادة الباصات'
                          : 'Enable titles whose holders can drive buses',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Status badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (hasCustom)
                _statusChip(
                    icon: Icons.tune,
                    label: isAr ? 'مخصّص' : 'Custom',
                    color: AppColors.warning)
              else
                _statusChip(
                    icon: Icons.auto_awesome,
                    label: isAr ? 'الافتراضي' : 'Default',
                    color: AppColors.info),
              const SizedBox(width: 6),
              _statusChip(
                  icon: Icons.check_circle_outline,
                  label: isAr
                      ? 'مفعَّل: ${selected.length}'
                      : 'Enabled: ${selected.length}',
                  color: AppColors.success),
              const Spacer(),
              if (hasCustom)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restore, size: 14),
                  label: Text(isAr ? 'استعادة' : 'Reset',
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            itemCount: allTitles.length,
            itemBuilder: (_, i) {
              final jt = allTitles[i];
              return _TitleRow(
                jobTitle: jt,
                isSelected: selected.contains(jt.id),
                isAr: isAr,
                onToggle: () => onToggle(jt.id),
                accent: AppColors.brand,
              );
            },
          ),
        ),
        if (dirty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    isAr
                        ? '💾 حفظ (${selected.length} مسمّى)'
                        : '💾 Save (${selected.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// تاب الركّاب
// ============================================================
class _PassengersTab extends StatelessWidget {
  final Set<String> selected;
  final bool hasCustom;
  final bool isAr;
  final ValueChanged<String> onToggle;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final bool dirty;

  const _PassengersTab({
    required this.selected,
    required this.hasCustom,
    required this.isAr,
    required this.onToggle,
    required this.onSave,
    required this.onReset,
    required this.dirty,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final allTitles = repo.jobTitles.toList()
      ..sort((a, b) {
        final lc = a.level.compareTo(b.level);
        if (lc != 0) return lc;
        return a.nameAr.compareTo(b.nameAr);
      });

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.airline_seat_recline_normal,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'مَن يحقّ له ركوب الباص؟'
                          : 'Who can ride the bus?',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? 'افتراضيّاً: كل المسمّيات. خصّص لتقييد قائمة المرشّحين عند الإسناد.'
                          : 'Default: all titles. Customize to restrict candidates.',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (hasCustom)
                _statusChip(
                    icon: Icons.tune,
                    label: isAr ? 'مخصّص' : 'Custom',
                    color: AppColors.warning)
              else
                _statusChip(
                    icon: Icons.all_inclusive,
                    label: isAr ? 'الكل' : 'All',
                    color: AppColors.info),
              const Spacer(),
              if (hasCustom)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restore, size: 14),
                  label: Text(isAr ? 'استعادة' : 'Reset',
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            itemCount: allTitles.length,
            itemBuilder: (_, i) {
              final jt = allTitles[i];
              return _TitleRow(
                jobTitle: jt,
                isSelected: !hasCustom || selected.contains(jt.id),
                isAr: isAr,
                onToggle: () => onToggle(jt.id),
                accent: AppColors.success,
              );
            },
          ),
        ),
        if (dirty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    isAr
                        ? '💾 حفظ (${selected.length} مسمّى)'
                        : '💾 Save (${selected.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final JobTitle jobTitle;
  final bool isSelected;
  final bool isAr;
  final VoidCallback onToggle;
  final Color accent;

  const _TitleRow({
    required this.jobTitle,
    required this.isSelected,
    required this.isAr,
    required this.onToggle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.5)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (_) => onToggle(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobTitle.displayName(isAr),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                  Text(
                    isAr
                        ? jobTitle.category.labelAr()
                        : jobTitle.category.labelEn(),
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L${jobTitle.level}',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _statusChip(
    {required IconData icon, required String label, required Color color}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

