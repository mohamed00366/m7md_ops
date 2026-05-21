// =============================================================================
// 🔐 PinHubScreen — مَركَز إدارة PINs (مُؤَقَّت + دائِم)
// =============================================================================
// شاشة مُوَحَّدة فيها تابان:
//   1. PIN مُؤَقَّت — يُوَلَّد عِندَ الحاجة، يَنتَهي بَعد دَقائِق (مُوصى بِه)
//   2. PIN دائِم — لِكُلّ مُوَظَّف، لِلطَوارِئ فَقَط
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../operation/temporary_pin_screen.dart';
import 'pin_management_screen.dart';

class PinHubScreen extends StatefulWidget {
  const PinHubScreen({super.key});

  @override
  State<PinHubScreen> createState() => _PinHubScreenState();
}

class _PinHubScreenState extends State<PinHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🔐 إدارة PINs' : '🔐 PIN Management',
      ),
      body: Column(
        children: [
          // شَريط التابات
          Container(
            color: AppColors.brand.withOpacity(0.08),
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.brand,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.brand,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.timer),
                  text: isAr ? '⚡ مُؤَقَّت' : '⚡ Temporary',
                ),
                Tab(
                  icon: const Icon(Icons.lock_outline),
                  text: isAr ? '🔒 دائِم' : '🔒 Permanent',
                ),
              ],
            ),
          ),
          // مُحتَوى التابات
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                // التاب 1: PIN مُؤَقَّت (مُوصى بِه — أَكثَر أَماناً)
                TemporaryPinScreen(),
                // التاب 2: PIN دائِم (لِلطَوارِئ)
                PinManagementScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
