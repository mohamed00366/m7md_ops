import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/location_map_picker.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/m7_toolbar.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'point_hub.dart';
import 'point_terminal_account_dialog.dart';
import 'points_excel_io.dart';

/// شاشة إدارة نقاط البيع (Points) + ربط العملاء بكل نقطة
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _searchCtrl.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 🆕 صلاحيّات
    final canEdit = auth.isSuperAdmin ||
        auth.permissions.contains(P.sitesEdit);
    final canDelete = auth.isSuperAdmin ||
        auth.permissions.contains(P.sitesDelete);
    // 🆕 صَلاحيّة إدارة حِسابات Point Terminal
    final canManageTerminal = auth.isSuperAdmin ||
        auth.permissions.contains(P.pointTerminalManage);

    var list = auth.activeCountryId == null
        ? [...repo.points]
        : repo.points
            .where((p) => p.countryId == auth.activeCountryId)
            .toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.code.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: s.isAr
                    ? 'بحث بالاسم أو الكود...'
                    : 'Search by name or code...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: isDark
                    ? AppColors.surface2Dark
                    : AppColors.surface2Light,
              ),
            ),
          ),
          // 🆕 شَريط أَدَوات Import/Export/Template
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: M7Toolbar(
              busy: _busy,
              actions: M7StandardActions.ioActions(
                isAr: s.isAr,
                onTemplate: _onTemplate,
                onImport: _onImport,
                onExport: () => _onExport(list),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.isAr
                  ? '${list.length} نقطة بيع'
                  : '${list.length} points',
              style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 11),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.place_outlined,
                            size: 56,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight),
                        const SizedBox(height: 12),
                        Text(
                          s.isAr ? 'لا توجد نقاط بيع' : 'No points yet',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _PointCard(
                      point: list[i],
                      isDark: isDark,
                      // 🆕 nullable حسب الصلاحيّة
                      onTap:
                          canEdit ? () => _open(existing: list[i]) : null,
                      onDelete:
                          canDelete ? () => _confirmDelete(list[i]) : null,
                      onLink:
                          canEdit ? () => _openLink(list[i]) : null,
                      // 🆕 إنشاء/عَرض حِساب الجِهاز — يَحتاج صَلاحيّة pointTerminalManage
                      onCreateTerminal: canManageTerminal
                          ? () => _openTerminalAccount(list[i])
                          : null,
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.sitesCreate,
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.brand,
          onPressed: () => _open(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            s.isAr ? 'نقطة جديدة' : 'New Point',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _open({Point? existing}) {
    // 🆕 لِنُقطة قائِمة: افتَح PointHub. لِنُقطة جَديدة: المُحَرِّر القَديم.
    if (existing != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PointHub(point: existing),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PointEditor(),
    );
  }

  void _openLink(Point p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkClientsSheet(point: p),
    );
  }

  // ============================================================
  // 🆕 Import / Export / Template
  // ============================================================
  Future<void> _onTemplate() async {
    setState(() => _busy = true);
    await PointsExcelIO.downloadTemplate();
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      content: Text(s.isAr ? '📋 تَمّ تَنزيل القالَب' : '📋 Template downloaded'),
    ));
  }

  Future<void> _onImport() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final result =
        await PointsExcelIO.importPoints(countryId: auth.activeCountryId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.cancelled) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          result.imported > 0 ? Icons.check_circle : Icons.warning_amber,
          color: result.imported > 0 ? AppColors.success : Colors.orange,
          size: 36,
        ),
        title: Text(isAr ? 'نَتيجة الاستيراد' : 'Import Result'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                isAr
                    ? 'تَمّ استيراد ${result.imported} نُقطة'
                    : 'Imported: ${result.imported}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(isAr ? 'تَجاوُز: ${result.skipped}' : 'Skipped: ${result.skipped}',
                style: const TextStyle(color: Colors.grey)),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...result.errors.take(8).map((e) => Text('• $e',
                  style: const TextStyle(fontSize: 11, color: Colors.red))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'حَسَناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onExport(List<Point> points) async {
    final s = AppStrings.of(context);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(s.isAr ? 'لا تُوجَد بَيانات' : 'No data'),
      ));
      return;
    }
    setState(() => _busy = true);
    await PointsExcelIO.exportPoints(points);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تَمّ التَصدير (${points.length})'
          : '✅ Exported (${points.length})'),
    ));
  }

  /// 🆕 يَفتَح حِوار حِساب جِهاز النُقطة — إنشاء أَو عَرض كَلِمة المُرور
  void _openTerminalAccount(Point p) {
    showDialog(
      context: context,
      builder: (_) => PointTerminalAccountDialog(point: p),
    );
  }

  Future<void> _confirmDelete(Point p) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'حذف نقطة' : 'Delete Point'),
        content: Text(s.isAr
            ? 'سيتم حذف ${p.name} وفك كل روابطها بالعملاء.'
            : 'Will delete ${p.name} and unlink from all clients.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok == true) {
      if (SupabaseService().isReady) {
        await SupabaseDataService().deletePoint(p.id);
      } else {
        MockRepository().points.removeWhere((x) => x.id == p.id);
        MockRepository().notifyListeners();
      }
    }
  }
}

// ============================================================
// كارد نقطة
// ============================================================
class _PointCard extends StatelessWidget {
  final Point point;
  final bool isDark;
  /// 🆕 nullable — الأزرار تَختفي إذا null
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onLink;
  // 🆕 إنشاء حِساب جِهاز نُقطة (Kiosk)
  final VoidCallback? onCreateTerminal;
  const _PointCard({
    required this.point,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
    required this.onLink,
    this.onCreateTerminal,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final city = point.cityId == null ? null : repo.cityById(point.cityId);
    final clientsCount = point.linkedClients.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.place,
                      color: AppColors.warning, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        point.name,
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (point.code.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                point.code,
                                style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          if (city != null)
                            Text(
                              city.displayName(s.isAr),
                              style: const TextStyle(
                                  color: AppColors.textSecondaryLight,
                                  fontSize: 11),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link,
                                    size: 10, color: AppColors.info),
                                const SizedBox(width: 3),
                                Text(
                                  s.isAr
                                      ? '$clientsCount عميل'
                                      : '$clientsCount clients',
                                  style: const TextStyle(
                                      color: AppColors.info,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 🆕 الأزرار تَختفي إذا الصلاحيّة مفقودة
                if (onCreateTerminal != null)
                  IconButton(
                    icon: const Icon(Icons.qr_code_2,
                        size: 18, color: AppColors.gold),
                    tooltip: s.isAr
                        ? 'إنشاء/عَرض حِساب الجِهاز'
                        : 'Create/view terminal account',
                    onPressed: onCreateTerminal,
                  ),
                if (onLink != null)
                  IconButton(
                    icon: const Icon(Icons.link,
                        size: 18, color: AppColors.info),
                    tooltip: s.isAr ? 'ربط عملاء' : 'Link clients',
                    onPressed: onLink,
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.danger),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// شيت إنشاء/تعديل نقطة
// ============================================================
class _PointEditor extends StatefulWidget {
  final Point? existing;
  const _PointEditor({this.existing});

  @override
  State<_PointEditor> createState() => _PointEditorState();
}

class _PointEditorState extends State<_PointEditor> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  String? _countryId;
  String? _cityId;
  String? _areaId;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (widget.existing != null) {
      final p = widget.existing!;
      _name.text = p.name;
      _description.text = p.description;
      _address.text = p.fullAddress;
      _lat.text = p.latitude?.toString() ?? '';
      _lng.text = p.longitude?.toString() ?? '';
      _countryId = p.countryId;
      _cityId = p.cityId;
      _areaId = p.areaId;
    } else {
      _countryId = auth.activeCountryId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_name.text.trim().isEmpty) {
      _toast(s.isAr ? 'الاسم مطلوب' : 'Name required');
      return;
    }
    if (_countryId == null) {
      _toast(s.isAr ? 'الدولة مطلوبة' : 'Country required');
      return;
    }
    final repo = MockRepository();
    final dataService = SupabaseDataService();
    final supaReady = SupabaseService().isReady;

    if (isEdit) {
      final p = widget.existing!;
      p.name = _name.text.trim();
      p.description = _description.text.trim();
      p.fullAddress = _address.text.trim();
      p.latitude = double.tryParse(_lat.text);
      p.longitude = double.tryParse(_lng.text);
      p.countryId = _countryId;
      p.cityId = _cityId;
      p.areaId = _areaId;
      if (supaReady) {
        final ok = await dataService.updatePoint(p);
        if (!ok) {
          _toast(dataService.lastError ?? 'Failed', isError: true);
          return;
        }
      }
      repo.notifyListeners();
    } else {
      String? code;
      if (supaReady) {
        code = await dataService.consumeNextCode(
            technicalId: 'pos_point', countryId: _countryId!);
      }
      code ??= 'POS-?';

      final p = Point(
        id: repo.generateId(),
        code: code,
        name: _name.text.trim(),
        description: _description.text.trim(),
        countryId: _countryId,
        cityId: _cityId,
        areaId: _areaId,
        fullAddress: _address.text.trim(),
        latitude: double.tryParse(_lat.text),
        longitude: double.tryParse(_lng.text),
      );
      if (supaReady) {
        final created = await dataService.createPoint(p);
        if (created == null) {
          _toast(dataService.lastError ?? 'Failed', isError: true);
          return;
        }
      } else {
        repo.addPoint(p);
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cities = _countryId == null
        ? <dynamic>[]
        : repo.cities.where((c) => c.countryId == _countryId).toList();
    final areas = _cityId == null
        ? <dynamic>[]
        : repo.areas.where((a) => a.cityId == _cityId).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'تعديل نقطة' : 'Edit Point')
                          : (s.isAr ? 'نقطة جديدة' : 'New Point'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'اسم النقطة *' : 'Point Name *',
                      hintText: s.isAr
                          ? 'مثلاً: مول الرياض - الفرع الرئيسي'
                          : 'e.g. Riyadh Mall - Main Branch',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _countryId,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'الدولة *' : 'Country *',
                      border: const OutlineInputBorder(),
                    ),
                    items: repo.countries
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(s.isAr ? c.nameAr : c.nameEn),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _countryId = v;
                      _cityId = null;
                      _areaId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _cityId,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'المدينة' : 'City',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(s.isAr ? 'بدون' : 'None'),
                      ),
                      ...cities.map((c) => DropdownMenuItem<String>(
                            value: c.id as String,
                            child: Text(s.isAr ? c.nameAr : c.nameEn),
                          )),
                    ],
                    onChanged: (v) => setState(() {
                      _cityId = v;
                      _areaId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _areaId,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'المنطقة' : 'Area',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(s.isAr ? 'بدون' : 'None'),
                      ),
                      ...areas.map((a) => DropdownMenuItem<String>(
                            value: a.id as String,
                            child: Text(s.isAr ? a.nameAr : a.nameEn),
                          )),
                    ],
                    onChanged: (v) => setState(() => _areaId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _address,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'العنوان الكامل' : 'Full Address',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 🆕 زِرّ "اختَر من الخَريطة" — يَفتَح map picker مَع بَحث
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        LatLng? initial;
                        final curLat = double.tryParse(_lat.text);
                        final curLng = double.tryParse(_lng.text);
                        if (curLat != null && curLng != null) {
                          initial = LatLng(curLat, curLng);
                        }
                        final result = await Navigator.of(context).push<LatLng>(
                          MaterialPageRoute(
                            builder: (_) => LocationMapPicker(
                              initial: initial,
                              title: s.isAr
                                  ? 'اختَر مَوقِع النُقطة'
                                  : 'Pick Point Location',
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() {
                            _lat.text = result.latitude.toStringAsFixed(6);
                            _lng.text = result.longitude.toStringAsFixed(6);
                          });
                        }
                      },
                      icon: const Icon(Icons.map, size: 18),
                      label: Text(
                        s.isAr
                            ? (_lat.text.isNotEmpty && _lng.text.isNotEmpty
                                ? '🗺 تَغيير المَوقِع'
                                : '📍 اختَر من الخَريطة (بَحث + نَقر)')
                            : (_lat.text.isNotEmpty && _lng.text.isNotEmpty
                                ? '🗺 Change Location'
                                : '📍 Pick on Map (search + tap)'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                            color: AppColors.brand.withOpacity(0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _lat,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.isAr ? 'خط العرض' : 'Latitude',
                            border: const OutlineInputBorder(),
                            helperText: s.isAr ? 'يَدَويّ' : 'manual',
                            helperStyle: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lng,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.isAr ? 'خط الطول' : 'Longitude',
                            border: const OutlineInputBorder(),
                            helperText: s.isAr ? 'يَدَويّ' : 'manual',
                            helperStyle: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'الوصف' : 'Description',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'حفظ' : 'Save')
                          : (s.isAr ? 'إنشاء النقطة' : 'Create Point'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
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

// ============================================================
// شيت ربط عملاء بنقطة
// ============================================================
class _LinkClientsSheet extends StatefulWidget {
  final Point point;
  const _LinkClientsSheet({required this.point});

  @override
  State<_LinkClientsSheet> createState() => _LinkClientsSheetState();
}

class _LinkClientsSheetState extends State<_LinkClientsSheet> {
  late Set<String> _linked;

  @override
  void initState() {
    super.initState();
    _linked = widget.point.linkedClients.map((l) => l.clientId).toSet();
  }

  Future<void> _toggle(String siteId) async {
    final supaReady = SupabaseService().isReady;
    if (_linked.contains(siteId)) {
      // Unlink
      if (supaReady) {
        await SupabaseDataService().unlinkSiteFromPoint(
            pointId: widget.point.id, siteId: siteId);
      } else {
        widget.point.linkedClients.removeWhere((l) => l.clientId == siteId);
        MockRepository().notifyListeners();
      }
      setState(() => _linked.remove(siteId));
    } else {
      // Link
      if (supaReady) {
        await SupabaseDataService()
            .linkSiteToPoint(pointId: widget.point.id, siteId: siteId);
      } else {
        widget.point.linkedClients.add(PointClientLink(clientId: siteId));
        MockRepository().notifyListeners();
      }
      setState(() => _linked.add(siteId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // العملاء بنفس دولة النقطة
    final eligibleClients = widget.point.countryId == null
        ? repo.sites
        : repo.sites
            .where((c) => c.countryId == widget.point.countryId)
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.link, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isAr
                              ? 'ربط عملاء بـ ${widget.point.name}'
                              : 'Link Clients to ${widget.point.name}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800),
                        ),
                        Text(
                          s.isAr
                              ? '${_linked.length} عميل مرتبط'
                              : '${_linked.length} clients linked',
                          style: const TextStyle(
                              color: AppColors.textSecondaryLight,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: eligibleClients.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          s.isAr
                              ? 'لا يوجد عملاء في هذه الدولة. أضف عملاء من تاب "Clients" أولاً.'
                              : 'No clients in this country. Add some in "Clients" tab first.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSecondaryLight),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: eligibleClients.length,
                      itemBuilder: (_, i) {
                        final c = eligibleClients[i];
                        final linked = _linked.contains(c.id);
                        return CheckboxListTile(
                          value: linked,
                          onChanged: (_) => _toggle(c.id),
                          title: Text(
                            c.companyName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          subtitle: c.shortName.isNotEmpty
                              ? Text(c.shortName,
                                  style: const TextStyle(fontSize: 11))
                              : null,
                          activeColor: AppColors.info,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
