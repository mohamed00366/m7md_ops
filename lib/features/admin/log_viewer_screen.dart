import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/m7_log.dart';
import '../../core/theme/app_colors.dart';

/// 📝 شاشة LogViewer — تعرض الـ logs المباشرة من M7Log داخل التطبيق.
///
/// • تتسجّل في M7Log كـ Sink مؤقّت طوال فتح الشاشة.
/// • فلترة بالمستوى (debug/info/warn/error).
/// • فلترة بالـ tag (search).
/// • نسخ سجلّ كامل للـ clipboard لإرساله للدعم.
///
/// ℹ️ في الإنتاج يجب أن تظهر فقط للـ Super Admin أو في وضع debug.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  late final _LiveLogSink _sink;
  M7LogLevel _minLevel = M7LogLevel.debug;
  String _search = '';
  bool _autoScroll = true;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _sink = _LiveLogSink(onAdd: (_) {
      if (mounted) {
        setState(() {});
        if (_autoScroll && _scrollCtrl.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(
                _scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });
    M7Log.sinks.add(_sink);
    // سجلّ افتتاح
    M7Log.info('LogViewer', 'opened');
  }

  @override
  void dispose() {
    M7Log.sinks.remove(_sink);
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<M7LogEntry> get _filtered {
    final q = _search.trim().toLowerCase();
    return _sink.entries.where((e) {
      if (e.level.priority < _minLevel.priority) return false;
      if (q.isEmpty) return true;
      return e.tag.toLowerCase().contains(q) ||
          e.message.toLowerCase().contains(q);
    }).toList();
  }

  String _formatEntry(M7LogEntry e) {
    final ts = e.timestamp.toIso8601String().substring(11, 23);
    final buf = StringBuffer('[$ts] ${e.level.symbol} ${e.tag}: ${e.message}');
    if (e.data != null) buf.write('\n    data: ${e.data}');
    if (e.error != null) buf.write('\n    error: ${e.error}');
    if (e.stack != null) buf.write('\n${e.stack}');
    return buf.toString();
  }

  void _copyAll() {
    final text = _filtered.map(_formatEntry).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 2),
      content: Text('نُسخ ${_filtered.length} سطر'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'نسخ كل السجلّ',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'مسح',
            onPressed: () {
              setState(() => _sink.entries.clear());
            },
          ),
          IconButton(
            icon: Icon(_autoScroll
                ? Icons.vertical_align_bottom
                : Icons.vertical_align_center),
            tooltip: _autoScroll ? 'إيقاف auto-scroll' : 'تفعيل auto-scroll',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
        ],
      ),
      body: Column(
        children: [
          // فلتر المستوى
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final lvl in M7LogLevel.values) ...[
                      ChoiceChip(
                        label: Text('${lvl.symbol} ${lvl.name}'),
                        selected: _minLevel == lvl,
                        onSelected: (_) => setState(() => _minLevel = lvl),
                        labelStyle: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${filtered.length}/${_sink.entries.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'بحث في tag/message…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ],
            ),
          ),
          // قائمة السجلّ
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد سجلّات بعد… استخدم التطبيق',
                      style: TextStyle(
                          color: theme.textTheme.bodySmall?.color),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final color = _colorFor(e.level);
                      return InkWell(
                        onTap: () => _showDetails(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          color: color.withValues(alpha: 0.04),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.level.symbol,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text(
                                e.timestamp
                                    .toIso8601String()
                                    .substring(11, 19),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(e.tag,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                    )),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                              if (e.error != null)
                                const Icon(Icons.warning_amber,
                                    size: 14, color: AppColors.danger),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(M7LogLevel lvl) {
    switch (lvl) {
      case M7LogLevel.debug:
        return AppColors.info;
      case M7LogLevel.info:
        return AppColors.success;
      case M7LogLevel.warn:
        return AppColors.warning;
      case M7LogLevel.error:
        return AppColors.danger;
    }
  }

  void _showDetails(M7LogEntry e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Text(e.level.symbol),
            const SizedBox(width: 6),
            Text(e.tag),
          ],
        ),
        content: SelectableText(
          _formatEntry(e),
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _formatEntry(e)));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تمّ النسخ')),
              );
            },
            child: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _LiveLogSink implements M7LogSink {
  final List<M7LogEntry> entries = [];
  final void Function(M7LogEntry) onAdd;
  static const _maxEntries = 500; // رايث من النموّ غير المحدود

  _LiveLogSink({required this.onAdd});

  @override
  void add(M7LogEntry entry) {
    entries.add(entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    onAdd(entry);
  }
}
