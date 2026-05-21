// =============================================================================
// 🎬 Splash Video Screen — يُحَمَّل مِن URL أَو asset حَسَب الإعدادات
// =============================================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/splash_video_settings.dart';

/// شاشة فيديو الترحيب — تَتَّبِع الإعدادات المُخَزَّنة في Supabase.
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
          // 'session' = نَفس Tab — لا نُخَزِّن، نَستَخدِم session storage فِعلِيّاً
          // كَحَلّ بَسيط: 30 دَقيقة كَنافِذة جَلسة
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

  /// تَسجيل وَقت آخِر عَرض
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
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _completed = false;
  bool _muted = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // اِختَر المَصدَر — URL (مِن Storage) أَو asset احتياطيّ
      final url = widget.config.videoUrl;
      if (url != null && url.isNotEmpty) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        _controller = VideoPlayerController.asset(widget.config.videoPath);
      }

      await _controller!.initialize();

      // مُحاوَلة تَشغيل الصَوت إن طَلَب المُستَخدِم (قَد يَفشَل في الويب)
      if (widget.config.autoUnmute) {
        await _controller!.setVolume(1.0);
        _muted = false;
      } else {
        await _controller!.setVolume(0);
      }

      await _controller!.play();
      _controller!.addListener(_onVideoStateChanged);
      if (mounted) setState(() => _initialized = true);

      // الحَدّ الأَقصى لِلمُدَّة
      Future.delayed(
        Duration(seconds: widget.config.maxDurationSeconds),
        () {
          if (mounted && !_completed) _finish();
        },
      );
    } catch (e) {
      _loadError = e.toString();
      _finish();
    }
  }

  void _onVideoStateChanged() {
    if (_controller == null) return;
    final v = _controller!.value;
    if (v.position >= v.duration && !_completed) {
      _finish();
    }
  }

  Future<void> _toggleMute() async {
    if (_controller == null) return;
    final newMuted = !_muted;
    await _controller!.setVolume(newMuted ? 0 : 1.0);
    if (mounted) setState(() => _muted = newMuted);
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    await SplashVideoScreen.markShown();
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // الفيديو
            Center(
              child: _initialized && _controller != null
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
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
