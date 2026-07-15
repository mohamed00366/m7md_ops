import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/excel_exporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';

/// 👥 تقرير الموظفين التفصيلي
///
/// يعرض جميع الموظفين مع أرقام الهواتف وأزرار اتصال/واتساب/بريد.
/// يدعم البحث (الاسم/الكود/الجوال) والفلترة (نشط/الكلّ/فرع/مسمّى).
class EmployeesReportScreen extends StatefulWidget {
  /// نطاق التاريخ القادم من شاشة التقارير الرئيسيّة (لأرشيف لاحق).
  final DateTime? fromDate;
  final DateTime? toDate;
  const EmployeesReportScreen({super.key, this.fromDate, this.toDate});

  @override
  State<EmployeesReportScreen> createState() => _EmployeesReportScreenState();
}

class _EmployeesReportScreenState extends State<EmployeesReportScreen> {
  String _query = '';
  String? _filterJobTitleId;
  bool _onlyActive = true;
  bool _onlyWithPhone = false;

  /// فتح تطبيق الاتصال (web: tel: scheme).
  void _call(String phone) {
    if (phone.trim().isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    html.window.open('tel:$cleaned', '_self');
  }

  /// فتح واتساب على ويب.
  void _whatsapp(String phone) {
    if (phone.trim().isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    html.window.open('https://wa.me/$cleaned', '_blank');
  }

  /// فتح برنامج البريد.
  void _email(String email) {
    if (email.trim().isEmpty) return;
    html.window.open('mailto:$email', '_self');
  }

  /// نسخ نصّ للحافظة + تنبيه.
  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text('$label: $text'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    var employees = repo.employees.toList();
    if (_onlyActive) {
      employees =
          employees.where((e) => e.status == EntityStatus.active).toList();
    }
    if (_filterJobTitleId != null) {
      employees =
          employees.where((e) => e.jobTitleId == _filterJobTitleId).toList();
    }
    if (_onlyWithPhone) {
      employees = employees.where((e) => e.mobile.trim().isNotEmpty).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      employees = employees.where((e) {
        return e.fullName.toLowerCase().contains(q) ||
            e.code.toLowerCase().contains(q) ||
            e.mobile.toLowerCase().contains(q) ||
            e.email.toLowerCase().contains(q);
      }).toList();
    }
    employees.sort((a, b) => a.fullName.compareTo(b.fullName));

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'تقرير الموظفين' : 'Employees Report'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          // 🆕 زرّ تصدير Excel
          IconButton(
            tooltip: isAr ? 'تصدير Excel' : 'Export Excel',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => _exportExcel(employees, isAr, repo),
          ),
          // عداد سريع
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${employees.length}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== شريط بحث + فلاتر =====
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.brand.withValues(alpha: 0.05),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? '🔍 ابحث بالاسم/الكود/الجوال/البريد...'
                        : '🔍 Search name/code/phone/email...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      selected: _onlyActive,
                      label: Text(
                          isAr ? 'النشطون فقط' : 'Active only',
                          style: const TextStyle(fontSize: 11)),
                      onSelected: (v) => setState(() => _onlyActive = v),
                    ),
                    FilterChip(
                      selected: _onlyWithPhone,
                      label: Text(
                          isAr ? 'لديهم رقم جوال' : 'Has phone',
                          style: const TextStyle(fontSize: 11)),
                      onSelected: (v) => setState(() => _onlyWithPhone = v),
                    ),
                    if (repo.jobTitles.isNotEmpty)
                      InputChip(
                        label: Text(
                          _filterJobTitleId == null
                              ? (isAr ? 'كلّ المسمّيات' : 'All titles')
                              : (isAr
                                  ? repo
                                      .jobTitles
                                      .firstWhere(
                                          (j) => j.id == _filterJobTitleId)
                                      .nameAr
                                  : repo
                                      .jobTitles
                                      .firstWhere(
                                          (j) => j.id == _filterJobTitleId)
                                      .nameEn),
                          style: const TextStyle(fontSize: 11),
                        ),
                        avatar: const Icon(Icons.badge_outlined, size: 14),
                        onDeleted: _filterJobTitleId == null
                            ? null
                            : () => setState(() => _filterJobTitleId = null),
                        onPressed: () async {
                          final id = await showModalBottomSheet<String?>(
                            context: context,
                            backgroundColor: Theme.of(context).cardTheme.color,
                            builder: (ctx) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  ListTile(
                                    title: Text(isAr ? 'الكلّ' : 'All'),
                                    onTap: () => Navigator.pop(ctx, null),
                                  ),
                                  for (final j in repo.jobTitles)
                                    ListTile(
                                      title: Text(isAr ? j.nameAr : j.nameEn),
                                      onTap: () => Navigator.pop(ctx, j.id),
                                    ),
                                ],
                              ),
                            ),
                          );
                          setState(() => _filterJobTitleId = id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ===== قائمة الموظفين =====
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_off_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            isAr
                                ? 'لا يوجد موظفون مطابقون'
                                : 'No matching employees',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: employees.length,
                    itemBuilder: (_, i) => _EmployeeCard(
                      employee: employees[i],
                      isAr: isAr,
                      onCall: _call,
                      onWhatsApp: _whatsapp,
                      onEmail: _email,
                      onCopy: _copy,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 🆕 تصدير قائمة الموظّفين الحاليّة (بعد الفلاتر) إلى Excel
  Future<void> _exportExcel(
      List<Employee> employees, bool isAr, MockRepository repo) async {
    final rows = employees.map<List<dynamic>>((e) {
      final jt = e.jobTitleId == null
          ? null
          : repo.jobTitleById(e.jobTitleId);
      final dept = e.departmentId == null
          ? null
          : repo.departmentById(e.departmentId);
      return [
        e.fullName,
        e.code,
        e.fileNo, // 🆕 رقم الملف
        e.mobile,
        e.email,
        jt == null ? '' : (isAr ? jt.nameAr : jt.nameEn),
        dept == null ? '' : (isAr ? dept.nameAr : dept.nameEn),
        e.status == EntityStatus.active
            ? (isAr ? 'نشط' : 'Active')
            : (isAr ? 'غير نشط' : 'Inactive'),
        // 🆕 تفاصيل الراتب
        e.basicSalary,
        e.housingAllowance,
        e.transportAllowance,
        e.otherAllowances,
        e.overtimeHourlyRate,
        e.totalSalary,
        e.iban,
        e.emergencyContactName,
        e.emergencyContactPhone,
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'employees_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الموظفون' : 'Employees',
          headers: isAr
              ? ['الاسم الكامل', 'الكود', 'رقم الملف', 'الجوال', 'البريد',
                  'المسمى', 'القسم', 'الحالة',
                  'الراتب الأساسي', 'بدل السكن', 'بدل المواصلات', 'بدلات أخرى',
                  'سعر ساعة الأوفرتايم', 'إجمالي الراتب', 'الآيبان',
                  'جهة الطوارئ', 'جوال الطوارئ']
              : ['Full Name', 'Code', 'File No', 'Mobile', 'Email',
                  'Title', 'Department', 'Status',
                  'Basic Salary', 'Housing Allowance', 'Transport Allowance',
                  'Other Allowances', 'Overtime Hourly Rate', 'Total Salary',
                  'IBAN', 'Emergency Contact', 'Emergency Phone'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ تصدير ${employees.length} موظف' : '✅ Exported ${employees.length} employees')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

/// بطاقة الموظّف داخل التقرير.
class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final bool isAr;
  final void Function(String) onCall;
  final void Function(String) onWhatsApp;
  final void Function(String) onEmail;
  final void Function(String, String) onCopy;
  const _EmployeeCard({
    required this.employee,
    required this.isAr,
    required this.onCall,
    required this.onWhatsApp,
    required this.onEmail,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final jt = employee.jobTitleId == null
        ? null
        : repo.jobTitleById(employee.jobTitleId);
    final dept = employee.departmentId == null
        ? null
        : repo.departmentById(employee.departmentId);

    final hasPhone = employee.mobile.trim().isNotEmpty;
    final hasEmail = employee.email.trim().isNotEmpty;
    final isActive = employee.status == EntityStatus.active;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.brand.withValues(alpha: 0.20)
              : Colors.grey.withValues(alpha: 0.30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف العلوي: الاسم + الكود + الحالة
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                  child: Text(
                    employee.initials,
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 14,
                        fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        employee.fileNo.isNotEmpty
                            ? '${employee.code}  •  ${employee.fileNo}'
                            : employee.code,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.success.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isActive
                        ? (isAr ? 'نشط' : 'Active')
                        : (isAr ? 'غير نشط' : 'Inactive'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isActive ? AppColors.success : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // المسمّى + القسم
            if (jt != null || dept != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (jt != null) ...[
                      const Icon(Icons.badge_outlined,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isAr ? jt.nameAr : jt.nameEn,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (jt != null && dept != null) const SizedBox(width: 12),
                    if (dept != null) ...[
                      const Icon(Icons.apartment_outlined,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isAr ? dept.nameAr : dept.nameEn,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // 🆕 ====== الراتب ======
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 14, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'الإجمالي: ${employee.totalSalary.toStringAsFixed(0)}'
                              ' (أساسي ${employee.basicSalary.toStringAsFixed(0)}'
                              '${employee.housingAllowance > 0 ? ' · سكن ${employee.housingAllowance.toStringAsFixed(0)}' : ''}'
                              '${employee.transportAllowance > 0 ? ' · مواصلات ${employee.transportAllowance.toStringAsFixed(0)}' : ''}'
                              '${employee.otherAllowances > 0 ? ' · أخرى ${employee.otherAllowances.toStringAsFixed(0)}' : ''})'
                              '${employee.overtimeHourlyRate > 0 ? ' · ساعة أوفرتايم ${employee.overtimeHourlyRate.toStringAsFixed(0)}' : ''}'
                          : 'Total: ${employee.totalSalary.toStringAsFixed(0)}'
                              ' (Basic ${employee.basicSalary.toStringAsFixed(0)}'
                              '${employee.housingAllowance > 0 ? ' · Housing ${employee.housingAllowance.toStringAsFixed(0)}' : ''}'
                              '${employee.transportAllowance > 0 ? ' · Transport ${employee.transportAllowance.toStringAsFixed(0)}' : ''}'
                              '${employee.otherAllowances > 0 ? ' · Other ${employee.otherAllowances.toStringAsFixed(0)}' : ''})'
                              '${employee.overtimeHourlyRate > 0 ? ' · OT/hr ${employee.overtimeHourlyRate.toStringAsFixed(0)}' : ''}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            // ====== الجوال ======
            _ContactRow(
              icon: Icons.phone_outlined,
              iconColor: AppColors.brand,
              label: isAr ? 'الجوال' : 'Mobile',
              value: hasPhone ? employee.mobile : (isAr ? '—' : '—'),
              actions: hasPhone
                  ? [
                      _ActionBtn(
                        icon: Icons.call,
                        color: AppColors.success,
                        tooltip: isAr ? 'اتصال' : 'Call',
                        onTap: () => onCall(employee.mobile),
                      ),
                      _ActionBtn(
                        icon: Icons.chat_bubble_outline,
                        color: const Color(0xFF25D366),
                        tooltip: 'WhatsApp',
                        onTap: () => onWhatsApp(employee.mobile),
                      ),
                      _ActionBtn(
                        icon: Icons.copy,
                        color: Colors.grey.shade600,
                        tooltip: isAr ? 'نسخ' : 'Copy',
                        onTap: () => onCopy(employee.mobile,
                            isAr ? 'الجوال' : 'Mobile'),
                      ),
                    ]
                  : const [],
            ),
            // ====== البريد ======
            if (hasEmail) ...[
              const SizedBox(height: 6),
              _ContactRow(
                icon: Icons.email_outlined,
                iconColor: AppColors.info,
                label: isAr ? 'البريد' : 'Email',
                value: employee.email,
                actions: [
                  _ActionBtn(
                    icon: Icons.send,
                    color: AppColors.info,
                    tooltip: isAr ? 'إرسال بريد' : 'Send email',
                    onTap: () => onEmail(employee.email),
                  ),
                  _ActionBtn(
                    icon: Icons.copy,
                    color: Colors.grey.shade600,
                    tooltip: isAr ? 'نسخ' : 'Copy',
                    onTap: () =>
                        onCopy(employee.email, isAr ? 'البريد' : 'Email'),
                  ),
                ],
              ),
            ],
            // ====== جهة الطوارئ ======
            if (employee.emergencyContactPhone.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _ContactRow(
                icon: Icons.warning_amber_outlined,
                iconColor: AppColors.danger,
                label: isAr
                    ? 'طوارئ${employee.emergencyContactName.isNotEmpty ? " (${employee.emergencyContactName})" : ""}'
                    : 'Emergency${employee.emergencyContactName.isNotEmpty ? " (${employee.emergencyContactName})" : ""}',
                value: employee.emergencyContactPhone,
                actions: [
                  _ActionBtn(
                    icon: Icons.call,
                    color: AppColors.danger,
                    tooltip: isAr ? 'اتصال' : 'Call',
                    onTap: () => onCall(employee.emergencyContactPhone),
                  ),
                  _ActionBtn(
                    icon: Icons.chat_bubble_outline,
                    color: const Color(0xFF25D366),
                    tooltip: 'WhatsApp',
                    onTap: () => onWhatsApp(employee.emergencyContactPhone),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final List<Widget> actions;
  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actions.isNotEmpty) ...actions,
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
