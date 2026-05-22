import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'customer_wizard.dart';

class ManagerSites extends StatefulWidget {
  const ManagerSites({super.key});

  @override
  State<ManagerSites> createState() => _ManagerSitesState();
}

class _ManagerSitesState extends State<ManagerSites> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // 🆕 صلاحيّات الموقع — العرض دائماً للمصرَّح له بـ sitesView
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.isSuperAdmin ||
        auth.permissions.contains(P.sitesCreate);
    final canEdit = auth.isSuperAdmin ||
        auth.permissions.contains(P.sitesEdit);
    final filtered = repo.sites.where((site) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return site.companyName.toLowerCase().contains(q) ||
          site.shortName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(message: s.noData)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _SiteCard(
                      site: filtered[i],
                      // 🆕 لو لا يملك canEdit → onEdit = null (الكارد غير قابل للتعديل)
                      onEdit: canEdit
                          ? () => _showEditor(existing: filtered[i])
                          : null,
                    ),
                  ),
          ),
        ],
      ),
      // 🆕 الزرّ يظهر فقط لمن يملك sitesCreate
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showEditor(),
              icon: const Icon(Icons.add),
              label: Text('${s.add} ${s.isAr ? 'عميل' : 'Customer'}'),
            )
          : null,
    );
  }

  void _showEditor({Site? existing}) {
    if (existing == null) {
      // إنشاء جديد - استخدم Wizard
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const CustomerWizardScreen(),
      ));
    } else {
      // تعديل موجود - استخدم النموذج القديم
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CustomerEditorScreen(existing: existing),
      ));
    }
  }
}

// =============================================================
// Site card in list
// =============================================================
class _SiteCard extends StatelessWidget {
  final Site site;
  /// 🆕 nullable — لو null يَعرض البطاقة بدون onTap (read-only)
  final VoidCallback? onEdit;
  const _SiteCard({required this.site, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final empCount = repo.employees.where((e) => e.siteId == site.id).length;
    final country = repo.countryById(site.countryId);
    final city = repo.cityById(site.cityId);
    final bt = repo.businessTypeById(site.businessTypeId);

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.business, color: AppColors.purple),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(site.companyName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(
                        '${site.shortName}${city != null ? " • ${city.displayName(s.isAr)}" : ""}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: site.status == EntityStatus.active
                      ? s.active
                      : s.inactive,
                  color: site.status == EntityStatus.active
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _MiniInfo(icon: Icons.people, value: '$empCount ${s.employees}'),
                if (bt != null)
                  _MiniInfo(icon: Icons.work, value: bt.displayName(s.isAr)),
                if (country != null)
                  _MiniInfo(
                      icon: Icons.public,
                      value: country.displayName(s.isAr)),
                if (site.latitude != null)
                  const _MiniInfo(icon: Icons.location_on, value: 'GPS'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String value;
  const _MiniInfo({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).disabledColor),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// =============================================================
// Customer Editor (Full screen with sections)
// =============================================================
class CustomerEditorScreen extends StatefulWidget {
  final Site? existing;
  const CustomerEditorScreen({super.key, this.existing});

  @override
  State<CustomerEditorScreen> createState() => _CustomerEditorScreenState();
}

class _CustomerEditorScreenState extends State<CustomerEditorScreen> {
  // Basic
  late final TextEditingController _company;
  late final TextEditingController _short;
  late final TextEditingController _accounting;
  String? _businessTypeId;

  // Contact
  late final TextEditingController _email;
  late final TextEditingController _phone;

  // Location (cascading)
  String? _countryId;
  String? _cityId;
  String? _areaId;
  late final TextEditingController _fullAddress;
  late final TextEditingController _lat;
  late final TextEditingController _lng;

  // Additional
  late final TextEditingController _taxId;
  late final TextEditingController _notes;
  EntityStatus _status = EntityStatus.active;

  // Files
  List<String> _attachedFileIds = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _company = TextEditingController(text: e?.companyName ?? '');
    _short = TextEditingController(text: e?.shortName ?? '');
    _accounting = TextEditingController(text: e?.accountingName ?? '');
    _businessTypeId = e?.businessTypeId;
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _countryId = e?.countryId;
    _cityId = e?.cityId;
    _areaId = e?.areaId;
    _fullAddress = TextEditingController(text: e?.fullAddress ?? '');
    _lat = TextEditingController(text: e?.latitude?.toString() ?? '');
    _lng = TextEditingController(text: e?.longitude?.toString() ?? '');
    _taxId = TextEditingController(text: e?.taxId ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _status = e?.status ?? EntityStatus.active;
    _attachedFileIds = List.from(e?.attachedFileIds ?? []);
  }

  @override
  void dispose() {
    _company.dispose();
    _short.dispose();
    _accounting.dispose();
    _email.dispose();
    _phone.dispose();
    _fullAddress.dispose();
    _lat.dispose();
    _lng.dispose();
    _taxId.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppStrings.of(context);
    if (_company.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isAr ? 'اسم الشركة مطلوب' : 'Company name required')),
      );
      return;
    }
    final repo = MockRepository();
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);

    if (widget.existing == null) {
      repo.addSite(Site(
        id: repo.generateId(),
        companyName: _company.text.trim(),
        shortName: _short.text.trim(),
        accountingName: _accounting.text.trim(),
        businessTypeId: _businessTypeId,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        countryId: _countryId,
        cityId: _cityId,
        areaId: _areaId,
        fullAddress: _fullAddress.text.trim(),
        latitude: lat,
        longitude: lng,
        taxId: _taxId.text.trim(),
        notes: _notes.text.trim(),
        status: _status,
        attachedFileIds: _attachedFileIds,
      ));
    } else {
      final e = widget.existing!;
      e.companyName = _company.text.trim();
      e.shortName = _short.text.trim();
      e.accountingName = _accounting.text.trim();
      e.businessTypeId = _businessTypeId;
      e.email = _email.text.trim();
      e.phone = _phone.text.trim();
      e.countryId = _countryId;
      e.cityId = _cityId;
      e.areaId = _areaId;
      e.fullAddress = _fullAddress.text.trim();
      e.latitude = lat;
      e.longitude = lng;
      e.taxId = _taxId.text.trim();
      e.notes = _notes.text.trim();
      e.status = _status;
      e.attachedFileIds = _attachedFileIds;
      repo.updateSite(e);
    }
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

    final availableCities =
        _countryId == null ? <City>[] : repo.citiesOfCountry(_countryId!);
    final availableAreas =
        _cityId == null ? <Area>[] : repo.areasOfCity(_cityId!);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit
            ? (s.isAr ? 'تعديل عميل' : 'Edit Customer')
            : (s.isAr ? 'عميل جديد' : 'New Customer')),
        actions: [
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
          // ===== Basic Information =====
          _SectionHeader(
              icon: Icons.info_outline, title: s.basicInfo),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _company,
                  decoration: InputDecoration(
                    labelText: s.companyName,
                    hintText: s.isAr ? 'أدخل اسم الشركة' : 'Enter company name',
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _short,
                      decoration: InputDecoration(labelText: s.shortName),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _accounting,
                      decoration: InputDecoration(labelText: s.accountingName),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _businessTypeId,
                  decoration: InputDecoration(
                    labelText: s.businessType2,
                    hintText: s.isAr
                        ? 'اختر نوع النشاط'
                        : 'Choose business type',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...repo.businessTypes.map((bt) => DropdownMenuItem(
                          value: bt.id,
                          child: Text(bt.displayName(s.isAr)),
                        )),
                  ],
                  onChanged: (v) => setState(() => _businessTypeId = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== Contact Information =====
          _SectionHeader(icon: Icons.contact_mail, title: s.contactInfo),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s.email,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: s.phone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== Location (cascading) =====
          _SectionHeader(icon: Icons.location_on, title: s.locationInfo),
          SectionCard(
            child: Column(
              children: [
                DropdownButtonFormField<String?>(
                  value: _countryId,
                  decoration: InputDecoration(
                    labelText: '${s.country2} *',
                    prefixIcon: const Icon(Icons.public),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...repo.countries.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.displayName(s.isAr)),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _countryId = v;
                      _cityId = null;
                      _areaId = null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _cityId,
                      decoration: InputDecoration(
                        labelText: s.city2,
                        hintText: _countryId == null
                            ? s.selectCountryFirst
                            : null,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...availableCities.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.displayName(s.isAr)),
                            )),
                      ],
                      onChanged: _countryId == null
                          ? null
                          : (v) => setState(() {
                                _cityId = v;
                                _areaId = null;
                              }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _areaId,
                      decoration: InputDecoration(
                        labelText: s.area,
                        hintText:
                            _cityId == null ? s.selectCityFirst : null,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...availableAreas.map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.displayName(s.isAr)),
                            )),
                      ],
                      onChanged: _cityId == null
                          ? null
                          : (v) => setState(() => _areaId = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _fullAddress,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: s.fullAddress,
                    prefixIcon: const Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.latitude),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.longitude),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== Additional Information =====
          _SectionHeader(icon: Icons.add_circle_outline, title: s.additionalInfo),
          SectionCard(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _taxId,
                      decoration: InputDecoration(labelText: s.taxId),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).inputDecorationTheme.fillColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.customerStatus,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Switch(
                            value: _status == EntityStatus.active,
                            onChanged: (v) => setState(() {
                              _status = v
                                  ? EntityStatus.active
                                  : EntityStatus.inactive;
                            }),
                          ),
                          StatusBadge(
                            label: _status == EntityStatus.active
                                ? s.active
                                : s.inactive,
                            color: _status == EntityStatus.active
                                ? AppColors.success
                                : AppColors.danger,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: s.notes,
                    hintText: s.isAr
                        ? 'أضف ملاحظات حول هذا العميل'
                        : 'Add notes about this customer',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== Files & Documents =====
          _SectionHeader(
              icon: Icons.attach_file, title: s.filesAndDocs),
          SectionCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.brand.withValues(alpha: 0.3),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_upload_outlined,
                          color: AppColors.brand, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        s.isAr
                            ? 'اضغط لاختيار الملفات أو اسحبها هنا'
                            : 'Tap to select files or drag here',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PDF, DOC, DOCX, PNG, JPG (max 5MB)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          // Mock: في الإنتاج استخدم file_picker
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(s.isAr
                                  ? 'سيتم إضافة file_picker عند الربط بـ Supabase Storage'
                                  : 'file_picker integrates when Supabase Storage is wired'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(s.isAr ? 'اختيار ملف' : 'Choose file'),
                      ),
                    ],
                  ),
                ),
                if (_attachedFileIds.isEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      s.isAr ? 'لا توجد ملفات' : 'No files',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ===== Save buttons =====
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              isEdit
                  ? s.save
                  : (s.isAr ? 'حفظ العميل' : 'Save Customer'),
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
