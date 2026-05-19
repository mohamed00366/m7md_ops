import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/services/smart_alerts_service.dart';
import '../features/admin/smart_alerts_screen.dart';

/// 🚨 بانِر تَنبيهات في الصَفحة الرَئيسيّة
///
/// يَعرِض عَدَد التَنبيهات الحَرِجة وَالعاجِلة فَقَط. إذا لا يُوجَد، يَختَفي.
class SmartAlertsBanner extends StatelessWidget {
  const SmartAlertsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final isUr = s.isUr;
    final auth = context.watch<AuthProvider>();
    final alerts =
        SmartAlertsService.instance.scan(countryId: auth.activeCountryId);
    final critical =
        alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final urgent =
        alerts.where((a) => a.severity == AlertSeverity.urgent).length;
    final warning =
        alerts.where((a) => a.severity == AlertSeverity.warning).length;
    final total = critical + urgent + warning;
    if (total == 0) return const SizedBox.shrink();
    final color = critical > 0
        ? Colors.red
        : urgent > 0
            ? Colors.orange
            : Colors.amber.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SmartAlertsScreen())),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.notifications_active, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUr
                            ? '$total اطلاعات آپ کی توجہ چاہتی ہیں'
                            : isAr
                                ? '$total تَنبيه يَحتاج اهتِمامك'
                                : '$total alerts need your attention',
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 3,
                        children: [
                          if (critical > 0)
                            _miniPill(
                                count: critical,
                                label: isUr ? 'نازک' : (isAr ? 'حَرِج' : 'Critical'),
                                color: Colors.red),
                          if (urgent > 0)
                            _miniPill(
                                count: urgent,
                                label: isUr ? 'فوری' : (isAr ? 'عاجِل' : 'Urgent'),
                                color: Colors.orange),
                          if (warning > 0)
                            _miniPill(
                                count: warning,
                                label: isUr ? 'انتباہ' : (isAr ? 'تَحذير' : 'Warning'),
                                color: Colors.amber.shade700),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniPill({
    required int count,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 9)),
        ],
      ),
    );
  }
}
