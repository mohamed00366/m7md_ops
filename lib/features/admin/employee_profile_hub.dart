import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../shared/entity_qr_screen.dart';
import '../../shared/entity_timeline_widget.dart';
import '../../shared/m7_app_bar.dart';
import '../manager/drivers/driver_report_screen.dart';
import '../manager/manager_employees.dart';
import 'employee_documents_screen.dart';
import 'employee_profile_sections.dart';
import 'employee_360_tabs.dart';
import '../hr/employee_entitlements_screen.dart';
import '../hr/employee_pin_dialog.dart';
import 'package:provider/provider.dart';
import '../../core/providers/auth_provider.dart';

/// 👤 شاشة الملف الشَخصيّ لِلموظَّف — Hub
///
/// تَعرِض كُلّ أَقسام الموظَّف كَبِطاقات مُستَقِلّة. كُلّ بِطاقة تُؤَدّي
/// إلى شاشَتها الخاصّة. هذا يَستَبدِل الـeditor الطَويل المُكتَظّ.
class EmployeeProfileHub extends StatefulWidget {
  final Employee employee;
  const EmployeeProfileHub({super.key, required this.employee});

  @override
  State<EmployeeProfileHub> createState() => _EmployeeProfileHubState();
}

class _EmployeeProfileHubState extends State<EmployeeProfileHub>
    with SingleTickerProviderStateMixin {
  Employee get employee => widget.employee;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// يُفتَح قِسم في شاشة مُنفَصِلة ثُمَّ يُحَدِّث الـHub عند العَودة.
  Future<void> _openSection(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final completion = _calcCompletion(employee);
    return Scaffold(
      appBar: M7AppBar(
        title: employee.fullName,
        subtitle: '${employee.code} · ${_completionLabel(completion, isAr)}',
        actions: [
          // 🆕 QR Code
          M7AppBarAction(
            icon: Icons.qr_code,
            tooltip: isAr ? 'رَمز QR' : 'QR Code',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EntityQrScreen(
                entityType: 'employee',
                entityId: employee.id,
                entityName: employee.fullName,
                subtitle: employee.code,
                icon: Icons.person,
                color: AppColors.brand,
              ),
            )),
          ),
          // 🆕 تَقرير السائِق — يَظهَر فَقَط لِأَصحاب الرُخصة
          if (employee.licenseNumber.isNotEmpty)
            M7AppBarAction(
              icon: Icons.directions_car,
              tooltip: isAr ? 'تَقرير السائِق' : 'Driver Report',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DriverReportScreen(driver: employee),
              )),
            ),
          // 🔐 تَوليد PIN مُؤَقَّت — يَظهَر فَقَط لِمَن لَدَيه pin.generate_temporary
          if (context.watch<AuthProvider>().isSuperAdmin ||
              context
                  .watch<AuthProvider>()
                  .permissions
                  .contains('pin.generate_temporary'))
            M7AppBarAction(
              icon: Icons.lock_clock,
              tooltip: isAr ? 'تَوليد PIN مُؤَقَّت' : 'Generate Temporary PIN',
              onPressed: () => showEmployeePinDialog(context, employee),
            ),
          M7AppBarAction(
            icon: Icons.edit_note,
            tooltip: isAr ? 'تَعديل كامِل (المُتَقَدِّم)' : 'Full editor (advanced)',
            onPressed: () => _openFullEditor(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== بانِر الموظَّف ثابِت في الأَعلى =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: _ProfileHeader(employee: employee),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CompletionBar(value: completion),
          ),
          const SizedBox(height: 8),
          // ===== شَريط Tabs =====
          Container(
            color: AppColors.brand.withOpacity(0.08),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              labelColor: AppColors.brand,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.brand,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              tabs: [
                Tab(icon: const Icon(Icons.person), text: isAr ? 'المِلَفّ' : 'Profile'),
                Tab(icon: const Icon(Icons.bar_chart), text: isAr ? 'إحصاءات' : 'Stats'),
                Tab(icon: const Icon(Icons.beach_access), text: isAr ? 'إجازات' : 'Leaves'),
                Tab(icon: const Icon(Icons.gavel), text: isAr ? 'إنذارات' : 'Discipline'),
                Tab(icon: const Icon(Icons.access_time), text: isAr ? 'حُضور' : 'Attendance'),
                Tab(icon: const Icon(Icons.payments), text: isAr ? 'مُستَحَقّات' : 'Entitlements'),
              ],
            ),
          ),
          // ===== مُحتَوى الـ Tab المُختار =====
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _profileTab(context, isAr),
                EmployeeStatsTab(employee: employee),
                EmployeeLeavesTab(employee: employee),
                EmployeeDisciplineTab(employee: employee),
                EmployeeAttendanceTab(employee: employee),
                EmployeeEntitlementsScreen(employee: employee),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTab(BuildContext context, bool isAr) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
          // ===== شَبَكة البِطاقات =====
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              _SectionCard(
                icon: Icons.person,
                titleAr: 'شَخصيّة',
                titleEn: 'Personal',
                color: AppColors.brand,
                statusOk: employee.fullName.isNotEmpty,
                statusText:
                    employee.fullName.isNotEmpty ? '✓' : '—',
                onTap: () => _openSection(
                    EmployeePersonalSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.contact_phone,
                titleAr: 'تَواصُل',
                titleEn: 'Contact',
                color: AppColors.info,
                statusOk: employee.mobile.isNotEmpty,
                statusText:
                    employee.mobile.isNotEmpty ? '✓' : '—',
                onTap: () => _openSection(
                    EmployeeContactSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.book,
                titleAr: 'جَواز السَفَر',
                titleEn: 'Passport',
                color: AppColors.gold,
                statusOk: employee.passportNumber.isNotEmpty,
                statusText:
                    employee.passportNumber.isNotEmpty ? '✓' : '—',
                onTap: () => _openSection(
                    EmployeePassportSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.badge,
                titleAr: 'الهَوِيّة',
                titleEn: 'ID Card',
                color: AppColors.warning,
                statusOk: employee.idNumber.isNotEmpty,
                statusText:
                    employee.idNumber.isNotEmpty ? '✓' : '—',
                onTap: () =>
                    _openSection(EmployeeIDSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.drive_eta,
                titleAr: 'الرُخصة',
                titleEn: 'License',
                color: Colors.purple,
                statusOk: employee.licenseNumber.isNotEmpty,
                statusText: employee.licenseExpiry == null
                    ? (employee.licenseNumber.isNotEmpty ? '✓' : '—')
                    : _daysHint(employee.licenseExpiry!),
                onTap: () => _openSection(
                    EmployeeLicenseSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.attach_money,
                titleAr: 'الراتِب',
                titleEn: 'Financial',
                color: AppColors.success,
                statusOk: employee.basicSalary > 0,
                statusText: employee.basicSalary > 0
                    ? '${employee.basicSalary.toStringAsFixed(0)}'
                    : '—',
                onTap: () => _openSection(
                    EmployeeFinancialSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.checkroom,
                titleAr: 'اليونيفورم',
                titleEn: 'Uniform',
                color: Colors.indigo,
                statusOk: employee.shirtSize.isNotEmpty,
                statusText: employee.shirtSize.isNotEmpty
                    ? '✓'
                    : '—',
                onTap: () => _openSection(
                    EmployeeUniformSection(employee: employee)),
              ),
              _SectionCard(
                icon: Icons.directions_bus,
                titleAr: 'الباص الافتِراضيّ',
                titleEn: 'Default Bus',
                color: Colors.teal,
                statusOk: employee.defaultBusId != null,
                statusText:
                    employee.defaultBusId != null ? '✓' : '—',
                onTap: () =>
                    _openSection(EmployeeBusSection(employee: employee)),
              ),
              // 🆕 الدَور الوَظيفيّ
              _SectionCard(
                icon: Icons.work_outline,
                titleAr: 'الدَور الوَظيفيّ',
                titleEn: 'Job & Role',
                color: Colors.deepPurple,
                statusOk: employee.jobTitleId != null,
                statusText:
                    employee.jobTitleId != null ? '✓' : '—',
                onTap: () => _openSection(
                    EmployeeJobRoleSection(employee: employee)),
              ),
              // 🆕 السَكَن وَالنَقل
              _SectionCard(
                icon: Icons.home_work_outlined,
                titleAr: 'السَكَن وَالنَقل',
                titleEn: 'Housing',
                color: Colors.brown,
                statusOk: true,
                statusText: employee.housingType == HousingType.onCamp
                    ? (isAr ? '🏕️' : 'Camp')
                    : (isAr ? '🏠' : 'Off'),
                onTap: () => _openSection(
                    EmployeeHousingSection(employee: employee)),
              ),
              // 🆕 النُقطة وَالحالة
              _SectionCard(
                icon: Icons.flag_circle_outlined,
                titleAr: 'النُقطة وَالحالة',
                titleEn: 'Point & Status',
                color: Colors.cyan,
                statusOk: employee.pointId != null &&
                    employee.status == EntityStatus.active,
                statusText: employee.status == EntityStatus.active
                    ? (employee.pointId != null ? '✓' : '—')
                    : '⛔',
                onTap: () => _openSection(
                    EmployeePointStatusSection(employee: employee)),
              ),
              // 🆕 الصورة الشَخصيّة
              _SectionCard(
                icon: Icons.photo_camera_outlined,
                titleAr: 'الصورة الشَخصيّة',
                titleEn: 'Photo',
                color: Colors.pink,
                statusOk: employee.photoFileId != null &&
                    employee.photoFileId!.isNotEmpty,
                statusText: (employee.photoFileId != null &&
                        employee.photoFileId!.isNotEmpty)
                    ? '✓'
                    : '—',
                onTap: () => _openSection(
                    EmployeePhotoSection(employee: employee)),
              ),
              // 🆕 وَثائِق (إصدارات) — شاشة مُنفَصِلة
              _SectionCard(
                icon: Icons.folder_special,
                titleAr: 'الوَثائِق',
                titleEn: 'Documents',
                color: AppColors.info,
                statusOk: false, // التَحقُّق الفِعليّ من قاعِدة البَيانات داخِل الشاشة
                statusText: '›',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        EmployeeDocumentsScreen(employee: employee),
                  ));
                },
              ),
              // 💡 بَصمة الوَجه أُزيلَت مِن هُنا — تُدار حَصراً مِن
              //    «المَسؤول ← المُستَخدِمون ← الحِساب» لِأَنّها مَربوطة بِالحِساب
              //    وَلَيس بِسِجِلّ المُوظَّف.
            ],
          ),
          const SizedBox(height: 12),
          // 🆕 سِجِلّ النَشاط لِهَذا المُوظَّف
          EntityTimelineWidget(
            entityType: 'employee',
            entityId: employee.id,
            limit: 10,
          ),
        ],
      );
  }

  void _openFullEditor(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeeEditorScreen(existing: employee),
    ));
  }

  /// نِسبة الإكمال البَسيطة (0.0 - 1.0)
  double _calcCompletion(Employee e) {
    int filled = 0;
    int total = 0;
    void check(bool ok) {
      total++;
      if (ok) filled++;
    }
    check(e.fullName.isNotEmpty);
    check(e.code.isNotEmpty);
    check(e.mobile.isNotEmpty);
    check(e.email.isNotEmpty);
    check(e.passportNumber.isNotEmpty);
    check(e.passportExpiry != null);
    check(e.idNumber.isNotEmpty);
    check(e.licenseNumber.isNotEmpty);
    check(e.basicSalary > 0);
    check(e.shirtSize.isNotEmpty);
    check(e.pointId != null || e.siteId != null);
    check(e.jobTitleId != null);
    return total == 0 ? 0.0 : filled / total;
  }

  String _completionLabel(double v, bool isAr) {
    final pct = (v * 100).round();
    return isAr ? '$pct% مُكتَمِل' : '$pct% complete';
  }

  String _daysHint(DateTime expiry) {
    final days = expiry.difference(DateTime.now()).inDays;
    if (days < 0) return '🔴';
    if (days <= 30) return '🟠 ${days}d';
    if (days <= 90) return '🟡';
    return '✓';
  }
}

// ============================================================
// بانِر رَأس الصَفحة
// ============================================================
class _ProfileHeader extends StatelessWidget {
  final Employee employee;
  const _ProfileHeader({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withOpacity(0.08),
            AppColors.gold.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.gold.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.gold.withOpacity(0.40),
                  AppColors.gold.withOpacity(0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              employee.initials,
              style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(employee.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    const SizedBox(width: 6),
                    _StatusChip(status: employee.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  employee.code,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey),
                ),
                if (employee.jobTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(employee.jobTitle,
                      style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شَريط نِسبة الإكمال
// ============================================================
class _CompletionBar extends StatelessWidget {
  final double value;
  const _CompletionBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 0.85
        ? AppColors.success
        : value >= 0.50
            ? AppColors.gold
            : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.assessment, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              AppStrings.of(context).isAr
                  ? 'نِسبة اكتِمال الملف'
                  : 'Profile Completion',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// شارة الحالة (Active / Inactive / Maintenance)
// ============================================================
class _StatusChip extends StatelessWidget {
  final EntityStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final Color c;
    final String label;
    final IconData ic;
    switch (status) {
      case EntityStatus.active:
        c = AppColors.success;
        ic = Icons.check_circle;
        label = isAr ? 'نَشِط' : 'Active';
        break;
      case EntityStatus.inactive:
        c = Colors.red;
        ic = Icons.cancel;
        label = isAr ? 'مُعَطَّل' : 'Inactive';
        break;
      case EntityStatus.maintenance:
        c = Colors.orange;
        ic = Icons.build_circle;
        label = isAr ? 'صِيانة' : 'Maintenance';
        break;
      case EntityStatus.vacation:
        c = Colors.teal;
        ic = Icons.beach_access;
        label = isAr ? 'في إجازة' : 'On Vacation';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, color: c, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w900, fontSize: 10)),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة قِسم
// ============================================================
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final bool statusOk;
  final String statusText;
  final VoidCallback onTap;
  const _SectionCard({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.color,
    required this.statusOk,
    required this.statusText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: color.withOpacity(0.25), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  // شارة الحالة
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusOk
                          ? AppColors.success.withOpacity(0.18)
                          : color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusOk
                            ? AppColors.success
                            : color,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                isAr ? titleAr : titleEn,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.chevron_right,
                      color: color.withOpacity(0.60), size: 14),
                  Text(
                    isAr ? 'فَتح' : 'Open',
                    style: TextStyle(
                        fontSize: 10,
                        color: color.withOpacity(0.70)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
