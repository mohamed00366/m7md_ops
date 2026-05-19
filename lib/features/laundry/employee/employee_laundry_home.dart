// =============================================================================
// 🏠 شاشة المَغسلة الرَئيسيّة لِلمُوَظَّف
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../features/auth/country_selector.dart';
import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/availability_banner.dart';
import '../shared/laundry_colors.dart';
import '../shared/status_badge.dart';
import '../shared/voucher_detail_screen.dart';
import 'new_request_screen.dart';

class EmployeeLaundryHome extends StatefulWidget {
  final String employeeId;
  final String? countryId;
  final String? defaultCampBossId;

  const EmployeeLaundryHome({
    super.key,
    required this.employeeId,
    this.countryId,
    this.defaultCampBossId,
  });

  @override
  State<EmployeeLaundryHome> createState() => _EmployeeLaundryHomeState();
}

class _EmployeeLaundryHomeState extends State<EmployeeLaundryHome> {
  List<LaundryRequest> _requests = [];
  List<LaundryVoucher> _vouchers = [];
  List<MissingReport> _reports = [];
  Map<String, ClothingType> _types = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = LaundryDataSource.instance;
    final results = await Future.wait([
      ds.listRequestsForEmployee(widget.employeeId),
      ds.listVouchersForEmployee(widget.employeeId),
      ds.listReports(employeeId: widget.employeeId),
      ds.loadClothingTypes(),
    ]);
    if (!mounted) return;
    setState(() {
      _requests = results[0] as List<LaundryRequest>;
      _vouchers = results[1] as List<LaundryVoucher>;
      _reports = results[2] as List<MissingReport>;
      _types = {
        for (final t in (results[3] as List<ClothingType>)) t.id: t,
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🚧 حارِس: البَلَد إجباريّ — مَع مُختار جَميل
    final auth = context.watch<AuthProvider>();
    final effectiveCountry = widget.countryId ?? auth.activeCountryId;
    if (effectiveCountry == null || effectiveCountry.isEmpty) {
      return _EmployeeLaundryCountryGate();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧺 المَغسلة'),
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (widget.defaultCampBossId != null)
                    AvailabilityBanner(
                      campBossId: widget.defaultCampBossId!,
                      mode: 'receive',
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _newRequestButton(),
                  ),
                  _activeRequestsSection(),
                  _inLaundrySection(),
                  _readySection(),
                  _activeReportsSection(),
                  const SizedBox(height: 60),
                ],
              ),
            ),
    );
  }

  Widget _newRequestButton() {
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: LaundryColors.primary,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => NewLaundryRequestScreen(
                employeeId: widget.employeeId,
                countryId: widget.countryId,
              ),
            ),
          );
          if (ok == true) _load();
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.white, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طَلَب تَسليم جَديد',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('أَضِف قِطَع المَلابِس لِلكَمب بُوص',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  // ===== أَقسام الشاشة =====
  Widget _activeRequestsSection() {
    final active = _requests.where((r) => r.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return _section(
      icon: Icons.hourglass_top,
      title: 'طَلَب بانتِظار التَأكيد',
      color: LaundryColors.statusPending,
      children: active.map(_requestCard).toList(),
    );
  }

  Widget _inLaundrySection() {
    final inLaundry = _vouchers
        .where((v) => v.status == VoucherStatus.inLaundry)
        .toList();
    if (inLaundry.isEmpty) return const SizedBox.shrink();
    return _section(
      icon: Icons.local_laundry_service,
      title: 'في المَغسلة',
      color: LaundryColors.statusInLaundry,
      children: inLaundry.map(_voucherCard).toList(),
    );
  }

  Widget _readySection() {
    final ready = _vouchers
        .where((v) =>
            v.status == VoucherStatus.returnedComplete ||
            v.status == VoucherStatus.returnedWithMissing)
        .toList();
    if (ready.isEmpty) return const SizedBox.shrink();
    return _section(
      icon: Icons.check_circle,
      title: 'جاهِز لِلاستِلام',
      color: LaundryColors.success,
      children: ready.map(_voucherCard).toList(),
    );
  }

  Widget _activeReportsSection() {
    final open = _reports
        .where((r) =>
            r.status == MissingReportStatus.open ||
            r.status == MissingReportStatus.underReview)
        .toList();
    if (open.isEmpty) return const SizedBox.shrink();
    return _section(
      icon: Icons.warning,
      title: 'بَلاغات نَشطة',
      color: LaundryColors.danger,
      children: open.map(_reportCard).toList(),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _requestCard(LaundryRequest r) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LaundryStatusBadge.forRequest(r.status),
                const Spacer(),
                Text(r.requestNumber,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              r.items
                  .map((i) =>
                      '${_types[i.clothingTypeId]?.nameAr ?? "?"} × ${i.requestedQty}')
                  .join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voucherCard(LaundryVoucher v) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VoucherDetailScreen(voucher: v),
        )),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LaundryStatusBadge.forVoucher(v.status),
                const Spacer(),
                Text(v.voucherNumber,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.inventory_2,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text('${v.totalItems} قِطعة',
                    style: const TextStyle(fontSize: 12)),
                if (v.totalMissing > 0) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.warning,
                      size: 14, color: LaundryColors.danger),
                  const SizedBox(width: 4),
                  Text('مَفقود ${v.totalMissing}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: LaundryColors.danger,
                          fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _reportCard(MissingReport r) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            LaundryStatusBadge.forReport(r.status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'بَلاغ ${r.reportNumber} · ${r.totalMissingItems} قِطعة مَفقودة',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 🚧 مُختار البَلَد لِشاشة المَغسلة لِلمُوَظَّف
// =============================================================================
class _EmployeeLaundryCountryGate extends StatelessWidget {
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
        title: const Text('🧺 مَغسَلَتي (أَمانة)'),
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
                  color: LaundryColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_laundry_service,
                    size: 44, color: LaundryColors.primary),
              ),
              const SizedBox(height: 18),
              const Text(
                'اختَر دَولة لِلمُتابَعة',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'حِسابك يَصِل لِأَكثَر مِن دَولة. اختَر الدَولة لِفَتح مَغسَلَتك.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              if (countries.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.grey.withOpacity(0.20)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < countries.length; i++) ...[
                        if (i > 0)
                          const Divider(
                              height: 1, indent: 16, endIndent: 16),
                        InkWell(
                          onTap: () => context
                              .read<AuthProvider>()
                              .setActiveCountry(countries[i].id),
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
                                        .withOpacity(0.12),
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
                                      Text(countries[i].nameAr,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14)),
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const CountrySelectorScreen(isSwitch: true),
                  ),
                ),
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
