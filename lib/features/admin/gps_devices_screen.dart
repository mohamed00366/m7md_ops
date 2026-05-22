import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🛰 إدارة أَجهِزة GPS لِلباصات
///
/// يَعرِض كُلّ الباصات + طَريقة التَتَبُّع لِكُلّ منها (3 خِيارات):
///   - 📱 هاتِف السائِق
///   - 🛰 جِهاز GPS مُخَصَّص
///   - 📲 تابلت في الباص
///   - ⚪ بِدون
///
/// يَعرِض حالة الاتِّصال (آخِر إشارة) + يَسمَح بِتَغيير الإعداد
class GpsDevicesScreen extends StatefulWidget {
  const GpsDevicesScreen({super.key});

  @override
  State<GpsDevicesScreen> createState() => _GpsDevicesScreenState();
}

class _GpsDevicesScreenState extends State<GpsDevicesScreen> {
  bool _loading = false;
  List<Bus> _buses = [];
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService().isReady) {
        final rows = await SupabaseService().client
            .from('buses')
            .select()
            .order('name', ascending: true);
        // المُحَوَّل لِـBus model مُتَوَفِّر، لكِنّنا نَقرَأ مُباشَرَة لِأَنّ
        // الحُقول الجَديدة (tracking_method) لا تَكون في model.
        // نَستَخدِم Map<String, dynamic> داخِليّاً
        _busesRaw = (rows as List).cast<Map<String, dynamic>>();
        _buses = MockRepository().buses; // لا نَزال نَستَخدِم الـmodel لِلعَرض
      } else {
        _buses = MockRepository().buses;
        _busesRaw = [];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _busesRaw = [];

  Map<String, dynamic>? _rawFor(String busId) {
    for (final r in _busesRaw) {
      if (r['id'].toString() == busId) return r;
    }
    return null;
  }

  String _trackingMethod(Bus b) {
    final raw = _rawFor(b.id);
    return raw?['tracking_method']?.toString() ?? 'none';
  }

  String _deviceId(Bus b) {
    final raw = _rawFor(b.id);
    return raw?['gps_device_id']?.toString() ?? '';
  }

  DateTime? _lastPing(Bus b) {
    final raw = _rawFor(b.id);
    final v = raw?['last_ping_at'];
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _openEditor(Bus bus) async {
    final raw = _rawFor(bus.id);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GpsEditorScreen(bus: bus, current: raw ?? {}),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    // 🔐 فَحص الصَلاحيّة الدِفاعيّ
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isSuperAdmin ||
        auth.permissions.contains(P.settingsBusView);
    if (!canManage) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '🛰 أَجهِزة GPS' : '🛰 GPS Devices',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 56, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'لا تَملك صَلاحيّة إدارة أَجهِزة GPS'
                      : 'No permission to manage GPS devices',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filtered = _buses.where((b) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return b.name.toLowerCase().contains(q) ||
          b.plateNumber.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🛰 أَجهِزة GPS لِلباصات' : '🛰 Bus GPS Devices',
        subtitle:
            isAr ? '${_buses.length} باص' : '${_buses.length} buses',
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
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr ? 'بَحث بِالاسم أَو اللوحة…' : 'Search…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      isAr ? 'لا توجد باصات' : 'No buses',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final bus = filtered[i];
                      return _BusGpsCard(
                        bus: bus,
                        method: _trackingMethod(bus),
                        deviceId: _deviceId(bus),
                        lastPing: _lastPing(bus),
                        isAr: isAr,
                        onTap: () => _openEditor(bus),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// بِطاقة باص
// ============================================================================
class _BusGpsCard extends StatelessWidget {
  final Bus bus;
  final String method;
  final String deviceId;
  final DateTime? lastPing;
  final bool isAr;
  final VoidCallback onTap;

  const _BusGpsCard({
    required this.bus,
    required this.method,
    required this.deviceId,
    required this.lastPing,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final methodMeta = _MethodMeta.of(method);
    final status = _statusOf(method, lastPing);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // أَيقونة الطَريقة
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: methodMeta.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(methodMeta.icon, color: methodMeta.color),
              ),
              const SizedBox(width: 12),
              // مَعلومات
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚌 ${bus.name} · ${bus.plateNumber}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr ? methodMeta.labelAr : methodMeta.labelEn,
                      style: TextStyle(
                          fontSize: 11,
                          color: methodMeta.color,
                          fontWeight: FontWeight.w700),
                    ),
                    if (deviceId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ID: $deviceId',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // حالة الاتِّصال
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(status.icon, size: 10, color: status.color),
                        const SizedBox(width: 3),
                        Text(
                          isAr ? status.labelAr : status.labelEn,
                          style: TextStyle(
                            fontSize: 10,
                            color: status.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastPing == null
                        ? '—'
                        : _ago(lastPing!, isAr),
                    style: const TextStyle(
                        fontSize: 9, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _Status _statusOf(String method, DateTime? lastPing) {
    if (method == 'none') {
      return _Status(
        labelAr: 'بِدون',
        labelEn: 'None',
        icon: Icons.do_not_disturb,
        color: Colors.grey,
      );
    }
    if (lastPing == null) {
      return _Status(
        labelAr: 'لا إشارة',
        labelEn: 'No signal',
        icon: Icons.signal_cellular_off,
        color: AppColors.danger,
      );
    }
    final diff = DateTime.now().difference(lastPing);
    if (diff.inMinutes < 5) {
      return _Status(
        labelAr: 'مُتَّصِل',
        labelEn: 'Live',
        icon: Icons.circle,
        color: AppColors.success,
      );
    }
    if (diff.inHours < 24) {
      return _Status(
        labelAr: 'خامِل',
        labelEn: 'Idle',
        icon: Icons.access_time,
        color: AppColors.warning,
      );
    }
    return _Status(
      labelAr: 'مَفقود',
      labelEn: 'Lost',
      icon: Icons.warning,
      color: AppColors.danger,
    );
  }

  String _ago(DateTime t, bool isAr) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (d.inMinutes < 60) {
      return isAr ? 'قَبل ${d.inMinutes} د' : '${d.inMinutes}m ago';
    }
    if (d.inHours < 24) {
      return isAr ? 'قَبل ${d.inHours} س' : '${d.inHours}h ago';
    }
    return isAr ? 'قَبل ${d.inDays} يَوم' : '${d.inDays}d ago';
  }
}

class _MethodMeta {
  final IconData icon;
  final Color color;
  final String labelAr;
  final String labelEn;
  const _MethodMeta(
      {required this.icon,
      required this.color,
      required this.labelAr,
      required this.labelEn});

  static _MethodMeta of(String method) {
    switch (method) {
      case 'driver_phone':
        return const _MethodMeta(
          icon: Icons.phone_android,
          color: AppColors.info,
          labelAr: '📱 هاتِف السائِق',
          labelEn: '📱 Driver Phone',
        );
      case 'gps_device':
        return const _MethodMeta(
          icon: Icons.gps_fixed,
          color: AppColors.success,
          labelAr: '🛰 جِهاز GPS',
          labelEn: '🛰 GPS Device',
        );
      case 'tablet':
        return const _MethodMeta(
          icon: Icons.tablet_android,
          color: AppColors.purple,
          labelAr: '📲 تابلت في الباص',
          labelEn: '📲 Vehicle Tablet',
        );
      default:
        return const _MethodMeta(
          icon: Icons.location_disabled,
          color: Colors.grey,
          labelAr: '⚪ بِدون تَتَبُّع',
          labelEn: '⚪ No tracking',
        );
    }
  }
}

class _Status {
  final String labelAr;
  final String labelEn;
  final IconData icon;
  final Color color;
  _Status({
    required this.labelAr,
    required this.labelEn,
    required this.icon,
    required this.color,
  });
}

// ============================================================================
// شاشة تَعديل/ربط GPS لِباص
// ============================================================================
class _GpsEditorScreen extends StatefulWidget {
  final Bus bus;
  final Map<String, dynamic> current;
  const _GpsEditorScreen({required this.bus, required this.current});

  @override
  State<_GpsEditorScreen> createState() => _GpsEditorScreenState();
}

class _GpsEditorScreenState extends State<_GpsEditorScreen> {
  late String _method;
  final _deviceId = TextEditingController();
  final _deviceType = TextEditingController();
  final _sim = TextEditingController();
  final _tabletSerial = TextEditingController();
  final _notes = TextEditingController();
  bool _active = true;
  bool _saving = false;

  static const _deviceTypes = [
    'Concox GT06N',
    'Teltonika FMB920',
    'Queclink GV55',
    'Coban TK103',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _method = (c['tracking_method'] ?? 'none').toString();
    _deviceId.text = (c['gps_device_id'] ?? '').toString();
    _deviceType.text = (c['gps_device_type'] ?? '').toString();
    _sim.text = (c['sim_number'] ?? '').toString();
    _tabletSerial.text = (c['tablet_serial'] ?? '').toString();
    _notes.text = (c['tracking_notes'] ?? '').toString();
    _active = c['tracking_active'] == true;
  }

  @override
  void dispose() {
    _deviceId.dispose();
    _deviceType.dispose();
    _sim.dispose();
    _tabletSerial.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      final supa = SupabaseService();
      if (!supa.isReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase not ready')),
        );
        return;
      }

      final payload = <String, dynamic>{
        'tracking_method': _method,
        'tracking_active': _active && _method != 'none',
        'gps_device_id': _method == 'gps_device' ? _deviceId.text.trim() : null,
        'gps_device_type':
            _method == 'gps_device' ? _deviceType.text.trim() : null,
        'sim_number': _method == 'gps_device' ? _sim.text.trim() : null,
        'tablet_serial':
            _method == 'tablet' ? _tabletSerial.text.trim() : null,
        'tracking_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'tracking_installed_at': _method != 'none' ? DateTime.now().toIso8601String() : null,
      };

      await supa.client.from('buses').update(payload).eq('id', widget.bus.id);

      // سَجِّل التَغيير لِلتَدقيق
      await supa.client.from('bus_tracking_changes').insert({
        'bus_id': widget.bus.id,
        'old_method': widget.current['tracking_method'],
        'new_method': _method,
        'old_device_id': widget.current['gps_device_id'],
        'new_device_id': _method == 'gps_device' ? _deviceId.text.trim() : null,
        'changed_by': auth.currentUser?.id,
        'reason': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Error: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Text(
          '${widget.bus.name} · ${widget.bus.plateNumber}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: Text(isAr ? 'إلغاء' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(isAr ? 'حِفظ' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            isAr ? 'طَريقة التَتَبُّع' : 'Tracking Method',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _MethodTile(
            method: 'driver_phone',
            selected: _method == 'driver_phone',
            onTap: () => setState(() => _method = 'driver_phone'),
            isAr: isAr,
          ),
          _MethodTile(
            method: 'gps_device',
            selected: _method == 'gps_device',
            onTap: () => setState(() => _method = 'gps_device'),
            isAr: isAr,
          ),
          _MethodTile(
            method: 'tablet',
            selected: _method == 'tablet',
            onTap: () => setState(() => _method = 'tablet'),
            isAr: isAr,
          ),
          _MethodTile(
            method: 'none',
            selected: _method == 'none',
            onTap: () => setState(() => _method = 'none'),
            isAr: isAr,
          ),

          // الحُقول الخاصّة بِكُلّ طَريقة
          if (_method == 'gps_device') ...[
            const SizedBox(height: 16),
            const Divider(),
            Text(isAr ? 'تَفاصيل الجِهاز' : 'Device details',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _deviceTypes.contains(_deviceType.text)
                  ? _deviceType.text
                  : null,
              decoration: InputDecoration(
                labelText: isAr ? 'نَوع الجِهاز' : 'Device type',
                border: const OutlineInputBorder(),
              ),
              items: _deviceTypes
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _deviceType.text = v ?? ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deviceId,
              decoration: InputDecoration(
                labelText:
                    isAr ? 'IMEI / Device ID' : 'IMEI / Device ID',
                hintText: '864180048593214',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sim,
              decoration: InputDecoration(
                labelText:
                    isAr ? 'رَقَم شَريحة SIM' : 'SIM Number',
                hintText: '+971 50 123 4567',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (_method == 'tablet') ...[
            const SizedBox(height: 16),
            const Divider(),
            Text(isAr ? 'تَفاصيل التابلت' : 'Tablet details',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(
              controller: _tabletSerial,
              decoration: InputDecoration(
                labelText: isAr ? 'الرَقَم التَسَلسُليّ' : 'Serial number',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (_method == 'driver_phone') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.info),
                      const SizedBox(width: 6),
                      Text(
                        isAr ? 'كَيف يَعمَل؟' : 'How it works',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.info),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isAr
                        ? '• السائِق يَفتَح تَطبيق M7 على هاتِفه\n'
                            '• يُسَجِّل دُخوله — الـGPS إجباريّ\n'
                            '• الجَلسة تَستَمِرّ 24 ساعة بِدون إعادة دُخول\n'
                            '• الموقِع يُرسَل تلقائيّاً كُلّ 30 ثانية'
                        : '• Driver opens M7 app on their phone\n'
                            '• Logs in — GPS is required\n'
                            '• Session lasts 24h without re-login\n'
                            '• Location sent every 30 seconds',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          if (_method != 'none') ...[
            const SizedBox(height: 16),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(isAr ? 'التَتَبُّع نَشِط' : 'Tracking active'),
              subtitle: Text(
                isAr
                    ? 'إذا أَطفأَت → لَن يُسَجَّل أَيّ مَوقِع'
                    : 'If off → no locations will be recorded',
                style: const TextStyle(fontSize: 11),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: isAr ? 'مُلاحَظات' : 'Notes',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// بِطاقة اختيار طَريقة
// ============================================================================
class _MethodTile extends StatelessWidget {
  final String method;
  final bool selected;
  final VoidCallback onTap;
  final bool isAr;
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _MethodMeta.of(method);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected
            ? meta.color.withValues(alpha: 0.10)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? meta.color : Theme.of(context).dividerColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(meta.icon, color: meta.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAr ? meta.labelAr : meta.labelEn,
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: meta.color),
            ],
          ),
        ),
      ),
    );
  }
}
