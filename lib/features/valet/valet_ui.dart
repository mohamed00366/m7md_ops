import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/theme/app_colors.dart';
import 'valet_admin.dart';

/// نَصّ بِلُغة المُستَخدِم (عَرَبيّ / English / اُردو تِلقائيّاً).
String tx(BuildContext c, String ar, String en) => AppStrings.of(c).t(ar, en);

class VC {
  static const gold = Color(0xFFC9A227);
  static const ok = AppColors.success;
  static const warn = Color(0xFFF59E0B);
  static const bad = AppColors.danger;
  static const info = AppColors.info;
  static const muted = Color(0xFF6B7280);
}

class VF {
  static final _money = NumberFormat('#,##0.00', 'en');
  static final _int = NumberFormat('#,##0', 'en');
  static String money(num? v) => _money.format(v ?? 0);
  static String n(num? v) => _int.format(v ?? 0);
  static String dt(DateTime? d) => d == null ? '-' : DateFormat('dd/MM/yyyy HH:mm', 'en').format(d);
  static String date(DateTime? d) => d == null ? '-' : DateFormat('dd/MM/yyyy', 'en').format(d);
  static String time(DateTime? d) => d == null ? '-' : DateFormat('HH:mm', 'en').format(d);
  static String iso(DateTime d) => DateFormat('yyyy-MM-dd', 'en').format(d);
  static String short(String code) {
    final p = code.split('-');
    return code.startsWith('T-') && p.length > 2 ? p[1] : code;
  }

  static String since(BuildContext c, DateTime? d) {
    if (d == null) return '-';
    final m = DateTime.now().difference(d).inMinutes;
    if (m < 1) return tx(c, 'الآن', 'now');
    if (m < 60) return tx(c, '$m د', '$m min');
    return tx(c, '${m ~/ 60} س ${(m % 60).toString().padLeft(2, '0')} د', '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min');
  }

  /// طَلَب مُتَأَخِّر: بُرتُقاليّ بَعد 5 دَقائِق، أَحمَر بَعد 10.
  static Color age(DateTime? t) {
    if (t == null) return VC.muted;
    final m = DateTime.now().difference(t).inMinutes;
    return m >= 10 ? VC.bad : (m >= 5 ? VC.warn : VC.ok);
  }
}

void vToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? VC.bad : null, behavior: SnackBarBehavior.floating));
}

String vErr(BuildContext c, Object e) => e is ValetError ? tx(c, e.ar, e.en) : '$e';

/// يُنَفِّذ [f] وَيُظهِر الخَطَأ في رِسالة. يُعيد null عِند الخَطَأ.
Future<T?> vGuard<T>(BuildContext context, Future<T> Function() f, {String? ok}) async {
  try {
    final r = await f();
    if (ok != null && context.mounted) vToast(context, ok);
    return r;
  } catch (e) {
    if (context.mounted) vToast(context, vErr(context, e), error: true);
    return null;
  }
}

/// يَفتَح جَلسة الفاليه قَبل عَرض الشاشة (أَو يَطلُب كَلِمة المُرور مَرّة واحِدة).
class ValetGate extends StatefulWidget {
  const ValetGate({super.key, required this.child, this.perm = ValetAdmin.permView});
  final Widget child;
  final String perm;

  @override
  State<ValetGate> createState() => _ValetGateState();
}

class _ValetGateState extends State<ValetGate> {
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ValetAdmin.I.restore();
  }

  Future<void> _login() async {
    final user = context.read<AuthProvider>().account?.username ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ValetAdmin.I.login(user, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = vErr(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ValetAdmin.I,
        builder: (context, _) {
          final v = ValetAdmin.I;
          if (!v.restored) return const Center(child: CircularProgressIndicator());
          if (v.hasSession && v.can(widget.perm)) return widget.child;
          if (v.hasSession) {
            return _message(Icons.lock_outline, tx(context, 'لَيس لَديك صَلاحيّة لِهذه الصَفحة.', 'You do not have access to this page.'));
          }
          final user = context.read<AuthProvider>().account?.username ?? '';
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Icon(Icons.local_parking, size: 48, color: VC.gold),
                      const SizedBox(height: 12),
                      Text(tx(context, 'التَحَكُّم في تَطبيقات الفاليه', 'Valet apps control'),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        tx(context, 'أَكِّد كَلِمة مُرورك ($user) لِفَتح قِسم الفاليه.', 'Confirm your password ($user) to open the valet section.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: VC.muted),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        autofocus: true,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(labelText: tx(context, 'كَلِمة المُرور', 'Password'), prefixIcon: const Icon(Icons.lock_outline)),
                      ),
                      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: VC.bad))],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(tx(context, 'فَتح', 'Open')),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _message(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: VC.muted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// عُنوان الصَفحة + أَزرار.
class VHead extends StatelessWidget {
  const VHead(this.title, {super.key, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          spacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(color: VC.muted, fontSize: 13)),
            ]),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          ],
        ),
      );
}

class VPanel extends StatelessWidget {
  const VPanel({super.key, this.title, required this.child, this.actions = const []});
  final String? title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (title != null || actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  if (title != null) Expanded(child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  ...actions,
                ]),
              ),
            child,
          ]),
        ),
      );
}

class VKpi extends StatelessWidget {
  const VKpi(this.label, this.value, {super.key, required this.icon, this.color, this.note});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 190,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                Text(label, style: const TextStyle(color: VC.muted, fontSize: 12)),
                if (note != null) Text(note!, style: const TextStyle(color: VC.muted, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class VPill extends StatelessWidget {
  const VPill(this.text, {super.key, this.color = VC.muted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

VPill vStatusPill(BuildContext c, String status, {String? voidReason}) {
  if (voidReason != null && voidReason.isNotEmpty) return VPill(tx(c, 'مُلغاة', 'Void'), color: VC.bad, icon: Icons.block);
  switch (status) {
    case 'Active':
      return VPill(tx(c, 'نَشِطة', 'Active'), color: VC.info);
    case 'Check-Out':
      return VPill(tx(c, 'خُروج', 'Check-out'), color: VC.warn);
    case 'Finish':
      return VPill(tx(c, 'مُنتَهية', 'Finished'), color: VC.ok);
    case 'Open':
      return VPill(tx(c, 'مَفتوحة', 'Open'), color: VC.ok);
    case 'Closing':
      return VPill(tx(c, 'مُغلَقة', 'Closed'));
  }
  return VPill(status);
}

/// تَحميل البَيانات مَع مُؤَشِّر، وَرِسالة خَطَأ مَع "إعادة المُحاوَلة"، وَتَحديث دَوريّ اختِياريّ.
class VLoader<T> extends StatefulWidget {
  const VLoader({super.key, required this.load, required this.builder, this.refreshEvery});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  final Duration? refreshEvery;

  @override
  State<VLoader<T>> createState() => _VLoaderState<T>();
}

class _VLoaderState<T> extends State<VLoader<T>> {
  T? _data;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    final every = widget.refreshEvery;
    if (every != null) _tick(every);
  }

  void _tick(Duration every) async {
    while (mounted) {
      await Future.delayed(every);
      if (!mounted) return;
      if (!_busy) await _reload(silent: true);
    }
  }

  Future<void> _reload({bool silent = false}) async {
    _busy = true;
    if (!silent && mounted) setState(() {});
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && (!silent || _data == null)) setState(() => _error = e);
    } finally {
      _busy = false;
      if (mounted && !silent) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: VC.bad, size: 40),
            const SizedBox(height: 8),
            Text(vErr(context, _error!), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: Text(tx(context, 'إعادة المُحاوَلة', 'Try again'))),
          ]),
        ),
      );
    }
    if (_data == null) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    return Stack(children: [
      widget.builder(context, _data as T, _reload),
      if (_busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }
}

/// جَدول يَملأ العَرض وَيَتَمَرَّر أُفُقيّاً عِند الحاجة.
class VTable extends StatelessWidget {
  const VTable({super.key, required this.columns, required this.rows, this.empty});
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(empty ?? tx(context, 'لا تُوجَد بَيانات.', 'Nothing to show.'), style: const TextStyle(color: VC.muted))),
      );
    }
    return LayoutBuilder(
      builder: (_, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            columns: columns,
            rows: rows,
            columnSpacing: 20,
            horizontalMargin: 10,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 58,
            headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// شَريط الفَترة (مِن / إلى) مَع اختِصارات.
class VRange extends StatelessWidget {
  const VRange({super.key, required this.from, required this.to, required this.onChanged});
  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Widget p(String ar, String en, DateTime a, DateTime b) => ActionChip(label: Text(tx(context, ar, en)), onPressed: () => onChanged(a, b));
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.date_range, size: 18),
        label: Text('${VF.date(from)}  ←→  ${VF.date(to)}'),
        onPressed: () async {
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2024),
            lastDate: today.add(const Duration(days: 1)),
            initialDateRange: DateTimeRange(start: from, end: to),
          );
          if (r != null) onChanged(r.start, r.end);
        },
      ),
      p('اليَوم', 'Today', today, today),
      p('أَمس', 'Yesterday', today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1))),
      p('7 أَيّام', '7 days', today.subtract(const Duration(days: 6)), today),
      p('هذا الشَهر', 'This month', DateTime(now.year, now.month), today),
      p('الشَهر الماضي', 'Last month', DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
    ]);
  }
}

/// قائِمة نِقاط الفاليه (مُخَزَّنة) لِلفَلاتِر.
class VPoints {
  static List<VJson>? _list;
  static Future<List<VJson>> get() async => _list ??= vList((await ValetAdmin.I.call('vva_points'))['points']);
  static void clear() => _list = null;
}

/// اختيار النُقطة مَع البَحث بِالكِتابة (الكود أَو الاسم): يَفتَح نافِذة فيها حَقل بَحث وَالقائِمة.
class VPointFilter extends StatelessWidget {
  const VPointFilter({super.key, required this.points, required this.value, required this.onChanged});
  final List<VJson> points;
  final String? value;
  final ValueChanged<String?> onChanged;

  String _name(VJson p) => '${p['code']}  ${p['name']}';

  Future<void> _open(BuildContext context) async {
    final q = TextEditingController();
    const all = '__all__';
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final f = q.text.trim().toLowerCase();
        final list = points.where((p) => f.isEmpty || _name(p).toLowerCase().contains(f)).toList();
        return AlertDialog(
          title: Text(tx(ctx, 'اختَر النُقطة', 'Choose a point')),
          content: SizedBox(
            width: 440,
            height: 460,
            child: Column(children: [
              TextField(
                controller: q,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: tx(ctx, 'اكتُب اسم النُقطة أَو الكود', 'Type the point name or code'),
                  suffixIcon: q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => set(q.clear)),
                ),
                onChanged: (_) => set(() {}),
                onSubmitted: (_) {
                  if (list.length == 1) Navigator.pop(ctx, vStr(list.first['id']));
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  if (f.isEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.public),
                      title: Text(tx(ctx, 'كُلّ النِقاط', 'All points'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      selected: value == null,
                      onTap: () => Navigator.pop(ctx, all),
                    ),
                  for (final p in list)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(_name(p), overflow: TextOverflow.ellipsis),
                      selected: vStr(p['id']) == value,
                      onTap: () => Navigator.pop(ctx, vStr(p['id'])),
                    ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(tx(ctx, 'لا تُوجَد نُقطة بِهذا الاسم.', 'No point with this name.'), textAlign: TextAlign.center, style: const TextStyle(color: VC.muted)),
                    ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    q.dispose();
    if (picked == null) return;
    onChanged(picked == all ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final cur = points.where((p) => vStr(p['id']) == value).firstOrNull;
    return SizedBox(
      width: 280,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: tx(context, 'النُقطة', 'Point'),
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          child: Text(cur == null ? tx(context, 'كُلّ النِقاط', 'All points') : _name(cur), overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ),
    );
  }
}

Future<String?> vAskReason(BuildContext context, String title, String message, {required String button}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, maxLines: 2, decoration: InputDecoration(labelText: tx(ctx, 'السَبَب *', 'Reason *'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: VC.bad),
          onPressed: () {
            if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
          },
          child: Text(button),
        ),
      ],
    ),
  );
}

Future<bool> vConfirm(BuildContext context, String title, String message, {String? button}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: VC.bad),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(button ?? tx(ctx, 'حَذف', 'Delete')),
        ),
      ],
    ),
  );
  return r == true;
}

/// تَصدير Excel (.xlsx) بِخِدمة الأوبريشن المُوَحَّدة.
Future<void> vExport(BuildContext context, String fileName, List<ExcelSheet> sheets) async {
  final ok = await ExcelExporter.export(fileName: fileName, sheets: sheets);
  if (context.mounted && !ok) vToast(context, tx(context, 'تَعَذَّر التَصدير.', 'Export failed.'), error: true);
}


// ---------------------------------------------------------------- days of the week (hourly tables)
/// ISO days (1 = Monday … 7 = Sunday) of a `valet_prices.days` value; empty = every day.
List<int> vDays(dynamic v) =>
    (v is List ? v : const []).map((e) => int.tryParse('$e') ?? 0).where((d) => d >= 1 && d <= 7).toList()..sort();

String vDayName(BuildContext c, int d) {
  const ar = ['الإثنَين', 'الثُلاثاء', 'الأَربِعاء', 'الخَميس', 'الجُمُعة', 'السَبت', 'الأَحَد'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return tx(c, ar[d - 1], en[d - 1]);
}

String vDaysLabel(BuildContext c, dynamic v) {
  final d = vDays(v);
  if (d.isEmpty) return tx(c, 'كُلّ الأَيّام', 'Every day');
  // show Saturday first (UAE week)
  final order = [6, 7, 1, 2, 3, 4, 5];
  return order.where(d.contains).map((x) => vDayName(c, x)).join(tx(c, '، ', ', '));
}

/// Minutes of a `H:MM` duration (Infinity = very large).
int vMinutes(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0;
  if (t.toLowerCase().startsWith('inf')) return 1 << 30;
  final p = t.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

String vBand(BuildContext c, String from, String to) {
  final open = to.trim().isEmpty || to.toLowerCase().startsWith('inf');
  return open
      ? tx(c, 'مِن $from فَما فَوق (لِكُلّ ساعة)', '$from+ (per hour)')
      : tx(c, 'مِن $from إلى $to', '$from → $to');
}


// ---------------------------------------------------------------- VAT entry mode
/// (net, total) of an [amount] typed with VAT included ([included]) or without (VAT added).
(double, double) vSplitVat(num amount, num vatRate, bool included) {
  double r2(num v) => double.parse(v.toStringAsFixed(2));
  return included ? (r2(amount / (1 + vatRate)), r2(amount)) : (r2(amount), r2(amount * (1 + vatRate)));
}

/// "Amount includes VAT" / "VAT is added to the amount".
Widget vVatToggle(BuildContext c, bool included, num vatRate, ValueChanged<bool> onChanged) {
  final pct = (vatRate * 100).toStringAsFixed(vatRate * 100 % 1 == 0 ? 0 : 1);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
    Text(tx(c, 'الضَريبة ($pct%)', 'VAT ($pct%)'), style: const TextStyle(fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: true, label: Text(tx(c, 'المَبلَغ شامِل الضَريبة', 'Amount includes VAT'))),
        ButtonSegment(value: false, label: Text(tx(c, 'بِدون ضَريبة (تُضاف)', 'Net (VAT added)'))),
      ],
      selected: {included},
      onSelectionChanged: (v) => onChanged(v.first),
    ),
  ]);
}


/// Amount field with its own VAT button: "incl. VAT" / "+ VAT"; shows the split under it.
class VatAmountField extends StatelessWidget {
  const VatAmountField({
    super.key,
    required this.controller,
    required this.included,
    required this.vatRate,
    required this.onToggle,
    this.onChanged,
    this.label,
    this.extra = '',
    this.dense = false,
  });
  final TextEditingController controller;
  final bool included;
  final num vatRate;
  final VoidCallback onToggle;
  final VoidCallback? onChanged;
  final String? label;
  final String extra;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final a = num.tryParse(controller.text.trim()) ?? 0;
    final (net, total) = vSplitVat(a, vatRate, included);
    final pct = (vatRate * 100).toStringAsFixed(vatRate * 100 % 1 == 0 ? 0 : 1);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(
        isDense: dense,
        labelText: label,
        helperText: dense
            ? tx(context, '= ${VF.money(total)} شامِل', '= ${VF.money(total)} incl.')
            : tx(context, '${VF.money(net)} + ضَريبة $pct% ${VF.money(total - net)} = ${VF.money(total)}$extra',
                '${VF.money(net)} + VAT $pct% ${VF.money(total - net)} = ${VF.money(total)}$extra'),
        suffixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Tooltip(
            message: tx(context, 'اضغَط لِلتَبديل بَين: المَبلَغ شامِل الضَريبة / الضَريبة تُضاف عَلَيه',
                'Tap to switch: amount includes VAT / VAT is added on top'),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(included ? Icons.check_circle_outline : Icons.add_circle_outline, size: 16,
                  color: included ? VC.ok : VC.warn),
              label: Text(
                  dense
                      ? (included ? tx(context, 'شامِل', 'incl.') : '+$pct%')
                      : (included ? tx(context, 'شامِل الضَريبة', 'incl. VAT') : tx(context, '+ ضَريبة $pct%', '+ VAT $pct%')),
                  style: const TextStyle(fontSize: 12)),
              onPressed: onToggle,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 32),
      ),
    );
  }
}
