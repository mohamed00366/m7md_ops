import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/deletion_guard.dart';
import '../../shared/permission_gate.dart';

/// شاشة إدارة الدول (CRUD كامل) - متاحة لـ Super Admin
class AdminCountries extends StatefulWidget {
  const AdminCountries({super.key});

  @override
  State<AdminCountries> createState() => _AdminCountriesState();
}

class _AdminCountriesState extends State<AdminCountries> {
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

  void _openEditor({Country? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryEditor(existing: existing),
    );
  }

  Future<void> _confirmDelete(Country c) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // إحصاءات الارتباطات
    final cities = repo.cities.where((x) => x.countryId == c.id).length;
    final employees =
        repo.employees.where((x) => x.countryId == c.id).length;
    final sites = repo.sites.where((x) => x.countryId == c.id).length;
    final blockers = <DeletionLink>[
      if (cities > 0)
        DeletionLink(
            label: s.isAr ? 'مدينة' : 'cities',
            count: cities,
            icon: Icons.location_city),
      if (employees > 0)
        DeletionLink(
            label: s.isAr ? 'موظف' : 'employees',
            count: employees,
            icon: Icons.people),
      if (sites > 0)
        DeletionLink(
            label: s.isAr ? 'موقع/عميل' : 'sites/clients',
            count: sites,
            icon: Icons.business),
    ];
    final ok = await DeletionGuard.requireSafe(
      context,
      entityName: s.isAr ? 'دولة' : 'country',
      subjectName: s.isAr ? c.nameAr : c.nameEn,
      blockers: blockers,
    );
    if (!ok || !context.mounted) return;
    if (SupabaseService().isReady) {
      final ds = SupabaseDataService();
      final ok2 = await ds.deleteCountry(c.id);
      if (!ok2 && context.mounted) {
        await DeletionGuard.showServerLinkError(context,
            entityName: s.isAr ? 'دولة' : 'country',
            rawError: ds.lastError);
      }
    } else {
      repo.countries.removeWhere((x) => x.id == c.id);
      repo.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final countries = [...repo.countries]..sort((a, b) => a.code.compareTo(b.code));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
        children: [
          // ===== ملاحظة =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.brand.withOpacity(0.3), width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.brand, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.isAr
                        ? 'كل دولة لها كود ISO، رمز هاتف، وعملة. الكود يستخدم في توليد رموز الموظفين (مثلاً EMP-LB-0001 للبنان).'
                        : 'Each country has ISO code, phone code, currency. The code is used in entity numbering (e.g. EMP-LB-0001 for Lebanon).',
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ===== قائمة الدول =====
          ...countries.map((c) {
            final users = repo.userCountryAccess
                .where((u) => u.countryId == c.id)
                .map((u) => u.userId)
                .toSet()
                .length;
            final cities = repo.cities.where((x) => x.countryId == c.id).length;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDark
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                    width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.brand,
                          AppColors.brand.withOpacity(0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      c.code,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isAr ? c.nameAr : c.nameEn,
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textDark
                                  : AppColors.textLight,
                              fontSize: 15,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.phoneCode} • ${c.currency}',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            _MiniBadge(
                                icon: Icons.people,
                                label: '$users',
                                color: AppColors.success),
                            _MiniBadge(
                                icon: Icons.location_city,
                                label: '$cities',
                                color: AppColors.info),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 🆕 الزرّان يَظهران فقط لمن يملك صلاحيّة الإدارة
                  PermissionGate(
                    permission: P.adminCountriesManage,
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _openEditor(existing: c),
                    ),
                  ),
                  PermissionGate(
                    permission: P.adminCountriesManage,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      onPressed: () => _confirmDelete(c),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.adminCountriesManage,
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.brand,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            s.isAr ? 'دولة جديدة' : 'New Country',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniBadge(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شيت إنشاء/تعديل دولة
// ============================================================
class _CountryEditor extends StatefulWidget {
  final Country? existing;
  const _CountryEditor({this.existing});

  @override
  State<_CountryEditor> createState() => _CountryEditorState();
}

class _CountryEditorState extends State<_CountryEditor> {
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _code = TextEditingController();
  final _phoneCode = TextEditingController();
  final _currency = TextEditingController();
  final _flag = TextEditingController();

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final c = widget.existing!;
      _nameAr.text = c.nameAr;
      _nameEn.text = c.nameEn;
      _code.text = c.code;
      _phoneCode.text = c.phoneCode;
      _currency.text = c.currency;
      _flag.text = c.flagEmoji;
    }
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _code.dispose();
    _phoneCode.dispose();
    _currency.dispose();
    _flag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_nameAr.text.trim().isEmpty ||
        _nameEn.text.trim().isEmpty ||
        _code.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr
                ? 'الاسم والكود مطلوبان'
                : 'Name and code are required')),
      );
      return;
    }
    final code = _code.text.trim().toUpperCase();
    if (code.length > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr
                ? 'الكود يجب ألا يتجاوز 3 أحرف'
                : 'Code must be 3 characters or less')),
      );
      return;
    }
    final supaReady = SupabaseService().isReady;
    if (isEdit) {
      final c = widget.existing!;
      c.nameAr = _nameAr.text.trim();
      c.nameEn = _nameEn.text.trim();
      c.code = code;
      c.phoneCode = _phoneCode.text.trim();
      c.currency = _currency.text.trim();
      c.flagEmoji = _flag.text.trim();
      if (supaReady) {
        await SupabaseDataService().updateCountry(c);
      } else {
        MockRepository().notifyListeners();
      }
    } else {
      if (supaReady) {
        final created = await SupabaseDataService().createCountry(
          nameAr: _nameAr.text.trim(),
          nameEn: _nameEn.text.trim(),
          code: code,
          phoneCode: _phoneCode.text.trim(),
          currency: _currency.text.trim(),
          flagEmoji: _flag.text.trim(),
        );
        if (created == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(s.isAr
                    ? 'فشل الإنشاء (الكود قد يكون موجوداً)'
                    : 'Failed (code may already exist)')),
          );
          return;
        }
      } else {
        final repo = MockRepository();
        repo.countries.add(Country(
          id: repo.generateId(),
          nameAr: _nameAr.text.trim(),
          nameEn: _nameEn.text.trim(),
          code: code,
          phoneCode: _phoneCode.text.trim(),
          currency: _currency.text.trim(),
          flagEmoji: _flag.text.trim(),
        ));
        repo.notifyListeners();
      }
    }
    if (!context.mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                          ? (s.isAr ? 'تعديل دولة' : 'Edit Country')
                          : (s.isAr ? 'دولة جديدة' : 'New Country'),
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
                  // ملاحظة المثال
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s.isAr
                          ? 'مثال: لبنان — الاسم: لبنان / Lebanon، الكود: LB، رمز الهاتف: +961، العملة: LBP'
                          : 'Example: Lebanon — Code: LB, Phone: +961, Currency: LBP',
                      style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: s.isAr ? 'الاسم بالعربية' : 'Name (AR)',
                    controller: _nameAr,
                    hint: s.isAr ? 'لبنان' : 'لبنان',
                  ),
                  _Field(
                    label: s.isAr ? 'الاسم بالإنجليزية' : 'Name (EN)',
                    controller: _nameEn,
                    hint: 'Lebanon',
                  ),
                  _Field(
                    label: s.isAr ? 'كود ISO (حرفان أو 3)' : 'ISO Code (2-3)',
                    controller: _code,
                    hint: 'LB',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: s.isAr ? 'رمز الهاتف' : 'Phone Code',
                          controller: _phoneCode,
                          hint: '+961',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Field(
                          label: s.isAr ? 'العملة' : 'Currency',
                          controller: _currency,
                          hint: 'LBP',
                        ),
                      ),
                    ],
                  ),
                  _Field(
                    label: s.isAr
                        ? 'الراية (إيموجي اختياري)'
                        : 'Flag (emoji, optional)',
                    controller: _flag,
                    hint: 'LB',
                  ),
                  const SizedBox(height: 18),
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
                          : (s.isAr ? 'إنشاء الدولة' : 'Create Country'),
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

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
