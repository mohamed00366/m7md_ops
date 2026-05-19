import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'image_field.dart';

/// 🚗 حَقل عِدّة سَيّارات (Repeating Section)
///
/// يَعرِض قائِمة بِطاقات كُلّ بِطاقة فيها بَيانات سَيّارة + صُوَر.
/// يُحفَظ كَـList<Map> في الـvalue.
///
/// كُلّ سَيّارة:
///   - role: our_vehicle / third_party
///   - plate, model, color
///   - driver_name (إذا our_vehicle), owner_name + phone (إذا third_party)
///   - photo_before, photo_after
///   - damage_description
class VehiclesField extends StatefulWidget {
  final String label;
  final bool required;
  final List<Map<String, dynamic>> initial;
  final String? helper;
  final bool isAr;
  final void Function(List<Map<String, dynamic>> vehicles) onChanged;

  const VehiclesField({
    super.key,
    required this.label,
    required this.required,
    required this.initial,
    required this.onChanged,
    required this.isAr,
    this.helper,
  });

  @override
  State<VehiclesField> createState() => _VehiclesFieldState();
}

class _VehiclesFieldState extends State<VehiclesField> {
  late List<Map<String, dynamic>> _vehicles;

  @override
  void initState() {
    super.initState();
    _vehicles = widget.initial
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
  }

  void _emit() => widget.onChanged(_vehicles);

  void _addVehicle({String role = 'third_party'}) {
    setState(() {
      _vehicles.add({
        'role': role,
        'plate': '',
        'model': '',
        'color': '',
        'driver_name': '',
        'owner_name': '',
        'owner_phone': '',
        'photo_before': null,
        'photo_after': null,
        'damage_description': '',
      });
    });
    _emit();
  }

  void _removeVehicle(int index) {
    setState(() => _vehicles.removeAt(index));
    _emit();
  }

  void _updateVehicle(int index, String key, dynamic value) {
    setState(() => _vehicles[index][key] = value);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === Header ===
          Row(
            children: [
              const Icon(Icons.directions_car, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style.copyWith(
                        fontSize: 13, fontWeight: FontWeight.w900),
                    children: [
                      TextSpan(text: widget.label),
                      if (widget.required)
                        const TextSpan(
                            text: ' *',
                            style: TextStyle(color: AppColors.danger)),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_vehicles.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 4),
            Text(widget.helper!,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
          const SizedBox(height: 10),

          // === Vehicles list ===
          if (_vehicles.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_outlined,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 6),
                  Text(
                    isAr
                        ? 'لا توجد سَيّارات بَعد'
                        : 'No vehicles yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _vehicles.length; i++)
              _VehicleCard(
                index: i,
                vehicle: _vehicles[i],
                isAr: isAr,
                onChange: (k, v) => _updateVehicle(i, k, v),
                onRemove: () => _removeVehicle(i),
              ),

          const SizedBox(height: 10),

          // === Add buttons ===
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addVehicle(role: 'our_vehicle'),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(
                    isAr ? '➕ سَيّارَتُنا' : '➕ Our vehicle',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addVehicle(role: 'third_party'),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(
                    isAr ? '➕ طَرف ثالِث' : '➕ Third party',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// بِطاقة سَيّارة واحِدة
// ============================================================================
class _VehicleCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> vehicle;
  final bool isAr;
  final void Function(String key, dynamic value) onChange;
  final VoidCallback onRemove;

  const _VehicleCard({
    required this.index,
    required this.vehicle,
    required this.isAr,
    required this.onChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isOurs = vehicle['role'] == 'our_vehicle';
    final roleColor = isOurs ? AppColors.success : AppColors.warning;
    final roleLabel = isOurs
        ? (isAr ? 'سَيّارَتُنا' : 'Our vehicle')
        : (isAr ? 'طَرف ثالِث' : 'Third party');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: roleColor.withOpacity(0.40), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: roleColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                tooltip: isAr ? 'حَذف' : 'Remove',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Plate + Model
          Row(
            children: [
              Expanded(
                child: _miniField(
                  label: isAr ? 'رَقَم اللَوحة' : 'Plate',
                  value: vehicle['plate']?.toString() ?? '',
                  onChange: (v) => onChange('plate', v),
                  hint: 'A 12345',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _miniField(
                  label: isAr ? 'الموديل' : 'Model',
                  value: vehicle['model']?.toString() ?? '',
                  onChange: (v) => onChange('model', v),
                  hint: 'Toyota Camry',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Color + Driver/Owner
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _miniField(
                  label: isAr ? 'اللَون' : 'Color',
                  value: vehicle['color']?.toString() ?? '',
                  onChange: (v) => onChange('color', v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _miniField(
                  label: isOurs
                      ? (isAr ? 'اسم السائِق' : 'Driver name')
                      : (isAr ? 'اسم المالِك' : 'Owner name'),
                  value: isOurs
                      ? (vehicle['driver_name']?.toString() ?? '')
                      : (vehicle['owner_name']?.toString() ?? ''),
                  onChange: (v) => onChange(
                      isOurs ? 'driver_name' : 'owner_name', v),
                ),
              ),
            ],
          ),

          // Phone (only for third party)
          if (!isOurs) ...[
            const SizedBox(height: 6),
            _miniField(
              label: isAr ? 'هاتِف المالِك' : 'Owner phone',
              value: vehicle['owner_phone']?.toString() ?? '',
              onChange: (v) => onChange('owner_phone', v),
              hint: '+971...',
            ),
          ],

          const SizedBox(height: 8),

          // Damage description
          _miniField(
            label: isAr ? 'وَصف الضَرَر' : 'Damage description',
            value: vehicle['damage_description']?.toString() ?? '',
            onChange: (v) => onChange('damage_description', v),
            maxLines: 2,
          ),

          const SizedBox(height: 10),

          // Photos: before + after
          Row(
            children: [
              Expanded(
                child: ImageField(
                  label: isAr ? '📸 قَبل' : '📸 Before',
                  required: false,
                  initialUrl: vehicle['photo_before']?.toString(),
                  isAr: isAr,
                  subFolder: 'incidents/vehicles',
                  onChanged: (url) => onChange('photo_before', url),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ImageField(
                  label: isAr ? '📸 بَعد' : '📸 After',
                  required: false,
                  initialUrl: vehicle['photo_after']?.toString(),
                  isAr: isAr,
                  subFolder: 'incidents/vehicles',
                  onChanged: (url) => onChange('photo_after', url),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniField({
    required String label,
    required String value,
    required void Function(String) onChange,
    String? hint,
    int maxLines = 1,
  }) {
    return TextFormField(
      initialValue: value,
      maxLines: maxLines,
      onChanged: onChange,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        labelStyle: const TextStyle(fontSize: 11),
        hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
      style: const TextStyle(fontSize: 12),
    );
  }
}
