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
import '../../../shared/permission_gate.dart';
import 'site_hub.dart';

/// helper لفتح محرر العميل من أي مكان (مع تمهيد Master اختياري)
void showClientEditor(
  BuildContext context, {
  Site? existing,
  Master? prefilledMaster,
}) {
  // 🆕 لِفَرع قائِم: افتَح SiteHub. لِفَرع جَديد: المُحَرِّر القَديم.
  if (existing != null) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SiteHub(site: existing),
    ));
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ClientEditor(
      prefilledMaster: prefilledMaster,
    ),
  );
}

/// شاشة إدارة العملاء (Clients/Sites) — لم تعد مستخدمة في الـ Hub
/// لكن نُبقي على كود الـ Editor لاستخدامه من Masters
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

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
        auth.permissions.contains(P.sitesEdit) ||
        auth.permissions.contains(P.customersEdit);
    final canDelete = auth.isSuperAdmin ||
        auth.permissions.contains(P.sitesDelete) ||
        auth.permissions.contains(P.customersDelete);

    var list = auth.activeCountryId == null
        ? [...repo.sites]
        : repo.sites
            .where((x) => x.countryId == auth.activeCountryId)
            .toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((c) =>
              c.companyName.toLowerCase().contains(q) ||
              c.shortName.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => a.companyName.compareTo(b.companyName));

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.isAr
                  ? '${list.length} عميل'
                  : '${list.length} clients',
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
                        Icon(Icons.storefront_outlined,
                            size: 56,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight),
                        const SizedBox(height: 12),
                        Text(s.isAr ? 'لا يوجد عملاء' : 'No clients',
                            style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ClientCard(
                      client: list[i],
                      isDark: isDark,
                      // 🆕 nullable: لو لا يَملك الصلاحيّة، الزرّ مختفٍ
                      onTap:
                          canEdit ? () => _open(existing: list[i]) : null,
                      onDelete:
                          canDelete ? () => _confirmDelete(list[i]) : null,
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
            s.isAr ? 'عميل جديد' : 'New Client',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _open({Site? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientEditor(existing: existing),
    );
  }

  Future<void> _confirmDelete(Site c) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'حذف العميل' : 'Delete Client'),
        content: Text(s.isAr
            ? 'سيتم حذف ${c.companyName}. هل أنت متأكد؟'
            : 'Will delete ${c.companyName}. Are you sure?'),
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
        await SupabaseDataService().deleteSite(c.id);
      } else {
        MockRepository().sites.removeWhere((x) => x.id == c.id);
        MockRepository().notifyListeners();
      }
    }
  }
}

// ============================================================
// كارد عميل
// ============================================================
class _ClientCard extends StatelessWidget {
  final Site client;
  final bool isDark;
  /// 🆕 nullable — لو null البطاقة غير قابلة للضغط (لا صلاحيّة edit)
  final VoidCallback? onTap;
  /// 🆕 nullable — لو null زرّ الحذف مختفٍ
  final VoidCallback? onDelete;
  const _ClientCard({
    required this.client,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final master = client.masterId == null
        ? null
        : repo.masters.firstWhere(
            (m) => m.id == client.masterId,
            orElse: () => Master(
                id: '', code: '', name: '?', countryId: ''),
          );

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
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storefront,
                      color: AppColors.success, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.companyName,
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      if (master != null && master.id.isNotEmpty)
                        Text(
                          '${s.isAr ? "تابع لـ" : "Under"}: ${master.name}',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11),
                        ),
                      if (client.shortName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            client.shortName,
                            style: const TextStyle(
                                color: AppColors.brand,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 🆕 يَختفي لو لا يَملك صلاحيّة الحذف
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
// شيت عميل
// ============================================================
class _ClientEditor extends StatefulWidget {
  final Site? existing;
  final Master? prefilledMaster;
  const _ClientEditor({this.existing, this.prefilledMaster});

  @override
  State<_ClientEditor> createState() => _ClientEditorState();
}

class _ClientEditorState extends State<_ClientEditor> {
  final _company = TextEditingController();
  final _short = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  String? _masterId;
  String? _businessTypeId;
  String? _countryId;
  String? _cityId;
  String? _areaId;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (widget.existing != null) {
      final c = widget.existing!;
      _company.text = c.companyName;
      _short.text = c.shortName;
      _email.text = c.email;
      _phone.text = c.phone;
      _address.text = c.fullAddress;
      _taxId.text = c.taxId;
      _masterId = c.masterId;
      _businessTypeId = c.businessTypeId;
      _countryId = c.countryId;
      _cityId = c.cityId;
      _areaId = c.areaId;
    } else {
      _countryId = auth.activeCountryId;
      // لو فيه Master ممرّر مسبقاً، نضبطه + نضبط الدولة منه
      if (widget.prefilledMaster != null) {
        _masterId = widget.prefilledMaster!.id;
        _countryId = widget.prefilledMaster!.countryId;
      }
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _short.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _taxId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_company.text.trim().isEmpty) {
      _toast(s.isAr ? 'اسم الشركة مطلوب' : 'Company name required');
      return;
    }
    if (_countryId == null) {
      _toast(s.isAr ? 'الدولة مطلوبة' : 'Country required');
      return;
    }
    if (_masterId == null) {
      _toast(s.isAr
          ? 'اختر اسماً تجارياً (Master) أولاً'
          : 'Select a Master first');
      return;
    }
    final repo = MockRepository();
    final dataService = SupabaseDataService();
    final supaReady = SupabaseService().isReady;

    if (isEdit) {
      final c = widget.existing!;
      c.companyName = _company.text.trim();
      c.shortName = _short.text.trim();
      c.email = _email.text.trim();
      c.phone = _phone.text.trim();
      c.fullAddress = _address.text.trim();
      c.taxId = _taxId.text.trim();
      c.masterId = _masterId;
      c.businessTypeId = _businessTypeId;
      c.countryId = _countryId;
      c.cityId = _cityId;
      c.areaId = _areaId;
      if (supaReady) {
        final ok = await dataService.updateSite(c);
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
            technicalId: 'branch', countryId: _countryId!);
      }
      code ??= 'B-?';

      final c = Site(
        id: repo.generateId(),
        companyName: _company.text.trim(),
        shortName: _short.text.trim().isEmpty
            ? code
            : _short.text.trim(),
        masterId: _masterId,
        businessTypeId: _businessTypeId,
        countryId: _countryId,
        cityId: _cityId,
        areaId: _areaId,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        fullAddress: _address.text.trim(),
        taxId: _taxId.text.trim(),
        status: EntityStatus.active,
      );
      if (supaReady) {
        final created = await dataService.createSite(c);
        if (created == null) {
          _toast(dataService.lastError ?? 'Failed', isError: true);
          return;
        }
      } else {
        repo.addSite(c);
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
    // الـ Masters لنفس الدولة
    final mastersForCountry = _countryId == null
        ? <Master>[]
        : repo.masters.where((m) => m.countryId == _countryId).toList();
    final cities = _countryId == null
        ? <dynamic>[]
        : repo.cities.where((c) => c.countryId == _countryId).toList();
    final areas = _cityId == null
        ? <dynamic>[]
        : repo.areas.where((a) => a.cityId == _cityId).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
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
                          ? (s.isAr ? 'تعديل عميل' : 'Edit Client')
                          : (s.isAr ? 'عميل جديد' : 'New Client'),
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
                  // الدولة
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
                      _masterId = null;
                      _cityId = null;
                      _areaId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Master (مطلوب)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.business,
                                size: 14, color: AppColors.brand),
                            const SizedBox(width: 6),
                            Text(
                              s.isAr
                                  ? 'تابع لاسم تجاري (Master) *'
                                  : 'Belongs to a Master *',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brand),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _masterId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: s.isAr
                                ? 'اختر اسماً تجارياً'
                                : 'Choose a Master',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: mastersForCountry
                              .map((m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text('${m.code}  •  ${m.name}'),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _masterId = v),
                        ),
                        if (mastersForCountry.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            s.isAr
                                ? 'لا توجد أسماء تجارية بعد. أضف واحداً من تاب "Masters" أولاً.'
                                : 'No masters yet. Add one in "Masters" tab first.',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.danger),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _company,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'اسم الشركة *' : 'Company Name *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _short,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'الكود (سيُولّد تلقائياً إذا فارغ)'
                          : 'Code (auto-generated if empty)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // نوع النشاط
                  DropdownButtonFormField<String>(
                    value: _businessTypeId,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'نوع النشاط' : 'Business Type',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(s.isAr ? 'بدون' : 'None'),
                      ),
                      ...repo.businessTypes.map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(s.isAr ? b.nameAr : b.nameEn),
                          )),
                    ],
                    onChanged: (v) => setState(() => _businessTypeId = v),
                  ),
                  const SizedBox(height: 12),
                  // المدينة
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
                  // المنطقة
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
                      labelText: s.isAr ? 'العنوان' : 'Address',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'البريد الإلكتروني' : 'Email',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'الهاتف' : 'Phone',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxId,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'الرقم الضريبي' : 'Tax ID',
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
                          : (s.isAr ? 'إنشاء العميل' : 'Create Client'),
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
