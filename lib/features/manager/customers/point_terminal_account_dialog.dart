import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/m7_log.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';

/// 🏪 حِوار إنشاء/إعادة تَوليد حِساب جِهاز النُقطة
///
/// يَفحَص إذا كان لِلنُقطة حِساب Terminal مُسبَقاً:
///   - لا → يَعرِض زِرّ "إنشاء" + كَلِمة مُرور عَشوائيّة جَديدة
///   - نَعَم → يَعرِض اسم المُستَخدِم + خِيار "إعادة تَوليد كَلِمة المُرور"
class PointTerminalAccountDialog extends StatefulWidget {
  final Point point;
  const PointTerminalAccountDialog({super.key, required this.point});

  @override
  State<PointTerminalAccountDialog> createState() =>
      _PointTerminalAccountDialogState();
}

class _PointTerminalAccountDialogState
    extends State<PointTerminalAccountDialog> {
  bool _busy = false;
  String? _newPassword; // يَظهَر بَعدَ الإنشاء/إعادة التَوليد
  AppAccount? _existing;
  // 🆕 الحَدّ الأَقصى لِلأَجهِزة (0 = بِدون حَدّ)
  int _maxDevices = 0;

  @override
  void initState() {
    super.initState();
    _findExisting();
    if (_existing != null) {
      _maxDevices = _existing!.maxDevices;
    }
  }

  void _findExisting() {
    final repo = MockRepository();
    try {
      _existing = repo.accounts.firstWhere(
        (a) =>
            a.accountType == AccountType.pointTerminal &&
            a.pointId == widget.point.id,
      );
    } catch (_) {
      _existing = null;
    }
  }

  String _generatePassword() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const small = 'abcdefghjkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$%&*';
    final r = Random.secure();
    return [
      letters[r.nextInt(letters.length)],
      small[r.nextInt(small.length)],
      small[r.nextInt(small.length)],
      digits[r.nextInt(digits.length)],
      digits[r.nextInt(digits.length)],
      letters[r.nextInt(letters.length)],
      small[r.nextInt(small.length)],
      digits[r.nextInt(digits.length)],
      symbols[r.nextInt(symbols.length)],
      letters[r.nextInt(letters.length)],
    ].join();
  }

  /// اسم المُستَخدِم المُقتَرَح: term-{point_code}
  String _suggestedUsername() {
    final code = widget.point.code.trim();
    if (code.isNotEmpty) return 'term-${code.toLowerCase()}';
    // fallback: term-{id-prefix}
    return 'term-${widget.point.id.substring(0, 8)}';
  }

  Future<void> _createTerminal() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      _snack(
          isAr: AppStrings.of(context).isAr,
          ok: false,
          msg: 'يَجِب الاتّصال بِـSupabase');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = MockRepository();
      final username = _suggestedUsername();

      // فَحص تَكرار اسم المُستَخدِم
      final dup = repo.accounts
          .any((a) => a.username.toLowerCase() == username.toLowerCase());
      if (dup) {
        _snack(
            isAr: AppStrings.of(context).isAr,
            ok: false,
            msg: 'اسم المُستَخدِم مُستَخدَم — احذِف الحِساب القَديم أَوَّلاً');
        return;
      }

      final pass = _generatePassword();
      final acc = AppAccount(
        id: repo.generateId(),
        username: username,
        passwordHash: pass,
        fullName: '${widget.point.name} Terminal',
        isActive: true,
        accountType: AccountType.pointTerminal,
        pointId: widget.point.id,
        // 🆕 الحَدّ الأَقصى لِلأَجهِزة (0 = بِدون حَدّ)
        maxDevices: _maxDevices,
      );

      // أَنشِئ بِدون أَدوار وَلا دُوَل (الحِساب يَستَخدِم accountType لِلتَوجيه)
      final created = await SupabaseDataService().createAccount(
        acc,
        roleIds: const [],
        countryIds: widget.point.countryId == null
            ? const []
            : [widget.point.countryId!],
      );

      if (created == null) {
        _snack(
            isAr: AppStrings.of(context).isAr,
            ok: false,
            msg: 'فَشِل الإنشاء');
        return;
      }

      _findExisting(); // أَعِد التَحميل
      if (!mounted) return;
      setState(() {
        _newPassword = pass;
      });
    } catch (e) {
      M7Log.error('PointTerminalDialog', 'create', error: e);
      _snack(
          isAr: AppStrings.of(context).isAr, ok: false, msg: 'خَطَأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🆕 يَحفَظ تَغيير الحَدّ الأَقصى لِلأَجهِزة
  Future<void> _saveMaxDevices(int newMax) async {
    final supa = SupabaseService();
    if (!supa.isReady || _existing == null) return;
    setState(() => _busy = true);
    try {
      await supa.client.from('accounts').update({
        'max_devices': newMax,
      }).eq('id', _existing!.id);
      _existing!.maxDevices = newMax;
      _maxDevices = newMax;
      if (!mounted) return;
      _snack(
          isAr: AppStrings.of(context).isAr,
          ok: true,
          msg: AppStrings.of(context).isAr
              ? '✅ تَمَّ الحِفظ'
              : '✅ Saved');
    } catch (e) {
      M7Log.error('PointTerminalDialog', 'saveMaxDevices', error: e);
      _snack(
          isAr: AppStrings.of(context).isAr,
          ok: false,
          msg: 'خَطَأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regeneratePassword() async {
    final supa = SupabaseService();
    if (!supa.isReady || _existing == null) return;
    setState(() => _busy = true);
    try {
      final pass = _generatePassword();
      await supa.client.from('accounts').update({
        'password_hash': pass,
        'auth_user_id': null, // أَعِد التَهيِئة لِلاسْتِخدام عَبر password_hash
        'linked_device_id': null, // إِفصِل الجِهاز القَديم
      }).eq('id', _existing!.id);
      _existing!.passwordHash = pass;
      _existing!.linkedDeviceId = null;
      if (!mounted) return;
      setState(() => _newPassword = pass);
    } catch (e) {
      M7Log.error('PointTerminalDialog', 'regenerate', error: e);
      _snack(
          isAr: AppStrings.of(context).isAr, ok: false, msg: 'خَطَأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTerminal() async {
    if (_existing == null) return;
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? 'حَذف حِساب الجِهاز' : 'Delete Terminal'),
        content: Text(isAr
            ? 'سَيَتِم حَذف حِساب الجِهاز نِهائيّاً. لا يَتَأَثَّر سِجِلّ الدَوام.'
            : 'Terminal account will be permanently deleted. Attendance history is kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(isAr ? 'حَذف' : 'Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final supa = SupabaseService();
      if (supa.isReady) {
        await supa.client.from('accounts').delete().eq('id', _existing!.id);
      }
      MockRepository().accounts.removeWhere((a) => a.id == _existing!.id);
      MockRepository().notifyListeners();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      M7Log.error('PointTerminalDialog', 'delete', error: e);
      _snack(isAr: isAr, ok: false, msg: 'خَطَأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack({required bool isAr, required bool ok, required String msg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(msg),
    ));
  }

  Future<void> _copyCredentials() async {
    if (_existing == null || _newPassword == null) return;
    final text = '''
🏪 ${widget.point.name}

اسم المُستَخدِم: ${_existing!.username}
كَلِمة المُرور: $_newPassword

(احفَظها — لَن تَظهَر مَرّة أُخرى)
''';
    await Clipboard.setData(ClipboardData(text: text));
    _snack(isAr: true, ok: true, msg: 'تَمَّ النَسخ');
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    // 🆕 صَلاحيّة الحَذف مُنفَصِلة عَن الإدارة العاديّة
    final auth = context.watch<AuthProvider>();
    final canDelete = auth.isSuperAdmin ||
        auth.permissions.contains(P.pointTerminalDelete);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.storefront, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr ? 'حِساب جِهاز النُقطة' : 'Terminal Account',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اسم النُقطة
            Text(
              '📍 ${widget.point.name}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.point.code,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),

            if (_existing == null) ...[
              // لا حِساب — اعرِض زِرّ الإنشاء
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.info.withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'لا حِساب جِهاز لِهذِه النُقطة. سَيُنشَأ بِاسم مُستَخدِم: ${_suggestedUsername()}'
                            : 'No terminal account exists. Will create with username: ${_suggestedUsername()}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _createTerminal,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  isAr ? 'إنشاء حِساب الجِهاز' : 'Create Terminal Account',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ] else ...[
              // الحِساب مَوجود
              _kv(
                  isAr ? 'اسم المُستَخدِم' : 'Username', _existing!.username),
              if (_newPassword != null) ...[
                _kv(isAr ? 'كَلِمة المُرور' : 'Password', _newPassword!,
                    highlight: true),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? '⚠ احفَظ كَلِمة المُرور الآن — لَن تَظهَر مَرّة أُخرى.'
                              : '⚠ Save the password now — it will not be shown again.',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _copyCredentials,
                  icon: const Icon(Icons.copy),
                  label: Text(isAr ? 'نَسخ' : 'Copy'),
                ),
              ],
              const SizedBox(height: 16),
              if (_existing!.linkedDeviceId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.devices,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr
                                ? 'مَربوط بِجِهاز: ${_existing!.linkedDeviceId!.substring(0, 12)}…'
                                : 'Linked device: ${_existing!.linkedDeviceId!.substring(0, 12)}…',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // 🆕 الحَدّ الأَقصى لِلأَجهِزة المَربوطة
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.info.withValues(alpha: 0.20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.devices_other,
                            color: AppColors.info, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr
                                ? 'الحَدّ الأَقصى لِلأَجهِزة'
                                : 'Max devices',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _maxDevices == 0
                                ? (isAr ? 'بِدون حَدّ' : 'Unlimited')
                                : '$_maxDevices',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w900,
                                color: AppColors.gold,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _maxDevices.toDouble(),
                      min: 0,
                      max: 20,
                      divisions: 20,
                      label: _maxDevices == 0
                          ? (isAr ? 'بِدون حَدّ' : 'Unlimited')
                          : '$_maxDevices',
                      onChanged: (v) =>
                          setState(() => _maxDevices = v.toInt()),
                      onChangeEnd: (_) => _saveMaxDevices(_maxDevices),
                    ),
                    Text(
                      isAr
                          ? '0 = بِدون حَدّ · يَنطَبِق فَوراً'
                          : '0 = unlimited · applied immediately',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _regeneratePassword,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                          isAr ? 'إعادة تَوليد' : 'Regenerate'),
                    ),
                  ),
                  if (canDelete) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _busy ? null : _deleteTerminal,
                      icon: const Icon(Icons.delete,
                          color: AppColors.danger),
                      tooltip: isAr ? 'حَذف' : 'Delete',
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إغلاق' : 'Close'),
        ),
      ],
    );
  }

  Widget _kv(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: highlight
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  color: highlight ? Colors.black : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
