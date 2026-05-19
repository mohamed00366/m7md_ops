import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// 🔢 تَحويل آمِن لِأَيّ قِيمة عَدَدِيّة قادِمة من JSONB إلى عَرض حَقل (1-12).
/// JSON من قاعِدة البَيانات قَد يُعيد الأَرقام كَـdouble (12.0) — هذه الدالّة
/// تَحمي من خَطَأ `type cast` عِند فَتح مُحَرِّر الحُقول.
int _safeWidth(dynamic v) {
  if (v == null) return 12;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 12;
  }
  return 12;
}

/// 🆕 القَوائِم المَرجِعيّة المُتاحة لِحَقل `lookup_select` — مُستَخدَمة في
/// مُحَرِّر الحَقل لِعَرض قائِمة المَصادِر، وَفي form_renderer لِجَلب الخَيارات.
/// مُعَرَّفة في مُستَوى المِلَفّ لِيَصِل إليها كِلا الكلاسَين.
const List<Map<String, String>> _lookupOptions = [
  {'value': 'business_types', 'label_ar': 'أَنواع الأَنشطة',  'label_en': 'Business Types'},
  {'value': 'departments',    'label_ar': 'الأَقسام',         'label_en': 'Departments'},
  {'value': 'job_titles',     'label_ar': 'المُسَمَّيات الوَظيفيّة', 'label_en': 'Job Titles'},
  {'value': 'nationalities',  'label_ar': 'الجِنسيّات',       'label_en': 'Nationalities'},
  {'value': 'visa_types',     'label_ar': 'أَنواع التَأشيرات', 'label_en': 'Visa Types'},
  {'value': 'countries',      'label_ar': 'الدُوَل',          'label_en': 'Countries'},
];

/// 🧱 محرر الحقول البصريّ (Visual Field Builder)
///
/// يَسمَح بِبناء حُقول النَموذج خَليّة-خَليّة من الواجهة.
///
/// يَدعَم 8 أَنواع حُقول:
///   - text       (سَطر نصّ قَصير)
///   - textarea   (نصّ طَويل)
///   - number     (رَقَم — أَو money)
///   - date       (تاريخ)
///   - select     (قائمة مُنسَدِلة)
///   - radio      (اختيار واحِد)
///   - checkbox   (مُربَّعات — مُتَعَدِّد)
///   - signature  (تَوقيع)
///
/// خَصائص كلّ حَقل:
///   - key (المُعَرِّف الداخليّ)
///   - label_ar / label_en
///   - required (إجباريّ)
///   - placeholder, helper_text
///   - options[] (لِـselect/radio/checkbox)
///   - min/max (لِـnumber)
///   - default_value
///
/// الاستِخدام:
/// ```dart
/// final newSchema = await showModalBottomSheet<List<Map<String, dynamic>>>(
///   context: context,
///   builder: (_) => FieldBuilderSheet(initialSchema: tpl.schema),
/// );
/// if (newSchema != null) {
///   tpl.schema = newSchema;
/// }
/// ```
class FieldBuilderSheet extends StatefulWidget {
  final List<Map<String, dynamic>> initialSchema;
  const FieldBuilderSheet({super.key, required this.initialSchema});

  @override
  State<FieldBuilderSheet> createState() => _FieldBuilderSheetState();
}

class _FieldBuilderSheetState extends State<FieldBuilderSheet> {
  late List<Map<String, dynamic>> _fields;

  static const _typeOptions = [
    {'value': 'text',      'icon': Icons.short_text,
     'label_ar': 'نَصّ قَصير',  'label_en': 'Short text'},
    {'value': 'textarea',  'icon': Icons.notes,
     'label_ar': 'نَصّ طَويل',  'label_en': 'Long text'},
    {'value': 'number',    'icon': Icons.numbers,
     'label_ar': 'رَقَم',       'label_en': 'Number'},
    {'value': 'date',      'icon': Icons.calendar_today,
     'label_ar': 'تاريخ',      'label_en': 'Date'},
    {'value': 'select',    'icon': Icons.list,
     'label_ar': 'قائمة',      'label_en': 'Dropdown'},
    {'value': 'radio',     'icon': Icons.radio_button_checked,
     'label_ar': 'اختيار واحِد', 'label_en': 'Radio'},
    {'value': 'checkbox',  'icon': Icons.check_box,
     'label_ar': 'مُربَّعات',    'label_en': 'Checkboxes'},
    {'value': 'signature', 'icon': Icons.draw,
     'label_ar': 'تَوقيع',      'label_en': 'Signature'},
    {'value': 'section',   'icon': Icons.horizontal_rule,
     'label_ar': 'فاصِل قِسم',   'label_en': 'Section divider'},
    // 🆕 أَنواع مُتَقَدِّمة
    {'value': 'image',     'icon': Icons.photo_camera,
     'label_ar': 'صورة',       'label_en': 'Image'},
    {'value': 'vehicles',  'icon': Icons.directions_car,
     'label_ar': 'سَيّارات (مُتَكَرِّر)', 'label_en': 'Vehicles (repeating)'},
    {'value': 'employee_picker', 'icon': Icons.person_search,
     'label_ar': 'اختيار مَوظَّف', 'label_en': 'Employee picker'},
    {'value': 'gps_picker', 'icon': Icons.map,
     'label_ar': 'مَوقِع GPS',    'label_en': 'GPS picker'},
    // 🆕 قائِمة من القَوائِم المَرجِعيّة (تَجلُب الخَيارات تِلقائيّاً)
    {'value': 'lookup_select', 'icon': Icons.list_alt,
     'label_ar': 'قائِمة من المَراجِع', 'label_en': 'List from Lookups'},
    // 🆕 أَصناف الكاتالوج (تَلقائيّ مِن uniform_items + كَمّيّة لِكُلّ صَنف)
    {'value': 'catalog_items', 'icon': Icons.inventory_2_outlined,
     'label_ar': 'أَصناف الكاتالوج', 'label_en': 'Catalog items'},
  ];

  @override
  void initState() {
    super.initState();
    _fields = widget.initialSchema
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
  }

  Future<void> _addField() async {
    final newField = await _openFieldEditor(null);
    if (newField != null) {
      setState(() => _fields.add(newField));
    }
  }

  Future<void> _editField(int index) async {
    final updated = await _openFieldEditor(_fields[index]);
    if (updated != null) {
      setState(() => _fields[index] = updated);
    }
  }

  void _deleteField(int index) {
    setState(() => _fields.removeAt(index));
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final tmp = _fields[index];
      _fields[index] = _fields[index - 1];
      _fields[index - 1] = tmp;
    });
  }

  void _moveDown(int index) {
    if (index >= _fields.length - 1) return;
    setState(() {
      final tmp = _fields[index];
      _fields[index] = _fields[index + 1];
      _fields[index + 1] = tmp;
    });
  }

  Future<Map<String, dynamic>?> _openFieldEditor(
      Map<String, dynamic>? existing) async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FieldEditDialog(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    // 🆕 بِنية بَسيطة وَمَوثوقة:
    // - AppBar لِلرَأس (مَوقِع قِياسيّ، لا يَنهار)
    // - body = ListView (سَكرول واحِد لِكُلّ شَيء)
    // - FloatingActionButton لِإضافة حَقل (دائِماً ظاهِر)
    // - bottomNavigationBar لِزِرّ الحِفظ
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        // 🆕 أَيقونة الرجوع ذَهَبيّة وَواضِحة
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Text(
          isAr
              ? '🧱 مُحَرِّر الحُقول (${_fields.length})'
              : '🧱 Field Builder (${_fields.length})',
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle,
                color: AppColors.gold, size: 30),
            tooltip: isAr ? 'حِفظ' : 'Save',
            onPressed: () => Navigator.pop(context, _fields),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(isAr ? 'إضافة حَقل' : 'Add field'),
        onPressed: _addField,
      ),
      body: _fields.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    isAr ? 'لا توجد حُقول بَعد' : 'No fields yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'اضغَط زِرّ "إضافة حَقل" في الأَسفَل'
                        : 'Tap "Add field" below',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
              itemCount: _fields.length,
              itemBuilder: (_, i) {
                final f = _fields[i];
                return _SimpleFieldRow(
                  field: f,
                  index: i,
                  isAr: isAr,
                  typeOptions: _typeOptions,
                  onEdit: () => _editField(i),
                  onDelete: () => _deleteField(i),
                  onMoveUp: i == 0 ? null : () => _moveUp(i),
                  onMoveDown:
                      i == _fields.length - 1 ? null : () => _moveDown(i),
                );
              },
            ),
    );
  }
}

// ============================================================
// 🃏 بَطاقة حَقل بَسيطة (بَدَل _FieldCard المُعَقَّد)
// ============================================================
class _SimpleFieldRow extends StatelessWidget {
  final Map<String, dynamic> field;
  final int index;
  final bool isAr;
  final List<Map<String, Object>> typeOptions;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _SimpleFieldRow({
    required this.field,
    required this.index,
    required this.isAr,
    required this.typeOptions,
    required this.onEdit,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final type = (field['type'] ?? 'text').toString();
    final label = isAr
        ? (field['label_ar'] ?? field['key'] ?? '').toString()
        : (field['label_en'] ?? field['key'] ?? '').toString();
    final required = field['required'] == true;
    final key = (field['key'] ?? '').toString();
    final width = _safeWidth(field['width']);

    final typeInfo = typeOptions.firstWhere(
      (t) => t['value'] == type,
      orElse: () => typeOptions.first,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: onEdit,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.brand.withOpacity(0.12),
          child: Icon(typeInfo['icon'] as IconData,
              size: 16, color: AppColors.brand),
        ),
        title: Text(
          '${index + 1}. $label${required ? " *" : ""}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$type · $key · $width/12',
          style: const TextStyle(
              fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 16, color: AppColors.brand),
              tooltip: isAr ? 'تَعديل' : 'Edit',
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.danger),
              tooltip: isAr ? 'حَذف' : 'Delete',
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🃏 بَطاقة حَقل (في القائمة)
// ============================================================
class _FieldCard extends StatelessWidget {
  final Map<String, dynamic> field;
  final int index;
  final bool isAr;
  final List<Map<String, Object>> typeOptions;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _FieldCard({
    super.key,
    required this.field,
    required this.index,
    required this.isAr,
    required this.typeOptions,
    required this.onEdit,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final type = (field['type'] ?? 'text').toString();
    final label = isAr
        ? (field['label_ar'] ?? field['key'] ?? '').toString()
        : (field['label_en'] ?? field['key'] ?? '').toString();
    final required = field['required'] == true;
    final key = (field['key'] ?? '').toString();

    final typeInfo = typeOptions.firstWhere(
      (t) => t['value'] == type,
      orElse: () => typeOptions.first,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator,
                    size: 18, color: Colors.grey),
              ),
            ),
            // Type icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                typeInfo['icon'] as IconData,
                size: 18,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.isEmpty
                              ? (isAr ? '(بدون عُنوان)' : '(no label)')
                              : label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (required) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '*',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        isAr
                            ? typeInfo['label_ar'] as String
                            : typeInfo['label_en'] as String,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey),
                      ),
                      if (key.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('·',
                            style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(width: 6),
                        Text(
                          key,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontFamily: 'monospace'),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text('·',
                          style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(width: 6),
                      // 🆕 شارة العَرض
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${_safeWidth(field['width'])}/12',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: isAr ? 'تَعديل' : 'Edit',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.danger),
              tooltip: isAr ? 'حَذف' : 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 📝 حِوار تَعديل حَقل واحِد
// ============================================================
/// 🆕 يَفتَح مُحَرِّر حَقل واحِد (يُستَخدَم من template_editor_sheet مُباشَرَة)
/// يُرجِع الحَقل المُحَرَّر أَو null لو أُلغِيَت العَمَليّة.
Future<Map<String, dynamic>?> openSingleFieldEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  // _FieldEditDialog أَصبَحَت Scaffold بِنَفسها — نُمَرِّرها مُباشَرَة
  return Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FieldEditDialog(existing: existing),
    ),
  );
}

class _FieldEditDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _FieldEditDialog({this.existing});

  @override
  State<_FieldEditDialog> createState() => _FieldEditDialogState();
}

class _FieldEditDialogState extends State<_FieldEditDialog> {
  final _key = TextEditingController();
  final _labelAr = TextEditingController();
  final _labelEn = TextEditingController();
  final _placeholder = TextEditingController();
  final _helperText = TextEditingController();
  final _optionsRaw = TextEditingController();
  final _minVal = TextEditingController();
  final _maxVal = TextEditingController();
  final _defaultVal = TextEditingController();

  String _type = 'text';
  bool _required = false;
  /// 🆕 عَرض الحَقل من 1 إلى 12 (مَثل Bootstrap)
  /// 12 = العَرض الكامِل، 6 = نِصف، 4 = ثُلث، إلخ.
  int _width = 12;
  /// 🆕 اسم القائِمة المَرجِعيّة (لِـlookup_select)
  String? _lookupName;

  /// تَحويل آمِن لِأَيّ قِيمة عَدَدِيّة قادِمة من JSONB (int / double / String / null)
  static int _safeInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
    }
    return fallback;
  }

  /// تَحويل أَيّ رَقَم لِنَصّ نَظيف (1.0 → "1"، 1 → "1"، "1" → "1")
  static String _numAsText(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v is double) {
      if (v == v.toInt()) return v.toInt().toString();
      return v.toString();
    }
    return v.toString();
  }

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    if (f != null) {
      _key.text = (f['key'] ?? '').toString();
      _labelAr.text = (f['label_ar'] ?? '').toString();
      _labelEn.text = (f['label_en'] ?? '').toString();
      _placeholder.text = (f['placeholder'] ?? '').toString();
      _helperText.text = (f['helper'] ?? '').toString();
      _type = (f['type'] ?? 'text').toString();
      _required = f['required'] == true;
      _width = _safeInt(f['width'], 12);
      _minVal.text = _numAsText(f['min']);
      _maxVal.text = _numAsText(f['max']);
      _defaultVal.text = (f['default'] ?? '').toString();
      // 🆕 اسم القائِمة المَرجِعيّة (لِـlookup_select)
      _lookupName = f['lookup']?.toString();
      // الخيارات: قَد تَكون list من strings أَو list من {value, label_ar, label_en}
      final opts = f['options'];
      if (opts is List) {
        _optionsRaw.text = opts.map((o) {
          if (o is Map) {
            return '${o['label_ar'] ?? o['value']} | ${o['label_en'] ?? o['value']}';
          }
          return o.toString();
        }).join('\n');
      }
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _labelAr.dispose();
    _labelEn.dispose();
    _placeholder.dispose();
    _helperText.dispose();
    _optionsRaw.dispose();
    _minVal.dispose();
    _maxVal.dispose();
    _defaultVal.dispose();
    super.dispose();
  }

  bool get _needsOptions =>
      _type == 'select' || _type == 'radio' || _type == 'checkbox';
  bool get _needsMinMax => _type == 'number';
  /// 🆕 lookup_select يَحتاج اختِيار اسم القائِمة المَرجِعيّة بَدَلاً من خَيارات يَدَويّة
  bool get _needsLookup => _type == 'lookup_select';

  void _save(bool isAr) {
    // Validate
    if (_key.text.trim().isEmpty || _labelAr.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'المُعَرِّف (key) + الاسم العَرَبيّ مَطلوبَين'
            : 'Key and Arabic label are required'),
      ));
      return;
    }
    // اسم المِفتاح: حُروف صَغيرة + _
    final cleanKey = _key.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');

    final result = <String, dynamic>{
      'key': cleanKey,
      'type': _type,
      'label_ar': _labelAr.text.trim(),
      'label_en':
          _labelEn.text.trim().isEmpty ? _labelAr.text.trim() : _labelEn.text.trim(),
      'required': _required,
      'width': _width,  // 🆕 عَرض الحَقل (1-12)
    };
    if (_placeholder.text.trim().isNotEmpty) {
      result['placeholder'] = _placeholder.text.trim();
    }
    if (_helperText.text.trim().isNotEmpty) {
      result['helper'] = _helperText.text.trim();
    }
    if (_defaultVal.text.trim().isNotEmpty) {
      result['default'] = _defaultVal.text.trim();
    }
    if (_needsMinMax) {
      if (_minVal.text.trim().isNotEmpty) {
        result['min'] = double.tryParse(_minVal.text.trim());
      }
      if (_maxVal.text.trim().isNotEmpty) {
        result['max'] = double.tryParse(_maxVal.text.trim());
      }
    }
    if (_needsOptions) {
      // كلّ سَطر = خيار. الصيغة: "عَرَبيّ | إنجليزيّ" أَو فَقَط "نص"
      final lines = _optionsRaw.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final options = <Map<String, dynamic>>[];
      for (var i = 0; i < lines.length; i++) {
        final parts = lines[i].split('|').map((p) => p.trim()).toList();
        final labelAr = parts[0];
        final labelEn = parts.length > 1 ? parts[1] : labelAr;
        options.add({
          'value': labelEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
          'label_ar': labelAr,
          'label_en': labelEn,
        });
      }
      result['options'] = options;
    }
    // 🆕 lookup_select — احفَظ اسم القائِمة المَرجِعيّة
    if (_needsLookup) {
      if (_lookupName == null || _lookupName!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(isAr
              ? 'اختَر القائِمة المَرجِعيّة أَوَّلاً'
              : 'Pick a lookup source first'),
        ));
        return;
      }
      result['lookup'] = _lookupName;
    }
    // 🆕 gps_picker — حُقول لَات/لُنج مُسبَّقة بِالـkey
    if (_type == 'gps_picker') {
      result['lat_key'] = '${cleanKey}_lat';
      result['lng_key'] = '${cleanKey}_lng';
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final isNew = widget.existing == null;

    // 🆕 Scaffold بَسيط — AppBar + body ListView + bottom toolbar
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        // 🆕 أَيقونة الرجوع ذَهَبيّة وَواضِحة
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Text(
          isNew
              ? (isAr ? '➕ حَقل جَديد' : '➕ New field')
              : (isAr ? '✏ تَعديل حَقل' : '✏ Edit field'),
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isAr ? 'إلغاء' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check),
                  label: Text(isAr ? 'حِفظ الحَقل' : 'Save field'),
                  onPressed: () => _save(isAr),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            Row(
              children: [
                Icon(isNew ? Icons.add_circle : Icons.edit,
                    color: AppColors.brand),
                const SizedBox(width: 8),
                Text(
                  isNew
                      ? (isAr ? '➕ حَقل جَديد' : '➕ New field')
                      : (isAr ? '✏ تَعديل حَقل' : '✏ Edit field'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // === النَوع ===
            Text(
              isAr ? '1️⃣ نَوع الحَقل' : '1️⃣ Field type',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            _TypeGrid(
              selected: _type,
              isAr: isAr,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 16),

            // === المُعَرِّف ===
            Text(
              isAr
                  ? '2️⃣ المُعَرِّف (key) — حُروف إنجليزيّة فَقَط'
                  : '2️⃣ Key — lowercase identifier',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                hintText: 'employee_name',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // === الاسم ===
            Text(
              isAr ? '3️⃣ العُنوان' : '3️⃣ Label',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelAr,
                    decoration: const InputDecoration(
                      labelText: 'العَرَبيّ',
                      hintText: 'اسم الموظَّف',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _labelEn,
                    decoration: const InputDecoration(
                      labelText: 'English',
                      hintText: 'Employee Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeholder,
              decoration: InputDecoration(
                labelText: isAr ? 'مِثال داخِل الحَقل' : 'Placeholder',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lightbulb_outline),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _helperText,
              decoration: InputDecoration(
                labelText: isAr ? 'نَصّ مُساعِد (تَلميح)' : 'Helper text',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.info_outline),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _required,
              onChanged: (v) => setState(() => _required = v ?? false),
              title: Text(
                isAr ? 'إجباريّ *' : 'Required *',
                style: const TextStyle(fontSize: 13),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),

            // === 🆕 عَرض الحَقل (Layout Width) ===
            const SizedBox(height: 16),
            Text(
              isAr
                  ? '4️⃣ عَرض الحَقل في الصَفحة'
                  : '4️⃣ Field width on page',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            _WidthPicker(
              selected: _width,
              isAr: isAr,
              onChanged: (w) => setState(() => _width = w),
            ),

            // === خَيارات Number ===
            if (_needsMinMax) ...[
              const SizedBox(height: 16),
              Text(
                isAr ? '4️⃣ الحَدّ الأَدنى والأَعلى' : '4️⃣ Min/Max',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minVal,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isAr ? 'الحَدّ الأَدنى' : 'Min',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _maxVal,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isAr ? 'الحَدّ الأَعلى' : 'Max',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // === خَيارات Select / Radio / Checkbox ===
            if (_needsOptions) ...[
              const SizedBox(height: 16),
              Text(
                isAr ? '4️⃣ الخَيارات' : '4️⃣ Options',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'سَطر لِكلّ خَيار — صيغة: "عَرَبيّ | إنجليزيّ" (الفاصِل |)'
                    : 'One per line — format: "Arabic | English"',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _optionsRaw,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                  hintText: isAr
                      ? 'نَعَم | Yes\nلا | No\nرُبَّما | Maybe'
                      : 'Yes | Yes\nNo | No',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],

            // === 🆕 اختِيار القائِمة المَرجِعيّة (لِـlookup_select) ===
            if (_needsLookup) ...[
              const SizedBox(height: 16),
              Text(
                isAr
                    ? '4️⃣ مَصدَر القائِمة'
                    : '4️⃣ Lookup Source',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'الخَيارات سَتُحَمَّل تِلقائيّاً من القائِمة المَرجِعيّة المُختارة. تُدار من: مَركَز الإعدادات ← القَوائِم المَرجِعيّة'
                    : 'Options will load automatically from the chosen lookup. Manage them in: Settings Hub → Lookups',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _lookupName,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.list_alt, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText:
                      isAr ? 'اختَر المَصدَر *' : 'Pick lookup source *',
                ),
                items: _lookupOptions
                    .map((opt) => DropdownMenuItem<String>(
                          value: opt['value'],
                          child: Row(
                            children: [
                              Text(isAr ? opt['label_ar']! : opt['label_en']!),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.brand.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  opt['value']!,
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      color: AppColors.brand),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _lookupName = v),
              ),
              const SizedBox(height: 4),
              if (_lookupName != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.success.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'سَيَجلُب الحَقل خَيارات "${_lookupOptions.firstWhere((o) => o['value'] == _lookupName)['label_ar']}" مُباشَرة من قاعِدة البَيانات'
                              : 'This field will pull "${_lookupOptions.firstWhere((o) => o['value'] == _lookupName)['label_en']}" options directly from the database',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // === القيمة الافتراضيّة ===
            const SizedBox(height: 16),
            Text(
              isAr ? '5️⃣ القَيمة الافتراضيّة (اختياريّ)' : '5️⃣ Default value',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _defaultVal,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),
            // الأَزرار نُقِلَت إلى bottomNavigationBar
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 مَعاينة بَصَريّة لِتَخطيط الفورم
// ============================================================
class _LayoutPreview extends StatelessWidget {
  final List<Map<String, dynamic>> fields;
  final bool isAr;
  const _LayoutPreview({required this.fields, required this.isAr});

  @override
  Widget build(BuildContext context) {
    // قَسِّم الحُقول إلى صُفوف بِناءً على المَجموع ≤ 12
    final rows = <List<Map<String, dynamic>>>[];
    var currentRow = <Map<String, dynamic>>[];
    var currentSum = 0;

    for (final f in fields) {
      final w = _safeWidth(f['width']);
      if (currentSum + w > 12) {
        if (currentRow.isNotEmpty) rows.add(currentRow);
        currentRow = [f];
        currentSum = w;
      } else {
        currentRow.add(f);
        currentSum += w;
      }
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);

    return Column(
      children: rows.map((row) {
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: row.map((f) {
              final w = _safeWidth(f['width']);
              final label = isAr
                  ? (f['label_ar'] ?? f['key'] ?? '').toString()
                  : (f['label_en'] ?? f['key'] ?? '').toString();
              return Expanded(
                flex: w,
                child: Container(
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _colorForType(f['type']?.toString() ?? 'text'),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForType(f['type']?.toString() ?? 'text'),
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label.isEmpty
                              ? (isAr ? '(بدون عنوان)' : '(no label)')
                              : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'textarea':
        return const Color(0xFF06B6D4); // cyan
      case 'number':
        return const Color(0xFFEAB308); // yellow
      case 'date':
        return const Color(0xFF10B981); // emerald
      case 'select':
        return const Color(0xFF8B5CF6); // violet
      case 'radio':
        return const Color(0xFFEC4899); // pink
      case 'checkbox':
        return const Color(0xFFF59E0B); // amber
      case 'signature':
        return const Color(0xFF6B7280); // gray
      default:
        return AppColors.brand;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'textarea':
        return Icons.notes;
      case 'number':
        return Icons.numbers;
      case 'date':
        return Icons.calendar_today;
      case 'select':
        return Icons.list;
      case 'radio':
        return Icons.radio_button_checked;
      case 'checkbox':
        return Icons.check_box;
      case 'signature':
        return Icons.draw;
      default:
        return Icons.short_text;
    }
  }
}

// ============================================================
// 🆕 مُحَدِّد عَرض الحَقل (Layout Width)
// ============================================================
class _WidthPicker extends StatelessWidget {
  final int selected;
  final bool isAr;
  final ValueChanged<int> onChanged;
  const _WidthPicker({
    required this.selected,
    required this.isAr,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      {'value': 12, 'labelAr': 'كامِل',     'labelEn': 'Full',    'fraction': '1'},
      {'value': 9,  'labelAr': '3 أَرباع', 'labelEn': '3/4',    'fraction': '¾'},
      {'value': 8,  'labelAr': 'ثُلثَين',   'labelEn': '2/3',    'fraction': '⅔'},
      {'value': 6,  'labelAr': 'نِصف',     'labelEn': 'Half',   'fraction': '½'},
      {'value': 4,  'labelAr': 'ثُلث',     'labelEn': '1/3',    'fraction': '⅓'},
      {'value': 3,  'labelAr': 'رُبع',     'labelEn': '1/4',    'fraction': '¼'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // مُعاينة بَصَريّة للعَرض المُختار
        Container(
          height: 28,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                flex: selected,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$selected/12',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (selected < 12)
                Expanded(
                  flex: 12 - selected,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isAr ? 'فاضي' : 'empty',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // أَزرار الاختيار
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final v = opt['value'] as int;
            final isSel = v == selected;
            return InkWell(
              onTap: () => onChanged(v),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel
                      ? AppColors.brand
                      : Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSel
                        ? AppColors.brand
                        : Theme.of(context).dividerColor,
                    width: isSel ? 1.5 : 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt['fraction'] as String,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isSel ? Colors.white : AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isAr
                          ? opt['labelAr'] as String
                          : opt['labelEn'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isSel
                            ? Colors.white
                            : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          isAr
              ? '💡 الحُقول بِنَفس الصَفّ تَنضَمّ تلقائيّاً (مَثلاً نِصف + نِصف = صَفّ واحِد)'
              : '💡 Fields in same row auto-stack (e.g. half + half = one row)',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}

// ============================================================
// شَبَكة اختيار النَوع
// ============================================================
class _TypeGrid extends StatelessWidget {
  final String selected;
  final bool isAr;
  final ValueChanged<String> onChanged;
  const _TypeGrid({
    required this.selected,
    required this.isAr,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final types = _FieldBuilderSheetState._typeOptions;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (_, i) {
        final t = types[i];
        final value = t['value'] as String;
        final isSel = selected == value;
        return InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSel
                  ? AppColors.brand.withOpacity(0.15)
                  : Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSel
                    ? AppColors.brand
                    : Theme.of(context).dividerColor,
                width: isSel ? 1.5 : 0.6,
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  t['icon'] as IconData,
                  size: 22,
                  color: isSel ? AppColors.brand : Colors.grey,
                ),
                const SizedBox(height: 4),
                Text(
                  isAr ? t['label_ar'] as String : t['label_en'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isSel ? FontWeight.w900 : FontWeight.w600,
                    color: isSel ? AppColors.brand : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
