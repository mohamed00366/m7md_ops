// =============================================================================
// 📋 Employee Deductions Screen — sees their own deductions + can sign pending
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/services/deductions_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/signature_pad.dart';

class EmployeeDeductionsScreen extends StatefulWidget {
  const EmployeeDeductionsScreen({super.key});

  @override
  State<EmployeeDeductionsScreen> createState() =>
      _EmployeeDeductionsScreenState();
}

class _EmployeeDeductionsScreenState
    extends State<EmployeeDeductionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeductionsService.instance.refresh();
    });
  }

  Color _categoryColor(String c) {
    switch (c) {
      case 'theft':
        return Colors.red.shade900;
      case 'fighting':
      case 'misconduct':
        return Colors.red.shade700;
      case 'late_return':
      case 'absence':
        return Colors.orange.shade700;
      case 'damage':
      case 'manual_ticket':
        return Colors.amber.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  String _categoryLabel(String c) {
    const labels = {
      'late_return':    '🏖 تَأَخُّر مِن إجازة',
      'absence':        '❌ غِياب',
      'theft':          '🚨 سَرِقة',
      'fighting':       '⚠ شِجار',
      'misconduct':     '⚠ سُلوك سَيِّء',
      'manual_ticket':  '🎫 تَذكَرة يَدَويّة',
      'damage':         '🔧 إتلاف',
      'other':          '📋 أُخرى',
    };
    return labels[c] ?? c;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final empId = auth.account?.employeeId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 خَصوماتي'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => DeductionsService.instance.refresh(),
          ),
        ],
      ),
      body: empId == null
          ? const Center(child: Text('حِسابك غَير مَربوط بِمُوَظَّف'))
          : ChangeNotifierProvider.value(
              value: DeductionsService.instance,
              child: Consumer<DeductionsService>(
                builder: (_, svc, __) {
                  if (svc.loading) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final mine = svc.forEmployee(empId);
                  if (mine.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          '✅ لا تُوجَد خَصومات — أَحسَنت!',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  }
                  final unsigned = mine.where((d) => !d.isSigned).toList();
                  final signed   = mine.where((d) => d.isSigned).toList();

                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (unsigned.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.warning.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.draw,
                                  color: AppColors.warning, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'لَدَيك ${unsigned.length} خَصم بانتِظار تَوقيعِك',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final d in unsigned)
                          _DeductionCard(
                            d: d,
                            color: _categoryColor(d.category),
                            label: _categoryLabel(d.category),
                            onTap: () => _openSign(d),
                          ),
                        if (signed.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'الخَصومات المُوَقَّعة',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                      for (final d in signed)
                        _DeductionCard(
                          d: d,
                          color: _categoryColor(d.category),
                          label: _categoryLabel(d.category),
                          onTap: null,
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Future<void> _openSign(Deduction d) async {
    final auth = context.read<AuthProvider>();
    final accountId = auth.account?.id;
    if (accountId == null) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SignDeductionDialog(
        deduction: d,
        accountId: accountId,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text('✓ تَمّ تَوقيع الخَصم ${d.warningNumber ?? ""}'),
      ));
    }
  }
}

class _DeductionCard extends StatelessWidget {
  final Deduction d;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  const _DeductionCard({
    required this.d,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      d.warningNumber ?? '—',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                  Text(
                    '${d.amount.toStringAsFixed(0)} ${d.currency}',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (d.reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(d.reason,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event,
                      size: 11, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${d.appliedAt.year}-${d.appliedAt.month.toString().padLeft(2, '0')}-${d.appliedAt.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  if (d.isSigned)
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 14),
                        const SizedBox(width: 3),
                        Text('مُوَقَّع',
                            style: TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.draw, color: AppColors.warning, size: 14),
                        const SizedBox(width: 3),
                        Text('بانتِظار التَوقيع',
                            style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sign deduction dialog
// =============================================================================
class _SignDeductionDialog extends StatefulWidget {
  final Deduction deduction;
  final String accountId;
  const _SignDeductionDialog({
    required this.deduction,
    required this.accountId,
  });

  @override
  State<_SignDeductionDialog> createState() => _SignDeductionDialogState();
}

class _SignDeductionDialogState extends State<_SignDeductionDialog> {
  final _signKey = GlobalKey<SignaturePadState>();
  bool _hasSig = false;
  bool _ack = false;
  bool _saving = false;

  Future<void> _save() async {
    if (!_ack || !_hasSig) return;
    setState(() => _saving = true);
    final png = await _signKey.currentState?.exportPng();
    if (png == null || png.isEmpty) {
      setState(() => _saving = false);
      return;
    }
    final ok = await DeductionsService.instance.sign(
      deductionId: widget.deduction.id,
      signatureBase64: png,
      signedByAccountId: widget.accountId,
    );
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deduction;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        d.warningNumber ?? '—',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('📋 إقرار وَتَوقيع',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('المَبلَغ',
                          '${d.amount.toStringAsFixed(0)} ${d.currency}'),
                      _row('النَوع', d.category),
                      _row('السَبَب', d.reason),
                      _row(
                        'التاريخ',
                        '${d.appliedAt.year}-${d.appliedAt.month.toString().padLeft(2, '0')}-${d.appliedAt.day.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  value: _ack,
                  onChanged: (v) => setState(() => _ack = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'أُقِرّ بِأَنّني اطَّلَعت عَلى الخَصم وَأُوافِق عَلَيه',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '🖊 وَقِّع في المُرَبَّع أَدناه:',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SignaturePad(
                  key: _signKey,
                  height: 180,
                  onChanged: (has) => setState(() => _hasSig = has),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _signKey.currentState?.clear(),
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('مَسح',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('لاحِقاً'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (_ack && _hasSig && !_saving)
                                  ? AppColors.success
                                  : Colors.grey,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed:
                            (_ack && _hasSig && !_saving) ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle),
                        label: const Text('✍ تَأكيد وَتَوقيع',
                            style: TextStyle(
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
}
