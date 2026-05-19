import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/lookups.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/location_map_picker.dart';
import '../../../shared/m7_dirty_tracker.dart';
import '../../../shared/m7_section_scaffold.dart';
import 'package:latlong2/latlong.dart' hide Path;

InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    );

Future<bool> _persist(Point p, [BuildContext? context]) async {
  if (SupabaseService().isReady) {
    final ok = await SupabaseDataService().updatePoint(p);
    if (!ok) return false;
  } else {
    MockRepository().notifyListeners();
  }
  // 🆕 سَجِّل في سِجِلّ التَدقيق
  if (context != null && context.mounted) {
    final auth = context.read<AuthProvider>();
    AuditLogService.instance.log(
      action: AuditAction.update,
      entityType: 'point',
      entityId: p.id,
      entityName: p.name,
      actorId: auth.account?.id,
      actorName: auth.account?.fullName,
      summary: 'Updated point',
      countryId: p.countryId,
    );
  }
  return true;
}

void _onResult(BuildContext context, bool ok) {
  final s = AppStrings.of(context);
  if (ok) {
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.success)));
  } else {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text(
          SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed')),
    ));
  }
}

// ============================================================
// 1️⃣ البَيانات الأَساسيّة
// ============================================================
class PointBasicSection extends StatefulWidget {
  final Point point;
  const PointBasicSection({super.key, required this.point});
  @override
  State<PointBasicSection> createState() => _PointBasicSectionState();
}

class _PointBasicSectionState extends State<PointBasicSection>
    with M7DirtyTrackerMixin<PointBasicSection> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.point.name);
    _code = TextEditingController(text: widget.point.code);
    _description = TextEditingController(text: widget.point.description);
    trackAll([_name, _code, _description]);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = widget.point;
    p.name = _name.text.trim();
    p.code = _code.text.trim();
    p.description = _description.text.trim();
    final ok = await _persist(p, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'البَيانات الأَساسيّة',
      titleEn: 'Basic Info',
      icon: Icons.info_outline,
      color: AppColors.brand,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
            controller: _name,
            decoration:
                _dec(isAr ? 'الاسم *' : 'Name *', icon: Icons.label)),
        const SizedBox(height: 12),
        TextField(
            controller: _code,
            decoration: _dec(isAr ? 'الكود' : 'Code', icon: Icons.tag)),
        const SizedBox(height: 12),
        TextField(
            controller: _description,
            maxLines: 3,
            decoration: _dec(isAr ? 'الوَصف' : 'Description',
                icon: Icons.description)),
      ],
    );
  }
}

// ============================================================
// 2️⃣ المَوقِع وَالعُنوان
// ============================================================
class PointLocationSection extends StatefulWidget {
  final Point point;
  const PointLocationSection({super.key, required this.point});
  @override
  State<PointLocationSection> createState() => _PointLocationSectionState();
}

class _PointLocationSectionState extends State<PointLocationSection>
    with M7DirtyTrackerMixin<PointLocationSection> {
  late final TextEditingController _address;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  String? _cityId;
  String? _areaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    _address = TextEditingController(text: p.fullAddress);
    _lat = TextEditingController(text: p.latitude?.toString() ?? '');
    _lng = TextEditingController(text: p.longitude?.toString() ?? '');
    _cityId = p.cityId;
    _areaId = p.areaId;
    trackAll([_address, _lat, _lng]);
  }

  @override
  void dispose() {
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = widget.point;
    p.fullAddress = _address.text.trim();
    p.latitude = double.tryParse(_lat.text);
    p.longitude = double.tryParse(_lng.text);
    p.cityId = _cityId;
    p.areaId = _areaId;
    final ok = await _persist(p, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final cities =
        repo.cities.where((c) => c.countryId == widget.point.countryId).toList();
    // 🆕 المَناطِق مُفَلتَرة حَسَب المَدينة المُختارة (cityId)
    final areas = _cityId == null
        ? <Area>[]
        : repo.areas.where((a) => a.cityId == _cityId).toList();
    return M7SectionScaffold(
      titleAr: 'المَوقِع وَالعُنوان',
      titleEn: 'Location',
      icon: Icons.location_on,
      color: AppColors.info,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
            controller: _address,
            maxLines: 2,
            decoration: _dec(isAr ? 'العُنوان الكامِل' : 'Full address',
                icon: Icons.home_outlined)),
        const SizedBox(height: 12),
        if (cities.isNotEmpty)
          DropdownButtonFormField<String?>(
            value: _cityId,
            decoration: _dec(isAr ? 'المَدينة' : 'City',
                icon: Icons.location_city),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              ...cities.map((c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(isAr ? c.nameAr : c.nameEn),
                  )),
            ],
            onChanged: (v) {
              markDirty();
              setState(() {
                _cityId = v;
                // إذا غُيِّرَت المَدينة → امسَح المَنطِقة لِأَنّها مُرتَبِطة
                _areaId = null;
              });
            },
          ),
        const SizedBox(height: 12),
        // 🆕 dropdown المَنطِقة — يَظهَر فَقَط بَعد اختِيار مَدينة فيها مَناطِق
        if (_cityId != null && areas.isNotEmpty)
          DropdownButtonFormField<String?>(
            value: areas.any((a) => a.id == _areaId) ? _areaId : null,
            decoration: _dec(isAr ? 'المَنطِقة' : 'Area',
                icon: Icons.map_outlined),
            isExpanded: true,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(isAr ? 'بِدون' : 'None'),
              ),
              ...areas.map((a) => DropdownMenuItem<String?>(
                    value: a.id,
                    child: Text(isAr ? a.nameAr : a.nameEn),
                  )),
            ],
            onChanged: (v) {
              markDirty();
              setState(() => _areaId = v);
            },
          ),
        if (_cityId != null && areas.isNotEmpty) const SizedBox(height: 12),
        if (_cityId != null && areas.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr
                        ? 'لا تُوجَد مَناطِق لِهذه المَدينة — أَضِفها من القَوائِم المَرجِعيّة'
                        : 'No areas for this city — add via Lookups',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        // 🆕 زِرّ "اختَر من الخَريطة" — يَفتَح map picker مَع بَحث Nominatim
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
                    title: isAr
                        ? 'اختَر مَوقِع النُقطة'
                        : 'Pick Point Location',
                  ),
                ),
              );
              if (result != null) {
                markDirty();
                setState(() {
                  _lat.text = result.latitude.toStringAsFixed(6);
                  _lng.text = result.longitude.toStringAsFixed(6);
                });
              }
            },
            icon: const Icon(Icons.map, size: 18),
            label: Text(
              isAr
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
              side: BorderSide(color: AppColors.brand.withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _dec(isAr ? 'خَطّ العَرض' : 'Latitude',
                    icon: Icons.north),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _dec(isAr ? 'خَطّ الطول' : 'Longitude',
                    icon: Icons.east),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? 'إحداثيّات GPS تُستَخدَم في Geo-fence لِشاشة Point Terminal.'
                      : 'GPS coords used for Geo-fence in Point Terminal.',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 3️⃣ العُملاء المَربوطون
// ============================================================
class PointClientsSection extends StatefulWidget {
  final Point point;
  const PointClientsSection({super.key, required this.point});
  @override
  State<PointClientsSection> createState() => _PointClientsSectionState();
}

class _PointClientsSectionState extends State<PointClientsSection>
    with M7DirtyTrackerMixin<PointClientsSection> {
  late List<PointClientLink> _links;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _links = [...widget.point.linkedClients];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.point.linkedClients = _links;
    final ok = await _persist(widget.point, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  void _addClient(Site site) {
    if (_links.any((l) => l.clientId == site.id)) return;
    markDirty();
    setState(() {
      _links.add(PointClientLink(clientId: site.id));
    });
  }

  void _removeClient(String clientId) {
    markDirty();
    setState(() {
      _links.removeWhere((l) => l.clientId == clientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final available = repo.sites
        .where((s) => !_links.any((l) => l.clientId == s.id))
        .toList()
      ..sort((a, b) => a.companyName.compareTo(b.companyName));
    return M7SectionScaffold(
      titleAr: 'العُملاء المَربوطون',
      titleEn: 'Linked Clients',
      icon: Icons.business,
      color: AppColors.gold,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        Text(isAr ? 'المَربوطون حاليّاً' : 'Currently linked',
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_links.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isAr ? 'لا يُوجَد عُملاء مَربوطون.' : 'No clients linked.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        else
          ..._links.map((link) {
            final site = repo.sites
                .where((s) => s.id == link.clientId)
                .firstOrNull;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.storefront,
                    color: AppColors.gold),
                title: Text(site?.companyName ?? link.clientId,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: site == null
                    ? const Text('—')
                    : Text(site.shortName,
                        style: const TextStyle(fontSize: 10)),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red),
                  onPressed: () => _removeClient(link.clientId),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        Text(isAr ? 'إضافة عَميل' : 'Add client',
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: null,
          decoration: _dec(isAr ? 'اختَر عَميلاً' : 'Pick a client',
              icon: Icons.add_business),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...available.map((s) => DropdownMenuItem<String?>(
                  value: s.id,
                  child: Text(s.companyName),
                )),
          ],
          onChanged: (v) {
            if (v == null) return;
            final site = available.where((s) => s.id == v).firstOrNull;
            if (site != null) _addClient(site);
          },
        ),
      ],
    );
  }
}

// ============================================================
// 4️⃣ الحالة (Active/Inactive)
// ============================================================
class PointStatusSection extends StatefulWidget {
  final Point point;
  const PointStatusSection({super.key, required this.point});
  @override
  State<PointStatusSection> createState() => _PointStatusSectionState();
}

class _PointStatusSectionState extends State<PointStatusSection>
    with M7DirtyTrackerMixin<PointStatusSection> {
  EntityStatus _status = EntityStatus.active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.point.status;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.point.status = _status;
    final ok = await _persist(widget.point, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'حالة النُقطة',
      titleEn: 'Point Status',
      icon: Icons.toggle_on,
      color: _status == EntityStatus.active ? AppColors.success : Colors.red,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              RadioListTile<EntityStatus>(
                dense: true,
                title: Text(isAr ? '✅ نَشِط' : '✅ Active'),
                subtitle: Text(
                  isAr
                      ? 'تَعمَل النُقطة وَتَستَقبِل البَيانات'
                      : 'Point operational',
                  style: const TextStyle(fontSize: 10),
                ),
                value: EntityStatus.active,
                groupValue: _status,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _status = v);
                },
              ),
              RadioListTile<EntityStatus>(
                dense: true,
                title: Text(isAr ? '⛔ مُعَطَّل' : '⛔ Inactive'),
                subtitle: Text(
                  isAr
                      ? 'تَتَوَقَّف الجَلسات وَلا يُسمَح بِالدُخول الجَديد'
                      : 'Sessions stop, no new logins',
                  style: const TextStyle(fontSize: 10),
                ),
                value: EntityStatus.inactive,
                groupValue: _status,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _status = v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
