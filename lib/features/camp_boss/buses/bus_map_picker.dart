import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/app_strings.dart';
import '../camp_palette.dart';
import 'buses_shared.dart';

/// 🗺️ شاشة اختيار موقع على الخريطة (OpenStreetMap)
/// تُعيد LatLng المختارة عند الضغط على "تأكيد"
class BusMapPicker extends StatefulWidget {
  final LatLng? initial;
  final String? title;

  const BusMapPicker({super.key, this.initial, this.title});

  @override
  State<BusMapPicker> createState() => _BusMapPickerState();
}

class _BusMapPickerState extends State<BusMapPicker> {
  late final MapController _mapCtrl;
  LatLng? _picked;

  // مركز افتراضي: الرياض/دبي تقريباً
  static const _defaultCenter = LatLng(24.7136, 46.6753);

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _picked = widget.initial;
  }

  void _onTap(TapPosition tap, LatLng latlng) {
    setState(() => _picked = latlng);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BusesPalette.primary,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 18),
            const SizedBox(width: 6),
            Text(widget.title ??
                (s.isAr ? 'اختر الموقع' : 'Pick Location')),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _picked == null
                ? null
                : () => Navigator.of(context).pop(_picked),
            icon: const Icon(Icons.check, color: Colors.white),
            label: Text(s.isAr ? 'تأكيد' : 'Confirm',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
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
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.m7w.app',
                tileProvider: NetworkTileProvider(),
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 44),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                  ),
                ],
              ),
            ],
          ),
          // ===== صندوق الإحداثيات =====
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place,
                        color: BusesPalette.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.isAr
                                ? 'الإحداثيات المختارة'
                                : 'Selected Coordinates',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: CampPalette.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _picked == null
                                ? (s.isAr
                                    ? 'اضغط على الخريطة لاختيار موقع'
                                    : 'Tap on the map to pick a location')
                                : '${_picked!.latitude.toStringAsFixed(6)}, ${_picked!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: _picked == null
                                  ? CampPalette.textTertiary
                                  : CampPalette.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_picked != null)
                      IconButton(
                        tooltip: s.isAr ? 'مسح' : 'Clear',
                        icon: const Icon(Icons.clear,
                            color: CampPalette.red, size: 18),
                        onPressed: () =>
                            setState(() => _picked = null),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🗺️ معاينة موقع غير قابلة للتعديل (للعرض في شاشة التفاصيل)
class BusMapPreview extends StatelessWidget {
  final double lat;
  final double lng;
  final double height;

  const BusMapPreview({
    super.key,
    required this.lat,
    required this.lng,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.m7w.app',
              tileProvider: NetworkTileProvider(),
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.location_on,
                      color: Colors.red, size: 38),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
