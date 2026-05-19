import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../manager/customers_hub.dart';
import '../hr/hr_palette.dart';

/// 💼 قسم المبيعات - حالياً يحتوي على شاشة العملاء فقط
/// (مهيكل ليسهل توسيعه لاحقاً)
class SalesHub extends StatefulWidget {
  const SalesHub({super.key});

  @override
  State<SalesHub> createState() => _SalesHubState();
}

class _SalesHubState extends State<SalesHub> with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: TabBar(
          controller: _tab,
          indicatorColor: SalesPalette.primary,
          labelColor: SalesPalette.primary,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          tabs: [
            Tab(
                icon: const Icon(Icons.people_outline, size: 18),
                text: s.isAr ? 'العملاء' : 'Customers'),
          ],
        ),
      ),
      const Expanded(
        child: TabBarView(
          children: [CustomersHub()],
        ),
      ),
    ]);
  }
}
