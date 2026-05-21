// =============================================================================
// 📅✅ Company Calendar Hub — 3 tabs: Auto Events / Custom Events / My Tasks
// =============================================================================
// Wraps the existing CompanyCalendarScreen + adds Custom Events tab + My Tasks.
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import 'company_calendar_screen.dart';
import 'custom_events_tab.dart';
import 'my_tasks_tab.dart';

class CompanyCalendarTabsScreen extends StatefulWidget {
  const CompanyCalendarTabsScreen({super.key});

  @override
  State<CompanyCalendarTabsScreen> createState() =>
      _CompanyCalendarTabsScreenState();
}

class _CompanyCalendarTabsScreenState extends State<CompanyCalendarTabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
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
        title: isAr ? '📅 التَقويم وَالمَهامّ' : '📅 Calendar & Tasks',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.black,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorColor: AppColors.gold,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: [
                Tab(
                  icon: const Icon(Icons.event_available, size: 18),
                  text: isAr ? 'تِلقائيّة' : 'Auto Events',
                ),
                Tab(
                  icon: const Icon(Icons.event_note, size: 18),
                  text: isAr ? 'مُخَصَّصة' : 'Custom Events',
                ),
                Tab(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  text: isAr ? 'مَهامّي' : 'My Tasks',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          // التابة 1: الأَحداث التِلقائيّة من البَيانات (الشاشة القَديمة)
          _AutoEventsEmbedded(),
          // التابة 2: الأَحداث المُخَصَّصة
          CustomEventsTab(),
          // التابة 3: المَهامّ الشَخصِيّة
          MyTasksTab(),
        ],
      ),
    );
  }
}

/// يُضَمِّن `CompanyCalendarScreen` القَديم بِدون AppBar مُكَرَّر
class _AutoEventsEmbedded extends StatelessWidget {
  const _AutoEventsEmbedded();

  @override
  Widget build(BuildContext context) {
    // الشاشة القَديمة لَدَيها AppBar خاصّ — نَستَخدِم Builder لِتَجاهُله
    // بِإخفائه عَبر Theme override.
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: const AppBarTheme(toolbarHeight: 0),
      ),
      child: const CompanyCalendarScreen(),
    );
  }
}
