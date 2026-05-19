import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../models/rbac.dart';
import '../../shared/country_guard.dart';
import '../../shared/deletion_guard.dart';
import 'camp_palette.dart';
import 'camp_widgets.dart';

/// Camp Boss Rooms - شبكة بطاقات الغرف
class CampBossRooms extends StatefulWidget {
  const CampBossRooms({super.key});

  @override
  State<CampBossRooms> createState() => _CampBossRoomsState();
}

class _CampBossRoomsState extends State<CampBossRooms> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    // فلترة بالدولة المختارة
    final rooms = auth.filterByCountry(repo.rooms, (r) => r.countryId);
    return CampThemeWrapper(
      child: Scaffold(
        backgroundColor: CampPalette.bg,
        body: rooms.isEmpty
            ? Center(
                child: Text(s.noData,
                    style: const TextStyle(
                        color: CampPalette.textSecondary)),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.85,
                ),
                itemCount: rooms.length,
                itemBuilder: (_, i) => _RoomCard(
                  room: rooms[i],
                  onRate: () => _openRate(rooms[i]),
                  onEdit: () => _openEdit(rooms[i]),
                  onManage: () => _openManage(rooms[i]),
                ),
              ),
        floatingActionButton: !auth.hasPermission(P.campRoomsCreate)
            ? null
            : FloatingActionButton(
                backgroundColor: CampPalette.accent,
                onPressed: _openCreate,
                child: const Icon(Icons.add, color: Colors.white),
              ),
      ),
    );
  }

  /// فتح نافذة تقييم غرفة موجودة (نضغط على بطاقتها)
  void _openRate(Room? room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RateRoomSheet(initialRoom: room),
    );
  }

  /// فتح نافذة إنشاء غرفة جديدة (الزر +)
  void _openCreate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateRoomSheet(),
    );
  }

  /// فتح نافذة تعديل بيانات الغرفة
  void _openEdit(Room room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRoomSheet(room: room),
    );
  }

  /// 🆕 فَتح Sheet إدارة سُكان الغُرفة (إضافة/إزالة مُوَظَّفين)
  void _openManage(Room room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoomOccupantsSheet(room: room),
    );
  }
}

// =============================================================================
// 👥 Sheet إدارة سُكان الغُرفة — عَرض + إضافة + إزالة مُوَظَّفين
// =============================================================================
class _RoomOccupantsSheet extends StatefulWidget {
  final Room room;
  const _RoomOccupantsSheet({required this.room});

  @override
  State<_RoomOccupantsSheet> createState() => _RoomOccupantsSheetState();
}

class _RoomOccupantsSheetState extends State<_RoomOccupantsSheet> {
  bool _busy = false;

  Future<void> _addEmployee() async {
    final picked = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickRoomEmployeeSheet(room: widget.room),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    final ds = SupabaseDataService();
    final ok = await ds.assignEmployeeToRoom(widget.room.id, picked.id);
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? CampPalette.green : Colors.red,
      content: Text(ok
          ? (s.isAr
              ? '✓ تَمّ إضافة ${picked.fullName} لِلغُرفة'
              : '✓ Added ${picked.fullName} to the room')
          : (ds.lastError ?? (s.isAr ? 'فَشَل الإضافة' : 'Failed to add'))),
    ));
  }

  Future<void> _removeEmployee(Employee emp) async {
    final s = AppStrings.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? 'إزالة مِن الغُرفة؟' : 'Remove from room?'),
        content: Text(s.isAr
            ? 'سَيَتِمّ إزالة ${emp.fullName} مِن غُرفة ${widget.room.name}.'
            : '${emp.fullName} will be removed from room ${widget.room.name}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: CampPalette.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'إزالة' : 'Remove',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final ok = await SupabaseDataService()
        .unassignEmployeeFromRoom(widget.room.id, emp.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? CampPalette.green : Colors.red,
      content: Text(ok
          ? (s.isAr ? '✓ تَمّت الإزالة' : '✓ Removed')
          : (s.isAr ? 'فَشَل الإزالة' : 'Failed to remove')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final occupants = widget.room.employeeIds
        .map((id) => repo.employeeById(id))
        .whereType<Employee>()
        .toList();
    final canAddMore =
        widget.room.used < widget.room.capacity && !_busy;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CampPalette.accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.bed, color: CampPalette.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.room.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                      Text(
                        '${widget.room.used}/${widget.room.capacity} ${s.isAr ? "مَقاعِد مَشغولة" : "occupied"}',
                        style: const TextStyle(
                            fontSize: 11, color: CampPalette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            // قائِمة السُكان
            if (occupants.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    s.isAr
                        ? 'لا يُوجَد سُكان في هذه الغُرفة'
                        : 'No occupants in this room',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: occupants.length,
                  itemBuilder: (_, i) => _occupantTile(occupants[i], s),
                ),
              ),
            const SizedBox(height: 12),
            // زِرّ إضافة مُوَظَّف
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      canAddMore ? CampPalette.accent : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.person_add),
                label: Text(
                  canAddMore
                      ? (s.isAr
                          ? '➕ إضافة مُوَظَّف لِلغُرفة'
                          : '➕ Add Employee to Room')
                      : (s.isAr ? 'الغُرفة مُمتَلِئة' : 'Room is full'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
                onPressed: canAddMore ? _addEmployee : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _occupantTile(Employee e, AppStrings s) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CampPalette.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: CampPalette.accent.withOpacity(0.20),
            child: Text(e.initials,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: CampPalette.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.fullName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${e.code}${e.jobTitle.isEmpty ? "" : " · ${e.jobTitle}"}',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: CampPalette.red, size: 18),
            tooltip: s.isAr ? 'إزالة' : 'Remove',
            onPressed: _busy ? null : () => _removeEmployee(e),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 🔍 Sheet اختِيار مُوَظَّف لِإضافَته لِلغُرفة
// =============================================================================
class _PickRoomEmployeeSheet extends StatefulWidget {
  final Room room;
  const _PickRoomEmployeeSheet({required this.room});

  @override
  State<_PickRoomEmployeeSheet> createState() =>
      _PickRoomEmployeeSheetState();
}

class _PickRoomEmployeeSheetState extends State<_PickRoomEmployeeSheet> {
  String _query = '';

  List<Employee> get _availableEmployees {
    final repo = MockRepository();
    // كُلّ المُوَظَّفين السَكَن في الكامِب + بِنَفس البَلَد + غَير مُعَيَّنين
    // في أَيّ غُرفة + نَشِطين
    final assignedIds = <String>{};
    for (final r in repo.rooms) {
      assignedIds.addAll(r.employeeIds);
    }
    var emps = repo.employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      if (e.housingType != HousingType.onCamp) return false;
      if (e.countryId != widget.room.countryId) return false;
      if (assignedIds.contains(e.id)) return false;
      return true;
    }).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      emps = emps
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q) ||
              e.mobile.toLowerCase().contains(q))
          .toList();
    }
    emps.sort((a, b) => a.fullName.compareTo(b.fullName));
    return emps.take(100).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final emps = _availableEmployees;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.isAr
                  ? 'اختَر مُوَظَّفاً لِغُرفة ${widget.room.name}'
                  : 'Pick employee for room ${widget.room.name}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              s.isAr
                  ? 'فَقَط المُوَظَّفون السَاكِنون في الكامِب وَغَير مُعَيَّنين في غُرفة'
                  : 'Only on-camp employees not assigned to a room',
              style:
                  const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: s.isAr
                    ? 'ابحَث بِالاسم / الكود / الجَوّال...'
                    : 'Search by name / code / mobile...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: emps.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          s.isAr
                              ? 'لا يُوجَد مُوَظَّف مُتاح\n(تَأَكَّد أَنّ السَكَن=في الكامِب وَبِنَفس البَلَد)'
                              : 'No available employees\n(check housing=onCamp and same country)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: emps.length,
                      itemBuilder: (_, i) {
                        final e = emps[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  CampPalette.accent.withOpacity(0.15),
                              child: Text(e.initials,
                                  style: const TextStyle(
                                      color: CampPalette.accent,
                                      fontWeight: FontWeight.w900)),
                            ),
                            title: Text(e.fullName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                '${e.code}${e.jobTitle.isEmpty ? "" : " · ${e.jobTitle}"}',
                                style: const TextStyle(fontSize: 11)),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 14),
                            onTap: () => Navigator.pop(context, e),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onRate;
  final VoidCallback onEdit;
  final VoidCallback onManage;
  const _RoomCard({
    required this.room,
    required this.onRate,
    required this.onEdit,
    required this.onManage,
  });

  Color _occupancyColor() {
    if (room.occupancy >= 0.8) return CampPalette.green;
    if (room.occupancy >= 0.6) return CampPalette.amber;
    return CampPalette.red;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = AppStrings.of(context);
    final occupants = room.employeeIds.length;
    final blockers = <DeletionLink>[
      if (occupants > 0)
        DeletionLink(
          label: s.isAr ? 'موظف ساكن' : 'occupants',
          count: occupants,
          icon: Icons.people,
        ),
    ];
    final ok = await DeletionGuard.requireSafe(
      context,
      entityName: s.isAr ? 'غرفة' : 'room',
      subjectName: room.name,
      blockers: blockers,
    );
    if (!ok || !context.mounted) return;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok2 = await ds.deleteRoom(room.id);
      if (!ok2 && context.mounted) {
        await DeletionGuard.showServerLinkError(context,
            entityName: s.isAr ? 'غرفة' : 'room',
            rawError: ds.lastError);
      }
    } else {
      MockRepository().rooms.removeWhere((r) => r.id == room.id);
      MockRepository().notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _occupancyColor();
    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCard,
      child: InkWell(
        // 🆕 الضغط على البطاقة يفتح تفاصيل الموظفين (وليس التقييم)
        onTap: onManage,
        borderRadius: CampPalette.rCard,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: رقم الغرفة + التقييم
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CampPalette.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bed,
                        color: CampPalette.accent, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(room.name,
                        style: const TextStyle(
                            color: CampPalette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (room.avgRating > 0) ...[
                    const Icon(Icons.star,
                        size: 14, color: CampPalette.amber),
                    const SizedBox(width: 2),
                    Text(room.avgRating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: CampPalette.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ],
                  // قائمة الإجراءات (تجنّب الـ overflow)
                  Builder(builder: (ctx) {
                    final auth = ctx.watch<AuthProvider>();
                    final canRate = auth.hasPermission(P.campRoomsRate);
                    final canEdit = auth.hasPermission(P.campRoomsEdit);
                    final canDelete = auth.hasPermission(P.campRoomsDelete);
                    return PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: CampPalette.textSecondary),
                    tooltip: s.isAr ? 'إجراءات' : 'Actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'manage':
                          onManage();
                          break;
                        case 'rate':
                          onRate();
                          break;
                        case 'edit':
                          onEdit();
                          break;
                        case 'delete':
                          _confirmDelete(context);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'manage',
                        child: Row(
                          children: [
                            const Icon(Icons.people_outline,
                                size: 18, color: CampPalette.green),
                            const SizedBox(width: 8),
                            Text(s.isAr ? 'الموظفون' : 'Occupants'),
                          ],
                        ),
                      ),
                      if (canRate)
                        PopupMenuItem<String>(
                        value: 'rate',
                        child: Row(
                          children: [
                            const Icon(Icons.star_outline,
                                size: 18, color: CampPalette.amber),
                            const SizedBox(width: 8),
                            Text(s.isAr ? 'تقييم' : 'Rate'),
                          ],
                        ),
                      ),
                      if (canEdit)
                        PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit_outlined,
                                size: 18, color: CampPalette.accent),
                            const SizedBox(width: 8),
                            Text(s.edit),
                          ],
                        ),
                      ),
                      if (canDelete)
                        PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline,
                                size: 18, color: CampPalette.red),
                            const SizedBox(width: 8),
                            Text(s.delete,
                                style: const TextStyle(color: CampPalette.red)),
                          ],
                        ),
                      ),
                    ],
                  );
                  }),
                ],
              ),
              const SizedBox(height: 10),
              // عدد المقيمين
              Row(
                children: [
                  Icon(Icons.people,
                      size: 14, color: color),
                  const SizedBox(width: 4),
                  Text('${room.used}/${room.capacity}',
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Text(s.isAr ? 'مقيم' : 'occupants',
                      style: const TextStyle(
                          color: CampPalette.textSecondary,
                          fontSize: 10)),
                ],
              ),
              const SizedBox(height: 6),
              // progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: room.occupancy,
                  minHeight: 6,
                  backgroundColor: CampPalette.input,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 8),
              // 🆕 قائمة الموظفين المرتبطين + وسيلة النقل
              Expanded(
                child: _RoomOccupantsList(room: room),
              ),
              if (room.notes != null && room.notes!.isNotEmpty)
                Text(
                  room.notes!,
                  style: const TextStyle(
                      color: CampPalette.textTertiary,
                      fontSize: 10,
                      fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              if (room.cleanRating > 0 || room.orderRating > 0)
                Row(
                  children: [
                    _MiniRating(
                      label: s.isAr ? 'نظافة' : 'Clean',
                      value: room.cleanRating,
                      color: CampPalette.green,
                    ),
                    const SizedBox(width: 6),
                    _MiniRating(
                      label: s.isAr ? 'ترتيب' : 'Order',
                      value: room.orderRating,
                      color: CampPalette.accent,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 🆕 قائمة موظفي الغرفة (مع رمز وسيلة النقل)
class _RoomOccupantsList extends StatelessWidget {
  final Room room;
  const _RoomOccupantsList({required this.room});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    if (room.employeeIds.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          s.isAr ? 'لا يوجد موظفون' : 'No occupants yet',
          style: const TextStyle(
              color: CampPalette.textTertiary,
              fontSize: 10,
              fontStyle: FontStyle.italic),
        ),
      );
    }
    final employees = room.employeeIds
        .map((id) {
          try {
            return repo.employees.firstWhere((e) => e.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<Employee>()
        .toList();

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: employees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final e = employees[i];
        final isUsedBus = repo.transportModes.any((m) =>
            m.id == e.transportModeId && m.key == 'used_bus');
        final hasMode = e.transportModeId != null;
        final modeColor = !hasMode
            ? CampPalette.textTertiary
            : (isUsedBus ? CampPalette.accent : CampPalette.amberDark);
        final modeBg = !hasMode
            ? CampPalette.input
            : (isUsedBus
                ? CampPalette.accent.withOpacity(0.08)
                : CampPalette.amberBg);
        final modeIcon = !hasMode
            ? Icons.help_outline
            : (isUsedBus ? Icons.directions_bus : Icons.directions_car);
        final modeLabelAr = !hasMode
            ? 'غير محدد'
            : (isUsedBus ? 'باص' : 'سيارة');
        final modeLabelEn = !hasMode
            ? 'N/A'
            : (isUsedBus ? 'Bus' : 'Car');
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: modeBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: modeColor.withOpacity(0.35), width: 0.5),
          ),
          child: Row(
            children: [
              Icon(modeIcon, size: 12, color: modeColor),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: CampPalette.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      e.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: CampPalette.textSecondary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  AppStrings.of(context).isAr ? modeLabelAr : modeLabelEn,
                  style: TextStyle(
                    color: modeColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniRating extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _MiniRating(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label:',
              style: TextStyle(color: color, fontSize: 9)),
          const SizedBox(width: 3),
          Text('$value/5',
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ============================================================
// Rate Room Sheet
// ============================================================
class _RateRoomSheet extends StatefulWidget {
  final Room? initialRoom;
  const _RateRoomSheet({this.initialRoom});

  @override
  State<_RateRoomSheet> createState() => _RateRoomSheetState();
}

class _RateRoomSheetState extends State<_RateRoomSheet> {
  String? _roomId;
  int _clean = 0;
  int _order = 0;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _roomId = widget.initialRoom?.id;
    if (widget.initialRoom != null) {
      _clean = widget.initialRoom!.cleanRating;
      _order = widget.initialRoom!.orderRating;
      _notes.text = widget.initialRoom!.notes ?? '';
    }
  }

  Future<void> _save() async {
    if (_roomId == null) return;
    final repo = MockRepository();
    final room = repo.rooms.firstWhere((r) => r.id == _roomId);
    room.cleanRating = _clean;
    room.orderRating = _order;
    room.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRoom(room);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return CampThemeWrapper(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: CampPalette.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CampPalette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.isAr ? 'تقييم غرفة' : 'Rate Room',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: CampPalette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                value: _roomId,
                dropdownColor: CampPalette.card,
                style: const TextStyle(color: CampPalette.text, fontSize: 14),
                decoration:
                    InputDecoration(labelText: s.isAr ? 'الغرفة' : 'Room'),
                items: repo.rooms
                    .map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(r.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roomId = v),
              ),
              const SizedBox(height: 14),
              _StarRating(
                label: s.isAr ? 'النظافة' : 'Cleanliness',
                value: _clean,
                color: CampPalette.green,
                onRate: (v) => setState(() => _clean = v),
              ),
              const SizedBox(height: 12),
              _StarRating(
                label: s.isAr ? 'الترتيب' : 'Order',
                value: _order,
                color: CampPalette.accent,
                onRate: (v) => setState(() => _order = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                style: const TextStyle(color: CampPalette.text),
                decoration: InputDecoration(labelText: s.notes),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: CampPalette.accent),
                onPressed: _save,
                child: Text(s.save),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CampPalette.text,
                  side: const BorderSide(color: CampPalette.border),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onRate;
  const _StarRating({
    required this.label,
    required this.value,
    required this.color,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CampPalette.input,
        borderRadius: CampPalette.rInput,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final v = i + 1;
              final selected = v <= value;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onRate(v),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          selected ? color.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected
                              ? color
                              : CampPalette.border),
                    ),
                    child: Icon(
                      selected ? Icons.star : Icons.star_border,
                      color: selected ? color : CampPalette.textTertiary,
                      size: 22,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// نافذة إنشاء غرفة جديدة
// ============================================================
class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final _floor = TextEditingController();
  final _capacity = TextEditingController(text: '4');
  final _notes = TextEditingController();
  String? _roomTypeId; // 🆕 من الـ lookup
  bool _saving = false;

  String _selectedRoomTypeName() {
    final repo = MockRepository();
    try {
      final t = repo.roomTypes.firstWhere((r) => r.id == _roomTypeId);
      return t.nameAr;
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _floor.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_roomTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isAr ? 'اختر نوع الغرفة' : 'Select type')),
      );
      return;
    }
    // 🛡️ حارس الدولة
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إنشاء غرفة' : 'creating a room')) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final activeCountry = auth.activeCountryId!;
    setState(() => _saving = true);

    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final dataService = SupabaseDataService();

    // ===== ولّد كود تلقائي للغرفة =====
    String roomCode = '';
    if (supaReady) {
      final code = await dataService.consumeNextCode(
          technicalId: 'room', countryId: activeCountry);
      if (code != null) roomCode = code;
    }
    if (roomCode.isEmpty) {
      // fallback - رقم تسلسلي محلي
      final count = repo.rooms.length + 1;
      roomCode = 'ROOM-$count';
    }

    final room = Room(
      id: repo.generateId(),
      name: roomCode, // الاسم = الكود التلقائي
      floor: _floor.text.trim(),
      capacity: int.tryParse(_capacity.text) ?? 4,
      type: _selectedRoomTypeName(),
      roomTypeId: _roomTypeId,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      countryId: activeCountry,
    );

    if (supaReady) {
      final created = await dataService.createRoom(room,
          countryId: activeCountry);
      if (created == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(dataService.lastError ?? 'Failed'),
        ));
        setState(() => _saving = false);
        return;
      }
    } else {
      repo.rooms.add(room);
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CampPalette.green,
        content: Text(s.isAr ? 'تم إنشاء الغرفة' : 'Room created'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return CampThemeWrapper(
      child: Container(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: CampPalette.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CampPalette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  s.isAr ? 'إنشاء غرفة جديدة' : 'New Room',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 18),
              // 🆕 شعار توضيحي - الكود يُولّد تلقائياً
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CampPalette.amberBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: CampPalette.amber.withOpacity(0.30)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: CampPalette.amberDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.isAr
                            ? 'سيتم توليد كود الغرفة تلقائياً (مثال: ROOM-AE-0001)'
                            : 'Room code will be auto-generated (e.g. ROOM-AE-0001)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 🆕 نوع الغرفة من الـ lookup
              DropdownButtonFormField<String>(
                value: _roomTypeId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.isAr ? 'نوع الغرفة' : 'Room Type',
                  border: const OutlineInputBorder(),
                ),
                items: MockRepository()
                    .roomTypes
                    .where((t) => t.isActive)
                    .map((t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(s.isAr ? t.nameAr : t.nameEn),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roomTypeId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _floor,
                      decoration: InputDecoration(
                        labelText: s.isAr ? 'الطابق' : 'Floor',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.isAr ? 'السعة' : 'Capacity',
                        border: const OutlineInputBorder(),
                      ),
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
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CampPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(s.save),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(s.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// نافذة تعديل بيانات غرفة موجودة
// ============================================================
class _EditRoomSheet extends StatefulWidget {
  final Room room;
  const _EditRoomSheet({required this.room});

  @override
  State<_EditRoomSheet> createState() => _EditRoomSheetState();
}

class _EditRoomSheetState extends State<_EditRoomSheet> {
  late final TextEditingController _name;
  late final TextEditingController _floor;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  String? _roomTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.room.name);
    _floor = TextEditingController(text: widget.room.floor);
    _capacity = TextEditingController(text: widget.room.capacity.toString());
    _notes = TextEditingController(text: widget.room.notes ?? '');
    _roomTypeId = widget.room.roomTypeId;
  }

  String _selectedRoomTypeName() {
    final repo = MockRepository();
    try {
      final t = repo.roomTypes.firstWhere((r) => r.id == _roomTypeId);
      return t.nameAr;
    } catch (_) {
      return widget.room.type;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _floor.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr ? 'أدخل اسم الغرفة' : 'Enter room name')),
      );
      return;
    }
    setState(() => _saving = true);

    // نحدّث الكائن نفسه (نفس المرجع في القائمة)
    final r = widget.room;
    r.name = _name.text.trim();
    r.floor = _floor.text.trim();
    r.capacity = int.tryParse(_capacity.text) ?? r.capacity;
    r.roomTypeId = _roomTypeId;
    r.type = _selectedRoomTypeName();
    final notesTxt = _notes.text.trim();
    r.notes = notesTxt.isEmpty ? null : notesTxt;

    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRoom(r);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          setState(() => _saving = false);
        }
        return;
      }
    } else {
      MockRepository().notifyListeners();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CampPalette.green,
        content: Text(s.isAr ? 'تم حفظ التعديلات' : 'Saved'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return CampThemeWrapper(
      child: Container(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: CampPalette.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CampPalette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  s.isAr ? 'تعديل الغرفة' : 'Edit Room',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: s.isAr ? 'اسم/كود الغرفة' : 'Room code/name',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _roomTypeId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.isAr ? 'نوع الغرفة' : 'Room Type',
                  border: const OutlineInputBorder(),
                ),
                items: MockRepository()
                    .roomTypes
                    .where((t) => t.isActive)
                    .map((t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(s.isAr ? t.nameAr : t.nameEn),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roomTypeId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _floor,
                      decoration: InputDecoration(
                        labelText: s.isAr ? 'الطابق' : 'Floor',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.isAr ? 'السعة' : 'Capacity',
                        border: const OutlineInputBorder(),
                      ),
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
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CampPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(s.save),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(s.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// إدارة موظفي الغرفة (Add / Remove + Transport Mode)
// ============================================================
class _ManageRoomEmployeesSheet extends StatefulWidget {
  final Room room;
  const _ManageRoomEmployeesSheet({required this.room});

  @override
  State<_ManageRoomEmployeesSheet> createState() =>
      _ManageRoomEmployeesSheetState();
}

class _ManageRoomEmployeesSheetState extends State<_ManageRoomEmployeesSheet> {
  bool _busy = false;

  Future<void> _addEmployee() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();

    // المرشحون: موظفون نشطون في نفس دولة الغرفة وليسوا في غرفة أخرى
    final inAnyRoom = <String>{
      for (final r in repo.rooms) ...r.employeeIds,
    };
    final candidates = repo.employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      if (inAnyRoom.contains(e.id)) return false;
      if (widget.room.countryId != null &&
          e.countryId != widget.room.countryId) return false;
      // 🆕 فقط موظفو السكن "في الكمب" يظهرون في غرف الكمب
      if (e.housingType != HousingType.onCamp) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.isAr
            ? 'لا يوجد موظفون متاحون لإضافتهم'
            : 'No available employees to add'),
      ));
      return;
    }

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickEmployeeSheet(candidates: candidates),
    );
    if (result == null) return;
    final empId = result['employeeId'];
    final transportModeId = result['transportModeId'];
    if (empId == null) return;

    if (widget.room.available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: CampPalette.red,
        content: Text(s.isAr ? 'الغرفة ممتلئة' : 'Room is full'),
      ));
      return;
    }

    setState(() => _busy = true);
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();

    // 1) عيّن وسيلة النقل على الموظف
    final emp = repo.employees.firstWhere((e) => e.id == empId);
    emp.transportModeId = transportModeId;
    if (supaReady) {
      await ds.updateEmployee(emp);
    }

    // 2) اربط الموظف بالغرفة
    bool ok = true;
    if (supaReady) {
      ok = await ds.assignEmployeeToRoom(widget.room.id, empId);
    } else {
      if (!widget.room.employeeIds.contains(empId)) {
        widget.room.employeeIds.add(empId);
      }
      repo.notifyListeners();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(ds.lastError ?? 'Failed'),
      ));
    }
  }

  Future<void> _removeEmployee(String empId) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(
            s.isAr ? 'إزالة الموظف من الغرفة؟' : 'Remove employee from room?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CampPalette.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      await SupabaseDataService()
          .unassignEmployeeFromRoom(widget.room.id, empId);
    } else {
      widget.room.employeeIds.remove(empId);
      MockRepository().notifyListeners();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changeTransport(Employee e) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    if (repo.transportModes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            s.isAr ? 'لم تُحمَّل وسائل النقل' : 'Transport modes not loaded'),
      ));
      return;
    }
    final newModeId = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(s.isAr ? 'وسيلة النقل' : 'Transport Mode'),
        children: [
          for (final m in repo.transportModes.where((t) => t.isActive))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m.id),
              child: Row(
                children: [
                  Icon(
                    m.key == 'used_bus'
                        ? Icons.directions_bus
                        : Icons.directions_car,
                    color: m.key == 'used_bus'
                        ? CampPalette.accent
                        : CampPalette.amberDark,
                  ),
                  const SizedBox(width: 10),
                  Text(s.isAr ? m.nameAr : m.nameEn),
                ],
              ),
            ),
        ],
      ),
    );
    if (newModeId == null) return;
    setState(() => _busy = true);
    e.transportModeId = newModeId;
    if (SupabaseService().isReady) {
      await SupabaseDataService().updateEmployee(e);
    } else {
      MockRepository().notifyListeners();
    }
    if (mounted) setState(() => _busy = false);
  }

  String _modeName(String? id, bool isAr) {
    final repo = MockRepository();
    if (id == null) return isAr ? 'غير محدد' : 'Not set';
    try {
      final m = repo.transportModes.firstWhere((t) => t.id == id);
      return isAr ? m.nameAr : m.nameEn;
    } catch (_) {
      return isAr ? 'غير محدد' : 'Not set';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final assigned = widget.room.employeeIds
        .map((id) {
          try {
            return repo.employees.firstWhere((e) => e.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<Employee>()
        .toList();

    return CampThemeWrapper(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.bed, color: CampPalette.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.room.name} · ${widget.room.used}/${widget.room.capacity}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CampPalette.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : _addEmployee,
                    icon: const Icon(Icons.person_add, size: 18),
                    label: Text(s.isAr ? 'إضافة موظف' : 'Add Employee'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: assigned.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          s.isAr
                              ? 'لا يوجد موظفون مرتبطون بهذه الغرفة'
                              : 'No employees assigned to this room',
                          style: const TextStyle(
                              color: CampPalette.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: assigned.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = assigned[i];
                        return _EmployeeRichCard(
                          employee: e,
                          modeName: _modeName(e.transportModeId, s.isAr),
                          busy: _busy,
                          onChangeTransport: () => _changeTransport(e),
                          onRemove: () => _removeEmployee(e.id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// نافذة اختيار موظف + وسيلة نقل
// ============================================================
class _PickEmployeeSheet extends StatefulWidget {
  final List<Employee> candidates;
  const _PickEmployeeSheet({required this.candidates});

  @override
  State<_PickEmployeeSheet> createState() => _PickEmployeeSheetState();
}

class _PickEmployeeSheetState extends State<_PickEmployeeSheet> {
  String? _employeeId;
  String? _transportModeId;
  String _query = '';
  bool _loadingModes = false;

  @override
  void initState() {
    super.initState();
    // إذا كانت قائمة وسائل النقل فارغة - نحاول مزامنتها فوراً
    if (MockRepository().transportModes.isEmpty &&
        SupabaseService().isReady) {
      _loadingModes = true;
      SupabaseDataService().syncTransportModes().then((_) {
        if (!mounted) return;
        setState(() => _loadingModes = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final filtered = widget.candidates.where((e) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();

    return CampThemeWrapper(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                s.isAr ? 'اختر موظف' : 'Select Employee',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: s.isAr ? 'بحث بالاسم/الكود' : 'Search name/code',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(s.noData,
                          style: const TextStyle(
                              color: CampPalette.textSecondary)),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final selected = e.id == _employeeId;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              CampPalette.accent.withOpacity(0.10),
                          leading: CircleAvatar(
                            backgroundColor:
                                CampPalette.accent.withOpacity(0.15),
                            child: Text(e.initials,
                                style: const TextStyle(
                                    color: CampPalette.accent,
                                    fontWeight: FontWeight.w800)),
                          ),
                          title: Text(e.fullName),
                          subtitle: Text(e.code),
                          trailing: selected
                              ? const Icon(Icons.check_circle,
                                  color: CampPalette.green)
                              : null,
                          onTap: () => setState(() => _employeeId = e.id),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dropdown وسيلة النقل
                  if (_loadingModes)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (repo.transportModes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CampPalette.redBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: CampPalette.red.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 18, color: CampPalette.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.isAr
                                  ? 'لم يتم تهيئة وسائل النقل في قاعدة البيانات. شغّل ملف transport_modes_lookup.sql ثم Hot Restart'
                                  : 'Transport modes not initialized. Run transport_modes_lookup.sql then Hot Restart',
                              style: const TextStyle(
                                  fontSize: 11, color: CampPalette.redText),
                            ),
                          ),
                          IconButton(
                            tooltip: s.isAr ? 'إعادة محاولة' : 'Retry',
                            icon: const Icon(Icons.refresh,
                                size: 18, color: CampPalette.red),
                            onPressed: () {
                              if (!SupabaseService().isReady) return;
                              setState(() => _loadingModes = true);
                              SupabaseDataService()
                                  .syncTransportModes()
                                  .then((_) {
                                if (!mounted) return;
                                setState(() => _loadingModes = false);
                              });
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _transportModeId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            s.isAr ? 'وسيلة النقل' : 'Transport Mode',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: repo.transportModes
                          .where((t) => t.isActive)
                          .map((t) => DropdownMenuItem<String>(
                                value: t.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      t.key == 'used_bus'
                                          ? Icons.directions_bus
                                          : Icons.directions_car,
                                      size: 16,
                                      color: t.key == 'used_bus'
                                          ? CampPalette.accent
                                          : CampPalette.amberDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(s.isAr ? t.nameAr : t.nameEn),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _transportModeId = v),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(s.cancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CampPalette.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_employeeId == null ||
                                  _transportModeId == null)
                              ? null
                              : () => Navigator.of(context).pop({
                                    'employeeId': _employeeId,
                                    'transportModeId': _transportModeId,
                                  }),
                          child: Text(s.isAr ? 'تأكيد' : 'Confirm'),
                        ),
                      ),
                    ],
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

// ============================================================
// 🆕 بطاقة موظف غنية بالبيانات (داخل تفاصيل الغرفة)
// ============================================================
class _EmployeeRichCard extends StatelessWidget {
  final Employee employee;
  final String modeName;
  final bool busy;
  final VoidCallback onChangeTransport;
  final VoidCallback onRemove;

  const _EmployeeRichCard({
    required this.employee,
    required this.modeName,
    required this.busy,
    required this.onChangeTransport,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final e = employee;

    final isUsedBus = repo.transportModes.any(
        (m) => m.id == e.transportModeId && m.key == 'used_bus');
    final hasMode = e.transportModeId != null;
    final modeColor = !hasMode
        ? CampPalette.textTertiary
        : (isUsedBus ? CampPalette.accent : CampPalette.amberDark);
    final modeBg = !hasMode
        ? CampPalette.input
        : (isUsedBus
            ? CampPalette.accent.withOpacity(0.10)
            : CampPalette.amberBg);
    final modeIcon = !hasMode
        ? Icons.help_outline
        : (isUsedBus ? Icons.directions_bus : Icons.directions_car);

    // اسم نوع الغرفة و القسم/المسمى من الـ lookups
    String _lookupName(List items, String? id, bool isAr) {
      if (id == null) return '';
      try {
        final m = items.firstWhere((x) => x.id == id);
        return isAr ? m.nameAr : m.nameEn;
      } catch (_) {
        return '';
      }
    }

    final jobTitle = e.jobTitle.isNotEmpty
        ? e.jobTitle
        : _lookupName(repo.jobTitles, e.jobTitleId, s.isAr);
    final department = e.department.isNotEmpty
        ? e.department
        : _lookupName(repo.departments, e.departmentId, s.isAr);
    final nationality = e.nationality.isNotEmpty
        ? e.nationality
        : _lookupName(repo.nationalities, e.nationalityId, s.isAr);

    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rInput,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: CampPalette.rInput,
          border: Border.all(color: CampPalette.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === الصف العلوي: الأفاتار + الاسم/الكود + شارة وسيلة النقل ===
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: CampPalette.accent.withOpacity(0.15),
                  child: Text(e.initials,
                      style: const TextStyle(
                          color: CampPalette.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: CampPalette.text)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined,
                              size: 11, color: CampPalette.textSecondary),
                          const SizedBox(width: 3),
                          Text(e.code,
                              style: const TextStyle(
                                  color: CampPalette.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          if (e.status != EntityStatus.active) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: CampPalette.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                s.isAr ? 'غير نشط' : 'Inactive',
                                style: const TextStyle(
                                    color: CampPalette.red,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // شارة وسيلة النقل
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: modeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: modeColor.withOpacity(0.4), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(modeIcon, size: 12, color: modeColor),
                      const SizedBox(width: 3),
                      Text(modeName,
                          style: TextStyle(
                              color: modeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // === صفوف البيانات ===
            if (jobTitle.isNotEmpty || department.isNotEmpty)
              _DataLine(
                icon: Icons.work_outline,
                items: [jobTitle, department].where((x) => x.isNotEmpty),
              ),
            if (e.mobile.isNotEmpty || e.email.isNotEmpty)
              _DataLine(
                icon: Icons.contact_phone_outlined,
                items: [e.mobile, e.email].where((x) => x.isNotEmpty),
              ),
            if (nationality.isNotEmpty)
              _DataLine(
                icon: Icons.public,
                items: [nationality],
              ),
            const SizedBox(height: 8),
            // === الإجراءات ===
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CampPalette.accent,
                      side: BorderSide(
                          color: CampPalette.accent.withOpacity(0.4)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                    ),
                    onPressed: busy ? null : onChangeTransport,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: Text(
                      s.isAr ? 'وسيلة النقل' : 'Transport',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CampPalette.red,
                      side: BorderSide(
                          color: CampPalette.red.withOpacity(0.4)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                    ),
                    onPressed: busy ? null : onRemove,
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: Text(
                      s.isAr ? 'إزالة' : 'Remove',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DataLine extends StatelessWidget {
  final IconData icon;
  final Iterable<String> items;
  const _DataLine({required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    final list = items.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: CampPalette.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              list.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: CampPalette.text),
            ),
          ),
        ],
      ),
    );
  }
}
