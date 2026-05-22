import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🎭 شاشة "العرض كحساب" (Impersonate Picker)
///
/// تُتيح للـ Super Admin اختيار حساب موظّف ورؤية التطبيق بصلاحيّاته بدون
/// كلمة سرّ. مفيدة لاختبار:
///   - أيّ شاشات يراها كلّ مسمّى وظيفيّ
///   - أيّ صلاحيّات ينقصها كل دور
///   - تجربة الموافقات قبل النشر
class ImpersonatePicker extends StatefulWidget {
  const ImpersonatePicker({super.key});

  @override
  State<ImpersonatePicker> createState() => _ImpersonatePickerState();
}

class _ImpersonatePickerState extends State<ImpersonatePicker> {
  String _query = '';
  String? _filterDashboard;

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
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final isAr = s.isAr;

    if (!auth.isSuperAdmin) {
      return Scaffold(
        appBar: M7AppBar(
            title: isAr ? '🎭 العَرض كَحِساب' : '🎭 Impersonate'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              isAr
                  ? '⚠️ هذه الشاشة متاحة لـ Super Admin فقط'
                  : '⚠️ This screen is for Super Admin only',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      );
    }

    // كل الحسابات التي لها employeeId (تستحقّ الاختبار)
    var accounts = repo.accounts.where((a) => a.id != auth.account?.id).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      accounts = accounts.where((a) {
        if (a.fullName.toLowerCase().contains(q)) return true;
        if (a.username.toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }
    if (_filterDashboard != null) {
      accounts = accounts.where((a) {
        if (a.employeeId == null) return false;
        final emp = repo.employeeById(a.employeeId);
        final jt = emp?.jobTitleId == null
            ? null
            : repo.jobTitleById(emp!.jobTitleId);
        return jt?.dashboardType.key == _filterDashboard;
      }).toList();
    }
    accounts.sort((a, b) => a.fullName.compareTo(b.fullName));

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🎭 العَرض كَحِساب' : '🎭 Impersonate',
      ),
      body: Column(
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_outlined,
                    color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? '⚠️ ميزة اختبار: ستنتقل إلى تجربة المستخدم بصلاحيّاته الكاملة. كلّ الإجراءات تُسجَّل.'
                        : '⚠️ Testing feature: You\'ll see the app as this user with their full permissions. All actions are audited.',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr ? 'بحث بالاسم...' : 'Search by name...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // Dashboard filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: isAr ? 'كل الـ Dashboards' : 'All',
                  selected: _filterDashboard == null,
                  onTap: () => setState(() => _filterDashboard = null),
                ),
                for (final t in DashboardType.values) ...[
                  const SizedBox(width: 4),
                  _filterChip(
                    label: t.label(isAr),
                    selected: _filterDashboard == t.key,
                    onTap: () => setState(() => _filterDashboard = t.key),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Text(
                      isAr ? 'لا توجد حسابات' : 'No accounts',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: accounts.length,
                    itemBuilder: (_, i) =>
                        _AccountRow(account: accounts[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final AppAccount account;
  const _AccountRow({required this.account});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final emp = account.employeeId == null
        ? null
        : repo.employeeById(account.employeeId);
    final jt = emp?.jobTitleId == null
        ? null
        : repo.jobTitleById(emp!.jobTitleId);
    final color = _hexToColor(jt?.color) ?? AppColors.brand;
    final permsCount = repo
        .rolesOfAccount(account.id)
        .fold<int>(0, (sum, r) => sum + repo.permissionKeysForRole(r.id).length);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            account.fullName.isEmpty
                ? '?'
                : account.fullName[0].toUpperCase(),
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          account.fullName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '@${account.username}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (jt != null)
                  _badge(jt.displayName(isAr), color),
                if (jt != null && jt.level > 0)
                  _badge('L${jt.level}', Colors.indigo),
                if (jt != null)
                  _badge(jt.dashboardType.label(isAr), Colors.teal),
                if (permsCount > 0)
                  _badge(
                      isAr ? '$permsCount صلاحية' : '$permsCount perms',
                      Colors.green),
                if (account.isSuperAdmin)
                  _badge('Super Admin', Colors.red),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: const Icon(Icons.visibility_outlined, size: 14),
          label: Text(
            isAr ? 'تجربة' : 'Try',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          onPressed: () => _confirmStart(context),
        ),
      ),
    );
  }

  Future<void> _confirmStart(BuildContext context) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '🎭 العرض كحساب' : '🎭 Impersonate'),
        content: Text(
          isAr
              ? 'سترى التطبيق بصلاحيّات ${account.fullName} كاملةً.\nيمكنك الخروج بأيّ وقت من الشريط الأحمر أعلى الشاشة.'
              : 'You\'ll see the app with ${account.fullName}\'s full permissions.\nYou can exit anytime from the red banner.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    auth.startImpersonate(account.id);
    if (!context.mounted) return;
    // 🆕 ارجِع لِشاشة الجَذر — الآن سَيَرى المُستَخدِم تَطبيق الحِساب المُحاكى
    // بَدَلاً من شاشة "محاكاة الحسابات" التي ستَحجِبه (Super Admin only)
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
