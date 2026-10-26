import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_network_data.dart';
import 'valet_ui.dart';

// ---------------------------------------------------------------- saving
/// يَحفَظ سِجِلّاً؛ عَميل بِاسم / TRN مُكَرَّر → يَسأَل "حِفظ عَلى أَيّ حال".
Future<String?> netSave(BuildContext context, String kind, String? id, Map<String, dynamic> data) async {
  try {
    final r = await ValetAdmin.I.call('vva_network_save', {'p_kind': kind, 'p_id': id, 'p_data': data});
    return vStr(r['id']);
  } on ValetError catch (e) {
    if (!context.mounted) return null;
    if (kind == 'client' && e.en.contains('already exists')) {
      final ok = await vConfirm(context, tx(context, 'عَميل مُكَرَّر؟', 'Duplicate client?'),
          tx(context, '${e.en}\nهَل تُريد الحِفظ عَلى أَيّ حال؟', '${e.en}\nSave anyway?'),
          button: tx(context, 'حِفظ عَلى أَيّ حال', 'Save anyway'));
      if (ok && context.mounted) return netSave(context, kind, id, {...data, 'force': true});
      return null;
    }
    vToast(context, vErr(context, e), error: true);
    return null;
  }
}

InputDecoration _dec(String label, {String? hint, IconData? icon}) =>
    InputDecoration(labelText: label, hintText: hint, isDense: true, prefixIcon: icon == null ? null : Icon(icon, size: 20));

Widget _gap() => const SizedBox(height: 10);

Future<T?> _form<T>(BuildContext context, {required String title, required IconData icon, required Widget Function(BuildContext, StateSetter) body,
    required Future<T?> Function(BuildContext) onSave, double width = 520}) {
  var busy = false;
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return AlertDialog(
        title: Row(children: [Icon(icon), const SizedBox(width: 8), Expanded(child: Text(title))]),
        content: SizedBox(width: width, child: SingleChildScrollView(child: body(ctx, set))),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton.icon(
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(tx(ctx, 'حِفظ', 'Save')),
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    final r = await onSave(ctx);
                    if (!ctx.mounted) return;
                    set(() => busy = false);
                    if (r != null) Navigator.pop(ctx, r);
                  },
          ),
        ],
      );
    }),
  );
}

/// نَوع الفَرع / العَميل (مَطعَم، فُندُق…) مَع إضافة نَوع جَديد.
class NetTypeField extends StatelessWidget {
  const NetTypeField({super.key, required this.net, required this.value, required this.onChanged});
  final Net net;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => NetPickField(
        label: tx(context, 'النَوع', 'Type'),
        icon: Icons.category_outlined,
        value: value == null ? '' : net.typeName(context, value),
        onTap: () async {
          final opts = [
            const NetOption('', '—'),
            for (final t in net.types) NetOption(vStr(t['id']), net.typeName(context, t['id']), sub: vStr(t['name'])),
            NetOption('+', tx(context, '+ نَوع جَديد', '+ New type'), icon: Icons.add),
          ];
          final r = await netPick(context, tx(context, 'النَوع', 'Type'), opts, selected: {value ?? ''});
          if (r == null || !context.mounted) return;
          final v = r.first;
          if (v != '+') return onChanged(v.isEmpty ? null : v);
          final en = TextEditingController(), ar = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(tx(c, 'نَوع جَديد', 'New type')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: en, autofocus: true, decoration: _dec('Name (English)', hint: 'Gym')),
                _gap(),
                TextField(controller: ar, decoration: _dec('الاسم (عَرَبيّ)', hint: 'نادي رياضي')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'إضافة', 'Add'))),
              ],
            ),
          );
          if (ok != true || !context.mounted || en.text.trim().isEmpty) return;
          final id = await netSave(context, 'type', null, {'name': en.text.trim(), 'name_ar': ar.text.trim()});
          if (id != null) {
            net.types.add({'id': id, 'name': en.text.trim(), 'name_ar': ar.text.trim()});
            net.type[id] = net.types.last;
            onChanged(id);
          }
        },
      );
}

// ---------------------------------------------------------------- client
Future<String?> netClientForm(BuildContext context, Net net, {VJson? row}) {
  final name = TextEditingController(text: vStr(row?['name']));
  final nameAr = TextEditingController(text: vStr(row?['name_ar']) == vStr(row?['name']) ? '' : vStr(row?['name_ar']));
  final vat = TextEditingController(text: vStr(row?['vat']));
  final lic = TextEditingController(text: vStr(row?['trade_license']));
  final notes = TextEditingController(text: vStr(row?['notes']));
  String? type = row?['type_id'] == null ? null : vStr(row!['type_id']);
  var active = row == null || vBool(row['is_active']);
  return _form<String>(context,
      title: row == null ? tx(context, 'عَميل جَديد', 'New client') : tx(context, 'تَعديل العَميل', 'Edit client'),
      icon: Icons.apartment,
      body: (c, set) => Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: row == null, decoration: _dec(tx(c, 'اسم الشَرِكة *', 'Company name *'), icon: Icons.apartment)),
            _gap(),
            TextField(controller: nameAr, decoration: _dec(tx(c, 'الاسم بِالعَرَبيّ', 'Name in Arabic'))),
            _gap(),
            Row(children: [
              Expanded(child: TextField(controller: vat, decoration: _dec(tx(c, 'الرَقم الضَريبيّ (TRN)', 'VAT number (TRN)'), icon: Icons.receipt_long_outlined))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: lic, decoration: _dec(tx(c, 'الرُخصة التِجاريّة', 'Trade license')))),
            ]),
            _gap(),
            NetTypeField(net: net, value: type, onChanged: (v) => set(() => type = v)),
            _gap(),
            TextField(controller: notes, maxLines: 2, decoration: _dec(tx(c, 'مُلاحَظات', 'Notes'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: active, title: Text(tx(c, 'نَشِط', 'Active')), onChanged: (v) => set(() => active = v)),
            Text(tx(c, 'يُرسَل إلى Odoo كَشَرِكة خِلال دَقيقَتَين.', 'Sent to Odoo as a company within two minutes.'), style: const TextStyle(color: VC.muted, fontSize: 12)),
          ]),
      onSave: (c) => netSave(c, 'client', row == null ? null : vStr(row['id']), {
            'name': name.text.trim(),
            'name_ar': nameAr.text.trim(),
            'vat': vat.text.trim(),
            'trade_license': lic.text.trim(),
            'notes': notes.text.trim(),
            'type_id': type,
            'is_active': active,
          }));
}

// ---------------------------------------------------------------- branch
Future<String?> netBranchForm(BuildContext context, Net net, {VJson? row, String? clientId, String? pointId}) {
  String? client = row == null ? clientId : vStr(row['client_id']);
  final name = TextEditingController(text: vStr(row?['name']));
  final vat = TextEditingController(text: vStr(row?['vat']));
  final phone = TextEditingController(text: vStr(row?['phone']));
  final email = TextEditingController(text: vStr(row?['email']));
  final contact = TextEditingController(text: vStr(row?['contact_name']));
  final contactPhone = TextEditingController(text: vStr(row?['contact_phone']));
  final address = TextEditingController(text: vStr(row?['address']));
  String? type = row?['type_id'] == null ? null : vStr(row!['type_id']);
  var active = row == null || vBool(row['is_active']);
  final id = row == null ? null : vStr(row['id']);
  // points with unit / floor
  final pts = <String, (TextEditingController, TextEditingController)>{
    for (final p in id == null ? [if (pointId != null) pointId] : (net.pointsOfBranch[id] ?? const <String>[]))
      p: (TextEditingController(text: vStr(net.link['$p|$id']?['unit'])), TextEditingController(text: vStr(net.link['$p|$id']?['floor']))),
  };
  return _form<String>(context,
      title: row == null ? tx(context, 'فَرع جَديد', 'New branch') : tx(context, 'تَعديل الفَرع', 'Edit branch'),
      icon: Icons.storefront_outlined,
      width: 580,
      body: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NetPickField(
              label: tx(c, 'العَميل *', 'Client *'),
              icon: Icons.apartment,
              value: client == null ? '' : net.clientName(client),
              onTap: () async {
                final r = await netPick(c, tx(c, 'العَميل', 'Client'), netClientOptions(net), selected: {client ?? ''});
                if (r != null) set(() => client = r.first);
              },
            ),
            _gap(),
            TextField(controller: name, decoration: _dec(tx(c, 'اسم الفَرع *', 'Branch name *'), icon: Icons.storefront_outlined)),
            _gap(),
            Row(children: [
              Expanded(child: NetTypeField(net: net, value: type, onChanged: (v) => set(() => type = v))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: vat, decoration: _dec(tx(c, 'الرَقم الضَريبيّ', 'VAT number')))),
            ]),
            _gap(),
            Row(children: [
              Expanded(child: TextField(controller: phone, decoration: _dec(tx(c, 'الهاتِف', 'Phone'), icon: Icons.phone_outlined))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: email, decoration: _dec(tx(c, 'البَريد', 'Email'), icon: Icons.mail_outline))),
            ]),
            _gap(),
            Row(children: [
              Expanded(child: TextField(controller: contact, decoration: _dec(tx(c, 'الشَخص المَسؤول', 'Contact person')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: contactPhone, decoration: _dec(tx(c, 'هاتِفه', 'Contact phone')))),
            ]),
            _gap(),
            TextField(controller: address, decoration: _dec(tx(c, 'العُنوان', 'Address'), icon: Icons.location_on_outlined)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(tx(c, 'النِقاط الَّتي يُخدَم فيها (${pts.length})', 'Points it is served at (${pts.length})'), style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: Text(tx(c, 'اختيار النِقاط', 'Choose points')),
                onPressed: () async {
                  final r = await netPick(c, tx(c, 'النِقاط', 'Points'), netPointOptions(net), selected: pts.keys.toSet(), multi: true);
                  if (r == null) return;
                  set(() {
                    pts.removeWhere((k, _) => !r.contains(k));
                    for (final p in r) {
                      pts.putIfAbsent(p, () => (TextEditingController(), TextEditingController()));
                    }
                  });
                },
              ),
            ]),
            if (pts.isEmpty)
              Text(tx(c, 'غَير مَربوط بِأَيّ نُقطة – لا يَظهَر في تَطبيق الفاليه.', 'Not linked to a point – it does not show in the valet app.'),
                  style: const TextStyle(color: VC.warn, fontSize: 12)),
            for (final e in pts.entries)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.place_outlined, size: 18, color: VC.gold),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: Text(net.pointLabel(e.key), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: e.value.$1, decoration: _dec(tx(c, 'الوِحدة', 'Unit')))),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: e.value.$2, decoration: _dec(tx(c, 'الطابِق', 'Floor')))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => set(() => pts.remove(e.key))),
                ]),
              ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: active, title: Text(tx(c, 'نَشِط', 'Active')), onChanged: (v) => set(() => active = v)),
          ]),
      onSave: (c) async {
        if (client == null) {
          vToast(c, tx(c, 'اختَر العَميل.', 'Choose the client.'), error: true);
          return null;
        }
        return netSave(c, 'branch', id, {
          'client_id': client,
          'name': name.text.trim(),
          'type_id': type,
          'vat': vat.text.trim(),
          'phone': phone.text.trim(),
          'email': email.text.trim(),
          'contact_name': contact.text.trim(),
          'contact_phone': contactPhone.text.trim(),
          'address': address.text.trim(),
          'is_active': active,
          'points': [for (final e in pts.entries) {'point': e.key, 'unit': e.value.$1.text.trim(), 'floor': e.value.$2.text.trim()}],
        });
      });
}

// ---------------------------------------------------------------- point
Future<String?> netPointForm(BuildContext context, Net net, {VJson? row, String? areaId}) {
  final id = row == null ? null : vStr(row['id']);
  final name = TextEditingController(text: vStr(row?['name']));
  final code = TextEditingController(text: vStr(row?['code']));
  final address = TextEditingController(text: vStr(row?['address']));
  final lat = TextEditingController(text: vStr(row?['lat']));
  final lng = TextEditingController(text: vStr(row?['lng']));
  String? area = row == null ? areaId : (vStr(row['area_id']).isEmpty ? null : vStr(row['area_id']));
  String? copyFrom;
  var active = row == null || vBool(row['is_active']);
  var branches = {...(id == null ? const <String>[] : (net.branchesOfPoint[id] ?? const <String>[]))};
  return _form<String>(context,
      title: row == null ? tx(context, 'نُقطة جَديدة', 'New point') : tx(context, 'تَعديل النُقطة', 'Edit point'),
      icon: Icons.place_outlined,
      body: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: name, decoration: _dec(tx(c, 'اسم النُقطة *', 'Point name *'), icon: Icons.place_outlined))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextField(controller: code, decoration: _dec(tx(c, 'الكود', 'Code'), hint: tx(c, 'تِلقائيّ', 'Auto')))),
            ]),
            _gap(),
            NetPickField(
              label: tx(c, 'المَنطِقة (الجروب)', 'Area (group)'),
              icon: Icons.map_outlined,
              value: area == null ? '' : net.areaName(area),
              onTap: () async {
                final r = await netPick(c, tx(c, 'المَنطِقة', 'Area'), [
                  NetOption('', tx(c, 'بِلا مَنطِقة', 'No area')),
                  for (final a in net.areas) NetOption(vStr(a['id']), vStr(a['name']), sub: vStr(a['code']), icon: Icons.map_outlined),
                ], selected: {area ?? ''});
                if (r != null) set(() => area = r.first.isEmpty ? null : r.first);
              },
            ),
            _gap(),
            TextField(controller: address, decoration: _dec(tx(c, 'العُنوان', 'Address'), icon: Icons.location_on_outlined)),
            _gap(),
            Row(children: [
              Expanded(child: TextField(controller: lat, decoration: _dec('Latitude', hint: '25.1972'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: lng, decoration: _dec('Longitude', hint: '55.2744'))),
            ]),
            if (row == null) ...[
              _gap(),
              NetPickField(
                label: tx(c, 'نَسخ إعدادات تَطبيق الفاليه مِن نُقطة', 'Copy the valet app settings from a point'),
                icon: Icons.copy_all_outlined,
                value: copyFrom == null ? tx(c, 'الإعدادات الافتِراضيّة', 'Default settings') : net.pointLabel(copyFrom),
                onTap: () async {
                  final r = await netPick(c, tx(c, 'نَسخ مِن', 'Copy from'), [NetOption('', tx(c, 'الإعدادات الافتِراضيّة', 'Default settings')), ...netPointOptions(net)],
                      selected: {copyFrom ?? ''});
                  if (r != null) set(() => copyFrom = r.first.isEmpty ? null : r.first);
                },
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(tx(c, 'الفُروع (${branches.length})', 'Branches (${branches.length})'), style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                icon: const Icon(Icons.add_link, size: 18),
                label: Text(tx(c, 'اختيار الفُروع', 'Choose branches')),
                onPressed: () async {
                  final r = await netPick(c, tx(c, 'الفُروع', 'Branches'), netBranchOptions(net), selected: branches, multi: true);
                  if (r != null) set(() => branches = r);
                },
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in branches)
                InputChip(
                  avatar: const Icon(Icons.storefront_outlined, size: 16),
                  label: Text('${vStr(net.branch[b]?['name'])} · ${net.clientName(net.branch[b]?['client_id'])}'),
                  onDeleted: () => set(() => branches.remove(b)),
                ),
            ]),
            Text(tx(c, 'Visitor وَ VIP مَربوطان بِكُلّ نُقطة تِلقائيّاً.', 'Visitor and VIP are linked to every point automatically.'),
                style: const TextStyle(color: VC.muted, fontSize: 12)),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: active, title: Text(tx(c, 'مَفتوحة', 'Open')), onChanged: (v) => set(() => active = v)),
          ]),
      onSave: (c) => netSave(c, 'point', id, {
            'name': name.text.trim(),
            'code': code.text.trim(),
            'area_id': area,
            'address': address.text.trim(),
            'lat': lat.text.trim(),
            'lng': lng.text.trim(),
            'is_active': active,
            'copy_from': copyFrom,
            'branches': branches.toList(),
          }));
}

// ---------------------------------------------------------------- area
Future<String?> netAreaForm(BuildContext context, Net net, {VJson? row}) {
  final id = row == null ? null : vStr(row['id']);
  final name = TextEditingController(text: vStr(row?['name']));
  final code = TextEditingController(text: vStr(row?['code']));
  var active = row == null || vBool(row['is_active']);
  var points = {for (final p in net.pointsOfArea[id ?? '-'] ?? const <VJson>[]) vStr(p['id'])};
  return _form<String>(context,
      title: row == null ? tx(context, 'مَنطِقة جَديدة', 'New area') : tx(context, 'تَعديل المَنطِقة', 'Edit area'),
      icon: Icons.map_outlined,
      body: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: name, autofocus: row == null, decoration: _dec(tx(c, 'اسم المَنطِقة *', 'Area name *'), hint: 'Downtown'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: code, decoration: _dec(tx(c, 'الكود', 'Code'), hint: 'DTD'))),
            ]),
            const SizedBox(height: 4),
            Text(tx(c, 'الكود يَدخُل في كود النِقاط الجَديدة (AE-DTD-001).', 'The code goes into new point codes (AE-DTD-001).'),
                style: const TextStyle(color: VC.muted, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(tx(c, 'النِقاط (${points.length})', 'Points (${points.length})'), style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: Text(tx(c, 'اختيار النِقاط', 'Choose points')),
                onPressed: () async {
                  final r = await netPick(c, tx(c, 'النِقاط — النُقطة في مَنطِقة واحِدة', 'Points — a point is in one area'), netPointOptions(net),
                      selected: points, multi: true);
                  if (r != null) set(() => points = r);
                },
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in points)
                InputChip(
                  avatar: const Icon(Icons.place_outlined, size: 16),
                  label: Text(net.pointLabel(p)),
                  onDeleted: () => set(() => points.remove(p)),
                ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: active, title: Text(tx(c, 'مَفتوحة', 'Open')), onChanged: (v) => set(() => active = v)),
          ]),
      onSave: (c) => netSave(c, 'area', id, {'name': name.text.trim(), 'code': code.text.trim(), 'is_active': active, 'points': points.toList()}));
}

// ---------------------------------------------------------------- full setup wizard
class _NewBranch {
  final name = TextEditingController();
  final unit = TextEditingController();
  String? type;
}

/// 🪄 إعداد كامِل: العَميل ← الفُروع ← النُقطة ← مُراجَعة (يُحفَظ مَرّة واحِدة).
Future<bool?> netWizard(BuildContext context, Net net, {String? clientId, String? pointId}) {
  var step = 0;
  var newClient = clientId == null;
  String? client = clientId;
  final cName = TextEditingController(), cVat = TextEditingController();
  String? cType;
  final existing = <String>{};
  final fresh = <_NewBranch>[_NewBranch()];
  var pointMode = pointId == null ? 'existing' : 'existing'; // existing | new | none
  String? point = pointId;
  final pName = TextEditingController(), pAddress = TextEditingController();
  String? pArea, pCopy;
  var busy = false;

  String clientLabel(BuildContext c) => newClient ? cName.text.trim() : net.clientName(client);
  List<_NewBranch> freshFilled() => fresh.where((b) => b.name.text.trim().isNotEmpty).toList();

  String? check(BuildContext c, int s) {
    if (s == 0 && (newClient ? cName.text.trim().isEmpty : client == null)) return tx(c, 'اختَر العَميل أَو اكتُب اسمه.', 'Choose the client or type its name.');
    if (s == 1 && existing.isEmpty && freshFilled().isEmpty) return tx(c, 'أَضِف فَرعاً واحِداً عَلى الأَقَلّ.', 'Add at least one branch.');
    if (s == 2 && pointMode == 'existing' && point == null) return tx(c, 'اختَر النُقطة.', 'Choose the point.');
    if (s == 2 && pointMode == 'new' && pName.text.trim().isEmpty) return tx(c, 'اكتُب اسم النُقطة.', 'Type the point name.');
    return null;
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Widget stepClient() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.search), label: Text(tx(ctx, 'عَميل مَوجود', 'Existing client'))),
                ButtonSegment(value: true, icon: const Icon(Icons.add), label: Text(tx(ctx, 'عَميل جَديد', 'New client'))),
              ],
              selected: {newClient},
              onSelectionChanged: (v) => set(() => newClient = v.first),
            ),
            const SizedBox(height: 12),
            if (!newClient)
              NetPickField(
                label: tx(ctx, 'العَميل', 'Client'),
                icon: Icons.apartment,
                value: client == null ? '' : net.clientName(client),
                onTap: () async {
                  final r = await netPick(ctx, tx(ctx, 'العَميل', 'Client'), netClientOptions(net), selected: {client ?? ''});
                  if (r != null) set(() => client = r.first);
                },
              )
            else ...[
              TextField(controller: cName, autofocus: true, decoration: _dec(tx(ctx, 'اسم الشَرِكة *', 'Company name *'), icon: Icons.apartment), onChanged: (_) => set(() {})),
              _gap(),
              Row(children: [
                Expanded(child: TextField(controller: cVat, decoration: _dec(tx(ctx, 'الرَقم الضَريبيّ (TRN)', 'VAT number (TRN)')))),
                const SizedBox(width: 10),
                Expanded(child: NetTypeField(net: net, value: cType, onChanged: (v) => set(() => cType = v))),
              ]),
              Builder(builder: (_) {
                final q = cName.text.trim().toLowerCase();
                if (q.length < 3) return const SizedBox();
                final same = net.clients.where((c) => vStr(c['name']).toLowerCase().contains(q)).take(4).toList();
                if (same.isEmpty) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tx(ctx, 'مَوجود بِاسم مُشابِه:', 'Similar existing:'), style: const TextStyle(color: VC.warn, fontSize: 12)),
                    for (final c in same)
                      ActionChip(
                        avatar: const Icon(Icons.apartment, size: 16),
                        label: Text(vStr(c['name'])),
                        onPressed: () => set(() {
                          newClient = false;
                          client = vStr(c['id']);
                        }),
                      ),
                  ]),
                );
              }),
            ],
          ]);

      Widget stepBranches() {
        final mine = newClient ? const <VJson>[] : (net.branchesOfClient[client] ?? const <VJson>[]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mine.isNotEmpty) ...[
            Text(tx(ctx, 'فُروع ${clientLabel(ctx)} المَوجودة — اختَر ما يُخدَم في النُقطة', 'Existing branches of ${clientLabel(ctx)} — tick the ones served at the point'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final b in mine)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: existing.contains(vStr(b['id'])),
                title: Text(vStr(b['name'])),
                subtitle: Text((net.pointsOfBranch[vStr(b['id'])] ?? const []).map((p) => vStr(net.point[p]?['code'])).join(', ')),
                onChanged: (v) => set(() => v == true ? existing.add(vStr(b['id'])) : existing.remove(vStr(b['id']))),
              ),
            const Divider(),
          ],
          Text(tx(ctx, 'فُروع جَديدة', 'New branches'), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final b in fresh)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: b.name, decoration: _dec(tx(ctx, 'اسم الفَرع', 'Branch name'), icon: Icons.storefront_outlined))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: NetTypeField(net: net, value: b.type, onChanged: (v) => set(() => b.type = v))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: b.unit, decoration: _dec(tx(ctx, 'الوِحدة', 'Unit')))),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: fresh.length == 1 ? null : () => set(() => fresh.remove(b))),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => set(() => fresh.add(_NewBranch())), icon: const Icon(Icons.add), label: Text(tx(ctx, 'فَرع آخَر', 'Another branch'))),
          ),
        ]);
      }

      Widget stepPoint() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'existing', icon: const Icon(Icons.search), label: Text(tx(ctx, 'نُقطة مَوجودة', 'Existing point'))),
                ButtonSegment(value: 'new', icon: const Icon(Icons.add_location_alt_outlined), label: Text(tx(ctx, 'نُقطة جَديدة', 'New point'))),
                ButtonSegment(value: 'none', icon: const Icon(Icons.do_not_disturb_alt), label: Text(tx(ctx, 'لاحِقاً', 'Later'))),
              ],
              selected: {pointMode},
              onSelectionChanged: (v) => set(() => pointMode = v.first),
            ),
            const SizedBox(height: 12),
            if (pointMode == 'existing')
              NetPickField(
                label: tx(ctx, 'النُقطة', 'Point'),
                icon: Icons.place_outlined,
                value: point == null ? '' : net.pointLabel(point),
                onTap: () async {
                  final r = await netPick(ctx, tx(ctx, 'النُقطة', 'Point'), netPointOptions(net), selected: {point ?? ''});
                  if (r != null) set(() => point = r.first);
                },
              ),
            if (pointMode == 'new') ...[
              TextField(controller: pName, decoration: _dec(tx(ctx, 'اسم النُقطة *', 'Point name *'), icon: Icons.place_outlined), onChanged: (_) => set(() {})),
              _gap(),
              NetPickField(
                label: tx(ctx, 'المَنطِقة (الجروب)', 'Area (group)'),
                icon: Icons.map_outlined,
                value: pArea == null ? '' : net.areaName(pArea),
                onTap: () async {
                  final r = await netPick(ctx, tx(ctx, 'المَنطِقة', 'Area'),
                      [for (final a in net.areas) NetOption(vStr(a['id']), vStr(a['name']), sub: vStr(a['code']), icon: Icons.map_outlined)],
                      selected: {pArea ?? ''});
                  if (r != null) set(() => pArea = r.first);
                },
              ),
              _gap(),
              TextField(controller: pAddress, decoration: _dec(tx(ctx, 'العُنوان', 'Address'), icon: Icons.location_on_outlined)),
              _gap(),
              NetPickField(
                label: tx(ctx, 'نَسخ إعدادات تَطبيق الفاليه مِن', 'Copy the valet app settings from'),
                icon: Icons.copy_all_outlined,
                value: pCopy == null ? tx(ctx, 'الإعدادات الافتِراضيّة', 'Default settings') : net.pointLabel(pCopy),
                onTap: () async {
                  final r = await netPick(ctx, tx(ctx, 'نَسخ مِن', 'Copy from'), [NetOption('', tx(ctx, 'الإعدادات الافتِراضيّة', 'Default settings')), ...netPointOptions(net)],
                      selected: {pCopy ?? ''});
                  if (r != null) set(() => pCopy = r.first.isEmpty ? null : r.first);
                },
              ),
            ],
            if (pointMode == 'none')
              Text(tx(ctx, 'الفُروع تُحفَظ بِدون نُقطة — لا تَظهَر في تَطبيق الفاليه حَتّى تُربَط.', 'The branches are saved without a point — they do not show in the valet app until linked.'),
                  style: const TextStyle(color: VC.warn)),
          ]);

      Widget stepReview() {
        final pLabel = pointMode == 'existing'
            ? net.pointLabel(point)
            : pointMode == 'new'
                ? '${pName.text.trim()}  (${tx(ctx, 'جَديدة', 'new')}${pArea == null ? '' : ' · ${net.areaName(pArea)}'})'
                : tx(ctx, 'بِدون نُقطة', 'No point');
        Widget line(IconData i, String t, {double indent = 0, Color? color, String? tag}) => Padding(
              padding: EdgeInsetsDirectional.only(start: indent, top: 6),
              child: Row(children: [
                Icon(i, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
                if (tag != null) VPill(tag, color: VC.ok),
              ]),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          line(Icons.apartment, clientLabel(ctx), color: netColor('client'), tag: newClient ? tx(ctx, 'جَديد', 'New') : null),
          line(Icons.place_outlined, pLabel, indent: 22, color: netColor('point'), tag: pointMode == 'new' ? tx(ctx, 'جَديدة', 'New') : null),
          for (final b in existing) line(Icons.storefront_outlined, vStr(net.branch[b]?['name']), indent: 44, color: netColor('branch')),
          for (final b in freshFilled())
            line(Icons.storefront_outlined, '${b.name.text.trim()}${b.type == null ? '' : ' · ${net.typeName(ctx, b.type)}'}${b.unit.text.trim().isEmpty ? '' : ' · ${b.unit.text.trim()}'}',
                indent: 44, color: netColor('branch'), tag: tx(ctx, 'جَديد', 'New')),
          const SizedBox(height: 14),
          Text(tx(ctx, 'يُحفَظ كُلّه مَرّة واحِدة وَيُرسَل إلى Odoo خِلال دَقيقَتَين.', 'Everything is saved at once and sent to Odoo within two minutes.'),
              style: const TextStyle(color: VC.muted, fontSize: 12)),
        ]);
      }

      final titles = [tx(ctx, 'العَميل', 'Client'), tx(ctx, 'الفُروع', 'Branches'), tx(ctx, 'النُقطة', 'Point'), tx(ctx, 'مُراجَعة', 'Review')];
      final body = [stepClient, stepBranches, stepPoint, stepReview][step]();

      Future<void> save() async {
        set(() => busy = true);
        final r = await vGuard(
            ctx,
            () => ValetAdmin.I.call('vva_network_setup', {
                  'p_data': {
                    'client': newClient ? {'name': cName.text.trim(), 'vat': cVat.text.trim(), 'type_id': cType, 'force': true} : {'id': client},
                    'branches': [
                      for (final b in existing) {'id': b},
                      for (final b in freshFilled()) {'name': b.name.text.trim(), 'type_id': b.type, 'unit': b.unit.text.trim()},
                    ],
                    'point': pointMode == 'existing'
                        ? {'id': point}
                        : pointMode == 'new'
                            ? {'name': pName.text.trim(), 'area_id': pArea, 'address': pAddress.text.trim(), 'copy_from': pCopy}
                            : null,
                  }
                }),
            ok: tx(ctx, 'تَمّ الحِفظ — يُرسَل إلى Odoo خِلال دَقيقَتَين.', 'Saved — sent to Odoo within two minutes.'));
        if (!ctx.mounted) return;
        set(() => busy = false);
        if (r != null) Navigator.pop(ctx, true);
      }

      return AlertDialog(
        title: Row(children: [const Icon(Icons.auto_awesome_outlined), const SizedBox(width: 8), Text(tx(ctx, 'إعداد كامِل', 'Full setup'))]),
        content: SizedBox(
          width: 640,
          height: 470,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const Expanded(child: Divider(indent: 6, endIndent: 6)),
                CircleAvatar(
                  radius: 13,
                  backgroundColor: i <= step ? VC.gold : VC.muted.withValues(alpha: 0.25),
                  child: i < step ? const Icon(Icons.check, size: 15, color: Colors.white) : Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 6),
                Text(titles[i], style: TextStyle(fontWeight: i == step ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
              ],
            ]),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: body)),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          if (step > 0) OutlinedButton(onPressed: busy ? null : () => set(() => step--), child: Text(tx(ctx, 'رُجوع', 'Back'))),
          if (step < 3)
            FilledButton(
              onPressed: () {
                final e = check(ctx, step);
                if (e != null) return vToast(ctx, e, error: true);
                set(() => step++);
              },
              child: Text(tx(ctx, 'التالي', 'Next')),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : save,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(tx(ctx, 'حِفظ الكُلّ', 'Save all')),
            ),
        ],
      );
    }),
  );
}

// ---------------------------------------------------------------- Excel import
const _importCols = ['client', 'client_vat', 'branch', 'branch_vat', 'type', 'point_code', 'area', 'unit', 'floor'];

Future<void> netImportTemplate(BuildContext context) => vExport(context, 'network_import_template', [
      ExcelSheet(name: 'Network', headers: _importCols, rows: const [
        ['Chaplin LLC', '100123456700003', 'Chaplin Restaurant', '', 'Restaurant', 'AE-DTD-007', 'Downtown', 'G12', 'Ground'],
        ['Chaplin LLC', '100123456700003', 'Chaplin Lounge', '', 'Café', 'AE-DTD-007', 'Downtown', '', '1'],
      ]),
    ]);

List<Map<String, String>> _readRows(PlatformFile f) {
  final bytes = f.bytes;
  if (bytes == null) return [];
  List<List<String>> grid;
  if ((f.extension ?? '').toLowerCase() == 'csv') {
    grid = const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true)).where((l) => l.trim().isNotEmpty).map((l) => l.split(',').map((e) => e.trim()).toList()).toList();
  } else {
    final book = xl.Excel.decodeBytes(bytes);
    final ws = book.sheets['Network'] ?? (book.sheets.isEmpty ? null : book.sheets.values.first);
    if (ws == null) return [];
    grid = [for (final r in ws.rows) [for (final c in r) c?.value?.toString().trim() ?? '']];
  }
  if (grid.isEmpty) return [];
  final head = grid.first.map((h) => h.toLowerCase().replaceAll(' ', '_')).toList();
  return [
    for (final r in grid.skip(1))
      if (r.any((c) => c.isNotEmpty)) {for (var i = 0; i < head.length && i < r.length; i++) if (_importCols.contains(head[i])) head[i]: r[i]},
  ];
}

String _acts(BuildContext c, dynamic v) {
  final l = (v is List ? v : const []).map((e) => '$e').toList();
  return l.isEmpty ? tx(c, 'مَوجود — لا تَغيير', 'Exists — no change') : l.join(', ');
}

/// 📥 استيراد Excel: مُعايَنة لِكُلّ سَطر ثُمّ حِفظ الكُلّ مَرّة واحِدة.
Future<bool> netImport(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
  if (picked == null || picked.files.isEmpty || !context.mounted) return false;
  final rows = _readRows(picked.files.first);
  if (rows.isEmpty) {
    vToast(context, tx(context, 'المَلَف فارِغ أَو بِدون أَعمِدة القالَب.', 'The file is empty or has no template columns.'), error: true);
    return false;
  }
  final pre = await vGuard(context, () => ValetAdmin.I.call('vva_network_import', {'p_rows': rows, 'p_commit': false}));
  if (pre == null || !context.mounted) return false;
  final sum = vMap(pre['summary']);
  final res = vList(pre['rows']);
  final errors = vNum(sum['errors']).toInt();
  var busy = false;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return AlertDialog(
        title: Text(tx(ctx, 'مُعايَنة الاستيراد — ${rows.length} سَطر', 'Import preview — ${rows.length} rows')),
        content: SizedBox(
          width: 760,
          height: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              VPill(tx(ctx, 'عُمَلاء جُدُد ${sum['clients']}', 'New clients ${sum['clients']}'), color: netColor('client'), icon: Icons.apartment),
              VPill(tx(ctx, 'فُروع جَديدة ${sum['branches']}', 'New branches ${sum['branches']}'), color: netColor('branch'), icon: Icons.storefront_outlined),
              VPill(tx(ctx, 'رَبط بِنُقطة ${sum['links']}', 'Point links ${sum['links']}'), color: netColor('point'), icon: Icons.link),
              VPill(tx(ctx, 'مَناطِق جَديدة ${sum['areas']}', 'New areas ${sum['areas']}'), color: netColor('area'), icon: Icons.map_outlined),
              if (errors > 0) VPill(tx(ctx, 'أَخطاء $errors', 'Errors $errors'), color: VC.bad, icon: Icons.error_outline),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: VTable(columns: [
                  const DataColumn(label: Text('#'), numeric: true),
                  DataColumn(label: Text(tx(ctx, 'العَميل', 'Client'))),
                  DataColumn(label: Text(tx(ctx, 'الفَرع', 'Branch'))),
                  DataColumn(label: Text(tx(ctx, 'النُقطة', 'Point'))),
                  DataColumn(label: Text(tx(ctx, 'ما سَيَحدُث', 'What happens'))),
                ], rows: [
                  for (var i = 0; i < res.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(rows[i]['client'] ?? '')),
                      DataCell(Text(rows[i]['branch'] ?? '')),
                      DataCell(Text(rows[i]['point_code'] ?? '')),
                      DataCell(res[i]['error'] != null
                          ? Text(vStr(res[i]['error']), style: const TextStyle(color: VC.bad))
                          : Text(_acts(ctx, res[i]['actions']))),
                    ]),
                ]),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: Text(errors > 0 ? tx(ctx, 'صَحِّح الأَخطاء أَوَّلاً', 'Fix the errors first') : tx(ctx, 'استيراد', 'Import')),
            onPressed: busy || errors > 0
                ? null
                : () async {
                    set(() => busy = true);
                    final r = await vGuard(ctx, () => ValetAdmin.I.call('vva_network_import', {'p_rows': rows, 'p_commit': true}),
                        ok: tx(ctx, 'تَمّ الاستيراد — يُرسَل إلى Odoo خِلال دَقائِق.', 'Imported — sent to Odoo within minutes.'));
                    if (!ctx.mounted) return;
                    set(() => busy = false);
                    if (r != null) Navigator.pop(ctx, true);
                  },
          ),
        ],
      );
    }),
  );
  return done == true;
}
