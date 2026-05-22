import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/active_duty_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🚧 شاشة "التَطبيق على رَأس العَمَل فَقَط"
///
/// تَتَحَكَّم في مَنع الدُخول إذا الموظَّف:
///   - في إجازة مُعتَمَدة
///   - حِسابه/مَوظَّفه مُعَلَّق
class ActiveDutySettingsScreen extends StatefulWidget {
  const ActiveDutySettingsScreen({super.key});

  @override
  State<ActiveDutySettingsScreen> createState() =>
      _ActiveDutySettingsScreenState();
}

class _ActiveDutySettingsScreenState
    extends State<ActiveDutySettingsScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ActiveDutySettings.instance.load();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _pickJobTitles() async {
    final settings = ActiveDutySettings.instance;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _JobTitlePicker(initial: settings.jobTitleIds),
    );
    if (selected != null) await settings.setJobTitleIds(selected);
  }

  Future<void> _editMessage({
    required String titleAr,
    required String titleEn,
    required String currentAr,
    required String currentEn,
    required void Function(String? ar, String? en) onSave,
  }) async {
    final ar = TextEditingController(text: currentAr);
    final en = TextEditingController(text: currentEn);
    final isAr = AppStrings.of(context).isAr;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? titleAr : titleEn),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ar,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'العَرَبيّة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: en,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'English',
                  border: OutlineInputBorder(),
                ),
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
            child: Text(isAr ? 'حِفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (result == true) onSave(ar.text, en.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return AnimatedBuilder(
      animation: ActiveDutySettings.instance,
      builder: (context, _) {
        final settings = ActiveDutySettings.instance;
        return Scaffold(
          appBar: M7AppBar(
            title: isAr
                ? '🚧 التَطبيق على رَأس العَمَل'
                : '🚧 Active-Duty Only',
            subtitle: isAr
                ? 'مَنع الدُخول أَثناء الإجازة أَو التَعليق'
                : 'Block login during leave or suspension',
            actions: [
              M7AppBarAction(
                icon: Icons.restore,
                tooltip: isAr ? 'الافتِراضيّات' : 'Reset',
                onPressed: _ready
                    ? () => settings.resetToDefaults()
                    : null,
              ),
            ],
          ),
          body: !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    // ===== Info Banner =====
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: AppColors.info),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'عِندَ التَفعيل، التَطبيق يَرفُض دُخول الموظَّف إذا كانَت لَدَيه إجازة مُعتَمَدة سارِية اليَوم، أَو إذا كانَ حِسابه مُعَلَّقاً. الإدارة وَالـSuper Admin مُسْتَثنَون افتِراضيّاً.'
                                  : 'When enabled, the app blocks login if employee is on approved leave today, or if account is suspended. Admin & Super Admin are bypassed by default.',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ===== 1) Master Switch =====
                    _SectionTitle(
                      icon: Icons.power_settings_new,
                      title: isAr ? 'التَفعيل' : 'Enable',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: settings.enabled,
                      onChanged: settings.setEnabled,
                      title: Text(isAr
                          ? 'تَفعيل سياسة "على رَأس العَمَل فَقَط"'
                          : 'Enable Active-Duty-Only policy'),
                      subtitle: Text(
                        settings.enabled
                            ? (isAr ? 'مُفَعَّلة' : 'Active')
                            : (isAr ? 'مُعَطَّلة' : 'Disabled'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),

                    if (settings.enabled) ...[
                      // ===== 2) What to check =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.checklist,
                        title: isAr ? 'ما الذي يَفحَصه؟' : 'What to check',
                      ),
                      Card(
                        child: Column(
                          children: [
                            SwitchListTile(
                              value: settings.checkLeave,
                              onChanged: settings.setCheckLeave,
                              title: Text(isAr
                                  ? '🏖 مَنع أَثناء الإجازة المُعتَمَدة'
                                  : '🏖 Block during approved leave'),
                              subtitle: Text(
                                isAr
                                    ? 'إذا اليَوم ضِمن فَترة إجازة مُعتَمَدة'
                                    : 'If today is within approved leave',
                                style: const TextStyle(fontSize: 11),
                              ),
                              secondary: const Icon(Icons.beach_access),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              value: settings.checkSuspension,
                              onChanged: settings.setCheckSuspension,
                              title: Text(isAr
                                  ? '🚫 مَنع الحِسابات المُعَلَّقة'
                                  : '🚫 Block suspended accounts'),
                              subtitle: Text(
                                isAr
                                    ? 'إذا حِساب/مَوظَّف غَير نَشِط'
                                    : 'If account/employee inactive',
                                style: const TextStyle(fontSize: 11),
                              ),
                              secondary: const Icon(Icons.block),
                            ),
                          ],
                        ),
                      ),

                      // ===== 3) Scope =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.group,
                        title: isAr ? 'النِطاق' : 'Scope',
                      ),
                      Card(
                        child: Column(
                          children: [
                            RadioListTile<ActiveDutyScope>(
                              value: ActiveDutyScope.allAccounts,
                              groupValue: settings.scope,
                              onChanged: (v) =>
                                  v != null ? settings.setScope(v) : null,
                              title: Text(isAr
                                  ? 'كُلّ الحِسابات'
                                  : 'All accounts'),
                            ),
                            RadioListTile<ActiveDutyScope>(
                              value: ActiveDutyScope.includedOnly,
                              groupValue: settings.scope,
                              onChanged: (v) =>
                                  v != null ? settings.setScope(v) : null,
                              title: Text(isAr
                                  ? 'فَقَط لِلمُسَمَّيات المُحَدَّدة'
                                  : 'Only for selected job titles'),
                            ),
                            RadioListTile<ActiveDutyScope>(
                              value: ActiveDutyScope.excludedOnly,
                              groupValue: settings.scope,
                              onChanged: (v) =>
                                  v != null ? settings.setScope(v) : null,
                              title: Text(isAr
                                  ? 'لِلجَميع عَدا المُحَدَّدين'
                                  : 'Everyone except selected'),
                            ),
                          ],
                        ),
                      ),

                      if (settings.scope != ActiveDutyScope.allAccounts) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: Text(isAr
                                ? 'المُسَمَّيات الوَظيفيّة'
                                : 'Job titles'),
                            subtitle: Text(
                              isAr
                                  ? '${settings.jobTitleIds.length} مُسَمَّى مُحَدَّد'
                                  : '${settings.jobTitleIds.length} selected',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _pickJobTitles,
                          ),
                        ),
                      ],

                      // ===== 4) Bypass Roles =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.admin_panel_settings,
                        title:
                            isAr ? 'تَجاوُز لِأَدوار مُعَيَّنة' : 'Bypass roles',
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr
                                    ? 'هذه الأَدوار لا تَخضَع لِلسياسة (تَدخُل حَتّى في الإجازة):'
                                    : 'These roles bypass the policy:',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final r in [
                                    'super_admin',
                                    'admin',
                                    'manager',
                                    'operation',
                                    'supervisor',
                                    'camp_boss',
                                    'hr',
                                  ])
                                    FilterChip(
                                      label: Text(r),
                                      selected: settings.bypassRoles
                                          .contains(r),
                                      onSelected: (sel) {
                                        final newSet =
                                            Set<String>.from(settings.bypassRoles);
                                        if (sel) {
                                          newSet.add(r);
                                        } else {
                                          newSet.remove(r);
                                        }
                                        settings.setBypassRoles(newSet);
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ===== 5) Messages =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.message,
                        title: isAr ? 'الرَسائِل' : 'Messages',
                      ),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.beach_access,
                                  color: AppColors.warning),
                              title: Text(isAr
                                  ? 'رِسالة الإجازة'
                                  : 'Leave message'),
                              subtitle: Text(
                                isAr
                                    ? settings.messageLeaveAr
                                    : settings.messageLeaveEn,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.edit),
                              onTap: () => _editMessage(
                                titleAr: 'رِسالة الإجازة',
                                titleEn: 'Leave message',
                                currentAr: settings.messageLeaveAr,
                                currentEn: settings.messageLeaveEn,
                                onSave: (ar, en) => settings.setMessageLeave(
                                    ar: ar, en: en),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.block,
                                  color: AppColors.danger),
                              title: Text(isAr
                                  ? 'رِسالة التَعليق'
                                  : 'Suspension message'),
                              subtitle: Text(
                                isAr
                                    ? settings.messageSuspendedAr
                                    : settings.messageSuspendedEn,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.edit),
                              onTap: () => _editMessage(
                                titleAr: 'رِسالة التَعليق',
                                titleEn: 'Suspension message',
                                currentAr: settings.messageSuspendedAr,
                                currentEn: settings.messageSuspendedEn,
                                onSave: (ar, en) =>
                                    settings.setMessageSuspended(
                                        ar: ar, en: en),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),
                  ],
                ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.brand,
              fontSize: 14),
        ),
      ],
    );
  }
}

// ============================================================
// مُختار المُسَمَّيات الوَظيفيّة
// ============================================================
class _JobTitlePicker extends StatefulWidget {
  final Set<String> initial;
  const _JobTitlePicker({required this.initial});
  @override
  State<_JobTitlePicker> createState() => _JobTitlePickerState();
}

class _JobTitlePickerState extends State<_JobTitlePicker> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final jobTitles = MockRepository().jobTitles;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr ? 'اختَر المُسَمَّيات' : 'Pick Job Titles',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _selected),
                    child: Text(isAr ? 'تَطبيق' : 'Apply',
                        style: const TextStyle(color: AppColors.gold)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: jobTitles.length,
                itemBuilder: (_, i) {
                  final jt = jobTitles[i];
                  final on = _selected.contains(jt.id);
                  return CheckboxListTile(
                    value: on,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(jt.id);
                        } else {
                          _selected.remove(jt.id);
                        }
                      });
                    },
                    title: Text(isAr ? jt.nameAr : jt.nameEn),
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
