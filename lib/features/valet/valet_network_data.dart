import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🌐 بَيانات قِسم الشَبَكة (vva_network): المَناطِق ▸ النِقاط ▸ الفُروع (وَعَميل كُلّ فَرع).
class Net {
  Net(VJson d)
      : areas = vList(d['areas']),
        points = vList(d['points']),
        clients = vList(d['clients']),
        branches = vList(d['branches']),
        links = vList(d['links']),
        types = vList(d['types']) {
    for (final a in areas) {
      area[vStr(a['id'])] = a;
    }
    for (final p in points) {
      point[vStr(p['id'])] = p;
      (pointsOfArea[vStr(p['area_id'])] ??= []).add(p);
    }
    for (final c in clients) {
      client[vStr(c['id'])] = c;
    }
    for (final b in branches) {
      branch[vStr(b['id'])] = b;
      (branchesOfClient[vStr(b['client_id'])] ??= []).add(b);
    }
    for (final t in types) {
      type[vStr(t['id'])] = t;
    }
    for (final l in links) {
      final p = vStr(l['point_id']), b = vStr(l['branch_id']);
      if (!point.containsKey(p) || !branch.containsKey(b)) continue;
      (branchesOfPoint[p] ??= []).add(b);
      (pointsOfBranch[b] ??= []).add(p);
      link['$p|$b'] = l;
    }
    for (final l in branchesOfPoint.values) {
      l.sort((a, b) => vStr(branch[a]?['name']).toLowerCase().compareTo(vStr(branch[b]?['name']).toLowerCase()));
    }
  }

  final List<VJson> areas, points, clients, branches, links, types;
  final area = <String, VJson>{}, point = <String, VJson>{}, client = <String, VJson>{}, branch = <String, VJson>{}, type = <String, VJson>{};
  final link = <String, VJson>{};
  final pointsOfArea = <String, List<VJson>>{}; // '' = without an area
  final branchesOfClient = <String, List<VJson>>{};
  final branchesOfPoint = <String, List<String>>{};
  final pointsOfBranch = <String, List<String>>{};

  List<VJson> get pointsWithoutArea => points.where((p) => vStr(p['area_id']).isEmpty || !area.containsKey(vStr(p['area_id']))).toList();
  List<VJson> get branchesUnlinked => branches.where((b) => (pointsOfBranch[vStr(b['id'])] ?? const []).isEmpty).toList();
  List<VJson> get clientsWithoutBranches => clients.where((c) => (branchesOfClient[vStr(c['id'])] ?? const []).isEmpty).toList();

  /// [kind, row] of everything waiting for Odoo / failed there.
  List<(String, VJson)> syncRows(String state) => [
        for (final a in areas)
          if (a['sync'] == state) ('area', a),
        for (final p in points)
          if (p['sync'] == state) ('point', p),
        for (final c in clients)
          if (c['sync'] == state) ('client', c),
        for (final b in branches)
          if (b['sync'] == state) ('branch', b),
        for (final l in links)
          if (l['sync'] == state) ('link', l),
      ];

  String clientName(dynamic id) => vStr(client[vStr(id)]?['name']);
  String typeName(BuildContext c, dynamic id) {
    final t = type[vStr(id)];
    return t == null ? '' : tx(c, vStr(t['name_ar']).isEmpty ? vStr(t['name']) : vStr(t['name_ar']), vStr(t['name']));
  }

  String areaName(dynamic id) => vStr(area[vStr(id)]?['name']);
  String pointLabel(dynamic id) {
    final p = point[vStr(id)];
    return p == null ? '' : '${vStr(p['code'])} · ${vStr(p['name'])}';
  }

  /// the text a record is found by
  String hay(String kind, VJson r) => switch (kind) {
        'area' => '${r['name']} ${r['code'] ?? ''}',
        'point' => '${r['code']} ${r['name']} ${r['address'] ?? ''} ${areaName(r['area_id'])}',
        'client' => '${r['name']} ${r['name_ar'] ?? ''} ${r['vat'] ?? ''} ${r['code'] ?? ''}',
        _ => '${r['name']} ${r['vat'] ?? ''} ${r['phone'] ?? ''} ${clientName(r['client_id'])} ${vStr(type[vStr(r['type_id'])]?['name'])} ${vStr(type[vStr(r['type_id'])]?['name_ar'])}',
      }
          .toLowerCase();
}

IconData netIcon(String kind) => switch (kind) {
      'area' => Icons.map_outlined,
      'point' => Icons.place_outlined,
      'client' => Icons.apartment,
      'branch' => Icons.storefront_outlined,
      _ => Icons.link,
    };

Color netColor(String kind) => switch (kind) {
      'area' => VC.info,
      'point' => VC.gold,
      'client' => const Color(0xFF8B5CF6),
      'branch' => VC.ok,
      _ => VC.muted,
    };

String netKindName(BuildContext c, String kind) => switch (kind) {
      'area' => tx(c, 'مَنطِقة', 'Area'),
      'point' => tx(c, 'نُقطة', 'Point'),
      'client' => tx(c, 'عَميل', 'Client'),
      'branch' => tx(c, 'فَرع', 'Branch'),
      _ => tx(c, 'رَبط', 'Link'),
    };

/// Odoo state of a record: synced / sending / error.
Widget netSyncPill(BuildContext c, VJson r) {
  if (r['sync'] == 'error') return VPill(tx(c, 'خَطَأ Odoo', 'Odoo error'), color: VC.bad, icon: Icons.error_outline);
  if (r['sync'] == 'pending') return VPill(tx(c, 'يُرسَل', 'Sending'), color: VC.warn, icon: Icons.sync);
  if (r['odoo_id'] != null) return const VPill('Odoo', color: VC.ok, icon: Icons.check);
  return VPill(tx(c, 'غَير مُرسَل', 'Not in Odoo'), icon: Icons.cloud_off_outlined);
}

class NetOption {
  const NetOption(this.id, this.label, {this.sub, this.icon});
  final String id;
  final String label;
  final String? sub;
  final IconData? icon;
}

/// 🔎 اختيار بِالكِتابة (واحِد أَو أَكثَر). يُعيد المُختار أَو null عِند الإلغاء.
Future<Set<String>?> netPick(BuildContext context, String title, List<NetOption> options,
    {Set<String> selected = const {}, bool multi = false}) {
  final sel = {...selected};
  final q = TextEditingController();
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final s = q.text.trim().toLowerCase();
      final list = options.where((o) => s.isEmpty || '${o.label} ${o.sub ?? ''}'.toLowerCase().contains(s)).toList();
      if (multi) list.sort((a, b) => (sel.contains(a.id) ? 0 : 1) - (sel.contains(b.id) ? 0 : 1));
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          height: 520,
          child: Column(children: [
            TextField(
              controller: q,
              autofocus: true,
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'اكتُب لِلبَحث', 'Type to search')),
              onChanged: (_) => set(() {}),
            ),
            if (multi)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(tx(ctx, 'المُختار: ${sel.length}', 'Selected: ${sel.length}'), style: const TextStyle(color: VC.muted, fontSize: 12))),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(tx(ctx, 'لا نَتائِج.', 'No results.'), style: const TextStyle(color: VC.muted)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final o = list[i];
                        return multi
                            ? CheckboxListTile(
                                dense: true,
                                value: sel.contains(o.id),
                                secondary: o.icon == null ? null : Icon(o.icon, size: 18),
                                title: Text(o.label),
                                subtitle: o.sub == null || o.sub!.isEmpty ? null : Text(o.sub!, style: const TextStyle(fontSize: 12)),
                                onChanged: (v) => set(() => v == true ? sel.add(o.id) : sel.remove(o.id)),
                              )
                            : ListTile(
                                dense: true,
                                leading: o.icon == null ? null : Icon(o.icon, size: 18),
                                selected: sel.contains(o.id),
                                title: Text(o.label),
                                subtitle: o.sub == null || o.sub!.isEmpty ? null : Text(o.sub!, style: const TextStyle(fontSize: 12)),
                                onTap: () => Navigator.pop(ctx, {o.id}),
                              );
                      },
                    ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          if (multi) FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: Text(tx(ctx, 'تَمّ', 'Done'))),
        ],
      );
    }),
  );
}

List<NetOption> netPointOptions(Net n, {bool withArea = true}) => [
      for (final p in n.points)
        NetOption(vStr(p['id']), '${vStr(p['code'])}  ${vStr(p['name'])}',
            sub: [if (withArea) n.areaName(p['area_id']), if (!vBool(p['is_active'])) 'closed'].where((e) => e.isNotEmpty).join(' · '), icon: Icons.place_outlined),
    ];

List<NetOption> netBranchOptions(Net n) => [
      for (final b in n.branches)
        NetOption(vStr(b['id']), vStr(b['name']), sub: [n.clientName(b['client_id']), if (!vBool(b['is_active'])) 'closed'].join(' · '), icon: Icons.storefront_outlined),
    ];

List<NetOption> netClientOptions(Net n) => [
      for (final c in n.clients) NetOption(vStr(c['id']), vStr(c['name']), sub: vStr(c['vat']), icon: Icons.apartment),
    ];

/// زِرّ اختيار يَعرِض القيمة الحاليّة (يَفتَح netPick).
class NetPickField extends StatelessWidget {
  const NetPickField({super.key, required this.label, required this.value, required this.onTap, this.icon, this.error});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? error;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, isDense: true, errorText: error, prefixIcon: icon == null ? null : Icon(icon, size: 20),
              suffixIcon: const Icon(Icons.search, size: 18)),
          child: Text(value.isEmpty ? tx(context, 'اختَر…', 'Choose…') : value, style: TextStyle(color: value.isEmpty ? VC.muted : null)),
        ),
      );
}
