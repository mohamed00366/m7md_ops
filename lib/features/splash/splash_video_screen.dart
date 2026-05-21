// =============================================================================
// 🎬 Splash Video Screen — يُعرَض مَرَّة واحِدة في الجَلسة
// =============================================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n/app_strings.dart';

/// شاشة فيديو الترحيب — تَظهَر عِندَ أَوَّل فَتح فَقَط في اليَوم.
///
/// السُلوك:
/// - يُحَمَّل الفيديو وَيُشَغَّل تِلقائيّاً (صَوت مَكتوم لِيَعمَل في المُتَصَفِّحات)
/// - زِرّ Skip في الأَعلى يَمين
/// - عِندَ انتِهاء الفيديو أَو الضَغط Skip → يُستَدعى [onComplete]
/// - يُحفَظ في SharedPreferences التاريخ لِتَجَنُّب التَكرار في نَفس اليَوم
class SplashVideoScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashVideoScreen({super.key, required this.onComplete});

  /// مِفتاح SharedPreferences لِتاريخ آخِر عَرض
  static const String _prefKey = 'splash_video_shown_date';

  /// فَحص هَل يَجِب عَرض الفيديو اليَوم
  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShown = prefs.getString(_prefKey);
      final today = _formatDate(DateTime.now());
      return lastShown != today;
    } catch (_) {
      return false; // عِندَ الفَشَل، لا تَعرِض (آمِن)
    }
  }

  /// تَسجيل أَنّ الفيديو عُرِضَ اليَوم
  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _formatDate(DateTime.now()));
    } catch (_) {
      // ignore
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _controller = VideoPlayerController.asset('assets/video/welcome.mp4');
      await _controller!.initialize();
      await _controller!.setVolume(0); // 🔇 مَكتوم لِيَعمَل تِلقائيّاً
      await _controller!.play();
      _controller!.addListener(_onVideoStateChanged);
      if (mounted) setState(() => _initialized = true);

      // اِحتِياط — تَخَطّى الفيديو بَعد 8 ثَوانٍ كَحَدّ أَقصى
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && !_completed) _finish();
      });
    } catch (e) {
      // إن فَشِل التَحميل، انتَقِل مُباشَرةً
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

            // زِرّ Skip
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
                        const Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 18,
                        ),
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
