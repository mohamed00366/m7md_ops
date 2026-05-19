
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'supabase_data_service.dart';
import 'supabase_service.dart';

/// 🖼️ خدمة موحّدة لاختيار/رفع الصور من الكاميرا أو المعرض
///
/// تستخدم في كلّ التطبيق (صورة الموظف، الهويّة، الرخصة، أيّ مرفق).
///
/// الاستخدام:
/// ```dart
/// final result = await ImagePickerService.pickAndUpload(
///   context: context,
///   bucket: 'employee_photos',
///   pathPrefix: 'emp_${empId}',
/// );
/// if (result != null) {
///   // result.fileId مفتاح للحفظ في DB
///   // result.url للعرض
/// }
/// ```
class ImagePickerService {
  ImagePickerService._();
  static final _picker = ImagePicker();

  /// اختر صورة (camera/gallery) وارفعها إلى Supabase Storage.
  /// يُرجع `_UploadResult` يحوي fileId + url، أو null إن لُغي.
  static Future<UploadedImage?> pickAndUpload({
    required BuildContext context,
    required String bucket,
    String? pathPrefix,
    int imageQuality = 80,
    double maxWidth = 1600,
  }) async {
    final source = await _showSourcePicker(context);
    if (source == null) return null;
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
      );
      if (picked == null) return null;

      // اقرأ البايتات (يعمل على web و mobile)
      final bytes = await picked.readAsBytes();
      final ext = _extOf(picked.name);
      final filename =
          '${pathPrefix ?? 'img'}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      // ارفع للـ Supabase Storage إن جاهز
      String? publicUrl;
      String? fileId;
      if (SupabaseService().isReady) {
        final res = await _uploadToStorage(
          bucket: bucket,
          filename: filename,
          bytes: bytes,
          contentType: _mimeOf(ext),
        );
        publicUrl = res?.url;
        fileId = res?.fileId;
      } else {
        // fallback: نخزّن في الذاكرة (لا رفع فعلي)
        fileId = filename;
      }

      return UploadedImage(
        fileId: fileId ?? filename,
        url: publicUrl,
        bytes: bytes,
        filename: filename,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('فشل رفع الصورة: $e'),
        ));
      }
      return null;
    }
  }

  /// اختر فقط (بدون رفع) — يفيد للنماذج التي تحفظ لاحقاً
  static Future<UploadedImage?> pickOnly({
    required BuildContext context,
    int imageQuality = 80,
    double maxWidth = 1600,
  }) async {
    final source = await _showSourcePicker(context);
    if (source == null) return null;
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      return UploadedImage(
        fileId: picked.name,
        url: null,
        bytes: bytes,
        filename: picked.name,
      );
    } catch (_) {
      return null;
    }
  }

  /// عرض bottom-sheet لاختيار المصدر
  static Future<ImageSource?> _showSourcePicker(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // الكاميرا — مخفيّة على web (غير مدعومة دائماً)
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera, size: 24),
                title: const Text('التقط من الكاميرا'),
                subtitle: const Text('Take a photo'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library, size: 24),
              title: const Text('اختر من المعرض'),
              subtitle: const Text('Pick from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.close, size: 24),
              title: const Text('إلغاء'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  static Future<_UploadResult?> _uploadToStorage({
    required String bucket,
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      // نستخدم SupabaseDataService لو فيه دالة موحّدة، وإلا storage مباشرة
      final url = await SupabaseDataService().uploadImageToStorage(
        bucket: bucket,
        filename: filename,
        bytes: bytes,
        contentType: contentType,
      );
      if (url == null) return null;
      return _UploadResult(fileId: filename, url: url);
    } catch (_) {
      return null;
    }
  }

  static String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _mimeOf(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}

/// نتيجة رفع/اختيار صورة
class UploadedImage {
  final String fileId;
  final String? url;
  final Uint8List bytes;
  final String filename;
  UploadedImage({
    required this.fileId,
    required this.url,
    required this.bytes,
    required this.filename,
  });
}

class _UploadResult {
  final String fileId;
  final String url;
  _UploadResult({required this.fileId, required this.url});
}
