import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 📢 شاشة إرسال إشعارات يدويّة (Session 19)
///
/// تتيح للمسؤول إرسال إشعار مخصّص إلى:
///   - موظّف محدّد
///   - كلّ من يحمل مسمّى وظيفياً معيّناً
///   - كلّ موظفي قسم
///   - الجميع (في الدولة الحالية)
///
/// مفيدة لـ:
///   - إعلانات الشركة
///   - تذكير بمواعيد
///   - تنبيهات طوارئ
///   - رسائل ترحيب
class NotificationSenderScreen extends StatefulWidget {
  const NotificationSenderScreen({super.key});

  @override
  State<NotificationSenderScreen> createState() =>
      _NotificationSenderScreenState();
}

enum _Target { specificEmp, byJobTitle, byDept, all }

class _NotificationSenderScreenState extends State<NotificationSenderScreen> {
  _Target _target = _Target.byJobTitle;
  String? _targetId; // employee or jobtitle or department
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// حساب عدد المستلمين بناءً على الهدف الحالي
  int _recipientsCount() {
    final repo = MockRepository();
    switch (_target) {
      case _Target.specificEmp:
        return _targetId == null ? 0 : 1;
      case _Target.byJobTitle:
        if (_targetId == null) return 0;
        return repo.employees.where((e) => e.jobTitleId == _targetId).length;
      case _Target.byDept:
        if (_targetId == null) return 0;
        return repo.employees
            .where((e) => e.departmentId == _targetId)
            .length;
      case _Target.all:
        return repo.employees.length;
    }
  }

  Future<void> _send() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(
          isAr ? 'العنوان والمحتوى مطلوبان' : 'Title and body required',
        ),
      ));
      return;
    }

    if (_target != _Target.all && _targetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(isAr ? 'اختر الهدف أولاً' : 'Pick target first'),
      ));
      return;
    }

    final count = _recipientsCount();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '📢 تأكيد الإرسال' : '📢 Confirm Send'),
        content: Text(
          isAr
              ? 'سيتمّ إرسال هذا الإشعار إلى $count مستلم.'
              : 'This will send to $count recipient(s).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'إرسال' : 'Send'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final targets = _resolveTargets(repo);
    var sent = 0;
    for (final emp in targets) {
      final acc = repo.accountForEmployee(emp.id);
      if (acc == null) continue;
      repo.addNotification(AppNotification(
        id: repo.generateId(),
        userId: acc.id,
        employeeId: emp.id,
        type: AppNotificationType.generic,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
      ));
      sent++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
        isAr ? '✅ تمّ الإرسال إلى $sent مستلم' : '✅ Sent to $sent recipients',
      ),
    ));
    setState(() {
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _targetId = null;
    });
  }

  List<Employee> _resolveTargets(MockRepository repo) {
    switch (_target) {
      case _Target.specificEmp:
        if (_targetId == null) return [];
        final emp = repo.employeeById(_targetId);
        return emp == null ? [] : [emp];
      case _Target.byJobTitle:
        if (_targetId == null) return [];
        return repo.employees.where((e) => e.jobTitleId == _targetId).toList();
      case _Target.byDept:
        if (_targetId == null) return [];
        return repo.employees
            .where((e) => e.departmentId == _targetId)
            .toList();
      case _Target.all:
        return repo.employees;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final count = _recipientsCount();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Header banner =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brand.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined,
                    color: AppColors.brand, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'إرسال إشعار' : 'Send Notification',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAr
                            ? 'سيظهر فوراً في جرس الإشعارات للمستلمين'
                            : 'Appears instantly in recipients\' bell',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== Target selection =====
          Text(
            isAr ? '🎯 المستلم' : '🎯 Recipient',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _targetTypeChips(isAr),
          const SizedBox(height: 12),
          _targetPicker(isAr),
          const SizedBox(height: 16),

          // ===== Message =====
          Text(
            isAr ? '✉️ الرسالة' : '✉️ Message',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: isAr ? 'العنوان' : 'Title',
              prefixIcon: const Icon(Icons.title, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: isAr ? 'المحتوى' : 'Body',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===== Preview =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview, color: AppColors.info, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isAr ? 'معاينة' : 'Preview',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.info),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: count > 0 ? AppColors.success : Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isAr ? '$count مستلم' : '$count recipient(s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_outlined,
                            color: AppColors.brand, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titleCtrl.text.isEmpty
                                  ? (isAr ? 'العنوان...' : 'Title...')
                                  : _titleCtrl.text,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: _titleCtrl.text.isEmpty
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _bodyCtrl.text.isEmpty
                                  ? (isAr ? 'المحتوى...' : 'Body...')
                                  : _bodyCtrl.text,
                              style: TextStyle(
                                fontSize: 11,
                                color: _bodyCtrl.text.isEmpty
                                    ? Colors.grey
                                    : Colors.grey[800],
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== Send button =====
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: count > 0 ? _send : null,
              icon: const Icon(Icons.send, size: 18),
              label: Text(
                isAr
                    ? 'إرسال إلى $count مستلم'
                    : 'Send to $count recipient(s)',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _targetTypeChips(bool isAr) {
    final options = <_Target, MapEntry<IconData, String>>{
      _Target.specificEmp: MapEntry(
          Icons.person_outline, isAr ? 'موظف محدّد' : 'Specific Employee'),
      _Target.byJobTitle: MapEntry(
          Icons.badge_outlined, isAr ? 'حسب المسمّى' : 'By Job Title'),
      _Target.byDept: MapEntry(
          Icons.apartment_outlined, isAr ? 'حسب القسم' : 'By Department'),
      _Target.all:
          MapEntry(Icons.groups_outlined, isAr ? 'الجميع' : 'Everyone'),
    };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.entries.map((entry) {
        final selected = _target == entry.key;
        return InkWell(
          onTap: () => setState(() {
            _target = entry.key;
            _targetId = null;
          }),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand
                  : Colors.grey.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppColors.brand
                    : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.value.key,
                    size: 14,
                    color: selected ? Colors.white : Colors.grey[800]),
                const SizedBox(width: 4),
                Text(
                  entry.value.value,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.grey[800],
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _targetPicker(bool isAr) {
    final repo = MockRepository();
    if (_target == _Target.all) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined,
                color: AppColors.warning, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isAr
                    ? 'سيُرسل لكل ${repo.employees.length} موظف. تأكّد قبل الإرسال.'
                    : 'Will send to all ${repo.employees.length} employees. Confirm before sending.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    final items = <MapEntry<String, String>>[];
    switch (_target) {
      case _Target.specificEmp:
        for (final e in repo.employees) {
          items.add(MapEntry(e.id, '${e.fullName} (${e.code})'));
        }
        break;
      case _Target.byJobTitle:
        for (final j in repo.jobTitles) {
          final count =
              repo.employees.where((e) => e.jobTitleId == j.id).length;
          items.add(
              MapEntry(j.id, '${j.displayName(isAr)} ($count)'));
        }
        break;
      case _Target.byDept:
        for (final d in repo.departments) {
          final count =
              repo.employees.where((e) => e.departmentId == d.id).length;
          items.add(
              MapEntry(d.id, '${d.displayName(isAr)} ($count)'));
        }
        break;
      case _Target.all:
        break;
    }
    items.sort((a, b) => a.value.compareTo(b.value));

    return DropdownButtonFormField<String>(
      value: _targetId,
      decoration: InputDecoration(
        labelText: _target == _Target.specificEmp
            ? (isAr ? 'الموظف' : 'Employee')
            : _target == _Target.byJobTitle
                ? (isAr ? 'المسمّى' : 'Job Title')
                : (isAr ? 'القسم' : 'Department'),
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() => _targetId = v),
    );
  }
}
