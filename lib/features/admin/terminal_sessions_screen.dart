import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/point_terminal_session_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🖥 شاشة "أَجهِزة نِقاط الدَوام"
///
/// تَعرِض لِكُلّ نُقطة فيها حِساب Terminal:
///   - حالة الرَبط (مَربوط بِجِهاز / لا)
///   - مَعرّف الجِهاز المَربوط
///   - الجَلسة الحاليّة النَشطة (إذا وُجِدَت)
///   - آخِر دُخول وَآخِر نَشاط
///   - أَزرار: فَكّ رَبط الجِهاز / إنهاء الجَلسة
class TerminalSessionsScreen extends StatefulWidget {
  const TerminalSessionsScreen({super.key});

  @override
  State<TerminalSessionsScreen> createState() =>
      _TerminalSessionsScreenState();
}

class _TerminalSessionsScreenState extends State<TerminalSessionsScreen> {
  bool _loading = true;
  // 🆕 جَميع الجَلسات النَشطة مَجموعة حَسَب الحِساب (دَعم تَعَدُّد الأَجهِزة)
  Map<String, List<TerminalSession>> _sessionsByAccount = {};
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PointTerminalSessionService.instance
          .listAll(onlyActive: true);
      final map = <String, List<TerminalSession>>{};
      for (final s in list) {
        map.putIfAbsent(s.accountId, () => []).add(s);
      }
      _sessionsByAccount = map;
    } catch (e) {
      M7Log.error('TerminalDevices', 'load', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unlinkDevice(AppAccount acc) async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? 'فَكّ رَبط الجِهاز' : 'Unlink Device'),
        content: Text(isAr
            ? 'سَيُمسَح linked_device_id من الحِساب وَتُلغى الجَلسة الحاليّة. يُمكِن لِأَيّ جِهاز جَديد تَسجيل الدُخول بَعدَ ذلك.'
            : 'linked_device_id will be cleared and current session will be revoked. Any new device can sign in after that.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: Text(isAr ? 'فَكّ الرَبط' : 'Unlink')),
        ],
      ),
    );
    if (ok != true) return;
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      // ١) أَلغِ الجَلسة الحاليّة إن وُجِدَت
      await supa.client
          .from('point_terminal_sessions')
          .update({
            'is_active': false,
            'deactivated_at': DateTime.now().toIso8601String(),
            'deactivated_reason': 'admin_unlinked',
          })
          .eq('account_id', acc.id)
          .eq('is_active', true);
      // ٢) امسَح linked_device_id
      await supa.client
          .from('accounts')
          .update({'linked_device_id': null}).eq('id', acc.id);
      // ٣) حَدِّث الذاكِرة
      acc.linkedDeviceId = null;
      MockRepository().notifyListeners();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
            isAr ? '✅ تَمَّ فَكّ الرَبط' : '✅ Device unlinked'),
      ));
      await _load();
    } catch (e) {
      M7Log.error('TerminalDevices', 'unlink', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('$e'),
      ));
    }
  }

  Future<void> _revokeSession(TerminalSession s) async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? 'إنهاء الجَلسة' : 'End Session'),
        content: Text(isAr
            ? 'سَيَتِم تَسجيل خُروج الجِهاز فَوراً. الجِهاز يَبقى مَربوطاً بِالنُقطة وَيُمكِنه إعادة الدُخول.'
            : 'The terminal will be logged out immediately. The device remains linked and can sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: Text(isAr ? 'إنهاء' : 'End')),
        ],
      ),
    );
    if (ok != true) return;
    final success = await PointTerminalSessionService.instance
        .revokeSession(s.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          success ? AppColors.success : AppColors.danger,
      content: Text(success
          ? (isAr ? '✅ تَمَّ إنهاء الجَلسة' : '✅ Session ended')
          : (isAr ? 'فَشِل' : 'Failed')),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    // 🆕 صَلاحيّة الإدارة (revoke / unlink) — مُنفَصِلة عَن صَلاحيّة العَرض
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isSuperAdmin ||
        auth.permissions.contains(P.pointTerminalManage);

    // ابني قائِمة المَدخَلات: لِكُلّ حِساب Terminal، اعرِض نُقطَتَه
    final terminalAccounts = repo.accounts
        .where((a) => a.accountType == AccountType.pointTerminal)
        .toList();

    // فَلتَر بَحث
    final query = _filter.trim().toLowerCase();
    final filtered = terminalAccounts.where((a) {
      if (query.isEmpty) return true;
      final point = a.pointId == null
          ? null
          : repo.pointById(a.pointId);
      return a.username.toLowerCase().contains(query) ||
          (point?.name.toLowerCase().contains(query) ?? false) ||
          (point?.code.toLowerCase().contains(query) ?? false);
    }).toList();

    // إحصاءات سَريعة
    final linkedCount =
        filtered.where((a) => a.linkedDeviceId != null).length;
    final activeCount = filtered
        .where((a) => (_sessionsByAccount[a.id]?.isNotEmpty ?? false))
        .length;

    return Scaffold(
      appBar: M7AppBar(
        title:
            isAr ? 'أَجهِزة نِقاط الدَوام' : 'Terminal Devices',
        subtitle: isAr
            ? '$linkedCount مَربوط · $activeCount نَشِط'
            : '$linkedCount linked · $activeCount active',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // شَريط البَحث
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr
                    ? 'ابحَث بِالنُقطة أَو اسم المُستَخدِم…'
                    : 'Search by point or username…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.computer,
                            size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          isAr
                              ? 'لا حِسابات Terminal'
                              : 'No terminal accounts',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isAr
                              ? 'أَنشِئ حِساب Terminal من شاشة Points'
                              : 'Create one from Points screen',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final acc = filtered[i];
                        final point = acc.pointId == null
                            ? null
                            : repo.pointById(acc.pointId);
                        return _DeviceCard(
                          account: acc,
                          point: point,
                          sessions: _sessionsByAccount[acc.id] ?? const [],
                          canManage: canManage,
                          onUnlinkAll: !canManage
                              ? null
                              : () => _unlinkDevice(acc),
                          onRevoke: !canManage
                              ? null
                              : (s) => _revokeSession(s),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final AppAccount account;
  final Point? point;
  final List<TerminalSession> sessions;
  final bool canManage;
  final VoidCallback? onUnlinkAll;
  final void Function(TerminalSession)? onRevoke;
  const _DeviceCard({
    required this.account,
    required this.point,
    required this.sessions,
    required this.canManage,
    required this.onUnlinkAll,
    required this.onRevoke,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _idleLabel(bool isAr, DateTime? lastSeen) {
    if (lastSeen == null) return '—';
    final mins = DateTime.now().difference(lastSeen).inMinutes;
    if (mins < 1) return isAr ? 'الآن' : 'now';
    if (mins < 60) {
      return isAr ? 'قَبل $mins د' : '$mins m ago';
    }
    final h = (mins / 60).floor();
    return isAr ? 'قَبل $h س' : '$h h ago';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final activeCount = sessions.length;
    final max = account.maxDevices;
    final hasAny = activeCount > 0 ||
        (account.linkedDeviceId != null &&
            account.linkedDeviceId!.isNotEmpty);
    final headerColor = activeCount > 0
        ? AppColors.success
        : hasAny
            ? AppColors.gold
            : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerColor.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== Header: النُقطة + عَدّاد الأَجهِزة =====
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront,
                    color: AppColors.gold, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(point?.name ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15)),
                    Text(
                      '${point?.code ?? ""} · ${account.username}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              // ===== شارة "X / Y" =====
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: headerColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  max == 0
                      ? '$activeCount / ∞'
                      : '$activeCount / $max',
                  style: TextStyle(
                    color: headerColor,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? (max == 0
                    ? '$activeCount جِهاز نَشِط · بِدون حَدّ'
                    : '$activeCount مِن $max جِهاز نَشِط')
                : (max == 0
                    ? '$activeCount active · unlimited'
                    : '$activeCount of $max active'),
            style: const TextStyle(
                fontSize: 10, color: Colors.grey),
          ),
          if (sessions.isEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_empty,
                      color: Colors.grey, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr
                          ? hasAny
                              ? 'الجِهاز السابِق مَفصول — بِانتِظار دُخول جَديد'
                              : 'لم يَدخُل أَيّ جِهاز بَعد'
                          : hasAny
                              ? 'Previous device disconnected — waiting for new login'
                              : 'No device has logged in yet',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ...sessions.map((s) => _SessionRow(
                  session: s,
                  fmt: _fmt,
                  idleLabel: _idleLabel,
                  onRevoke: onRevoke == null ? null : () => onRevoke!(s),
                )),
          ],
          if (canManage && hasAny) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onUnlinkAll,
                icon: const Icon(Icons.link_off, size: 16),
                label: Text(isAr
                    ? '🔗 فَكّ رَبط كُلّ الأَجهِزة'
                    : '🔗 Unlink All Devices'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.warning),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v,
      {required IconData icon, Color color = Colors.grey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SelectableText(v,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _kvSmall(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

/// 🆕 صَفّ جَلسة واحِدة (داخِل بِطاقة النُقطة)
class _SessionRow extends StatelessWidget {
  final TerminalSession session;
  final String Function(DateTime?) fmt;
  final String Function(bool isAr, DateTime? lastSeen) idleLabel;
  final VoidCallback? onRevoke;
  const _SessionRow({
    required this.session,
    required this.fmt,
    required this.idleLabel,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final label =
        (session.deviceLabel?.trim().isNotEmpty ?? false)
            ? session.deviceLabel!
            : (isAr ? 'جِهاز بِدون اسم' : 'Unnamed device');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tablet_mac,
                color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${session.platform ?? "?"} · ${idleLabel(isAr, session.lastSeenAt)}',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey),
                ),
                Text(
                  '${isAr ? "بَدَأَت" : "Started"}: ${fmt(session.firstLoginAt)}',
                  style: const TextStyle(
                      fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            IconButton(
              onPressed: onRevoke,
              icon: const Icon(Icons.logout,
                  color: AppColors.danger, size: 18),
              tooltip: isAr ? 'إنهاء الجَلسة' : 'End session',
            ),
        ],
      ),
    );
  }
}
