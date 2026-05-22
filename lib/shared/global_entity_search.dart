import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../features/admin/account_report_screen.dart';
import '../features/admin/employee_profile_hub.dart';
import '../features/camp_boss/buses/bus_hub.dart';
import '../features/manager/customers/master_report_screen.dart';
import '../features/manager/customers/point_hub.dart';
import '../features/manager/customers/site_hub.dart';
import '../repositories/mock_repository.dart';

/// 🔍 بَحث عام عَبر كُلّ الكِيانات في النِظام
///
/// يَبحَث في: مُوظَّفون، باصات، Masters، فُروع، نُقاط، حِسابات.
/// كُلّ نَتيجة تَفتَح Hub الكِيان المُناسِب مُباشَرة.
class GlobalEntitySearch extends SearchDelegate<void> {
  GlobalEntitySearch({required this.isAr})
      : super(searchFieldLabel: isAr ? 'ابحَث عَبر النِظام...' : 'Search…');

  final bool isAr;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (query.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search,
                  size: 48, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? 'اكتُب حَرفَين أَو أَكثَر لِلبَحث'
                    : 'Type 2+ chars to search',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'مُوظَّفون · باصات · عُملاء · فُروع · نُقاط · حِسابات'
                    : 'Employees · Buses · Masters · Sites · Points · Accounts',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }
    final q = query.toLowerCase();
    final repo = MockRepository();
    final results = <_SearchResult>[];

    // Employees
    for (final e in repo.employees) {
      if (e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q) ||
          e.mobile.contains(q) ||
          e.email.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          icon: Icons.person,
          color: AppColors.brand,
          typeAr: 'مُوظَّف',
          typeEn: 'Employee',
          title: e.fullName,
          subtitle: e.code,
          onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => EmployeeProfileHub(employee: e))),
        ));
      }
    }
    // Buses
    for (final b in repo.buses) {
      if (b.name.toLowerCase().contains(q) ||
          (b.displayName?.toLowerCase().contains(q) ?? false) ||
          b.plateNumber.toLowerCase().contains(q) ||
          b.model.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          icon: Icons.directions_bus,
          color: AppColors.info,
          typeAr: 'باص',
          typeEn: 'Bus',
          title: b.shownLabel,
          subtitle: b.plateNumber,
          onTap: (ctx) => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => BusHub(bus: b))),
        ));
      }
    }
    // Masters
    for (final m in repo.masters) {
      if (m.name.toLowerCase().contains(q) ||
          m.code.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          icon: Icons.business,
          color: AppColors.gold,
          typeAr: 'اسم تِجاريّ',
          typeEn: 'Master',
          title: m.name,
          subtitle: m.code,
          onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => MasterReportScreen(master: m))),
        ));
      }
    }
    // Sites
    for (final s in repo.sites) {
      if (s.companyName.toLowerCase().contains(q) ||
          s.shortName.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          icon: Icons.storefront,
          color: AppColors.success,
          typeAr: 'فَرع',
          typeEn: 'Site',
          title: s.companyName,
          subtitle: s.shortName,
          onTap: (ctx) => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => SiteHub(site: s))),
        ));
      }
    }
    // Points
    for (final p in repo.points) {
      if (p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          icon: Icons.place,
          color: AppColors.warning,
          typeAr: 'نُقطة',
          typeEn: 'Point',
          title: p.name,
          subtitle: p.code,
          onTap: (ctx) => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => PointHub(point: p))),
        ));
      }
    }
    // Accounts
    for (final a in repo.accounts) {
      if (a.fullName.toLowerCase().contains(q) ||
          a.username.toLowerCase().contains(q) ||
          (a.email?.toLowerCase().contains(q) ?? false)) {
        results.add(_SearchResult(
          icon: Icons.account_circle,
          color: AppColors.purple,
          typeAr: 'حِساب',
          typeEn: 'Account',
          title: a.fullName,
          subtitle: '@${a.username}',
          onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => AccountReportScreen(account: a))),
        ));
      }
    }

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 48, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                isAr ? 'لا تُوجَد نَتائِج' : 'No results',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'جَرِّب كَلِمات بَحث أُخرى'
                    : 'Try different keywords',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length.clamp(0, 50),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = results[i];
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: r.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(r.icon, color: r.color, size: 20),
          ),
          title: Text(r.title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Row(
            children: [
              Text(r.subtitle,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: r.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAr ? r.typeAr : r.typeEn,
                  style: TextStyle(
                      color: r.color,
                      fontSize: 9,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            close(context, null);
            r.onTap(context);
          },
        );
      },
    );
  }
}

class _SearchResult {
  final IconData icon;
  final Color color;
  final String typeAr;
  final String typeEn;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  const _SearchResult({
    required this.icon,
    required this.color,
    required this.typeAr,
    required this.typeEn,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
