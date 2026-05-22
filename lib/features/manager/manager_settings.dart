import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'manager_numbering.dart';

/// شاشة الإعدادات - إدارة القوائم المرجعية:
/// - الدول
/// - المناطق/المحافظات (مرتبطة بالدول)
/// - المدن (مرتبطة بالدول)
/// - الأحياء (مرتبطة بالمدن)
/// - أنواع الأنشطة (مستقلة)
class ManagerSettings extends StatefulWidget {
  const ManagerSettings({super.key});

  @override
  State<ManagerSettings> createState() => _ManagerSettingsState();
}

class _ManagerSettingsState extends State<ManagerSettings>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 9, vsync: this);
    // 9 = نظام الترقيم + 3 جغرافي (Cities/Areas/BusinessTypes) + 5 lookups بسيطة
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // ملاحظة: لا نضع AppBar هنا - الـparent (SettingsHubScreen) يُوَفِّر Scaffold + AppBar
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.brand,
            unselectedLabelColor: Theme.of(context).disabledColor,
            indicatorColor: AppColors.brand,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.all(
                AppColors.brand.withValues(alpha: 0.05)),
            tabs: [
              Tab(text: s.numberingSystem),
              Tab(text: s.cities),
              Tab(text: s.areasList),
              Tab(text: s.businessTypes),
              Tab(text: s.jobTitles),
              Tab(text: s.departments),
              Tab(text: s.maritalStatuses),
              Tab(text: s.nationalities),
              Tab(text: s.visaTypes),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              ManagerNumbering(),
              _CitiesTab(),
              _AreasTab(),
              _BusinessTypesTab(),
              _SimpleListTab(type: _SimpleListType.jobTitle),
              _SimpleListTab(type: _SimpleListType.department),
              _SimpleListTab(type: _SimpleListType.maritalStatus),
              _SimpleListTab(type: _SimpleListType.nationality),
              _SimpleListTab(type: _SimpleListType.visaType),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Cities Tab
// ============================================================
class _CitiesTab extends StatefulWidget {
  const _CitiesTab();
  @override
  State<_CitiesTab> createState() => _CitiesTabState();
}

class _CitiesTabState extends State<_CitiesTab> {
  String? _filterCountry;

  @override
  void initState() {
    super.initState();
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
    final list = _filterCountry == null
        ? repo.cities
        : repo.citiesOfCountry(_filterCountry!);

    return Scaffold(
      body: Column(
        children: [
          _CountryFilter(
            value: _filterCountry,
            onChanged: (v) => setState(() => _filterCountry = v),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(message: s.noData, icon: Icons.location_on)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final country = repo.countryById(c.countryId);
                      final areaCount = repo.areasOfCity(c.id).length;
                      return _LookupCard(
                        icon: Icons.location_on,
                        color: AppColors.warning,
                        title: c.displayName(s.isAr),
                        subtitle:
                            '${country?.displayName(s.isAr) ?? "-"} • $areaCount ${s.areasList}',
                        onEdit: () =>
                            _showCityEditor(context, existing: c),
                        onDelete: () => _confirmDelete(
                          context,
                          name: c.displayName(s.isAr),
                          cascade: areaCount > 0,
                          onConfirm: () async {
                            if (SupabaseService().isReady) {
                              await SupabaseDataService().deleteCity(c.id);
                            } else {
                              repo.deleteCity(c.id);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCityEditor(context),
        icon: const Icon(Icons.add),
        label: Text('${s.add} ${s.city2}'),
      ),
    );
  }

  void _showCityEditor(BuildContext context, {City? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CityEditor(existing: existing),
    );
  }
}

class _CityEditor extends StatefulWidget {
  final City? existing;
  const _CityEditor({this.existing});
  @override
  State<_CityEditor> createState() => _CityEditorState();
}

class _CityEditorState extends State<_CityEditor> {
  late final TextEditingController _ar;
  late final TextEditingController _en;
  String? _countryId;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.existing?.nameAr ?? '');
    _en = TextEditingController(text: widget.existing?.nameEn ?? '');
    _countryId = widget.existing?.countryId;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return _SheetContainer(
      title: widget.existing == null
          ? '${s.add} ${s.city2}'
          : '${s.edit} ${s.city2}',
      onSave: () async {
        if (_countryId == null ||
            _ar.text.trim().isEmpty ||
            _en.text.trim().isEmpty) {
          return;
        }
        final supaReady = SupabaseService().isReady;
        if (widget.existing == null) {
          if (supaReady) {
            await SupabaseDataService().createCity(
              countryId: _countryId!,
              nameAr: _ar.text.trim(),
              nameEn: _en.text.trim(),
            );
          } else {
            repo.addCity(City(
              id: repo.generateId(),
              countryId: _countryId!,
              nameAr: _ar.text.trim(),
              nameEn: _en.text.trim(),
            ));
          }
        } else {
          final updated = City(
            id: widget.existing!.id,
            countryId: _countryId!,
            nameAr: _ar.text.trim(),
            nameEn: _en.text.trim(),
          );
          if (supaReady) {
            await SupabaseDataService().updateCity(updated);
            repo.updateCity(updated);
          } else {
            repo.updateCity(updated);
          }
        }
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      children: [
        DropdownButtonFormField<String>(
          value: _countryId,
          decoration: InputDecoration(labelText: s.country2),
          items: repo.countries
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.displayName(s.isAr)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _countryId = v),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _ar,
            decoration: InputDecoration(labelText: s.nameArabic)),
        const SizedBox(height: 10),
        TextField(
            controller: _en,
            decoration: InputDecoration(labelText: s.nameEnglish)),
      ],
    );
  }
}

// ============================================================
// 4) Areas Tab
// ============================================================
class _AreasTab extends StatefulWidget {
  const _AreasTab();
  @override
  State<_AreasTab> createState() => _AreasTabState();
}

class _AreasTabState extends State<_AreasTab> {
  String? _filterCountry;
  String? _filterCity;

  @override
  void initState() {
    super.initState();
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
    var list = repo.areas;
    if (_filterCity != null) {
      list = repo.areasOfCity(_filterCity!);
    } else if (_filterCountry != null) {
      list = repo.areasOfCountry(_filterCountry!);
    }

    return Scaffold(
      body: Column(
        children: [
          _CountryFilter(
            value: _filterCountry,
            onChanged: (v) => setState(() {
              _filterCountry = v;
              _filterCity = null;
            }),
          ),
          if (_filterCountry != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: DropdownButtonFormField<String?>(
                value: _filterCity,
                decoration: InputDecoration(
                  labelText: s.city2,
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(s.all)),
                  ...repo
                      .citiesOfCountry(_filterCountry!)
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.displayName(s.isAr)),
                          )),
                ],
                onChanged: (v) => setState(() => _filterCity = v),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(message: s.noData, icon: Icons.map)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final country = repo.countryById(a.countryId);
                      final city = repo.cityById(a.cityId);
                      return _LookupCard(
                        icon: Icons.map,
                        color: AppColors.teal,
                        title: a.displayName(s.isAr),
                        subtitle:
                            '${country?.displayName(s.isAr) ?? "-"} • ${city?.displayName(s.isAr) ?? "-"}',
                        onEdit: () =>
                            _showAreaEditor(context, existing: a),
                        onDelete: () => _confirmDelete(
                          context,
                          name: a.displayName(s.isAr),
                          onConfirm: () async {
                            if (SupabaseService().isReady) {
                              await SupabaseDataService().deleteArea(a.id);
                            } else {
                              repo.deleteArea(a.id);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAreaEditor(context),
        icon: const Icon(Icons.add),
        label: Text('${s.add} ${s.area}'),
      ),
    );
  }

  void _showAreaEditor(BuildContext context, {Area? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AreaEditor(existing: existing),
    );
  }
}

class _AreaEditor extends StatefulWidget {
  final Area? existing;
  const _AreaEditor({this.existing});
  @override
  State<_AreaEditor> createState() => _AreaEditorState();
}

class _AreaEditorState extends State<_AreaEditor> {
  late final TextEditingController _ar;
  late final TextEditingController _en;
  String? _countryId;
  String? _cityId;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.existing?.nameAr ?? '');
    _en = TextEditingController(text: widget.existing?.nameEn ?? '');
    _countryId = widget.existing?.countryId;
    _cityId = widget.existing?.cityId;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final availableCities =
        _countryId == null ? <City>[] : repo.citiesOfCountry(_countryId!);
    return _SheetContainer(
      title: widget.existing == null
          ? '${s.add} ${s.area}'
          : '${s.edit} ${s.area}',
      onSave: () async {
        if (_countryId == null ||
            _cityId == null ||
            _ar.text.trim().isEmpty ||
            _en.text.trim().isEmpty) {
          return;
        }
        final supaReady = SupabaseService().isReady;
        if (widget.existing == null) {
          if (supaReady) {
            await SupabaseDataService().createArea(
              cityId: _cityId!,
              nameAr: _ar.text.trim(),
              nameEn: _en.text.trim(),
            );
          } else {
            repo.addArea(Area(
              id: repo.generateId(),
              countryId: _countryId!,
              cityId: _cityId!,
              nameAr: _ar.text.trim(),
              nameEn: _en.text.trim(),
            ));
          }
        } else {
          widget.existing!.nameAr = _ar.text.trim();
          widget.existing!.nameEn = _en.text.trim();
          if (supaReady) {
            await SupabaseDataService().updateArea(widget.existing!);
            repo.updateArea(widget.existing!);
          } else {
            repo.updateArea(widget.existing!);
          }
        }
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      children: [
        DropdownButtonFormField<String>(
          value: _countryId,
          decoration: InputDecoration(labelText: s.country2),
          items: repo.countries
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.displayName(s.isAr)),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _countryId = v;
              _cityId = null;
            });
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _cityId,
          decoration: InputDecoration(
            labelText: s.city2,
            hintText: _countryId == null ? s.selectCountryFirst : null,
          ),
          items: availableCities
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.displayName(s.isAr)),
                  ))
              .toList(),
          onChanged: _countryId == null
              ? null
              : (v) => setState(() => _cityId = v),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _ar,
            decoration: InputDecoration(labelText: s.nameArabic)),
        const SizedBox(height: 10),
        TextField(
            controller: _en,
            decoration: InputDecoration(labelText: s.nameEnglish)),
      ],
    );
  }
}

// ============================================================
// 5) Business Types Tab
// ============================================================
class _BusinessTypesTab extends StatelessWidget {
  const _BusinessTypesTab();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return Scaffold(
      body: repo.businessTypes.isEmpty
          ? EmptyState(message: s.noData, icon: Icons.business)
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: repo.businessTypes.length,
              itemBuilder: (_, i) {
                final b = repo.businessTypes[i];
                return _LookupCard(
                  icon: Icons.business,
                  color: AppColors.success,
                  title: b.displayName(s.isAr),
                  subtitle: s.isAr ? b.nameEn : b.nameAr,
                  onEdit: () => _show(context, existing: b),
                  onDelete: () => _confirmDelete(
                    context,
                    name: b.displayName(s.isAr),
                    onConfirm: () => repo.deleteBusinessType(b.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _show(context),
        icon: const Icon(Icons.add),
        label: Text('${s.add} ${s.businessType2}'),
      ),
    );
  }

  void _show(BuildContext context, {BusinessType? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BusinessTypeEditor(existing: existing),
    );
  }
}

class _BusinessTypeEditor extends StatefulWidget {
  final BusinessType? existing;
  const _BusinessTypeEditor({this.existing});
  @override
  State<_BusinessTypeEditor> createState() =>
      _BusinessTypeEditorState();
}

class _BusinessTypeEditorState extends State<_BusinessTypeEditor> {
  late final TextEditingController _ar;
  late final TextEditingController _en;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.existing?.nameAr ?? '');
    _en = TextEditingController(text: widget.existing?.nameEn ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return _SheetContainer(
      title: widget.existing == null
          ? '${s.add} ${s.businessType2}'
          : '${s.edit} ${s.businessType2}',
      onSave: () {
        if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) return;
        final repo = MockRepository();
        if (widget.existing == null) {
          repo.addBusinessType(BusinessType(
            id: repo.generateId(),
            nameAr: _ar.text.trim(),
            nameEn: _en.text.trim(),
          ));
        } else {
          widget.existing!.nameAr = _ar.text.trim();
          widget.existing!.nameEn = _en.text.trim();
          repo.updateBusinessType(widget.existing!);
        }
        Navigator.of(context).pop();
      },
      children: [
        TextField(
            controller: _ar,
            decoration: InputDecoration(labelText: s.nameArabic)),
        const SizedBox(height: 10),
        TextField(
            controller: _en,
            decoration: InputDecoration(labelText: s.nameEnglish)),
      ],
    );
  }
}

// ============================================================
// Generic Simple-List Tab (Job Titles, Departments, Marital, Nationality, Visa Types)
// ============================================================
enum _SimpleListType {
  jobTitle, department, maritalStatus, nationality, visaType
}

class _SimpleListTab extends StatelessWidget {
  final _SimpleListType type;
  const _SimpleListTab({required this.type});

  String _typeLabel(AppStrings s) {
    switch (type) {
      case _SimpleListType.jobTitle:      return s.jobTitle2;
      case _SimpleListType.department:    return s.department2;
      case _SimpleListType.maritalStatus: return s.maritalStatus2;
      case _SimpleListType.nationality:   return s.nationality2;
      case _SimpleListType.visaType:      return s.visaType2;
    }
  }

  IconData _icon() {
    switch (type) {
      case _SimpleListType.jobTitle:      return Icons.work_outline;
      case _SimpleListType.department:    return Icons.business_center_outlined;
      case _SimpleListType.maritalStatus: return Icons.favorite_border;
      case _SimpleListType.nationality:   return Icons.flag_outlined;
      case _SimpleListType.visaType:      return Icons.card_membership;
    }
  }

  Color _color() {
    switch (type) {
      case _SimpleListType.jobTitle:      return AppColors.brand;
      case _SimpleListType.department:    return AppColors.purple;
      case _SimpleListType.maritalStatus: return AppColors.warning;
      case _SimpleListType.nationality:   return AppColors.teal;
      case _SimpleListType.visaType:      return AppColors.info;
    }
  }

  /// قائمة العناصر بصيغة (id, nameAr, nameEn, originalObject)
  List<_GenericItem> _items(MockRepository repo) {
    switch (type) {
      case _SimpleListType.jobTitle:
        return repo.jobTitles
            .map((j) => _GenericItem(j.id, j.nameAr, j.nameEn, j))
            .toList();
      case _SimpleListType.department:
        return repo.departments
            .map((d) => _GenericItem(d.id, d.nameAr, d.nameEn, d))
            .toList();
      case _SimpleListType.maritalStatus:
        return repo.maritalStatuses
            .map((m) => _GenericItem(m.id, m.nameAr, m.nameEn, m))
            .toList();
      case _SimpleListType.nationality:
        return repo.nationalities
            .map((n) => _GenericItem(n.id, n.nameAr, n.nameEn, n))
            .toList();
      case _SimpleListType.visaType:
        return repo.visaTypes
            .map((v) => _GenericItem(v.id, v.nameAr, v.nameEn, v))
            .toList();
    }
  }

  void _delete(MockRepository repo, String id) {
    switch (type) {
      case _SimpleListType.jobTitle:      repo.deleteJobTitle(id);     break;
      case _SimpleListType.department:    repo.deleteDepartment(id);   break;
      case _SimpleListType.maritalStatus: repo.deleteMaritalStatus(id);break;
      case _SimpleListType.nationality:   repo.deleteNationality(id);  break;
      case _SimpleListType.visaType:      repo.deleteVisaType(id);     break;
    }
  }

  void _showEditor(BuildContext context, {_GenericItem? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimpleListEditor(type: type, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final items = _items(repo);
    return Scaffold(
      body: items.isEmpty
          ? EmptyState(message: s.noData, icon: _icon())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                return _LookupCard(
                  icon: _icon(),
                  color: _color(),
                  title: s.isAr ? it.nameAr : it.nameEn,
                  subtitle: s.isAr ? it.nameEn : it.nameAr,
                  onEdit: () => _showEditor(context, existing: it),
                  onDelete: () => _confirmDelete(
                    context,
                    name: s.isAr ? it.nameAr : it.nameEn,
                    onConfirm: () => _delete(repo, it.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add),
        label: Text('${s.add} ${_typeLabel(s)}'),
      ),
    );
  }
}

class _GenericItem {
  final String id;
  final String nameAr;
  final String nameEn;
  final dynamic original;
  _GenericItem(this.id, this.nameAr, this.nameEn, this.original);
}

class _SimpleListEditor extends StatefulWidget {
  final _SimpleListType type;
  final _GenericItem? existing;
  const _SimpleListEditor({required this.type, this.existing});

  @override
  State<_SimpleListEditor> createState() => _SimpleListEditorState();
}

class _SimpleListEditorState extends State<_SimpleListEditor> {
  late final TextEditingController _ar;
  late final TextEditingController _en;
  // 🆕 الهيكل التنظيمي: للأقسام
  String? _parentId;
  // 🆕 الهيكل التنظيمي: للمسمّيات الوظيفيّة (multiple managers)
  final Set<String> _reportsToIds = {};
  String? _primaryReportsToId;
  // 🆕 Phase 2: حقول غنيّة للـ JobTitle
  String? _color;
  DashboardType _dashboardType = DashboardType.employee;
  int _approvalPower = 0;
  int _level = 0;
  bool _isSupervisor = false;
  // 🆕 تصنيف JobTitle — افتراضي operations بعد إلغاء worker
  JobTitleCategory _category = JobTitleCategory.operations;
  // 🆕 إظهار كلّ خيارات Dashboard أم الموصى بها فقط
  bool _showAllDashboards = false;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.existing?.nameAr ?? '');
    _en = TextEditingController(text: widget.existing?.nameEn ?? '');
    // قراءة قيم التسلسل من الكائن الأصلي إن وُجد
    final orig = widget.existing?.original;
    if (orig is Department) {
      _parentId = orig.parentId;
    } else if (orig is JobTitle) {
      _reportsToIds.addAll(orig.reportsToIds);
      _primaryReportsToId = orig.primaryReportsToId;
      _color = orig.color;
      _dashboardType = orig.dashboardType;
      _approvalPower = orig.approvalPower;
      _level = orig.level;
      _isSupervisor = orig.isSupervisor;
      _category = orig.category;
    }
  }

  /// 🆕 خيارات Dashboard الموصى بها حسب التصنيف
  /// - worker: ميدان فقط
  /// - admin: إداري + قياديّ
  /// - operations: عمليّاتي
  Set<DashboardType> _recommendedDashboards() {
    switch (_category) {
      case JobTitleCategory.worker:
        return {
          DashboardType.employee,
          DashboardType.driver,
          DashboardType.supervisor,
        };
      case JobTitleCategory.admin:
        return {
          DashboardType.manager,
          DashboardType.hr,
          DashboardType.finance,
          DashboardType.supervisor,
        };
      case JobTitleCategory.operations:
        return {
          DashboardType.manager,
          DashboardType.supervisor,
          DashboardType.operations,
          DashboardType.employee,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    String typeLabel() {
      switch (widget.type) {
        case _SimpleListType.jobTitle:      return s.jobTitle2;
        case _SimpleListType.department:    return s.department2;
        case _SimpleListType.maritalStatus: return s.maritalStatus2;
        case _SimpleListType.nationality:   return s.nationality2;
        case _SimpleListType.visaType:      return s.visaType2;
      }
    }

    return _SheetContainer(
      title: widget.existing == null
          ? '${s.add} ${typeLabel()}'
          : '${s.edit} ${typeLabel()}',
      onSave: () {
        if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) return;
        final repo = MockRepository();
        final ar = _ar.text.trim();
        final en = _en.text.trim();

        if (widget.existing == null) {
          // إضافة جديد
          switch (widget.type) {
            case _SimpleListType.jobTitle:
              repo.addJobTitle(JobTitle(
                id: repo.generateId(),
                nameAr: ar,
                nameEn: en,
                category: _category,
                level: _level,
                isSupervisor: _isSupervisor,
                reportsToIds: _reportsToIds.toList(),
                primaryReportsToId: _primaryReportsToId,
                color: _color,
                dashboardType: _dashboardType,
                approvalPower: _approvalPower,
              ));
              break;
            case _SimpleListType.department:
              repo.addDepartment(Department(
                id: repo.generateId(),
                nameAr: ar,
                nameEn: en,
                parentId: _parentId,
              ));
              break;
            case _SimpleListType.maritalStatus:
              repo.addMaritalStatus(MaritalStatusItem(id: repo.generateId(), nameAr: ar, nameEn: en));
              break;
            case _SimpleListType.nationality:
              repo.addNationality(Nationality(id: repo.generateId(), nameAr: ar, nameEn: en));
              break;
            case _SimpleListType.visaType:
              repo.addVisaType(VisaType(id: repo.generateId(), nameAr: ar, nameEn: en));
              break;
          }
        } else {
          // تعديل
          final orig = widget.existing!.original;
          switch (widget.type) {
            case _SimpleListType.jobTitle:
              (orig as JobTitle).nameAr = ar;
              orig.nameEn = en;
              orig.category = _category;
              orig.level = _level;
              orig.isSupervisor = _isSupervisor;
              orig.reportsToIds
                ..clear()
                ..addAll(_reportsToIds);
              orig.primaryReportsToId = _primaryReportsToId;
              orig.color = _color;
              orig.dashboardType = _dashboardType;
              orig.approvalPower = _approvalPower;
              repo.updateJobTitle(orig);
              break;
            case _SimpleListType.department:
              (orig as Department).nameAr = ar;
              orig.nameEn = en;
              orig.parentId = _parentId;
              repo.updateDepartment(orig);
              break;
            case _SimpleListType.maritalStatus:
              (orig as MaritalStatusItem).nameAr = ar; orig.nameEn = en;
              repo.updateMaritalStatus(orig);
              break;
            case _SimpleListType.nationality:
              (orig as Nationality).nameAr = ar; orig.nameEn = en;
              repo.updateNationality(orig);
              break;
            case _SimpleListType.visaType:
              (orig as VisaType).nameAr = ar; orig.nameEn = en;
              repo.updateVisaType(orig);
              break;
          }
        }
        Navigator.of(context).pop();
      },
      children: [
        TextField(
            controller: _ar,
            decoration: InputDecoration(labelText: s.nameArabic)),
        const SizedBox(height: 10),
        TextField(
            controller: _en,
            decoration: InputDecoration(labelText: s.nameEnglish)),

        // ===== 🆕 Phase 2: حقول غنيّة للـ JobTitle =====
        if (widget.type == _SimpleListType.jobTitle) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            s.isAr ? 'إعدادات الدور' : 'Role Settings',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),

          // 🆕 Session 11: شريط اقتراحات ذكيّة (يظهر فقط عند وجود اقتراح)
          _SmartSuggestionsBanner(
            level: _level,
            isSupervisor: _isSupervisor,
            dashboardType: _dashboardType,
            approvalPower: _approvalPower,
            reportsToCount: _reportsToIds.length,
            existingRoleId:
                widget.existing?.original is JobTitle
                    ? (widget.existing!.original as JobTitle).roleId
                    : null,
            onApplySupervisor: () {
              setState(() {
                _isSupervisor = true;
              });
            },
            onApplyManagerLevel: () {
              setState(() {
                _level = 3;
              });
            },
            onClearSupervisor: () {
              setState(() {
                _isSupervisor = false;
              });
            },
          ),
          const SizedBox(height: 12),

          // Level (1..5)
          _LevelSelector(
            value: _level,
            label: s.isAr ? 'المستوى الهرمي' : 'Hierarchy Level',
            onChanged: (v) => setState(() => _level = v),
          ),
          const SizedBox(height: 12),

          // Is Supervisor
          SwitchListTile.adaptive(
            value: _isSupervisor,
            onChanged: (v) => setState(() => _isSupervisor = v),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              s.isAr ? 'مشرف (يستطيع إدارة فريق)' : 'Supervisor (manages a team)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              s.isAr
                  ? 'يظهر في قائمة المسمّيات المتاحة كمدير'
                  : 'Appears in available manager list',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(height: 12),

          // 🆕 تصنيف JobTitle (worker/admin/operations)
          DropdownButtonFormField<JobTitleCategory>(
            value: _category,
            decoration: InputDecoration(
              labelText: s.isAr ? 'تصنيف المسمّى' : 'Title Category',
              prefixIcon: const Icon(Icons.category_outlined, size: 18),
              isDense: true,
              helperText: s.isAr
                  ? 'يحدّد الـ Dashboards الموصى بها أدناه'
                  : 'Determines recommended dashboards below',
              helperStyle: const TextStyle(fontSize: 10),
            ),
            items: [
              DropdownMenuItem(
                value: JobTitleCategory.operations,
                child: Text(s.isAr ? '⚙️ عمليّات' : '⚙️ Operations'),
              ),
              DropdownMenuItem(
                value: JobTitleCategory.admin,
                child: Text(s.isAr ? '💼 إداري' : '💼 Admin'),
              ),
              // worker: مخفي بعد إلغاء قاعدة الترقيم — مرحَّل لـ operations
            ],
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: 12),

          // 🆕 Dashboard Type — مفلتر حسب التصنيف
          Builder(builder: (_) {
            final recommended = _recommendedDashboards();
            final visibleOptions = _showAllDashboards
                ? DashboardType.values
                : DashboardType.values
                    .where(recommended.contains)
                    .toList();
            // إن كانت القيمة الحاليّة خارج القائمة المعروضة، أَضِفها
            if (!visibleOptions.contains(_dashboardType)) {
              visibleOptions.add(_dashboardType);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<DashboardType>(
                  value: _dashboardType,
                  decoration: InputDecoration(
                    labelText:
                        s.isAr ? 'نوع لوحة التحكم' : 'Dashboard Type',
                    prefixIcon:
                        const Icon(Icons.dashboard_outlined, size: 18),
                    isDense: true,
                  ),
                  items: visibleOptions.map((d) {
                    final isRec = recommended.contains(d);
                    return DropdownMenuItem(
                      value: d,
                      child: Row(
                        children: [
                          Text(d.label(s.isAr)),
                          if (isRec) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.star,
                                size: 12, color: AppColors.gold),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _dashboardType = v);
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 11, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _showAllDashboards
                            ? (s.isAr
                                ? 'يُعرض الكلّ — ⭐ موصى به للتصنيف المختار'
                                : 'Showing all — ⭐ recommended for category')
                            : (s.isAr
                                ? 'يُعرض الموصى به فقط للتصنيف المختار'
                                : 'Showing recommended only'),
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[700]),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(
                          () => _showAllDashboards = !_showAllDashboards),
                      child: Text(
                        _showAllDashboards
                            ? (s.isAr ? 'عرض الموصى به' : 'Show recommended')
                            : (s.isAr ? 'عرض الكلّ' : 'Show all'),
                        style: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
          const SizedBox(height: 12),

          // Approval Power (0..5)
          _ApprovalPowerSelector(
            value: _approvalPower,
            label: s.isAr ? 'قوّة الموافقات' : 'Approval Power',
            onChanged: (v) => setState(() => _approvalPower = v),
          ),
          const SizedBox(height: 12),

          // Color picker (preset palette)
          _ColorPalettePicker(
            value: _color,
            label: s.isAr ? 'لون الواجهة' : 'UI Color',
            onChanged: (v) => setState(() => _color = v),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 🆕 Phase 2: مكوّنات مساعدة لمحرّر JobTitle
// ============================================================

/// 🆕 Session 11: شريط اقتراحات ذكيّة
///
/// يفحص حالة الحقول ويعرض اقتراحات قابلة للتطبيق بنقرة:
///   - dashboard مدير لكنّ المستوى عالٍ (5) → اقترح خفض المستوى
///   - approvalPower > 0 لكنّ is_supervisor = false → اقترح تفعيل المشرف
///   - is_supervisor = true لكن لا يوجد role → تحذير
///   - level > 1 لكنّ reports_to فارغ → اقترح إضافة مدير
///   - dashboard supervisor/manager لكنّ approvalPower = 0 → اقترح رفعها
class _SmartSuggestionsBanner extends StatelessWidget {
  final int level;
  final bool isSupervisor;
  final DashboardType dashboardType;
  final int approvalPower;
  final int reportsToCount;
  final String? existingRoleId;
  final VoidCallback onApplySupervisor;
  final VoidCallback onApplyManagerLevel;
  final VoidCallback onClearSupervisor;

  const _SmartSuggestionsBanner({
    required this.level,
    required this.isSupervisor,
    required this.dashboardType,
    required this.approvalPower,
    required this.reportsToCount,
    required this.existingRoleId,
    required this.onApplySupervisor,
    required this.onApplyManagerLevel,
    required this.onClearSupervisor,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final suggestions = _detect(isAr);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 14, color: AppColors.info),
                const SizedBox(width: 4),
                Text(
                  isAr
                      ? 'اقتراحات (${suggestions.length})'
                      : 'Suggestions (${suggestions.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.info,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          for (final sug in suggestions) _suggestionRow(sug, isAr),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _suggestionRow(_Suggestion sug, bool isAr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(sug.icon, size: 13, color: sug.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              sug.message,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (sug.action != null && sug.actionLabel != null) ...[
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: sug.action,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sug.color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sug.actionLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_Suggestion> _detect(bool isAr) {
    final list = <_Suggestion>[];

    // مدير قياديّ بمستوى عالٍ (5)
    if ((dashboardType == DashboardType.manager ||
            dashboardType == DashboardType.hr ||
            dashboardType == DashboardType.finance) &&
        level == 5) {
      list.add(_Suggestion(
        icon: Icons.trending_up,
        color: AppColors.warning,
        message: isAr
            ? 'دور قياديّ بمستوى ميدانيّ (L5) — رفع للمستوى L3؟'
            : 'Leadership dashboard with field level (L5) — raise to L3?',
        actionLabel: isAr ? 'L3' : 'L3',
        action: onApplyManagerLevel,
      ));
    }

    // approvalPower > 0 لكن غير مشرف
    if (approvalPower > 0 && !isSupervisor) {
      list.add(_Suggestion(
        icon: Icons.supervisor_account_outlined,
        color: AppColors.brand,
        message: isAr
            ? 'لديه قوّة موافقات لكن غير مشرف — تفعيل؟'
            : 'Has approval power but not supervisor — enable?',
        actionLabel: isAr ? 'فعّل' : 'Enable',
        action: onApplySupervisor,
      ));
    }

    // مشرف بقوّة 0
    if (isSupervisor && approvalPower == 0) {
      list.add(_Suggestion(
        icon: Icons.warning_amber_outlined,
        color: AppColors.danger,
        message: isAr
            ? 'مشرف بقوّة موافقات صفر — لن يستطيع الموافقة'
            : 'Supervisor with 0 approval power — won\'t be able to approve',
      ));
    }

    // dashboard supervisor/manager لكن قوّة 0
    if ((dashboardType == DashboardType.supervisor ||
            dashboardType == DashboardType.manager) &&
        approvalPower == 0) {
      list.add(_Suggestion(
        icon: Icons.shield_outlined,
        color: AppColors.warning,
        message: isAr
            ? 'لوحة "${dashboardType.label(true)}" تتوقّع قوّة موافقات > 0'
            : '${dashboardType.label(false)} dashboard expects approval power > 0',
      ));
    }

    // dashboard employee لكن مشرف
    if (dashboardType == DashboardType.employee && isSupervisor) {
      list.add(_Suggestion(
        icon: Icons.dashboard_outlined,
        color: AppColors.warning,
        message: isAr
            ? 'مشرف بلوحة "موظف" — يُفضّل تغييرها إلى "مشرف"'
            : 'Supervisor with Employee dashboard — switch to Supervisor?',
      ));
    }

    // is_supervisor = true لكن لا role
    if (isSupervisor && existingRoleId == null) {
      list.add(_Suggestion(
        icon: Icons.link_off,
        color: AppColors.warning,
        message: isAr
            ? 'مشرف بدون دور مرتبط — لن تكون له صلاحيّات'
            : 'Supervisor without linked role — will have no permissions',
      ));
    }

    // مستوى > 1 لكن لا reports_to
    if (level > 1 && reportsToCount == 0) {
      list.add(_Suggestion(
        icon: Icons.account_tree_outlined,
        color: AppColors.info,
        message: isAr
            ? 'مستوى L$level بدون مدير — أضِف "يتبع لـ"'
            : 'Level L$level with no manager — add reports-to',
      ));
    }

    return list;
  }
}

class _Suggestion {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? action;
  _Suggestion({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.action,
  });
}

class _LevelSelector extends StatelessWidget {
  final int value;
  final String label;
  final ValueChanged<int> onChanged;
  const _LevelSelector({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  static const _levelColors = {
    0: Color(0xFF94A3B8), // unset / general
    1: Color(0xFF1A1A1A), // C-Level
    2: Color(0xFF374151), // Director
    3: Color(0xFF6B21A8), // Manager
    4: Color(0xFF0F766E), // Supervisor
    5: Color(0xFF9CA3AF), // Staff
  };

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [0, 1, 2, 3, 4, 5].map((lvl) {
            final selected = value == lvl;
            final c = _levelColors[lvl]!;
            final lbl = lvl == 0 ? (isAr ? 'بدون' : 'None') : 'L$lvl';
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(lvl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? c : c.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? c : c.withValues(alpha: 0.30),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  lbl,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : c,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ApprovalPowerSelector extends StatelessWidget {
  final int value;
  final String label;
  final ValueChanged<int> onChanged;
  const _ApprovalPowerSelector({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: value > 0
                    ? AppColors.success.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$value / 5',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: value > 0 ? AppColors.success : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 5,
          divisions: 5,
          label: value.toString(),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

class _ColorPalettePicker extends StatelessWidget {
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  const _ColorPalettePicker({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  static const _palette = <String>[
    '#1A1A1A', '#374151', '#6B21A8', '#0F766E',
    '#0EA5E9', '#10B981', '#34D399', '#C9A961',
    '#E8C97D', '#F59E0B', '#FCD34D', '#92400E',
    '#A78BFA', '#1F2937', '#4B5563', '#6B7280',
    '#9CA3AF',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // No color option
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(null),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value == null ? AppColors.brand : Colors.grey,
                    width: value == null ? 2 : 1,
                  ),
                ),
                child: const Icon(Icons.format_color_reset_outlined, size: 16),
              ),
            ),
            ..._palette.map((hex) {
              final selected =
                  value?.toLowerCase() == hex.toLowerCase();
              final c = _hexToColor(hex);
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(hex),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: c.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  static Color _hexToColor(String hex) {
    final s = hex.replaceAll('#', '');
    return Color(int.parse('FF$s', radix: 16));
  }
}

// ============================================================
// Shared Components
// ============================================================
class _LookupCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LookupCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
            color: Theme.of(context).disabledColor,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

class _CountryFilter extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _CountryFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DropdownButtonFormField<String?>(
        value: value,
        decoration: InputDecoration(
          labelText: s.country2,
          isDense: true,
          prefixIcon: const Icon(Icons.public, size: 18),
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(s.all)),
          ...repo.countries.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.displayName(s.isAr)),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _SheetContainer extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  const _SheetContainer({
    required this.title,
    required this.onSave,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 18),
            ...children,
            const SizedBox(height: 18),
            ElevatedButton(onPressed: onSave, child: Text(s.save)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

void _confirmDelete(
  BuildContext context, {
  required String name,
  bool cascade = false,
  required VoidCallback onConfirm,
}) {
  final s = AppStrings.of(context);
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(s.confirm),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.isAr ? 'هل تريد حذف "$name"؟' : 'Delete "$name"?'),
          if (cascade) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.cascadeWarning,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop();
          },
          child: Text(s.delete),
        ),
      ],
    ),
  );
}
