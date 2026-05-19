import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/entity_qr_service.dart';
import '../core/theme/app_colors.dart';
import 'm7_app_bar.dart';

/// 🔲 شاشة عَرض QR لِكِيان مُحَدَّد
///
/// تَستَخدِم بِسُهولة مِن أَيّ Hub:
/// ```dart
/// EntityQrScreen(
///   entityType: 'employee',
///   entityId: e.id,
///   entityName: e.fullName,
///   subtitle: e.code,
/// )
/// ```
class EntityQrScreen extends StatelessWidget {
  final String entityType;
  final String entityId;
  final String entityName;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const EntityQrScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    this.subtitle,
    this.icon = Icons.qr_code,
    this.color = AppColors.brand,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final payload = EntityQrService.instance
        .encode(entityType: entityType, entityId: entityId);
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'رَمز QR' : 'QR Code',
        subtitle: entityName,
        actions: [
          M7AppBarAction(
            icon: Icons.copy,
            tooltip: isAr ? 'نَسخ الرابِط' : 'Copy link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: AppColors.success,
                  content: Text(isAr ? '✅ تَمّ النَسخ' : '✅ Copied'),
                ));
              }
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // بانِر الكِيان
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entityName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // الـQR
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 260,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.brand.withOpacity(0.25)),
                ),
                child: SelectableText(
                  payload,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.brand),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.info.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'امسَح هَذا الرَمز بِكاميرا الجَوّال (أَو طابِعه) لِفَتح هَذه الصَفحة مُباشَرة في التَطبيق.'
                            : 'Scan this code with a phone camera (or print it) to open this page directly in the app.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
