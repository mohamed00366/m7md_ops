// =============================================================================
// 🎬 SplashVideoSettings — إعدادات فيديو الترحيب
// =============================================================================
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// تَكرار عَرض الفيديو
enum SplashShowFrequency {
  /// كُلّ مَرَّة يُفتَح التَطبيق
  everyTime,
  /// مَرَّة واحِدة في الجَلسة (browser session)
  session,
  /// مَرَّة في اليَوم
  daily,
  /// مَرَّة في الأُسبوع
  weekly,
  /// لَن يَظهَر أَبَداً
  never,
}

extension SplashShowFrequencyX on SplashShowFrequency {
  String get key {
    switch (this) {
      case SplashShowFrequency.everyTime:
        return 'every_time';
      case SplashShowFrequency.session:
        return 'session';
      case SplashShowFrequency.daily:
        return 'daily';
      case SplashShowFrequency.weekly:
        return 'weekly';
      case SplashShowFrequency.never:
        return 'never';
    }
  }

  String labelAr() {
    switch (this) {
      case SplashShowFrequency.everyTime:
        return 'كُلّ مَرَّة';
      case SplashShowFrequency.session:
        return 'مَرَّة في الجَلسة';
      case SplashShowFrequency.daily:
        return 'مَرَّة في اليَوم';
      case SplashShowFrequency.weekly:
        return 'مَرَّة في الأُسبوع';
      case SplashShowFrequency.never:
        return 'لا يَظهَر';
    }
  }

  String labelEn() {
    switch (this) {
      case SplashShowFrequency.everyTime:
        return 'Every time';
      case SplashShowFrequency.session:
        return 'Once per session';
      case SplashShowFrequency.daily:
        return 'Once a day';
      case SplashShowFrequency.weekly:
        return 'Once a week';
      case SplashShowFrequency.never:
        return 'Never';
    }
  }

  static SplashShowFrequency fromKey(String? k) {
    switch (k) {
      case 'session':
        return SplashShowFrequency.session;
      case 'daily':
        return SplashShowFrequency.daily;
      case 'weekly':
        return SplashShowFrequency.weekly;
      case 'never':
        return SplashShowFrequency.never;
      case 'every_time':
      default:
        return SplashShowFrequency.everyTime;
    }
  }
}

/// مَوديل الإعدادات
class SplashVideoConfig {
  final bool enabled;
  final String? videoUrl;       // مِن Supabase Storage — لا فيديو بِدونها
  final String? audioUrl;       // 🆕 مِلَفّ صَوت مُنفَصِل (اختِياريّ)
  final int maxDurationSeconds;
  final bool autoUnmute;
  final SplashShowFrequency showFrequency;

  const SplashVideoConfig({
    this.enabled = true,
    this.videoUrl,
    this.audioUrl,
    this.maxDurationSeconds = 15,
    this.autoUnmute = false,
    this.showFrequency = SplashShowFrequency.everyTime,
  });

  /// هَل لَدَيها فيديو فِعليّ قابِل لِلعَرض؟
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'video_url': videoUrl,
        'audio_url': audioUrl,
        'max_duration_seconds': maxDurationSeconds,
        'auto_unmute': autoUnmute,
        'show_frequency': showFrequency.key,
      };

  factory SplashVideoConfig.fromJson(Map<String, dynamic> j) =>
      SplashVideoConfig(
        enabled: j['enabled'] as bool? ?? true,
        videoUrl: j['video_url'] as String?,
        audioUrl: j['audio_url'] as String?,
        maxDurationSeconds:
            (j['max_duration_seconds'] as num?)?.toInt() ?? 15,
        autoUnmute: j['auto_unmute'] as bool? ?? false,
        showFrequency: SplashShowFrequencyX.fromKey(
            j['show_frequency'] as String?),
      );

  SplashVideoConfig copyWith({
    bool? enabled,
    String? videoUrl,
    String? audioUrl,
    int? maxDurationSeconds,
    bool? autoUnmute,
    SplashShowFrequency? showFrequency,
    bool clearVideoUrl = false,
    bool clearAudioUrl = false,
  }) {
    return SplashVideoConfig(
      enabled: enabled ?? this.enabled,
      videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
      audioUrl: clearAudioUrl ? null : (audioUrl ?? this.audioUrl),
      maxDurationSeconds: maxDurationSeconds ?? this.maxDurationSeconds,
      autoUnmute: autoUnmute ?? this.autoUnmute,
      showFrequency: showFrequency ?? this.showFrequency,
    );
  }
}

/// خِدمة لِقِراءَة/كِتابة الإعدادات
class SplashVideoSettings {
  SplashVideoSettings._();
  static final instance = SplashVideoSettings._();

  static const _settingsKey = 'splash_video';

  String? lastError;
  SplashVideoConfig _cached = const SplashVideoConfig();
  bool _loaded = false;

  /// تَحميل الإعدادات (مَع cache)
  Future<SplashVideoConfig> load({bool forceReload = false}) async {
    if (_loaded && !forceReload) return _cached;
    try {
      final c = SupabaseService().client;
      final row = await c
          .from('app_settings')
          .select('value_json')
          .eq('key', _settingsKey)
          .maybeSingle();
      if (row != null && row['value_json'] is Map) {
        _cached = SplashVideoConfig.fromJson(
            Map<String, dynamic>.from(row['value_json'] as Map));
      } else {
        _cached = const SplashVideoConfig();
      }
      _loaded = true;
      return _cached;
    } catch (e) {
      lastError = e.toString();
      return _cached;
    }
  }

  /// الإعدادات الحاليّة (sync بَعد load)
  SplashVideoConfig get config => _cached;

  /// حِفظ الإعدادات
  Future<bool> save(SplashVideoConfig config) async {
    try {
      final c = SupabaseService().client;
      await c.from('app_settings').upsert({
        'key': _settingsKey,
        'value_json': config.toJson(),
      });
      _cached = config;
      _loaded = true;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// رَفع مِلَفّ فيديو إلى Supabase Storage وَإرجاع الـ public URL
  Future<String?> uploadVideo({
    required Uint8List bytes,
    required String filename,
    String contentType = 'video/mp4',
  }) async {
    try {
      final c = SupabaseService().client;
      final ext = filename.contains('.')
          ? filename.split('.').last.toLowerCase()
          : 'mp4';
      final path = 'welcome_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await c.storage.from('splash_videos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );
      return c.storage.from('splash_videos').getPublicUrl(path);
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// رَفع مِلَفّ صَوت إلى Supabase Storage وَإرجاع الـ public URL
  Future<String?> uploadAudio({
    required Uint8List bytes,
    required String filename,
    String contentType = 'audio/mpeg',
  }) async {
    try {
      final c = SupabaseService().client;
      final ext = filename.contains('.')
          ? filename.split('.').last.toLowerCase()
          : 'mp3';
      final path = 'audio_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await c.storage.from('splash_videos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );
      return c.storage.from('splash_videos').getPublicUrl(path);
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }
}
