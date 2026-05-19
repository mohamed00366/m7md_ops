import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_dirty_tracker.dart';
import '../../../shared/m7_section_scaffold.dart';

InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    );

Future<bool> _persist(Site s, [BuildContext? context]) async {
  if (SupabaseService().isReady) {
    final ok = await SupabaseDataService().updateSite(s);
    if (!ok) return false;
  } else {
    MockRepository().notifyListeners();
  }
  // 🆕 سَجِّل في سِجِلّ التَدقيق
  if (context != null && context.mounted) {
    final auth = context.read<AuthProvider>();
    AuditLogService.instance.log(
      action: AuditAction.update,
      entityType: 'site',
      entityId: s.id,
      entityName: s.companyName,
      actorId: auth.account?.id,
      actorName: auth.account?.fullName,
      summary: 'Updated site',
      countryId: s.countryId,
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

// 1️⃣ البَيانات الأَساسيّة
class SiteBasicSection extends StatefulWidget {
  final Site site;
  const SiteBasicSection({super.key, required this.site});
  @override
  State<SiteBasicSection> createState() => _SiteBasicSectionState();
}

class _SiteBasicSectionState extends State<SiteBasicSection>
    with M7DirtyTrackerMixin<SiteBasicSection> {
  late final TextEditingController _name;
  late final TextEditingController _short;
  late final TextEditingController _accounting;
  late final TextEditingController _tax;
  late final TextEditingController _notes;
  String? _businessTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.site;
    _name = TextEditingController(text: s.companyName);
    _short = TextEditingController(text: s.shortName);
    _accounting = TextEditingController(text: s.accountingName);
    _tax = TextEditingController(text: s.taxId);
    _notes = TextEditingController(text: s.notes ?? '');
    _businessTypeId = s.businessTypeId;
    trackAll([_name, _short, _accounting, _tax, _notes]);
  }

  @override
  void dispose() {
    for (final c in [_name, _short, _accounting, _tax, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final site = widget.site;
    site.companyName = _name.text.trim();
    site.shortName = _short.text.trim();
    site.accountingName = _accounting.text.trim();
    site.taxId = _tax.text.trim();
    site.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    site.businessTypeId = _businessTypeId;
    final ok = await _persist(site, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
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
                _dec(isAr ? 'الاسم الكامِل *' : 'Company name *',
                    icon: Icons.business)),
        const SizedBox(height: 12),
        TextField(
            controller: _short,
            decoration:
                _dec(isAr ? 'الاسم القَصير' : 'Short name', icon: Icons.label)),
        const SizedBox(height: 12),
        TextField(
            controller: _accounting,
            decoration: _dec(isAr ? 'اسم المُحاسَبة' : 'Accounting name',
                icon: Icons.account_balance)),
        const SizedBox(height: 12),
        TextField(
            controller: _tax,
            decoration: _dec(isAr ? 'الرَقم الضَريبيّ' : 'Tax ID',
                icon: Icons.numbers)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _businessTypeId,
          decoration:
              _dec(isAr ? 'نَوع النَشاط' : 'Business type', icon: Icons.category),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.businessTypes.map((b) => DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text(isAr ? b.nameAr : b.nameEn),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _businessTypeId = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _notes,
            maxLines: 2,
            decoration: _dec(isAr ? 'مُلاحَظات' : 'Notes', icon: Icons.notes)),
      ],
    );
  }
}

// 2️⃣ الاسم التِجاريّ (Master)
class SiteMasterSection extends StatefulWidget {
  final Site site;
  const SiteMasterSection({super.key, required this.site});
  @override
  State<SiteMasterSection> createState() => _SiteMasterSectionState();
}

class _SiteMasterSectionState extends State<SiteMasterSection>
    with M7DirtyTrackerMixin<SiteMasterSection> {
  String? _masterId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _masterId = widget.site.masterId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.site.masterId = _masterId;
    final ok = await _persist(widget.site, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final masters = repo.masters
        .where((m) => m.countryId == widget.site.countryId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return M7SectionScaffold(
      titleAr: 'الاسم التِجاريّ',
      titleEn: 'Master',
      icon: Icons.business,
      color: AppColors.gold,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        DropdownButtonFormField<String?>(
          value: _masterId,
          decoration: _dec(isAr ? 'الاسم التِجاريّ' : 'Master',
              icon: Icons.business),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...masters.map((m) => DropdownMenuItem<String?>(
                  value: m.id,
                  child: Text('${m.code} · ${m.name}'),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _masterId = v);
          },
        ),
        const SizedBox(height: 14),
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
                      ? 'الفَرع يُمكِن أن يَكون مُستَقِلّاً (بِدون Master) أو تَحت اسم تِجاريّ.'
                      : 'A branch can be standalone or under a Master.',
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

// 3️⃣ التَواصُل
class SiteContactSection extends StatefulWidget {
  final Site site;
  const SiteContactSection({super.key, required this.site});
  @override
  State<SiteContactSection> createState() => _SiteContactSectionState();
}

class _SiteContactSectionState extends State<SiteContactSection>
    with M7DirtyTrackerMixin<SiteContactSection> {
  late final TextEditingController _phone;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.site.phone);
    _email = TextEditingController(text: widget.site.email);
    trackAll([_phone, _email]);
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.site.phone = _phone.text.trim();
    widget.site.email = _email.text.trim();
    final ok = await _persist(widget.site, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'بَيانات التَواصُل',
      titleEn: 'Contact Info',
      icon: Icons.contact_phone,
      color: AppColors.info,
      editPermission: P.sitesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration:
                _dec(isAr ? 'الهاتِف' : 'Phone', icon: Icons.phone)),
        const SizedBox(height: 12),
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: _dec(isAr ? 'البَريد الإلكتروني' : 'Email',
                icon: Icons.email_outlined)),
      ],
    );
  }
}

// 4️⃣ العُنوان
class SiteAddressSection extends StatefulWidget {
  final Site site;
  const SiteAddressSection({super.key, required this.site});
  @override
  State<SiteAddressSection> createState() => _SiteAddressSectionState();
}

class _SiteAddressSectionState extends State<SiteAddressSection>
    with M7DirtyTrackerMixin<SiteAddressSection> {
  late final TextEditingController _address;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  String? _cityId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.site.fullAddress);
    _lat = TextEditingController(text: widget.site.latitude?.toString() ?? '');
    _lng = TextEditingController(text: widget.site.longitude?.toString() ?? '');
    _cityId = widget.site.cityId;
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
    widget.site.fullAddress = _address.text.trim();
    widget.site.latitude = double.tryParse(_lat.text);
    widget.site.longitude = double.tryParse(_lng.text);
    widget.site.cityId = _cityId;
    final ok = await _persist(widget.site, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final cities = repo.cities
        .where((c) => c.countryId == widget.site.countryId)
        .toList();
    return M7SectionScaffold(
      titleAr: 'العُنوان',
      titleEn: 'Address',
      icon: Icons.location_on,
      color: Colors.teal,
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
              setState(() => _cityId = v);
            },
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
      ],
    );
  }
}

// 5️⃣ الحالة
class SiteStatusSection extends StatefulWidget {
  final Site site;
  const SiteStatusSection({super.key, required this.site});
  @override
  State<SiteStatusSection> createState() => _SiteStatusSectionState();
}

class _SiteStatusSectionState extends State<SiteStatusSection>
    with M7DirtyTrackerMixin<SiteStatusSection> {
  EntityStatus _status = EntityStatus.active;
  DateTime? _activationDate;
  DateTime? _deactivationDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.site.status;
    _activationDate = widget.site.activationDate;
    _deactivationDate = widget.site.deactivationDate;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.site.status = _status;
    widget.site.activationDate = _activationDate;
    widget.site.deactivationDate = _deactivationDate;
    final ok = await _persist(widget.site, context);
    if (!mounted) return;
    setState(() => _saving = false);
    _onResult(context, ok);
  }

  Future<void> _pickDate(DateTime? current, void Function(DateTime) set) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      markDirty();
      setState(() => set(d));
    }
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    IconData icon = Icons.event,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _dec(label, icon: icon),
        child: Text(
          value == null
              ? '—'
              : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'الحالة',
      titleEn: 'Status',
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ التَفعيل' : 'Activation date',
                value: _activationDate,
                icon: Icons.event_available,
                onTap: () => _pickDate(
                    _activationDate, (d) => _activationDate = d),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ الإيقاف' : 'Deactivation date',
                value: _deactivationDate,
                icon: Icons.event_busy,
                onTap: () => _pickDate(
                    _deactivationDate, (d) => _deactivationDate = d),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
