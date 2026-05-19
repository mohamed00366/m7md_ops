import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/replacement_notification_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🔔 شاشة إعدادات إشعار التَبديل
///
/// تَتَحَكَّم في:
///   - مَن يَستَلِم إشعاراً داخِل التَطبيق عِندَ تَبديل مُوظَّف غائِب.
///   - مَن يَستَلِم بَريداً إلكترونيّاً (إذا كان البَريد مُفَعَّلاً).
///   - تَفعيل/تَعطيل كُلّ قَناة.
class ReplacementNotificationSettingsScreen extends StatefulWidget {
  const ReplacementNotificationSettingsScreen({super.key});

  @override
  State<ReplacementNotificationSettingsScreen> createState() =>
      _ReplacementNotificationSettingsScreenState();
}

class _ReplacementNotificationSettingsScreenState
    extends State<ReplacementNotificationSettingsScreen> {
  bool _ready = false;
  bool _inAppEnabled = true;
  bool _emailEnabled = false;
  final Set<String> _userIds = {};
  final Set<String> _emails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ReplacementNotificationSettings.instance.load();
    final s = ReplacementNotificationSettings.instance;
    _inAppEnabled = s.inAppEnabled;
    _emailEnabled = s.emailEnabled;
    _userIds
      ..clear()
      ..addAll(s.recipientUserIds);
    _emails
      ..clear()
      ..addAll(s.recipientEmails);
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _save() async {
    final ok = await ReplacementNotificationSettings.instance.save(
      recipientUserIds: _userIds,
      recipientEmails: _emails,
      inAppEnabled: _inAppEnabled,
      emailEnabled: _emailEnabled,
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

  Future<void> _pickUsers() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _UserPickerSheet(initial: _userIds),
    );
    if (picked != null) {
      setState(() {
        _userIds
          ..clear()
          ..addAll(picked);
      });
    }
  }

  Future<void> _addEmail() async {
    final isAr = AppStrings.of(context).isAr;
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? 'أَضِف بَريداً' : 'Add email'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: isAr ? 'user@example.com' : 'user@example.com',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(isAr ? 'إضافة' : 'Add'),
          ),
        ],
      ),
    );
    final clean = email?.trim() ?? '';
    if (clean.isEmpty) return;
    if (!clean.contains('@')) return;
    setState(() => _emails.add(clean));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    if (!_ready) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? 'إشعارات التَبديل' : 'Replacement Notifications',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إشعارات التَبديل' : 'Replacement Notifications',
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
          _sectionHeader(
              isAr ? 'إشعار داخِل التَطبيق' : 'In-app Notification'),
          SwitchListTile(
            value: _inAppEnabled,
            onChanged: (v) => setState(() => _inAppEnabled = v),
            title: Text(isAr ? 'مُفَعَّل' : 'Enabled'),
            subtitle: Text(isAr
                ? 'يَظهَر في شاشة الإشعارات لِلمُستَلِمين'
                : 'Shown in notifications screen for recipients'),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.people, color: AppColors.gold),
              title: Text(isAr
                  ? '${_userIds.length} مُستَخدِم مُحَدَّد'
                  : '${_userIds.length} users selected'),
              subtitle: Text(isAr
                  ? 'اختَر مَن يَستَلِم الإشعار داخِل التَطبيق'
                  : 'Pick who gets in-app notifications'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickUsers,
            ),
          ),
          if (_userIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _userIds.map((uid) {
                final user = MockRepository()
                    .users
                    .firstWhere((u) => u.id == uid,
                        orElse: () => AppUser(
                              id: uid,
                              username: uid,
                              fullName: uid,
                              role: UserRole.employee,
                            ));
                return Chip(
                  label: Text(user.fullName,
                      style: const TextStyle(fontSize: 11)),
                  onDeleted: () => setState(() => _userIds.remove(uid)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 24),
          _sectionHeader(isAr ? 'إشعار بِالبَريد' : 'Email Notification'),
          SwitchListTile(
            value: _emailEnabled,
            onChanged: (v) => setState(() => _emailEnabled = v),
            title: Text(isAr ? 'مُفَعَّل' : 'Enabled'),
            subtitle: Text(isAr
                ? 'يَتَطَلَّب إعداد Edge Function: send-email'
                : 'Requires Edge Function: send-email'),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email, color: AppColors.gold),
                  title: Text(isAr
                      ? '${_emails.length} عُنوان بَريد'
                      : '${_emails.length} email addresses'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.gold),
                    onPressed: _addEmail,
                  ),
                ),
                if (_emails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _emails
                          .map((e) => Chip(
                                label:
                                    Text(e, style: const TextStyle(fontSize: 11)),
                                onDeleted: () => setState(() => _emails.remove(e)),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
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
// مُختار مُستَخدِمين
// ============================================================
class _UserPickerSheet extends StatefulWidget {
  final Set<String> initial;
  const _UserPickerSheet({required this.initial});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  late final Set<String> _selected = widget.initial.toSet();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final query = _filter.trim().toLowerCase();
    final users = repo.users.where((u) {
      if (query.isEmpty) return true;
      return u.fullName.toLowerCase().contains(query) ||
          u.username.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

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
                const Icon(Icons.people, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr ? 'اختَر المُستَلِمين' : 'Select recipients',
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
              itemCount: users.length,
              itemBuilder: (_, i) {
                final u = users[i];
                final isSel = _selected.contains(u.id);
                return CheckboxListTile(
                  value: isSel,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(u.id);
                      } else {
                        _selected.remove(u.id);
                      }
                    });
                  },
                  title: Text(u.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text('${u.username} · ${u.role.name}',
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
