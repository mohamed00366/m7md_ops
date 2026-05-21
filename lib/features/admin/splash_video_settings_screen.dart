// =============================================================================
// 🎬 SplashVideoSettingsScreen — إدارة فيديو الترحيب
// =============================================================================
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/splash_video_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class SplashVideoSettingsScreen extends StatefulWidget {
  const SplashVideoSettingsScreen({super.key});

  @override
  State<SplashVideoSettingsScreen> createState() =>
      _SplashVideoSettingsScreenState();
}

class _SplashVideoSettingsScreenState extends State<SplashVideoSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  SplashVideoConfig _config = const SplashVideoConfig();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cfg = await SplashVideoSettings.instance.load(forceReload: true);
    if (mounted) {
      setState(() {
        _config = cfg;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await SplashVideoSettings.instance.save(_config);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        content: Text(ok
            ? (AppStrings.of(context).isAr
                ? '✅ تَمَّ الحِفظ'
                : '✅ Saved')
            : (AppStrings.of(context).isAr
                ? '❌ فَشِل الحِفظ: ${SplashVideoSettings.instance.lastError}'
                : '❌ Failed: ${SplashVideoSettings.instance.lastError}')),
      ));
    }
  }

  Future<void> _uploadVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'webm', 'mov'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) {
        setState(() => _error = 'No file data');
        return;
      }

      // فَحص الحَجم (50 MB كَحَدّ أَقصى)
      const maxSize = 50 * 1024 * 1024;
      if (f.bytes!.length > maxSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('⚠ الحَجم أَكبَر مِن 50 MB'),
          ));
        }
        return;
      }

      setState(() => _uploading = true);
      final ct = f.extension == 'webm'
          ? 'video/webm'
          : f.extension == 'mov'
              ? 'video/quicktime'
              : 'video/mp4';
      final url = await SplashVideoSettings.instance.uploadVideo(
        bytes: f.bytes!,
        filename: f.name,
        contentType: ct,
      );
      if (!mounted) return;
      setState(() => _uploading = false);

      if (url != null) {
        setState(() {
          _config = _config.copyWith(videoUrl: url);
        });
        // حِفظ تِلقائيّ بَعد الرَفع
        await _save();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
              '❌ فَشِل الرَفع: ${SplashVideoSettings.instance.lastError}'),
        ));
      }
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
    }
  }

  void _useDefaultAsset() {
    setState(() {
      _config = _config.copyWith(clearVideoUrl: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🎬 إعدادات فيديو الترحيب' : '🎬 Splash Video Settings',
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: isAr ? 'حِفظ' : 'Save',
              onPressed: _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1️⃣ تَفعيل/إيقاف
                _section(
                  title: isAr ? 'الحالة' : 'Status',
                  child: SwitchListTile(
                    title: Text(isAr
                        ? 'تَفعيل فيديو الترحيب'
                        : 'Enable splash video'),
                    subtitle: Text(isAr
                        ? 'إذا أُغلِق، يَدخُل المُستَخدِم مُباشَرةً'
                        : 'When off, users skip directly to login'),
                    value: _config.enabled,
                    onChanged: (v) =>
                        setState(() => _config = _config.copyWith(enabled: v)),
                  ),
                ),

                const SizedBox(height: 16),

                // 2️⃣ الفيديو الحاليّ + الرَفع
                _section(
                  title: isAr ? 'الفيديو الحاليّ' : 'Current Video',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.brand.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.movie,
                                color: AppColors.brand, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _config.videoUrl != null
                                        ? (isAr
                                            ? 'فيديو مَرفوع'
                                            : 'Custom video')
                                        : (isAr
                                            ? 'الفيديو الافتِراضيّ'
                                            : 'Default video'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14),
                                  ),
                                  Text(
                                    _config.videoUrl ?? _config.videoPath,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _uploading ? null : _uploadVideo,
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.upload),
                              label: Text(_uploading
                                  ? (isAr
                                      ? 'جارٍ الرَفع...'
                                      : 'Uploading...')
                                  : (isAr
                                      ? 'رَفع فيديو جَديد'
                                      : 'Upload new video')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brand,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          if (_config.videoUrl != null) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _useDefaultAsset,
                              icon: const Icon(Icons.restore),
                              label: Text(
                                  isAr ? 'استِخدام الافتِراضيّ' : 'Use default'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isAr
                            ? '⚠ الصِيَغ المَدعومة: MP4 / WebM / MOV — حَدّ أَقصى 50 MB'
                            : '⚠ Supported: MP4 / WebM / MOV — max 50 MB',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3️⃣ الصَوت
                _section(
                  title: isAr ? 'الصَوت' : 'Audio',
                  child: SwitchListTile(
                    title: Text(isAr
                        ? 'مُحاوَلة تَشغيل الصَوت تِلقائيّاً'
                        : 'Try auto-unmute'),
                    subtitle: Text(isAr
                        ? '⚠ المُتَصَفِّحات تَمنَع الصَوت تِلقائيّاً — قَد لا يَعمَل'
                        : '⚠ Browsers block autoplay sound — may not work'),
                    value: _config.autoUnmute,
                    onChanged: (v) => setState(
                        () => _config = _config.copyWith(autoUnmute: v)),
                  ),
                ),

                const SizedBox(height: 16),

                // 4️⃣ المُدَّة القُصوى
                _section(
                  title: isAr
                      ? 'المُدَّة القُصوى: ${_config.maxDurationSeconds} ثانية'
                      : 'Max duration: ${_config.maxDurationSeconds} seconds',
                  child: Column(
                    children: [
                      Slider(
                        value: _config.maxDurationSeconds.toDouble(),
                        min: 3,
                        max: 30,
                        divisions: 27,
                        label: '${_config.maxDurationSeconds}s',
                        onChanged: (v) => setState(() => _config =
                            _config.copyWith(maxDurationSeconds: v.round())),
                      ),
                      Text(
                        isAr
                            ? 'إذا لَم يَنتَهِ الفيديو في هذا الوَقت، يُتَخَطّى تِلقائيّاً'
                            : 'Video auto-skips after this duration',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 5️⃣ مَتى يَظهَر
                _section(
                  title: isAr ? 'مَتى يَظهَر الفيديو' : 'When to show',
                  child: Column(
                    children: SplashShowFrequency.values.map((f) {
                      return RadioListTile<SplashShowFrequency>(
                        title: Text(isAr ? f.labelAr() : f.labelEn()),
                        value: f,
                        groupValue: _config.showFrequency,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _config =
                                _config.copyWith(showFrequency: v));
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // 6️⃣ زِرّ حِفظ كَبير
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving
                        ? (isAr ? 'جارٍ الحِفظ...' : 'Saving...')
                        : (isAr ? '💾 حِفظ كُلّ الإعدادات' : '💾 Save all settings'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: AppColors.danger)),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
