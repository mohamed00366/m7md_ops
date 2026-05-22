import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/file_save_helper.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../../core/providers/auth_provider.dart';
import '../../core/services/employee_bulk_io.dart';
import '../../core/services/image_picker_service.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/country_guard.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/employee_status_history.dart';
import '../../shared/m7_multi_upload.dart';
import '../../shared/widgets.dart';
import '../admin/employee_documents_expiry_report_screen.dart';
import '../admin/employee_documents_screen.dart';
import '../admin/employee_profile_hub.dart';
import '../../core/services/m7_log.dart';

class ManagerEmployees extends StatefulWidget {
  const ManagerEmployees({super.key});

  @override
  State<ManagerEmployees> createState() => _ManagerEmployeesState();
}

enum _EmployeesView { list, grid, compact }

enum _EmployeesSort { nameAsc, nameDesc, codeAsc, codeDesc, recent }

/// 🆕 إجراءات التنزيل/الرفع الجماعيّة
enum _BulkAction {
  templateXlsx,
  templateCsv,
  exportXlsx,
  exportCsv,
  import,
}

class _ManagerEmployeesState extends State<ManagerEmployees> {
  String _query = '';
  String? _filterDept;
  _EmployeesView _view = _EmployeesView.list;
  _EmployeesSort _sort = _EmployeesSort.nameAsc;
  bool _showStats = true;
  String? _filterStatus; // active | inactive | null=all
  String? _filterHire; // trainee | professional | null=all
  String? _filterHousing; // on_camp | off_camp | null=all

  @override
  void initState() {
    super.initState();
    // 🆕 استمع لتغييرات Repository ليعاد بناء الواجهة فوراً عند حفظ موظف
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final activeCountry = auth.activeCountryId;
    var filtered = repo.employees.where((e) {
      if (activeCountry != null) {
        if (e.countryId != activeCountry) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      if (_filterDept != null && e.departmentId != _filterDept) return false;
      if (_filterStatus == 'active' && e.status != EntityStatus.active) {
        return false;
      }
      if (_filterStatus == 'inactive' && e.status != EntityStatus.inactive) {
        return false;
      }
      if (_filterHire != null) {
        if (_filterHire == 'trainee' &&
            e.hireType != EmployeeHireType.trainee) return false;
        if (_filterHire == 'professional' &&
            e.hireType != EmployeeHireType.professional) return false;
      }
      if (_filterHousing != null) {
        if (_filterHousing == 'on_camp' &&
            e.housingType != HousingType.onCamp) return false;
        if (_filterHousing == 'off_camp' &&
            e.housingType != HousingType.offCamp) return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q) ||
          e.mobile.contains(q);
    }).toList();

    // الترتيب
    switch (_sort) {
      case _EmployeesSort.nameAsc:
        filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case _EmployeesSort.nameDesc:
        filtered.sort((a, b) => b.fullName.compareTo(a.fullName));
        break;
      case _EmployeesSort.codeAsc:
        filtered.sort((a, b) => a.code.compareTo(b.code));
        break;
      case _EmployeesSort.codeDesc:
        filtered.sort((a, b) => b.code.compareTo(a.code));
        break;
      case _EmployeesSort.recent:
        filtered.sort((a, b) {
          final ad = a.activationDate ?? a.joiningDate ?? DateTime(2000);
          final bd = b.activationDate ?? b.joiningDate ?? DateTime(2000);
          return bd.compareTo(ad);
        });
        break;
    }

    // KPIs (محسوبة من القائمة الكاملة بعد فلتر الدولة فقط)
    final scopeList = repo.employees.where((e) {
      if (activeCountry != null) return e.countryId == activeCountry;
      return auth.isSuperAdmin;
    }).toList();
    final totalCount = scopeList.length;
    final activeCount =
        scopeList.where((e) => e.status == EntityStatus.active).length;
    final traineeCount = scopeList
        .where((e) => e.hireType == EmployeeHireType.trainee)
        .length;
    final inCampCount =
        scopeList.where((e) => e.housingType == HousingType.onCamp).length;

    return Scaffold(
      body: Column(
        children: [
          // ===== الـ Stats Bar (أعلى الصفحة) =====
          if (_showStats)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _StatChip(
                      icon: Icons.people,
                      label: s.isAr ? ar2ur.tr('الإجمالي') : 'Total',
                      value: '$totalCount',
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.check_circle,
                      label: s.isAr ? ar2ur.tr('النشطون') : 'Active',
                      value: '$activeCount',
                      color: AppColors.success,
                      onTap: () => setState(() =>
                          _filterStatus = _filterStatus == 'active' ? null : 'active'),
                      selected: _filterStatus == 'active',
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.school_outlined,
                      label: s.isAr ? ar2ur.tr('متدرّبون') : 'Trainees',
                      value: '$traineeCount',
                      color: AppColors.warning,
                      onTap: () => setState(() => _filterHire =
                          _filterHire == 'trainee' ? null : 'trainee'),
                      selected: _filterHire == 'trainee',
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.holiday_village,
                      label: s.isAr ? ar2ur.tr('في الكمب') : 'On Camp',
                      value: '$inCampCount',
                      color: AppColors.info,
                      onTap: () => setState(() => _filterHousing =
                          _filterHousing == 'on_camp' ? null : 'on_camp'),
                      selected: _filterHousing == 'on_camp',
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.directions_bus,
                      label: s.isAr ? ar2ur.tr('يحتاج باص') : 'Needs Bus',
                      value:
                          '${scopeList.where((e) => e.housingType == HousingType.offCamp).length}',
                      color: AppColors.warning,
                      onTap: () => setState(() => _filterHousing =
                          _filterHousing == 'off_camp' ? null : 'off_camp'),
                      selected: _filterHousing == 'off_camp',
                    ),
                    // 🆕 عَرض عَدَد المُوَظَّفين حَسَب نَوع الفيزا (نَشِطون فَقَط)
                    ...(() {
                      final activeOnly = scopeList
                          .where((e) => e.status == EntityStatus.active)
                          .toList();
                      final byVisa = <String, int>{};
                      for (final e in activeOnly) {
                        final v = e.visaTypeId;
                        if (v == null || v.isEmpty) continue;
                        byVisa[v] = (byVisa[v] ?? 0) + 1;
                      }
                      return byVisa.entries.map((entry) {
                        final vt = repo.visaTypeById(entry.key);
                        final label = vt?.displayName(s.isAr) ??
                            (s.isAr ? 'فيزا' : 'Visa');
                        return Padding(
                          padding: const EdgeInsets.only(right: 6, left: 6),
                          child: _StatChip(
                            icon: Icons.badge,
                            label: '${s.isAr ? "فيزا" : "Visa"}: $label',
                            value: '${entry.value}',
                            color: AppColors.purple,
                          ),
                        );
                      });
                    })(),
                  ],
                ),
              ),
            ),
          // ===== شريط البحث + خيارات العرض =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: s.search,
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // زرّ تبديل عرض الإحصاءات
                    IconButton(
                      tooltip: s.isAr ? ar2ur.tr('إظهار/إخفاء الإحصاءات') : 'Toggle stats',
                      icon: Icon(
                        _showStats
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showStats = !_showStats),
                    ),
                    // قائمة العرض (list/grid/compact)
                    PopupMenuButton<_EmployeesView>(
                      tooltip: s.isAr ? ar2ur.tr('نمط العرض') : 'View',
                      icon: Icon(_viewIcon(_view)),
                      onSelected: (v) => setState(() => _view = v),
                      itemBuilder: (_) => [
                        _viewMenu(_EmployeesView.list, Icons.list,
                            s.isAr ? ar2ur.tr('قائمة') : 'List'),
                        _viewMenu(_EmployeesView.grid, Icons.grid_view,
                            s.isAr ? ar2ur.tr('شبكة') : 'Grid'),
                        _viewMenu(_EmployeesView.compact, Icons.density_small,
                            s.isAr ? ar2ur.tr('مضغوط') : 'Compact'),
                      ],
                    ),
                    // 🆕 اختِصار: تَقرير وَثائِق المُوَظَّفين
                    if (auth.isSuperAdmin ||
                        auth.permissions
                            .contains(P.employeeDocumentsExpiryReport))
                      IconButton(
                        tooltip: s.isAr
                            ? '📅 تَقرير الوَثائِق المُنتَهية'
                            : '📅 Documents Expiry Report',
                        icon: const Icon(Icons.event_busy,
                            color: AppColors.warning),
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                const EmployeeDocumentsExpiryReportScreen(),
                          ));
                        },
                      ),
                    // قائمة الفرز
                    PopupMenuButton<_EmployeesSort>(
                      tooltip: s.isAr ? ar2ur.tr('الترتيب') : 'Sort',
                      icon: const Icon(Icons.sort),
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        _sortMenu(_EmployeesSort.nameAsc,
                            s.isAr ? ar2ur.tr('الاسم ↑') : 'Name ↑'),
                        _sortMenu(_EmployeesSort.nameDesc,
                            s.isAr ? ar2ur.tr('الاسم ↓') : 'Name ↓'),
                        _sortMenu(_EmployeesSort.codeAsc,
                            s.isAr ? ar2ur.tr('الكود ↑') : 'Code ↑'),
                        _sortMenu(_EmployeesSort.codeDesc,
                            s.isAr ? ar2ur.tr('الكود ↓') : 'Code ↓'),
                        _sortMenu(_EmployeesSort.recent,
                            s.isAr ? ar2ur.tr('الأحدث') : 'Recent'),
                      ],
                    ),
                    // 🆕 تنزيل/رفع البيانات بالجملة — مَحميّ بصلاحيّات
                    Builder(builder: (ctx) {
                      // كلّ عمليّة لها صلاحيّتها الخاصّة
                      final canExport = auth.isSuperAdmin ||
                          auth.permissions.contains(P.reportsEmployeesExport);
                      final canImport = auth.isSuperAdmin ||
                          auth.permissions
                              .contains(P.employeesBulkImportManage);
                      // التمبليت متاح لمن يَستطيع الاستيراد فقط
                      final canDownloadTemplate = canImport;
                      // إذا لا يَملك أيّ صلاحيّة → الزرّ مختفٍ تماماً
                      if (!canExport &&
                          !canImport &&
                          !canDownloadTemplate) {
                        return const SizedBox.shrink();
                      }
                      return PopupMenuButton<_BulkAction>(
                        tooltip: s.isAr
                            ? 'استيراد/تصدير'
                            : 'Import / Export',
                        icon:
                            const Icon(Icons.cloud_download_outlined),
                        onSelected: _handleBulkAction,
                        itemBuilder: (_) => [
                          if (canDownloadTemplate)
                            PopupMenuItem(
                              value: _BulkAction.templateXlsx,
                              child: Row(children: [
                                const Icon(Icons.description_outlined,
                                    size: 18, color: AppColors.brand),
                                const SizedBox(width: 8),
                                Text(s.isAr
                                    ? 'تنزيل تمبليت Excel'
                                    : 'Download Excel template'),
                              ]),
                            ),
                          if (canDownloadTemplate)
                            PopupMenuItem(
                              value: _BulkAction.templateCsv,
                              child: Row(children: [
                                const Icon(
                                    Icons.text_snippet_outlined,
                                    size: 18,
                                    color: AppColors.brand),
                                const SizedBox(width: 8),
                                Text(s.isAr
                                    ? 'تنزيل تمبليت CSV'
                                    : 'Download CSV template'),
                              ]),
                            ),
                          if (canDownloadTemplate && canExport)
                            const PopupMenuDivider(),
                          if (canExport)
                            PopupMenuItem(
                              value: _BulkAction.exportXlsx,
                              child: Row(children: [
                                const Icon(
                                    Icons.file_download_outlined,
                                    size: 18,
                                    color: AppColors.success),
                                const SizedBox(width: 8),
                                Text(s.isAr
                                    ? 'تصدير الموظفين (Excel)'
                                    : 'Export employees (Excel)'),
                              ]),
                            ),
                          if (canExport)
                            PopupMenuItem(
                              value: _BulkAction.exportCsv,
                              child: Row(children: [
                                const Icon(
                                    Icons.file_download_outlined,
                                    size: 18,
                                    color: AppColors.success),
                                const SizedBox(width: 8),
                                Text(s.isAr
                                    ? 'تصدير الموظفين (CSV)'
                                    : 'Export employees (CSV)'),
                              ]),
                            ),
                          if ((canExport || canDownloadTemplate) &&
                              canImport)
                            const PopupMenuDivider(),
                          if (canImport)
                            PopupMenuItem(
                              value: _BulkAction.import,
                              child: Row(children: [
                                const Icon(Icons.file_upload_outlined,
                                    size: 18,
                                    color: AppColors.warning),
                                const SizedBox(width: 8),
                                Text(s.isAr
                                    ? 'رفع موظّفين (إضافة فقط)'
                                    : 'Upload employees (add only)'),
                              ]),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                // فلاتر الأقسام
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: s.all,
                        selected: _filterDept == null,
                        onTap: () => setState(() => _filterDept = null),
                      ),
                      ...repo.departments.map((d) => _FilterChip(
                            label: d.displayName(s.isAr),
                            selected: _filterDept == d.id,
                            onTap: () =>
                                setState(() => _filterDept = d.id),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ===== المحتوى =====
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(message: s.noData)
                : _buildContent(filtered),
          ),
        ],
      ),
      // 🆕 الزرّ يَظهر فقط لمن يملك صلاحيّة employees.create (أو Super Admin)
      floatingActionButton: (auth.isSuperAdmin ||
              auth.permissions.contains(P.employeesCreate))
          ? FloatingActionButton.extended(
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: Text('${s.add} ${s.isAr ? ar2ur.tr('موظف') : 'Employee'}'),
            )
          : null,
    );
  }

  IconData _viewIcon(_EmployeesView v) {
    switch (v) {
      case _EmployeesView.list:
        return Icons.list;
      case _EmployeesView.grid:
        return Icons.grid_view;
      case _EmployeesView.compact:
        return Icons.density_small;
    }
  }

  PopupMenuItem<_EmployeesView> _viewMenu(
      _EmployeesView v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(children: [
        Icon(icon, size: 16, color: _view == v ? AppColors.brand : null),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              fontWeight: _view == v ? FontWeight.w800 : FontWeight.normal,
              color: _view == v ? AppColors.brand : null,
            )),
      ]),
    );
  }

  PopupMenuItem<_EmployeesSort> _sortMenu(_EmployeesSort v, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(children: [
        if (_sort == v)
          const Icon(Icons.check, size: 16, color: AppColors.brand),
        if (_sort == v) const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontWeight: _sort == v ? FontWeight.w800 : FontWeight.normal,
              color: _sort == v ? AppColors.brand : null,
            )),
      ]),
    );
  }

  /// المحتوى — list/grid/compact + bottom padding لتجنّب تغطية الـ FAB
  Widget _buildContent(List<Employee> filtered) {
    // padding سفلي إضافي لكي لا يغطّي الـ FAB البطاقة الأخيرة
    const bottomPad = EdgeInsets.fromLTRB(12, 0, 12, 88);
    // 🆕 صلاحيّة التعديل — تحدّد ما إذا كان النقر على البطاقة يَفتح المحرّر
    final auth = context.read<AuthProvider>();
    final canEdit = auth.isSuperAdmin ||
        auth.permissions.contains(P.employeesEdit);
    switch (_view) {
      case _EmployeesView.grid:
        return GridView.builder(
          padding: bottomPad,
          // 🆕 childAspectRatio أصغر = بطاقة أطول → مكان كافٍ للاسم + الكود
          //    تحت الصورة بدون overflow في الـ 30 بكسل
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
          ),
          itemCount: filtered.length,
          itemBuilder: (_, i) => _EmployeeGridCard(
            employee: filtered[i],
            onTap:
                canEdit ? () => _openEditor(existing: filtered[i]) : null,
          ),
        );
      case _EmployeesView.compact:
        return ListView.separated(
          padding: bottomPad,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _EmployeeCompactRow(
            employee: filtered[i],
            onTap:
                canEdit ? () => _openEditor(existing: filtered[i]) : null,
          ),
        );
      case _EmployeesView.list:
      default:
        return ListView.builder(
          padding: bottomPad,
          itemCount: filtered.length,
          itemBuilder: (_, i) => _EmployeeCard(
            employee: filtered[i],
            onTap:
                canEdit ? () => _openEditor(existing: filtered[i]) : null,
          ),
        );
    }
  }

  void _openEditor({Employee? existing}) {
    // 🆕 Hub & Spoke: المُوظَّف القَديم يَفتَح Hub (شَبَكة بِطاقات أقسام)
    //    أَمّا الجَديد فَيَفتَح المُحَرِّر الكامِل لِإدخال البَيانات أَوّل مَرّة.
    if (existing != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeProfileHub(employee: existing),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const EmployeeEditorScreen(),
    ));
  }

  // ============================================================
  // 🆕 Bulk IO handlers (تنزيل/رفع البيانات بالجملة)
  // ============================================================

  Future<void> _handleBulkAction(_BulkAction action) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final io = EmployeeBulkIO.instance;
    // 🆕 طبقة حماية ثانية — التحقّق من الصلاحيّة قبل التنفيذ
    // (الـ UI أصلاً يَخفي الخيارات، لكن هذا تأكيد إضافي لأيّ تجاوز)
    final auth = context.read<AuthProvider>();
    final isExport = action == _BulkAction.exportXlsx ||
        action == _BulkAction.exportCsv;
    final isImport = action == _BulkAction.import;
    if (isExport &&
        !(auth.isSuperAdmin ||
            auth.permissions.contains(P.reportsEmployeesExport))) {
      _showDeniedSnack(isAr, isExport: true);
      return;
    }
    if (isImport &&
        !(auth.isSuperAdmin ||
            auth.permissions.contains(P.employeesBulkImportManage))) {
      _showDeniedSnack(isAr, isExport: false);
      return;
    }

    try {
      switch (action) {
        case _BulkAction.templateXlsx:
          final bytes = io.buildExcelTemplate(isAr: isAr);
          await _saveAndShare(
            bytes: Uint8List.fromList(bytes),
            filename: 'employees_template.xlsx',
            isAr: isAr,
          );
          break;
        case _BulkAction.templateCsv:
          final csv = io.buildCsvTemplate(isAr: isAr);
          // BOM لجعل Excel يفتح UTF-8 بشكل صحيح
          final bytes = Uint8List.fromList(
              [0xEF, 0xBB, 0xBF, ...csv.codeUnits]);
          await _saveAndShare(
            bytes: bytes,
            filename: 'employees_template.csv',
            isAr: isAr,
          );
          break;
        case _BulkAction.exportXlsx:
          final bytes = io.exportEmployeesExcel(repo.employees, isAr: isAr);
          await _saveAndShare(
            bytes: Uint8List.fromList(bytes),
            filename: 'employees_${_dateStamp()}.xlsx',
            isAr: isAr,
          );
          break;
        case _BulkAction.exportCsv:
          final csv = io.exportEmployeesCsv(repo.employees, isAr: isAr);
          final bytes = Uint8List.fromList(
              [0xEF, 0xBB, 0xBF, ...csv.codeUnits]);
          await _saveAndShare(
            bytes: bytes,
            filename: 'employees_${_dateStamp()}.csv',
            isAr: isAr,
          );
          break;
        case _BulkAction.import:
          await _runImport();
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('${isAr ? ar2ur.tr("خطأ") : "Error"}: $e'),
      ));
    }
  }

  String _dateStamp() {
    final n = DateTime.now();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${pad(n.month)}${pad(n.day)}_${pad(n.hour)}${pad(n.minute)}';
  }

  /// 🆕 رسالة رفض موحَّدة للتصدير/الاستيراد عند نقص الصلاحيّة
  void _showDeniedSnack(bool isAr, {required bool isExport}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.danger,
      content: Text(isAr
          ? (isExport
              ? '⛔ لا تَملك صلاحيّة "تصدير الموظّفين". تواصل مع المسؤول.'
              : '⛔ لا تَملك صلاحيّة "استيراد جماعي". تواصل مع المسؤول.')
          : (isExport
              ? '⛔ Missing permission: reports.employees.export'
              : '⛔ Missing permission: employees.bulk_import.manage')),
    ));
  }

  Future<void> _saveAndShare({
    required Uint8List bytes,
    required String filename,
    required bool isAr,
  }) async {
    // 🆕 حفظ موحّد عبر FileSaveHelper:
    //   • على الويب: تحميل عبر المتصفّح (Blob + AnchorElement)
    //   • على الجوّال: مجلّد Downloads
    //   • على سطح المكتب: مجلّد المستندات
    String message;
    try {
      message = await FileSaveHelper.save(
        bytes: bytes,
        filename: filename,
        isAr: isAr,
      );
    } catch (e) {
      message = isAr ? '${ar2ur.tr("فشل الحفظ")}: $e' : 'Save failed: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          message.startsWith('فشل') || message.startsWith('Save failed')
              ? AppColors.danger
              : AppColors.success,
      duration: const Duration(seconds: 5),
      content: Text(message),
    ));
  }

  Future<void> _runImport() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    // 🆕 withData: true → نحصل على Uint8List مباشرة (يعمل على الويب أيضاً)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'تعذّر قراءة محتوى الملف'
            : 'Could not read file contents'),
      ));
      return;
    }

    List<ParsedEmployeeRow> rows;
    try {
      rows = EmployeeBulkIO.instance.parseBytes(
        bytes: bytes,
        filename: picked.name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('${isAr ? ar2ur.tr("فشل القراءة") : "Read failed"}: $e'),
      ));
      return;
    }
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isAr ? ar2ur.tr('الملف فارغ') : 'File is empty'),
      ));
      return;
    }

    // افتح حوار المعاينة
    if (!mounted) return;
    final approved = await showDialog<List<ParsedEmployeeRow>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BulkImportPreviewDialog(rows: rows, isAr: isAr),
    );
    if (approved == null || approved.isEmpty) return;

    // نفّذ الإدراج (إضافة فقط — تخطّى الموجود مسبقاً)
    final cid = context.read<AuthProvider>().selectedCountryId;
    final res = await SupabaseDataService().bulkInsertNewEmployees(
      approved.map((r) => r.employee).toList(),
      countryId: cid,
    );
    if (!mounted) return;
    final summary = isAr
        ? 'أُضيف: ${res.added} • تخطّى: ${res.skipped} • فشل: ${res.failed}'
        : 'Added: ${res.added} • Skipped: ${res.skipped} • Failed: ${res.failed}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          res.failed == 0 ? AppColors.success : AppColors.warning,
      duration: const Duration(seconds: 6),
      content: Text(summary),
    ));
    setState(() {});
  }
}

/// شارة إحصاء قابلة للنقر — لتفعيل/إلغاء فلتر سريع
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(selected ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(selected ? 0.6 : 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    )),
                Text(label,
                    style: TextStyle(
                      color: color.withOpacity(0.85),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand
                : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.brand
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  /// 🆕 nullable — لو null فالبطاقة غير قابلة للضغط (لا صلاحيّة edit)
  final VoidCallback? onTap;
  const _EmployeeCard({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isActive = employee.status == EntityStatus.active;
    final dept = repo.departmentById(employee.departmentId);
    final job = repo.jobTitleById(employee.jobTitleId);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            _EmployeeAvatar(employee: employee),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Chip(text: employee.code),
                      if (job != null) _Chip(text: job.displayName(s.isAr)),
                      if (dept != null) _Chip(text: dept.displayName(s.isAr)),
                    ],
                  ),
                ],
              ),
            ),
            StatusBadge(
              label: isActive ? s.active : s.inactive,
              color: isActive ? AppColors.success : AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }
}

/// 🖼️ صورة الموظف — تعرض الصورة إن وُجدت ونجح تحميلها، وإلا تعرض الـ initials
class _EmployeeAvatar extends StatelessWidget {
  final Employee employee;
  final double radius;
  final Color color;
  const _EmployeeAvatar({
    required this.employee,
    this.radius = 22,
    this.color = AppColors.brand,
  });

  Widget _initials() {
    return Text(
      employee.initials,
      style: TextStyle(
        color: color,
        fontSize: radius * 0.6,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = employee.photoFileId;
    final hasPhoto = raw != null &&
        raw.isNotEmpty &&
        (raw.startsWith('http://') || raw.startsWith('https://'));

    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.15),
      child: _initials(),
    );

    if (!hasPhoto) return fallback;

    // 🆕 cache-busting بناءً على آخر updated في الموظف لتجاوز كاش Flutter
    // و key يتغيّر مع تغيّر الـ URL لإجبار rebuild حقيقي
    final url = raw;
    final keyHash = '${employee.id}_${url.hashCode}';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
      ),
      child: ClipOval(
        child: Image.network(
          url,
          key: ValueKey(keyHash),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) {
            // ignore: avoid_print
            M7Log.info('Employees', 'image load failed: $err  url=$url');
            return fallback;
          },
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(child: _initials());
          },
        ),
      ),
    );
  }
}

/// 🔲 بطاقة موظف بنمط Grid (مربّعة)
class _EmployeeGridCard extends StatelessWidget {
  final Employee employee;
  /// 🆕 nullable — لو null فالبطاقة غير قابلة للضغط (لا صلاحيّة edit)
  final VoidCallback? onTap;
  const _EmployeeGridCard({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isActive = employee.status == EntityStatus.active;
    final color = isActive ? AppColors.success : AppColors.textTertiaryLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== الصورة بحجم الويدجت كامل (الجزء العلوي) =====
            AspectRatio(
              aspectRatio: 1.05,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _EmployeeBigPhoto(employee: employee, color: color),
                  // شارة الحالة (نشط/غير نشط) في الزاوية
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1))
                        ],
                      ),
                      child: Text(
                        isActive
                            ? (s.isAr ? 'نَشِط' : 'Active')
                            : (s.isAr ? 'مَوقوف' : 'Inactive'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  // شارة "متدرّب" في الزاوية الأخرى
                  if (employee.hireType == EmployeeHireType.trainee)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 1))
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school,
                                size: 9, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'متدرّب',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ===== المعلومات تحت الصورة =====
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(employee.fullName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                  Text(employee.code,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.brand,
                          fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🖼️ صورة موظف كبيرة بحجم الـ widget (تستخدم في Grid Card)
class _EmployeeBigPhoto extends StatelessWidget {
  final Employee employee;
  final Color color;
  const _EmployeeBigPhoto({required this.employee, required this.color});

  @override
  Widget build(BuildContext context) {
    final url = employee.photoFileId;
    final hasPhoto = url != null &&
        url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));

    final fallback = Container(
      color: color.withOpacity(0.12),
      alignment: Alignment.center,
      child: Text(
        employee.initials,
        style: TextStyle(
          color: color,
          fontSize: 36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    if (!hasPhoto) return fallback;

    return Image.network(
      url,
      key: ValueKey('${employee.id}_${url.hashCode}'),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: color.withOpacity(0.08),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

/// 📋 صفّ موظف مضغوط (سطر واحد)
class _EmployeeCompactRow extends StatelessWidget {
  final Employee employee;
  /// 🆕 nullable — لو null فالبطاقة غير قابلة للضغط (لا صلاحيّة edit)
  final VoidCallback? onTap;
  const _EmployeeCompactRow({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = employee.status == EntityStatus.active;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: _EmployeeAvatar(employee: employee, radius: 16),
      title: Row(
        children: [
          Expanded(
            child: Text(employee.fullName,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (employee.hireType == EmployeeHireType.trainee)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('🎓',
                  style: TextStyle(fontSize: 10)),
            ),
        ],
      ),
      subtitle: Text(
        '${employee.code} • ${employee.jobTitle}',
        style: const TextStyle(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? AppColors.success : AppColors.textTertiaryLight,
        ),
      ),
    );
  }
}

// ============================================================
// Employee Editor (Full screen with 5 sections)
// ============================================================
class EmployeeEditorScreen extends StatefulWidget {
  final Employee? existing;
  const EmployeeEditorScreen({super.key, this.existing});

  @override
  State<EmployeeEditorScreen> createState() => _EmployeeEditorScreenState();
}

class _EmployeeEditorScreenState extends State<EmployeeEditorScreen> {
  // Personal
  late final TextEditingController _code;
  late final TextEditingController _fullName;
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late final TextEditingController _address;
  String? _jobTitleId;
  String? _departmentId;
  String? _maritalStatusId;
  String? _nationalityId;
  DateTime? _birthDate;
  DateTime? _joiningDate;
  String? _photoFileId;

  // Passport & ID
  late final TextEditingController _passportNumber;
  late final TextEditingController _idNumber;
  DateTime? _passportExpiry;
  String? _visaTypeId;
  String? _idCardFileId;
  // 🇦🇪 حُقول حُكومِيّة إضافيّة (UAE)
  late final TextEditingController _visaFileNumber;
  DateTime? _eidExpiry;
  late final TextEditingController _establishmentFileNumber;
  late final TextEditingController _labourCardNumber;
  DateTime? _labourCardExpiry;
  late final TextEditingController _mohreNumber;
  late final TextEditingController _waslUid;

  // License
  late final TextEditingController _licenseNumber;
  DateTime? _licenseIssue;
  DateTime? _licenseExpiry;
  String? _licenseFileId;

  // Financial
  late final TextEditingController _basicSalary;
  late final TextEditingController _overtime;
  late final TextEditingController _trainingFee;
  late final TextEditingController _others;
  late final TextEditingController _iban;
  // 🆕 بَدَلات إضافيّة وَ تَذكِرة (May 2026)
  late final TextEditingController _housingAllowance;
  late final TextEditingController _transportAllowance;
  late final TextEditingController _otherAllowances;
  late final TextEditingController _ticketAmount;
  bool _eligibleForTicket = false;
  // 🆕 جَواز السَفَر — الحَفظ + المُلاحَظات + التَواريخ
  String _passportCustody = 'with_employee';
  late final TextEditingController _passportCustodyNotes;
  DateTime? _passportReceivedDate;
  DateTime? _passportReturnedDate;
  DateTime? _workLetterDate;
  String? _workLetterFileId;

  // Emergency / Additional
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _education;

  // Status
  EntityStatus _status = EntityStatus.active;

  // 🏠 السكن (في الكمب / خارج الكمب)
  HousingType _housingType = HousingType.offCamp;

  // 🎓 نوع التحاق الموظف (متدرّب / محترف)
  EmployeeHireType _hireType = EmployeeHireType.trainee;

  // 👕 مقاسات اليونيفورم
  late final TextEditingController _shirtSize;
  late final TextEditingController _pantSize;
  late final TextEditingController _shoeSize;

  // 🚌 الباص الافتراضي للموظف
  String? _defaultBusId;

  // 🎭 استِثناء فَردِيّ مِن دُخول بَصمة الوَجه
  bool _excludedFromFaceLogin = false;

  // 📎 مِلَفّات إضافيّة (Multi-file) لِكُلّ وَثيقة
  List<String> _idCardFiles = <String>[];
  List<String> _licenseFiles = <String>[];
  List<String> _workLetterFiles = <String>[];
  // 📎 جَواز السَفَر — مِلَفّ رَئيسيّ + مِلَفّات إضافيّة
  String? _passportFileId;
  List<String> _passportFiles = <String>[];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final repo = MockRepository();

    // كود الموظف يأتي من نظام الترقيم (مثال: V-SA-0001)
    // technical_id يعتمد على تصنيف القسم/المسمّى:
    //   worker → worker_employee
    //   admin → admin_employee
    //   operations → operations_employee
    String autoCode = '';
    if (e == null) {
      // ندحرج post-frame لأن context.read غير متاح في initState مباشرة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCodePreview();
      });
    }
    _code = TextEditingController(text: e?.code ?? autoCode);
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _mobile = TextEditingController(text: e?.mobile ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _jobTitleId = e?.jobTitleId;
    _departmentId = e?.departmentId;
    _maritalStatusId = e?.maritalStatusId;
    _nationalityId = e?.nationalityId;
    _birthDate = e?.birthDate;
    _joiningDate = e?.joiningDate;
    _photoFileId = e?.photoFileId;

    _passportNumber = TextEditingController(text: e?.passportNumber ?? '');
    _idNumber = TextEditingController(text: e?.idNumber ?? '');
    _passportExpiry = e?.passportExpiry;
    _visaTypeId = e?.visaTypeId;
    _idCardFileId = e?.idCardFileId;

    _licenseNumber = TextEditingController(text: e?.licenseNumber ?? '');
    _licenseIssue = e?.licenseIssue;
    _licenseExpiry = e?.licenseExpiry;
    _licenseFileId = e?.licenseFileId;

    _basicSalary = TextEditingController(text: (e?.basicSalary ?? 0).toString());
    _overtime = TextEditingController(text: (e?.overtime ?? 0).toString());
    _trainingFee = TextEditingController(text: (e?.trainingFee ?? 0).toString());
    _others = TextEditingController(text: (e?.others ?? 0).toString());
    _iban = TextEditingController(text: e?.iban ?? '');
    // 🆕 بَدَلات + تَذكِرة
    _housingAllowance =
        TextEditingController(text: (e?.housingAllowance ?? 0).toString());
    _transportAllowance =
        TextEditingController(text: (e?.transportAllowance ?? 0).toString());
    _otherAllowances =
        TextEditingController(text: (e?.otherAllowances ?? 0).toString());
    _ticketAmount =
        TextEditingController(text: (e?.ticketAmount ?? 0).toString());
    _eligibleForTicket = e?.eligibleForTicket ?? false;
    // 🆕 جَواز السَفَر
    _passportCustody = e?.passportCustody ?? 'with_employee';
    _passportCustodyNotes =
        TextEditingController(text: e?.passportCustodyNotes ?? '');
    _passportReceivedDate = e?.passportReceivedDate;
    _passportReturnedDate = e?.passportReturnedDate;
    _workLetterDate = e?.workLetterDate;
    _workLetterFileId = e?.workLetterFileId;

    // 📎 مِلَفّات إضافيّة
    _idCardFiles = List<String>.from(e?.idCardFiles ?? const <String>[]);
    _licenseFiles = List<String>.from(e?.licenseFiles ?? const <String>[]);
    _workLetterFiles =
        List<String>.from(e?.workLetterFiles ?? const <String>[]);
    _passportFileId = e?.passportFileId;
    _passportFiles = List<String>.from(e?.passportFiles ?? const <String>[]);

    // 🇦🇪 حُقول حُكومِيّة إضافيّة (UAE)
    _visaFileNumber = TextEditingController(text: e?.visaFileNumber ?? '');
    _eidExpiry = e?.eidExpiry;
    _establishmentFileNumber =
        TextEditingController(text: e?.establishmentFileNumber ?? '');
    _labourCardNumber =
        TextEditingController(text: e?.labourCardNumber ?? '');
    _labourCardExpiry = e?.labourCardExpiry;
    _mohreNumber = TextEditingController(text: e?.mohreNumber ?? '');
    _waslUid = TextEditingController(text: e?.waslUid ?? '');
    _excludedFromFaceLogin = e?.excludedFromFaceLogin ?? false;

    _emergencyName = TextEditingController(text: e?.emergencyContactName ?? '');
    _emergencyPhone = TextEditingController(text: e?.emergencyContactPhone ?? '');
    _education = TextEditingController(text: e?.education ?? '');

    _status = e?.status ?? EntityStatus.active;
    _housingType = e?.housingType ?? HousingType.offCamp;
    _hireType = e?.hireType ?? EmployeeHireType.trainee;
    _shirtSize = TextEditingController(text: e?.shirtSize ?? '');
    _pantSize = TextEditingController(text: e?.pantSize ?? '');
    _shoeSize = TextEditingController(text: e?.shoeSize ?? '');
    _defaultBusId = e?.defaultBusId;
  }

  @override
  void dispose() {
    _code.dispose();
    _fullName.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    _passportNumber.dispose();
    _idNumber.dispose();
    _licenseNumber.dispose();
    _basicSalary.dispose();
    _overtime.dispose();
    _trainingFee.dispose();
    _others.dispose();
    _iban.dispose();
    _housingAllowance.dispose();
    _transportAllowance.dispose();
    _otherAllowances.dispose();
    _ticketAmount.dispose();
    _passportCustodyNotes.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _education.dispose();
    _shirtSize.dispose();
    _pantSize.dispose();
    _shoeSize.dispose();
    // 🇦🇪 حُقول حُكومِيّة إضافيّة
    _visaFileNumber.dispose();
    _establishmentFileNumber.dispose();
    _labourCardNumber.dispose();
    _mohreNumber.dispose();
    _waslUid.dispose();
    super.dispose();
  }

  /// 🎨 لَون الحالة (لِبادج AppBar وَالبِطاقات)
  Color _statusColor(EntityStatus s) {
    switch (s) {
      case EntityStatus.active:
        return AppColors.success;
      case EntityStatus.vacation:
        return AppColors.info;
      case EntityStatus.suspended:
        return AppColors.warning;
      case EntityStatus.resigned:
      case EntityStatus.terminated:
        return AppColors.danger;
      case EntityStatus.inactive:
      case EntityStatus.maintenance:
        return Colors.grey;
    }
  }

  double get _totalSalary {
    final basic = double.tryParse(_basicSalary.text) ?? 0;
    final others = double.tryParse(_others.text) ?? 0;
    return basic + others;
  }

  /// 🆕 يُعيد توليد رمز الموظف بناءً على تصنيف القسم/المسمّى المختار
  /// يُستدعى عند initState وعند تغيير القسم أو المسمّى الوظيفي
  void _refreshCodePreview() {
    if (widget.existing != null) return; // لا تغيير على الموظف القديم
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final cid = auth.selectedCountryId ?? auth.activeCountryId;

    // تحديد technical_id حسب القسم أوّلاً، ثم المسمّى الوظيفي
    String tech;
    if (_departmentId != null) {
      tech = repo.numberingTechnicalIdForDepartment(_departmentId);
    } else if (_jobTitleId != null) {
      tech = repo.numberingTechnicalIdForJobTitle(_jobTitleId);
    } else {
      tech = 'worker_employee'; // افتراضي
    }

    String? preview;
    if (cid != null) {
      preview = repo.previewCodeFor(cid, tech);
    }
    // fallback: legacy
    preview ??= repo.generateEmployeeCode();
    setState(() => _code.text = preview!);
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked,
      {DateTime? first, DateTime? last}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: first ?? DateTime(1950),
      lastDate: last ?? DateTime(2100),
    );
    if (d != null) onPicked(d);
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_fullName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr ? ar2ur.tr('الاسم مطلوب') : 'Name is required')),
      );
      return;
    }
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final dataService = SupabaseDataService();
    // 🛡️ حارس الدولة عند الإنشاء فقط
    if (widget.existing == null) {
      if (!await CountryGuard.require(context,
          entityName: s.isAr ? ar2ur.tr('إنشاء موظف') : 'creating employee')) {
        return;
      }
      if (!mounted) return;
    }
    final cid = context.read<AuthProvider>().selectedCountryId;

    // عند الإنشاء الجديد: استهلك الكود من نظام الترقيم (RPC في Supabase أو مزامنة محلية)
    // 🆕 تحديد technical_id الصَحيح حَسَب القسم/المُسمّى الوظيفيّ (وليس 'employee')
    String techId;
    if (_departmentId != null) {
      techId = repo.numberingTechnicalIdForDepartment(_departmentId);
    } else if (_jobTitleId != null) {
      techId = repo.numberingTechnicalIdForJobTitle(_jobTitleId);
    } else {
      techId = 'worker_employee'; // افتراضيّ
    }

    String finalCode = _code.text.trim();
    if (widget.existing == null) {
      if (cid != null) {
        if (supaReady) {
          // 🆕 جَرِّب الـtechId الدَقيق أَوّلاً، ثمّ fallback إلى أنواع شائِعة
          String? code = await dataService.consumeNextCode(
              technicalId: techId, countryId: cid);
          // fallbacks لو القاعدة غَير مَوجودة
          code ??= await dataService.consumeNextCode(
              technicalId: 'worker_employee', countryId: cid);
          code ??= await dataService.consumeNextCode(
              technicalId: 'operations_employee', countryId: cid);
          code ??= await dataService.consumeNextCode(
              technicalId: 'employee', countryId: cid);
          if (code != null) finalCode = code;
        } else {
          final consumed = repo.generateCodeFor(cid, techId);
          if (consumed != null) finalCode = consumed;
        }
      }
      if (finalCode.isEmpty) finalCode = repo.generateEmployeeCode();

      // 🆕 ضَمان نِهائيّ: لو الكود مَوجود مُسبَقاً في الذاكرة → اِبني واحِداً فَريداً
      if (repo.employees.any((e) => e.code == finalCode)) {
        finalCode = '$finalCode-${DateTime.now().millisecondsSinceEpoch % 10000}';
      }
    }

    final basic = double.tryParse(_basicSalary.text) ?? 0;
    final ot = double.tryParse(_overtime.text) ?? 0;
    final tf = double.tryParse(_trainingFee.text) ?? 0;
    final ot2 = double.tryParse(_others.text) ?? 0;

    // الحصول على الأسماء النصية من الـ lookups (للتوافق مع الكود القديم الذي يقرأ الحقول النصية)
    final jobTitleName = repo.jobTitleById(_jobTitleId)?.displayName(true) ?? '';
    final deptName = repo.departmentById(_departmentId)?.displayName(true) ?? '';
    final maritalName =
        repo.maritalStatusById(_maritalStatusId)?.displayName(true) ?? '';
    final nationName =
        repo.nationalityById(_nationalityId)?.displayName(true) ?? '';
    final visaName = repo.visaTypeById(_visaTypeId)?.displayName(true) ?? '';

    if (widget.existing == null) {
      final newEmp = Employee(
        id: repo.generateId(),
        code: finalCode,
        fullName: _fullName.text.trim(),
        jobTitle: jobTitleName,
        department: deptName,
        maritalStatus: maritalName,
        nationality: nationName,
        visaType: visaName,
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
        birthDate: _birthDate,
        joiningDate: _joiningDate,
        address: _address.text.trim(),
        passportNumber: _passportNumber.text.trim(),
        passportExpiry: _passportExpiry,
        idNumber: _idNumber.text.trim(),
        licenseNumber: _licenseNumber.text.trim(),
        licenseIssue: _licenseIssue,
        licenseExpiry: _licenseExpiry,
        basicSalary: basic,
        overtime: ot,
        trainingFee: tf,
        others: ot2,
        iban: _iban.text.trim(),
        emergencyContactName: _emergencyName.text.trim(),
        emergencyContactPhone: _emergencyPhone.text.trim(),
        education: _education.text.trim(),
        status: _status,
        // معرفات الـ lookups
        jobTitleId: _jobTitleId,
        departmentId: _departmentId,
        maritalStatusId: _maritalStatusId,
        nationalityId: _nationalityId,
        visaTypeId: _visaTypeId,
        // 🏠 السكن
        housingType: _housingType,
        // 🎓 نوع الالتحاق
        hireType: _hireType,
        // 👕 مقاسات اليونيفورم
        shirtSize: _shirtSize.text.trim(),
        pantSize: _pantSize.text.trim(),
        shoeSize: _shoeSize.text.trim(),
        // 🚌 الباص الافتراضي
        defaultBusId: _defaultBusId,
        // 🆕 بَدَلات وَ تَذكِرة
        housingAllowance: double.tryParse(_housingAllowance.text) ?? 0,
        transportAllowance: double.tryParse(_transportAllowance.text) ?? 0,
        otherAllowances: double.tryParse(_otherAllowances.text) ?? 0,
        eligibleForTicket: _eligibleForTicket,
        ticketAmount: double.tryParse(_ticketAmount.text) ?? 0,
        passportCustody: _passportCustody,
        passportCustodyNotes: _passportCustodyNotes.text.trim(),
        passportReceivedDate: _passportReceivedDate,
        passportReturnedDate: _passportReturnedDate,
        // 🎭 استِثناء فَردِيّ مِن دُخول بَصمة الوَجه
        excludedFromFaceLogin: _excludedFromFaceLogin,
        // الملفات
        photoFileId: _photoFileId,
        idCardFileId: _idCardFileId,
        licenseFileId: _licenseFileId,
        workLetterFileId: _workLetterFileId,
        workLetterDate: _workLetterDate,
        // 📎 مِلَفّات إضافيّة (Multi-file)
        idCardFiles: _idCardFiles,
        licenseFiles: _licenseFiles,
        workLetterFiles: _workLetterFiles,
        passportFileId: _passportFileId,
        passportFiles: _passportFiles,
        // 🇦🇪 حُقول حُكومِيّة إضافيّة (UAE)
        visaFileNumber: _visaFileNumber.text.trim(),
        eidExpiry: _eidExpiry,
        establishmentFileNumber: _establishmentFileNumber.text.trim(),
        labourCardNumber: _labourCardNumber.text.trim(),
        labourCardExpiry: _labourCardExpiry,
        mohreNumber: _mohreNumber.text.trim(),
        waslUid: _waslUid.text.trim(),
      );
      if (supaReady) {
        final created = await dataService.createEmployee(newEmp, countryId: cid);
        if (created == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(dataService.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.addEmployee(newEmp);
      }
      // 🎓 لو الموظف الجديد متدرّب → أنشئ سجلّ OnPointTraining تلقائيّاً
      //    + نَموذَج TRAINEE-ONBOARDING (يَظهَر فَوراً في "موافقاتي" لِلمُشرِف)
      if (newEmp.hireType == EmployeeHireType.trainee) {
        repo.autoCreateOnPointForNewTrainee(newEmp);
        final accountId = context.read<AuthProvider>().account?.id;
        final sub = repo.autoCreateTraineeOnboardingForm(
          newEmp,
          submittedByAccountId: accountId,
        );
        // ادفَع لِـSupabase لَو جاهِز (لا نَنتَظِر — لا يَمنَع إنهاء التَسجيل)
        if (sub != null && supaReady) {
          // ignore: unawaited_futures
          dataService.createFormSubmission(sub);
        }
      }
    } else {
      final e = widget.existing!;
      e.code = _code.text.trim();
      e.fullName = _fullName.text.trim();
      e.jobTitle = jobTitleName;
      e.department = deptName;
      e.maritalStatus = maritalName;
      e.nationality = nationName;
      e.visaType = visaName;
      e.mobile = _mobile.text.trim();
      e.email = _email.text.trim();
      e.birthDate = _birthDate;
      e.joiningDate = _joiningDate;
      e.address = _address.text.trim();
      e.passportNumber = _passportNumber.text.trim();
      e.passportExpiry = _passportExpiry;
      e.idNumber = _idNumber.text.trim();
      e.licenseNumber = _licenseNumber.text.trim();
      e.licenseIssue = _licenseIssue;
      e.licenseExpiry = _licenseExpiry;
      e.basicSalary = basic;
      e.overtime = ot;
      e.trainingFee = tf;
      e.others = ot2;
      e.iban = _iban.text.trim();
      e.emergencyContactName = _emergencyName.text.trim();
      e.emergencyContactPhone = _emergencyPhone.text.trim();
      e.education = _education.text.trim();
      e.status = _status;
      e.jobTitleId = _jobTitleId;
      e.departmentId = _departmentId;
      e.maritalStatusId = _maritalStatusId;
      e.nationalityId = _nationalityId;
      e.visaTypeId = _visaTypeId;
      e.housingType = _housingType; // 🆕 السكن
      e.hireType = _hireType;       // 🆕 نوع الالتحاق
      e.shirtSize = _shirtSize.text.trim();
      e.pantSize = _pantSize.text.trim();
      e.shoeSize = _shoeSize.text.trim();
      e.defaultBusId = _defaultBusId; // 🆕 الباص الافتراضي
      // 🆕 بَدَلات وَ تَذكِرة
      e.housingAllowance = double.tryParse(_housingAllowance.text) ?? 0;
      e.transportAllowance = double.tryParse(_transportAllowance.text) ?? 0;
      e.otherAllowances = double.tryParse(_otherAllowances.text) ?? 0;
      e.eligibleForTicket = _eligibleForTicket;
      e.ticketAmount = double.tryParse(_ticketAmount.text) ?? 0;
      e.passportCustody = _passportCustody;
      e.passportCustodyNotes = _passportCustodyNotes.text.trim();
      e.passportReceivedDate = _passportReceivedDate;
      e.passportReturnedDate = _passportReturnedDate;
      e.excludedFromFaceLogin = _excludedFromFaceLogin;
      e.photoFileId = _photoFileId;
      e.idCardFileId = _idCardFileId;
      e.licenseFileId = _licenseFileId;
      e.workLetterFileId = _workLetterFileId;
      e.workLetterDate = _workLetterDate;
      // 📎 مِلَفّات إضافيّة (Multi-file)
      e.idCardFiles = List<String>.from(_idCardFiles);
      e.licenseFiles = List<String>.from(_licenseFiles);
      e.workLetterFiles = List<String>.from(_workLetterFiles);
      e.passportFileId = _passportFileId;
      e.passportFiles = List<String>.from(_passportFiles);
      // 🇦🇪 حُقول حُكومِيّة إضافيّة (UAE)
      e.visaFileNumber = _visaFileNumber.text.trim();
      e.eidExpiry = _eidExpiry;
      e.establishmentFileNumber = _establishmentFileNumber.text.trim();
      e.labourCardNumber = _labourCardNumber.text.trim();
      e.labourCardExpiry = _labourCardExpiry;
      e.mohreNumber = _mohreNumber.text.trim();
      e.waslUid = _waslUid.text.trim();
      if (supaReady) {
        final ok = await dataService.updateEmployee(e);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(dataService.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.updateEmployee(e);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.success)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit
            ? (s.isAr ? ar2ur.tr('تعديل موظف') : 'Edit Employee')
            : (s.isAr ? ar2ur.tr('موظف جديد') : 'New Employee')),
        actions: [
          // 🆕 Status badge مَع لَون ديناميكيّ — التَوغل يَعمَل فَقَط بَين
          // active/inactive. الحالات الأُخرى تَأتي مِن workflows تِلقائيّة.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Row(
              children: [
                StatusBadge(
                  label: _status.label(isAr: s.isAr),
                  color: _statusColor(_status),
                  dense: true,
                ),
                if (_status == EntityStatus.active ||
                    _status == EntityStatus.inactive)
                  Switch(
                    value: _status == EntityStatus.active,
                    onChanged: (v) => setState(() {
                      _status =
                          v ? EntityStatus.active : EntityStatus.inactive;
                    }),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message: s.isAr
                          ? 'الحالة مُدارَة تِلقائيّاً مِن إجازات/استِقالة/خَصم'
                          : 'Auto-managed by leaves/resignation/deduction',
                      child: const Icon(Icons.lock_outline,
                          size: 18, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 16),
            label: Text(s.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ========= 1) PERSONAL INFORMATION =========
          _SectionHeader(icon: Icons.person, title: s.personalInfo),
          SectionCard(
            child: Column(
              children: [
                _UploadBox(
                  label: s.employeePhoto,
                  hint: s.uploadPhoto,
                  icon: Icons.add_a_photo_outlined,
                  hasFile: _photoFileId != null,
                  bucket: 'employee_photos',
                  pathPrefix: 'emp_${widget.existing?.id ?? "new"}_photo',
                  existingUrl: _photoFileId,
                  onUploaded: (id) => setState(() => _photoFileId = id),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      readOnly: widget.existing == null, // كود تلقائي للموظف الجديد
                      decoration: InputDecoration(
                        labelText: s.employeeCode,
                        suffixIcon: widget.existing == null
                            ? Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.brand,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Center(
                                  widthFactor: 1,
                                  child: Text(
                                    'AUTO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _fullName,
                      decoration: InputDecoration(
                        labelText: '${s.fullName} *',
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _jobTitleId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.jobTitle2),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.jobTitles.map((j) => DropdownMenuItem(
                              value: j.id,
                              child: Text(j.displayName(s.isAr),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _jobTitleId = v);
                        _refreshCodePreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _departmentId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.department2),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.departments.map((d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(d.displayName(s.isAr),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _departmentId = v);
                        _refreshCodePreview();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _maritalStatusId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.maritalStatus2),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.maritalStatuses.map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.displayName(s.isAr),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _maritalStatusId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: s.phone),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: s.email),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.birthDate,
                      value: _birthDate,
                      onPicked: (d) => setState(() => _birthDate = d),
                      lastDate: DateTime.now(),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _nationalityId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.nationality2),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.nationalities.map((n) => DropdownMenuItem(
                              value: n.id,
                              child: Text(n.displayName(s.isAr),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _nationalityId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.joiningDate,
                      value: _joiningDate,
                      onPicked: (d) => setState(() => _joiningDate = d),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: s.fullAddress2),
                ),
                const SizedBox(height: 12),
                // 🏠 السكن (في الكمب / خارج الكمب)
                _HousingField(
                  value: _housingType,
                  onChanged: (v) => setState(() => _housingType = v),
                  isAr: s.isAr,
                ),
                const SizedBox(height: 12),
                // 🎓 نوع الالتحاق (متدرّب / محترف)
                _HireTypeField(
                  value: _hireType,
                  onChanged: (v) => setState(() => _hireType = v),
                  isAr: s.isAr,
                ),
                const SizedBox(height: 12),
                // 👕 مقاسات اليونيفورم
                _UniformSizesField(
                  shirtCtrl: _shirtSize,
                  pantCtrl: _pantSize,
                  shoeCtrl: _shoeSize,
                  isAr: s.isAr,
                ),
                const SizedBox(height: 12),
                // 🆕 📄 وَثائِق الموظَّف (إصدارات) — يَظهَر بَعدَ الحِفظ
                // 🆕 بَصمة الوَجه نُقِلَت إلى شاشة المُستَخدِمين (Admin → Users)
                if (widget.existing != null) ...[
                  // 🆕 بِطاقة سِجِلّ الحالة (Status History)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EmployeeStatusHistoryScreen(
                          employeeId: widget.existing!.id,
                          employeeName: widget.existing!.fullName,
                        ),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: _statusColor(_status).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _statusColor(_status).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.history,
                              color: _statusColor(_status)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.isAr
                                      ? '📜 سِجِلّ تَغَيُّرات الحالة'
                                      : '📜 Status History',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.isAr
                                      ? 'الحالة الحاليّة: ${_status.label(isAr: true)} — اضغَط لِعَرض كُلّ التَغَيُّرات'
                                      : 'Current: ${_status.label(isAr: false)} — tap to view all changes',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  _DocumentsLinkCard(
                    employee: widget.existing!,
                    isAr: s.isAr,
                  ),
                  const SizedBox(height: 8),
                  // إرشاد لِلمَسؤول: تَسجيل البَصمة من شاشة المُستَخدِمين
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.info.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.info, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? '😊 لِتَسجيل بَصمة الوَجه لِهذا الموظَّف، اذهَب إلى: المَسؤول ← المُستَخدِمون ← حِسابُه ← بَصمة الوَجه'
                                : '😊 To enroll face, go to: Admin → Users → his account → Face Biometric',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ========= 2) PASSPORT & ID =========
          _SectionHeader(
              icon: Icons.badge_outlined, title: s.passportIdInfo),
          SectionCard(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _passportNumber,
                      decoration: InputDecoration(labelText: s.passportNumber),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.passportExpiry,
                      value: _passportExpiry,
                      onPicked: (d) => setState(() => _passportExpiry = d),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // 🆕 حِفظ الجَواز: مَع الشَركة / مَع المُوَظَّف
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.brand.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.book_outlined,
                            size: 18, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text(
                          s.isAr
                              ? '📓 مَوضِع جَواز السَفَر'
                              : '📓 Passport Custody',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              s.isAr ? 'مَع المُوَظَّف' : 'With Employee',
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: 'with_employee',
                            groupValue: _passportCustody,
                            onChanged: (v) =>
                                setState(() => _passportCustody = v!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              s.isAr ? 'مَع الشَركة' : 'With Company',
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: 'with_company',
                            groupValue: _passportCustody,
                            onChanged: (v) =>
                                setState(() => _passportCustody = v!),
                          ),
                        ),
                      ]),
                      if (_passportCustody == 'with_company') ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: _DateField(
                              label: s.isAr
                                  ? 'تاريخ الاستِلام'
                                  : 'Received Date',
                              value: _passportReceivedDate,
                              onPicked: (d) => setState(
                                  () => _passportReceivedDate = d),
                              pickFn: _pickDate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DateField(
                              label: s.isAr
                                  ? 'تاريخ التَسليم'
                                  : 'Returned Date',
                              value: _passportReturnedDate,
                              onPicked: (d) => setState(
                                  () => _passportReturnedDate = d),
                              pickFn: _pickDate,
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passportCustodyNotes,
                        decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'مُلاحَظات / سَبَب'
                              : 'Notes / Reason',
                          hintText: s.isAr
                              ? 'مَثَلاً: لِتَجديد الإقامة'
                              : 'e.g., for residence renewal',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 📎 رَفع مِلَفّ جَواز السَفَر (Multi-file: صُوَر + PDF)
                M7MultiUploadBox(
                  label: s.isAr ? 'مِلَفّ الجَواز' : 'Passport Document',
                  hint: s.isAr
                      ? 'ارفَع صُوَر + PDF لِجَواز السَفَر'
                      : 'Upload images + PDF of passport',
                  icon: Icons.book_outlined,
                  bucket: 'passports',
                  pathPrefix:
                      'emp_${widget.existing?.id ?? "new"}_passport',
                  urls: [
                    if (_passportFileId != null) _passportFileId!,
                    ..._passportFiles,
                  ],
                  onChanged: (list) => setState(() {
                    if (list.isEmpty) {
                      _passportFileId = null;
                      _passportFiles = <String>[];
                    } else {
                      _passportFileId = list.first;
                      _passportFiles = list.skip(1).toList();
                    }
                  }),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _idNumber,
                      decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'رَقم الهَوِيّة الإماراتيّة'
                              : 'Emirates ID'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.isAr
                          ? 'انتِهاء الهَوِيّة الإماراتيّة'
                          : 'EID Expiry',
                      value: _eidExpiry,
                      onPicked: (d) => setState(() => _eidExpiry = d),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _visaTypeId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.visaType2),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.visaTypes.map((v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.displayName(s.isAr),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _visaTypeId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _visaFileNumber,
                      decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'رَقم مِلَفّ التَأشيرة'
                              : 'Visa File Number'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // 🇦🇪 صَفّ MOHRE + Establishment File
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _mohreNumber,
                      decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'رَقم MOHRE الشَخصيّ'
                              : 'MOHRE Personal No.',
                          helperText: s.isAr
                              ? 'رَقم العامِل في وِزارة المَوارِد البَشَريّة'
                              : 'Worker ID at MOHRE',
                          helperMaxLines: 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _establishmentFileNumber,
                      decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'رَقم مِلَفّ المُنشَأة'
                              : 'Establishment File No.'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // 🇦🇪 صَفّ بِطاقة العَمَل (رَقم + انتِهاء)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _labourCardNumber,
                      decoration: InputDecoration(
                          labelText: s.isAr
                              ? 'رَقم بِطاقة العَمَل'
                              : 'Labour Card No.'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.isAr
                          ? 'انتِهاء بِطاقة العَمَل'
                          : 'Labour Card Expiry',
                      value: _labourCardExpiry,
                      onPicked: (d) =>
                          setState(() => _labourCardExpiry = d),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // 🚗 WASL VIP UID (لِسائِقي النَقل)
                TextField(
                  controller: _waslUid,
                  decoration: InputDecoration(
                    labelText: s.isAr
                        ? 'رَقم WASL VIP UID'
                        : 'WASL VIP UID',
                    helperText: s.isAr
                        ? 'مَطلوب لِسائِقي خِدمات النَقل في الإمارات'
                        : 'Required for transport drivers in UAE',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.directions_car, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                M7MultiUploadBox(
                  label: s.idCardDoc,
                  hint: s.uploadIdCard,
                  icon: Icons.badge_outlined,
                  bucket: 'id_cards',
                  pathPrefix: 'emp_${widget.existing?.id ?? "new"}_idcard',
                  urls: [
                    if (_idCardFileId != null) _idCardFileId!,
                    ..._idCardFiles,
                  ],
                  onChanged: (list) => setState(() {
                    // أَوَّل عُنصُر يَبقى كَالمِلَفّ الرَئيسيّ (تَوافُق خَلفيّ)
                    if (list.isEmpty) {
                      _idCardFileId = null;
                      _idCardFiles = <String>[];
                    } else {
                      _idCardFileId = list.first;
                      _idCardFiles = list.skip(1).toList();
                    }
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ========= 3) LICENSE =========
          _SectionHeader(
              icon: Icons.card_membership_outlined, title: s.licenseInfo),
          SectionCard(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _licenseNumber,
                      decoration: InputDecoration(labelText: s.licenseNumber),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.licenseIssue,
                      value: _licenseIssue,
                      onPicked: (d) => setState(() => _licenseIssue = d),
                      pickFn: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: s.licenseExpiry,
                      value: _licenseExpiry,
                      onPicked: (d) => setState(() => _licenseExpiry = d),
                      pickFn: _pickDate,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                M7MultiUploadBox(
                  label: s.licenseDoc,
                  hint: s.uploadLicense,
                  icon: Icons.upload_file_outlined,
                  bucket: 'licenses',
                  pathPrefix: 'emp_${widget.existing?.id ?? "new"}_license',
                  urls: [
                    if (_licenseFileId != null) _licenseFileId!,
                    ..._licenseFiles,
                  ],
                  onChanged: (list) => setState(() {
                    if (list.isEmpty) {
                      _licenseFileId = null;
                      _licenseFiles = <String>[];
                    } else {
                      _licenseFileId = list.first;
                      _licenseFiles = list.skip(1).toList();
                    }
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ========= 4) FINANCIAL =========
          _SectionHeader(
              icon: Icons.payments_outlined, title: s.financialInfo),
          SectionCard(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _basicSalary,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.basicSalary),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _overtime,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.overtime),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _trainingFee,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.trainingFee),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _others,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.others),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _iban,
                  decoration: InputDecoration(labelText: s.iban),
                ),
                const SizedBox(height: 14),
                // 🆕 البَدَلات الإضافيّة (تُحسَب لاحِقاً في المُستَحَقّات)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.purple.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.account_balance_wallet,
                              size: 18, color: AppColors.purple),
                          SizedBox(width: 6),
                          Text('💰 البَدَلات الإضافيّة',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _housingAllowance,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '🏠 بَدَل سَكَن',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _transportAllowance,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '🚌 بَدَل مُواصَلات',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otherAllowances,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '✨ بَدَلات أُخرى',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 🎫 تَذكِرة السَفَر (حَسَب قانون العَمَل)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _eligibleForTicket
                        ? AppColors.success.withOpacity(0.05)
                        : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _eligibleForTicket
                            ? AppColors.success.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.flight,
                            color: AppColors.success),
                        title: const Text(
                          '✈ يَستَحِقّ تَذكِرة سَفَر',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'لَيس كُلّ المُوَظَّفين يَستَحِقّون تَذكِرة',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        value: _eligibleForTicket,
                        onChanged: (v) =>
                            setState(() => _eligibleForTicket = v),
                      ),
                      if (_eligibleForTicket)
                        TextField(
                          controller: _ticketAmount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '💵 مَبلَغ التَذكِرة',
                            isDense: true,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Total Salary card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calculate_outlined,
                          color: AppColors.brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.totalSalary,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800)),
                            Text(s.totalSalaryHint,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).disabledColor)),
                          ],
                        ),
                      ),
                      Text(
                        _totalSalary.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _DateField(
                  label: s.workLetterDate,
                  value: _workLetterDate,
                  onPicked: (d) => setState(() => _workLetterDate = d),
                  pickFn: _pickDate,
                ),
                const SizedBox(height: 10),
                M7MultiUploadBox(
                  label: s.workLetter,
                  hint: s.uploadWorkLetter,
                  icon: Icons.description_outlined,
                  bucket: 'work_letters',
                  pathPrefix:
                      'emp_${widget.existing?.id ?? "new"}_workletter',
                  urls: [
                    if (_workLetterFileId != null) _workLetterFileId!,
                    ..._workLetterFiles,
                  ],
                  onChanged: (list) => setState(() {
                    if (list.isEmpty) {
                      _workLetterFileId = null;
                      _workLetterFiles = <String>[];
                    } else {
                      _workLetterFileId = list.first;
                      _workLetterFiles = list.skip(1).toList();
                    }
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ========= 5) EMERGENCY & ADDITIONAL =========
          _SectionHeader(
              icon: Icons.emergency_outlined,
              title: s.emergencyAdditional),
          SectionCard(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _emergencyName,
                      decoration:
                          InputDecoration(labelText: s.emergencyContactName2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _emergencyPhone,
                      keyboardType: TextInputType.phone,
                      decoration:
                          InputDecoration(labelText: s.emergencyContactPhone2),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _education,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.education),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              isEdit ? s.save : (s.isAr ? ar2ur.tr('حفظ الموظف') : 'Save Employee'),
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============================================================
// Helper widgets
// ============================================================

/// 📄 بِطاقة وَثائِق الموظَّف — تَفتَح شاشة إصدارات الوَثائِق
class _DocumentsLinkCard extends StatelessWidget {
  final Employee employee;
  final bool isAr;
  const _DocumentsLinkCard({
    required this.employee,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              EmployeeDocumentsScreen(employee: employee),
        ));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppColors.info.withOpacity(0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.folder_special,
                  color: AppColors.info, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr
                        ? '📄 وَثائِق الموظَّف (إصدارات)'
                        : '📄 Employee Documents (Versions)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAr
                        ? 'هَوِيّة، جَواز، رُخصة، تَأشيرة، شَهادات…'
                        : 'ID, passport, license, visa, certificates…',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.info),
          ],
        ),
      ),
    );
  }
}

// 💡 _FaceEnrollmentCard أُزيل — البَصمة تُدار حَصراً مِن شاشة المُستَخدِمين
// راجِع: features/admin/admin_users.dart → _UserFaceEnrollmentCard

/// 🏠 حقل السكن (في الكمب / خارج الكمب) كبطاقة بصريّة
class _HousingField extends StatelessWidget {
  final HousingType value;
  final ValueChanged<HousingType> onChanged;
  final bool isAr;
  const _HousingField({
    required this.value,
    required this.onChanged,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.home_outlined,
                  color: AppColors.brand, size: 16),
              const SizedBox(width: 6),
              Text(
                isAr ? ar2ur.tr('السكن') : 'Housing',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? '— يحدّد الظهور في شاشات الكمب أو خطّة الباصات'
                      : '— controls camp vs bus assignments',
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HousingOption(
                  selected: value == HousingType.onCamp,
                  icon: Icons.holiday_village,
                  color: AppColors.success,
                  label:
                      isAr ? HousingType.onCamp.arabicLabel() : HousingType.onCamp.englishLabel(),
                  helper: isAr
                      ? 'يظهر في الغرف، اليونيفورم، الغسيل'
                      : 'Shown in rooms, uniform, laundry',
                  onTap: () => onChanged(HousingType.onCamp),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HousingOption(
                  selected: value == HousingType.offCamp,
                  icon: Icons.directions_bus,
                  color: AppColors.warning,
                  label: isAr
                      ? HousingType.offCamp.arabicLabel()
                      : HousingType.offCamp.englishLabel(),
                  helper: isAr
                      ? 'يحتاج توصيلاً (يظهر في خطّة الباص)'
                      : 'Needs transport (shown in bus plan)',
                  onTap: () => onChanged(HousingType.offCamp),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HousingOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String label;
  final String helper;
  final VoidCallback onTap;
  const _HousingOption({
    required this.selected,
    required this.icon,
    required this.color,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: selected ? color : Theme.of(context).disabledColor,
                    size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? color : null,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: color, size: 16),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              helper,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🎓 حقل نوع التحاق الموظف (متدرّب / محترف)
class _HireTypeField extends StatelessWidget {
  final EmployeeHireType value;
  final ValueChanged<EmployeeHireType> onChanged;
  final bool isAr;
  const _HireTypeField({
    required this.value,
    required this.onChanged,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined,
                  color: AppColors.warning, size: 16),
              const SizedBox(width: 6),
              Text(
                isAr ? ar2ur.tr('نوع الالتحاق') : 'Hire Type',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? '— المتدرّب يدخل تلقائيّاً صفحة التدريب (HR)'
                      : '— Trainees auto-appear in HR Training page',
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HireOption(
                  selected: value == EmployeeHireType.trainee,
                  icon: Icons.psychology_alt_outlined,
                  color: AppColors.warning,
                  label: isAr
                      ? EmployeeHireType.trainee.arabicLabel()
                      : EmployeeHireType.trainee.englishLabel(),
                  helper: isAr
                      ? '٧ أيّام تدريب على نقطة قبل الاعتماد'
                      : '7 days OnPoint training first',
                  onTap: () => onChanged(EmployeeHireType.trainee),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HireOption(
                  selected: value == EmployeeHireType.professional,
                  icon: Icons.workspace_premium_outlined,
                  color: AppColors.success,
                  label: isAr
                      ? EmployeeHireType.professional.arabicLabel()
                      : EmployeeHireType.professional.englishLabel(),
                  helper: isAr
                      ? 'يبدأ مباشرةً بدون تدريب'
                      : 'Starts immediately, no training',
                  onTap: () => onChanged(EmployeeHireType.professional),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HireOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String label;
  final String helper;
  final VoidCallback onTap;
  const _HireOption({
    required this.selected,
    required this.icon,
    required this.color,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: selected ? color : Theme.of(context).disabledColor,
                    size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? color : null,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: color, size: 16),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              helper,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 👕 حقل مقاسات اليونيفورم (3 خانات)
class _UniformSizesField extends StatelessWidget {
  final TextEditingController shirtCtrl;
  final TextEditingController pantCtrl;
  final TextEditingController shoeCtrl;
  final bool isAr;
  const _UniformSizesField({
    required this.shirtCtrl,
    required this.pantCtrl,
    required this.shoeCtrl,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.checkroom,
                  color: AppColors.info, size: 16),
              const SizedBox(width: 6),
              Text(
                isAr ? ar2ur.tr('مقاسات اليونيفورم') : 'Uniform Sizes',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.info),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: shirtCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? ar2ur.tr('مقاس القميص') : 'Shirt',
                    hintText: 'M / L / XL',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: pantCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? ar2ur.tr('مقاس البنطلون') : 'Pant',
                    hintText: '32 / 34',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: shoeCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? ar2ur.tr('مقاس الحذاء') : 'Shoe',
                    hintText: '42 / 9',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 🚌 حقل اختيار الباص الافتراضي للموظّف
class _DefaultBusField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool isAr;
  const _DefaultBusField({
    required this.value,
    required this.onChanged,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final buses = repo.buses
        .where((b) => b.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final brand = AppColors.success;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: brand.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: brand.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.directions_bus_outlined, color: brand, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr ? ar2ur.tr('الباص الافتراضي') : 'Default Bus',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: brand),
                ),
              ),
              if (value != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: isAr ? ar2ur.tr('مسح') : 'Clear',
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              hintText: isAr ? ar2ur.tr('اختر باصاً (اختياري)') : 'Pick a bus (optional)',
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(isAr ? ar2ur.tr('— لا يوجد —') : '— None —'),
              ),
              ...buses.map((b) => DropdownMenuItem(
                    value: b.id,
                    child: Text(
                      '${b.name} • ${b.plateNumber}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: onChanged,
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'يُستخدم في خطّة الباصات اليوميّة. يمكن تجاوزه ليوم محدّد.'
                : 'Used in daily bus plan. Can be overridden per day.',
            style: TextStyle(
              fontSize: 10.5,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// 🆕 حوار معاينة الاستيراد الجماعي
/// يعرض الصفوف المحلَّلة من الملف، يُبيّن أيّها صالح/فيه مشاكل/مكرّر،
/// ثمّ يُتيح للمستخدم تأكيد الإضافة (للصفوف الصالحة فقط).
class _BulkImportPreviewDialog extends StatefulWidget {
  final List<ParsedEmployeeRow> rows;
  final bool isAr;
  const _BulkImportPreviewDialog({
    required this.rows,
    required this.isAr,
  });

  @override
  State<_BulkImportPreviewDialog> createState() =>
      _BulkImportPreviewDialogState();
}

class _BulkImportPreviewDialogState extends State<_BulkImportPreviewDialog> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    // افتراضياً: حدّد كل الصفوف الصالحة وغير المكرّرة
    _selected = widget.rows
        .where((r) => r.isValid && !r.isUpdate)
        .map((r) => r.rowNumber)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final theme = Theme.of(context);
    final total = widget.rows.length;
    final valid = widget.rows.where((r) => r.isValid).length;
    final invalid = total - valid;
    final duplicates = widget.rows.where((r) => r.isUpdate).length;
    final selectedCount = _selected.length;

    return Dialog(
      child: Container(
        width: 720,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الهيدر
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.file_upload_outlined,
                      color: AppColors.brand, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'معاينة الاستيراد ($total صفوف)'
                          : 'Import Preview ($total rows)',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // ملخّص
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  _PreviewSummary(
                      label: isAr ? ar2ur.tr('صالح') : 'Valid',
                      value: valid,
                      color: AppColors.success),
                  const SizedBox(width: 6),
                  _PreviewSummary(
                      label: isAr ? ar2ur.tr('مكرّر (تجاوز)') : 'Duplicate (skip)',
                      value: duplicates,
                      color: AppColors.warning),
                  const SizedBox(width: 6),
                  _PreviewSummary(
                      label: isAr ? ar2ur.tr('مشاكل') : 'Issues',
                      value: invalid,
                      color: AppColors.danger),
                  const Spacer(),
                  Text(
                    isAr
                        ? 'محدّد: $selectedCount'
                        : 'Selected: $selectedCount',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // قائمة الصفوف
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = widget.rows[i];
                  final canSelect = r.isValid && !r.isUpdate;
                  final selected = _selected.contains(r.rowNumber);
                  Color rowColor;
                  String statusLabel;
                  Color statusColor;
                  if (r.isUpdate) {
                    rowColor = AppColors.warning.withOpacity(0.05);
                    statusLabel = isAr ? ar2ur.tr('موجود — تجاوز') : 'Exists — skip';
                    statusColor = AppColors.warning;
                  } else if (!r.isValid) {
                    rowColor = AppColors.danger.withOpacity(0.05);
                    statusLabel = isAr ? ar2ur.tr('مشاكل') : 'Issues';
                    statusColor = AppColors.danger;
                  } else {
                    rowColor = Colors.transparent;
                    statusLabel = isAr ? ar2ur.tr('جديد') : 'New';
                    statusColor = AppColors.success;
                  }
                  return Container(
                    color: rowColor,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: !canSelect
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(r.rowNumber);
                                    } else {
                                      _selected.remove(r.rowNumber);
                                    }
                                  });
                                },
                        ),
                        SizedBox(
                          width: 30,
                          child: Text('${r.rowNumber}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.employee.fullName.isEmpty
                                    ? '—'
                                    : r.employee.fullName,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                [
                                  if (r.employee.code.isNotEmpty)
                                    r.employee.code,
                                  if (r.employee.jobTitle.isNotEmpty)
                                    r.employee.jobTitle,
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: theme.textTheme.bodySmall?.color),
                              ),
                              if (r.issues.isNotEmpty)
                                Text(
                                  r.issues.join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: statusColor.withOpacity(0.4)),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // الأزرار
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(isAr ? ar2ur.tr('إلغاء') : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () {
                              final approved = widget.rows
                                  .where((r) => _selected.contains(r.rowNumber))
                                  .toList();
                              Navigator.of(context).pop(approved);
                            },
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                        isAr
                            ? 'إضافة $selectedCount موظّف'
                            : 'Add $selectedCount employees',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PreviewSummary({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 🖼️ صندوق رفع الصور — يفتح كاميرا/معرض ويرفع لـ Supabase Storage
class _UploadBox extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool hasFile;
  /// bucket في Supabase Storage (مثل: employee_photos, id_cards, licenses)
  final String bucket;
  /// مفتاح بادئة لاسم الملف (مثل: emp_${id})
  final String? pathPrefix;
  /// callback عند نجاح الرفع → fileId يُحفظ في DB
  final ValueChanged<String>? onUploaded;
  /// URL لعرض الصورة الموجودة (لو فيه)
  final String? existingUrl;

  const _UploadBox({
    required this.label,
    required this.hint,
    required this.icon,
    required this.hasFile,
    this.bucket = 'employee_photos',
    this.pathPrefix,
    this.onUploaded,
    this.existingUrl,
  });

  @override
  State<_UploadBox> createState() => _UploadBoxState();
}

class _UploadBoxState extends State<_UploadBox> {
  Uint8List? _previewBytes;
  String? _previewUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _previewUrl = widget.existingUrl;
  }

  Future<void> _pick() async {
    setState(() => _uploading = true);
    final result = await ImagePickerService.pickAndUpload(
      context: context,
      bucket: widget.bucket,
      pathPrefix: widget.pathPrefix,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result == null) {
      // قد يكون الإلغاء أو فشل الرفع — نُظهر آخر خطأ
      final err = SupabaseDataService().lastError;
      if (err != null && err.contains('Bucket')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 6),
          content: Text(
            AppStrings.of(context).isAr
                ? '⚠️ Bucket "${widget.bucket}" غير موجود في Supabase Storage. شغّل setup_storage_buckets.sql أوّلاً.'
                : '⚠️ Bucket "${widget.bucket}" missing. Run setup_storage_buckets.sql first.',
          ),
        ));
      }
      return;
    }
    setState(() {
      _previewBytes = result.bytes;
      _previewUrl = result.url;
    });
    // 🆕 نحفظ الـ URL فقط لو فعلاً نجح الرفع وحصلنا على URL صحيح
    // (لو لم تكن hosted، نتجنّب حفظ filename فقط — يُظهر initials)
    if (widget.onUploaded != null && result.url != null) {
      widget.onUploaded!(result.url!);
    }
    if (mounted && result.url != null) {
      // ignore: avoid_print
      M7Log.info('Employees', 'uploaded URL: ${result.url}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 5),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.of(context).isAr
                ? '✅ تمّ رفع الصورة'
                : '✅ Image uploaded'),
            Text(
              result.url!,
              style: const TextStyle(fontSize: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'فتح',
          textColor: Colors.white,
          onPressed: () {
            // فقط ينسخ الرابط للحافظة
          },
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final hasPreview = _previewBytes != null || _previewUrl != null;

    return InkWell(
      onTap: _uploading ? null : _pick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.brand.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.brand.withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            // ===== المعاينة أو الأيقونة =====
            if (hasPreview)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 80,
                  child: _previewBytes != null
                      ? Image.memory(
                          _previewBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(widget.icon,
                                  color: AppColors.brand, size: 28),
                        )
                      : Image.network(
                          _previewUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(widget.icon,
                                  color: AppColors.brand, size: 28),
                        ),
                ),
              )
            else
              Icon(widget.icon, color: AppColors.brand, size: 28),
            const SizedBox(height: 6),
            Text(widget.label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            Text(widget.hint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pick,
              icon: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      (widget.hasFile || hasPreview)
                          ? Icons.check_circle
                          : Icons.photo_camera,
                      size: 16,
                    ),
              label: Text(
                _uploading
                    ? (s.isAr ? ar2ur.tr('جارٍ الرفع...') : 'Uploading...')
                    : (widget.hasFile || hasPreview)
                        ? (s.isAr ? ar2ur.tr('استبدال') : 'Replace')
                        : (s.isAr ? ar2ur.tr('كاميرا أو معرض') : 'Camera or Gallery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;
  final Future<void> Function(DateTime?, ValueChanged<DateTime>,
      {DateTime? first, DateTime? last}) pickFn;
  final DateTime? lastDate;
  final DateTime? firstDate;

  const _DateField({
    required this.label,
    required this.value,
    required this.onPicked,
    required this.pickFn,
    this.lastDate,
    this.firstDate,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(
      text: value == null
          ? ''
          : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}',
    );
    return GestureDetector(
      onTap: () =>
          pickFn(value, onPicked, first: firstDate, last: lastDate),
      child: AbsorbPointer(
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'dd/mm/yyyy',
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
        ),
      ),
    );
  }
}
