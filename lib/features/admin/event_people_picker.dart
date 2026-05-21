// =============================================================================
// 👥 People Picker — يَختار مَسؤول + مُشارِكين + مُتابِعين بِشَكل مَرِن
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/events_tasks_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// نَموذَج اختِيار شَخص (إمّا حِساب أَو مُوَظَّف)
class PickedPerson {
  final String? accountId;
  final String? employeeId;
  final String name;
  final String? code;
  final ParticipantRole role;

  PickedPerson({
    this.accountId,
    this.employeeId,
    required this.name,
    this.code,
    required this.role,
  });
}

/// عُنصُر يُضاف داخِل editor (لَيس ديالوغ مُستَقِلّ)
class EventPeoplePicker extends StatefulWidget {
  final List<PickedPerson> initial;
  final ValueChanged<List<PickedPerson>> onChanged;
  /// لِفَحص التَعارُض الزَمَنيّ
  final DateTime? eventDate;
  const EventPeoplePicker({
    super.key,
    this.initial = const [],
    required this.onChanged,
    this.eventDate,
  });

  @override
  State<EventPeoplePicker> createState() => _EventPeoplePickerState();
}

class _EventPeoplePickerState extends State<EventPeoplePicker> {
  late List<PickedPerson> _picked;

  @override
  void initState() {
    super.initState();
    _picked = List.of(widget.initial);
  }

  // ============================================================
  // Grouped getters
  // ============================================================
  List<PickedPerson> get _responsible =>
      _picked.where((p) => p.role == ParticipantRole.responsible).toList();
  List<PickedPerson> get _participants =>
      _picked.where((p) => p.role == ParticipantRole.participant).toList();
  List<PickedPerson> get _watchers =>
      _picked.where((p) => p.role == ParticipantRole.watcher).toList();

  void _notify() => widget.onChanged(List.of(_picked));

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr ? '👥 الأَشخاص' : '👥 People',
          style:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        _roleSection(
          icon: Icons.shield_outlined,
          color: AppColors.danger,
          title: isAr ? '🎯 المَسؤول (واحِد)' : '🎯 Responsible (one)',
          people: _responsible,
          role: ParticipantRole.responsible,
          isAr: isAr,
          maxOne: true,
        ),
        const SizedBox(height: 10),
        _roleSection(
          icon: Icons.groups_outlined,
          color: AppColors.brand,
          title: isAr
              ? '👥 المُشارِكون (${_participants.length})'
              : '👥 Participants (${_participants.length})',
          people: _participants,
          role: ParticipantRole.participant,
          isAr: isAr,
        ),
        const SizedBox(height: 10),
        _roleSection(
          icon: Icons.visibility_outlined,
          color: Colors.blueGrey,
          title: isAr
              ? '👁 المُتابِعون (${_watchers.length})'
              : '👁 Watchers (${_watchers.length})',
          people: _watchers,
          role: ParticipantRole.watcher,
          isAr: isAr,
        ),
      ],
    );
  }

  Widget _roleSection({
    required IconData icon,
    required Color color,
    required String title,
    required List<PickedPerson> people,
    required ParticipantRole role,
    required bool isAr,
    bool maxOne = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w900)),
              ),
              if (!maxOne || people.isEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt_1, size: 14),
                  label: Text(isAr ? 'إضافة' : 'Add',
                      style: const TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _openPicker(role),
                ),
            ],
          ),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                isAr ? '— لا أَحَد بَعد' : '— none yet',
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 11),
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: people.map((p) => _personChip(p, color)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _personChip(PickedPerson p, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.name,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
          if (p.code != null) ...[
            const SizedBox(width: 4),
            Text('(${p.code})',
                style: TextStyle(
                    color: color.withOpacity(0.7), fontSize: 9)),
          ],
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _picked.removeWhere((x) =>
                  x.employeeId == p.employeeId &&
                  x.accountId == p.accountId &&
                  x.role == p.role));
              _notify();
            },
            child: Icon(Icons.close,
                color: color.withOpacity(0.7), size: 14),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Picker — bottom sheet
  // ============================================================
  Future<void> _openPicker(ParticipantRole role) async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();

    final picked = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        final ctrl = TextEditingController();
        return StatefulBuilder(builder: (ctx, setSt) {
          // اِستَثنِ مَن سَبَق اختِياره
          final excludedEmployeeIds = _picked
              .where((x) => x.employeeId != null)
              .map((x) => x.employeeId!)
              .toSet();
          final candidates = repo.employees.where((e) {
            if (excludedEmployeeIds.contains(e.id)) return false;
            if (query.isEmpty) return true;
            final q = query.toLowerCase();
            return e.fullName.toLowerCase().contains(q) ||
                e.code.toLowerCase().contains(q) ||
                e.jobTitle.toLowerCase().contains(q);
          }).toList();

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAr
                              ? 'اختَر ${role.labelAr()}'
                              : 'Pick ${role.key}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: isAr
                          ? 'بَحث بِالاسم/الكود/المُسَمَّى…'
                          : 'Search name/code/title…',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setSt(() => query = v),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: candidates.isEmpty
                      ? Center(
                          child: Text(
                              isAr ? 'لا تُوجَد نَتائج' : 'No results',
                              style: TextStyle(
                                  color: Colors.grey.shade600)),
                        )
                      : ListView.builder(
                          itemCount: candidates.length,
                          itemBuilder: (_, i) => _candidateTile(
                              candidates[i], ctx, isAr),
                        ),
                ),
              ],
            ),
          );
        });
      },
    );

    if (picked != null) {
      // 🆕 فَحص التَعارُض إذا كان لَدَينا تاريخ
      String? conflict;
      if (widget.eventDate != null) {
        conflict = await EventsTasksService.instance.checkConflict(
          employeeId: picked.id,
          date: widget.eventDate!,
        );
      }
      if (conflict != null && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon:
                const Icon(Icons.warning_amber, color: AppColors.warning),
            title: Text(isAr ? 'تَنبيه تَعارُض' : 'Conflict warning'),
            content: Text('${picked.fullName}\n\n$conflict'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(isAr ? 'إلغاء' : 'Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isAr ? 'أَضِف رَغم ذلك' : 'Add anyway')),
            ],
          ),
        );
        if (proceed != true) return;
      }

      setState(() {
        _picked.add(PickedPerson(
          employeeId: picked.id,
          name: picked.fullName,
          code: picked.code,
          role: role,
        ));
      });
      _notify();
    }
  }

  Widget _candidateTile(Employee e, BuildContext ctx, bool isAr) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.brand.withOpacity(0.15),
        child: Text(e.fullName.isNotEmpty ? e.fullName[0] : '?',
            style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w900,
                fontSize: 11)),
      ),
      title: Text(e.fullName,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800)),
      subtitle: Text('${e.code} · ${e.jobTitle}',
          style: const TextStyle(fontSize: 10)),
      onTap: () => Navigator.pop(ctx, e),
    );
  }
}
