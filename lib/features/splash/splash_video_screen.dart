// =============================================================================
// 🎬 Splash Video Screen — فيديو + صَوت مُنفَصِل (اختِياريّ)
// =============================================================================
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/splash_video_settings.dart';

/// شاشة فيديو الترحيب — مَع دَعم صَوت مُنفَصِل (audioUrl).
class SplashVideoScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final SplashVideoConfig config;

  const SplashVideoScreen({
    super.key,
    required this.onComplete,
    required this.config,
  });

  /// فَحص هَل يَجِب عَرض الفيديو الآن حَسَب الإعدادات
  static Future<bool> shouldShow(SplashVideoConfig cfg) async {
    if (!cfg.enabled) return false;
    if (!cfg.hasVideo) return false;
    if (cfg.showFrequency == SplashShowFrequency.everyTime) return true;
    if (cfg.showFrequency == SplashShowFrequency.never) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShown = prefs.getString('splash_video_last_shown');
      if (lastShown == null) return true;

      final last = DateTime.tryParse(lastShown);
      if (last == null) return true;
      final now = DateTime.now();

      switch (cfg.showFrequency) {
        case SplashShowFrequency.session:
          return now.difference(last).inMinutes >= 30;
        case SplashShowFrequency.daily:
          return now.day != last.day ||
              now.month != last.month ||
              now.year != last.year;
        case SplashShowFrequency.weekly:
          return now.difference(last).inDays >= 7;
        case SplashShowFrequency.everyTime:
        case SplashShowFrequency.never:
          return true;
      }
    } catch (_) {
      return true;
    }
  }

  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'splash_video_last_shown', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _initialized = false;
  bool _completed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = widget.config.videoUrl;
      if (url == null || url.isEmpty) {
        _finish();
        return;
      }

      // 1) تَهيِئة الفيديو
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      _videoController!.addListener(_onVideoStateChanged);

      // 2) تَهيِئة الصَوت المُنفَصِل (إن وُجِد)
      if (widget.config.hasAudio) {
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
      }

      // 3) تَحديد الصَوت الأَوَّليّ
      // - إن كانَ هُناك صَوت مُنفَصِل: الفيديو صامِت (نَستَخدِم الصَوت المُنفَصِل فَقَط)
      // - إن لا: نَستَخدِم صَوت الفيديو
      if (widget.config.autoUnmute) {
        if (widget.config.hasAudio) {
          await _videoController!.setVolume(0);
          await _audioPlayer!.setVolume(1.0);
        } else {
          await _videoController!.setVolume(1.0);
        }
        _muted = false;
      } else {
        await _videoController!.setVolume(0);
        if (_audioPlayer != null) {
          await _audioPlayer!.setVolume(0);
        }
      }

      // 4) ابدَأ التَشغيل
      await _videoController!.play();
      if (_audioPlayer != null) {
        try {
          await _audioPlayer!.play(UrlSource(widget.config.audioUrl!));
        } catch (_) {/* صَوت اختِياريّ — لا تَفشَل */}
      }

      if (mounted) setState(() => _initialized = true);

      // 5) الحَدّ الأَقصى
      Future.delayed(
        Duration(seconds: widget.config.maxDurationSeconds),
        () {
          if (mounted && !_completed) _finish();
        },
      );
    } catch (e) {
      _finish();
    }
  }

  void _onVideoStateChanged() {
    if (_videoController == null) return;
    final v = _videoController!.value;
    if (v.position >= v.duration && !_completed) {
      _finish();
    }
  }

  Future<void> _toggleMute() async {
    if (_videoController == null) return;
    final newMuted = !_muted;

    if (widget.config.hasAudio) {
      // الصَوت يَأتي مِن AudioPlayer، الفيديو يَظَلّ صامِت
      await _videoController!.setVolume(0);
      await _audioPlayer?.setVolume(newMuted ? 0 : 1.0);
    } else {
      // الصَوت يَأتي مِن الفيديو نَفسه
      await _videoController!.setVolume(newMuted ? 0 : 1.0);
    }

    if (mounted) setState(() => _muted = newMuted);
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    try {
      await _audioPlayer?.stop();
    } catch (_) {}
    await SplashVideoScreen.markShown();
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoStateChanged);
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      backgroundColor: Colors.black,
      // 🚫 لا SafeArea — نُريد ملء الشاشة كامِلاً (Cinematic experience)
      // 🆕 Directionality.ltr لِتَجَنُّب انزِياح الفيديو مَع RTL
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand, // 🆕 الـ Stack يَملَأ الشاشة كامِلة
          children: [
            // 🎬 الفيديو — يَتَكَيَّف مَع كُلّ النِسَب وَالأَجهِزة (ويب + جَوّال)
            // BoxFit.contain يَضمَن:
            // - فيديو portrait عَلى شاشة عَريضة → أَشرِطة سَوداء عَلى الجانِبَين
            // - فيديو landscape عَلى شاشة طَويلة → أَشرِطة سَوداء فَوق وَتَحت
            // - الفيديو يَظهَر دائِماً بِنِسبَتِه الأَصلِيّة بِدون قَطع
            Center(
              child: _initialized && _videoController != null
                  ? FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),

            // 🔊 زِرّ تَفعيل الصَوت
            if (_initialized && _muted)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    elevation: 8,
                    child: InkWell(
                      onTap: _toggleMute,
                      borderRadius: BorderRadius.circular(32),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.volume_off,
                                color: Colors.black87, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              isAr ? 'اضغَط لِتَفعيل الصَوت' : 'Tap to unmute',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 🔇 زِرّ كَتم
            if (_initialized && !_muted)
              Positioned(
                top: 16,
                left: 16,
                child: Material(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: _toggleMute,
                    borderRadius: BorderRadius.circular(24),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.volume_up,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),

            // ⏭ Skip
            Positioned(
              top: 16,
              right: 16,
              child: Material(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: _finish,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'تَخَطّى' : 'Skip',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.skip_next,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
