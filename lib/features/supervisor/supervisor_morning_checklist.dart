import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة الجرد الصباحي - 3 صور يومية:
/// - البوديوم (نظافة بيئة العمل)
/// - الموظفون (المظهر والزي)
/// - البركنج (الجاهزية والأمان)
/// مع تعليمات + سجل الأيام السابقة
class SupervisorMorningChecklist extends StatefulWidget {
  const SupervisorMorningChecklist({super.key});

  @override
  State<SupervisorMorningChecklist> createState() =>
      _SupervisorMorningChecklistState();
}

class _SupervisorMorningChecklistState
    extends State<SupervisorMorningChecklist>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _instructionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final pointId = auth.selectedSiteId;
    final supId = auth.currentUser?.employeeId;

    if (pointId == null) {
      // 🆕 لِلمَدير/المُسؤول: مُنتَقي نِقاط بَدَلاً من رِسالة "غَير مَربوط"
      final canSeeAll = auth.isSuperAdmin ||
          auth.permissions.contains(P.sitesView);
      if (canSeeAll) {
        return _PointPickerView(
          countryId: auth.selectedCountryId,
          onPicked: (id) {
            auth.setActiveSite(id);
            // ستُعيد بِناء الشاشة تِلقائيّاً بِفَضل watch
          },
        );
      }
      return EmptyState(
        icon: Icons.location_off,
        message: s.isAr
            ? 'لم يتم ربط حسابك بنقطة بعد. تواصل مع مدير العمليات.'
            : 'Your account is not assigned to a point yet. Contact Operations.',
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              indicatorColor: AppColors.brand,
              unselectedLabelColor: Theme.of(context).disabledColor,
              tabs: [
                Tab(
                    icon: const Icon(Icons.today, size: 16),
                    text: s.todayChecklist),
                Tab(
                    icon: const Icon(Icons.history, size: 16),
                    text: s.pastChecklists),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _TodayTab(
                  pointId: pointId,
                  supervisorId: supId ?? '',
                  instructionsExpanded: _instructionsExpanded,
                  onToggleInstructions: () => setState(() {
                    _instructionsExpanded = !_instructionsExpanded;
                  }),
                ),
                _HistoryTab(pointId: pointId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب اليوم - 3 أقسام للصور
// ============================================================
class _TodayTab extends StatelessWidget {
  final String pointId;
  final String supervisorId;
  final bool instructionsExpanded;
  final VoidCallback onToggleInstructions;

  const _TodayTab({
    required this.pointId,
    required this.supervisorId,
    required this.instructionsExpanded,
    required this.onToggleInstructions,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final checklist = repo.getOrCreateTodayChecklist(
      pointId: pointId,
      supervisorId: supervisorId,
    );

    // 🆕 الموظفون من الروستر الفعلي لهذه النقطة
    final pointRosters = repo.rosters
        .where((r) => r.siteId == pointId)
        .toList()
      ..sort((a, b) {
        int p(WeeklyRoster x) {
          if (x.status == RosterStatus.approved) return 3;
          if (x.status == RosterStatus.submitted) return 2;
          if (x.status == RosterStatus.draft) return 1;
          return 0;
        }
        final cmp = p(b).compareTo(p(a));
        if (cmp != 0) return cmp;
        return b.weekStart.compareTo(a.weekStart);
      });
    final List<Employee> rosterEmployees;
    if (pointRosters.isEmpty) {
      rosterEmployees = [];
    } else {
      final empIds =
          pointRosters.first.assignments.map((a) => a.employeeId).toSet();
      rosterEmployees =
          repo.employees.where((e) => empIds.contains(e.id)).toList();
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // شريط الحالة في الأعلى
        _StatusHeader(checklist: checklist),
        const SizedBox(height: 12),

        // 🆕 موظفو الروستر - يجب أن يظهروا في صورة "الموظفون"
        _RosterEmployeesBanner(employees: rosterEmployees),
        const SizedBox(height: 12),

        // التعليمات (قابلة للطي)
        _InstructionsBanner(
          expanded: instructionsExpanded,
          onToggle: onToggleInstructions,
        ),
        const SizedBox(height: 12),

        // 1. البوديوم
        _PhotoCard(
          checklist: checklist,
          kind: ChecklistPhotoKind.podium,
          icon: Icons.dashboard,
          color: AppColors.success,
          title: s.podiumPhoto,
          criterion: s.podiumCriterion,
          description: s.podiumDesc,
        ),

        // 2. الموظفون
        _PhotoCard(
          checklist: checklist,
          kind: ChecklistPhotoKind.employees,
          icon: Icons.groups_2,
          color: AppColors.brand,
          title: s.employeesPhoto,
          criterion: s.employeesCriterion,
          description: s.employeesDesc,
        ),

        // 3. البركنج
        _PhotoCard(
          checklist: checklist,
          kind: ChecklistPhotoKind.parking,
          icon: Icons.local_parking,
          color: AppColors.purple,
          title: s.parkingPhoto,
          criterion: s.parkingCriterion,
          description: s.parkingDesc,
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ============================================================
// شريط الحالة - إجمالي الصور المرفوعة
// ============================================================
class _StatusHeader extends StatelessWidget {
  final MorningChecklist checklist;
  const _StatusHeader({required this.checklist});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isComplete = checklist.isComplete;
    final color = isComplete ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
                isComplete ? Icons.check : Icons.access_time,
                color: Colors.white,
                size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isComplete ? s.checklistComplete : s.checklistPending,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${checklist.uploadedCount}/3 ${s.photosUploaded} • ${_fmt(checklist.date)}',
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
          // مؤشر دائري للتقدم
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: checklist.uploadedCount / 3,
                  strokeWidth: 4,
                  backgroundColor: color.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '${checklist.uploadedCount}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';
}

// ============================================================
// بانر التعليمات (قابل للطي)
// ============================================================
class _InstructionsBanner extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _InstructionsBanner({
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.menu_book,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.checklistInstructions,
                        style: const TextStyle(
                            color: AppColors.info,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.info,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(s.checklistInstructionsBody,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// كارد كل صورة (Podium / Employees / Parking)
// ============================================================
class _PhotoCard extends StatefulWidget {
  final MorningChecklist checklist;
  final ChecklistPhotoKind kind;
  final IconData icon;
  final Color color;
  final String title;
  final String criterion;
  final String description;

  const _PhotoCard({
    required this.checklist,
    required this.kind,
    required this.icon,
    required this.color,
    required this.title,
    required this.criterion,
    required this.description,
  });

  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  ChecklistPhoto get _photo {
    switch (widget.kind) {
      case ChecklistPhotoKind.podium:
        return widget.checklist.podium;
      case ChecklistPhotoKind.employees:
        return widget.checklist.employees;
      case ChecklistPhotoKind.parking:
        return widget.checklist.parking;
    }
  }

  /// 🆕 التقاط صورة فعليّة من الكاميرا أو المعرض.
  /// يَفتح حواراً يَسأل المستخدم: كاميرا أم معرض؟
  /// (على الـ Web الكاميرا تَفتح كاميرا المتصفّح، والمعرض يَفتح file picker.)
  Future<void> _capture() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    // 1) اختر مصدر الصورة: كاميرا أم معرض
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                isAr
                    ? 'اختر مصدر الصورة'
                    : 'Choose image source',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.camera_alt,
                  color: AppColors.brand, size: 28),
              title: Text(isAr ? 'الكاميرا' : 'Camera',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              subtitle: Text(
                  isAr
                      ? 'التقاط صورة جديدة الآن'
                      : 'Capture a new photo now',
                  style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: AppColors.success, size: 28),
              title: Text(isAr ? 'المعرض' : 'Gallery',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              subtitle: Text(
                  isAr
                      ? 'اختيار صورة من جهازك'
                      : 'Pick a photo from your device',
                  style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    // 2) التقاط/اختيار الصورة عبر image_picker
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 80, // ضغط معتدل لتقليل الحجم
        maxWidth: 1920,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) {
        // المستخدم ألغى الالتقاط
        return;
      }

      // 3) احفظ المسار في الـ checklist
      // ملاحظة: على Flutter Web، file.path يَكون blob URL — كافٍ للعرض
      // والرفع لـ Supabase Storage لاحقاً.
      repo.setChecklistPhoto(
        checklist: widget.checklist,
        kind: widget.kind,
        localPath: file.path,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr
            ? '✅ تمّ تسجيل ${widget.title}'
            : '✅ ${widget.title} captured'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? '❌ فشل التقاط الصورة: $e'
            : '❌ Failed to capture: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final photo = _photo;
    final isUploaded = photo.isUploaded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUploaded
              ? widget.color.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor,
          width: isUploaded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // رأس الكارد
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon,
                      color: widget.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: TextStyle(
                              color: widget.color,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      Text(widget.criterion,
                          style: TextStyle(
                              color: widget.color.withValues(alpha: 0.8),
                              fontSize: 10)),
                    ],
                  ),
                ),
                if (isUploaded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check,
                            color: Colors.white, size: 12),
                        SizedBox(width: 3),
                        Text('✓',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // الوصف + معاينة الصورة
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.description,
                    style: const TextStyle(
                        fontSize: 11, height: 1.5)),
                const SizedBox(height: 12),
                if (isUploaded) ...[
                  // معاينة الصورة (Placeholder حتى ربط الكاميرا)
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.color.withValues(alpha: 0.2),
                          widget.color.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: widget.color.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image,
                              size: 48, color: widget.color),
                          const SizedBox(height: 4),
                          Text(
                            s.isAr
                                ? 'معاينة الصورة'
                                : 'Photo Preview',
                            style: TextStyle(
                                color: widget.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // وقت الالتقاط
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 12, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(
                          '${s.capturedAt}: ${_fmtDt(photo.capturedAt!)}',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _capture,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(s.retakePhoto),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _capture,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(
                      s.takePhoto,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDt(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year}  $h:$m';
  }
}

// ============================================================
// تاب التاريخ
// ============================================================
class _HistoryTab extends StatelessWidget {
  final String pointId;
  const _HistoryTab({required this.pointId});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final list = repo.checklistsForPoint(pointId);

    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        message: s.isAr ? 'لا يوجد سجل بعد' : 'No history yet',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _HistoryCard(checklist: list[i]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final MorningChecklist checklist;
  const _HistoryCard({required this.checklist});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isComplete = checklist.isComplete;
    final color = isComplete ? AppColors.success : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                isComplete ? Icons.check_circle : Icons.warning,
                color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmt(checklist.date),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text(
                  '${checklist.uploadedCount}/3 ${s.photosUploaded}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _MiniIcon(
                  ok: checklist.podium.isUploaded,
                  icon: Icons.dashboard,
                  color: AppColors.success),
              const SizedBox(width: 4),
              _MiniIcon(
                  ok: checklist.employees.isUploaded,
                  icon: Icons.groups_2,
                  color: AppColors.brand),
              const SizedBox(width: 4),
              _MiniIcon(
                  ok: checklist.parking.isUploaded,
                  icon: Icons.local_parking,
                  color: AppColors.purple),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    const days = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    return '${days[d.weekday - 1]} ${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';
  }
}

class _MiniIcon extends StatelessWidget {
  final bool ok;
  final IconData icon;
  final Color color;
  const _MiniIcon({
    required this.ok,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: ok ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: ok
                ? color
                : Theme.of(context).dividerColor),
      ),
      child: Icon(icon,
          size: 14,
          color: ok ? color : Theme.of(context).disabledColor),
    );
  }
}

// ============================================================
// 🆕 شريط: موظفو الروستر للنقطة (يجب التحقق منهم في صورة الموظفين)
// ============================================================
class _RosterEmployeesBanner extends StatelessWidget {
  final List<Employee> employees;
  const _RosterEmployeesBanner({required this.employees});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (employees.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline,
              color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.isAr
                  ? 'لا يوجد روستر لهذه النقطة بعد. أنشئ روستراً وأضف الموظفين أولاً.'
                  : 'No roster for this point yet. Create a roster and add employees first.',
              style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.fact_check_outlined,
                color: AppColors.brand, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.isAr
                    ? 'موظفو الروستر اليوم (${employees.length})'
                    : "Today's roster employees (${employees.length})",
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brand),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            s.isAr
                ? 'تأكد من ظهورهم جميعاً في صورة "الموظفون" أدناه'
                : 'Make sure all of them appear in the "Employees" photo below',
            style: const TextStyle(
                fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: employees.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.brand.withValues(alpha: 0.30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 8,
                    backgroundColor:
                        AppColors.brand.withValues(alpha: 0.15),
                    child: Text(
                      e.initials,
                      style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: AppColors.brand),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    e.fullName.length > 20
                        ? '${e.fullName.substring(0, 20)}…'
                        : e.fullName,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ]),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// 🆕 مُنتَقي النِقاط لِلمَدير/المُسؤول الذي لا يَملِك نُقطة مُسَنَدة.
/// يَعرِض كُلّ النِقاط النَشِطة في دَولة المُستَخدِم النَشِطة، وَعِندَ
/// الاختِيار يَنادي `onPicked` (تُحَدِّث `auth.setActiveSite`).
class _PointPickerView extends StatefulWidget {
  final String? countryId;
  final ValueChanged<String> onPicked;
  const _PointPickerView({
    required this.countryId,
    required this.onPicked,
  });

  @override
  State<_PointPickerView> createState() => _PointPickerViewState();
}

class _PointPickerViewState extends State<_PointPickerView> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final q = _filter.trim().toLowerCase();
    // ابني قائِمة النِقاط النَشطة (مُقَيَّدة بِالدَولة إن وُجِدَت)
    var points = repo.points
        .where((p) => p.status == EntityStatus.active)
        .where((p) {
      if (widget.countryId == null) return true;
      return p.countryId == widget.countryId;
    }).toList();
    // فالـback: إن خَلَت الدَولة من نِقاط، اعرِض الكُلّ
    if (points.isEmpty) {
      points = repo.points
          .where((p) => p.status == EntityStatus.active)
          .toList();
    }
    if (q.isNotEmpty) {
      points = points
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.code.toLowerCase().contains(q))
          .toList();
    }
    points.sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      child: Column(
        children: [
          // بانِر تَرحيبيّ مُتَدَرِّج
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.brand.withValues(alpha: 0.10),
                  AppColors.gold.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings,
                      color: AppColors.gold, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? 'وَضع المَدير' : 'Manager Mode',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isAr
                            ? 'اختَر نُقطة لِعَرض شيكلستِها الصَباحيّ. يُمكِنكَ التَبديل بَين النِقاط في أَيّ وَقت.'
                            : 'Pick a point to view its morning checklist. You can switch points anytime.',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // شَريط البَحث
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.isAr
                    ? 'ابحَث بِالاسم أَو الكود…'
                    : 'Search by name or code…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.isAr
                    ? '${points.length} نُقطة مُتاحة'
                    : '${points.length} points available',
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: points.isEmpty
                ? EmptyState(
                    icon: Icons.location_off,
                    message: s.isAr
                        ? 'لا نِقاط مُطابِقة'
                        : 'No matching points',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: points.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final p = points[i];
                      return InkWell(
                        onTap: () => widget.onPicked(p.id),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.gold
                                    .withValues(alpha: 0.20)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.place,
                                    color: AppColors.warning,
                                    size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14)),
                                    Text(
                                      p.code,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.gold),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
