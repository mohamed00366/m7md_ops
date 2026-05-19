import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/point_terminal_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 🏪 شاشة إعدادات Point Terminal (جِهاز نُقطة الدَوام)
///
/// تَتَحَكَّم في:
///   - نِصف قُطر Geo-fence (٢٠–٢٠٠٠م)
///   - مُدّة خُمول الشاشة قَبل الإقفال
///   - فاصِل فَحص الإقفال التِلقائيّ
///   - حَدّ التَأَخُّر (دَقائِق)
///   - إجبار GPS عَلى التَسجيل
///   - التِقاط صورة لِلتَدقيق
///   - نِطاق مُطابَقة الوَجه (نُقطة/دَولة/كُلّ)
///   - حَدّ أَدنى لِثِقة المُطابَقة
class PointTerminalSettingsScreen extends StatefulWidget {
  const PointTerminalSettingsScreen({super.key});

  @override
  State<PointTerminalSettingsScreen> createState() =>
      _PointTerminalSettingsScreenState();
}

class _PointTerminalSettingsScreenState
    extends State<PointTerminalSettingsScreen> {
  bool _ready = false;
  int _geoFenceRadiusM = 200;
  int _idleTimeoutMinutes = 15;
  int _autoLockCheckMinutes = 5;
  int _lateThresholdMinutes = 10;
  bool _requireGps = false;
  bool _captureAuditPhoto = true;
  FaceMatchScope _faceScope = FaceMatchScope.country;
  double _matchConfidenceMin = 0.65;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await PointTerminalSettings.instance.load();
    final s = PointTerminalSettings.instance;
    _geoFenceRadiusM = s.geoFenceRadiusM;
    _idleTimeoutMinutes = s.idleTimeoutMinutes;
    _autoLockCheckMinutes = s.autoLockCheckMinutes;
    _lateThresholdMinutes = s.lateThresholdMinutes;
    _requireGps = s.requireGps;
    _captureAuditPhoto = s.captureAuditPhoto;
    _faceScope = s.faceScope;
    _matchConfidenceMin = s.matchConfidenceMin;
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _save() async {
    final ok = await PointTerminalSettings.instance.save(
      geoFenceRadiusM: _geoFenceRadiusM,
      idleTimeoutMinutes: _idleTimeoutMinutes,
      autoLockCheckMinutes: _autoLockCheckMinutes,
      lateThresholdMinutes: _lateThresholdMinutes,
      requireGps: _requireGps,
      captureAuditPhoto: _captureAuditPhoto,
      faceScope: _faceScope,
      matchConfidenceMin: _matchConfidenceMin,
    );
    if (!mounted) return;
    final isAr = AppStrings.of(context).isAr;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.warning,
      content: Text(ok
          ? (isAr ? 'تَمَّ الحِفظ' : 'Saved')
          : (isAr ? 'حُفِظ محلّيّاً فَقَط' : 'Saved locally only')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    if (!_ready) {
      return Scaffold(
        appBar: M7AppBar(
            title:
                isAr ? 'إعدادات نُقطة الدَوام' : 'Point Terminal Settings'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: M7AppBar(
        title:
            isAr ? 'إعدادات نُقطة الدَوام' : 'Point Terminal Settings',
        actions: [
          M7AppBarAction(
            icon: Icons.save,
            tooltip: isAr ? 'حِفظ' : 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Geo-fence =====
          _sectionHeader('📍 ' +
              (isAr ? 'حُدود المَوقِع (Geo-fence)' : 'Geo-fence')),
          _info(isAr
              ? 'مَسافة قُصوى مَسموحة بَين جِهاز النُقطة وَالنُقطة لِقَبول تَسجيل الدَوام.'
              : 'Maximum allowed distance between the terminal and the point for clock-in to be accepted.'),
          _intSliderRow(
            label: isAr
                ? 'نِصف قُطر Geo-fence'
                : 'Geo-fence radius',
            value: _geoFenceRadiusM,
            min: 20,
            max: 2000,
            divisions: 99,
            unit: 'م',
            onChanged: (v) => setState(() => _geoFenceRadiusM = v),
            icon: Icons.radio_button_unchecked,
          ),
          SwitchListTile(
            value: _requireGps,
            onChanged: (v) => setState(() => _requireGps = v),
            title: Text(isAr
                ? 'GPS إلزاميّ'
                : 'GPS required'),
            subtitle: Text(isAr
                ? 'إذا مُفَعَّل → يُرفَض التَسجيل عَن جِهاز بِدون GPS'
                : 'If enabled → reject clock if GPS is unavailable'),
            secondary: const Icon(Icons.gps_fixed, color: AppColors.gold),
          ),
          const Divider(height: 24),

          // ===== Auto-Lock =====
          _sectionHeader('🔒 ' +
              (isAr ? 'الإقفال التِلقائيّ' : 'Auto-Lock')),
          _info(isAr
              ? 'يُقفِل الجِهاز عِندَ خُمول الشاشة بِشَرط لا أَحَد مُسَجَّل دُخول.'
              : 'Locks the device when the screen is idle and no employees are still clocked in.'),
          _intSliderRow(
            label: isAr ? 'مُهلة الخُمول' : 'Idle timeout',
            value: _idleTimeoutMinutes,
            min: 1,
            max: 240,
            divisions: 60,
            unit: 'د',
            onChanged: (v) =>
                setState(() => _idleTimeoutMinutes = v),
            icon: Icons.hourglass_empty,
          ),
          _intSliderRow(
            label: isAr ? 'فاصِل الفَحص' : 'Check interval',
            value: _autoLockCheckMinutes,
            min: 1,
            max: 60,
            divisions: 59,
            unit: 'د',
            onChanged: (v) =>
                setState(() => _autoLockCheckMinutes = v),
            icon: Icons.timer,
          ),
          const Divider(height: 24),

          // ===== Late =====
          _sectionHeader('🕐 ' +
              (isAr ? 'حَدّ التَأَخُّر' : 'Late Threshold')),
          _info(isAr
              ? 'إذا تَجاوَزَ المُوَظَّف بَعدَ بِداية وَردِيَّتِه هذِه المُدّة، يُسَجَّل كَمُتَأَخِّر في التَقرير.'
              : 'If clock-in exceeds shift start by this many minutes, the employee is marked late in the report.'),
          _intSliderRow(
            label: isAr ? 'دَقائِق' : 'Minutes',
            value: _lateThresholdMinutes,
            min: 0,
            max: 120,
            divisions: 24,
            unit: 'د',
            onChanged: (v) =>
                setState(() => _lateThresholdMinutes = v),
            icon: Icons.access_time,
          ),
          const Divider(height: 24),

          // ===== Face Matching =====
          _sectionHeader('🧠 ' +
              (isAr ? 'مُطابَقة الوَجه' : 'Face Matching')),
          _info(isAr
              ? 'نِطاق المُوَظَّفين الذين تَتِم مُطابَقَتُهم عِندَ مَسح وَجه عَلى جِهاز النُقطة.'
              : 'Scope of employees matched when scanning a face on the terminal.'),
          Card(
            child: Column(
              children: FaceMatchScope.values.map((s) {
                return RadioListTile<FaceMatchScope>(
                  value: s,
                  groupValue: _faceScope,
                  onChanged: (v) =>
                      setState(() => _faceScope = v ?? _faceScope),
                  title: Text(isAr ? s.labelAr() : s.labelEn()),
                  dense: true,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _sliderRow(
            label: isAr
                ? 'حَدّ أَدنى لِلثِقة'
                : 'Minimum confidence',
            value: _matchConfidenceMin,
            min: 0.50,
            max: 0.95,
            divisions: 45,
            unit: '%',
            displayMultiplier: 100,
            onChanged: (v) =>
                setState(() => _matchConfidenceMin = v),
            icon: Icons.verified_user,
          ),
          SwitchListTile(
            value: _captureAuditPhoto,
            onChanged: (v) =>
                setState(() => _captureAuditPhoto = v),
            title: Text(isAr
                ? 'حِفظ صورة لِلتَدقيق'
                : 'Save audit photo'),
            subtitle: Text(isAr
                ? 'تُحفَظ صورة الوَجه مَع كُلّ تَسجيل لِلمُراجَعة'
                : 'Save face photo with each clock entry for review'),
            secondary:
                const Icon(Icons.camera_alt, color: AppColors.gold),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.gold)),
      );

  Widget _info(String text) => Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.info.withOpacity(0.20)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info, color: AppColors.info, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 11, height: 1.4)),
              ),
            ],
          ),
        ),
      );

  Widget _intSliderRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required int divisions,
    required String unit,
    required ValueChanged<int> onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$value $unit',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppColors.gold,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            label: '$value',
            onChanged: (v) => onChanged(v.toInt()),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    int displayMultiplier = 1,
    required ValueChanged<double> onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(value * displayMultiplier).toStringAsFixed(0)}$unit',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppColors.gold,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: '${(value * displayMultiplier).toStringAsFixed(0)}',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
