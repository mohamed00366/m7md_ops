import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;

import '../core/l10n/app_strings.dart';
import '../core/theme/app_colors.dart';

/// 🗺 شاشة اختِيار مَوقِع شامِلة — تَستَخدِم OpenStreetMap + Nominatim
///
/// المُمَيِّزات:
///   • خَريطة OSM بِدون مِفتاح API
///   • النَقر على الخَريطة → تَحديد المَوقِع
///   • شَريط بَحث في الأَعلى → Nominatim geocoding (بَحث بِالاسم)
///   • زِرّ "تَأكيد" يُرجِع LatLng
///   • قَيمة افتِراضيّة اختِياريّة (لِتَعديل مَوقِع مَوجود)
///
/// الاستِخدام:
/// ```dart
/// final result = await Navigator.of(context).push<LatLng>(
///   MaterialPageRoute(
///     builder: (_) => LocationMapPicker(
///       initial: LatLng(25.2048, 55.2708),
///       title: 'اختَر مَوقِع النُقطة',
///     ),
///   ),
/// );
/// if (result != null) {
///   lat.text = result.latitude.toString();
///   lng.text = result.longitude.toString();
/// }
/// ```
class LocationMapPicker extends StatefulWidget {
  /// مَوقِع ابتِدائيّ — لِتَعديل مَوقِع مَوجود
  final LatLng? initial;

  /// عُنوان الشاشة (اختِياريّ — افتِراضيّ: "اختَر المَوقِع")
  final String? title;

  const LocationMapPicker({super.key, this.initial, this.title});

  @override
  State<LocationMapPicker> createState() => _LocationMapPickerState();
}

class _LocationMapPickerState extends State<LocationMapPicker> {
  late final MapController _mapCtrl;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  LatLng? _picked;
  bool _searching = false;
  List<_GeocodeResult> _results = [];

  // مَركَز افتِراضيّ: دبي / الرياض
  static const _defaultCenter = LatLng(24.7136, 46.6753);

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _picked = widget.initial;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ============================================================
  // 🔍 Nominatim search (geocoding)
  // ============================================================
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (mounted) setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&format=json&addressdetails=1&limit=8',
      );
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'M7-Nexus-App/1.0 (m7w.app)',
          'Accept-Language': 'ar,en',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        if (mounted) setState(() => _results = []);
        return;
      }
      final body = json.decode(res.body) as List;
      final results = body.map((r) {
        final m = r as Map<String, dynamic>;
        return _GeocodeResult(
          name: (m['display_name'] ?? '').toString(),
          lat: double.tryParse(m['lat']?.toString() ?? '') ?? 0,
          lng: double.tryParse(m['lon']?.toString() ?? '') ?? 0,
        );
      }).toList();
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onResultTap(_GeocodeResult r) {
    final ll = LatLng(r.lat, r.lng);
    setState(() {
      _picked = ll;
      _results = [];
      _searchCtrl.text = r.name.split(',').take(2).join(',').trim();
    });
    _mapCtrl.move(ll, 15);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 18),
            const SizedBox(width: 6),
            Text(widget.title ?? (isAr ? 'اختَر المَوقِع' : 'Pick Location')),
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
          // ===== الخَريطة =====
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

          // ===== شَريط البَحث + النَتائِج =====
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Column(
              children: [
                // مُدخَل البَحث
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: isAr
                          ? '🔍 ابحَث عَن مَكان أَو عُنوان...'
                          : '🔍 Search for a place or address...',
                      prefixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _results = []);
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                // قائِمة النَتائِج
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined,
                              size: 18, color: AppColors.brand),
                          title: Text(
                            r.name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _onResultTap(r),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ===== مَعلومات الـpicked في الأَسفَل =====
          if (_picked != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed,
                        color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'المَوقِع المُختار' : 'Selected Location',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                          Text(
                            '${_picked!.latitude.toStringAsFixed(6)}, ${_picked!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
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

class _GeocodeResult {
  final String name;
  final double lat;
  final double lng;
  const _GeocodeResult({
    required this.name,
    required this.lat,
    required this.lng,
  });
}
