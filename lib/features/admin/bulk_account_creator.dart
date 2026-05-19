import 'dart:math';
import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/services/face_enrollment_policy_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// 🪪 شاشة إنشاء حسابات دُخول جَماعيّ لِلْمُوَظَّفين بِدون حساب.
///
/// تُتيح:
/// - عَرض كلّ الموظّفين الذين لا يَملكون حساباً مَربوطاً
/// - اختيار من تُريد إنشاء حساب لَه
/// - تَوليد username تلقائيّ (من الـcode أو full_name)
/// - تَوليد كلمة مرور مُؤَقَّتة (random secure)
/// - رَبط الحساب بِمسمّى الموظّف الوظيفيّ + دَولَتِه + الأدوار المُناسبة
/// - وَضع `must_change_password = true` تلقائيّاً
/// - تَصدير Excel بِأسماء الموظّفين + usernames + كلمات المرور المُؤَقَّتة
class BulkAccountCreatorScreen extends StatefulWidget {
  const BulkAccountCreatorScreen({super.key});

  @override
  State<BulkAccountCreatorScreen> createState() =>
      _BulkAccountCreatorScreenState();
}

class _BulkAccountCreatorScreenState extends State<BulkAccountCreatorScreen> {
  final Set<String> _selected = {}; // employee IDs
  bool _busy = false;
  // نَتيجة الإنشاء — تَصلُح للتَصدير بَعد الانتهاء.
  final List<_CreatedCredential> _lastCreated = [];

  /// كلّ الموظّفين النَشطين الذين لا يوجد حساب مَربوط بِهم.
  ///
  /// 🔐 **فلتر هَرَميّ:** يَستَثني الموظّفين الّذين مُسمّاهم الوظيفيّ يَحمِل
  /// دَوراً مُساوياً أو أَعلى من المُستَخدِم الحاليّ. مَثلاً HR (priority=20)
  /// لن يَرى Manager (priority=80) أو Admin (priority=90).
  /// Super Admin يَرى الكلّ.
  List<Employee> _employeesWithoutAccount(
      MockRepository repo, AuthProvider auth) {
    final linked = <String>{
      for (final a in repo.accounts)
        if (a.employeeId != null && a.employeeId!.isNotEmpty)
          a.employeeId!
    };
    return repo.employees
        .where((e) {
          if (e.status != EntityStatus.active) return false;
          if (linked.contains(e.id)) return false;
          // 🔐 فلتر هَرَميّ — لا تَعرِض موظّفين أَعلى مُستوى منكَ
          if (!_canManageEmployeeHierarchy(repo, auth, e)) return false;
          return true;
        })
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  /// هل المُستَخدِم الحاليّ يَستَطيع إنشاء حساب لِهذا الموظّف؟
  /// يَتَحَقَّق من:
  ///   - المُستَخدِم Super Admin → نَعَم لِلْكلّ
  ///   - مُستوى الموظّف < مُستوى المُستَخدِم الحاليّ
  bool _canManageEmployeeHierarchy(
      MockRepository repo, AuthProvider auth, Employee emp) {
    if (auth.isSuperAdmin) return true;
    final myTop = auth.topPriority;
    // اعثر على دَور الموظّف من مُسمّاه الوظيفيّ
    if (emp.jobTitleId == null) {
      // بِدون مُسمّى → يُعتَبَر مُستوى مُنخَفِض → مَسموح
      return true;
    }
    try {
      final jt = repo.jobTitles.firstWhere((j) => j.id == emp.jobTitleId);
      if (jt.roleId == null) {
        // المُسمّى لَه دَور لكن لم يَنشأ بَعد → مَسموح
        return true;
      }
      final role = repo.roleDefs.firstWhere((r) => r.id == jt.roleId);
      // الدَور النظاميّ Super Admin → ممنوع لِغَير Super Admin
      if (role.key == SystemRoles.superAdmin) return false;
      // المُستوى يَجِب أن يَكون أَقَلّ من المُستَخدِم
      return role.priority < myTop;
    } catch (_) {
      // أيّ شَكّ → مَسموح (الفلتر الأَمنيّ في DB يَتولّى الباقي)
      return true;
    }
  }

  /// تَوليد username من الـcode أو الاسم.
  String _suggestUsername(Employee emp) {
    final code = emp.code.trim();
    if (code.isNotEmpty) return code.toLowerCase();
    final name = emp.fullName.trim().toLowerCase();
    return name.replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  /// تَوليد كلمة مرور مُؤَقَّتة (10 خانات: حُروف+أرقام+رَمز).
  String _generatePassword() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // بدون I, O
    const small = 'abcdefghjkmnpqrstuvwxyz'; // بدون i, l, o
    const digits = '23456789'; // بدون 0, 1
    const symbols = '!@#\$%&*';
    final r = Random.secure();
    return [
      letters[r.nextInt(letters.length)],
      small[r.nextInt(small.length)],
      small[r.nextInt(small.length)],
      digits[r.nextInt(digits.length)],
      digits[r.nextInt(digits.length)],
      letters[r.nextInt(letters.length)],
      small[r.nextInt(small.length)],
      digits[r.nextInt(digits.length)],
      symbols[r.nextInt(symbols.length)],
      letters[r.nextInt(letters.length)],
    ].join();
  }

  /// يَختار قائمة roleIds مُناسبة بِناءً على المُسمّى الوظيفيّ:
  /// إذا الـjob_title لَه role_id → نَستَعمِله.
  /// وإلّا → نَأخذ دَور "employee" النظاميّ كـfallback.
  List<String> _resolveRoleIds(MockRepository repo, Employee emp) {
    final ids = <String>[];
    if (emp.jobTitleId != null) {
      try {
        final jt =
            repo.jobTitles.firstWhere((j) => j.id == emp.jobTitleId);
        if (jt.roleId != null && jt.roleId!.isNotEmpty) {
          ids.add(jt.roleId!);
        }
      } catch (_) {}
    }
    if (ids.isEmpty) {
      try {
        final empRole =
            repo.roleDefs.firstWhere((r) => r.key == SystemRoles.employee);
        ids.add(empRole.id);
      } catch (_) {}
    }
    return ids;
  }

  Future<void> _createAccounts() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
    if (!supaReady) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? '❌ يَجب الاتّصال بـSupabase لإنشاء حسابات'
            : '❌ Supabase connection required'),
      ));
      return;
    }
    if (_selected.isEmpty) return;

    setState(() {
      _busy = true;
      _lastCreated.clear();
    });

    // 🔐 حَمِّل سياسة تَسجيل بَصمة الوَجه مَرّة واحِدة قَبل الحَلقة
    await FaceEnrollmentPolicySettings.instance.load();
    final facePolicy = FaceEnrollmentPolicySettings.instance;

    final created = <_CreatedCredential>[];
    final failed = <String>[];

    final auth = context.read<AuthProvider>();
    for (final empId in _selected) {
      final emp = repo.employeeById(empId);
      if (emp == null) continue;
      // 🔐 فَحص دِفاعيّ — لا تَخلق حساباً أَعلى مُستوى من المُنشِئ
      if (!_canManageEmployeeHierarchy(repo, auth, emp)) {
        failed.add('${emp.fullName} (مُستوى أَعلى — مَحجوب)');
        continue;
      }

      final username = _suggestUsername(emp);
      // تَأكَّد أنّ الـusername فَريد
      final dup = repo.accounts
          .any((a) => a.username.toLowerCase() == username.toLowerCase());
      if (dup) {
        failed.add('${emp.fullName} (username موجود: $username)');
        continue;
      }

      final tempPass = _generatePassword();
      // 🔐 إذا السياسة تَشمَل مُسَمَّى الموظَّف، نُضَع mustEnrollFace=true
      final requireFace = facePolicy.requiresEnrollment(emp.jobTitleId);
      final acc = AppAccount(
        id: repo.generateId(),
        username: username,
        passwordHash: tempPass,
        fullName: emp.fullName,
        email: emp.email.isEmpty ? null : emp.email,
        phone: emp.mobile.isEmpty ? null : emp.mobile,
        employeeId: emp.id,
        isActive: true,
        isSuperAdmin: false,
        mustChangePassword: true, // 🔐 يُجبَر على التَغيير
        mustEnrollFace: requireFace, // 🔐 يُجبَر على تَسجيل البَصمة
      );

      final roleIds = _resolveRoleIds(repo, emp);
      final countryIds =
          (emp.countryId != null && emp.countryId!.isNotEmpty)
              ? [emp.countryId!]
              : <String>[];

      final result = await ds.createAccount(
        acc,
        roleIds: roleIds,
        countryIds: countryIds,
      );
      if (result == null) {
        failed.add('${emp.fullName} (${ds.lastError ?? "خَطأ"})');
      } else {
        created.add(_CreatedCredential(
          employee: emp,
          username: username,
          password: tempPass,
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastCreated.addAll(created);
      _selected.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: failed.isEmpty
          ? AppColors.success
          : (created.isEmpty ? AppColors.danger : AppColors.warning),
      duration: const Duration(seconds: 5),
      content: Text(
        isAr
            ? '✅ أُنشِئ ${created.length} | ❌ فَشِل ${failed.length}'
            : '✅ Created ${created.length} | ❌ Failed ${failed.length}',
      ),
    ));
  }

  Future<void> _exportExcel() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    if (_lastCreated.isEmpty) return;
    final headers = isAr
        ? const [
            'الاسم',
            'الرَمز',
            'الإيميل',
            'الجَوّال',
            'username',
            'كلمة المرور المُؤقَّتة',
            'مُلاحَظة',
          ]
        : const [
            'Name',
            'Code',
            'Email',
            'Phone',
            'Username',
            'Temp Password',
            'Note',
          ];
    final note = isAr
        ? 'يُجبَر على تَغيير كلمة المرور عند أوّل دُخول'
        : 'Must change password on first login';
    final rows = _lastCreated.map<List<dynamic>>((c) => [
          c.employee.fullName,
          c.employee.code,
          c.employee.email,
          c.employee.mobile,
          c.username,
          c.password,
          note,
        ]).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'employee_credentials_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'بيانات الدُخول' : 'Credentials',
          headers: headers,
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تَمّ التَصدير' : '✅ Exported')
          : (isAr ? '❌ فَشِل التَصدير' : '❌ Export failed')),
    ));
  }

  // ============================================================
  // 🆕 WhatsApp send — رِسالة لِكلّ موظّف بِبَياناته
  // ============================================================
  String _buildCredentialMessage(_CreatedCredential c, bool isAr) {
    if (isAr) {
      return 'مَرحَباً ${c.employee.fullName} 👋\n\n'
          'تَمّ إنشاء حساب لكَ في تَطبيق M7 Nexus.\n\n'
          '🔑 اسم المستخدم: ${c.username}\n'
          '🔐 كلمة المرور المُؤَقَّتة: ${c.password}\n\n'
          '⚠ سَيُطلَب منكَ تَغيير كلمة المرور عند أوّل دُخول.\n'
          'الرَجاء عَدَم مُشارَكة هذه البيانات.';
    }
    return 'Hello ${c.employee.fullName} 👋\n\n'
        'An account has been created for you in M7 Nexus.\n\n'
        '🔑 Username: ${c.username}\n'
        '🔐 Temporary password: ${c.password}\n\n'
        '⚠ You will be asked to change the password on first login.\n'
        'Please do not share these credentials.';
  }

  Future<void> _sendWhatsAppOne(_CreatedCredential c, bool isAr) async {
    final phone = c.employee.mobile.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? 'لا يوجد رَقم جَوّال للموظّف ${c.employee.fullName}'
            : 'No mobile number for ${c.employee.fullName}'),
      ));
      return;
    }
    final msg = Uri.encodeComponent(_buildCredentialMessage(c, isAr));
    html.window.open('https://wa.me/$phone?text=$msg', '_blank');
  }

  Future<void> _sendWhatsAppAll(bool isAr) async {
    final withPhone = _lastCreated
        .where((c) => c.employee.mobile.replaceAll(RegExp(r'[^\d]'), '').isNotEmpty)
        .toList();
    final withoutPhone = _lastCreated.length - withPhone.length;
    if (withPhone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? 'لا يوجد موظّفون لَدَيهم أرقام جَوّال'
            : 'No employees with phone numbers'),
      ));
      return;
    }
    // فَتح كلّ رِسالة في تابة جَديدة (المُتَصَفِّح قَد يَطلُب الإذن)
    for (final c in withPhone) {
      await _sendWhatsAppOne(c, isAr);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 5),
      content: Text(isAr
          ? '📤 فُتِحَت ${withPhone.length} مُحادَثة WhatsApp'
              '${withoutPhone > 0 ? "  ·  ⚠ $withoutPhone بدون رَقم" : ""}'
          : '📤 Opened ${withPhone.length} WhatsApp chats'
              '${withoutPhone > 0 ? "  ·  ⚠ $withoutPhone without phone" : ""}'),
    ));
  }

  // ============================================================
  // 🆕 PDF أَنيق — لوغو + بَطاقة احترافيّة لِكلّ موظّف
  // ============================================================
  static const _brandColor = PdfColor.fromInt(0xFF7C3AED); // brand purple
  static const _brandLight = PdfColor.fromInt(0xFFEDE9FE);
  static const _accentColor = PdfColor.fromInt(0xFFF59E0B); // amber

  Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/logo_m7.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _buildPdf(bool isAr) async {
    final pdf = pw.Document();
    final arFont = await PdfGoogleFonts.cairoRegular();
    final arFontBold = await PdfGoogleFonts.cairoBold();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, "0")}/${now.month.toString().padLeft(2, "0")}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: arFont, bold: arFontBold),
        // ===== HEADER (يَظهَر في كلّ صَفحة) =====
        header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _brandColor, width: 2),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Container(
                  width: 50,
                  height: 50,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                )
              else
                pw.Container(
                  width: 50,
                  height: 50,
                  decoration: pw.BoxDecoration(
                    color: _brandColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'M7',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'M7 Nexus',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _brandColor,
                      ),
                    ),
                    pw.Text(
                      isAr
                          ? 'نظام إدارة العمليّات المُتَكامِل'
                          : 'Integrated Operations Management',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    isAr
                        ? '🔐 وَثيقة سرِّيّة'
                        : '🔐 Confidential',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red700,
                    ),
                  ),
                  pw.Text(
                    '$dateStr  $timeStr',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ===== FOOTER (يَظهَر في كلّ صَفحة) =====
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 14),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                isAr
                    ? 'صَفحة ${ctx.pageNumber} من ${ctx.pagesCount}'
                    : 'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey),
              ),
              pw.Spacer(),
              pw.Text(
                isAr
                    ? 'يُجبَر على تَغيير كلمة المرور عند أَوَّل دُخول'
                    : 'Password change required on first login',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: _brandColor,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // ===== BODY =====
        build: (ctx) => [
          // عُنوان رَئيسيّ مَع شارة عَدد الموظّفين
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(
                colors: [_brandColor, PdfColor.fromInt(0xFF9333EA)],
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
              ),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        isAr
                            ? 'بَيانات الدُخول'
                            : 'Login Credentials',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isAr
                            ? 'بَيانات الدُخول الأَوَّلِيّة لِـ${_lastCreated.length} موظّف'
                            : 'Initial credentials for ${_lastCreated.length} employees',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.white.shade(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(20),
                  ),
                  child: pw.Text(
                    '${_lastCreated.length}',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _brandColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // بَنر تَنبيه
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFEF3C7),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _accentColor, width: 0.6),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 18,
                  height: 18,
                  decoration: const pw.BoxDecoration(
                    color: _accentColor,
                    shape: pw.BoxShape.circle,
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '!',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(
                    isAr
                        ? 'وَثيقة سرِّيّة — تَحوي كلمات مرور مُؤَقَّتة. سَلِّمها لِلْموظّف فَقط، ثمّ أَتلِفها بَعد التَسليم.'
                        : 'Confidential document — contains temporary passwords. Hand it only to the employee, then destroy it after delivery.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: const PdfColor.fromInt(0xFF92400E),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // بَطاقة لِكلّ موظّف
          ..._lastCreated.map((c) => _employeeCard(c, isAr, arFontBold)),
        ],
      ),
    );

    return pdf.save();
  }

  /// بَطاقة موظّف واحد في PDF (مَع تَدَرُّج لَونيّ)
  pw.Widget _employeeCard(_CreatedCredential c, bool isAr, pw.Font fontBold) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey300,
            blurRadius: 2,
            offset: PdfPoint(0, 1),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ====== رأس البطاقة ======
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: const pw.BoxDecoration(
              color: _brandLight,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(10),
                topRight: pw.Radius.circular(10),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 42,
                  height: 42,
                  decoration: pw.BoxDecoration(
                    gradient: const pw.LinearGradient(
                      colors: [
                        _brandColor,
                        PdfColor.fromInt(0xFF9333EA),
                      ],
                    ),
                    borderRadius: pw.BorderRadius.circular(21),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    c.employee.initials,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        c.employee.fullName,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: _brandColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Text(
                              c.employee.code,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: _brandColor,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(
                            c.employee.jobTitle,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ====== جسم البطاقة — credentials ======
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: pw.Column(
              children: [
                _credentialRow(
                  icon: '👤',
                  label: isAr ? 'اسم المستخدم' : 'Username',
                  value: c.username,
                  fontBold: fontBold,
                ),
                pw.SizedBox(height: 8),
                _credentialRow(
                  icon: '🔐',
                  label: isAr ? 'كلمة المرور المُؤَقَّتة' : 'Temp password',
                  value: c.password,
                  fontBold: fontBold,
                  danger: true,
                ),
                if (c.employee.mobile.isNotEmpty ||
                    c.employee.email.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(height: 0.5, color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  if (c.employee.mobile.isNotEmpty)
                    _credentialRow(
                      icon: '📱',
                      label: isAr ? 'الجَوّال' : 'Phone',
                      value: c.employee.mobile,
                      fontBold: fontBold,
                      isInfo: true,
                    ),
                  if (c.employee.email.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    _credentialRow(
                      icon: '✉️',
                      label: isAr ? 'الإيميل' : 'Email',
                      value: c.employee.email,
                      fontBold: fontBold,
                      isInfo: true,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _credentialRow({
    required String icon,
    required String label,
    required String value,
    required pw.Font fontBold,
    bool danger = false,
    bool isInfo = false,
  }) {
    final highlight = danger
        ? const PdfColor.fromInt(0xFFFEE2E2)
        : (isInfo
            ? PdfColors.grey100
            : const PdfColor.fromInt(0xFFE0F2FE));
    final textColor = danger
        ? const PdfColor.fromInt(0xFF991B1B)
        : (isInfo
            ? PdfColors.grey800
            : const PdfColor.fromInt(0xFF075985));
    return pw.Row(
      children: [
        pw.Text(icon, style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 105,
          child: pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: highlight,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                font: fontBold,
                color: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportPdf(bool isAr) async {
    if (_lastCreated.isEmpty) return;
    try {
      final bytes = await _buildPdf(isAr);
      // فَتح حِوار الطِباعة/الحِفظ مَع المعاينة
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr ? '✅ تَمّ فَتح الـPDF' : '✅ PDF opened'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text((isAr ? '❌ فَشِل: ' : '❌ Failed: ') + e.toString()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    // الصلاحيّة
    final canCreate = auth.isSuperAdmin ||
        auth.permissions.contains(P.adminUsersCreate) ||
        auth.permissions.contains(P.adminUsersManage);
    if (!canCreate) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr
              ? 'إنشاء حسابات للموظّفين'
              : 'Create Accounts for Employees'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'لا تَملك صلاحيّة إنشاء حسابات.'
                  : 'You do not have permission to create accounts.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final pending = _employeesWithoutAccount(repo, auth);
    // عَدّ الموظّفين المَحجوبين بِفَلتر الهَرَميّة (لِلْإعلام)
    final totalWithoutAccount = repo.employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      final linked = repo.accounts
          .any((a) => a.employeeId == e.id && a.employeeId!.isNotEmpty);
      return !linked;
    }).length;
    final hierarchyHidden = totalWithoutAccount - pending.length;
    final filtered = pending;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            isAr ? 'إنشاء حسابات للموظّفين' : 'Create Employee Accounts'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          if (_lastCreated.isNotEmpty) ...[
            IconButton(
              tooltip: isAr ? 'تَصدير Excel' : 'Export Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: _exportExcel,
            ),
            IconButton(
              tooltip: isAr ? 'تَحميل PDF' : 'Download PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _exportPdf(isAr),
            ),
            IconButton(
              tooltip: isAr ? 'إرسال WhatsApp للكلّ' : 'Send WhatsApp to all',
              icon: const Icon(Icons.send_outlined),
              onPressed: () => _sendWhatsAppAll(isAr),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ===== شارة المعلومات =====
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.info, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? 'سَيُنشَأ لِكلّ موظّف مُحَدَّد حساب بكلمة مرور مُؤَقَّتة. سَيُجبَر على تَغييرها عند أوَّل دُخول.'
                        : 'Each selected employee will get a temporary password. They must change it on first login.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // 🆕 بَنر الفَلتر الهَرَميّ
          if (hierarchyHidden > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withOpacity(0.40)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? '🔐 $hierarchyHidden موظّف مَخفيّ — مُستواهُم الوظيفيّ مُساوٍ أو أَعلى من مُستواكَ. لا تَستَطيع رؤية أو إنشاء حساباتهم.'
                          : '🔐 $hierarchyHidden employees hidden — their level is equal or higher than yours. You cannot create their accounts.',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          if (hierarchyHidden > 0) const SizedBox(height: 8),

          // ===== شَريط الإجراءات =====
          if (_lastCreated.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.success.withOpacity(0.40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'تَمّ إنشاء ${_lastCreated.length} حساب — اِخْتَر طَريقة تَسليم البَيانات'
                              : 'Created ${_lastCreated.length} accounts — choose delivery method',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _DeliveryBtn(
                        icon: Icons.table_chart_outlined,
                        label: 'Excel',
                        color: AppColors.success,
                        onTap: _exportExcel,
                      ),
                      _DeliveryBtn(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'PDF',
                        color: AppColors.danger,
                        onTap: () => _exportPdf(isAr),
                      ),
                      _DeliveryBtn(
                        icon: Icons.send_outlined,
                        label: isAr ? 'WhatsApp للكلّ' : 'WhatsApp All',
                        color: const Color(0xFF25D366),
                        onTap: () => _sendWhatsAppAll(isAr),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ===== العَدّاد + اختيار الكلّ =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Text(
                  isAr
                      ? 'موظّفون بدون حساب: ${pending.length}'
                      : 'Without account: ${pending.length}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (pending.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(
                      _selected.length == pending.length
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    label: Text(
                      _selected.length == pending.length
                          ? (isAr ? 'إلغاء الكلّ' : 'Clear all')
                          : (isAr ? 'تَحديد الكلّ' : 'Select all'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        if (_selected.length == pending.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(pending.map((e) => e.id));
                        }
                      });
                    },
                  ),
              ],
            ),
          ),

          // ===== القائمة =====
          Expanded(
            child: pending.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48,
                              color: AppColors.success.withOpacity(0.7)),
                          const SizedBox(height: 12),
                          Text(
                            isAr
                                ? '🎉 كلّ الموظّفين النَشطين لَدَيهم حسابات'
                                : '🎉 All active employees have accounts',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final emp = filtered[i];
                      final isSel = _selected.contains(emp.id);
                      final suggestedUsername = _suggestUsername(emp);
                      return CheckboxListTile(
                        value: isSel,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(emp.id);
                          } else {
                            _selected.remove(emp.id);
                          }
                        }),
                        title: Text(emp.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${emp.code} · ${emp.jobTitle}',
                                style: const TextStyle(fontSize: 11)),
                            Text(
                              isAr
                                  ? 'سَيَكون username: $suggestedUsername'
                                  : 'Will use username: $suggestedUsername',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: AppColors.brand.withOpacity(0.15),
                          child: Text(
                            emp.initials,
                            style: const TextStyle(
                                color: AppColors.brand,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(
                      _busy
                          ? (isAr ? 'جاري الإنشاء…' : 'Creating…')
                          : (isAr
                              ? '🔐 إنشاء ${_selected.length} حساب'
                              : '🔐 Create ${_selected.length} accounts'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    onPressed: _busy ? null : _createAccounts,
                  ),
                ),
              ),
            ),
    );
  }
}

class _CreatedCredential {
  final Employee employee;
  final String username;
  final String password;
  _CreatedCredential({
    required this.employee,
    required this.username,
    required this.password,
  });
}

class _DeliveryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DeliveryBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
