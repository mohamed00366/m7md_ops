import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../features/auth/country_selector.dart';
import '../../repositories/mock_repository.dart';
import 'buses/bus_drivers_screen.dart';
import 'buses/bus_reports_screen.dart';
import 'buses/buses_list_screen.dart';
import 'buses/buses_shared.dart';
import 'camp_palette.dart';
import 'camp_boss_buses_weekly.dart';

/// 🚌 شاشة الباصات الرئيسية - تبويبات سفلية:
///   1. إدارة الباصات (CRUD)
///   2. الخطة الأسبوعية (الموجودة)
///   3. التقارير
class CampBossBuses extends StatefulWidget {
  const CampBossBuses({super.key});

  @override
  State<CampBossBuses> createState() => _CampBossBusesState();
}

class _CampBossBusesState extends State<CampBossBuses>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tab.dispose();
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

    if (auth.needsCountrySelection(repo)) {
      return _BusesCountryGate(
        accessibleCountryIds: auth.accessibleCountryIds(repo),
      );
    }

    return Column(children: [
      Container(
        decoration: const BoxDecoration(
          color: AppPalette.card,
          border: Border(
            bottom: BorderSide(color: AppPalette.border),
          ),
        ),
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: BusesPalette.primary,
          labelColor: BusesPalette.primary,
          unselectedLabelColor: AppPalette.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(
                icon: const Icon(Icons.directions_bus_outlined, size: 18),
                text: s.isAr ? 'الباصات' : 'Buses'),
            Tab(
                icon: const Icon(Icons.person_pin_outlined, size: 18),
                text: s.isAr ? 'السائقون' : 'Drivers'),
            Tab(
                icon: const Icon(Icons.calendar_view_week_outlined, size: 18),
                text: s.isAr ? 'الخطة' : 'Weekly'),
            Tab(
                icon: const Icon(Icons.analytics_outlined, size: 18),
                text: s.isAr ? 'تقارير' : 'Reports'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: const [
            BusesListScreen(),
            BusDriversScreen(),
            CampBossBusesWeekly(),
            BusReportsScreen(),
          ],
        ),
      ),
    ]);
  }
}

// ============================================================
// 🛡️ بوابة الدولة
// ============================================================
class _BusesCountryGate extends StatelessWidget {
  final List<String> accessibleCountryIds;
  const _BusesCountryGate({required this.accessibleCountryIds});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final countries = repo.countries
        .where((c) => accessibleCountryIds.contains(c.id))
        .toList();
    return SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: BusesPalette.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_bus,
                    size: 44, color: BusesPalette.primary),
              ),
              const SizedBox(height: 18),
              Text(
                  s.isAr ? 'اختر دولة للمتابعة' : 'Select a Country',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: CampPalette.text)),
              const SizedBox(height: 8),
              Text(
                s.isAr
                    ? 'حسابك يصل لأكثر من دولة. اختر الدولة التي تريد إدارة باصاتها.'
                    : 'Your account has access to multiple countries. Select the one to manage buses for.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: CampPalette.textSecondary),
              ),
              const SizedBox(height: 24),
              if (countries.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: CampPalette.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CampPalette.border),
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
                                    color: BusesPalette.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: countries[i].flagEmoji.isNotEmpty
                                      ? Text(countries[i].flagEmoji,
                                          style: const TextStyle(
                                              fontSize: 22))
                                      : Text(countries[i].code.toUpperCase(),
                                          style: const TextStyle(
                                              color: BusesPalette.primary,
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
                                        s.isAr
                                            ? countries[i].nameAr
                                            : countries[i].nameEn,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14),
                                      ),
                                      if (countries[i].code.isNotEmpty)
                                        Text(countries[i].code,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: CampPalette
                                                    .textSecondary)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: CampPalette.textTertiary),
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
                label: Text(s.isAr
                    ? 'فتح شاشة اختيار الدولة'
                    : 'Country Selector'),
              ),
            ],
          ),
        ),
    );
  }
}
