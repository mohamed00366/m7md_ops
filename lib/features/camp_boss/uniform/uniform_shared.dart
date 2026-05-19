import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../camp_palette.dart';

class UniformPalette {
  static const primary = AppPalette.purple;
  static const stockIn = AppPalette.success;
  static const stockOut = AppPalette.amberDark;
  static const danger = AppPalette.danger;
  static const info = AppPalette.info;
}

class UniformSearchBar extends StatefulWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final IconData? icon;

  const UniformSearchBar({
    super.key,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  State<UniformSearchBar> createState() => _UniformSearchBarState();
}

class _UniformSearchBarState extends State<UniformSearchBar> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant UniformSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
      _ctrl.selection = TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CampPalette.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CampPalette.border),
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(
              color: CampPalette.textTertiary, fontSize: 13),
          prefixIcon: Icon(widget.icon ?? Icons.search,
              size: 18, color: CampPalette.textSecondary),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear,
                      size: 16, color: CampPalette.textSecondary),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onChanged('');
                  },
                ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class UniformFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const UniformFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(selected ? 1 : 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(0.25)
                    : color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}

class UniformEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const UniformEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: CampPalette.input,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: CampPalette.textTertiary),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: CampPalette.textSecondary)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: CampPalette.textTertiary, fontSize: 12)),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

bool uniformMatchesQuery(String query, List<String> fields) {
  if (query.trim().isEmpty) return true;
  final q = query.trim().toLowerCase();
  return fields.any((f) => f.toLowerCase().contains(q));
}

String formatDateShort(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatDateTime(DateTime d) =>
    '${formatDateShort(d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
