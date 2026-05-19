/// 🌍 منطقة جغرافيّة مسموح بها للدخول
///
/// تتكوّن من:
///   • نقطة مركز (lat, lng)
///   • نصف قطر بالكيلومتر (الدائرة المسموحة)
///   • قائمة Wi-Fi SSIDs اختياريّة (تجاوز سريع داخل المباني)
///   • رمز دولة IP اختياري (طبقة احتياطيّة)
class LoginZone {
  final String id;
  String nameAr;
  String nameEn;
  double centerLat;
  double centerLng;
  double radiusKm;
  List<String> wifiSsids; // أسماء شبكات Wi-Fi المسموحة
  String? ipCountryCode;  // رمز ISO مثل 'AE'، 'SA'
  bool isActive;
  String? color; // hex لتمييز المنطقة على الخريطة

  LoginZone({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.centerLat,
    required this.centerLng,
    this.radiusKm = 5.0,
    List<String>? wifiSsids,
    this.ipCountryCode,
    this.isActive = true,
    this.color,
  }) : wifiSsids = wifiSsids ?? [];

  /// تسلسل لـ JSON (للحفظ في SharedPreferences كـ string)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius_km': radiusKm,
        'wifi_ssids': wifiSsids,
        'ip_country_code': ipCountryCode,
        'is_active': isActive,
        'color': color,
      };

  factory LoginZone.fromJson(Map<String, dynamic> j) => LoginZone(
        id: j['id'] as String,
        nameAr: j['name_ar'] as String? ?? '',
        nameEn: j['name_en'] as String? ?? '',
        centerLat: (j['center_lat'] as num).toDouble(),
        centerLng: (j['center_lng'] as num).toDouble(),
        radiusKm: ((j['radius_km'] as num?) ?? 5.0).toDouble(),
        wifiSsids: (j['wifi_ssids'] as List?)?.cast<String>() ?? [],
        ipCountryCode: j['ip_country_code'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        color: j['color'] as String?,
      );

  LoginZone copyWith({
    String? nameAr,
    String? nameEn,
    double? centerLat,
    double? centerLng,
    double? radiusKm,
    List<String>? wifiSsids,
    String? ipCountryCode,
    bool? isActive,
    String? color,
  }) =>
      LoginZone(
        id: id,
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
        centerLat: centerLat ?? this.centerLat,
        centerLng: centerLng ?? this.centerLng,
        radiusKm: radiusKm ?? this.radiusKm,
        wifiSsids: wifiSsids ?? this.wifiSsids,
        ipCountryCode: ipCountryCode ?? this.ipCountryCode,
        isActive: isActive ?? this.isActive,
        color: color ?? this.color,
      );
}
