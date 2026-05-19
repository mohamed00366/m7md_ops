import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/country_guard.dart';
import '../camp_palette.dart';
import 'buses_shared.dart';

/// 📝 محرّر الباص - إنشاء أو تعديل
class BusEditorSheet extends StatefulWidget {
  final Bus? existing;
  const BusEditorSheet({super.key, this.existing});

  @override
  State<BusEditorSheet> createState() => _BusEditorSheetState();
}

class _BusEditorSheetState extends State<BusEditorSheet> {
  late final TextEditingController _plate;
  late final TextEditingController _capacity;
  late final TextEditingController _model;
  late final TextEditingController _color;
  late final TextEditingController _year;
  late final TextEditingController _notes;

  String? _driverId;
  String? _pointId;
  TimeOfDay? _morning;
  TimeOfDay? _evening;
  late Set<int> _days;
  EntityStatus _status = EntityStatus.active;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _plate = TextEditingController(text: b?.plateNumber ?? '');
    _capacity =
        TextEditingController(text: (b?.capacity ?? 30).toString());
    _model = TextEditingController(text: b?.model ?? '');
    _color = TextEditingController(text: b?.color ?? '');
    _year = TextEditingController(text: b?.year?.toString() ?? '');
    _notes = TextEditingController(text: b?.notes ?? '');
    _driverId = b?.driverId;
    _pointId = b?.assignedPointId;
    _morning = _parseTime(b?.morningTime);
    _evening = _parseTime(b?.eveningTime);
    _days = b?.scheduleDays.toSet() ?? {0, 1, 2, 3, 4};
    _status = b?.status ?? EntityStatus.active;
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String? _formatTime(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _plate.dispose();
    _capacity.dispose();
    _model.dispose();
    _color.dispose();
    _year.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isMorning}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: (isMorning ? _morning : _evening) ??
          (isMorning
              ? const TimeOfDay(hour: 6, minute: 0)
              : const TimeOfDay(hour: 18, minute: 0)),
    );
    if (t != null) {
      setState(() {
        if (isMorning) {
          _morning = t;
        } else {
          _evening = t;
        }
      });
    }
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_plate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.isAr ? 'أدخل رقم اللوحة' : 'Enter plate number')));
      return;
    }
    if (!_isEdit) {
      // عند الإنشاء فقط: تأكيد الدولة
      if (!await CountryGuard.require(context,
          entityName: s.isAr ? 'إنشاء باص' : 'creating a bus')) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final activeCountry = auth.activeCountryId;
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();

    String name = widget.existing?.name ?? '';
    if (!_isEdit) {
      // ولّد رقم تلقائي
      String code = '';
      if (supaReady && activeCountry != null) {
        final c = await ds.consumeNextCode(
            technicalId: 'bus', countryId: activeCountry);
        if (c != null) code = c;
      }
      if (code.isEmpty) {
        code = 'BUS-${DateTime.now().millisecondsSinceEpoch}';
      }
      name = code;
    }

    final bus = Bus(
      id: widget.existing?.id ?? repo.generateId(),
      name: name,
      plateNumber: _plate.text.trim(),
      capacity: int.tryParse(_capacity.text) ?? 30,
      driverId: _driverId,
      status: _status,
      model: _model.text.trim(),
      year: int.tryParse(_year.text),
      color: _color.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      countryId: widget.existing?.countryId ?? activeCountry,
      assignedPointId: _pointId,
      morningTime: _formatTime(_morning),
      eveningTime: _formatTime(_evening),
      scheduleDays: _days.toList()..sort(),
    );

    if (supaReady) {
      if (_isEdit) {
        final ok = await ds.updateBus(bus);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          setState(() => _saving = false);
          return;
        }
      } else {
        final created =
            await ds.createBus(bus, countryId: activeCountry);
        if (created == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          setState(() => _saving = false);
          return;
        }
      }
    } else {
      if (_isEdit) {
        final i = repo.buses.indexWhere((x) => x.id == bus.id);
        if (i != -1) repo.buses[i] = bus;
      } else {
        repo.buses.add(bus);
      }
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: CampPalette.green,
      content: Text(_isEdit
          ? (s.isAr ? 'تم حفظ التعديلات' : 'Saved')
          : (s.isAr ? 'تم إنشاء الباص $name' : 'Bus $name created')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    // السائقون النشطون في نفس الدولة
    final drivers = auth
        .filterByCountry(repo.employees, (e) => e.countryId)
        .where((e) => e.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    // النقاط المتاحة في نفس الدولة
    final dayLabels = dayNames(s.isAr);

    return CampThemeWrapper(
      child: Container(
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
                    color: BusesPalette.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.directions_bus,
                      color: BusesPalette.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                    _isEdit
                        ? (s.isAr ? 'تعديل الباص' : 'Edit Bus')
                        : (s.isAr ? 'باص جديد' : 'New Bus'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isEdit)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BusesPalette.info.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  BusesPalette.info.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: BusesPalette.info, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.isAr
                                    ? 'سيتم توليد رقم الباص تلقائياً (BUS-XX-####)'
                                    : 'Bus number will be auto-generated',
                                style: const TextStyle(
                                    color: BusesPalette.info, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_isEdit) const SizedBox(height: 12),
                    _Section(title: s.isAr ? 'البيانات الأساسية' : 'Basics'),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _plate,
                            decoration: InputDecoration(
                              labelText:
                                  s.isAr ? 'رقم اللوحة *' : 'Plate No. *',
                              prefixIcon:
                                  const Icon(Icons.confirmation_number),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _capacity,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  s.isAr ? 'السعة' : 'Capacity',
                              prefixIcon: const Icon(Icons.event_seat),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _model,
                            decoration: InputDecoration(
                              labelText: s.isAr ? 'الموديل' : 'Model',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _year,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: s.isAr ? 'السنة' : 'Year',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _color,
                            decoration: InputDecoration(
                              labelText: s.isAr ? 'اللون' : 'Color',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _driverId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: s.isAr ? 'السائق' : 'Driver',
                        prefixIcon:
                            const Icon(Icons.person_outline, size: 18),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<String>(
                            value: null,
                            child:
                                Text(s.isAr ? 'بلا سائق' : 'No driver')),
                        for (final d in drivers)
                          DropdownMenuItem<String>(
                            value: d.id,
                            child: Text('${d.fullName} · ${d.code}',
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _driverId = v),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                        title: s.isAr ? 'الجدول الزمني' : 'Schedule'),
                    Row(
                      children: [
                        Expanded(
                          child: _TimePickButton(
                            label: s.isAr ? 'الذهاب' : 'Morning',
                            icon: Icons.wb_sunny_outlined,
                            time: _morning,
                            onTap: () => _pickTime(isMorning: true),
                            onClear: () =>
                                setState(() => _morning = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TimePickButton(
                            label: s.isAr ? 'العودة' : 'Evening',
                            icon: Icons.nights_stay_outlined,
                            time: _evening,
                            onTap: () => _pickTime(isMorning: false),
                            onClear: () =>
                                setState(() => _evening = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(s.isAr ? 'أيام العمل' : 'Working Days',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < 7; i++)
                          _DayChip(
                            label: dayLabels[i],
                            selected: _days.contains(i),
                            onTap: () => setState(() {
                              if (_days.contains(i)) {
                                _days.remove(i);
                              } else {
                                _days.add(i);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                        title: s.isAr ? 'الحالة وملاحظات' : 'Status & Notes'),
                    Row(
                      children: [
                        Expanded(
                          child: _StatusToggle(
                            isActive: _status == EntityStatus.active,
                            onChanged: (v) => setState(() => _status =
                                v ? EntityStatus.active : EntityStatus.inactive),
                          ),
                        ),
                      ],
                    ),
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
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                color: CampPalette.card,
                border: Border(
                    top: BorderSide(color: CampPalette.borderLight)),
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
                        backgroundColor: BusesPalette.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(s.save),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: BusesPalette.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: CampPalette.text)),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? BusesPalette.primary
              : CampPalette.input,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? BusesPalette.primary
                  : CampPalette.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : CampPalette.text,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _TimePickButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final TimeOfDay? time;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _TimePickButton({
    required this.label,
    required this.icon,
    required this.time,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasTime = time != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasTime
              ? BusesPalette.primary.withOpacity(0.08)
              : CampPalette.input,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasTime
                  ? BusesPalette.primary.withOpacity(0.30)
                  : CampPalette.border),
        ),
        child: Row(
          children: [
            Icon(icon,
                color:
                    hasTime ? BusesPalette.primary : CampPalette.textSecondary,
                size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: hasTime
                              ? BusesPalette.primary
                              : CampPalette.textSecondary,
                          fontWeight: FontWeight.w700)),
                  Text(
                    hasTime
                        ? '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'
                        : '—',
                    style: TextStyle(
                        fontSize: 14,
                        color: hasTime
                            ? CampPalette.text
                            : CampPalette.textTertiary,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            if (hasTime)
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusToggle extends StatelessWidget {
  final bool isActive;
  final ValueChanged<bool> onChanged;
  const _StatusToggle({required this.isActive, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: CampPalette.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onChanged(true),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? CampPalette.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  s.isAr ? 'نشط' : 'Active',
                  style: TextStyle(
                      color: isActive ? Colors.white : CampPalette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(false),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !isActive ? CampPalette.red : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  s.isAr ? 'غير نشط' : 'Inactive',
                  style: TextStyle(
                      color: !isActive ? Colors.white : CampPalette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
