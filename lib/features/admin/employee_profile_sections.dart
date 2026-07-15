import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/image_picker_service.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_dirty_tracker.dart';
import '../../shared/m7_section_scaffold.dart';

// ============================================================================
// 🧩 شَاشات تَعديل أَقسام مَلَفّ الموظَّف (مُنفَصِلة)
// ============================================================================
//
// كُلّ شاشة تُعالِج قِسماً واحِداً فَقَط مِن مَلَفّ الموظَّف، بِخِلاف المُحَرِّر
// الكامِل القَديم. هذا يُتيح تَجرِبة Hub & Spoke حَيث الـHub يَفتَح بِطاقات
// مُختَصَرة وَكُلّ بِطاقة تَنقُل إلى شاشَتها الخاصّة.
//
// نَمَط الحِفظ: تُعَدِّل كائِن الموظَّف مُباشَرة ثُمَّ تَستَدعي
// `SupabaseDataService.updateEmployee(e)` — نَفس النَمَط المُستَخدَم في
// `EmployeeEditorScreen._save()`.
// ============================================================================

// 💡 _SectionScaffold + _DirtyTrackerMixin + _confirmDiscard أُزيلَت
// واستُبدِلَت بِالنَسخ المُشتَرَكة في:
//   lib/shared/m7_section_scaffold.dart  →  M7SectionScaffold
//   lib/shared/m7_dirty_tracker.dart     →  M7DirtyTrackerMixin + showM7DiscardDialog

// مُساعِد لِحِفظ التَعديلات لِكائِن الموظَّف + تَسجيل audit تِلقائيّ
Future<bool> _persistEmployee(BuildContext context, Employee e,
    {String section = 'profile'}) async {
  final supaReady = SupabaseService().isReady;
  final repo = MockRepository();
  if (supaReady) {
    final ok = await SupabaseDataService().updateEmployee(e);
    if (!ok) return false;
  } else {
    repo.updateEmployee(e);
  }
  // 🆕 سَجِّل في سِجِلّ التَدقيق
  if (context.mounted) {
    final auth = context.read<AuthProvider>();
    AuditLogService.instance.log(
      action: AuditAction.update,
      entityType: 'employee',
      entityId: e.id,
      entityName: e.fullName,
      actorId: auth.account?.id,
      actorName: auth.account?.fullName,
      summary: 'Updated $section',
      countryId: e.countryId,
    );
  }
  return true;
}

// زَخرَفة مُوَحَّدة لِحُقول الإدخال
InputDecoration _dec(String label, {String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    );

// مُساعِد لاختِيار التاريخ
Future<DateTime?> _pickDate(BuildContext context, DateTime? current) async {
  return showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(1950),
    lastDate: DateTime(2100),
  );
}

// زِرّ تاريخ مُوَحَّد
Widget _dateField({
  required String label,
  required DateTime? value,
  required VoidCallback onTap,
  IconData icon = Icons.event,
}) =>
    InkWell(
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

// ============================================================
// 1️⃣ القِسم الشَخصيّ — الاسم/الكود/تواريخ
// ============================================================
class EmployeePersonalSection extends StatefulWidget {
  final Employee employee;
  const EmployeePersonalSection({super.key, required this.employee});

  @override
  State<EmployeePersonalSection> createState() =>
      _EmployeePersonalSectionState();
}

class _EmployeePersonalSectionState extends State<EmployeePersonalSection>
    with M7DirtyTrackerMixin<EmployeePersonalSection> {
  late final TextEditingController _fullName;
  late final TextEditingController _code;
  late final TextEditingController _fileNo; // 🆕 رقم الملف
  late final TextEditingController _education;
  DateTime? _birthDate;
  DateTime? _joiningDate;
  String? _maritalStatusId;
  String? _nationalityId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _fullName = TextEditingController(text: e.fullName);
    _code = TextEditingController(text: e.code);
    _fileNo = TextEditingController(text: e.fileNo); // 🆕
    _education = TextEditingController(text: e.education);
    _birthDate = e.birthDate;
    _joiningDate = e.joiningDate;
    _maritalStatusId = e.maritalStatusId;
    _nationalityId = e.nationalityId;
    track(_fullName);
    track(_code);
    track(_fileNo);
    track(_education);
  }

  @override
  void dispose() {
    _fullName.dispose();
    _code.dispose();
    _fileNo.dispose();
    _education.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_fullName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.isAr ? 'الاسم مطلوب' : 'Name is required')));
      return;
    }
    setState(() => _saving = true);
    final repo = MockRepository();
    final e = widget.employee;
    e.fullName = _fullName.text.trim();
    e.code = _code.text.trim();
    e.fileNo = _fileNo.text.trim(); // 🆕
    e.education = _education.text.trim();
    e.birthDate = _birthDate;
    e.joiningDate = _joiningDate;
    e.maritalStatusId = _maritalStatusId;
    e.nationalityId = _nationalityId;
    e.maritalStatus =
        repo.maritalStatusById(_maritalStatusId)?.displayName(true) ?? '';
    e.nationality =
        repo.nationalityById(_nationalityId)?.displayName(true) ?? '';
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    return M7SectionScaffold(
      titleAr: 'البَيانات الشَخصيّة',
      titleEn: 'Personal Info',
      icon: Icons.person,
      color: AppColors.brand,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _fullName,
          decoration: _dec(isAr ? 'الاسم الكامِل *' : 'Full name *',
              icon: Icons.person_outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          decoration: _dec(isAr ? 'الرَقم الوَظيفيّ' : 'Employee code',
              icon: Icons.tag),
        ),
        const SizedBox(height: 12),
        // 🆕 رقم الملف
        TextField(
          controller: _fileNo,
          decoration: _dec(isAr ? 'رَقم المِلَفّ' : 'File number',
              icon: Icons.folder_outlined),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ الميلاد' : 'Birth date',
                value: _birthDate,
                icon: Icons.cake_outlined,
                onTap: () async {
                  final d = await _pickDate(context, _birthDate);
                  if (d != null) {
                    markDirty();
                    setState(() => _birthDate = d);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ التَعيين' : 'Joining date',
                value: _joiningDate,
                icon: Icons.work_history_outlined,
                onTap: () async {
                  final d = await _pickDate(context, _joiningDate);
                  if (d != null) {
                    markDirty();
                    setState(() => _joiningDate = d);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _nationalityId,
          decoration: _dec(isAr ? 'الجِنسيّة' : 'Nationality',
              icon: Icons.flag_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.nationalities.map((n) => DropdownMenuItem<String?>(
                  value: n.id,
                  child: Text(n.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _nationalityId = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _maritalStatusId,
          decoration: _dec(isAr ? 'الحالة الاجتِماعيّة' : 'Marital status',
              icon: Icons.family_restroom),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.maritalStatuses.map((m) => DropdownMenuItem<String?>(
                  value: m.id,
                  child: Text(m.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _maritalStatusId = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _education,
          decoration: _dec(isAr ? 'المُؤَهِّل الدِراسيّ' : 'Education',
              icon: Icons.school_outlined),
        ),
      ],
    );
  }
}

// ============================================================
// 2️⃣ قِسم التَواصُل — جَوّال/إيميل/عُنوان/جِهة الطَوارِئ
// ============================================================
class EmployeeContactSection extends StatefulWidget {
  final Employee employee;
  const EmployeeContactSection({super.key, required this.employee});

  @override
  State<EmployeeContactSection> createState() =>
      _EmployeeContactSectionState();
}

class _EmployeeContactSectionState extends State<EmployeeContactSection>
    with M7DirtyTrackerMixin<EmployeeContactSection> {
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _emName;
  late final TextEditingController _emPhone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _mobile = TextEditingController(text: e.mobile);
    _email = TextEditingController(text: e.email);
    _address = TextEditingController(text: e.address);
    _emName = TextEditingController(text: e.emergencyContactName);
    _emPhone = TextEditingController(text: e.emergencyContactPhone);
    track(_mobile);
    track(_email);
    track(_address);
    track(_emName);
    track(_emPhone);
  }

  @override
  void dispose() {
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    _emName.dispose();
    _emPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.mobile = _mobile.text.trim();
    e.email = _email.text.trim();
    e.address = _address.text.trim();
    e.emergencyContactName = _emName.text.trim();
    e.emergencyContactPhone = _emPhone.text.trim();
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'بَيانات التَواصُل',
      titleEn: 'Contact Info',
      icon: Icons.contact_phone,
      color: AppColors.info,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration:
              _dec(isAr ? 'الجَوّال' : 'Mobile', icon: Icons.phone_iphone),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: _dec(isAr ? 'البَريد الإلِكتروني' : 'Email',
              icon: Icons.email_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration:
              _dec(isAr ? 'العُنوان' : 'Address', icon: Icons.home_outlined),
        ),
        const SizedBox(height: 18),
        Text(isAr ? 'جِهة الاتِّصال في الطَوارِئ' : 'Emergency Contact',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _emName,
          decoration:
              _dec(isAr ? 'الاسم' : 'Name', icon: Icons.person_outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emPhone,
          keyboardType: TextInputType.phone,
          decoration: _dec(isAr ? 'رَقم الجَوّال' : 'Phone number',
              icon: Icons.phone),
        ),
      ],
    );
  }
}

// ============================================================
// 3️⃣ قِسم جَواز السَفَر
// ============================================================
class EmployeePassportSection extends StatefulWidget {
  final Employee employee;
  const EmployeePassportSection({super.key, required this.employee});

  @override
  State<EmployeePassportSection> createState() =>
      _EmployeePassportSectionState();
}

class _EmployeePassportSectionState extends State<EmployeePassportSection>
    with M7DirtyTrackerMixin<EmployeePassportSection> {
  late final TextEditingController _number;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.employee.passportNumber);
    _expiry = widget.employee.passportExpiry;
    track(_number);
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.passportNumber = _number.text.trim();
    e.passportExpiry = _expiry;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'جَواز السَفَر',
      titleEn: 'Passport',
      icon: Icons.book,
      color: AppColors.gold,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _number,
          decoration: _dec(isAr ? 'رَقم الجَواز' : 'Passport number',
              icon: Icons.numbers),
        ),
        const SizedBox(height: 12),
        _dateField(
          label: isAr ? 'تاريخ الانتِهاء' : 'Expiry date',
          value: _expiry,
          icon: Icons.event_busy,
          onTap: () async {
            final d = await _pickDate(context, _expiry);
            if (d != null) {
              markDirty();
              setState(() => _expiry = d);
            }
          },
        ),
        if (_expiry != null) ...[
          const SizedBox(height: 10),
          _ExpiryHint(date: _expiry!),
        ],
      ],
    );
  }
}

// ============================================================
// 4️⃣ قِسم الهَوِيّة + تَأشيرة الإقامة
// ============================================================
class EmployeeIDSection extends StatefulWidget {
  final Employee employee;
  const EmployeeIDSection({super.key, required this.employee});

  @override
  State<EmployeeIDSection> createState() => _EmployeeIDSectionState();
}

class _EmployeeIDSectionState extends State<EmployeeIDSection>
    with M7DirtyTrackerMixin<EmployeeIDSection> {
  late final TextEditingController _idNumber;
  String? _visaTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _idNumber = TextEditingController(text: widget.employee.idNumber);
    _visaTypeId = widget.employee.visaTypeId;
    track(_idNumber);
  }

  @override
  void dispose() {
    _idNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = MockRepository();
    final e = widget.employee;
    e.idNumber = _idNumber.text.trim();
    e.visaTypeId = _visaTypeId;
    e.visaType = repo.visaTypeById(_visaTypeId)?.displayName(true) ?? '';
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    return M7SectionScaffold(
      titleAr: 'الهَوِيّة وَالتَأشيرة',
      titleEn: 'ID & Visa',
      icon: Icons.badge,
      color: AppColors.warning,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _idNumber,
          decoration: _dec(isAr ? 'رَقم الهَوِيّة' : 'ID number',
              icon: Icons.credit_card),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _visaTypeId,
          decoration: _dec(isAr ? 'نَوع التَأشيرة' : 'Visa type',
              icon: Icons.workspace_premium),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.visaTypes.map((v) => DropdownMenuItem<String?>(
                  value: v.id,
                  child: Text(v.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _visaTypeId = v);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? 'لِرَفع صورة الهَوِيّة أو تَجديدها، استَخدِم بِطاقة «الوَثائِق».'
                      : 'To upload or renew the ID image, use the «Documents» card.',
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
// 5️⃣ قِسم رُخصة القِيادة
// ============================================================
class EmployeeLicenseSection extends StatefulWidget {
  final Employee employee;
  const EmployeeLicenseSection({super.key, required this.employee});

  @override
  State<EmployeeLicenseSection> createState() =>
      _EmployeeLicenseSectionState();
}

class _EmployeeLicenseSectionState extends State<EmployeeLicenseSection>
    with M7DirtyTrackerMixin<EmployeeLicenseSection> {
  late final TextEditingController _number;
  DateTime? _issue;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.employee.licenseNumber);
    _issue = widget.employee.licenseIssue;
    _expiry = widget.employee.licenseExpiry;
    track(_number);
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.licenseNumber = _number.text.trim();
    e.licenseIssue = _issue;
    e.licenseExpiry = _expiry;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'رُخصة القِيادة',
      titleEn: 'Driving License',
      icon: Icons.drive_eta,
      color: Colors.purple,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _number,
          decoration: _dec(isAr ? 'رَقم الرُخصة' : 'License number',
              icon: Icons.numbers),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ الإصدار' : 'Issue date',
                value: _issue,
                icon: Icons.event_available,
                onTap: () async {
                  final d = await _pickDate(context, _issue);
                  if (d != null) {
                    markDirty();
                    setState(() => _issue = d);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ الانتِهاء' : 'Expiry date',
                value: _expiry,
                icon: Icons.event_busy,
                onTap: () async {
                  final d = await _pickDate(context, _expiry);
                  if (d != null) {
                    markDirty();
                    setState(() => _expiry = d);
                  }
                },
              ),
            ),
          ],
        ),
        if (_expiry != null) ...[
          const SizedBox(height: 10),
          _ExpiryHint(date: _expiry!),
        ],
      ],
    );
  }
}

// ============================================================
// 6️⃣ قِسم الراتِب وَالماليّات
// ============================================================
class EmployeeFinancialSection extends StatefulWidget {
  final Employee employee;
  const EmployeeFinancialSection({super.key, required this.employee});

  @override
  State<EmployeeFinancialSection> createState() =>
      _EmployeeFinancialSectionState();
}

class _EmployeeFinancialSectionState
    extends State<EmployeeFinancialSection>
    with M7DirtyTrackerMixin<EmployeeFinancialSection> {
  late final TextEditingController _basic;
  late final TextEditingController _ot;
  late final TextEditingController _train;
  late final TextEditingController _others;
  // 🆕 بَدَلات + سِعر ساعة الأوفرتايم
  late final TextEditingController _housing;
  late final TextEditingController _transport;
  late final TextEditingController _otherAllow;
  late final TextEditingController _otRate;
  late final TextEditingController _iban;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _basic = TextEditingController(
        text: e.basicSalary > 0 ? e.basicSalary.toString() : '');
    _ot = TextEditingController(
        text: e.overtime > 0 ? e.overtime.toString() : '');
    _train = TextEditingController(
        text: e.trainingFee > 0 ? e.trainingFee.toString() : '');
    _others =
        TextEditingController(text: e.others > 0 ? e.others.toString() : '');
    // 🆕
    _housing = TextEditingController(
        text: e.housingAllowance > 0 ? e.housingAllowance.toString() : '');
    _transport = TextEditingController(
        text: e.transportAllowance > 0 ? e.transportAllowance.toString() : '');
    _otherAllow = TextEditingController(
        text: e.otherAllowances > 0 ? e.otherAllowances.toString() : '');
    _otRate = TextEditingController(
        text: e.overtimeHourlyRate > 0 ? e.overtimeHourlyRate.toString() : '');
    _iban = TextEditingController(text: e.iban);
    track(_basic);
    track(_ot);
    track(_train);
    track(_others);
    track(_housing);
    track(_transport);
    track(_otherAllow);
    track(_otRate);
    track(_iban);
  }

  @override
  void dispose() {
    _basic.dispose();
    _ot.dispose();
    _train.dispose();
    _others.dispose();
    _housing.dispose();
    _transport.dispose();
    _otherAllow.dispose();
    _otRate.dispose();
    _iban.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.basicSalary = double.tryParse(_basic.text) ?? 0;
    e.overtime = double.tryParse(_ot.text) ?? 0;
    e.trainingFee = double.tryParse(_train.text) ?? 0;
    e.others = double.tryParse(_others.text) ?? 0;
    // 🆕 بَدَلات + سِعر ساعة الأوفرتايم
    e.housingAllowance = double.tryParse(_housing.text) ?? 0;
    e.transportAllowance = double.tryParse(_transport.text) ?? 0;
    e.otherAllowances = double.tryParse(_otherAllow.text) ?? 0;
    e.overtimeHourlyRate = double.tryParse(_otRate.text) ?? 0;
    e.iban = _iban.text.trim();
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final basic = double.tryParse(_basic.text) ?? 0;
    final ot = double.tryParse(_ot.text) ?? 0;
    final tr = double.tryParse(_train.text) ?? 0;
    final oth = double.tryParse(_others.text) ?? 0;
    final housing = double.tryParse(_housing.text) ?? 0;
    final transport = double.tryParse(_transport.text) ?? 0;
    final otherAllow = double.tryParse(_otherAllow.text) ?? 0;
    final gross = basic + ot + tr + oth + housing + transport + otherAllow;
    return M7SectionScaffold(
      titleAr: 'الراتِب وَالماليّات',
      titleEn: 'Salary & Financials',
      icon: Icons.attach_money,
      color: AppColors.success,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _basic,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _dec(isAr ? 'الراتِب الأساسيّ' : 'Basic salary',
              icon: Icons.payments),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ot,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(isAr ? 'OT (إضافيّ)' : 'Overtime',
                    icon: Icons.timer_outlined),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _train,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    _dec(isAr ? 'رَسم التَدريب' : 'Training fee',
                        icon: Icons.school),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _others,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _dec(isAr ? 'بُنود أُخرى' : 'Other items',
              icon: Icons.list_alt),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // 🆕 بَدَل السَكَن + بَدَل المُواصَلات
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _housing,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                    isAr ? 'بَدَل السَكَن' : 'Housing allowance',
                    icon: Icons.home_outlined),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _transport,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                    isAr ? 'بَدَل المُواصَلات' : 'Transport allowance',
                    icon: Icons.directions_bus_outlined),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 🆕 بَدَلات أُخرى + سِعر ساعة الأوفرتايم
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _otherAllow,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                    isAr ? 'بَدَلات أُخرى' : 'Other allowances',
                    icon: Icons.add_circle_outline),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _otRate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                    isAr ? 'سِعر ساعة الأوفرتايم' : 'Overtime hourly rate',
                    icon: Icons.schedule),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _iban,
          decoration: _dec(isAr ? 'الـ IBAN' : 'IBAN',
              icon: Icons.account_balance),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calculate,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                isAr ? 'إجمالي مُتَوَقَّع: ' : 'Expected gross: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                gross.toStringAsFixed(2),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    color: AppColors.success),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 7️⃣ قِسم اليونيفورم — مَقاسات
// ============================================================
class EmployeeUniformSection extends StatefulWidget {
  final Employee employee;
  const EmployeeUniformSection({super.key, required this.employee});

  @override
  State<EmployeeUniformSection> createState() =>
      _EmployeeUniformSectionState();
}

class _EmployeeUniformSectionState extends State<EmployeeUniformSection>
    with M7DirtyTrackerMixin<EmployeeUniformSection> {
  late final TextEditingController _shirt;
  late final TextEditingController _pant;
  late final TextEditingController _shoe;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shirt = TextEditingController(text: widget.employee.shirtSize);
    _pant = TextEditingController(text: widget.employee.pantSize);
    _shoe = TextEditingController(text: widget.employee.shoeSize);
    track(_shirt);
    track(_pant);
    track(_shoe);
  }

  @override
  void dispose() {
    _shirt.dispose();
    _pant.dispose();
    _shoe.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.shirtSize = _shirt.text.trim();
    e.pantSize = _pant.text.trim();
    e.shoeSize = _shoe.text.trim();
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return M7SectionScaffold(
      titleAr: 'مَقاسات اليونيفورم',
      titleEn: 'Uniform Sizes',
      icon: Icons.checkroom,
      color: Colors.indigo,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        TextField(
          controller: _shirt,
          decoration: _dec(isAr ? 'مَقاس القَميص' : 'Shirt size',
              icon: Icons.checkroom),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pant,
          decoration: _dec(isAr ? 'مَقاس البَنطَلون' : 'Pant size',
              icon: Icons.straighten),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _shoe,
          decoration: _dec(isAr ? 'مَقاس الحِذاء' : 'Shoe size',
              icon: Icons.directions_walk),
        ),
      ],
    );
  }
}

// ============================================================
// 8️⃣ قِسم الباص الافتِراضيّ
// ============================================================
class EmployeeBusSection extends StatefulWidget {
  final Employee employee;
  const EmployeeBusSection({super.key, required this.employee});

  @override
  State<EmployeeBusSection> createState() => _EmployeeBusSectionState();
}

class _EmployeeBusSectionState extends State<EmployeeBusSection>
    with M7DirtyTrackerMixin<EmployeeBusSection> {
  String? _busId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _busId = widget.employee.defaultBusId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.defaultBusId = _busId;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final buses = repo.buses;
    return M7SectionScaffold(
      titleAr: 'الباص الافتِراضيّ',
      titleEn: 'Default Bus',
      icon: Icons.directions_bus,
      color: Colors.teal,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        DropdownButtonFormField<String?>(
          value: _busId,
          decoration: _dec(isAr ? 'الباص' : 'Bus',
              icon: Icons.directions_bus_outlined),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('— (none)')),
            ...buses.map((b) => DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text('${b.plateNumber} · ${b.shownLabel}'),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _busId = v);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? 'يُمكِن تَجاوُز الباص الافتِراضيّ ليَوم مُحَدَّد عَبر «تَعيين باص يَوميّ».'
                      : 'Can be overridden per day via «Daily Bus Assignment».',
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
// 9️⃣ قِسم الدَور الوَظيفيّ (Job & Role)
// ============================================================
class EmployeeJobRoleSection extends StatefulWidget {
  final Employee employee;
  const EmployeeJobRoleSection({super.key, required this.employee});

  @override
  State<EmployeeJobRoleSection> createState() =>
      _EmployeeJobRoleSectionState();
}

class _EmployeeJobRoleSectionState extends State<EmployeeJobRoleSection>
    with M7DirtyTrackerMixin<EmployeeJobRoleSection> {
  String? _jobTitleId;
  String? _departmentId;
  String _category = 'worker';
  EmployeeHireType _hireType = EmployeeHireType.trainee;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _jobTitleId = e.jobTitleId;
    _departmentId = e.departmentId;
    _category = e.category.isEmpty ? 'worker' : e.category;
    _hireType = e.hireType;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = MockRepository();
    final e = widget.employee;
    e.jobTitleId = _jobTitleId;
    e.departmentId = _departmentId;
    e.category = _category;
    e.hireType = _hireType;
    e.jobTitle = repo.jobTitleById(_jobTitleId)?.displayName(true) ?? '';
    e.department = repo.departmentById(_departmentId)?.displayName(true) ?? '';
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    return M7SectionScaffold(
      titleAr: 'الدَور الوَظيفيّ',
      titleEn: 'Job & Role',
      icon: Icons.work_outline,
      color: Colors.deepPurple,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        DropdownButtonFormField<String?>(
          value: _jobTitleId,
          decoration: _dec(isAr ? 'المُسَمّى الوَظيفيّ' : 'Job title',
              icon: Icons.badge_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.jobTitles.map((j) => DropdownMenuItem<String?>(
                  value: j.id,
                  child: Text(j.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _jobTitleId = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _departmentId,
          decoration: _dec(isAr ? 'القِسم' : 'Department',
              icon: Icons.account_tree_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.departments.map((d) => DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(d.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _departmentId = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: _dec(isAr ? 'فِئة المُوظَّف' : 'Category',
              icon: Icons.category_outlined),
          items: [
            DropdownMenuItem(
                value: 'worker',
                child: Text(isAr ? 'عامِل (worker)' : 'Worker')),
            DropdownMenuItem(
                value: 'admin',
                child: Text(isAr ? 'إداريّ (admin)' : 'Admin')),
            DropdownMenuItem(
                value: 'operations',
                child: Text(isAr ? 'تَشغيل (operations)' : 'Operations')),
          ],
          onChanged: (v) {
            if (v == null) return;
            markDirty();
            setState(() => _category = v);
          },
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    isAr ? 'نَوع الالتِحاق' : 'Hire type',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              RadioListTile<EmployeeHireType>(
                dense: true,
                title: Text(isAr
                    ? '🎓 مُتَدَرِّب (Trainee)'
                    : '🎓 Trainee'),
                subtitle: Text(
                  isAr
                      ? 'يَدخُل تَلقائيّاً إلى OnPointTraining'
                      : 'Automatically enrolled in OnPointTraining',
                  style: const TextStyle(fontSize: 10),
                ),
                value: EmployeeHireType.trainee,
                groupValue: _hireType,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _hireType = v);
                },
              ),
              RadioListTile<EmployeeHireType>(
                dense: true,
                title: Text(isAr ? '💼 مُحتَرِف (Professional)' : '💼 Professional'),
                value: EmployeeHireType.professional,
                groupValue: _hireType,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _hireType = v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 🔟 قِسم السَكَن وَالنَقل (Housing & Transport)
// ============================================================
class EmployeeHousingSection extends StatefulWidget {
  final Employee employee;
  const EmployeeHousingSection({super.key, required this.employee});

  @override
  State<EmployeeHousingSection> createState() =>
      _EmployeeHousingSectionState();
}

class _EmployeeHousingSectionState extends State<EmployeeHousingSection>
    with M7DirtyTrackerMixin<EmployeeHousingSection> {
  HousingType _housing = HousingType.offCamp;
  String? _transportModeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _housing = widget.employee.housingType;
    _transportModeId = widget.employee.transportModeId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.housingType = _housing;
    e.transportModeId = _transportModeId;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    return M7SectionScaffold(
      titleAr: 'السَكَن وَالنَقل',
      titleEn: 'Housing & Transport',
      icon: Icons.home_work_outlined,
      color: Colors.brown,
      editPermission: P.employeesEdit,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    isAr ? 'نَوع السَكَن' : 'Housing type',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              RadioListTile<HousingType>(
                dense: true,
                title: Text(isAr ? '🏕️ في الكامب (onCamp)' : '🏕️ On Camp'),
                subtitle: Text(
                  isAr
                      ? 'يَستَخدِم خَدَمات الكامب (غُرَف، يونيفورم، غَسيل)'
                      : 'Uses camp services (rooms, uniform, laundry)',
                  style: const TextStyle(fontSize: 10),
                ),
                value: HousingType.onCamp,
                groupValue: _housing,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _housing = v);
                },
              ),
              RadioListTile<HousingType>(
                dense: true,
                title: Text(isAr ? '🏠 خارِج الكامب (offCamp)' : '🏠 Off Camp'),
                subtitle: Text(
                  isAr
                      ? 'يَدخُل في خُطّة الباصات/التَوصيل'
                      : 'Eligible for bus plan / transport',
                  style: const TextStyle(fontSize: 10),
                ),
                value: HousingType.offCamp,
                groupValue: _housing,
                onChanged: (v) {
                  if (v == null) return;
                  markDirty();
                  setState(() => _housing = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          value: _transportModeId,
          decoration: _dec(isAr ? 'وَسيلة النَقل' : 'Transport mode',
              icon: Icons.directions_bus_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.transportModes.map((t) => DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text(t.displayName(isAr)),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _transportModeId = v);
          },
        ),
      ],
    );
  }
}

// ============================================================
// 1️⃣1️⃣ قِسم النُقطة وَالحالة (Point & Status)
// ============================================================
class EmployeePointStatusSection extends StatefulWidget {
  final Employee employee;
  const EmployeePointStatusSection({super.key, required this.employee});

  @override
  State<EmployeePointStatusSection> createState() =>
      _EmployeePointStatusSectionState();
}

class _EmployeePointStatusSectionState
    extends State<EmployeePointStatusSection>
    with M7DirtyTrackerMixin<EmployeePointStatusSection> {
  String? _pointId;
  EntityStatus _status = EntityStatus.active;
  DateTime? _activationDate;
  DateTime? _deactivationDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _pointId = e.pointId;
    _status = e.status;
    _activationDate = e.activationDate;
    _deactivationDate = e.deactivationDate;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.pointId = _pointId;
    e.status = _status;
    e.activationDate = _activationDate;
    e.deactivationDate = _deactivationDate;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    return M7SectionScaffold(
      titleAr: 'النُقطة وَالحالة',
      titleEn: 'Point & Status',
      icon: Icons.flag_circle_outlined,
      color: Colors.cyan,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        DropdownButtonFormField<String?>(
          value: _pointId,
          decoration: _dec(isAr ? 'نُقطة العَمَل' : 'Work point',
              icon: Icons.location_on_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...repo.points.map((p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text('${p.code} · ${p.name}'),
                )),
          ],
          onChanged: (v) {
            markDirty();
            setState(() => _pointId = v);
          },
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    isAr ? 'الحالة' : 'Status',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
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
                onTap: () async {
                  final d = await _pickDate(context, _activationDate);
                  if (d != null) {
                    markDirty();
                    setState(() => _activationDate = d);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateField(
                label: isAr ? 'تاريخ الإيقاف' : 'Deactivation date',
                value: _deactivationDate,
                icon: Icons.event_busy,
                onTap: () async {
                  final d = await _pickDate(context, _deactivationDate);
                  if (d != null) {
                    markDirty();
                    setState(() => _deactivationDate = d);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 1️⃣2️⃣ قِسم الصورة الشَخصيّة (Photo)
// ============================================================
class EmployeePhotoSection extends StatefulWidget {
  final Employee employee;
  const EmployeePhotoSection({super.key, required this.employee});

  @override
  State<EmployeePhotoSection> createState() => _EmployeePhotoSectionState();
}

class _EmployeePhotoSectionState extends State<EmployeePhotoSection>
    with M7DirtyTrackerMixin<EmployeePhotoSection> {
  String? _photoFileId;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _photoFileId = widget.employee.photoFileId;
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    final result = await ImagePickerService.pickAndUpload(
      context: context,
      bucket: 'employee_photos',
      pathPrefix: 'emp_${widget.employee.id}_photo',
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result == null) return;
    // 🆕 نَحفَظ الـURL العامّ فَقَط — Image.network يَحتاج URL صَحيح.
    // (نَفس نَمَط _UploadBox في المُحَرِّر القَديم)
    if (result.url == null || result.url!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(AppStrings.of(context).isAr
            ? 'فَشَل الرَفع — لَم يُرجَع رابِط صَحيح'
            : 'Upload failed — no valid URL returned'),
      ));
      return;
    }
    markDirty();
    setState(() => _photoFileId = result.url);
  }

  void _removePhoto() {
    markDirty();
    setState(() => _photoFileId = null);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.employee;
    e.photoFileId = _photoFileId;
    final ok = await _persistEmployee(context, e);
    if (!mounted) return;
    setState(() => _saving = false);
    final s = AppStrings.of(context);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.success)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              SupabaseDataService().lastError ?? (s.isAr ? 'فَشَل' : 'Failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final hasPhoto = _photoFileId != null && _photoFileId!.isNotEmpty;
    return M7SectionScaffold(
      titleAr: 'الصورة الشَخصيّة',
      titleEn: 'Profile Photo',
      icon: Icons.photo_camera_outlined,
      color: Colors.pink,
      editPermission: P.employeesEdit,
      saving: _saving,
      onSave: _save,
      isDirty: () => isDirty,
      children: [
        Center(
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasPhoto ? AppColors.success : Colors.grey.shade400,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _uploading
                ? const CircularProgressIndicator()
                : hasPhoto
                    ? Image.network(
                        _photoFileId!,
                        fit: BoxFit.cover,
                        width: 180,
                        height: 180,
                        errorBuilder: (_, __, ___) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.broken_image_outlined,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 6),
                            Text(
                              isAr ? 'تَعَذُّر العَرض' : 'Preview unavailable',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_outline,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 6),
                          Text(
                            isAr ? 'لا تُوجَد صورة' : 'No photo',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _pickPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(isAr
                    ? (hasPhoto ? 'تَغيير الصورة' : 'إضافة صورة')
                    : (hasPhoto ? 'Change photo' : 'Add photo')),
              ),
            ),
            if (hasPhoto) ...[
              const SizedBox(width: 10),
              IconButton.outlined(
                onPressed: _uploading ? null : _removePhoto,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: isAr ? 'إزالة' : 'Remove',
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? 'تَظهَر الصورة في قائِمة المُوظَّفين، كَشف الراتِب، وَتَقارير الحُضور.'
                      : 'Appears in employee list, payroll, and attendance reports.',
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
// مُكَوِّن مُساعِد: تَلميح انتِهاء قَريب
// ============================================================
class _ExpiryHint extends StatelessWidget {
  final DateTime date;
  const _ExpiryHint({required this.date});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final days = date.difference(DateTime.now()).inDays;
    final Color c;
    final String txt;
    final IconData ic;
    if (days < 0) {
      c = Colors.red;
      ic = Icons.error_outline;
      txt = isAr
          ? 'مُنتَهيَة الصَلاحِيّة (${-days} يوم)'
          : 'Expired (${-days}d ago)';
    } else if (days <= 30) {
      c = Colors.orange;
      ic = Icons.warning_amber_rounded;
      txt = isAr
          ? 'تَنتَهي خِلال $days يَوم'
          : 'Expires in $days day(s)';
    } else if (days <= 90) {
      c = Colors.amber.shade700;
      ic = Icons.info_outline;
      txt = isAr ? 'تَنتَهي خِلال $days يَوم' : 'Expires in $days days';
    } else {
      c = Colors.green;
      ic = Icons.check_circle_outline;
      txt = isAr ? 'سارِية ($days يَوم)' : 'Valid ($days days left)';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(ic, size: 16, color: c),
          const SizedBox(width: 6),
          Text(txt,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}
