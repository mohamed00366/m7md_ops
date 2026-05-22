// =============================================================================
// 📎 M7MultiUploadBox — رَفع مُتَعَدِّد لِلصُوَر وَ PDF
// =============================================================================
// واجِهة مُوَحَّدة لِرَفع/عَرض/حَذف عِدّة مِلَفّات لِنَفس الحَقل (هَوِيّة،
// رُخصة، مَكتوب عَمَل، إلخ). يَدعَم خَلط أنواع المِلَفّات (صورة + PDF).
//
// تُمَرَّر قائِمة الـURLs الحاليّة وَ callback عِندَ كُلّ تَغيير.
// تَلقائياً تَفتَح الصورة في InteractiveViewer أَو PDF في المُتَصَفِّح.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/image_picker_service.dart';
import '../core/services/supabase_data_service.dart';
import '../core/theme/app_colors.dart';
import 'm7_app_bar.dart';

/// 🔎 يَكشِف هَل الـURL يُؤَدّي إلى مِلَفّ PDF
bool m7IsPdfUrl(String url) {
  final u = url.toLowerCase().split('?').first.split('#').first;
  return u.endsWith('.pdf');
}

/// 🔎 يَكشِف هَل الـURL يُؤَدّي إلى مِلَفّ صورة
bool m7IsImageUrl(String url) {
  final u = url.toLowerCase().split('?').first.split('#').first;
  return u.endsWith('.jpg') ||
      u.endsWith('.jpeg') ||
      u.endsWith('.png') ||
      u.endsWith('.webp') ||
      u.endsWith('.gif') ||
      u.endsWith('.bmp') ||
      u.endsWith('.heic') ||
      u.endsWith('.heif');
}

/// 🌍 فاتِح مِلَفّ عامّ — يُحَدِّد PDF/صورة تِلقائيّاً
Future<void> m7OpenFile(BuildContext context, String url, {String? title}) async {
  if (url.isEmpty) return;
  if (m7IsPdfUrl(url)) {
    // PDF: نَفتَحه في المُتَصَفِّح خارِجيّاً (أَكثَر تَوافُقاً عَلى Web/Mobile)
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  }
  // افتِراضيّاً: شاشة عَرض داخِليّة (تَدعَم الصورة + fallback PDF)
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => M7FileViewerScreen(url: url, title: title ?? ''),
  ));
}

/// شاشة عَرض مِلَفّ مَع InteractiveViewer لِلصُوَر + زِرّ فَتح خارِجيّ لِـPDF
class M7FileViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const M7FileViewerScreen({super.key, required this.url, this.title = ''});

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? 'لا يُمكِن فَتح المِلَفّ'
            : 'Cannot open file'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isPdf = m7IsPdfUrl(url);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: M7AppBar(
        title: title.isEmpty ? (isAr ? 'مِلَفّ' : 'File') : title,
        actions: [
          M7AppBarAction(
            icon: Icons.open_in_new,
            tooltip: isAr ? 'فَتح في المُتَصَفِّح' : 'Open in browser',
            onPressed: () => _openInBrowser(context),
          ),
        ],
      ),
      body: Center(
        child: isPdf
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.picture_as_pdf,
                      size: 96, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    isAr ? 'مِلَفّ PDF' : 'PDF File',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _openInBrowser(context),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(isAr ? 'فَتح المِلَفّ' : 'Open PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                  ),
                ],
              )
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(
                        color: Colors.white);
                  },
                  errorBuilder: (_, __, ___) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image,
                          color: Colors.white54, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        isAr ? 'فَشِل تَحميل الصورة' : 'Failed to load image',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openInBrowser(context),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(
                            isAr ? 'فَتح في المُتَصَفِّح' : 'Open in browser'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// 📤 صُندوق رَفع مُتَعَدِّد المِلَفّات (صورة + PDF خَليط)
class M7MultiUploadBox extends StatefulWidget {
  /// عُنوان كَبير (مَثَلاً: "مِلَفّ الهَوِيّة")
  final String label;

  /// نَصّ تَوضيحيّ صَغير تَحت العُنوان
  final String hint;

  /// أَيقونة العَرض الافتِراضيّة
  final IconData icon;

  /// قائِمة الـURLs الحاليّة (سَتُعرَض كَبِطاقات قابِلة لِلحَذف/العَرض)
  final List<String> urls;

  /// callback عِندَ تَغيير القائِمة (إضافة/حَذف)
  final ValueChanged<List<String>> onChanged;

  /// bucket في Supabase Storage
  final String bucket;

  /// بادِئة اسم المِلَفّ
  final String? pathPrefix;

  /// الحَدّ الأَقصى لِعَدَد المِلَفّات (افتِراضياً 5)
  final int maxFiles;

  const M7MultiUploadBox({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.urls,
    required this.onChanged,
    required this.bucket,
    this.pathPrefix,
    this.maxFiles = 5,
  });

  @override
  State<M7MultiUploadBox> createState() => _M7MultiUploadBoxState();
}

class _M7MultiUploadBoxState extends State<M7MultiUploadBox> {
  bool _uploading = false;

  Future<void> _pickAndAdd() async {
    if (widget.urls.length >= widget.maxFiles) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? 'الحَدّ الأَقصى ${widget.maxFiles} مِلَفّات'
            : 'Max ${widget.maxFiles} files'),
      ));
      return;
    }
    setState(() => _uploading = true);
    final result = await ImagePickerService.pickAndUpload(
      context: context,
      bucket: widget.bucket,
      pathPrefix: widget.pathPrefix,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result == null) {
      final err = SupabaseDataService().lastError;
      if (err != null && err.contains('Bucket')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 6),
          content: Text(
            AppStrings.of(context).isAr
                ? '⚠️ Bucket "${widget.bucket}" غَير مَوجود في Storage'
                : '⚠️ Bucket "${widget.bucket}" missing',
          ),
        ));
      }
      return;
    }
    if (result.url == null) return;
    final updated = [...widget.urls, result.url!];
    widget.onChanged(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(AppStrings.of(context).isAr
            ? '✅ تَمّ رَفع المِلَفّ (${updated.length}/${widget.maxFiles})'
            : '✅ File uploaded (${updated.length}/${widget.maxFiles})'),
      ));
    }
  }

  void _remove(int index) {
    final updated = [...widget.urls]..removeAt(index);
    widget.onChanged(updated);
  }

  void _confirmRemove(int index) {
    final isAr = AppStrings.of(context).isAr;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'حَذف المِلَفّ؟' : 'Remove file?'),
        content: Text(isAr
            ? 'سَيُحذَف رابِط المِلَفّ مِن السِجِلّ (لَن يُحذَف فِعليّاً مِن التَخزين).'
            : 'The file link will be removed (file remains in storage).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _remove(index);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(isAr ? 'حَذف' : 'Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final canAdd = widget.urls.length < widget.maxFiles && !_uploading;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== العُنوان =====
          Row(
            children: [
              Icon(widget.icon, color: AppColors.brand, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(widget.hint,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.urls.isEmpty
                      ? Colors.grey.withOpacity(0.2)
                      : AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.urls.length}/${widget.maxFiles}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: widget.urls.isEmpty
                        ? Colors.grey
                        : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          if (widget.urls.isNotEmpty) ...[
            const SizedBox(height: 10),
            // ===== شَبَكة المِلَفّات =====
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < widget.urls.length; i++)
                  _FilePreviewTile(
                    url: widget.urls[i],
                    index: i,
                    title: '${widget.label} ${i + 1}',
                    onOpen: () => m7OpenFile(
                      context,
                      widget.urls[i],
                      title: '${widget.label} (${i + 1})',
                    ),
                    onRemove: () => _confirmRemove(i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // ===== زِرّ الإضافة =====
          OutlinedButton.icon(
            onPressed: canAdd ? _pickAndAdd : null,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.urls.isEmpty
                        ? Icons.add_photo_alternate
                        : Icons.add,
                    size: 18,
                  ),
            label: Text(
              _uploading
                  ? (isAr ? 'جارٍ الرَفع...' : 'Uploading...')
                  : widget.urls.isEmpty
                      ? (isAr
                          ? 'إضافة مِلَفّ (صورة أَو PDF)'
                          : 'Add file (Image or PDF)')
                      : (isAr
                          ? 'إضافة مِلَفّ آخَر'
                          : 'Add another file'),
            ),
          ),
        ],
      ),
    );
  }
}

/// بِطاقة مُعايَنة مِلَفّ واحِد (صورة مُصَغَّرة أَو أَيقونة PDF)
class _FilePreviewTile extends StatelessWidget {
  final String url;
  final int index;
  final String title;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _FilePreviewTile({
    required this.url,
    required this.index,
    required this.title,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isPdf = m7IsPdfUrl(url);
    const tileSize = 84.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ===== المُعايَنة =====
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: isPdf
                  ? Colors.red.withOpacity(0.08)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPdf
                    ? Colors.red.withOpacity(0.4)
                    : AppColors.brand.withOpacity(0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isPdf
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 36),
                        const SizedBox(height: 4),
                        Text(
                          'PDF ${index + 1}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ],
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: tileSize,
                      height: tileSize,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.grey, size: 32),
                      ),
                    ),
            ),
          ),
        ),
        // ===== رَقم في الزاوِية =====
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        // ===== زِرّ الحَذف =====
        Positioned(
          top: -6,
          left: -6,
          child: Material(
            color: AppColors.danger,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
