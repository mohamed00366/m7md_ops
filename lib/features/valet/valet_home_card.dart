import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../unified/smart_home_navigator.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🚗 بِطاقة الفاليه في الصَفحة الرَئيسيّة (لِمَن لَدَيه صَلاحيّة عَرض الفاليه فَقَط).
class ValetHomeCard extends StatefulWidget {
  const ValetHomeCard({super.key});

  @override
  State<ValetHomeCard> createState() => _ValetHomeCardState();
}

class _ValetHomeCardState extends State<ValetHomeCard> {
  VJson? _d;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await ValetAdmin.I.restore();
    await _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  Future<void> _load() async {
    if (!ValetAdmin.I.hasSession) return;
    try {
      final d = await ValetAdmin.I.call('vva_live');
      if (mounted) setState(() => _d = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasPermission(ValetAdmin.permView)) return const SizedBox.shrink();
    final d = _d;
    final pts = vList(d?['points']);
    final req = vList(d?['requests']);
    num sum(String k) => pts.fold<num>(0, (a, p) => a + vNum(p[k]));
    final late = req.where((r) => DateTime.now().difference(vTime(r['requested_at']) ?? DateTime.now()).inMinutes >= 10).length;
    final open = pts.where((p) => p['valet_shift'] != null).length;
    Widget stat(String v, String l, Color? c) => Expanded(
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
            Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: VC.muted)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => SmartHomeNavigator.of(context)?.onOpenModule('valet_live'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.local_parking, color: VC.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(tx(context, 'الفاليه الآن', 'Valet now'), style: const TextStyle(fontWeight: FontWeight.w700))),
                if (late > 0) VPill(tx(context, '$late طَلَب مُتَأَخِّر', '$late late request(s)'), color: VC.bad, icon: Icons.notifications_active),
                const Icon(Icons.chevron_right),
              ]),
              const SizedBox(height: 10),
              if (!ValetAdmin.I.hasSession)
                Text(tx(context, 'اضغَط لِفَتح قِسم الفاليه.', 'Tap to open the valet section.'), style: const TextStyle(color: VC.muted))
              else if (d == null)
                const LinearProgressIndicator(minHeight: 2)
              else
                Row(children: [
                  stat(VF.n(sum('active')), tx(context, 'سَيّارات في المَواقِع', 'Cars on site'), null),
                  stat(VF.n(req.length), tx(context, 'طَلَبات بانتِظار', 'Waiting requests'), req.isEmpty ? null : VC.warn),
                  stat('$open/${pts.length}', tx(context, 'وَرديّات مَفتوحة', 'Open shifts'), VC.info),
                  stat(VF.money(sum('today_revenue')), tx(context, 'إيراد اليَوم AED', 'Revenue today AED'), VC.ok),
                ]),
            ]),
          ),
        ),
      ),
    );
  }
}
