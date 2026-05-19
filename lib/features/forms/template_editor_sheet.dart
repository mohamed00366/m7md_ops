import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/workflows/workflow_templates.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'field_builder_sheet.dart';
import 'form_renderer.dart';

/// 🛠️ محرّر قالب نموذج
/// 4 أقسام:
///   1) المعلومات الأساسيّة (الاسم، الفئة، الأيقونة، التفعيل)
///   2) الصلاحيات (من يَملأ، من يَطّلع)
///   3) سير الموافقات (Workflow)
///   4) الحقول (read-only في هذه المرحلة)
class TemplateEditorSheet extends StatefulWidget {
  /// إن كان null → إنشاء جديد، غير ذلك → تعديل
  final FormTemplate? existing;
  const TemplateEditorSheet({super.key, this.existing});

  @override
  State<TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<TemplateEditorSheet> {
  final _code = TextEditingController();
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _descAr = TextEditingController();
  final _descEn = TextEditingController();
  String _category = 'general';
  String? _icon = 'assignment_outlined';
  bool _isActive = true;
  int _sortOrder = 0;

  /// قائمة الأدوار التي يمكنها تقديم النموذج
  final Set<String> _submitRoles = {'employee'};
  /// قائمة الأدوار التي يمكنها مشاهدة كل الطلبات
  final Set<String> _viewAllRoles = {'admin', 'hr'};

  /// خطوات الموافقة
  late List<Map<String, dynamic>> _workflow;
  /// 🆕 حُقول النَموذج (Visual Field Builder)
  late List<Map<String, dynamic>> _schema;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    if (t != null) {
      _code.text = t.code;
      _nameAr.text = t.nameAr;
      _nameEn.text = t.nameEn;
      _descAr.text = t.descriptionAr ?? '';
      _descEn.text = t.descriptionEn ?? '';
      _category = t.category;
      _icon = t.icon;
      _isActive = t.isActive;
      _sortOrder = t.sortOrder;
      // اقرأ الصلاحيات
      final perms = t.permissions;
      if (perms['submit_roles'] is List) {
        _submitRoles
          ..clear()
          ..addAll((perms['submit_roles'] as List).map((e) => e.toString()));
      }
      if (perms['view_all_roles'] is List) {
        _viewAllRoles
          ..clear()
          ..addAll(
              (perms['view_all_roles'] as List).map((e) => e.toString()));
      }
      _workflow = List<Map<String, dynamic>>.from(t.workflow.map((s) => Map<String, dynamic>.from(s)));
      _schema = List<Map<String, dynamic>>.from(
          t.schema.map((s) => Map<String, dynamic>.from(s)));
    } else {
      _workflow = [];
      _schema = [];
    }
  }

  /// 🆕 فَتح Field Builder الكامِل (كَصَفحة كامِلة، لِتَجَنُّب مُشكِلة modal-in-modal)
  Future<void> _openFieldBuilder() async {
    debugPrint('🔧 _openFieldBuilder called — _schema.length=${_schema.length}');
    // FieldBuilderSheet أَصبَحَت Scaffold بِنَفسها — نُمَرِّرها مُباشَرَة
    final result = await Navigator.of(context, rootNavigator: true)
        .push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FieldBuilderSheet(initialSchema: _schema),
      ),
    );
    debugPrint(
        '🔧 _openFieldBuilder returned: ${result != null ? "${result.length} fields" : "cancelled"}');
    if (result != null) {
      setState(() => _schema = result);
    }
  }

  /// 🆕 تَعديل حَقل واحِد مُباشَرَة بِالضَغط عَلَيه
  Future<void> _editSingleField(int index) async {
    debugPrint(
        '🔧 _editSingleField($index) called — field: ${_schema[index]['key']}');
    final updated = await openSingleFieldEditor(
      context,
      existing: _schema[index],
    );
    debugPrint(
        '🔧 _editSingleField returned: ${updated != null ? "updated" : "cancelled"}');
    if (updated != null) {
      setState(() => _schema[index] = updated);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    super.dispose();
  }

  /// 🆕 Session 16: عرض معاينة النموذج (كما يراه الموظف)
  void _showPreview() {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final tpl = widget.existing;
    if (tpl == null) return;

    // ابنِ نسخة محدّثة بالقيم المحرّرة (الاسم والوصف الحاليّ + workflow الحاليّ)
    final previewTpl = FormTemplate(
      id: tpl.id,
      code: _code.text.trim().isEmpty ? tpl.code : _code.text.trim(),
      nameAr: _nameAr.text.trim().isEmpty ? tpl.nameAr : _nameAr.text.trim(),
      nameEn: _nameEn.text.trim().isEmpty ? tpl.nameEn : _nameEn.text.trim(),
      descriptionAr: _descAr.text.trim().isEmpty ? tpl.descriptionAr : _descAr.text.trim(),
      descriptionEn: _descEn.text.trim().isEmpty ? tpl.descriptionEn : _descEn.text.trim(),
      category: _category,
      icon: _icon,
      schema: _schema,  // 🆕 يَعرِض الحُقول المُحَرَّرة الآن
      workflow: _workflow,
      permissions: tpl.permissions,
      isActive: _isActive,
    );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.preview_outlined,
                      color: AppColors.info, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'معاينة: ${previewTpl.nameAr}'
                          : 'Preview: ${previewTpl.nameEn}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.info, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'هذا ما سيراه الموظف عند فتح هذا النموذج. هذه معاينة فقط — لن يُحفظ.'
                            : 'This is what employees will see. Preview only — won\'t save.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // Body — render form
              Expanded(
                child: SingleChildScrollView(
                  child: previewTpl.schema.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(Icons.assignment_outlined,
                                  color: Colors.grey[400], size: 40),
                              const SizedBox(height: 8),
                              Text(
                                isAr
                                    ? 'هذا القالب لا يحوي حقولاً (schema فارغ)'
                                    : 'This template has no fields (empty schema)',
                                style: TextStyle(color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isAr
                                    ? 'الـ workflow معاينته من تبويب «محرّر الموافقات»'
                                    : 'Workflow preview is in Workflow Builder tab',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500]),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : FormRenderer(
                          template: previewTpl,
                          readOnly: true,
                          onSubmit: (_) {},
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🆕 Session 15: تطبيق قالب workflow جاهز
  Future<void> _applyWorkflowPreset() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final picked = await showModalBottomSheet<WorkflowPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: AppColors.warning, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr ? 'اختر قالب workflow' : 'Pick a workflow preset',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(12),
                children: [
                  for (final preset in WorkflowTemplates.all)
                    _PresetCard(
                      preset: preset,
                      isAr: isAr,
                      onTap: () => Navigator.pop(ctx, preset),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    // إن كان هناك خطوات بالفعل، اطلب تأكيد
    if (_workflow.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isAr ? '⚠️ استبدال الخطوات؟' : '⚠️ Replace steps?'),
          content: Text(
            isAr
                ? 'سيتمّ مسح ${_workflow.length} خطوة حاليّة واستبدالها بـ ${picked.stepCount} خطوة من القالب.'
                : 'Will clear ${_workflow.length} current step(s) and replace with ${picked.stepCount} from preset.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'استبدال' : 'Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _workflow.clear();
      _workflow.addAll(picked.stepsCopy());
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
        isAr
            ? '✅ طُبّق قالب: ${picked.nameAr}'
            : '✅ Applied: ${picked.nameEn}',
      ),
    ));
  }

  void _addStep() {
    setState(() {
      _workflow.add({
        'step': _workflow.length,
        'role': 'manager',
        'label_ar': 'المدير المباشر',
        'label_en': 'Direct Manager',
        'require_signature': true,
      });
    });
  }

  void _removeStep(int i) {
    setState(() {
      _workflow.removeAt(i);
      // إعادة ترقيم
      for (var j = 0; j < _workflow.length; j++) {
        _workflow[j]['step'] = j;
      }
    });
  }

  void _moveStep(int from, int to) {
    if (to < 0 || to >= _workflow.length) return;
    setState(() {
      final tmp = _workflow.removeAt(from);
      _workflow.insert(to, tmp);
      for (var j = 0; j < _workflow.length; j++) {
        _workflow[j]['step'] = j;
      }
    });
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_code.text.trim().isEmpty ||
        _nameAr.text.trim().isEmpty ||
        _nameEn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(s.isAr
            ? 'الكود + الاسم AR + الاسم EN مطلوبة'
            : 'Code + AR name + EN name required'),
      ));
      return;
    }
    setState(() => _saving = true);
    final repo = MockRepository();
    final tpl = FormTemplate(
      id: widget.existing?.id ?? repo.generateId(),
      code: _code.text.trim().toUpperCase(),
      nameAr: _nameAr.text.trim(),
      nameEn: _nameEn.text.trim(),
      descriptionAr: _descAr.text.trim().isEmpty ? null : _descAr.text.trim(),
      descriptionEn: _descEn.text.trim().isEmpty ? null : _descEn.text.trim(),
      category: _category,
      icon: _icon,
      schema: _schema,  // 🆕 يَحفَظ الحُقول المَبنيّة من Field Builder
      workflow: _workflow,
      permissions: {
        'submit_roles': _submitRoles.toList(),
        'view_all_roles': _viewAllRoles.toList(),
      },
      isActive: _isActive,
      sortOrder: _sortOrder,
    );
    final result = await SupabaseDataService().upsertFormTemplate(tpl);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(SupabaseDataService().lastError ?? 'Failed'),
      ));
      return;
    }
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr ? '✓ تم الحفظ' : '✓ Saved'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final allRoles = repo.roleDefs.toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                    widget.existing == null
                        ? Icons.add_circle_outline
                        : Icons.edit_outlined,
                    color: AppColors.brand,
                    size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.existing == null
                        ? (s.isAr ? 'قالب نموذج جديد' : 'New Form Template')
                        : (s.isAr ? 'تعديل القالب' : 'Edit Template'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                // 🆕 Session 16: زرّ المعاينة
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: () => _showPreview(),
                    icon: const Icon(Icons.preview_outlined, size: 16),
                    label: Text(
                      s.isAr ? 'معاينة' : 'Preview',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.info,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 16),
          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ===== 1) المعلومات الأساسيّة =====
                  _Section(title: s.isAr ? '① المعلومات' : '① Info'),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'الكود * (مثلاً: LEAVE-REQ)'
                          : 'Code * (e.g. LEAVE-REQ)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _nameAr,
                        decoration: InputDecoration(
                          labelText:
                              s.isAr ? 'الاسم بالعربية *' : 'AR Name *',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _nameEn,
                        decoration: InputDecoration(
                          labelText:
                              s.isAr ? 'الاسم بالإنجليزية *' : 'EN Name *',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descAr,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'وصف بالعربية'
                          : 'AR Description',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descEn,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: s.isAr
                          ? 'وصف بالإنجليزية'
                          : 'EN Description',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _category,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: s.isAr ? 'الفئة' : 'Category',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: () {
                          // الفِئات المَعروفة + أَيّ فِئة غَير مَعروفة قادِمة من DB
                          const known = {
                            'leave': 'Leave / إجازة',
                            'loan': 'Loan / سلفة',
                            'certificate': 'Certificate / شهادة',
                            'training': 'Training / تدريب',
                            'resignation': 'Resignation / استقالة',
                            'site_onboarding':
                                'Site Onboarding / موقِع جَديد',
                            'incident': 'Incident / حادِث',
                            'maintenance':
                                'Maintenance / صِيانة',
                            'site_assets':
                                'Site Assets / أُصول المَوقِع',
                            'general': 'General / عام',
                          };
                          final all = {...known};
                          // أَضِف الفِئة الحاليّة لو كانَت غَير مَوجودة
                          if (!all.containsKey(_category)) {
                            all[_category] = _category;
                          }
                          return all.entries
                              .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ))
                              .toList();
                        }(),
                        onChanged: (v) =>
                            setState(() => _category = v ?? 'general'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _icon,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: s.isAr ? 'الأيقونة' : 'Icon',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: () {
                          const known = {
                            'beach_access': '🏖️ Beach',
                            'attach_money': '💰 Money',
                            'description': '📜 Document',
                            'logout': '🚪 Logout',
                            'school': '🎓 School',
                            'badge': '🏷️ Badge',
                            'assignment_outlined': '📋 Form',
                            'add_business': '🏗 Site / موقِع',
                            'business': '🏢 Business',
                            'store': '🏬 Store',
                            'location_on': '📍 Location',
                            'people': '👥 People',
                            'checkroom': '👕 Uniform',
                            'directions_car': '🚗 Vehicle',
                            'event': '📅 Event',
                            'warning': '🚨 Warning / Incident',
                            'report_problem': '⚠ Report Problem',
                            'local_hospital': '🏥 Hospital / Medical',
                            'security': '🛡 Security / Insurance',
                          };
                          final all = {...known};
                          // أَضِف الأيقونة الحاليّة إن لم تَكُن في القائِمة
                          if (_icon != null &&
                              _icon!.isNotEmpty &&
                              !all.containsKey(_icon)) {
                            all[_icon!] = _icon!;
                          }
                          return all.entries
                              .map((e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(e.value),
                                  ))
                              .toList();
                        }(),
                        onChanged: (v) => setState(() => _icon = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      s.isAr ? 'مفعّل' : 'Active',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      s.isAr
                          ? 'لو معطّل لن يظهر للموظفين'
                          : 'If off, hidden from employees',
                      style: const TextStyle(
                          fontSize: 11, color: AppPalette.textSecondary),
                    ),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),

                  // ===== 2) الصلاحيات =====
                  const SizedBox(height: 16),
                  _Section(
                      title: s.isAr ? '② الصلاحيات' : '② Permissions'),
                  Text(
                    s.isAr
                        ? 'من يَملأ النموذج؟'
                        : 'Who can submit?',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  _RoleSelector(
                    allRoles: allRoles,
                    selected: _submitRoles,
                    onChanged: (v) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.isAr
                        ? 'من يَطّلع على كل الطلبات؟'
                        : 'Who can view all submissions?',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  _RoleSelector(
                    allRoles: allRoles,
                    selected: _viewAllRoles,
                    onChanged: (v) => setState(() {}),
                  ),

                  // ===== 3) سير الموافقات =====
                  const SizedBox(height: 16),
                  _Section(
                      title: s.isAr
                          ? '③ سير الموافقات (${_workflow.length} خطوة)'
                          : '③ Workflow (${_workflow.length} steps)'),
                  // 🆕 Session 15: زرّ تطبيق قالب workflow
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _applyWorkflowPreset,
                      icon: const Icon(Icons.flash_on, size: 16),
                      label: Text(
                        s.isAr
                            ? '⚡ تطبيق قالب جاهز'
                            : '⚡ Apply preset workflow',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: BorderSide(
                            color: AppColors.warning.withOpacity(0.5)),
                      ),
                    ),
                  ),
                  if (_workflow.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                AppColors.warning.withOpacity(0.30)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? 'لا خطوات موافقة. سيتم القبول مباشرة عند الإرسال.'
                                : 'No approval steps. Auto-approves on submit.',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ]),
                    )
                  else
                    for (var i = 0; i < _workflow.length; i++)
                      _WorkflowStepEditor(
                        step: _workflow[i],
                        index: i,
                        total: _workflow.length,
                        roles: allRoles,
                        onChanged: () => setState(() {}),
                        onRemove: () => _removeStep(i),
                        onMoveUp: () => _moveStep(i, i - 1),
                        onMoveDown: () => _moveStep(i, i + 1),
                      ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addStep,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                        s.isAr ? '➕ إضافة خطوة موافقة' : '➕ Add step'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side:
                          BorderSide(color: AppColors.brand.withOpacity(0.40)),
                    ),
                  ),

                  // ===== 4) 🆕 الحُقول (Visual Field Builder) =====
                  const SizedBox(height: 20),
                  _Section(
                    title: s.isAr
                        ? '④ الحُقول (${_schema.length})'
                        : '④ Fields (${_schema.length})',
                  ),
                  if (_schema.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.info.withOpacity(0.30)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.info, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? 'لا توجد حُقول بَعد. اضغط أَدناه لِبِناء النَموذج خَليّة-خَليّة.'
                                : 'No fields yet. Tap below to build the form cell-by-cell.',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ]),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _schema.length; i++)
                            ListTile(
                              dense: true,
                              // 🆕 ضَغط الصَفّ يَفتَح مُحَرِّر هذا الحَقل مُباشَرَة
                              onTap: () => _editSingleField(i),
                              leading: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.brand.withOpacity(0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.brand,
                                  ),
                                ),
                              ),
                              title: Text(
                                (s.isAr
                                        ? _schema[i]['label_ar']
                                        : _schema[i]['label_en']) ??
                                    _schema[i]['key'] ??
                                    '',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                '${_schema[i]['type']} · ${_schema[i]['key']}'
                                '${_schema[i]['required'] == true ? " *" : ""}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontFamily: 'monospace'),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.brand),
                                tooltip: s.isAr ? 'تَعديل' : 'Edit',
                                onPressed: () => _editSingleField(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _openFieldBuilder,
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(
                      _schema.isEmpty
                          ? (s.isAr
                              ? '🧱 إنشاء حُقول النَموذج'
                              : '🧱 Build form fields')
                          : (s.isAr
                              ? '🧱 تَعديل الحُقول (${_schema.length})'
                              : '🧱 Edit fields (${_schema.length})'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom actions
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppPalette.border)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.cancel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(s.save),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شيب لاختيار أدوار متعدّدة
// ============================================================
class _RoleSelector extends StatelessWidget {
  final List<RoleDef> allRoles;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _RoleSelector({
    required this.allRoles,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (allRoles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: Text(
          s.isAr ? 'لا توجد أدوار في النظام' : 'No roles defined',
          style: const TextStyle(
              fontSize: 11, color: AppPalette.textTertiary),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in allRoles)
          FilterChip(
            label: Text(s.isAr ? r.nameAr : r.nameEn,
                style: const TextStyle(fontSize: 11)),
            selected: selected.contains(r.key),
            onSelected: (sel) {
              if (sel) {
                selected.add(r.key);
              } else {
                selected.remove(r.key);
              }
              onChanged(selected);
            },
            selectedColor: AppColors.brand.withOpacity(0.15),
            checkmarkColor: AppColors.brand,
          ),
      ],
    );
  }
}

// ============================================================
// محرّر خطوة موافقة
// ============================================================
class _WorkflowStepEditor extends StatelessWidget {
  final Map<String, dynamic> step;
  final int index;
  final int total;
  final List<RoleDef> roles;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _WorkflowStepEditor({
    required this.step,
    required this.index,
    required this.total,
    required this.roles,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isFirst = index == 0;
    final isLast = index == total - 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.isAr ? 'الخطوة ${index + 1}' : 'Step ${index + 1}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            // أزرار ترتيب
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: isFirst ? null : onMoveUp,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: isLast ? null : onMoveDown,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Colors.red),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          // 🆕 Phase 6: نمط الخطوة (Role / Auto-chain / Specific)
          _ActorTypeSelector(
            current: (step['actor_type'] as String?) ?? 'role',
            onChanged: (t) {
              step['actor_type'] = t;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          // 🆕 Phase 6: عند Auto-chain → اختر قوّة الموافقات المطلوبة
          if (step['actor_type'] == 'auto_chain')
            _MinApprovalPowerSelector(
              value: (step['min_approval_power'] as int?) ?? 1,
              onChanged: (v) {
                step['min_approval_power'] = v;
                onChanged();
              },
            ),
          if (step['actor_type'] != 'auto_chain') ...[
          // الدور المطلوب للموافقة
          Builder(
            builder: (_) {
              final currentRole = step['role']?.toString();
              // ابنِ مفاتيح فريدة وأضف الدور الحالي إن لم يكن موجوداً
              final roleKeys = roles.map((r) => r.key).toSet();
              final hasCurrent =
                  currentRole != null && roleKeys.contains(currentRole);
              return DropdownButtonFormField<String>(
                value: hasCurrent ? currentRole : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      s.isAr ? 'من يوافق؟' : 'Who approves?',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: !hasCurrent && currentRole != null
                      ? (s.isAr
                          ? 'الدور «$currentRole» غير موجود — اختر آخر'
                          : 'Role «$currentRole» not found — pick one')
                      : null,
                ),
                items: [
                  for (final r in roles)
                    DropdownMenuItem<String>(
                      value: r.key,
                      child: Text(s.isAr ? r.nameAr : r.nameEn,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  step['role'] = v;
                  try {
                    final r = roles.firstWhere((x) => x.key == v);
                    step['label_ar'] = r.nameAr;
                    step['label_en'] = r.nameEn;
                  } catch (_) {}
                  onChanged();
                },
              );
            },
          ),
          ], // end if actor_type != auto_chain
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: step['label_ar']?.toString() ?? '',
                decoration: InputDecoration(
                  labelText:
                      s.isAr ? 'تسمية بالعربية' : 'AR label',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => step['label_ar'] = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: step['label_en']?.toString() ?? '',
                decoration: InputDecoration(
                  labelText:
                      s.isAr ? 'تسمية بالإنجليزية' : 'EN label',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => step['label_en'] = v,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
                s.isAr ? 'يتطلّب توقيعاً' : 'Require signature',
                style: const TextStyle(fontSize: 12)),
            value: step['require_signature'] == true,
            onChanged: (v) {
              step['require_signature'] = v ?? false;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 Phase 6: مكوّنات Workflow Step (نمط الخطوة + قوّة الموافقات)
// ============================================================

class _ActorTypeSelector extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _ActorTypeSelector({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final options = <_ActorOption>[
      _ActorOption(
        key: 'role',
        labelAr: 'حسب الدور',
        labelEn: 'By Role',
        icon: Icons.shield_outlined,
      ),
      _ActorOption(
        key: 'auto_chain',
        labelAr: 'تلقائي (هرم)',
        labelEn: 'Auto-chain',
        icon: Icons.timeline,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr ? 'نمط الخطوة' : 'Step Mode',
          style:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final o in options) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(o.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: current == o.key
                          ? AppColors.brand.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current == o.key
                            ? AppColors.brand
                            : Colors.grey.withOpacity(0.3),
                        width: current == o.key ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          o.icon,
                          size: 14,
                          color: current == o.key
                              ? AppColors.brand
                              : Colors.grey[700],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isAr ? o.labelAr : o.labelEn,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: current == o.key
                                  ? AppColors.brand
                                  : Colors.grey[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (o != options.last) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActorOption {
  final String key;
  final String labelAr;
  final String labelEn;
  final IconData icon;
  const _ActorOption({
    required this.key,
    required this.labelAr,
    required this.labelEn,
    required this.icon,
  });
}

class _MinApprovalPowerSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _MinApprovalPowerSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.isAr
                      ? 'الحدّ الأدنى لقوّة الموافقات'
                      : 'Min Approval Power',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$value / 5',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: value.toString(),
            onChanged: (v) => onChanged(v.round()),
          ),
          Text(
            s.isAr
                ? 'يصعد الهرم انطلاقاً من المُقدِّم حتى يجد مسمّى بقوّة موافقات ≥ $value'
                : 'Walks chain from submitter until a job title with approval power ≥ $value is found',
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}

// 🆕 Session 15: بطاقة قالب workflow
class _PresetCard extends StatelessWidget {
  final WorkflowPreset preset;
  final bool isAr;
  final VoidCallback onTap;
  const _PresetCard({
    required this.preset,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(preset.icon,
                  style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAr ? preset.nameAr : preset.nameEn,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAr
                              ? '${preset.stepCount} خطوات'
                              : '${preset.stepCount} steps',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAr ? preset.descriptionAr : preset.descriptionEn,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  // معاينة الخطوات
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < preset.steps.length; i++) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isAr
                                ? '${i + 1}. ${preset.steps[i]['label_ar'] ?? "?"}'
                                : '${i + 1}. ${preset.steps[i]['label_en'] ?? "?"}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                        if (i < preset.steps.length - 1)
                          const Icon(Icons.arrow_forward,
                              size: 10, color: Colors.grey),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios,
                size: 12, color: AppColors.warning.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brand.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: AppColors.brand),
        ),
      ),
    );
  }
}
