// =============================================================================
// 🤖 شاشة AI Insights — تَحليلات ذَكيّة بِناءً عَلى بَيانات M7
// =============================================================================
// خَطَوات الـUI:
//   1. عَرض حالة الـAPI key (مُهَيَّأ / غَير مُهَيَّأ)
//   2. زِرّ لِإضافة/تَعديل المِفتاح
//   3. قائمة الـ3 تَحليلات الجاهِزة كَـcards
//   4. اضغَط card → يُشَغِّل التَحليل وَيَعرِض النَتيجة كَـMarkdown بَسيط
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/ai_insights_builtin.dart';
import '../../core/services/ai_insights_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  bool _configured = false;
  bool _checking = true;
  BuiltinInsight? _running;
  Map<BuiltinInsight, AiInsightResult> _results = {};

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    final c = await AiInsightsService.instance.isConfigured();
    if (mounted) {
      setState(() {
        _configured = c;
        _checking = false;
      });
    }
  }

  Future<void> _editApiKey() async {
    final s = AppStrings.of(context);
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? 'مِفتاح OpenAI API' : 'OpenAI API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.isAr
                  ? 'احصَل عَلَيه مِن platform.openai.com → API keys'
                  : 'Get it from platform.openai.com → API keys',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'sk-...',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'حِفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await AiInsightsService.instance.setApiKey(controller.text.trim());
      await _checkConfig();
    }
  }

  Future<void> _run(BuiltinInsight key) async {
    final isAr = AppStrings.of(context).isAr;
    setState(() => _running = key);
    try {
      final result = await AiInsightsBuiltin.run(key, isAr: isAr);
      if (mounted) {
        setState(() {
          _results = {..._results, key: result};
          _running = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🤖 رُؤى ذَكيّة' : '🤖 AI Insights',
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key),
            onPressed: _editApiKey,
            tooltip: isAr ? 'تَعديل المِفتاح' : 'Edit key',
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _StatusBanner(
                    configured: _configured, isAr: isAr, onEdit: _editApiKey),
                const SizedBox(height: 16),
                Text(
                  isAr ? 'تَحليلات جاهِزة' : 'Built-in insights',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ...kBuiltinInsights.map((def) => _InsightCard(
                      def: def,
                      isAr: isAr,
                      running: _running == def.key,
                      anythingRunning: _running != null,
                      result: _results[def.key],
                      onRun: _configured ? () => _run(def.key) : null,
                    )),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.privacy_tip,
                          size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'الخُصوصيّة: نُرسِل أَرقاماً مُلَخَّصة فَقَط — لا أَسماء، لا إيميلات، لا بَيانات تَعريفيّة لِلمُوَظَّفين.'
                              : 'Privacy: We send only aggregate numbers — no names, emails, or personally-identifying employee data.',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool configured;
  final bool isAr;
  final VoidCallback onEdit;
  const _StatusBanner(
      {required this.configured, required this.isAr, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final color = configured ? Colors.green.shade700 : Colors.orange.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(configured ? Icons.check_circle : Icons.warning_amber,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured
                      ? (isAr ? 'جاهِز' : 'Ready')
                      : (isAr
                          ? 'مِفتاح API غَير مُهَيَّأ'
                          : 'API key not configured'),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800),
                ),
                if (!configured) ...[
                  const SizedBox(height: 2),
                  Text(
                    isAr
                        ? 'اضغَط لِإضافة مِفتاح OpenAI API'
                        : 'Tap to add an OpenAI API key',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (!configured)
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.vpn_key, size: 16),
              label: Text(isAr ? 'إضافة' : 'Add'),
            ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final BuiltinInsightDef def;
  final bool isAr;
  final bool running;
  final bool anythingRunning;
  final AiInsightResult? result;
  final VoidCallback? onRun;
  const _InsightCard({
    required this.def,
    required this.isAr,
    required this.running,
    required this.anythingRunning,
    required this.result,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(def.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.title(isAr),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(def.desc(isAr),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[700])),
                    ],
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  FilledButton.icon(
                    onPressed:
                        anythingRunning || onRun == null ? null : onRun,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(isAr ? 'شَغِّل' : 'Run'),
                  ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (result!.ok)
                SelectableText(
                  result!.text,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result!.error ?? 'Unknown error',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
