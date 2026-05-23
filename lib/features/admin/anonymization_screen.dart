// =============================================================================
// 🔒 شاشة إخفاء هُوِيّة المُوَظَّفين (GDPR / Right to be Forgotten)
// =============================================================================
// Super Admin فَقَط — يَعرِض قائِمة المُوَظَّفين المُؤَهَّلين (المَفصولين/المُستَقيلين > 12 شَهر)
// مَع زِرّ "إخفاء هُوِيّة" لِكُلّ مِنهُم.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_empty_state.dart';
import '../../shared/m7_help_tooltip.dart';

class AnonymizationScreen extends StatefulWidget {
  const AnonymizationScreen({super.key});

  @override
  State<AnonymizationScreen> createState() => _AnonymizationScreenState();
}

class _Candidate {
  final String employeeId;
  final String code;
  final String name;
  final String status;
  final DateTime? deactivated;
  final int daysInactive;

  const _Candidate({
    required this.employeeId,
    required this.code,
    required this.name,
    required this.status,
    this.deactivated,
    required this.daysInactive,
  });

  factory _Candidate.fromRow(Map<String, dynamic> r) => _Candidate(
        employeeId: r['employee_id'] as String,
        code: r['employee_code'] as String? ?? '',
        name: r['full_name'] as String? ?? '?',
        status: r['status'] as String? ?? '?',
        deactivated: r['deactivated'] == null
            ? null
            : DateTime.tryParse(r['deactivated'] as String),
        daysInactive: (r['days_inactive'] as num?)?.toInt() ?? 0,
      );
}

class _AnonymizationScreenState extends State<AnonymizationScreen> {
  bool _loading = true;
  List<_Candidate> _candidates = const [];
  int _months = 12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await supa.client.rpc(
        'list_anonymization_candidates',
        params: {'p_terminated_months_ago': _months},
      );
      if (res is List) {
        _candidates = res
            .map((r) =>
                _Candidate.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
      }
    } catch (e) {
      M7Log.error('Anonymization', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _anonymize(_Candidate c) async {
    final isAr = AppStrings.of(context).isAr;
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_outlined,
            color: AppColors.danger, size: 40),
        title: Text(isAr ? '⚠ إخفاء هُوِيّة دائِم' : '⚠ Permanent Anonymization'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAr
                    ? 'سَتُحذَف كُلّ بَيانات "${c.name}" الشَخصيّة نِهائيّاً:'
                    : 'All personal data of "${c.name}" will be permanently erased:',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? '• الاسم، الجَواز، الإقامة، الرُخصة\n• الجَوّال، البَريد، العُنوان\n• كُلّ المُلَفّات المُرفَقة\n• حِسابه يُعَطَّل وَ اسم المُستَخدِم يُخفى'
                    : '• Name, passport, EID, license\n• Phone, email, address\n• All attached files\n• Account deactivated + username anonymized',
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? '✓ يُحتَفَظ بِالكود "${c.code}" + الإدارة + التَواريخ لِأَغراض التَدقيق.'
                    : '✓ Code "${c.code}" + dept + dates preserved for audit purposes.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.success),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isAr ? 'سَبَب الإخفاء *' : 'Reason *',
                  hintText: isAr
                      ? 'مَثَلاً: طَلَب رَسميّ مِن المُوَظَّف'
                      : 'e.g., Formal request from employee',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: Text(isAr ? 'تَأكيد الإخفاء' : 'Confirm Anonymize'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = SupabaseService();
    final auth = context.read<AuthProvider>();
    try {
      await supa.client.rpc('anonymize_employee', params: {
        'p_employee_id': c.employeeId,
        'p_reason': reasonCtrl.text.trim(),
        'p_anonymized_by': auth.account?.id,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.success,
          content: Text(isAr
              ? '✅ تَمّ إخفاء هُوِيّة ${c.name}'
              : '✅ ${c.name} anonymized'),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(isAr ? 'فَشِل: $e' : 'Failed: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    if (auth.account?.isSuperAdmin != true) {
      return Scaffold(
        appBar: M7AppBar(
            title: isAr
                ? '🔒 إخفاء هُوِيّة المُوَظَّفين'
                : '🔒 Anonymization'),
        body: M7EmptyState(
          icon: Icons.lock,
          titleAr: 'هذه الشاشة لِـSuper Admin فَقَط',
          titleEn: 'Super Admin only',
        ),
      );
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🔒 إخفاء هُوِيّة المُوَظَّفين' : '🔒 Anonymization',
        subtitle: isAr
            ? '${_candidates.length} مُؤَهَّل (مَفصول > $_months شَهر)'
            : '${_candidates.length} eligible (terminated > $_months mo)',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          M7HelpInfoCard(
            color: AppColors.danger,
            icon: Icons.warning_amber_outlined,
            titleAr: '⚠ تَحذير قانونيّ',
            titleEn: '⚠ Legal Warning',
            messageAr:
                'الإخفاء عَمَليّة لا رَجعة فيها. تُسَجَّل في anonymization_log لِلتَدقيق. يَجِب أَن تَكون مَبنيّة عَلى طَلَب رَسميّ مِن المُوَظَّف (GDPR Right to be Forgotten).',
            messageEn:
                'Anonymization is irreversible. Logged in anonymization_log for audit. Must be based on formal GDPR-style request from employee.',
          ),
          // ===== فِلتَر الفَترة =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(isAr
                    ? 'المَفصولون مُنذ أَكثَر مِن:'
                    : 'Terminated more than:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _months,
                  items: const [
                    DropdownMenuItem(value: 6, child: Text('6')),
                    DropdownMenuItem(value: 12, child: Text('12')),
                    DropdownMenuItem(value: 24, child: Text('24')),
                    DropdownMenuItem(value: 36, child: Text('36')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _months = v);
                      _load();
                    }
                  },
                ),
                const SizedBox(width: 4),
                Text(isAr ? 'شَهر' : 'months'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                    ? M7EmptyState(
                        icon: Icons.verified_user_outlined,
                        titleAr: 'لا يَوجَد مُوَظَّفون مُؤَهَّلون',
                        titleEn: 'No eligible employees',
                        subtitleAr:
                            'كُلّ المَفصولين/المُستَقيلين أَحدَث مِن $_months شَهر',
                        subtitleEn:
                            'All terminated/resigned within $_months months',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _candidates.length,
                        itemBuilder: (_, i) => _CandidateTile(
                          candidate: _candidates[i],
                          isAr: isAr,
                          onAnonymize: () => _anonymize(_candidates[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final _Candidate candidate;
  final bool isAr;
  final VoidCallback onAnonymize;
  const _CandidateTile({
    required this.candidate,
    required this.isAr,
    required this.onAnonymize,
  });

  @override
  Widget build(BuildContext context) {
    final yrs = (candidate.daysInactive / 365).toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: candidate.status == 'terminated'
                  ? AppColors.danger.withValues(alpha: 0.1)
                  : AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              candidate.status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: candidate.status == 'terminated'
                    ? AppColors.danger
                    : AppColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text(
                  '${candidate.code} • ${isAr ? "خامِل" : "inactive"} $yrs ${isAr ? "سَنة" : "yrs"}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.privacy_tip_outlined,
                color: AppColors.danger),
            tooltip: isAr ? 'إخفاء هُوِيّة' : 'Anonymize',
            onPressed: onAnonymize,
          ),
        ],
      ),
    );
  }
}
