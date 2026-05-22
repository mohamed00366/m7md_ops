import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 📊 شَريط إحصائيّات مُوَحَّد يَعرِض عِدّة مَقاييس بِشَكل أُفُقيّ
///
/// **الاستِخدام:**
/// ```dart
/// M7StatsBanner(stats: [
///   M7Stat(icon: Icons.business, label: 'الكُلّ', value: 42, color: AppColors.brand),
///   M7Stat(icon: Icons.check_circle, label: 'نَشِط', value: 38, color: AppColors.success),
/// ])
/// ```
class M7StatsBanner extends StatelessWidget {
  final List<M7Stat> stats;
  final bool compact;
  const M7StatsBanner({super.key, required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.10),
            AppColors.gold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: _interleaveDividers(
          stats.map((s) => Expanded(child: _StatBox(stat: s, compact: compact))).toList(),
        ),
      ),
    );
  }

  static List<Widget> _interleaveDividers(List<Widget> items) {
    if (items.length <= 1) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) {
        out.add(Container(
            width: 1, height: 38, color: Colors.grey.withValues(alpha: 0.2)));
      }
    }
    return out;
  }
}

class M7Stat {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  const M7Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StatBox extends StatelessWidget {
  final M7Stat stat;
  final bool compact;
  const _StatBox({required this.stat, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stat.icon, color: stat.color, size: compact ? 14 : 16),
        SizedBox(height: compact ? 1 : 2),
        Text('${stat.value}',
            style: TextStyle(
                color: stat.color,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 14 : 16,
                fontFamily: 'monospace')),
        Text(stat.label,
            style: TextStyle(
                color: stat.color,
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}
