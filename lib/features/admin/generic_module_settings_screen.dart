import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/module_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// 🎛️ شاشة عامّة لعرض إعدادات أيّ موديول بناءً على schema
///
/// تأخذ ModuleSettings (مع items) وتعرضها بشكل تلقائي:
///   - bool → SwitchListTile
///   - int/double مع min/max → Slider + قيمة عدديّة
///   - string مع options → ChoiceChips أو dropdown
///   - timeRange → time pickers
class GenericModuleSettingsScreen extends StatefulWidget {
  final String titleAr;
  final String titleEn;
  final ModuleSettings settings;

  const GenericModuleSettingsScreen({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.settings,
  });

  @override
  State<GenericModuleSettingsScreen> createState() =>
      _GenericModuleSettingsScreenState();
}

class _GenericModuleSettingsScreenState
    extends State<GenericModuleSettingsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
    widget.settings.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _init() async {
    await widget.settings.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    // تجميع العناصر حسب group
    final groups = <String, List<SettingItem>>{};
    for (final item in widget.settings.items) {
      final g = item.group ?? '';
      groups.putIfAbsent(g, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? widget.titleAr : widget.titleEn),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: isAr ? 'إعادة الافتراضيّ' : 'Reset',
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final entry in groups.entries) ...[
            if (entry.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            SectionCard(
              child: Column(
                children: [
                  for (var i = 0; i < entry.value.length; i++) ...[
                    if (i > 0) const Divider(height: 14),
                    _SettingRow(
                      item: entry.value[i],
                      settings: widget.settings,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'إعادة كل إعدادات هذا الموديول للافتراضيّ؟'
            : 'Reset all settings to defaults?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.isAr ? 'إعادة' : 'Reset')),
        ],
      ),
    );
    if (ok == true) await widget.settings.resetAll();
  }
}

class _SettingRow extends StatelessWidget {
  final SettingItem item;
  final ModuleSettings settings;
  const _SettingRow({required this.item, required this.settings});

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    final label = isAr ? item.labelAr : item.labelEn;
    final help = isAr ? item.helpAr : item.helpEn;

    switch (item.internalType) {
      case SettingType.boolType:
        final v = settings.getBool(item.key);
        return SwitchListTile(
          value: v,
          onChanged: (nv) => settings.set(item.key, nv),
          title: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          subtitle: help == null
              ? null
              : Text(help, style: const TextStyle(fontSize: 11)),
          contentPadding: EdgeInsets.zero,
          dense: true,
        );

      case SettingType.intType:
        final v = settings.getInt(item.key);
        final min = (item.min ?? 0).toInt();
        final max = (item.max ?? 100).toInt();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                      if (help != null)
                        Text(help, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$v${item.unit ?? ''}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brand),
                  ),
                ),
              ],
            ),
            Slider(
              value: v.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: ((max - min) / (item.step?.toInt() ?? 1)).round().clamp(1, 1000),
              label: '$v',
              onChanged: (nv) => settings.set(item.key, nv.round()),
            ),
          ],
        );

      case SettingType.doubleType:
        final v = settings.getDouble(item.key);
        final min = (item.min ?? 0).toDouble();
        final max = (item.max ?? 100).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                      if (help != null)
                        Text(help, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${v.toStringAsFixed(1)}${item.unit ?? ''}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brand),
                  ),
                ),
              ],
            ),
            Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChanged: (nv) => settings.set(item.key, nv),
            ),
          ],
        );

      case SettingType.stringType:
        final v = settings.getString(item.key);
        if (item.optionsBilingual != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              if (help != null)
                Text(help, style: const TextStyle(fontSize: 10)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: item.optionsBilingual!.map((opt) {
                  final selected = v == opt.key;
                  return ChoiceChip(
                    label: Text(isAr ? opt.key : opt.value,
                        style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) => settings.set(item.key, opt.key),
                  );
                }).toList(),
              ),
            ],
          );
        }
        if (item.options != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              if (help != null)
                Text(help, style: const TextStyle(fontSize: 10)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: item.options!.map((opt) {
                  final selected = v == opt;
                  return ChoiceChip(
                    label: Text(opt, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) => settings.set(item.key, opt),
                  );
                }).toList(),
              ),
            ],
          );
        }
        // free-text
        return TextField(
          controller: TextEditingController(text: v),
          onSubmitted: (nv) => settings.set(item.key, nv),
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        );

      case SettingType.timeRangeType:
        final v = settings.getTimeRange(item.key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
            if (help != null)
              Text(help, style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _parseTime(v.start),
                      );
                      if (t == null) return;
                      await settings.set(
                          item.key,
                          TimeRange(
                              start: _fmtTime(t), end: v.end));
                    },
                    icon: const Icon(Icons.login, size: 16),
                    label: Text('FROM ${v.start}'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _parseTime(v.end),
                      );
                      if (t == null) return;
                      await settings.set(
                          item.key,
                          TimeRange(start: v.start, end: _fmtTime(t)));
                    },
                    icon: const Icon(Icons.logout, size: 16),
                    label: Text('TO ${v.end}'),
                  ),
                ),
              ],
            ),
          ],
        );

      case SettingType.stringListType:
        final v = settings.getStringList(item.key);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text(
            v.isEmpty ? (isAr ? '— فارغ' : '— empty') : v.join(', '),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.edit, size: 16),
          // editing of stringList ليس مدعوماً هنا حالياً (صفحة خاصّة لو لزم)
        );
    }
  }

  TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    if (p.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? 8,
      minute: int.tryParse(p[1]) ?? 0,
    );
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
