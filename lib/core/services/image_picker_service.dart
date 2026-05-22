
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'supabase_data_service.dart';
import 'supabase_service.dart';

/// مَصدَر اختِيار المِلَفّ
enum _PickerSource { camera, gallery, file }

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

  /// اختر صورة (camera/gallery/file) وارفعها إلى Supabase Storage.
  /// عِندَ `allowFiles: true` يَظهَر خِيار إضافيّ "PDF / مُستَنَد".
  /// يُرجع `UploadedImage` يحوي fileId + url، أو null إن لُغي.
  static Future<UploadedImage?> pickAndUpload({
    required BuildContext context,
    required String bucket,
    String? pathPrefix,
    int imageQuality = 80,
    double maxWidth = 1600,
    bool allowFiles = true,
  }) async {
    final source = await _showSourcePicker(context, allowFiles: allowFiles);
    if (source == null) return null;
    try {
      Uint8List? bytes;
      String? originalName;

      if (source == _PickerSource.file) {
        // 📄 PDF أَو مُستَنَد
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf', 'doc', 'docx', 'xls', 'xlsx',
            'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
          ],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return null;
        final f = result.files.first;
        if (f.bytes == null) return null;
        bytes = f.bytes;
        originalName = f.name;
      } else {
        // 📷 كاميرا أَو 🖼 مَعرَض
        final imageSource = source == _PickerSource.camera
            ? ImageSource.camera
            : ImageSource.gallery;
        final XFile? picked = await _picker.pickImage(
          source: imageSource,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
        );
        if (picked == null) return null;
        bytes = await picked.readAsBytes();
        originalName = picked.name;
      }

      if (bytes == null) return null;

      final ext = _extOf(originalName);
      final filename =
          '${pathPrefix ?? 'file'}_${DateTime.now().millisecondsSinceEpoch}.$ext';

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
          content: Text('فشل رفع المِلَفّ: $e'),
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
    bool allowFiles = true,
  }) async {
    final source = await _showSourcePicker(context, allowFiles: allowFiles);
    if (source == null) return null;
    try {
      Uint8List? bytes;
      String? name;

      if (source == _PickerSource.file) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf', 'doc', 'docx', 'xls', 'xlsx',
            'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
          ],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return null;
        final f = result.files.first;
        if (f.bytes == null) return null;
        bytes = f.bytes;
        name = f.name;
      } else {
        final imageSource = source == _PickerSource.camera
            ? ImageSource.camera
            : ImageSource.gallery;
        final XFile? picked = await _picker.pickImage(
          source: imageSource,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
        );
        if (picked == null) return null;
        bytes = await picked.readAsBytes();
        name = picked.name;
      }

      if (bytes == null) return null;

      return UploadedImage(
        fileId: name,
        url: null,
        bytes: bytes,
        filename: name,
      );
    } catch (_) {
      return null;
    }
  }

  /// عرض bottom-sheet لاختيار المصدر
  static Future<_PickerSource?> _showSourcePicker(
    BuildContext context, {
    bool allowFiles = true,
  }) async {
    return showModalBottomSheet<_PickerSource>(
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
                onTap: () => Navigator.of(ctx).pop(_PickerSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library, size: 24),
              title: const Text('اختر من المعرض (صورة)'),
              subtitle: const Text('Pick image from gallery'),
              onTap: () => Navigator.of(ctx).pop(_PickerSource.gallery),
            ),
            // 🆕 خِيار اختِيار مِلَفّ (PDF / مُستَنَد)
            if (allowFiles)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf,
                    size: 24, color: Colors.red),
                title: const Text('اختر مِلَفّ (PDF / مُستَنَد)'),
                subtitle: const Text('Pick PDF or document'),
                onTap: () => Navigator.of(ctx).pop(_PickerSource.file),
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
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'bmp':
        return 'image/bmp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'jpg':
      case 'jpeg':
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
