import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../features/auth/country_selector.dart';
import '../../repositories/mock_repository.dart';
import 'camp_palette.dart';
import 'uniform/camp_awaiting_setup_screen.dart';
import 'uniform/uniform_catalog_screen.dart';
import 'uniform/uniform_issue_screen.dart';
import 'uniform/uniform_purchases_screen.dart';
import 'uniform/uniform_reports_screen.dart';
import 'uniform/uniform_requests_inbox_screen.dart';
import 'uniform/uniform_shared.dart';

/// 👕 شاشة اليونيفورم الرئيسية — موحّدة بنمط TabBar علوي
class CampBossUniform extends StatefulWidget {
  const CampBossUniform({super.key});

  @override
  State<CampBossUniform> createState() => _CampBossUniformState();
}

class _CampBossUniformState extends State<CampBossUniform>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
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
      return _UniformCountryGate(
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
          indicatorColor: UniformPalette.primary,
          labelColor: UniformPalette.primary,
          unselectedLabelColor: AppPalette.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            // 🆕 تابِ يَنتَظِرون التَجهيز
            Tab(
                icon: const Icon(Icons.hourglass_top, size: 18),
                text: s.isAr ? 'يَنتَظِرون التَجهيز' : 'Awaiting Setup'),
            // 🆕 تابِ الكاتالوج — مَع badge أَحمَر لِلأَصناف ذات مَخزون مُنخَفِض
            Tab(
              icon: Builder(builder: (_) {
                final repo = MockRepository();
                final lowCount = repo.uniformCatalog.where((u) {
                  final stock = repo.uniformCurrentStock(u.id);
                  return stock <= u.minStock;
                }).length;
                if (lowCount == 0) {
                  return const Icon(Icons.inventory_2_outlined, size: 18);
                }
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 18),
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        constraints: const BoxConstraints(minWidth: 14),
                        child: Text(
                          '$lowCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              text: s.isAr ? 'الكتالوج' : 'Catalog',
            ),
            // 🆕 تابِ فَواتير الاستِلام (مَشتَريات + كَمّيّات تِلقائيّاً)
            // — يَدعَم عِدّة بُنود في فاتورة واحِدة + رَقم تِلقائيّ REC-YYYY-####
            // (التابِ القَديم "استِلام" أُزيل لِأَنّ هَذا يَفعَل كُلّ شَيء أَفضَل)
            Tab(
                icon: const Icon(Icons.receipt_long, size: 18),
                text: s.isAr ? 'فَواتير الاستِلام' : 'Receipts'),
            // 🆕 تابِ استِقبال الطَلَبات — مِن نَموذَج UNIFORM-REQUEST بَعد الاعتِماد
            Tab(
                icon: const Icon(Icons.inbox_outlined, size: 18),
                text: s.isAr ? 'طَلَبات' : 'Requests'),
            Tab(
                icon: const Icon(Icons.handshake_outlined, size: 18),
                text: s.isAr ? 'صرف' : 'Issue'),
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
            CampAwaitingSetupScreen(),
            UniformCatalogScreen(),
            UniformPurchasesScreen(),
            UniformRequestsInboxScreen(),
            UniformIssueScreen(),
            UniformReportsScreen(),
          ],
        ),
      ),
    ]);
  }
}

class _UniformCountryGate extends StatelessWidget {
  final List<String> accessibleCountryIds;
  const _UniformCountryGate({required this.accessibleCountryIds});

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
                  color: UniformPalette.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.checkroom,
                    size: 44, color: UniformPalette.primary),
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
                    ? 'حسابك يصل لأكثر من دولة. اختر الدولة لإدارة اليونيفورم.'
                    : 'Your account has access to multiple countries. Select one to manage uniforms.',
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
                                    color: UniformPalette.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child:
                                      countries[i].flagEmoji.isNotEmpty
                                          ? Text(
                                              countries[i].flagEmoji,
                                              style: const TextStyle(
                                                  fontSize: 22))
                                          : Text(
                                              countries[i]
                                                  .code
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                  color: UniformPalette
                                                      .primary,
                                                  fontWeight:
                                                      FontWeight.w900,
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
