import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/device_session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 📱 شاشة إدارة جلسات الأجهزة
///
/// يستطيع المسؤول هنا أن:
///   • يرى كلّ الموظّفين الذين سجّلوا الدخول وأرقام أجهزتهم
///   • يحذف جلسة لتمكين موظّف من الدخول من جهاز آخر
///   • يفلتر بحسب: الكلّ / الفعّالة فقط / حساب معيّن
class AdminDeviceSessionsScreen extends StatefulWidget {
  const AdminDeviceSessionsScreen({super.key});

  @override
  State<AdminDeviceSessionsScreen> createState() =>
      _AdminDeviceSessionsScreenState();
}

class _AdminDeviceSessionsScreenState
    extends State<AdminDeviceSessionsScreen> {
  bool _onlyActive = true;
  bool _loading = false;
  String _query = '';
  List<DeviceSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final list = await DeviceSessionService.instance
        .listAll(onlyActive: _onlyActive);
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  List<DeviceSession> get _filtered {
    if (_query.trim().isEmpty) return _sessions;
    final q = _query.trim().toLowerCase();
    return _sessions.where((s) {
      return (s.accountUsername ?? '').toLowerCase().contains(q) ||
          (s.accountFullName ?? '').toLowerCase().contains(q) ||
          (s.deviceName ?? '').toLowerCase().contains(q) ||
          s.deviceId.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _deleteSession(DeviceSession s) async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'حذف الجلسة؟' : 'Delete session?'),
        content: Text(isAr
            ? 'سيتمكّن الموظّف من تسجيل الدخول من جهاز آخر بعد الحذف.\n\n${s.accountFullName ?? s.accountUsername ?? ''}\nالجهاز: ${s.displayDeviceLabel}'
            : 'After deletion, the employee can log in from another device.\n\n${s.accountFullName ?? s.accountUsername ?? ''}\nDevice: ${s.displayDeviceLabel}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: AppColors.danger,
                backgroundColor: AppColors.danger.withOpacity(0.1)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success =
        await DeviceSessionService.instance.deleteSession(s.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? (isAr ? '✓ حُذفت الجلسة' : '✓ Session deleted')
          : (isAr ? 'فشل الحذف' : 'Failed to delete')),
    ));
    if (success) _refresh();
  }

  Future<void> _revokeSession(DeviceSession s) async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await DeviceSessionService.instance.revokeSession(s.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (isAr ? '✓ عُطّلت الجلسة' : '✓ Session revoked')
          : (isAr ? 'فشل التعطيل' : 'Failed')),
    ));
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isSuperAdmin; // يحصرها على Super Admin

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'جلسات الأجهزة' : 'Device Sessions',
        subtitle: isAr
            ? 'جهاز واحد لكل موظّف'
            : 'One device per employee',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== شريط الفلترة =====
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: isAr
                          ? 'بحث: اسم، حساب، جهاز…'
                          : 'Search name, account, device…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    isAr ? 'الفعّالة فقط' : 'Active only',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _onlyActive,
                  onSelected: (v) {
                    setState(() => _onlyActive = v);
                    _refresh();
                  },
                ),
              ],
            ),
          ),

          // ===== KPI bar =====
          _StatsBar(sessions: _sessions),

          const Divider(height: 1),

          // ===== القائمة =====
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.devices_other,
                                size: 56,
                                color: Theme.of(context).disabledColor),
                            const SizedBox(height: 12),
                            Text(
                              isAr
                                  ? 'لا توجد جلسات'
                                  : 'No sessions found',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).disabledColor),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              12, 8, 12, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final session = _filtered[i];
                            return _SessionCard(
                              session: session,
                              isAr: isAr,
                              canManage: canManage,
                              onDelete: () => _deleteSession(session),
                              onRevoke: () => _revokeSession(session),
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

// ============================================================
// شريط KPI
// ============================================================
class _StatsBar extends StatelessWidget {
  final List<DeviceSession> sessions;
  const _StatsBar({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final active = sessions.where((s) => s.isActive).length;
    final inactive = sessions.length - active;
    final isAr =
        Directionality.of(context) == TextDirection.rtl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Kpi(
            label: isAr ? 'إجمالي' : 'Total',
            value: sessions.length.toString(),
            color: AppColors.brand,
            icon: Icons.devices,
          ),
          const SizedBox(width: 8),
          _Kpi(
            label: isAr ? 'فعّالة' : 'Active',
            value: active.toString(),
            color: AppColors.success,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(width: 8),
          _Kpi(
            label: isAr ? 'مُعطّلة' : 'Inactive',
            value: inactive.toString(),
            color: AppColors.textSecondaryLight,
            icon: Icons.do_not_disturb_on_outlined,
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Kpi({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: color.withOpacity(0.85),
                          fontWeight: FontWeight.w600)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 16,
                          color: color,
                          fontWeight: FontWeight.w900,
                          height: 1.1)),
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
// بطاقة جلسة
// ============================================================
class _SessionCard extends StatelessWidget {
  final DeviceSession session;
  final bool isAr;
  final bool canManage;
  final VoidCallback onDelete;
  final VoidCallback onRevoke;

  const _SessionCard({
    required this.session,
    required this.isAr,
    required this.canManage,
    required this.onDelete,
    required this.onRevoke,
  });

  IconData _platformIcon(String? p) {
    switch (p) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.desktop_windows;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.public;
      default:
        return Icons.devices_other;
    }
  }

  String _agoLabel(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) {
      return isAr ? 'منذ ${diff.inSeconds}ث' : '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return isAr ? 'منذ ${diff.inMinutes}د' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'منذ ${diff.inHours}س' : '${diff.inHours}h ago';
    }
    return isAr
        ? 'منذ ${diff.inDays}ي'
        : '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = session.isActive
        ? AppColors.success
        : AppColors.textSecondaryLight;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_platformIcon(session.platform),
                      color: c, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.accountFullName ??
                            session.accountUsername ??
                            (isAr ? 'موظّف' : 'Employee'),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (session.accountUsername != null)
                        Text(
                          '@${session.accountUsername}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _StatusChip(active: session.isActive, isAr: isAr),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // device line
            Row(
              children: [
                const Icon(Icons.devices, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    session.displayDeviceLabel,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      session.shortDeviceId,
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.login, size: 14),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'آخر دخول: ' : 'Last login: ',
                  style: const TextStyle(fontSize: 11),
                ),
                Expanded(
                  child: Text(
                    _agoLabel(session.lastLoginAt),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (session.appVersion != null)
                  Flexible(
                    child: Text(
                      'v${session.appVersion}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            if (!session.isActive &&
                session.deactivatedReason != null) ...[
              const SizedBox(height: 4),
              Text(
                isAr
                    ? '— عُطّلت: ${_reasonAr(session.deactivatedReason!)}'
                    : '— Reason: ${session.deactivatedReason}',
                style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color:
                        Theme.of(context).textTheme.bodySmall?.color),
              ),
            ],

            // ====== Admin actions ======
            if (canManage) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (session.isActive)
                    TextButton.icon(
                      onPressed: onRevoke,
                      icon: const Icon(Icons.block, size: 16),
                      label: Text(isAr ? 'تعطيل' : 'Revoke'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.warning),
                    ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(isAr ? 'حذف' : 'Delete'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _reasonAr(String r) {
    switch (r) {
      case 'replaced':
        return 'استُبدلت بجهاز جديد';
      case 'admin_revoked':
        return 'عطّلها المسؤول';
      case 'logout':
        return 'تسجيل خروج';
      default:
        return r;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;
  final bool isAr;
  const _StatusChip({required this.active, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.success : AppColors.textSecondaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            active
                ? (isAr ? 'فعّالة' : 'Active')
                : (isAr ? 'مُعطّلة' : 'Inactive'),
            style: TextStyle(
                color: c,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
