// =============================================================================
// 📊 لَوحة تَحَكُّم الكَمب بُوص — الشاشة الرَئيسيّة لِنِظام أَمانة
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../features/auth/country_selector.dart';
import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/laundry_strings.dart';
import 'direct_receive_screen.dart';
import 'pending_requests_screen.dart';
import 'active_vouchers_screen.dart';
import 'batches_screen.dart';
import 'laundry_reports_screen.dart';
import 'laundry_history_screen.dart';
import 'ready_to_deliver_screen.dart';
import 'schedule_settings_screen.dart';

class CampBossLaundryDashboard extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const CampBossLaundryDashboard({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<CampBossLaundryDashboard> createState() =>
      _CampBossLaundryDashboardState();
}

class _CampBossLaundryDashboardState extends State<CampBossLaundryDashboard> {
  int _pendingCount = 0;
  int _activeVouchers = 0;
  int _inLaundry = 0;
  int _readyToDeliver = 0;
  int _openReports = 0;
  bool _loading = true;

  // البَلَد الفِعليّ: مِن الـ widget أَوّلاً، ثُمَّ مِن AuthProvider
  String? get _country =>
      widget.countryId ??
      Provider.of<AuthProvider>(context, listen: false).activeCountryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_country == null) return;
    final ds = LaundryDataSource.instance;
    final results = await Future.wait([
      ds.listPendingRequests(countryId: _country),
      ds.listActiveVouchers(countryId: _country),
      ds.listBatches(countryId: _country, status: BatchStatus.inLaundry),
      ds.listReadyForDelivery(countryId: _country),
      ds.listReports(status: MissingReportStatus.open),
    ]);
    if (!mounted) return;
    setState(() {
      _pendingCount = (results[0] as List).length;
      _activeVouchers = (results[1] as List).length;
      _inLaundry = (results[2] as List).length;
      _readyToDeliver = (results[3] as List).length;
      _openReports = (results[4] as List).length;
      _loading = false;
    });
  }

  String? _lastCountryLoaded;

  @override
  Widget build(BuildContext context) {
    // 🚧 حارِس: البَلَد إجباريّ — نَراقِب AuthProvider هُنا لِيَتَجاوَب فَوراً
    final auth = context.watch<AuthProvider>();
    final effectiveCountry = widget.countryId ?? auth.activeCountryId;
    if (effectiveCountry == null || effectiveCountry.isEmpty) {
      return const _LaundryCountryGate();
    }
    // إن تَغَيَّر البَلَد، أَعِد التَحميل تِلقائيّاً
    if (_lastCountryLoaded != effectiveCountry) {
      _lastCountryLoaded = effectiveCountry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final L = LaundryStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('🧺 ${L.amana} — ${L.dashboard}'),
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ScheduleSettingsScreen(
                campBossId: widget.campBossId,
              ),
            )),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // KPIs 3x2 Grid (6 خَلايا)
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.0,
                    children: [
                      _kpi(L.requests, _pendingCount,
                          Icons.inbox, LaundryColors.statusPending),
                      _kpi(L.activeVouchers, _activeVouchers,
                          Icons.receipt_long, LaundryColors.statusConfirmed),
                      _kpi(L.inLaundry, _inLaundry,
                          Icons.local_laundry_service,
                          LaundryColors.statusInLaundry),
                      _kpi(L.readyToDeliver, _readyToDeliver,
                          Icons.handshake_outlined, LaundryColors.success),
                      _kpi(L.openReports, _openReports,
                          Icons.warning, LaundryColors.danger),
                      _kpi(L.history, 0,
                          Icons.history, LaundryColors.primary),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ⚡ زِرّ الاستِلام المُباشِر (الأَهَمّ)
                  _primaryCta(
                    icon: Icons.flash_on,
                    title: '⚡ ${L.directReceive}',
                    subtitle: L.directReceiveSub,
                    color: LaundryColors.success,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DirectReceiveSearchScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  _secondaryCta(
                    icon: Icons.inbox,
                    title: '📨 ${L.incomingRequests}',
                    subtitle: _pendingCount > 0
                        ? '$_pendingCount ${L.pendingRequestsHint}'
                        : L.noRequests,
                    badge: _pendingCount,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PendingRequestsScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  _secondaryCta(
                    icon: Icons.receipt_long,
                    title: '📋 ${L.activeVouchers}',
                    subtitle: '$_activeVouchers ${L.vouchersReady}',
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ActiveVouchersScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  _secondaryCta(
                    icon: Icons.local_shipping,
                    title: '📦 ${L.batchesSection}',
                    subtitle: '$_inLaundry ${L.batchesInLaundry}',
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BatchesScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  // 🟢 جَديد: السَنَدات الجاهِزة لِلتَسليم لِلمُوَظَّف
                  _secondaryCta(
                    icon: Icons.handshake_outlined,
                    title: '🤝 ${L.readyForEmployeeDelivery}',
                    subtitle: _readyToDeliver > 0
                        ? '$_readyToDeliver ${L.vouchersAwaitingDelivery}'
                        : L.noVoucherReady,
                    badge: _readyToDeliver,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReadyToDeliverScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  _secondaryCta(
                    icon: Icons.warning_amber,
                    title: '⚠️ ${L.missingReports}',
                    subtitle: _openReports > 0
                        ? '$_openReports ${L.openReportsCount}'
                        : L.noReports,
                    badge: _openReports,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LaundryReportsScreen(
                          campBossId: widget.campBossId,
                          countryId: _country,
                        ),
                      ));
                      _load();
                    },
                  ),
                  const SizedBox(height: 10),
                  _secondaryCta(
                    icon: Icons.history,
                    title: '📜 ${L.fullHistoryReports}',
                    subtitle: L.allVouchersStats,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LaundryHistoryScreen(
                        countryId: _country,
                      ),
                    )),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kpi(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text('$value',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _primaryCta({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white24,
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryCta({
    required IconData icon,
    required String title,
    required String subtitle,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Icon(icon, color: LaundryColors.primary, size: 28),
                  if (badge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: const BoxDecoration(
                          color: LaundryColors.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14)),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🚧 مُختار البَلَد لِنِظام أَمانة (يُحاكي مُختار موديول الزِيّ)
// =============================================================================
class _LaundryCountryGate extends StatelessWidget {
  const _LaundryCountryGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final accessibleIds = auth.countryIds;
    final countries = repo.countries
        .where((c) => auth.isSuperAdmin || accessibleIds.contains(c.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧺 المَغسلة (أَمانة)'),
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: LaundryColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_laundry_service,
                    size: 44, color: LaundryColors.primary),
              ),
              const SizedBox(height: 18),
              const Text(
                'اختَر دَولة لِلمُتابَعة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'نِظام "أَمانة" يَعمَل عَلى مُستَوى البَلَد. اختَر الدَولة لِإدارة المَغسلة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade700, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (countries.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.20)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < countries.length; i++) ...[
                        if (i > 0)
                          const Divider(
                              height: 1, indent: 16, endIndent: 16),
                        InkWell(
                          onTap: () {
                            context
                                .read<AuthProvider>()
                                .setActiveCountry(countries[i].id);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: LaundryColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: countries[i].flagEmoji.isNotEmpty
                                      ? Text(countries[i].flagEmoji,
                                          style: const TextStyle(
                                              fontSize: 22))
                                      : Text(
                                          countries[i].code.toUpperCase(),
                                          style: const TextStyle(
                                              color: LaundryColors.primary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        countries[i].nameAr,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14),
                                      ),
                                      if (countries[i].code.isNotEmpty)
                                        Text(countries[i].code,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_left,
                                    color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        const CountrySelectorScreen(isSwitch: true),
                  ));
                },
                icon: const Icon(Icons.public, size: 16),
                label: const Text('فَتح شاشة اختِيار الدَولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
