// =============================================================================
// 📅 Custom Events Tab — أَحداث الشَركة المُخَصَّصة (يُنشِئها المُدير)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/events_tasks_service.dart';
import '../../core/theme/app_colors.dart';
import 'event_people_picker.dart';

class CustomEventsTab extends StatefulWidget {
  const CustomEventsTab({super.key});

  @override
  State<CustomEventsTab> createState() => _CustomEventsTabState();
}

class _CustomEventsTabState extends State<CustomEventsTab> {
  bool _loading = true;
  List<CustomEvent> _events = [];
  int _daysAhead = 90;
  CustomEventType? _typeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final now = DateTime.now();
    _events = await EventsTasksService.instance.listEvents(
      from: DateTime(now.year, now.month, now.day),
      to: now.add(Duration(days: _daysAhead)),
      countryId: auth.activeCountryId,
    );
    if (mounted) setState(() => _loading = false);
  }

  List<CustomEvent> get _filtered {
    if (_typeFilter == null) return _events;
    return _events.where((e) => e.type == _typeFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _filterBar(isAr),
                  Expanded(
                    child: _filtered.isEmpty
                        ? _empty(isAr)
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) =>
                                _eventCard(_filtered[i], isAr),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(isAr ? 'حَدَث جَديد' : 'New Event'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _filterBar(bool isAr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        children: [
          // نِطاق الأَيّام
          Row(
            children: [
              Text(isAr ? 'النِطاق:' : 'Range:',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [30, 90, 180, 365].map((d) {
                      final selected = _daysAhead == d;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          label: Text(
                            isAr ? '$d يَوم' : '${d}d',
                            style: const TextStyle(fontSize: 10),
                          ),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _daysAhead = d);
                            _load();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // فِلتَر النَوع
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _typeChip(null, isAr ? 'الكُلّ' : 'All'),
                ...CustomEventType.values.map((t) =>
                    _typeChip(t, isAr ? t.labelAr() : t.labelEn())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(CustomEventType? t, String label) {
    final selected = _typeFilter == t;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        selected: selected,
        onSelected: (_) => setState(() => _typeFilter = t),
      ),
    );
  }

  Widget _empty(bool isAr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            isAr ? 'لا تُوجَد أَحداث مُخَصَّصة' : 'No custom events',
            style: TextStyle(
                color: Colors.grey.shade600, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'اِضغَط "حَدَث جَديد" لإضافة اِجتِماع أَو تَدريب أَو تَذكير'
                : 'Tap "New Event" to add a meeting, training or reminder',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _eventCard(CustomEvent e, bool isAr) {
    final color = _parseColor(e.color);
    final daysUntil =
        e.startDate.difference(DateTime.now()).inDays;
    final urgency = daysUntil < 0
        ? '⌛ ${isAr ? "مَضى" : "Past"}'
        : daysUntil <= 1
            ? '🔴 ${isAr ? "قَريب جِدّاً" : "Very soon"}'
            : daysUntil <= 7
                ? '🟠 ${isAr ? "$daysUntil أَيّام" : "$daysUntil days"}'
                : '🔵 ${isAr ? "$daysUntil يَوم" : "$daysUntil days"}';
    final time = (e.startTime != null && e.endTime != null)
        ? ' · ${e.startTime} → ${e.endTime}'
        : (e.startTime != null)
            ? ' · ${e.startTime}'
            : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openEditor(existing: e),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.title,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900)),
                        ),
                        Text(
                          isAr ? e.type.labelAr() : e.type.labelEn(),
                          style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${e.startDate.toIso8601String().substring(0, 10)}$time',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
                    ),
                    if (e.location != null && e.location!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.place,
                            size: 11, color: Colors.grey),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(e.location!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600)),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(urgency,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        // 🆕 عَدّاد المُشارِكين (لازو سَيتِم تَحميله asynchronously)
                        _ParticipantBadge(eventId: e.id),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.people_outline,
                    size: 18, color: AppColors.brand),
                tooltip: isAr ? 'إدارة المُشارِكين' : 'Manage participants',
                onPressed: () => _openParticipants(e),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                onPressed: () => _confirmDelete(e, isAr),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openParticipants(CustomEvent e) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ParticipantsSheet(event: e),
    );
    _load();
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.brand;
    }
  }

  Future<void> _confirmDelete(CustomEvent e, bool isAr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'حَذف الحَدَث؟' : 'Delete event?'),
        content: Text(isAr ? '"${e.title}"' : '"${e.title}"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'حَذف' : 'Delete')),
        ],
      ),
    );
    if (ok == true) {
      await EventsTasksService.instance.deleteEvent(e.id);
      _load();
    }
  }

  Future<void> _openEditor({CustomEvent? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EventEditor(existing: existing),
    );
    if (result == true) _load();
  }
}

// ============================================================
// Event Editor Sheet
// ============================================================
class _EventEditor extends StatefulWidget {
  final CustomEvent? existing;
  const _EventEditor({this.existing});

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _location;
  CustomEventType _type = CustomEventType.meeting;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  int _notifyBefore = 1;
  // 🆕 الأَشخاص المُسنَدون (مَسؤول/مُشارِكون/مُتابِعون)
  List<PickedPerson> _people = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    if (e != null) {
      _type = e.type;
      _startDate = e.startDate;
      _endDate = e.endDate;
      if (e.startTime != null) _startTime = _parseTime(e.startTime!);
      if (e.endTime != null) _endTime = _parseTime(e.endTime!);
      _notifyBefore = e.notifyBeforeDays;
    }
  }

  TimeOfDay _parseTime(String t) {
    final p = t.split(':');
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.read<AuthProvider>();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.existing == null
                  ? (isAr ? '➕ حَدَث جَديد' : '➕ New Event')
                  : (isAr ? '✏️ تَعديل حَدَث' : '✏️ Edit Event'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            // النَوع
            DropdownButtonFormField<CustomEventType>(
              value: _type,
              decoration: InputDecoration(
                labelText: isAr ? 'النَوع' : 'Type',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              items: CustomEventType.values
                  .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(isAr ? t.labelAr() : t.labelEn())))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: isAr ? 'العُنوان *' : 'Title *',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: isAr ? 'الوَصف' : 'Description',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: InputDecoration(
                labelText: isAr ? 'المَكان' : 'Location',
                prefixIcon: const Icon(Icons.place_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            // التَواريخ
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                      '${isAr ? "البَدء" : "Start"}: ${_startDate.toIso8601String().substring(0, 10)}',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 30)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) {
                      setState(() => _startDate = picked);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                      _endDate == null
                          ? (isAr ? 'النِهاية ←' : 'End ←')
                          : '${isAr ? "النِهاية" : "End"}: ${_endDate!.toIso8601String().substring(0, 10)}',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? _startDate,
                      firstDate: _startDate,
                      lastDate:
                          DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(
                      _startTime == null
                          ? (isAr ? 'بَدء الوَقت' : 'Start time')
                          : _fmtTime(_startTime!),
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: _startTime ??
                            const TimeOfDay(hour: 9, minute: 0));
                    if (t != null) setState(() => _startTime = t);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(
                      _endTime == null
                          ? (isAr ? 'نِهاية الوَقت' : 'End time')
                          : _fmtTime(_endTime!),
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: _endTime ??
                            const TimeOfDay(hour: 17, minute: 0));
                    if (t != null) setState(() => _endTime = t);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // 🆕 People Picker — مَسؤول / مُشارِكون / مُتابِعون
            EventPeoplePicker(
              initial: _people,
              eventDate: _startDate,
              onChanged: (list) => _people = list,
            ),
            const SizedBox(height: 14),
            // إشعار قَبل
            Row(children: [
              Expanded(
                child: Text(
                  isAr ? 'تَنبيه قَبل (يَوم):' : 'Notify before (days):',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              DropdownButton<int>(
                value: _notifyBefore,
                items: [0, 1, 2, 3, 7, 14, 30]
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d == 0 ? (isAr ? 'بِدون' : 'None') : '$d'),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _notifyBefore = v ?? _notifyBefore),
              ),
            ]),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(isAr ? 'حِفظ' : 'Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                if (_title.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.danger,
                    content: Text(isAr ? 'العُنوان مَطلوب' : 'Title required'),
                  ));
                  return;
                }
                final svc = EventsTasksService.instance;
                final ev = CustomEvent(
                  id: widget.existing?.id ?? '',
                  type: _type,
                  title: _title.text.trim(),
                  description: _desc.text.trim().isEmpty
                      ? null
                      : _desc.text.trim(),
                  location: _location.text.trim().isEmpty
                      ? null
                      : _location.text.trim(),
                  startDate: _startDate,
                  endDate: _endDate,
                  startTime:
                      _startTime == null ? null : _fmtTime(_startTime!),
                  endTime: _endTime == null ? null : _fmtTime(_endTime!),
                  countryId: auth.activeCountryId,
                  notifyBeforeDays: _notifyBefore,
                );
                bool ok = false;
                String? createdId;
                if (widget.existing == null) {
                  final created = await svc.createEvent(ev);
                  if (created != null) {
                    ok = true;
                    createdId = created.id;
                  }
                } else {
                  ok = await svc.updateEvent(
                      widget.existing!.id, ev.toCreatePayload());
                  createdId = widget.existing!.id;
                }

                // 🆕 أَضِف المُشارِكين (سيُولِّد الـ trigger إشعارات + مَهامّ تِلقائيّاً)
                if (ok && createdId != null && _people.isNotEmpty) {
                  final addedBy = auth.currentUser?.id;
                  final list = _people
                      .map((p) => (
                            accountId: p.accountId,
                            employeeId: p.employeeId,
                            role: p.role,
                          ))
                      .toList();
                  final count = await svc.addEventParticipants(
                    eventId: createdId,
                    participants: list,
                    addedBy: addedBy,
                  );
                  if (count > 0 && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: AppColors.brand,
                      duration: const Duration(seconds: 2),
                      content: Text(isAr
                          ? '📲 أُرسِلَت إشعارات لِـ $count شَخص'
                          : '📲 Notified $count people'),
                    ));
                  }
                }

                if (!mounted) return;
                if (ok) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.success,
                    content: Text(isAr ? '✅ تَمّ الحِفظ' : '✅ Saved'),
                  ));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.danger,
                    content: Text(svc.lastError ?? 'Failed'),
                  ));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 Participants Count Badge — يَجلِب العَدَد من DB
// ============================================================
class _ParticipantBadge extends StatefulWidget {
  final String eventId;
  const _ParticipantBadge({required this.eventId});

  @override
  State<_ParticipantBadge> createState() => _ParticipantBadgeState();
}

class _ParticipantBadgeState extends State<_ParticipantBadge> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await EventsTasksService.instance
        .listEventParticipants(widget.eventId);
    if (mounted) setState(() => _count = list.length);
  }

  @override
  Widget build(BuildContext context) {
    if (_count == null || _count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people, size: 11, color: AppColors.brand),
          const SizedBox(width: 3),
          Text('$_count',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brand)),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 Participants Sheet — قائِمة مُنَظَّمة بِالأَدوار + RSVP
// ============================================================
class _ParticipantsSheet extends StatefulWidget {
  final CustomEvent event;
  const _ParticipantsSheet({required this.event});

  @override
  State<_ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends State<_ParticipantsSheet> {
  bool _loading = true;
  List<EventParticipant> _participants = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _participants = await EventsTasksService.instance
        .listEventParticipants(widget.event.id);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final responsible = _participants
        .where((p) => p.role == ParticipantRole.responsible)
        .toList();
    final participants = _participants
        .where((p) => p.role == ParticipantRole.participant)
        .toList();
    final watchers = _participants
        .where((p) => p.role == ParticipantRole.watcher)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.event.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(12),
                children: [
                  _section(
                    isAr ? '🎯 المَسؤول' : '🎯 Responsible',
                    AppColors.danger,
                    responsible,
                    isAr,
                  ),
                  const SizedBox(height: 10),
                  _section(
                    isAr ? '👥 المُشارِكون' : '👥 Participants',
                    AppColors.brand,
                    participants,
                    isAr,
                  ),
                  const SizedBox(height: 10),
                  _section(
                    isAr ? '👁 المُتابِعون' : '👁 Watchers',
                    Colors.blueGrey,
                    watchers,
                    isAr,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(
      String title, Color color, List<EventParticipant> people, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title (${people.length})',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          if (people.isEmpty)
            Text(isAr ? '— لا أَحَد' : '— none',
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 11))
          else
            ...people.map((p) => _personRow(p, color, isAr)),
        ],
      ),
    );
  }

  Widget _personRow(EventParticipant p, Color color, bool isAr) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
                (p.displayName ?? '?').isNotEmpty
                    ? p.displayName![0]
                    : '?',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName ?? '?',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                if (p.displayCode != null)
                  Text(p.displayCode!,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade700)),
                if (p.rsvpNote != null && p.rsvpNote!.isNotEmpty)
                  Text('💬 ${p.rsvpNote}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          // RSVP badge
          _rsvpBadge(p.rsvpStatus),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
            onPressed: () async {
              await EventsTasksService.instance.removeParticipant(p.id);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _rsvpBadge(RsvpStatus s) {
    Color c;
    switch (s) {
      case RsvpStatus.confirmed:
      case RsvpStatus.attended:
        c = AppColors.success;
        break;
      case RsvpStatus.declined:
      case RsvpStatus.noShow:
        c = AppColors.danger;
        break;
      default:
        c = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(s.labelAr(),
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: c)),
    );
  }
}
