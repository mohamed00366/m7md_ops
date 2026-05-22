import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/geo_fence_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/login_zone.dart';
import '../../shared/m7_app_bar.dart';

/// 🗺️ محرّر منطقة Geo-fence
///
/// • النقر على الخريطة → يضع المركز
/// • شريط لتعديل نصف القطر
/// • اسم عربي/إنجليزي + رمز دولة + Wi-Fi SSIDs
class GeoFenceZoneEditor extends StatefulWidget {
  final LoginZone? zone; // null = جديد
  const GeoFenceZoneEditor({super.key, this.zone});

  @override
  State<GeoFenceZoneEditor> createState() => _GeoFenceZoneEditorState();
}

class _GeoFenceZoneEditorState extends State<GeoFenceZoneEditor> {
  final _arCtrl = TextEditingController();
  final _enCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _wifiCtrl = TextEditingController();

  late LatLng _center;
  double _radiusKm = 5.0;
  bool _isActive = true;
  List<String> _wifiSsids = [];
  late MapController _mapController;

  bool get isEdit => widget.zone != null;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.zone != null) {
      final z = widget.zone!;
      _arCtrl.text = z.nameAr;
      _enCtrl.text = z.nameEn;
      _ipCtrl.text = z.ipCountryCode ?? '';
      _center = LatLng(z.centerLat, z.centerLng);
      _radiusKm = z.radiusKm;
      _isActive = z.isActive;
      _wifiSsids = List.from(z.wifiSsids);
    } else {
      // افتراضي: دبي
      _center = const LatLng(25.2048, 55.2708);
      _radiusKm = 5.0;
    }
  }

  @override
  void dispose() {
    _arCtrl.dispose();
    _enCtrl.dispose();
    _ipCtrl.dispose();
    _wifiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final isAr = AppStrings.of(context).isAr;
    if (_arCtrl.text.trim().isEmpty || _enCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAr
              ? 'الاسم العربي والإنجليزي مطلوبان'
              : 'Arabic & English names required'),
        ),
      );
      return;
    }
    final zone = LoginZone(
      id: widget.zone?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      nameAr: _arCtrl.text.trim(),
      nameEn: _enCtrl.text.trim(),
      centerLat: _center.latitude,
      centerLng: _center.longitude,
      radiusKm: _radiusKm,
      wifiSsids: _wifiSsids,
      ipCountryCode:
          _ipCtrl.text.trim().isEmpty ? null : _ipCtrl.text.trim().toUpperCase(),
      isActive: _isActive,
    );
    await GeoFenceSettings.instance.upsertZone(zone);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _addWifi() {
    final v = _wifiCtrl.text.trim();
    if (v.isEmpty) return;
    if (_wifiSsids.contains(v)) return;
    setState(() {
      _wifiSsids.add(v);
      _wifiCtrl.clear();
    });
  }

  /// تحويل نصف القطر بالكيلومتر إلى متر للرسم
  double get _radiusMeters => _radiusKm * 1000.0;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isEdit
            ? (isAr ? 'تعديل منطقة' : 'Edit Zone')
            : (isAr ? 'منطقة جديدة' : 'New Zone'),
        actions: [
          M7AppBarAction(
            icon: Icons.save_outlined,
            tooltip: isAr ? 'حفظ' : 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 1) Map =====
          Container(
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Theme.of(context).dividerColor, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 12,
                    onTap: (tapPos, latLng) {
                      setState(() => _center = latLng);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.m7md.ops',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _center,
                          color:
                              AppColors.brand.withValues(alpha: 0.15),
                          borderColor: AppColors.brand,
                          borderStrokeWidth: 2,
                          radius: _radiusMeters,
                          useRadiusInMeter: true,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _center,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: AppColors.brand,
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Hint
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isAr
                          ? '👆 انقر على الخريطة لتحديد المركز'
                          : '👆 Tap on map to set center',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ===== 2) إحداثيّات حاليّة =====
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.my_location,
                    size: 14, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      'Lat: ${_center.latitude.toStringAsFixed(5)}, '
                      'Lng: ${_center.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3) نصف القطر =====
          Text(
            isAr
                ? 'نصف القطر: ${_radiusKm.toStringAsFixed(1)} كم'
                : 'Radius: ${_radiusKm.toStringAsFixed(1)} km',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Slider(
            value: _radiusKm,
            min: 0.5,
            max: 100,
            divisions: 199,
            label: '${_radiusKm.toStringAsFixed(1)} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),

          const SizedBox(height: 8),

          // ===== 4) الأسماء =====
          TextField(
            controller: _arCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'الاسم بالعربيّة' : 'Arabic name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _enCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'الاسم بالإنجليزيّة' : 'English name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 5) رمز الدولة =====
          TextField(
            controller: _ipCtrl,
            decoration: InputDecoration(
              labelText: isAr
                  ? 'رمز الدولة لـ IP (اختياري — مثل AE, SA)'
                  : 'IP country code (optional — e.g. AE, SA)',
              hintText: 'AE',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 3,
          ),

          const SizedBox(height: 8),

          // ===== 6) Wi-Fi SSIDs =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Theme.of(context).dividerColor, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'شبكات Wi-Fi المسموحة (اختياري)'
                      : 'Allowed Wi-Fi networks (optional)',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  isAr
                      ? 'أيّ جهاز متّصل بإحدى هذه الشبكات يُعتبر داخل المنطقة'
                      : 'Any device on these networks is considered inside the zone',
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wifiCtrl,
                        decoration: InputDecoration(
                          hintText: isAr
                              ? 'اسم الشبكة (SSID)'
                              : 'Network SSID',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (_) => _addWifi(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _addWifi,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (_wifiSsids.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _wifiSsids
                        .map((s) => Chip(
                              avatar: const Icon(Icons.wifi, size: 14),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(s,
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              deleteIcon:
                                  const Icon(Icons.close, size: 14),
                              onDeleted: () => setState(() {
                                _wifiSsids.remove(s);
                              }),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ===== 7) Active toggle =====
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Theme.of(context).dividerColor, width: 0.5),
            ),
            child: SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title:
                  Text(isAr ? 'المنطقة نشطة' : 'Active zone'),
              subtitle: Text(
                isAr
                    ? 'إن كانت معطّلة لا تُستخدم في فحص الدخول'
                    : 'If disabled, ignored during login check',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              isAr ? 'حفظ المنطقة' : 'Save Zone',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
