// =============================================================================
// 🤖 AiInsightsService — تَحليل ذَكيّ بِاستِخدام OpenAI/Anthropic API
// =============================================================================
// **مَبدَأ:** نَأخُذ بَيانات مُلَخَّصة (لا سَجِلّات فَردِيّة كامِلة لِأَجل الخُصوصيّة
// وَحَجم الـpayload)، نُرسِلها مَع prompt واضِح لِـmodel، وَنَستَلِم تَحليلاً
// نَصِّيّاً.
//
// **API key sources:**
//   1. `--dart-define=OPENAI_API_KEY=...` (build-time)
//   2. `app_settings['ai_api_key']` (runtime)
//
// **المُوَفِّر:** افتِراضيّاً OpenAI (`gpt-4o-mini` — سَريع وَرَخيص). يَدعَم
// أَنثروبيك لاحِقاً عَبر تَغيير `_endpoint` + headers.
//
// **خُصوصيّة:** لا نُرسِل أَسماء/إيميلات/بَيانات تَعريفيّة — فَقَط مُلَخَّصات
// رَقمِيّة وَفئوِيّة.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_settings_service.dart';
import 'error_tracking_service.dart';

const String _kApiKeySettingsKey = 'ai_api_key';
const String _kApiKeyFromBuild =
    String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

class AiInsightResult {
  final bool ok;
  final String text;
  final String? error;
  final Map<String, dynamic>? usage;

  const AiInsightResult({
    required this.ok,
    required this.text,
    this.error,
    this.usage,
  });

  factory AiInsightResult.failure(String error) =>
      AiInsightResult(ok: false, text: '', error: error);
}

class AiInsightsService {
  AiInsightsService._();
  static final AiInsightsService instance = AiInsightsService._();

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';

  String? _cachedKey;

  /// اِقرَأ مِفتاح API
  Future<String?> _readApiKey() async {
    if (_kApiKeyFromBuild.isNotEmpty) return _kApiKeyFromBuild;
    if (_cachedKey != null) return _cachedKey;
    try {
      final row = await AppSettingsService.instance.getJson(_kApiKeySettingsKey);
      final v = row?['value'];
      if (v is String && v.isNotEmpty) {
        _cachedKey = v;
        return v;
      }
    } catch (_) {/* تَجاهُل */}
    return null;
  }

  /// خُذ مِفتاح API جَديد (مِن لَوحة الإعدادات) — مُتَوَفِّر بَعد إعادة التَهيئَة
  Future<void> setApiKey(String key) async {
    _cachedKey = null; // لِنُجبِر إعادة القِراءة
    await AppSettingsService.instance.setJson(
      _kApiKeySettingsKey,
      {'value': key},
    );
  }

  /// هَل المِفتاح مُهَيَّأ؟
  Future<bool> isConfigured() async {
    final k = await _readApiKey();
    return k != null && k.isNotEmpty;
  }

  // ==========================================================================
  // 🎯 العَمَلِيّة الأَساسيّة — اِسأَل المُوَفِّر
  // ==========================================================================
  Future<AiInsightResult> ask({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.4,
    int maxTokens = 800,
  }) async {
    final key = await _readApiKey();
    if (key == null || key.isEmpty) {
      return AiInsightResult.failure(
          'OpenAI API key not configured. Add it in Settings → AI Insights.');
    }
    try {
      final body = jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': temperature,
        'max_tokens': maxTokens,
      });
      final resp = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: body,
      );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('AI Insights HTTP ${resp.statusCode}: ${resp.body}');
        }
        return AiInsightResult.failure(
            'HTTP ${resp.statusCode}: ${_extractError(resp.body)}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final text = (((json['choices'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .firstOrNull?['message'] as Map?)?['content']
          ?.toString()
          ?.trim();
      return AiInsightResult(
        ok: true,
        text: text ?? '',
        usage: (json['usage'] as Map?)?.cast<String, dynamic>(),
      );
    } catch (e, st) {
      ErrorTrackingService.instance
          .captureException(e, st, context: {'where': 'AiInsightsService.ask'});
      return AiInsightResult.failure(e.toString());
    }
  }

  String _extractError(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map) return (err['message'] ?? '').toString();
    } catch (_) {}
    return body.length > 120 ? '${body.substring(0, 120)}…' : body;
  }
}
