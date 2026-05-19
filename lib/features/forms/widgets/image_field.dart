import 'package:flutter/material.dart';

import '../../../core/services/form_upload_service.dart';
import '../../../core/theme/app_colors.dart';

/// 📷 حَقل صورة — كاميرا/مَعرِض + رَفع تلقائيّ
///
/// يَحفَظ URL الـpublic مِن Supabase Storage في الـvalue.
class ImageField extends StatefulWidget {
  final String label;
  final bool required;
  final String? initialUrl;
  final String? helper;
  final String subFolder;
  final bool isAr;
  final void Function(String? url) onChanged;

  const ImageField({
    super.key,
    required this.label,
    required this.required,
    required this.onChanged,
    required this.isAr,
    this.initialUrl,
    this.helper,
    this.subFolder = 'general',
  });

  @override
  State<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<ImageField> {
  String? _url;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl?.isEmpty == true ? null : widget.initialUrl;
  }

  Future<void> _pickFromCamera() async {
    setState(() => _uploading = true);
    final url = await FormUploadService.instance.pickAndUploadFromCamera(
      subFolder: widget.subFolder,
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _url = url;
    });
    if (url != null) widget.onChanged(url);
  }

  Future<void> _pickFromGallery() async {
    setState(() => _uploading = true);
    final url = await FormUploadService.instance.pickAndUploadFromGallery(
      subFolder: widget.subFolder,
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _url = url;
    });
    if (url != null) widget.onChanged(url);
  }

  void _remove() {
    setState(() => _url = null);
    widget.onChanged(null);
  }

  void _preview() {
    if (_url == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                _url!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image,
                        color: Colors.white, size: 64)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === Label ===
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(
                  fontSize: 12, fontWeight: FontWeight.w800),
              children: [
                TextSpan(text: widget.label),
                if (widget.required)
                  const TextSpan(
                      text: ' *',
                      style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.helper!,
              style:
                  const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 10),

          // === Preview أَو Placeholder ===
          if (_url != null)
            InkWell(
              onTap: _preview,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  _url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image,
                        size: 40, color: Colors.grey),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2));
                  },
                ),
              ),
            )
          else
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.grey.shade300, style: BorderStyle.solid),
              ),
              alignment: Alignment.center,
              child: _uploading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(strokeWidth: 2),
                        const SizedBox(height: 8),
                        Text(
                          isAr ? 'جارٍ الرَفع...' : 'Uploading...',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined,
                            size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text(
                          isAr ? 'لا توجد صورة' : 'No image',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
            ),

          const SizedBox(height: 8),

          // === Action buttons ===
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _pickFromCamera,
                  icon: const Icon(Icons.photo_camera, size: 16),
                  label: Text(isAr ? 'كاميرا' : 'Camera',
                      style: const TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: Text(isAr ? 'مَعرِض' : 'Gallery',
                      style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_url != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _remove,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.danger),
                  tooltip: isAr ? 'حَذف' : 'Remove',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
