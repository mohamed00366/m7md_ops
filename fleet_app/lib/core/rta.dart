/// RTA mParking messages (7275) – the same reader as the server (DB 339 vip__rta_parse / vip__rta_parse_out),
/// used for the Excel on the device.
library;

class RtaInfo {
  const RtaInfo({
    required this.kind,
    this.emirate = '',
    this.plate = '',
    this.inv = '',
    this.zones = '',
    this.zone = '',
    this.fee,
    this.tnxFee,
    this.exp,
    this.hours,
    this.maxHours,
  });

  /// in: confirm / extension / reminder / error / free / other · out: pay / extend / other
  final String kind;
  final String emirate;
  final String plate;
  final String inv;
  final String zones;
  final String zone;
  final double? fee;
  final double? tnxFee;
  final DateTime? exp;
  final int? hours;
  final int? maxHours;

  /// Fee + transaction fee ([withTnx] = false: the fee only).
  double total({bool withTnx = true}) => (fee ?? 0) + (withTnx ? (tnxFee ?? 0) : 0);

  bool get confirmed => kind == 'confirm' || kind == 'extension';
}

bool isRtaNumber(String address) => address.replaceAll(RegExp(r'\D'), '').endsWith('7275');

/// A reply FROM 7275.
RtaInfo parseRtaIn(String body) {
  final u = body.toUpperCase();
  String kind;
  if (RegExp(r'(INVALID|NOT ALLOWED|INSUFFICIENT|NOT ENOUGH|FAILED|REJECTED|INCORRECT|WRONG|UNABLE|غير صحيح|رصيد غير كاف)').hasMatch(u)) {
    kind = 'error';
  } else if (RegExp(r'^\s*REMINDER').hasMatch(u)) {
    kind = 'reminder';
  } else if (RegExp(r'^\s*EXTENSION').hasMatch(u)) {
    kind = 'extension';
  } else if (u.contains('FREE TODAY')) {
    kind = 'free';
  } else if (u.contains('PLATE-') && u.contains('INV-')) {
    kind = 'confirm';
  } else if (RegExp(r'(SEND Y|REPLY Y|TO EXTEND|WILL EXPIRE|EXPIRES IN|ABOUT TO EXPIRE)').hasMatch(u)) {
    kind = 'reminder';
  } else if (RegExp(r'(SUCCESS|CONFIRMED|VALID UNTIL|VALID TILL|THANK YOU)').hasMatch(u)) {
    kind = 'confirm';
  } else {
    kind = 'other';
  }
  String g(String re) => RegExp(re).firstMatch(u)?.group(1)?.trim() ?? '';
  final pm = RegExp(r'PLATE-\s*([A-Z]{2,4})\s+([A-Z0-9][A-Z0-9 ]*[A-Z0-9])').firstMatch(u);
  DateTime? exp;
  final em = RegExp(r'EXP-\s*(\d{1,2})/(\d{1,2})/(\d{2,4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)?').firstMatch(u);
  if (em != null) {
    var y = int.parse(em.group(3)!);
    if (y < 100) y += 2000;
    var h = int.parse(em.group(4)!);
    if (em.group(6) != null) h = (h % 12) + (em.group(6) == 'PM' ? 12 : 0);
    // Dubai time (UTC+4, no summer time)
    exp = DateTime.utc(y, int.parse(em.group(2)!), int.parse(em.group(1)!), h, int.parse(em.group(5)!)).subtract(const Duration(hours: 4));
  }
  final zones = g(r'VALID-\s*([^\n\r]+)');
  final zone = g(r'ZONE-\s*([0-9]{2,4}[A-Z]{0,3})');
  return RtaInfo(
    kind: kind,
    emirate: pm?.group(1) ?? '',
    plate: (pm?.group(2) ?? '').replaceAll(RegExp(r'[^A-Z0-9]'), ''),
    inv: g(r'INV-\s*([0-9A-Z]+)'),
    zones: zones,
    zone: zone.isNotEmpty ? zone : zones.split(',').first.trim(),
    fee: double.tryParse(g(r'(?:^|[\n\r\s])FEE-\s*AED\s*([0-9]+(?:\.[0-9]+)?)')),
    tnxFee: double.tryParse(g(r'TNXFEE-\s*AED\s*([0-9]+(?:\.[0-9]+)?)')),
    maxHours: int.tryParse(g(r'MAX-\s*([0-9]+)\s*HRS?')),
    exp: exp,
  );
}

/// A message the staff SENT to 7275: "CC57843 317AP 1" · "CC 57843 129CP 1" · "CC 57843 129 CP" · "AUH13 12345 335A 1" ·
/// "CC57843 317AP1" · "Y" / "1" (extend).
RtaInfo parseRtaOut(String body) {
  final u = body.trim().toUpperCase();
  if (const {'Y', '1', 'YES'}.contains(u)) return const RtaInfo(kind: 'extend');
  final t = u.split(RegExp(r'\s+'));
  final zoneRe = RegExp(r'^[0-9]{3}[A-Z]{0,2}[0-9]{0,2}$');
  var zi = -1;
  for (var i = 1; i < t.length; i++) {
    if (zoneRe.hasMatch(t[i]) && (i > 1 || RegExp(r'[0-9]').hasMatch(t[0]))) {
      zi = i;
      break;
    }
  }
  if (zi == 1 && t.length >= 3 && RegExp(r'^[0-9]{4,5}$').hasMatch(t[1])) {
    zi = -1;
    for (var i = 2; i < t.length; i++) {
      if (zoneRe.hasMatch(t[i])) {
        zi = i;
        break;
      }
    }
  }
  if (zi < 0) return const RtaInfo(kind: 'other');
  final plate = t.sublist(0, zi).join().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final m = RegExp(r'^([0-9]{3}[A-Z]{1,2})([0-9]{1,2})?$').firstMatch(t[zi]) ?? RegExp(r'^([0-9]{3})([0-9]{1,2})?$').firstMatch(t[zi]);
  var zone = m?.group(1) ?? t[zi];
  int? hours = int.tryParse(m?.group(2) ?? '');
  var nx = zi + 1;
  if (nx < t.length && RegExp(r'^[A-Z]{1,2}$').hasMatch(t[nx]) && RegExp(r'^[0-9]{3}$').hasMatch(zone)) {
    zone += t[nx];
    nx++;
  }
  if (hours == null && nx < t.length && RegExp(r'^[0-9]{1,2}$').hasMatch(t[nx])) hours = int.parse(t[nx]);
  return RtaInfo(kind: 'pay', plate: plate, zone: zone, hours: hours ?? 1);
}
