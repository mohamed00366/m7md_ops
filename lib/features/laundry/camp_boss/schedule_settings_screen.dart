// =============================================================================
// ⏰ إعدادات أَوقات الكَمب بُوص
// =============================================================================
import 'package:flutter/material.dart';

import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';

const _dayNames = [
  'السَبت', 'الأَحَد', 'الإثنَين', 'الثُلاثاء',
  'الأَربِعاء', 'الخَميس', 'الجُمعة'
];

class ScheduleSettingsScreen extends StatefulWidget {
  final String campBossId;
  const ScheduleSettingsScreen({super.key, required this.campBossId});

  @override
  State<ScheduleSettingsScreen> createState() => _ScheduleSettingsScreenState();
}

class _ScheduleSettingsScreenState extends State<ScheduleSettingsScreen> {
  CampBossSchedule? _schedule;
  bool _loading = true;
  bool _saving = false;

  TimeOfDay _receiveStart = const TimeOfDay(hour: 15, minute: 0);
  TimeOfDay _receiveEnd = const TimeOfDay(hour: 4, minute: 0);
  TimeOfDay _deliverStart = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _deliverEnd = const TimeOfDay(hour: 8, minute: 0);
  List<int> _receiveDays = [0, 1, 2, 3, 4, 6];
  List<int> _deliverDays = [0, 1, 2, 3, 4, 6];
  bool _disableOutsideHours = true;
  bool _showToEmployees = true;
  bool _allowScheduled = true;
  bool _emergency = false;
  final _emergencyReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s =
        await LaundryDataSource.instance.getSchedule(widget.campBossId);
    if (!mounted) return;
    if (s != null) {
      setState(() {
        _schedule = s;
        _receiveStart = _parse(s.receiveStartTime);
        _receiveEnd = _parse(s.receiveEndTime);
        _deliverStart = _parse(s.deliverStartTime);
        _deliverEnd = _parse(s.deliverEndTime);
        _receiveDays = List.from(s.receiveDays);
        _deliverDays = List.from(s.deliverDays);
        _disableOutsideHours = s.disableNotificationsOutsideHours;
        _showToEmployees = s.showAvailabilityToEmployees;
        _allowScheduled = s.allowScheduledRequests;
        _emergency = s.emergencyModeActive;
        _emergencyReasonCtrl.text = s.emergencyReason ?? '';
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  TimeOfDay _parse(String s) {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await LaundryDataSource.instance.upsertSchedule(
      campBossId: widget.campBossId,
      receiveStartTime: _fmt(_receiveStart),
      receiveEndTime: _fmt(_receiveEnd),
      receiveDays: _receiveDays,
      deliverStartTime: _fmt(_deliverStart),
      deliverEndTime: _fmt(_deliverEnd),
      deliverDays: _deliverDays,
      disableNotificationsOutsideHours: _disableOutsideHours,
      showAvailabilityToEmployees: _showToEmployees,
      allowScheduledRequests: _allowScheduled,
      emergencyModeActive: _emergency,
      emergencyReason:
          _emergencyReasonCtrl.text.trim().isEmpty ? null : _emergencyReasonCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? LaundryColors.success : LaundryColors.danger,
      duration: Duration(seconds: ok ? 2 : 6),
      content: Text(
        ok
            ? '✅ تَمّ الحِفظ'
            : '❌ ${LaundryDataSource.instance.lastError ?? "فَشَل الحِفظ"}',
        style: const TextStyle(fontSize: 12),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: const Text('⏰ إعدادات الأَوقات'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _section('📥 ساعات الاستِلام مِن المُوَظَّفين'),
                _timeRow('مِن', _receiveStart,
                    (t) => setState(() => _receiveStart = t)),
                _timeRow('إلى', _receiveEnd,
                    (t) => setState(() => _receiveEnd = t)),
                _daysSelector(_receiveDays,
                    (d) => setState(() => _receiveDays = d)),
                const SizedBox(height: 20),
                _section('📤 ساعات تَسليم النَظيف لِلمُوَظَّفين'),
                _timeRow('مِن', _deliverStart,
                    (t) => setState(() => _deliverStart = t)),
                _timeRow('إلى', _deliverEnd,
                    (t) => setState(() => _deliverEnd = t)),
                _daysSelector(_deliverDays,
                    (d) => setState(() => _deliverDays = d)),
                const SizedBox(height: 20),
                _section('⚙️ إعدادات إضافيّة'),
                SwitchListTile(
                  title: const Text('إيقاف الإشعارات خارِج الأَوقات'),
                  value: _disableOutsideHours,
                  onChanged: (v) => setState(() => _disableOutsideHours = v),
                ),
                SwitchListTile(
                  title: const Text('عَرض حالة التَوَفُّر لِلمُوَظَّفين'),
                  value: _showToEmployees,
                  onChanged: (v) => setState(() => _showToEmployees = v),
                ),
                SwitchListTile(
                  title: const Text('السَماح بِالطَلَبات المُجَدوَلة'),
                  value: _allowScheduled,
                  onChanged: (v) => setState(() => _allowScheduled = v),
                ),
                const SizedBox(height: 20),
                _section('🚨 وَضع الطوارِئ'),
                SwitchListTile(
                  title: const Text('تَفعيل وَضع الطوارِئ',
                      style: TextStyle(color: LaundryColors.danger)),
                  subtitle: const Text('إغلاق فَوريّ مَع رِسالة لِلمُوَظَّفين'),
                  value: _emergency,
                  onChanged: (v) => setState(() => _emergency = v),
                ),
                if (_emergency)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _emergencyReasonCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'سَبَب الإغلاق',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: LaundryColors.primary)),
      );

  Widget _timeRow(
      String label, TimeOfDay current, ValueChanged<TimeOfDay> onChanged) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.access_time),
        title: Text(label),
        trailing: Text(_fmt(current),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900)),
        onTap: () async {
          final picked =
              await showTimePicker(context: context, initialTime: current);
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }

  Widget _daysSelector(List<int> selected, ValueChanged<List<int>> onChanged) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 6,
          children: List.generate(7, (i) {
            final isOn = selected.contains(i);
            return FilterChip(
              label: Text(_dayNames[i]),
              selected: isOn,
              onSelected: (v) {
                final newList = List<int>.from(selected);
                if (v) {
                  if (!newList.contains(i)) newList.add(i);
                } else {
                  newList.remove(i);
                }
                onChanged(newList);
              },
            );
          }),
        ),
      ),
    );
  }
}
