// =============================================================================
// 💬 Daily Tips Dialog — يَظهَر بَعد مُطابَقة الوَجه وَقَبل تَسجيل الدُخول
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

class DailyTipsDialog extends StatefulWidget {
  final Employee employee;
  final Point currentPoint;
  final String? terminalAccountId;
  final String? deviceId;

  const DailyTipsDialog({
    super.key,
    required this.employee,
    required this.currentPoint,
    this.terminalAccountId,
    this.deviceId,
  });

  /// النَتيجة: true إذا أَكمَل المُوَظَّف وَيُمكِن المُتابَعة لِـ Clock-in
  static Future<bool> show(
    BuildContext context, {
    required Employee employee,
    required Point currentPoint,
    String? terminalAccountId,
    String? deviceId,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DailyTipsDialog(
        employee: employee,
        currentPoint: currentPoint,
        terminalAccountId: terminalAccountId,
        deviceId: deviceId,
      ),
    );
    return res == true;
  }

  @override
  State<DailyTipsDialog> createState() => _DailyTipsDialogState();
}

class _DailyTipsDialogState extends State<DailyTipsDialog> {
  bool _loading = true;
  Point? _yesterdayPoint;
  bool _wasAtDifferentPoint = false;
  late Point _confirmedPoint;
  String? _mood; // great | ok | tired | sick
  bool _hasEquipment = false;
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  bool _alreadySubmittedToday = false;

  @override
  void initState() {
    super.initState();
    _confirmedPoint = widget.currentPoint;
    _check();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // 1️⃣ هَل سَبَقَ أَن سَجَّل Tips اليَوم؟ → تَخَطّى الديالوغ
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final existing = await supa.client
          .from('daily_tips')
          .select('id')
          .eq('employee_id', widget.employee.id)
          .eq('shift_date', today)
          .maybeSingle();
      if (existing != null) {
        _alreadySubmittedToday = true;
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 2️⃣ هَل كان في نُقطة مُختَلِفة أَمس؟
      final res = await supa.client.rpc(
        'was_at_different_point_yesterday',
        params: {
          'p_employee_id': widget.employee.id,
          'p_current_point_id': widget.currentPoint.id,
        },
      );
      if (res is List && res.isNotEmpty) {
        final r = res.first as Map;
        _wasAtDifferentPoint = (r['was_different'] ?? false) as bool;
        final yId = r['yesterday_point_id'] as String?;
        if (yId != null) {
          _yesterdayPoint = MockRepository().pointById(yId);
        }
      }
    } catch (e) {
      M7Log.error('DailyTips', 'check', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final supa = SupabaseService();
    try {
      await supa.client.from('daily_tips').insert({
        'employee_id': widget.employee.id,
        'shift_date': DateTime.now().toIso8601String().substring(0, 10),
        'confirmed_point_id': _confirmedPoint.id,
        'default_point_id': widget.currentPoint.id,
        'point_changed': _confirmedPoint.id != widget.currentPoint.id,
        'mood': _mood,
        'has_equipment': _hasEquipment,
        'notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        if (widget.terminalAccountId != null)
          'terminal_account_id': widget.terminalAccountId,
        if (widget.deviceId != null) 'device_id': widget.deviceId,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      M7Log.error('DailyTips', 'save', error: e);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(e.toString()),
      ));
    }
  }

  Future<void> _changePoint() async {
    final repo = MockRepository();
    final all = repo.points
        .where((p) => p.countryId == widget.currentPoint.countryId)
        .toList();
    final picked = await showModalBottomSheet<Point>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(builder: (ctx, setSt) {
          final filtered = q.isEmpty
              ? all
              : all
                  .where((p) =>
                      p.name.toLowerCase().contains(q.toLowerCase()) ||
                      p.code.toLowerCase().contains(q.toLowerCase()))
                  .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بَحث…',
                      isDense: true,
                    ),
                    onChanged: (v) => setSt(() => q = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        leading: const Icon(Icons.place,
                            color: AppColors.brand),
                        title: Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                        subtitle: Text(p.code),
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    if (picked != null) {
      setState(() => _confirmedPoint = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;

    // إذا سَجَّل اليَوم بِالفِعل، اِسمَح بِالمُتابَعة فَوريّاً
    if (_alreadySubmittedToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
      return const SizedBox.shrink();
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== Header =====
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor:
                              AppColors.brand.withValues(alpha: 0.15),
                          child: Text(
                            widget.employee.fullName.isNotEmpty
                                ? widget.employee.fullName[0]
                                : '?',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: AppColors.brand),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr
                                    ? 'أَهلاً ${widget.employee.fullName}'
                                    : 'Welcome ${widget.employee.fullName}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${widget.employee.code} · ${widget.employee.jobTitle}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // ===== نُقطة العَمَل =====
                    Text(
                      isAr ? '📍 نُقطة العَمَل اليَوم' : '📍 Work point today',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.brand.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place, color: AppColors.brand),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_confirmedPoint.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(_confirmedPoint.code,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.edit, size: 14),
                            label: Text(
                                isAr ? 'تَغيير' : 'Change',
                                style: const TextStyle(fontSize: 11)),
                            onPressed: _changePoint,
                          ),
                        ],
                      ),
                    ),

                    // ===== تَنبيه أَمس =====
                    if (_wasAtDifferentPoint && _yesterdayPoint != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAr
                                    ? '⚠️ أَمس كُنت في «${_yesterdayPoint!.name}» — هَل تَغَيَّر مَوقِعك اليَوم؟'
                                    : '⚠️ Yesterday you were at «${_yesterdayPoint!.name}» — did your location change today?',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ===== المَزاج =====
                    Text(
                      isAr
                          ? '🎯 كَيف تَشعُر اليَوم؟ (اختِياريّ)'
                          : '🎯 How do you feel today? (optional)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _moodChip('great', '💪', isAr ? 'مُمتاز' : 'Great',
                            AppColors.success),
                        _moodChip('ok', '😐', isAr ? 'عاديّ' : 'OK',
                            AppColors.brand),
                        _moodChip('tired', '😩', isAr ? 'مُتعَب' : 'Tired',
                            AppColors.warning),
                        _moodChip('sick', '🤒', isAr ? 'مَريض' : 'Sick',
                            AppColors.danger),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ===== مَعَدَّات =====
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isAr
                            ? '🛠 هَل تَأتي مَع مَعَدَّات / أَدَوات؟'
                            : '🛠 Do you have equipment/tools?',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      value: _hasEquipment,
                      onChanged: (v) => setState(() => _hasEquipment = v),
                    ),
                    const SizedBox(height: 8),

                    // ===== مُلاحَظات =====
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: isAr
                            ? '📝 مُلاحَظات (اختِياريّ)'
                            : '📝 Notes (optional)',
                        hintText: isAr
                            ? 'تَحَدِّيات، أَولَوِيّات، مَلاحَظات…'
                            : 'Challenges, priorities, notes…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // ===== Save =====
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle, size: 20),
                      label: Text(
                        isAr ? '✅ أَكمِل تَسجيل الدُخول' : '✅ Continue to Clock-in',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                            isAr ? 'إلغاء' : 'Cancel',
                            style:
                                TextStyle(color: Colors.grey.shade600)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _moodChip(String key, String emoji, String label, Color c) {
    final selected = _mood == key;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _mood = selected ? null : key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? c.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? c : Colors.grey.shade300,
                  width: selected ? 2 : 1),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: selected ? c : Colors.grey.shade700,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
