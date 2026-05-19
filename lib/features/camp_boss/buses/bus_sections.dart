import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_dirty_tracker.dart';
import '../../../shared/m7_section_scaffold.dart';

// ============================================================================
// 🚌 شَاشات تَعديل أَقسام مَلَفّ الباص (مُنفَصِلة)
// ============================================================================

InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime? current) =>
    showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );

Widget _dateField({
  required String label,
  required DateTime? value,
  required VoidCallback onTap,
  IconData icon = Icons.event,
}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _dec(label, icon: icon),
        child: Text(
          value == null
              ? '—'
              : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );

Future<bool> _persist(BuildContext context, Bus b,
    {String section = 'bus'}) async {
  final supaReady = SupabaseService().isReady;
  if (supaReady) {
    final ok = await SupabaseDataService().updateBus(b);
    if (!ok) return false;
  } else {
    MockRepository().notifyListeners();
  }
  // 🆕 سَجِّل في سِجِلّ التَدقيق
  if (context.mounted) {
    final auth = context.read<AuthProvider>();
    AuditLogService.instance.log(
      action: AuditAction.update,
      entityType: 'bus',
      entityId: b.id,
      entityName: b.shownLabel,
      actorId: auth.account?.id,
      actorName: auth.account?.fullName,
      summary: 'Updated $section',
      countryId: b.countryId,
    );
  }
  return true;
}

void _onSaveResult(BuildContext context, bool ok) {
  final s = AppStrings.of(context);
  if (ok) {
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.success)));
  } else {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text(
          SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed')),
    ));
  }
}

// ============================================================
// 1️⃣ البَيانات الأَساسيّة — اسم/لوحة/سَعة/مُوديل/سَنة/لَون
// ============================================================
class BusBasicSection extends StatefulWidget {
  final Bus bus;
  const BusBasicSection({super.key, required this.bus});
  @override
  State<BusBasicSection> createState() => _BusBasicSectionState();
}

class _BusBasicSectionState extends State<BusBasicSection>
    with M7DirtyTrackerMixin<BusBasicSection> {
  late final TextEditingController _name;
  late final TextEditingController _displayName;
  late final TextEditingController _plate;
  late final TextEditingController _capacity;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _color;
  late final TextEditingController _notes;
  EntityStatus _status = EntityStatus.active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bus;
    _name = TextEditingController(text: b.name);
    _displayName = TextEditingController(text: b.displayName ?? '');
    _plate = TextEditingController(text: b.plateNumber);
    _capacity = TextEditingController(text: b.capacity.toString());
    _model = TextEditingController(text: b.model);
    _year = TextEditingController(text: b.year?.toString() ?? '');
    _color = TextEditingController(text: b.color);
    _notes = TextEditingController(text: b.notes ?? '');
    _status = b.status;
    trackAll([_name, _displayName, _plate, _capacity, _model, _year, _color, _notes]);
  }

  @override
  void dispose() {
    for (final c in [_name, _displayName, _plate, _capacity, _model, _year, _color, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final b = widget.bus;
    b.name = _name.text.trim();
    b.displayName =
        _displayName.text.trim().isEmpty ? null : _displayName.text.trim();
    b.plateNumber = _plate.text.trim();
    b.capacity = int.tryParse(_capacity.text) ?? b.capacity;
    b.model = _model.text.trim();
    b.year = int.tryParse(_year.text);
    b.color = _color.text.trim();
    b.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    b.status = _status;
    final ok = await _persist(context, b);
    if (!mounted) return;
    setState(() => _saving = false);
    _onSaveResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'البَيانات الأَساسيّة',
      titleEn: 'Basic Info',
      icon: Icons.directions_bus,
      color: AppColors.brand,
      editPermission: P.busesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
            controller: _name,
            decoration:
                _dec(isAr ? 'الاسم *' : 'Name *', icon: Icons.label_outline)),
        const SizedBox(height: 12),
        TextField(
            controller: _displayName,
            decoration: _dec(isAr ? 'الاسم المُختَصَر' : 'Display name',
                icon: Icons.label)),
        const SizedBox(height: 12),
        TextField(
            controller: _plate,
            decoration: _dec(isAr ? 'رَقم اللَوحة *' : 'Plate number *',
                icon: Icons.confirmation_number)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: _dec(isAr ? 'السَعة' : 'Capacity',
                      icon: Icons.people)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: _dec(isAr ? 'سَنة الصُنع' : 'Year',
                      icon: Icons.calendar_today)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                  controller: _model,
                  decoration: _dec(isAr ? 'المُوديل' : 'Model',
                      icon: Icons.directions_car)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                  controller: _color,
                  decoration: _dec(isAr ? 'اللَون' : 'Color',
                      icon: Icons.palette_outlined)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _notes,
            maxLines: 2,
            decoration:
                _dec(isAr ? 'مُلاحَظات' : 'Notes', icon: Icons.notes)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(isAr ? 'الحالة' : 'Status',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              RadioListTile<EntityStatus>(
                dense: true,
                title: Text(isAr ? '✅ نَشِط' : '✅ Active'),
                value: EntityStatus.active,
                groupValue: _status,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _status = v);
                },
              ),
              RadioListTile<EntityStatus>(
                dense: true,
                title: Text(isAr ? '⛔ مُعَطَّل' : '⛔ Inactive'),
                value: EntityStatus.inactive,
                groupValue: _status,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _status = v);
                },
              ),
              RadioListTile<EntityStatus>(
                dense: true,
                title: Text(isAr ? '🛠️ صِيانة' : '🛠️ Maintenance'),
                value: EntityStatus.maintenance,
                groupValue: _status,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _status = v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 2️⃣ السائِق
// ============================================================
class BusDriverSection extends StatefulWidget {
  final Bus bus;
  const BusDriverSection({super.key, required this.bus});
  @override
  State<BusDriverSection> createState() => _BusDriverSectionState();
}

class _BusDriverSectionState extends State<BusDriverSection>
    with M7DirtyTrackerMixin<BusDriverSection> {
  String? _driverId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _driverId = widget.bus.driverId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.bus.driverId = _driverId;
    final ok = await _persist(context, widget.bus);
    if (!mounted) return;
    setState(() => _saving = false);
    _onSaveResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    // الفِلتَر: فَقَط الذين مُسَمّاهم سائِق
    final drivers = repo.employees
        .where((e) =>
            e.status == EntityStatus.active &&
            (e.jobTitle.toLowerCase().contains('driver') ||
                e.jobTitle.contains('سائِق') ||
                e.jobTitle.contains('سائق')))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return M7SectionScaffold(
      titleAr: 'السائِق',
      titleEn: 'Driver',
      icon: Icons.person_pin_circle,
      color: AppColors.success,
      editPermission: P.busesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        DropdownButtonFormField<String?>(
          value: _driverId,
          decoration: _dec(isAr ? 'السائِق المُعَيَّن' : 'Assigned driver',
              icon: Icons.person),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...drivers.map((d) => DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text('${d.fullName} · ${d.code}'),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _driverId = v);
          },
        ),
        const SizedBox(height: 12),
        if (drivers.isEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.warning.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? 'لا يُوجَد مُوظَّفون بِمُسَمّى «سائِق» في النِظام.'
                        : 'No employees with «driver» job title.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================
// 3️⃣ الجَدوَلة — أَوقات الرَحلات + أَيّام العَمَل
// ============================================================
class BusScheduleSection extends StatefulWidget {
  final Bus bus;
  const BusScheduleSection({super.key, required this.bus});
  @override
  State<BusScheduleSection> createState() => _BusScheduleSectionState();
}

class _BusScheduleSectionState extends State<BusScheduleSection>
    with M7DirtyTrackerMixin<BusScheduleSection> {
  late final TextEditingController _morning;
  late final TextEditingController _evening;
  late Set<int> _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _morning = TextEditingController(text: widget.bus.morningTime ?? '');
    _evening = TextEditingController(text: widget.bus.eveningTime ?? '');
    _days = {...widget.bus.scheduleDays};
    trackAll([_morning, _evening]);
  }

  @override
  void dispose() {
    _morning.dispose();
    _evening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final b = widget.bus;
    b.morningTime =
        _morning.text.trim().isEmpty ? null : _morning.text.trim();
    b.eveningTime =
        _evening.text.trim().isEmpty ? null : _evening.text.trim();
    b.scheduleDays = _days.toList()..sort();
    final ok = await _persist(context, b);
    if (!mounted) return;
    setState(() => _saving = false);
    _onSaveResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const dayLabelsAr = ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];
    return M7SectionScaffold(
      titleAr: 'الجَدوَلة',
      titleEn: 'Schedule',
      icon: Icons.schedule,
      color: AppColors.info,
      editPermission: P.busesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _morning,
                decoration: _dec(isAr ? 'وَقت الصَباح (HH:mm)' : 'Morning (HH:mm)',
                    icon: Icons.wb_sunny_outlined),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _evening,
                decoration: _dec(isAr ? 'وَقت المَساء (HH:mm)' : 'Evening (HH:mm)',
                    icon: Icons.nightlight_round),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(isAr ? 'أَيّام العَمَل' : 'Working Days',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(7, (i) {
            final selected = _days.contains(i);
            return InkWell(
              onTap: () {
                markDirty();
                setState(() {
                  if (selected) {
                    _days.remove(i);
                  } else {
                    _days.add(i);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brand
                      : AppColors.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.brand.withOpacity(0.40)),
                ),
                child: Text(
                  isAr ? dayLabelsAr[i] : dayLabels[i],
                  style: TextStyle(
                      color: selected ? Colors.white : AppColors.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 11),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ============================================================
// 4️⃣ التَأمين / الرُخصة
// ============================================================
class BusInsuranceSection extends StatefulWidget {
  final Bus bus;
  const BusInsuranceSection({super.key, required this.bus});
  @override
  State<BusInsuranceSection> createState() => _BusInsuranceSectionState();
}

class _BusInsuranceSectionState extends State<BusInsuranceSection>
    with M7DirtyTrackerMixin<BusInsuranceSection> {
  DateTime? _licenseExpiry;
  DateTime? _insuranceExpiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _licenseExpiry = widget.bus.licenseExpiry;
    _insuranceExpiry = widget.bus.insuranceExpiry;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final b = widget.bus;
    b.licenseExpiry = _licenseExpiry;
    b.insuranceExpiry = _insuranceExpiry;
    final ok = await _persist(context, b);
    if (!mounted) return;
    setState(() => _saving = false);
    _onSaveResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'التَأمين وَالرُخصة',
      titleEn: 'License & Insurance',
      icon: Icons.policy_outlined,
      color: AppColors.warning,
      editPermission: P.busesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        _dateField(
          label: isAr ? 'انتِهاء الرُخصة' : 'License expiry',
          value: _licenseExpiry,
          icon: Icons.event_busy,
          onTap: () async {
            final d = await _pickDate(context, _licenseExpiry);
            if (d != null) {
              markDirty();
              setState(() => _licenseExpiry = d);
            }
          },
        ),
        if (_licenseExpiry != null) ...[
          const SizedBox(height: 8),
          _ExpiryHint(date: _licenseExpiry!),
        ],
        const SizedBox(height: 14),
        _dateField(
          label: isAr ? 'انتِهاء التَأمين' : 'Insurance expiry',
          value: _insuranceExpiry,
          icon: Icons.event_busy,
          onTap: () async {
            final d = await _pickDate(context, _insuranceExpiry);
            if (d != null) {
              markDirty();
              setState(() => _insuranceExpiry = d);
            }
          },
        ),
        if (_insuranceExpiry != null) ...[
          const SizedBox(height: 8),
          _ExpiryHint(date: _insuranceExpiry!),
        ],
      ],
    );
  }
}

class _ExpiryHint extends StatelessWidget {
  final DateTime date;
  const _ExpiryHint({required this.date});
  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final days = date.difference(DateTime.now()).inDays;
    final (Color c, IconData ic, String txt) = days < 0
        ? (Colors.red, Icons.error_outline,
            isAr ? 'مُنتَهيَة (${-days} يوم)' : 'Expired (${-days}d ago)')
        : days <= 30
            ? (Colors.orange, Icons.warning_amber_rounded,
                isAr ? 'تَنتَهي خِلال $days يوم' : 'Expires in $days day(s)')
            : days <= 90
                ? (Colors.amber.shade700, Icons.info_outline,
                    isAr ? 'تَنتَهي خِلال $days يوم' : 'Expires in $days days')
                : (Colors.green, Icons.check_circle_outline,
                    isAr ? 'سارِية ($days يوم)' : 'Valid ($days days left)');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(ic, size: 16, color: c),
          const SizedBox(width: 6),
          Text(txt,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}
