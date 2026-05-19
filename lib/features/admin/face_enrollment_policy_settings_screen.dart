import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/face_enrollment_policy_settings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🔐 شاشة إعدادات سياسة تَسجيل بَصمة الوَجه الإجباريّ
///
/// تَتَحَكَّم في:
///   - تَفعيل/تَعطيل السياسة كَكُلّ
///   - أَيّ المُسَمَّيات الوَظيفيّة مَشمولة (كُلّها أَو قائِمة مُحَدَّدة)
///   - مُهلة التَأجيل (Grace period) بِالساعات
///   - عَدَد زَوايا الوَجه الإجباريّ
///   - هَل يُحَوَّل المُستَخدِم تِلقائيّاً لِدُخول بِالوَجه بَعدَ التَسجيل
class FaceEnrollmentPolicySettingsScreen extends StatefulWidget {
  const FaceEnrollmentPolicySettingsScreen({super.key});

  @override
  State<FaceEnrollmentPolicySettingsScreen> createState() =>
      _FaceEnrollmentPolicySettingsScreenState();
}

class _FaceEnrollmentPolicySettingsScreenState
    extends State<FaceEnrollmentPolicySettingsScreen> {
  bool _ready = false;
  bool _enabled = false;
  bool _allJobTitles = false;
  final Set<String> _allowedIds = {};
  int _gracePeriodHours = 24;
  int _minPoses = 5;
  bool _forceFaceLoginAfter = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await FaceEnrollmentPolicySettings.instance.load();
    final s = FaceEnrollmentPolicySettings.instance;
    _enabled = s.enabled;
    _allJobTitles = s.allJobTitles;
    _allowedIds
      ..clear()
      ..addAll(s.allowedJobTitleIds);
    _gracePeriodHours = s.gracePeriodHours;
    _minPoses = s.minPoses;
    _forceFaceLoginAfter = s.forceFaceLoginAfter;
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _save() async {
    final ok = await FaceEnrollmentPolicySettings.instance.save(
      enabled: _enabled,
      allJobTitles: _allJobTitles,
      allowedJobTitleIds: _allowedIds,
      gracePeriodHours: _gracePeriodHours,
      minPoses: _minPoses,
      forceFaceLoginAfter: _forceFaceLoginAfter,
    );
    if (!mounted) return;
    final isAr = AppStrings.of(context).isAr;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.warning,
      content: Text(ok
          ? (isAr ? 'تَمَّ الحِفظ' : 'Saved')
          : (isAr ? 'حُفِظ محلّيّاً فَقَط' : 'Saved locally only')),
    ));
  }

  /// 🆕 احسُب الحِسابات المُتَأَثِّرة بِالسياسة الحاليّة
  /// (نَشطة + لم تُسَجِّل بَصمَتَها بَعد + ضِمن نِطاق المُسَمَّيات)
  List<Map<String, String>> _computeAffectedAccounts() {
    final repo = MockRepository();
    final affected = <Map<String, String>>[];
    for (final acc in repo.accounts) {
      if (!acc.isActive) continue;
      if (acc.mustEnrollFace) continue; // أَصلاً مُفَعَّل
      if (acc.faceEnrolledAt != null) continue; // سَبَق التَسجيل
      if (acc.employeeId == null || acc.employeeId!.isEmpty) continue;
      final emp = repo.employeeById(acc.employeeId);
      if (emp == null) continue;
      // فَحص نِطاق المُسَمَّيات
      if (!_allJobTitles && !_allowedIds.contains(emp.jobTitleId ?? '')) {
        continue;
      }
      affected.add({
        'id': acc.id,
        'username': acc.username,
        'name': acc.fullName,
      });
    }
    return affected;
  }

  Future<void> _applyRetroactively() async {
    final isAr = AppStrings.of(context).isAr;
    if (!_enabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? 'فَعِّل السياسة أَوَّلاً قَبل التَطبيق الرَجعيّ'
            : 'Enable the policy first before applying retroactively'),
      ));
      return;
    }

    final affected = _computeAffectedAccounts();
    if (affected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.info,
        content: Text(isAr
            ? 'لا حِسابات تُطابِق السياسة'
            : 'No accounts match the policy'),
      ));
      return;
    }

    // حِوار تَأكيد
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr
            ? 'تَأكيد التَطبيق الرَجعيّ'
            : 'Confirm Retroactive Apply'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAr
                  ? 'سَيُفرَض تَسجيل بَصمة الوَجه على ${affected.length} حِساب:'
                  : '${affected.length} accounts will be required to enroll:'),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: affected.map((a) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                            '• ${a['name']} (${a['username']})',
                            style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'لَن يَتَأَثَّر مَن سَجَّل بَصمَتَه أَو حِسابُه مُعَطَّل.'
                    : 'Already-enrolled or inactive accounts are skipped.',
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(isAr ? 'تَطبيق' : 'Apply'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // نَفِّذ على Supabase
    final supa = SupabaseService();
    if (!supa.isReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'لا اتّصال بِـSupabase'
            : 'No Supabase connection'),
      ));
      return;
    }

    int successCount = 0;
    for (final a in affected) {
      try {
        await supa.client
            .from('accounts')
            .update({
              'must_enroll_face': true,
              'face_enrolled_at': null,
            })
            .eq('id', a['id']!);
        // حَدِّث الذاكِرة المَحَلّيّة
        final acc = MockRepository()
            .accounts
            .firstWhere((x) => x.id == a['id']);
        acc.mustEnrollFace = true;
        acc.faceEnrolledAt = null;
        successCount++;
      } catch (e) {
        M7Log.error('FacePolicyApply', 'update ${a['username']}',
            error: e);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(isAr
          ? '✅ تَمَّ تَحديث $successCount/${affected.length} حِساب'
          : '✅ Updated $successCount/${affected.length} accounts'),
    ));
  }

  Future<void> _pickJobTitles() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _JobTitlePickerSheet(initial: _allowedIds),
    );
    if (picked != null) {
      setState(() {
        _allowedIds
          ..clear()
          ..addAll(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    if (!_ready) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr
              ? 'سياسة تَسجيل بَصمة الوَجه'
              : 'Face Enrollment Policy',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final repo = MockRepository();
    return Scaffold(
      appBar: M7AppBar(
        title: isAr
            ? 'سياسة تَسجيل بَصمة الوَجه'
            : 'Face Enrollment Policy',
        actions: [
          M7AppBarAction(
            icon: Icons.save,
            tooltip: isAr ? 'حِفظ' : 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== مُقَدِّمة =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.info.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? 'عِندَ تَفعيل هذِه السياسة، يَتِم إجبار الموظَّفين الجُدُد على تَسجيل بَصمة وَجه بَعدَ تَغيير كلِمة المُرور وَقَبل اكتِمال أَوَّل دُخول.'
                        : 'When enabled, new employees are forced to enroll a face biometric after changing their password and before completing their first login.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== تَفعيل =====
          SwitchListTile(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: Text(
              isAr ? 'تَفعيل السياسة' : 'Enable policy',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              _enabled
                  ? (isAr ? 'السياسة مُفَعَّلة' : 'Policy is active')
                  : (isAr
                      ? 'السياسة مُعَطَّلة — لا تَسجيل إجباريّ'
                      : 'Policy is inactive'),
            ),
          ),
          if (_enabled) ...[
            const Divider(),
            // ===== نِطاق التَطبيق =====
            _sectionHeader(isAr ? 'النِطاق' : 'Scope'),
            SwitchListTile(
              value: _allJobTitles,
              onChanged: (v) => setState(() => _allJobTitles = v),
              title: Text(isAr ? 'كُلّ المُسَمَّيات' : 'All job titles'),
              subtitle: Text(isAr
                  ? 'يَنطَبِق على كُلّ مُوظَّف جَديد'
                  : 'Applies to every new employee'),
            ),
            if (!_allJobTitles) ...[
              Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.work, color: AppColors.gold),
                  title: Text(isAr
                      ? '${_allowedIds.length} مُسَمَّى مُحَدَّد'
                      : '${_allowedIds.length} job titles selected'),
                  subtitle: Text(isAr
                      ? 'اختَر المُسَمَّيات المَشمولة'
                      : 'Pick included job titles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickJobTitles,
                ),
              ),
              if (_allowedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _allowedIds.map((id) {
                      final jt = repo.jobTitles
                          .firstWhere((j) => j.id == id, orElse: () {
                        return JobTitle(
                          id: id,
                          nameAr: id,
                          nameEn: id,
                          category: JobTitleCategory.worker,
                        );
                      });
                      final name = isAr ? jt.nameAr : jt.nameEn;
                      return Chip(
                        label:
                            Text(name, style: const TextStyle(fontSize: 11)),
                        onDeleted: () =>
                            setState(() => _allowedIds.remove(id)),
                      );
                    }).toList(),
                  ),
                ),
            ],
            const Divider(),

            // ===== مُهلة التَأجيل =====
            _sectionHeader(isAr ? 'مُهلة التَأجيل' : 'Grace Period'),
            ListTile(
              leading: const Icon(Icons.timer, color: AppColors.gold),
              title: Text(isAr
                  ? '$_gracePeriodHours ساعة'
                  : '$_gracePeriodHours hours'),
              subtitle: Text(isAr
                  ? '0 = إجباريّ من أَوَّل دُخول مُباشَرةً'
                  : '0 = mandatory from first login immediately'),
            ),
            Slider(
              value: _gracePeriodHours.toDouble(),
              min: 0,
              max: 168, // أُسبوع كامِل
              divisions: 168,
              label: '$_gracePeriodHours',
              onChanged: (v) =>
                  setState(() => _gracePeriodHours = v.toInt()),
            ),
            const Divider(),

            // ===== عَدَد الزَوايا =====
            _sectionHeader(isAr ? 'عَدَد الزَوايا' : 'Required Poses'),
            ListTile(
              leading: const Icon(Icons.photo_camera,
                  color: AppColors.gold),
              title: Text(isAr
                  ? '$_minPoses زَوايا إجباريّ'
                  : '$_minPoses poses required'),
              subtitle: Text(isAr
                  ? 'الافتِراضيّ 5: أَمام، يَمين، يَسار، ابتِسامة، تَنويع'
                  : 'Default 5: front, right, left, smile, variation'),
            ),
            Slider(
              value: _minPoses.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$_minPoses',
              onChanged: (v) => setState(() => _minPoses = v.toInt()),
            ),
            const Divider(),

            // ===== تَحويل تِلقائيّ لِدُخول بِالوَجه =====
            _sectionHeader(isAr ? 'بَعدَ التَسجيل' : 'After Enrollment'),
            SwitchListTile(
              value: _forceFaceLoginAfter,
              onChanged: (v) =>
                  setState(() => _forceFaceLoginAfter = v),
              title: Text(isAr
                  ? 'تَحويل طَريقة الدُخول إلى وَجه تِلقائيّاً'
                  : 'Auto-switch login method to face'),
              subtitle: Text(isAr
                  ? 'بَعدَ نَجاح التَسجيل، يُصبِح الدُخول بِالوَجه إلزاميّاً'
                  : 'After successful enrollment, force face login'),
            ),

            const SizedBox(height: 24),
            const Divider(),

            // ===== التَطبيق الرَجعيّ على الحِسابات الحاليّة =====
            _sectionHeader(
                isAr ? 'الحِسابات الحاليّة' : 'Existing Accounts'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withOpacity(0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'السياسة تُطَبَّق تِلقائيّاً على الحِسابات الجَديدة فَقَط. لِفَرضِها على المَوظَّفين الحاليّين، استَخدِم الزِرّ أَدناه.'
                          : 'The policy applies automatically only to NEW accounts. To enforce it on existing employees, use the button below.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _applyRetroactively,
              icon: const Icon(Icons.history),
              label: Text(
                isAr
                    ? '🔁 تَطبيق رَجعيّ على الحِسابات الحاليّة'
                    : '🔁 Apply Retroactively to Existing Accounts',
                style:
                    const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.gold)),
      );
}

// ============================================================
// مُختار مُسَمَّيات وَظيفيّة
// ============================================================
class _JobTitlePickerSheet extends StatefulWidget {
  final Set<String> initial;
  const _JobTitlePickerSheet({required this.initial});

  @override
  State<_JobTitlePickerSheet> createState() => _JobTitlePickerSheetState();
}

class _JobTitlePickerSheetState extends State<_JobTitlePickerSheet> {
  late final Set<String> _selected = widget.initial.toSet();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final query = _filter.trim().toLowerCase();
    final list = repo.jobTitles.where((j) {
      if (query.isEmpty) return true;
      return j.nameAr.toLowerCase().contains(query) ||
          j.nameEn.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) =>
          (isAr ? a.nameAr : a.nameEn).compareTo(isAr ? b.nameAr : b.nameEn));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.work, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'اختَر المُسَمَّيات الوَظيفيّة'
                          : 'Select job titles',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.white),
                    onPressed: () => Navigator.pop(context, _selected),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration: InputDecoration(
                  hintText: isAr ? 'ابحَث…' : 'Search…',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final jt = list[i];
                  final isSel = _selected.contains(jt.id);
                  final name = isAr ? jt.nameAr : jt.nameEn;
                  return CheckboxListTile(
                    value: isSel,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(jt.id);
                        } else {
                          _selected.remove(jt.id);
                        }
                      });
                    },
                    title: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                    subtitle: Text(
                        '${jt.category.name} · L${jt.level}',
                        style: const TextStyle(fontSize: 11)),
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
