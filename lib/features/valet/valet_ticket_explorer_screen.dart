import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/services/file_save_helper.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🧾 مُستَكشِف بَيانات التَذاكِر — كُلّ أَعمِدة التَذكَرة لِكُلّ النِقاط أَو بَعضها، بِفَترة، مَع اختيار الأَعمِدة
/// وَتَرتيبها، عَرض بِصَفَحات وَتَنزيل Excel / CSV لِكُلّ الصُفوف (SQL 280: vva_ticket_explorer).
class ValetTicketExplorerScreen extends StatelessWidget {
  const ValetTicketExplorerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tx(context, 'مُستَكشِف بَيانات التَذاكِر', 'Ticket data explorer'))),
        body: const ValetGate(perm: ValetAdmin.permReports, child: _Explorer()),
      );
}

// ---------------------------------------------------------------- column catalog
enum _K { text, money, int, dur, time, date, bool }

class _Col {
  const _Col(this.group, this.en, this.ar, [this.kind = _K.text]);
  final String group;
  final String en;
  final String ar;
  final _K kind;
}

const _groups = <String, (String, String)>{
  'basic': ('Basic', 'أَساسيّ'),
  'money': ('Money', 'المال'),
  'times': ('Times', 'الأَوقات'),
  'staff': ('Staff and shifts', 'المُوَظَّفون وَالوَرديّات'),
  'car': ('Car and parking', 'السَيّارة وَالرَكن'),
  'customer': ('Customer and client', 'العَميل'),
  'keyrack': ('Key rack', 'الكي راك'),
  'odoo': ('Accounting / Odoo', 'المُحاسَبة / Odoo'),
  'other': ('Other', 'أُخرى'),
};

const _cols = <String, _Col>{
  // basic
  'ticket_code': _Col('basic', 'Ticket no.', 'رَقم التَذكَرة'),
  'point_code': _Col('basic', 'Point code', 'كود النُقطة'),
  'point_name': _Col('basic', 'Point', 'النُقطة'),
  'site_name': _Col('basic', 'Site', 'المَوقِع'),
  'area_name': _Col('basic', 'Area', 'المَنطِقة'),
  'client_name': _Col('customer', 'Client (company)', 'العَميل (الشَركة)'),
  'branch_name': _Col('customer', 'Branch', 'الفَرع'),
  'ticket_status': _Col('basic', 'Status', 'الحالة'),
  'ticket_type': _Col('basic', 'Ticket type', 'نَوع التَذكَرة'),
  'ticket_name': _Col('basic', 'Ticket name', 'اسم التَذكَرة'),
  'ticket_mode': _Col('basic', 'Mode', 'الوَضع'),
  'is_vip': _Col('basic', 'VIP', 'VIP', _K.bool),
  'entry_date': _Col('basic', 'Entry date', 'تاريخ الدُخول', _K.date),
  'exit_date': _Col('basic', 'Exit date', 'تاريخ الخُروج', _K.date),
  'business_date': _Col('basic', 'Business date', 'يَوم العَمَل', _K.date),
  'void_reason': _Col('basic', 'Void reason', 'سَبَب الإلغاء'),
  'void_ticket_number': _Col('basic', 'Void ticket no.', 'رَقم المُلغاة'),
  'offline_entry': _Col('basic', 'Entered offline', 'أُدخِلَت بِلا إنتَرنِت', _K.bool),
  'manual_cars': _Col('basic', 'Paper ticket cars', 'سَيّارات التَذكَرة الوَرَقيّة', _K.int),
  'notes': _Col('basic', 'Notes', 'مُلاحَظات'),
  'id': _Col('other', 'Ticket id', 'مُعَرِّف التَذكَرة'),
  // money
  'amount_total': _Col('money', 'Amount (total)', 'المَبلَغ الكُلّيّ', _K.money),
  'ticket_price': _Col('money', 'Ticket price', 'سِعر التَذكَرة', _K.money),
  'vat_price': _Col('money', 'VAT', 'الضَريبة', _K.money),
  'total_price': _Col('money', 'Total price', 'السِعر الإجماليّ', _K.money),
  'payment_label': _Col('money', 'Payment', 'الدَفع'),
  'payment_mode': _Col('money', 'Payment mode (raw)', 'طَريقة الدَفع (خام)'),
  'payment_mode_prev': _Col('money', 'Previous payment mode', 'طَريقة الدَفع السابِقة'),
  'cash_amount': _Col('money', 'Cash part', 'نَصيب الكاش', _K.money),
  'card_amount': _Col('money', 'Card part', 'نَصيب الكارت', _K.money),
  'cash_part': _Col('money', 'Split: cash (raw)', 'مُقَسَّم: كاش (خام)', _K.money),
  'card_part': _Col('money', 'Split: card (raw)', 'مُقَسَّم: كارت (خام)', _K.money),
  'card_ref': _Col('money', 'Card approval no.', 'رَقم مُوافَقة الكارت'),
  'tips': _Col('money', 'Tips', 'الإكراميّة', _K.money),
  'total_w_tips': _Col('money', 'Total with tips', 'الإجماليّ مَع الإكراميّة', _K.money),
  'paid_amount': _Col('money', 'Paid amount', 'المَدفوع', _K.money),
  'remaining_amount': _Col('money', 'Remaining', 'المُتَبَقّي', _K.money),
  'lost_card': _Col('money', 'Lost ticket fee', 'رُسوم التَذكَرة المَفقودة', _K.money),
  'total_w_lostcard': _Col('money', 'Total with lost ticket', 'الإجماليّ مَع المَفقودة', _K.money),
  'lost_ticket_enabled': _Col('money', 'Lost ticket', 'تَذكَرة مَفقودة', _K.bool),
  'amount_lost_ticket': _Col('money', 'Lost ticket amount', 'مَبلَغ المَفقودة', _K.money),
  'over_night_fee': _Col('money', 'Overnight fee', 'رُسوم المَبيت', _K.money),
  'over_night_nights': _Col('money', 'Overnight nights', 'لَيالي المَبيت', _K.int),
  'discount_type': _Col('money', 'Discount type', 'نَوع الخَصم'),
  'discount_amount': _Col('money', 'Discount', 'الخَصم', _K.money),
  'discount_ticket_type': _Col('money', 'Discount ticket type', 'نَوع تَذكَرة الخَصم'),
  'voucher_code': _Col('money', 'Voucher', 'القَسيمة'),
  'paid_later': _Col('money', 'Paid later', 'مَدفوع لاحِقاً', _K.money),
  'credit_notes': _Col('money', 'Credit notes', 'إشعارات دائِنة', _K.money),
  'prepaid_hold': _Col('money', 'Prepaid, car waiting', 'مَدفوعة مُقَدَّماً', _K.bool),
  'paid_at': _Col('money', 'Paid at', 'وَقت الدَفع', _K.time),
  'grace_until': _Col('money', 'Grace until', 'السَماح حَتّى', _K.time),
  // times
  'entry_time': _Col('times', 'Entry', 'الدُخول', _K.time),
  'exit_time': _Col('times', 'Exit', 'الخُروج', _K.time),
  'check_out_time': _Col('times', 'Finished', 'الإنهاء', _K.time),
  'stay_minutes': _Col('times', 'Stay (min)', 'مُدّة الوُقوف (د)', _K.int),
  'driver_in_time': _Col('times', 'Driver in', 'استِلام السائِق', _K.time),
  'parking_time': _Col('times', 'Parked', 'الرَكن', _K.time),
  'park_seconds': _Col('times', 'Time to park', 'وَقت الرَكن', _K.dur),
  'car_request_time': _Col('times', 'Requested', 'الطَلَب', _K.time),
  'request_source': _Col('times', 'Request from', 'مَصدَر الطَلَب'),
  'received_recar_time': _Col('times', 'Request seen', 'استِلام الطَلَب', _K.time),
  'driver_out_time': _Col('times', 'Driver out', 'إخراج السائِق', _K.time),
  'car_arrival_time': _Col('times', 'Handed over', 'التَسليم', _K.time),
  'wait_seconds': _Col('times', 'Customer wait', 'انتِظار العَميل', _K.dur),
  'repark_time': _Col('times', 'Reparked', 'إعادة الرَكن', _K.time),
  'estimated_time': _Col('times', 'ETA (min)', 'الوَقت المُتَوَقَّع (د)'),
  'estimated_ready': _Col('times', 'Ready', 'جاهِزة'),
  'car_request_status': _Col('times', 'Request status', 'حالة الطَلَب'),
  'car_request_notes': _Col('times', 'Request notes', 'مُلاحَظات الطَلَب'),
  'car_request': _Col('times', 'Request flag', 'عَلامة الطَلَب', _K.bool),
  'received_recar': _Col('times', 'Request seen flag', 'عَلامة استِلام الطَلَب'),
  'created_at': _Col('times', 'Created', 'أُنشِئَت', _K.time),
  'updated_at': _Col('times', 'Updated', 'آخِر تَعديل', _K.time),
  // staff
  'opened_by_name': _Col('staff', 'Opened by', 'فَتَحَها'),
  'opened_by_code': _Col('staff', 'Opened by (code)', 'كود مَن فَتَحَها'),
  'received_by_name': _Col('staff', 'Received by', 'استَلَمها'),
  'delivered_by_name': _Col('staff', 'Delivered by', 'سَلَّمها'),
  'shift_code': _Col('staff', 'Opening shift', 'وَرديّة الفَتح'),
  'close_shift_code': _Col('staff', 'Closing shift', 'وَرديّة الإغلاق'),
  'sale_no': _Col('staff', 'Sale no.', 'رَقم البَيع'),
  'sale_no_prev': _Col('staff', 'Previous sale no.', 'رَقم البَيع السابِق'),
  'sale_series': _Col('staff', 'Sale series', 'سِلسِلة البَيع'),
  'sale_seq': _Col('staff', 'Sale sequence', 'تَسَلسُل البَيع', _K.int),
  // car
  'plate_number': _Col('car', 'Plate', 'اللَوحة'),
  'vehicle_country': _Col('car', 'Plate country', 'دَولة اللَوحة'),
  'vehicle_type': _Col('car', 'Car', 'السَيّارة'),
  'selected_color': _Col('car', 'Colour', 'اللَون'),
  'selected_damages': _Col('car', 'Damages', 'الأَضرار'),
  'has_photo': _Col('car', 'Has photo', 'بِها صورة', _K.bool),
  'parking_area': _Col('car', 'Parking area', 'مَنطِقة الرَكن'),
  'parking_number': _Col('car', 'Parking no.', 'رَقم الرَكن'),
  'slot_number': _Col('car', 'Board slot', 'خانة اللَوحة', _K.int),
  // customer
  'customer_name': _Col('customer', 'Customer', 'العَميل'),
  'member_card': _Col('customer', 'Member card', 'بِطاقة العُضويّة'),
  'qr_card': _Col('customer', 'QR card', 'بِطاقة QR'),
  'hotel_category': _Col('customer', 'Hotel category', 'فِئة الفُندُق'),
  'apartment_number': _Col('customer', 'Apartment', 'الشُقّة'),
  'staff_visitors': _Col('customer', 'Staff / visitor', 'مُوَظَّف / زائِر'),
  'validated_at': _Col('customer', 'Validated at', 'وَقت التَحَقُّق', _K.time),
  'validated_by_name': _Col('customer', 'Validated by (client)', 'تَحَقَّق (العَميل)'),
  'validated_via': _Col('customer', 'Validated via', 'طَريقة التَحَقُّق'),
  'validated_staff_name': _Col('customer', 'Validated by (staff)', 'تَحَقَّق (المُوَظَّف)'),
  'stamp_ticket': _Col('customer', 'Stamp ticket', 'تَذكَرة خِتم', _K.bool),
  'stamp_notes': _Col('customer', 'Stamp notes', 'مُلاحَظات الخِتم'),
  'stamp_responsible': _Col('customer', 'Stamp by', 'المَسؤول عَن الخِتم'),
  'customer_approved': _Col('customer', 'Customer approved', 'مُوافَقة العَميل', _K.bool),
  'before_customer': _Col('customer', 'Customer before change', 'العَميل قَبل التَغيير'),
  'before_ticket_type': _Col('customer', 'Type before change', 'النَوع قَبل التَغيير'),
  'before_ticket_name': _Col('customer', 'Name before change', 'الاسم قَبل التَغيير'),
  'before_ticket_mode': _Col('customer', 'Mode before change', 'الوَضع قَبل التَغيير'),
  // key rack
  'key_rack_status': _Col('keyrack', 'Key status', 'حالة المِفتاح'),
  'key_rack_received_time': _Col('keyrack', 'Key received', 'استِلام المِفتاح', _K.time),
  'key_rack_request': _Col('keyrack', 'Key ordered', 'طَلَب المِفتاح'),
  'key_rack_request_time': _Col('keyrack', 'Key requested', 'وَقت طَلَب المِفتاح', _K.time),
  'key_rack_finish_time': _Col('keyrack', 'Key out', 'إخراج المِفتاح', _K.time),
  'key_out_seconds': _Col('keyrack', 'Key out time', 'مُدّة إخراج المِفتاح', _K.dur),
  'key_rack_operator_name': _Col('keyrack', 'Key controller', 'مُوَظَّف المَفاتيح'),
  'key_rack_shift_code': _Col('keyrack', 'Key rack shift', 'وَرديّة الكي راك'),
  // odoo
  'odoo_invoice': _Col('odoo', 'Odoo invoice', 'فاتورة Odoo'),
  'odoo_status': _Col('odoo', 'Odoo status', 'حالة Odoo'),
};

const _presets = <String, (String, String, List<String>)>{
  'sales': ('Sales', 'المَبيعات', [
    'ticket_code', 'area_name', 'point_name', 'client_name', 'branch_name', 'exit_time', 'plate_number', 'ticket_name', 'payment_label', 'amount_total', 'vat_price', 'cash_amount',
    'card_amount', 'tips', 'discount_amount', 'opened_by_name', 'delivered_by_name',
  ]),
  'ops': ('Operations', 'التَشغيل', [
    'ticket_code', 'point_name', 'plate_number', 'entry_time', 'parking_time', 'park_seconds', 'car_request_time', 'request_source',
    'car_arrival_time', 'wait_seconds', 'exit_time', 'stay_minutes', 'parking_area', 'received_by_name', 'delivered_by_name',
  ]),
  'keyrack': ('Key rack', 'الكي راك', [
    'ticket_code', 'point_name', 'plate_number', 'key_rack_received_time', 'key_rack_request_time', 'key_rack_finish_time', 'key_out_seconds',
    'key_rack_status', 'key_rack_operator_name', 'key_rack_shift_code',
  ]),
  'odoo': ('Accounting / Odoo', 'المُحاسَبة / Odoo', [
    'ticket_code', 'sale_no', 'area_name', 'point_code', 'point_name', 'client_name', 'branch_name', 'exit_date', 'ticket_name', 'customer_name', 'payment_label', 'ticket_price',
    'vat_price', 'amount_total', 'cash_amount', 'card_amount', 'card_ref', 'paid_later', 'credit_notes', 'close_shift_code', 'odoo_invoice',
    'odoo_status',
  ]),
};

const _prefsKey = 'valet_explorer_v1';

// ---------------------------------------------------------------- screen
class _Explorer extends StatefulWidget {
  const _Explorer();

  @override
  State<_Explorer> createState() => _ExplorerState();
}

class _ExplorerState extends State<_Explorer> {
  late DateTime _from;
  late DateTime _to;
  final Set<String> _points = {};
  VScope _scope = VScope.all;
  List<VJson> _allPoints = [];
  String _basis = 'exit';
  String _status = 'closed';
  String _payment = '';
  final _q = TextEditingController();
  List<String> _columns = List.of(_presets['sales']!.$3);
  List<String> _server = [];
  Map<String, List<String>> _views = {};
  String? _sort;
  bool _desc = true;
  int _page = 0;
  static const _per = 100;

  List<VJson> _rows = [];
  int _total = 0;
  VJson _totals = {};
  bool _busy = false;
  String? _exporting;
  Object? _err;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month, n.day);
    VPoints.get().then((p) => mounted ? setState(() => _allPoints = p) : null).catchError((_) => null);
    _restore().whenComplete(_load);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- saved state
  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_prefsKey);
      if (s == null) return;
      final j = jsonDecode(s) as Map<String, dynamic>;
      final cols = (j['columns'] as List?)?.map((e) => '$e').toList();
      if (cols != null && cols.isNotEmpty) _columns = cols;
      _views = {for (final e in ((j['views'] as Map?) ?? {}).entries) '${e.key}': (e.value as List).map((x) => '$x').toList()};
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode({'columns': _columns, 'views': _views}));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- data
  Map<String, dynamic> get _options => {
        'basis': _basis,
        'status': _status,
        if (_payment.isNotEmpty) 'payment': _payment,
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
        if (!_scope.isAll) 'scope': _scope.json,
        if (_sort != null) 'sort': _sort,
        'desc': _desc,
      };

  Future<VJson> _fetch(List<String> cols, int offset, int limit) => ValetAdmin.I.call('vva_ticket_explorer', {
        'p_from': VF.iso(_from),
        'p_to': VF.iso(_to),
        'p_points': _points.isEmpty ? null : _points.toList(),
        'p_options': _options,
        'p_columns': cols,
        'p_offset': offset,
        'p_limit': limit,
      });

  Future<void> _load({bool keepPage = false}) async {
    if (!keepPage) _page = 0;
    setState(() => _busy = true);
    try {
      final d = await _fetch(_columns, _page * _per, _per);
      if (!mounted) return;
      setState(() {
        _rows = vList(d['rows']);
        _total = vNum(d['total']).toInt();
        _totals = vMap(d['totals']);
        final sc = (d['columns'] is List ? d['columns'] as List : const []).map((e) => '$e').toList();
        if (sc.isNotEmpty) _server = sc;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> get _available {
    final keys = <String>{..._cols.keys, ..._server};
    if (_server.isNotEmpty) keys.removeWhere((k) => !_server.contains(k));
    return keys.toList();
  }

  String _label(String k) {
    final c = _cols[k];
    if (c != null) return tx(context, c.ar, c.en);
    return k.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  _K _kind(String k) => _cols[k]?.kind ?? _K.text;

  String _fmt(String k, dynamic v) {
    if (v == null) return '';
    switch (_kind(k)) {
      case _K.money:
        return VF.money(vNum(v));
      case _K.int:
        return VF.n(vNum(v));
      case _K.dur:
        return _dur(vNum(v).toInt());
      case _K.time:
        return VF.dt(DateTime.tryParse('$v')?.toLocal());
      case _K.date:
        return VF.date(DateTime.tryParse('$v'));
      case _K.bool:
        return v == true ? tx(context, 'نَعَم', 'Yes') : (v == false ? tx(context, 'لا', 'No') : '$v');
      case _K.text:
        if (v is List) return v.join(', ');
        return '$v';
    }
  }

  /// قيمة لِلـ Excel: أَرقام كَأَرقام، أَوقات بِتَوقيت دُبَي.
  dynamic _cell(String k, dynamic v) {
    if (v == null) return '';
    switch (_kind(k)) {
      case _K.money:
      case _K.int:
        return vNum(v);
      case _K.dur:
        return _dur(vNum(v).toInt());
      case _K.time:
      case _K.date:
      case _K.bool:
        return _fmt(k, v);
      case _K.text:
        return v is List ? v.join(', ') : '$v';
    }
  }

  static String _dur(int v) {
    if (v < 60) return '${v}s';
    final m = v ~/ 60;
    if (m < 60) return '${m}m ${(v % 60).toString().padLeft(2, '0')}s';
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  // ---------------------------------------------------------------- export
  Future<void> _export(String format) async {
    if (_total == 0) return;
    if (_total > 50000) {
      vToast(context, tx(context, 'أَكثَر مِن 50,000 صَفّ — ضَيِّق الفَترة أَو النِقاط.', 'More than 50,000 rows. Narrow the period or the points.'), error: true);
      return;
    }
    setState(() => _exporting = '0 / $_total');
    try {
      final all = <VJson>[];
      while (all.length < _total) {
        final d = await _fetch(_columns, all.length, 5000);
        final part = vList(d['rows']);
        if (part.isEmpty) break;
        all.addAll(part);
        if (mounted) setState(() => _exporting = '${all.length} / $_total');
      }
      final name = 'valet_tickets_${VF.iso(_from)}_${VF.iso(_to)}';
      final headers = [for (final c in _columns) _label(c)];
      if (format == 'xlsx') {
        if (!mounted) return;
        await vExport(context, '$name.xlsx', [
          ExcelSheet(name: 'Tickets', headers: headers, rows: [for (final r in all) [for (final c in _columns) _cell(c, r[c])]]),
          ExcelSheet(name: 'Filters', headers: ['Filter', 'Value'], rows: [
            ['From', VF.iso(_from)],
            ['To', VF.iso(_to)],
            ['Points', _points.isEmpty ? 'All' : _pointNames().join(', ')],
            ['Scope', _scope.isAll ? 'All' : '${_scope.kind}: ${_scope.label}'],
            ['Date basis', _basis],
            ['Status', _status],
            ['Payment', _payment.isEmpty ? 'Any' : _payment],
            ['Search', _q.text],
            ['Rows', all.length],
          ]),
        ]);
      } else {
        String esc(String s) => s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
        final b = StringBuffer('﻿')..writeln(headers.map(esc).join(','));
        for (final r in all) {
          b.writeln([for (final c in _columns) esc('${_cell(c, r[c])}')].join(','));
        }
        if (!mounted) return;
        final msg = await FileSaveHelper.save(bytes: Uint8List.fromList(utf8.encode(b.toString())), filename: '$name.csv', isAr: AppStrings.of(context).isAr);
        if (mounted && msg.isNotEmpty) vToast(context, msg);
      }
      ValetAdmin.I.call('vva_ticket_explorer_log', {
        'p_rows': all.length,
        'p_columns': _columns,
        'p_format': format,
        'p_filters': {'from': VF.iso(_from), 'to': VF.iso(_to), 'points': _points.toList(), ..._options},
      }).catchError((_) => <String, dynamic>{});
    } catch (e) {
      if (mounted) vToast(context, vErr(context, e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  List<String> _pointNames() => [
        for (final p in _allPoints)
          if (_points.contains(vStr(p['id']))) '${p['code']} ${p['name']}'
      ];

  // ---------------------------------------------------------------- pickers
  Future<void> _pickPoints() async {
    final sel = Set<String>.of(_points);
    final search = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final q = search.text.trim().toLowerCase();
          final list = _allPoints.where((p) => q.isEmpty || '${p['code']} ${p['name']}'.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: Text(tx(ctx, 'النِقاط', 'Points')),
            content: SizedBox(
              width: 460,
              height: 480,
              child: Column(children: [
                TextField(
                  controller: search,
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'ابحَث', 'Search')),
                  onChanged: (_) => set(() {}),
                ),
                Row(children: [
                  TextButton(onPressed: () => set(sel.clear), child: Text(tx(ctx, 'كُلّ النِقاط', 'All points'))),
                  TextButton(onPressed: () => set(() => sel.addAll(list.map((p) => vStr(p['id'])))), child: Text(tx(ctx, 'اختَر الظاهِر', 'Select shown'))),
                  const Spacer(),
                  Text(sel.isEmpty ? tx(ctx, 'الكُلّ', 'All') : '${sel.length}', style: const TextStyle(color: VC.muted)),
                ]),
                Expanded(
                  child: ListView(children: [
                    for (final p in list)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(vStr(p['id'])),
                        title: Text('${p['code']}  ${p['name']}', overflow: TextOverflow.ellipsis),
                        onChanged: (v) => set(() => v == true ? sel.add(vStr(p['id'])) : sel.remove(vStr(p['id']))),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'تَطبيق', 'Apply'))),
            ],
          );
        },
      ),
    );
    search.dispose();
    if (ok == true) {
      setState(() => _points
        ..clear()
        ..addAll(sel));
      _load();
    }
  }

  Future<void> _pickColumns() async {
    final sel = List<String>.of(_columns);
    final search = TextEditingController();
    final avail = _available;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q = search.text.trim().toLowerCase();
        final byGroup = <String, List<String>>{};
        for (final k in avail) {
          if (q.isNotEmpty && !_label(k).toLowerCase().contains(q) && !k.contains(q)) continue;
          byGroup.putIfAbsent(_cols[k]?.group ?? 'other', () => []).add(k);
        }
        final wide = MediaQuery.of(ctx).size.width > 820;
        final pickList = ListView(children: [
          for (final g in _groups.keys)
            if (byGroup[g] != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                child: Row(children: [
                  Expanded(child: Text(tx(ctx, _groups[g]!.$2, _groups[g]!.$1), style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(
                    onPressed: () => set(() {
                      for (final k in byGroup[g]!) {
                        if (!sel.contains(k)) sel.add(k);
                      }
                    }),
                    child: Text(tx(ctx, 'الكُلّ', 'All'), style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
              for (final k in byGroup[g]!)
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  value: sel.contains(k),
                  title: Text(_label(k)),
                  onChanged: (v) => set(() => v == true ? sel.add(k) : sel.remove(k)),
                ),
            ],
        ]);
        final order = ReorderableListView(
          buildDefaultDragHandles: false,
          onReorder: (a, b) => set(() {
            if (b > a) b--;
            sel.insert(b, sel.removeAt(a));
          }),
          children: [
            for (var i = 0; i < sel.length; i++)
              ListTile(
                key: ValueKey(sel[i]),
                dense: true,
                leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                title: Text(_label(sel[i])),
                trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => set(() => sel.removeAt(i))),
              ),
          ],
        );
        return AlertDialog(
          title: Text(tx(ctx, 'الأَعمِدة (${sel.length} مِن ${avail.length})', 'Columns (${sel.length} of ${avail.length})')),
          content: SizedBox(
            width: wide ? 820 : 460,
            height: 560,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in _presets.entries)
                  ActionChip(label: Text(tx(ctx, p.value.$2, p.value.$1)), onPressed: () => set(() => sel
                    ..clear()
                    ..addAll(p.value.$3.where(avail.contains)))),
                ActionChip(
                    label: Text(tx(ctx, 'كُلّ الأَعمِدة', 'Everything')),
                    onPressed: () => set(() => sel
                      ..clear()
                      ..addAll([for (final g in _groups.keys) ...avail.where((k) => (_cols[k]?.group ?? 'other') == g)]))),
                for (final v in _views.entries)
                  InputChip(
                    avatar: const Icon(Icons.bookmark, size: 16),
                    label: Text(v.key),
                    onPressed: () => set(() => sel
                      ..clear()
                      ..addAll(v.value.where(avail.contains))),
                    onDeleted: () => set(() => _views.remove(v.key)),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: search,
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'ابحَث عَن عَمود', 'Search columns')),
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: pickList),
                        const VerticalDivider(),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(tx(ctx, 'المُختارة — اسحَب لِلتَرتيب', 'Selected · drag to reorder'), style: const TextStyle(color: VC.muted, fontSize: 12)),
                            Expanded(child: order),
                          ]),
                        ),
                      ])
                    : DefaultTabController(
                        length: 2,
                        child: Column(children: [
                          TabBar(tabs: [Tab(text: tx(ctx, 'كُلّ الأَعمِدة', 'All columns')), Tab(text: tx(ctx, 'التَرتيب', 'Order'))]),
                          Expanded(child: TabBarView(children: [pickList, order])),
                        ]),
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(tx(ctx, 'حِفظ كَعَرض', 'Save as view')),
              onPressed: sel.isEmpty
                  ? null
                  : () async {
                      final name = await vAskReason(ctx, tx(ctx, 'اسم العَرض', 'View name'), tx(ctx, 'مِثال: تَقرير المُحاسِب', 'For example: accountant report'),
                          button: tx(ctx, 'حِفظ', 'Save'));
                      if (name != null && name.trim().isNotEmpty) set(() => _views[name.trim()] = List.of(sel));
                    },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'تَطبيق', 'Apply'))),
          ],
        );
      }),
    );
    search.dispose();
    if (ok == true) {
      setState(() {
        _columns = sel;
        if (_sort != null && !_columns.contains(_sort)) _sort = null;
      });
      _persist();
      _load();
    } else {
      _persist(); // saved views may have changed
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final pages = (_total / _per).ceil();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          VRange(from: _from, to: _to, onChanged: (a, b) {
            _from = a;
            _to = b;
            _load();
          }),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          VScopeFilter(width: 260, value: _scope, onChanged: (v) {
            setState(() => _scope = v);
            _load();
          }),
          OutlinedButton.icon(
            icon: const Icon(Icons.place_outlined, size: 18),
            label: Text(_points.isEmpty
                ? tx(context, 'كُلّ النِقاط (${_allPoints.length})', 'All points (${_allPoints.length})')
                : tx(context, '${_points.length} نُقطة', '${_points.length} points')),
            onPressed: _pickPoints,
          ),
          _drop<String>(tx(context, 'التاريخ حَسَب', 'Date by'), _basis, {
            'exit': tx(context, 'الخُروج', 'Exit'),
            'entry': tx(context, 'الدُخول', 'Entry'),
          }, (v) => _basis = v),
          _drop<String>(tx(context, 'الحالة', 'Status'), _status, {
            'closed': tx(context, 'مُغلَقة', 'Closed'),
            'active': tx(context, 'مَفتوحة', 'Open'),
            'void': tx(context, 'مُلغاة', 'Void'),
            'all': tx(context, 'الكُلّ', 'All'),
          }, (v) => _status = v),
          _drop<String>(tx(context, 'الدَفع', 'Payment'), _payment, {
            '': tx(context, 'أَيّ', 'Any'),
            'Cash': tx(context, 'كاش', 'Cash'),
            'C-Card': tx(context, 'كارت', 'Card'),
            'Split': tx(context, 'مُقَسَّم', 'Split'),
            'Free': tx(context, 'مَجّانيّة', 'Free'),
          }, (v) => _payment = v),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: tx(context, 'تَذكَرة / لَوحة / عَميل', 'Ticket / plate / customer'),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: Text(tx(context, 'الأَعمِدة (${_columns.length})', 'Columns (${_columns.length})')),
            onPressed: _pickColumns,
          ),
          IconButton.filledTonal(onPressed: _busy ? null : () => _load(keepPage: true), icon: const Icon(Icons.refresh)),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Excel'),
            onPressed: _exporting != null || _total == 0 ? null : () => _export('xlsx'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('CSV'),
            onPressed: _exporting != null || _total == 0 ? null : () => _export('csv'),
          ),
          if (_exporting != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(tx(context, 'تَجهيز $_exporting', 'Preparing $_exporting'), style: const TextStyle(color: VC.muted)),
            ]),
        ]),
      ),
      SizedBox(height: 2, child: _busy ? const LinearProgressIndicator(minHeight: 2) : null),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(spacing: 18, runSpacing: 6, children: [
          _tot(tx(context, 'تَذاكِر', 'Tickets'), VF.n(_total)),
          _tot(tx(context, 'سَيّارات', 'Cars'), VF.n(vNum(_totals['cars']))),
          _tot(tx(context, 'المَبلَغ', 'Amount'), VF.money(vNum(_totals['amount']))),
          _tot(tx(context, 'الضَريبة', 'VAT'), VF.money(vNum(_totals['vat']))),
          _tot(tx(context, 'كاش', 'Cash'), VF.money(vNum(_totals['cash']))),
          _tot(tx(context, 'كارت', 'Card'), VF.money(vNum(_totals['card']))),
          _tot(tx(context, 'إكراميّات', 'Tips'), VF.money(vNum(_totals['tips']))),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _err != null
            ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))))
            : _rows.isEmpty
                ? Center(child: Text(_busy ? '' : tx(context, 'لا تُوجَد تَذاكِر بِهذه الفَلاتِر.', 'No tickets match these filters.'), style: const TextStyle(color: VC.muted)))
                : _table(),
      ),
      if (pages > 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                onPressed: _page > 0 && !_busy
                    ? () {
                        _page--;
                        _load(keepPage: true);
                      }
                    : null,
                icon: const Icon(Icons.chevron_left)),
            Text(tx(context, 'صَفحة ${_page + 1} مِن $pages', 'Page ${_page + 1} of $pages')),
            IconButton(
                onPressed: _page < pages - 1 && !_busy
                    ? () {
                        _page++;
                        _load(keepPage: true);
                      }
                    : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
    ]);
  }

  Widget _tot(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: VC.muted, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ]);

  Widget _drop<T>(String label, T value, Map<T, String> items, void Function(T) set) => SizedBox(
        width: 150,
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v == null) return;
            set(v);
            _load();
          },
        ),
      );

  Widget _table() {
    final sortIdx = _sort == null ? null : _columns.indexOf(_sort!);
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: sortIdx == null || sortIdx < 0 ? null : sortIdx,
            sortAscending: !_desc,
            columnSpacing: 22,
            horizontalMargin: 12,
            headingRowHeight: 44,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 48,
            headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            columns: [
              for (final c in _columns)
                DataColumn(
                  label: Text(_label(c)),
                  numeric: const {_K.money, _K.int}.contains(_kind(c)),
                  onSort: (_, __) {
                    setState(() {
                      if (_sort == c) {
                        _desc = !_desc;
                      } else {
                        _sort = c;
                        _desc = true;
                      }
                    });
                    _load();
                  },
                ),
            ],
            rows: [
              for (final r in _rows)
                DataRow(
                  color: r['void_reason'] != null ? WidgetStatePropertyAll(VC.bad.withValues(alpha: 0.06)) : null,
                  cells: [
                    for (final c in _columns)
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(_fmt(c, r[c]), overflow: TextOverflow.ellipsis),
                      )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
