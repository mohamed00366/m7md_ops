import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

/// 📷 خِدمة رَفع الصُوَر/المُستَنَدات إلى Supabase Storage
///
/// يَدعَم:
///   - التِقاط صورة من الكاميرا
///   - اختيار صورة من المَعرِض
///   - رَفع تلقائيّ إلى bucket form_uploads
///   - يُرجِع public URL لِحِفظِه في حَقل النَموذج
class FormUploadService {
  FormUploadService._();
  static final instance = FormUploadService._();

  final ImagePicker _picker = ImagePicker();

  static const String bucketName = 'form_uploads';

  /// يَطلُب صورة من الكاميرا، يَرفَعها، ويُرجِع الـURL.
  /// يُرجِع null لو ألغى المُستَخدِم.
  Future<String?> pickAndUploadFromCamera({
    String subFolder = 'general',
    int imageQuality = 70,
  }) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
        maxWidth: 1600,
      );
      if (xfile == null) return null;
      return await _upload(xfile, subFolder);
    } catch (e) {
      M7Log.error('FormUpload', 'camera', error: e);
      return null;
    }
  }

  /// يَطلُب صورة من المَعرِض، يَرفَعها، ويُرجِع الـURL.
  Future<String?> pickAndUploadFromGallery({
    String subFolder = 'general',
    int imageQuality = 80,
  }) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
        maxWidth: 1600,
      );
      if (xfile == null) return null;
      return await _upload(xfile, subFolder);
    } catch (e) {
      M7Log.error('FormUpload', 'gallery', error: e);
      return null;
    }
  }

  /// الرَفع الفِعليّ
  Future<String?> _upload(XFile xfile, String subFolder) async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      M7Log.error('FormUpload', '_upload',
          error: 'Supabase not ready');
      return null;
    }

    final userId = supa.client.auth.currentUser?.id ?? 'anonymous';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _extensionOf(xfile.name);
    final safeFolder = subFolder.replaceAll(RegExp(r'[^a-zA-Z0-9_/]'), '_');
    final path = '$safeFolder/${userId}_${ts}.$ext';

    try {
      final storage = supa.client.storage.from(bucketName);

      if (kIsWeb) {
        // Web: نَستَخدِم bytes
        final bytes = await xfile.readAsBytes();
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _mimeOf(ext),
            upsert: true,
          ),
        );
      } else {
        // Mobile/Desktop: نَستَخدِم File
        await storage.upload(
          path,
          File(xfile.path),
          fileOptions: FileOptions(
            contentType: _mimeOf(ext),
            upsert: true,
          ),
        );
      }

      // الحُصول على الـpublic URL
      final url = storage.getPublicUrl(path);
      return url;
    } catch (e) {
      M7Log.error('FormUpload', '_upload', error: e);
      return null;
    }
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return 'jpg';
    return filename.substring(dot + 1).toLowerCase();
  }

  String _mimeOf(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}
