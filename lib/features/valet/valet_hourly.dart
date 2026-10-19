import 'package:flutter/material.dart';

import 'valet_ui.dart';

/// One band of an hourly table as the manager writes it:
/// "from [from] to [to] → [amount], once for the band" or "… [amount] for every hour of the band".
/// [to] null = open (every extra hour, no end). Times are minutes since the car came in.
class HourBand {
  HourBand({required this.from, required this.to, required this.amount, required this.hourly});
  int from;
  int? to;
  num amount;
  bool hourly;
}

/// A row of `valet_prices` (what the valet app reads): cumulative total of the band, open band =
/// per extra hour on top of the highest finite total.
class PriceSlab {
  PriceSlab(this.from, this.to, this.total);
  final int from;
  final int? to;
  final num total;
}

const int kDayMinutes = 24 * 60;

String fmtMinutes(int m) => m % 60 == 0 ? '${m ~/ 60}' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
String slabTime(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';

/// "4", "4:30", "24", "نهاية اليوم" -> minutes; "مفتوح", "∞", "Infinity", "" -> null (open).
int? parseBandTime(String s, {required bool allowOpen}) {
  final t = s.trim().toLowerCase();
  if (t.isEmpty || t.startsWith('inf') || t.contains('∞') || t.contains('مَفتوح') || t.contains('مفتوح') || t.contains('open')) {
    return allowOpen ? null : -1;
  }
  if (t.contains('نهاي') || t.contains('نِهاي') || t.contains('end')) return kDayMinutes;
  final p = t.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
  final h = int.tryParse(p[0]);
  if (h == null) return -1;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return h * 60 + m;
}

/// Bands -> rows to save. Hourly finite bands become one row per hour (cumulative).
List<PriceSlab> bandsToSlabs(List<HourBand> bands) {
  final out = <PriceSlab>[];
  num running = 0;
  for (final b in bands) {
    final to = b.to;
    if (to == null) {
      // open band: the app adds amount x every started hour on top of the highest finite total
      out.add(PriceSlab(b.from, null, b.amount));
      break;
    }
    if (!b.hourly) {
      running += b.amount;
      out.add(PriceSlab(b.from, to, running));
    } else {
      for (var s = b.from; s < to; s += 60) {
        final e = s + 60 > to ? to : s + 60;
        running += b.amount;
        out.add(PriceSlab(s, e, running));
      }
    }
  }
  return out;
}

/// Saved rows -> bands (one-hour rows with the same step are merged back into a "per hour" band).
List<HourBand> slabsToBands(List<PriceSlab> slabs) {
  final s = [...slabs]..sort((a, b) => a.from.compareTo(b.from));
  final out = <HourBand>[];
  num prev = 0;
  for (final x in s) {
    if (x.to == null) {
      out.add(HourBand(from: x.from, to: null, amount: x.total, hourly: true));
      break;
    }
    final inc = x.total - prev;
    prev = x.total;
    final oneHour = x.to! - x.from == 60;
    final last = out.isEmpty ? null : out.last;
    if (oneHour && last != null && last.to == x.from && last.amount == inc &&
        (last.hourly || (last.to! - last.from == 60))) {
      last
        ..to = x.to
        ..hourly = true;
    } else {
      out.add(HourBand(from: x.from, to: x.to, amount: inc, hourly: false));
    }
  }
  return out;
}

/// Same rule as the valet app (lib/core/pricing.dart hourlyPrice).
num priceAt(List<PriceSlab> slabs, int minutes) {
  if (slabs.isEmpty) return 0;
  final s = [...slabs]..sort((a, b) => a.from.compareTo(b.from));
  for (final x in s) {
    if (minutes >= x.from && (x.to == null || minutes < x.to!)) {
      if (x.to != null) return x.total;
      final finite = s.where((y) => y.to != null).map((y) => y.total);
      final base = finite.isEmpty ? 0 : finite.reduce((a, b) => a > b ? a : b);
      final extra = ((minutes - x.from) / 60).ceil().clamp(1, 100000);
      return base + x.total * extra;
    }
  }
  if (minutes < s.first.from) return s.first.total;
  return s.where((y) => y.to != null).fold<num>(0, (a, y) => y.total > a ? y.total : a);
}

/// Editable time: type it, or pick it from the list.
class BandTimeField extends StatelessWidget {
  const BandTimeField({super.key, required this.controller, required this.label, required this.allowOpen, required this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool allowOpen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[
      for (var h = 1; h <= 23; h++) ('$h', tx(context, '$h ساعة', '$h h')),
      ('24', tx(context, 'نِهاية اليَوم (24 ساعة)', 'End of day (24 h)')),
      if (allowOpen) (tx(context, 'مَفتوح', 'Open'), tx(context, 'مَفتوح — بِلا نِهاية', 'Open — no end')),
    ];
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: tx(context, 'مِثال 4 أَو 4:30', 'e.g. 4 or 4:30'),
        suffixIcon: PopupMenuButton<String>(
          tooltip: tx(context, 'اختَر', 'Pick'),
          icon: const Icon(Icons.arrow_drop_down),
          itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.$1, child: Text(o.$2))],
          onSelected: (v) {
            controller.text = v;
            onChanged();
          },
        ),
      ),
    );
  }
}
