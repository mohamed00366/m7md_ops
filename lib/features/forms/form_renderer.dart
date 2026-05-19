import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// hide Path لِتَجَنُّب التَعارُض مَع dart:ui.Path المُستَخدَم في رَسم التَوقيع
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'widgets/image_field.dart';
import 'widgets/vehicles_field.dart';

/// 🔢 تَحويل آمِن لِعَرض الحَقل من JSONB (int/double/String) إلى int.
int _safeWidth(dynamic v) {
  if (v == null) return 12;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 12;
  }
  return 12;
}

/// 🧩 محرّك عرض النماذج الديناميكيّة
/// يقرأ schema (List<Map>) ويرسم الحقول المناسبة:
///   - text / textarea / number / date / radio / checkbox / select / signature
class FormRenderer extends StatefulWidget {
  final FormTemplate template;
  /// قيم افتراضيّة (مثلاً: name من حساب الموظف)
  final Map<String, dynamic> initialValues;
  /// عند الإرسال: تستلم الـ data
  final ValueChanged<Map<String, dynamic>> onSubmit;
  /// عند الإلغاء
  final VoidCallback? onCancel;
  /// نص الزر السفلي (افتراضياً: «إرسال»)
  final String? submitLabel;
  /// قراءة فقط (لمشاهدة طلب مُقدَّم)
  final bool readOnly;

  const FormRenderer({
    super.key,
    required this.template,
    this.initialValues = const {},
    required this.onSubmit,
    this.onCancel,
    this.submitLabel,
    this.readOnly = false,
  });

  @override
  State<FormRenderer> createState() => _FormRendererState();
}

class _FormRendererState extends State<FormRenderer> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, dynamic> _values;
  /// لكل حقل توقيع → قائمة ضربات (List<List<Offset>>)
  final Map<String, List<List<Offset>>> _signatures = {};

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
  }

  String _t(Map<String, dynamic> field, String suffix, bool isAr) {
    final key = isAr ? 'label_ar' : 'label_en';
    return (field[key] ?? field['label_$suffix'] ?? field['key'] ?? '')
        .toString();
  }

  void _trySubmit() {
    if (widget.readOnly) {
      Navigator.maybePop(context);
      return;
    }
    if (_formKey.currentState?.validate() != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? '⚠ يوجد حقول مطلوبة'
            : '⚠ Required fields missing'),
      ));
      return;
    }
    // أضف التواقيع إلى values
    for (final entry in _signatures.entries) {
      _values[entry.key] = entry.value
          .map((stroke) =>
              stroke.map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}').join(';'))
          .join('|');
    }
    widget.onSubmit(_values);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== ترويسة النموذج =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brand, AppColors.brandAccent],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                if (widget.template.icon != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(_iconFromString(widget.template.icon!),
                        color: Colors.white, size: 24),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? widget.template.nameAr : widget.template.nameEn,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900),
                      ),
                      Text(
                        widget.template.code,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ===== الحقول =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12)),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              children: [
                // 🆕 عَرض الحُقول مَع احتِرام الـwidth (12-col grid)
                _buildFieldsGrid(widget.template.schema, isAr),
                const SizedBox(height: 12),
                // ===== أزرار سفلية =====
                Row(
                  children: [
                    if (widget.onCancel != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onCancel,
                          child: Text(s.cancel),
                        ),
                      ),
                    if (widget.onCancel != null) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _trySubmit,
                        icon: Icon(widget.readOnly
                            ? Icons.close
                            : Icons.send),
                        label: Text(
                          widget.submitLabel ??
                              (widget.readOnly
                                  ? (isAr ? 'إغلاق' : 'Close')
                                  : (isAr ? 'إرسال' : 'Submit')),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🆕 يَبني الحُقول في شَبَكة 12-عَمود مَع التَفاف تلقائيّ.
  /// كلّ حَقل لَه `width` (1-12). الحُقول في نَفس الصَفّ تَنضَمّ
  /// أُفُقيّاً إذا مَجموع العَرض ≤ 12.
  Widget _buildFieldsGrid(
      List<Map<String, dynamic>> schema, bool isAr) {
    // قَسِّم لِصُفوف
    final rows = <List<Map<String, dynamic>>>[];
    var currentRow = <Map<String, dynamic>>[];
    var currentSum = 0;
    for (final f in schema) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  flex: _safeWidth(row[i]['width']),
                  child: _buildField(row[i], isAr),
                ),
              ],
              // 🆕 لو الصَفّ ناقِص (مَجموع < 12) — اِملأ الفَراغ
              if (row.fold<int>(
                      0,
                      (sum, f) =>
                          sum + (_safeWidth(f['width']))) <
                  12)
                Expanded(
                  flex: 12 -
                      row.fold<int>(
                          0,
                          (sum, f) =>
                              sum + (_safeWidth(f['width']))),
                  child: const SizedBox.shrink(),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildField(Map<String, dynamic> field, bool isAr) {
    final type = (field['type'] ?? 'text').toString();
    final key = (field['key'] ?? '').toString();
    final label = isAr
        ? (field['label_ar'] ?? key).toString()
        : (field['label_en'] ?? key).toString();
    final required = field['required'] == true;
    switch (type) {
      case 'text':
        return _textField(key, label, required, false);
      case 'textarea':
        return _textField(key, label, required, true);
      case 'number':
        return _numberField(key, label, required, field);
      case 'date':
        return _dateField(key, label, required);
      case 'radio':
        return _radioField(key, label, required, field, isAr);
      case 'checkbox':
        return _checkboxField(key, label, field);
      case 'select':
        return _selectField(key, label, required, field, isAr);
      case 'signature':
        return _signatureField(key, label, required);
      case 'section':
        return _sectionHeader(label);
      case 'image':
        return _imageField(key, label, required, field, isAr);
      case 'vehicles':
        return _vehiclesField(key, label, required, field, isAr);
      case 'gps_picker':
        return _gpsPickerField(key, label, required, field, isAr);
      case 'lookup_select':
        return _lookupSelectField(key, label, required, field, isAr);
      case 'catalog_items':
        return _catalogItemsField(key, label, required, field, isAr);
      default:
        return Text('Unknown field type: $type');
    }
  }

  /// 🆕 حَقل اختِيار أَصناف الكاتالوج (تَلقائيّ: يَقرَأ مِن uniform_items)
  /// القيمة المُخَزَّنة: List<Map> = [{item_id, name_ar, name_en, size, qty}]
  Widget _catalogItemsField(
      String key, String label, bool required, Map field, bool isAr) {
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final items = auth
        .filterByCountry(repo.uniformCatalog, (u) => u.countryId)
        .where((u) => u.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => (isAr ? a.nameAr : a.nameEn)
          .compareTo(isAr ? b.nameAr : b.nameEn));

    final rawSelected = _values[key];
    final selected = <String, int>{};
    if (rawSelected is List) {
      for (final s in rawSelected) {
        if (s is Map) {
          final id = s['item_id']?.toString();
          final qty = (s['qty'] as num?)?.toInt() ?? 1;
          if (id != null) selected[id] = qty;
        }
      }
    }

    void persist() {
      _values[key] = selected.entries.map((e) {
        final item = items.firstWhere(
          (i) => i.id == e.key,
          orElse: () =>
              UniformItem(id: e.key, nameAr: '?', nameEn: '?'),
        );
        return {
          'item_id': e.key,
          'name_ar': item.nameAr,
          'name_en': item.nameEn,
          'size': item.size,
          'qty': e.value,
        };
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label + (required ? ' *' : ''),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.brand.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${selected.length} ${isAr ? "صَنف" : "items"}',
                style: const TextStyle(
                    fontSize: 10,
                    color: AppPalette.brand,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.input,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr
                        ? 'لا تُوجَد أَصناف في الكاتالوج. أَضِف أَصنافاً مِن "تَجهيز المُوَظَّفين → الكاتالوج"'
                        : 'No items in catalog. Add items from "Employee Setup → Catalog"',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppPalette.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                  _catalogItemRow(
                    items[i],
                    repo,
                    isAr,
                    selected,
                    () {
                      persist();
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _catalogItemRow(
    UniformItem item,
    MockRepository repo,
    bool isAr,
    Map<String, int> selected,
    VoidCallback onChange,
  ) {
    final isPicked = selected.containsKey(item.id);
    final qty = selected[item.id] ?? 1;
    final stock = repo.uniformCurrentStock(item.id);
    return InkWell(
      onTap: widget.readOnly
          ? null
          : () {
              if (isPicked) {
                selected.remove(item.id);
              } else {
                selected[item.id] = 1;
              }
              onChange();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: isPicked,
              onChanged: widget.readOnly
                  ? null
                  : (v) {
                      if (v == true) {
                        selected[item.id] = 1;
                      } else {
                        selected.remove(item.id);
                      }
                      onChange();
                    },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? item.nameAr : item.nameEn,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      if (item.size.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          margin: const EdgeInsets.only(right: 4, top: 2),
                          decoration: BoxDecoration(
                            color: AppPalette.textSecondary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(item.size,
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      if (item.color.isNotEmpty)
                        Text(item.color,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppPalette.textSecondary)),
                      const SizedBox(width: 6),
                      Text(
                        '${isAr ? "مُتَوَفِّر" : "Stock"}: $stock',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: stock > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Qty stepper — يَظهَر فَقَط عَنَدَ التَحديد
            if (isPicked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28),
                    padding: EdgeInsets.zero,
                    onPressed: widget.readOnly || qty <= 1
                        ? null
                        : () {
                            selected[item.id] = qty - 1;
                            onChange();
                          },
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('$qty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        size: 18, color: AppPalette.brand),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28),
                    padding: EdgeInsets.zero,
                    onPressed: widget.readOnly
                        ? null
                        : () {
                            selected[item.id] = qty + 1;
                            onChange();
                          },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 🗺 GPS Picker — يَفتَح خَريطة لِاختِيار المَوقِع + يَملأ lat/lng تِلقائيّاً
  // ============================================================
  Widget _gpsPickerField(
    String key,
    String label,
    bool required,
    Map<String, dynamic> field,
    bool isAr,
  ) {
    // مَفاتيح فَرعيّة تُخَزَّن فيها الإحداثيّات (لِلتَوافُق مَع triggers قَديمة)
    final latKey = field['lat_key']?.toString() ?? '${key}_lat';
    final lngKey = field['lng_key']?.toString() ?? '${key}_lng';

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final lat = _toDouble(_values[latKey]);
    final lng = _toDouble(_values[lngKey]);
    final hasPicked = lat != null && lng != null;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: hasPicked
                ? AppColors.success.withOpacity(0.4)
                : AppPalette.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPicked ? Icons.location_on : Icons.location_off,
                color: hasPicked ? AppColors.success : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label + (required ? ' *' : ''),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (hasPicked && !widget.readOnly)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: isAr ? 'مَسح' : 'Clear',
                  onPressed: () => setState(() {
                    _values.remove(latKey);
                    _values.remove(lngKey);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasPicked) ...[
            // عَرض الإحداثيّات
            Row(
              children: [
                _coordChip(isAr ? 'العَرض' : 'Lat', lat.toStringAsFixed(6)),
                const SizedBox(width: 6),
                _coordChip(
                    isAr ? 'الطول' : 'Lng', lng.toStringAsFixed(6)),
              ],
            ),
            const SizedBox(height: 8),
            // مُعايَنة خَريطة صَغيرة
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 140,
                child: AbsorbPointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.m7w.app',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin,
                              color: AppColors.danger, size: 36),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                isAr
                    ? 'لم يَتِمّ تَحديد المَوقِع بَعد'
                    : 'No location picked yet',
                style: TextStyle(
                    fontSize: 12, color: theme.textTheme.bodySmall?.color),
              ),
            ),
          // زِرّ "اختَر من الخَريطة"
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.readOnly
                  ? null
                  : () => _openMapPicker(latKey, lngKey, lat, lng, isAr),
              icon: const Icon(Icons.map, size: 16),
              label: Text(
                hasPicked
                    ? (isAr ? 'تَغيير المَوقِع' : 'Change Location')
                    : (isAr ? '📍 اختَر من الخَريطة' : '📍 Pick on Map'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.brand.withOpacity(0.25)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.brand),
      ),
    );
  }

  Future<void> _openMapPicker(String latKey, String lngKey, double? curLat,
      double? curLng, bool isAr) async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => _InlineMapPicker(
          initial: (curLat != null && curLng != null)
              ? LatLng(curLat, curLng)
              : null,
          isAr: isAr,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _values[latKey] = result.latitude;
        _values[lngKey] = result.longitude;
      });
    }
  }

  // ============================================================
  // 📚 Lookup Select — يَجلُب الخَيارات من قائِمة مَرجِعيّة بَدَلاً من
  //    تَعريفها يَدَويّاً في schema.
  // مَدعوم: business_types, departments, job_titles, nationalities, visa_types
  // ============================================================
  Widget _lookupSelectField(
    String key,
    String label,
    bool required,
    Map<String, dynamic> field,
    bool isAr,
  ) {
    final lookupName = (field['lookup'] ?? '').toString();
    final repo = MockRepository();
    final options = <Map<String, String>>[];

    switch (lookupName) {
      case 'business_types':
        for (final b in repo.businessTypes) {
          options.add({
            'value': b.id,
            'label': isAr ? b.nameAr : b.nameEn,
          });
        }
        break;
      case 'departments':
        for (final d in repo.departments) {
          options.add({
            'value': d.id,
            'label': isAr ? d.nameAr : d.nameEn,
          });
        }
        break;
      case 'job_titles':
        for (final j in repo.jobTitles) {
          options.add({
            'value': j.id,
            'label': isAr ? j.nameAr : j.nameEn,
          });
        }
        break;
      case 'nationalities':
        for (final n in repo.nationalities) {
          options.add({
            'value': n.id,
            'label': isAr ? n.nameAr : n.nameEn,
          });
        }
        break;
      case 'visa_types':
        for (final v in repo.visaTypes) {
          options.add({
            'value': v.id,
            'label': isAr ? v.nameAr : v.nameEn,
          });
        }
        break;
      case 'countries':
        for (final c in repo.countries) {
          options.add({
            'value': c.id,
            'label': isAr ? c.nameAr : c.nameEn,
          });
        }
        break;
    }

    // فَرز أَلِفبائيّ
    options.sort((a, b) => (a['label'] ?? '').compareTo(b['label'] ?? ''));

    final cur = _values[key]?.toString();
    // تَأكَّد أنّ القيمة الحاليّة لا تَزال مَوجودة في الخَيارات
    final hasCurrent =
        cur != null && options.any((o) => o['value'] == cur);

    return DropdownButtonFormField<String>(
      value: hasCurrent ? cur : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        border: const OutlineInputBorder(),
        isDense: true,
        helperText: options.isEmpty
            ? (isAr
                ? '⚠️ القائِمة المَرجِعيّة فارِغة — أَضِف عَناصِر من الإعدادات'
                : '⚠️ Lookup is empty — add items in Settings')
            : null,
      ),
      items: options
          .map((o) => DropdownMenuItem(
                value: o['value'],
                child: Text(o['label'] ?? ''),
              ))
          .toList(),
      onChanged: widget.readOnly
          ? null
          : (v) => setState(() => _values[key] = v),
      validator: (v) {
        if (required && (v == null || v.isEmpty)) {
          return AppStrings.of(context).isAr ? 'مطلوب' : 'Required';
        }
        return null;
      },
    );
  }

  /// 📷 حَقل صورة — كاميرا/مَعرِض + رَفع لِـSupabase Storage
  Widget _imageField(
    String key,
    String label,
    bool required,
    Map<String, dynamic> field,
    bool isAr,
  ) {
    return ImageField(
      label: label,
      required: required,
      initialUrl: _values[key]?.toString(),
      helper: field['helper']?.toString(),
      isAr: isAr,
      subFolder: 'forms/${widget.template.code}',
      onChanged: (url) => _values[key] = url,
    );
  }

  /// 🚗 حَقل عِدّة سَيّارات (Repeating Section)
  Widget _vehiclesField(
    String key,
    String label,
    bool required,
    Map<String, dynamic> field,
    bool isAr,
  ) {
    final initial = <Map<String, dynamic>>[];
    final raw = _values[key];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) initial.add(Map<String, dynamic>.from(v));
      }
    }
    return VehiclesField(
      label: label,
      required: required,
      initial: initial,
      helper: field['helper']?.toString(),
      isAr: isAr,
      onChanged: (vehicles) => _values[key] = vehicles,
    );
  }

  /// رَأس قِسم — فاصِل بَصَريّ بَين مَجموعات الحُقول
  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Color(0xFF6B21A8),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ============= Widgets =============
  Widget _textField(String key, String label, bool required, bool multiline) {
    return TextFormField(
      initialValue: (_values[key] ?? '').toString(),
      readOnly: widget.readOnly,
      maxLines: multiline ? 3 : 1,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty)
              ? AppStrings.of(context).isAr ? 'مطلوب' : 'Required'
              : null
          : null,
      onChanged: (v) => _values[key] = v,
    );
  }

  Widget _numberField(
      String key, String label, bool required, Map<String, dynamic> field) {
    return TextFormField(
      initialValue: (_values[key] ?? '').toString(),
      readOnly: widget.readOnly,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return AppStrings.of(context).isAr ? 'مطلوب' : 'Required';
        }
        if (v != null && v.trim().isNotEmpty) {
          final n = num.tryParse(v);
          if (n == null) {
            return AppStrings.of(context).isAr
                ? 'رقم غير صالح'
                : 'Invalid number';
          }
          if (field['min'] != null && n < (field['min'] as num)) {
            return AppStrings.of(context).isAr
                ? 'الحدّ الأدنى ${field['min']}'
                : 'Min ${field['min']}';
          }
          if (field['max'] != null && n > (field['max'] as num)) {
            return AppStrings.of(context).isAr
                ? 'الحدّ الأقصى ${field['max']}'
                : 'Max ${field['max']}';
          }
        }
        return null;
      },
      onChanged: (v) => _values[key] = num.tryParse(v) ?? v,
    );
  }

  Widget _dateField(String key, String label, bool required) {
    final cur = _values[key];
    DateTime? value;
    if (cur is String && cur.isNotEmpty) {
      value = DateTime.tryParse(cur);
    } else if (cur is DateTime) {
      value = cur;
    }
    final text = value == null
        ? ''
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: widget.readOnly
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  _values[key] = picked.toIso8601String().substring(0, 10);
                });
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(text.isEmpty ? '—' : text,
            style: TextStyle(
                color: text.isEmpty
                    ? AppPalette.textTertiary
                    : AppPalette.text)),
      ),
    );
  }

  Widget _radioField(String key, String label, bool required,
      Map<String, dynamic> field, bool isAr) {
    final options =
        (field['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final current = (_values[key] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label + (required ? ' *' : ''),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final opt in options)
                RadioListTile<String>(
                  dense: true,
                  title: Text(isAr
                      ? (opt['label_ar'] ?? opt['value']).toString()
                      : (opt['label_en'] ?? opt['value']).toString()),
                  value: (opt['value'] ?? '').toString(),
                  groupValue: current,
                  onChanged: widget.readOnly
                      ? null
                      : (v) => setState(() => _values[key] = v),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _checkboxField(
      String key, String label, Map<String, dynamic> field) {
    final value = _values[key] == true;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: value,
      onChanged: widget.readOnly
          ? null
          : (v) => setState(() => _values[key] = v ?? false),
    );
  }

  Widget _selectField(String key, String label, bool required,
      Map<String, dynamic> field, bool isAr) {
    final options =
        (field['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final current = _values[key]?.toString();
    return DropdownButtonFormField<String>(
      value: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final opt in options)
          DropdownMenuItem<String>(
            value: (opt['value'] ?? '').toString(),
            child: Text(isAr
                ? (opt['label_ar'] ?? opt['value']).toString()
                : (opt['label_en'] ?? opt['value']).toString()),
          ),
      ],
      validator: required
          ? (v) => (v == null || v.isEmpty)
              ? AppStrings.of(context).isAr ? 'مطلوب' : 'Required'
              : null
          : null,
      onChanged: widget.readOnly
          ? null
          : (v) => setState(() => _values[key] = v),
    );
  }

  Widget _signatureField(String key, String label, bool required) {
    final strokes = _signatures.putIfAbsent(key, () => []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label + (required ? ' *' : ''),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
            if (strokes.isNotEmpty && !widget.readOnly)
              TextButton.icon(
                onPressed: () => setState(() => strokes.clear()),
                icon: const Icon(Icons.refresh,
                    size: 14, color: Colors.red),
                label: const Text('مسح',
                    style: TextStyle(color: Colors.red, fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppPalette.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppPalette.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              children: [
                if (strokes.isEmpty)
                  Center(
                    child: Text(
                      AppStrings.of(context).isAr
                          ? 'وقّع هنا'
                          : 'Sign here',
                      style: const TextStyle(
                          color: AppPalette.textTertiary,
                          fontSize: 11),
                    ),
                  ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: widget.readOnly
                        ? null
                        : (d) {
                            setState(() {
                              strokes.add([d.localPosition]);
                            });
                          },
                    onPanUpdate: widget.readOnly
                        ? null
                        : (d) {
                            setState(() {
                              if (strokes.isNotEmpty) {
                                strokes.last.add(d.localPosition);
                              }
                            });
                          },
                    child: CustomPaint(
                      painter: _SigPainter(strokes),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SigPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) =>
      old.strokes != strokes;
}

// تحويل اسم أيقونة من string → IconData
IconData _iconFromString(String name) {
  switch (name) {
    case 'beach_access':
      return Icons.beach_access;
    case 'attach_money':
      return Icons.attach_money;
    case 'description':
      return Icons.description;
    case 'logout':
      return Icons.logout;
    case 'school':
      return Icons.school;
    case 'badge':
      return Icons.badge;
    default:
      return Icons.assignment_outlined;
  }
}

// ============================================================
// 🗺 شاشة اختِيار المَوقِع — OpenStreetMap بَدون مِفتاح API
// تُرجِع `LatLng` عَنَدَ التَأكيد، `null` عَنَدَ الإلغاء
// ============================================================
class _InlineMapPicker extends StatefulWidget {
  final LatLng? initial;
  final bool isAr;
  const _InlineMapPicker({this.initial, required this.isAr});

  @override
  State<_InlineMapPicker> createState() => _InlineMapPickerState();
}

class _InlineMapPickerState extends State<_InlineMapPicker> {
  late final MapController _mapCtrl;
  LatLng? _picked;

  // مَركَز افتِراضيّ: دبي/الرياض
  static const _defaultCenter = LatLng(24.7136, 46.6753);

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _picked = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 18),
            const SizedBox(width: 6),
            Text(isAr ? 'اختَر المَوقِع' : 'Pick Location'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed:
                _picked == null ? null : () => Navigator.of(context).pop(_picked),
            icon: const Icon(Icons.check, color: Colors.white),
            label: Text(
              isAr ? 'تَأكيد' : 'Confirm',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: widget.initial ?? _defaultCenter,
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 18,
              onTap: (_, latlng) => setState(() => _picked = latlng),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.m7w.app',
              ),
              if (_picked != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_pin,
                        color: AppColors.danger, size: 36),
                  ),
                ]),
            ],
          ),
          // شَريط تَعليمات في الأَعلى
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 16, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _picked == null
                          ? (isAr
                              ? 'انقُر عَلى الخَريطة لِتَحديد المَوقِع'
                              : 'Tap on the map to pick the location')
                          : (isAr
                              ? 'العَرض ${_picked!.latitude.toStringAsFixed(6)} • الطول ${_picked!.longitude.toStringAsFixed(6)}'
                              : 'Lat ${_picked!.latitude.toStringAsFixed(6)} • Lng ${_picked!.longitude.toStringAsFixed(6)}'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
