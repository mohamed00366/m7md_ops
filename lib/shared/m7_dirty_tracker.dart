import 'package:flutter/material.dart';

/// 🆕 Mixin لِتَتَبُّع حالة «تَعديلات لَم تُحفَظ» لِأَيّ شاشة قِسم
///
/// **الاستِخدام:**
/// ```dart
/// class _MyState extends State<MyScreen> with M7DirtyTrackerMixin<MyScreen> {
///   @override void initState() {
///     super.initState();
///     track(_nameController); // مُراقَبة تِلقائيّة
///   }
///   // عِند تَغيير dropdown/date — استَدعِ markDirty();
/// }
/// ```
mixin M7DirtyTrackerMixin<T extends StatefulWidget> on State<T> {
  bool _dirty = false;
  bool get isDirty => _dirty;

  /// أَشِّر أَنّ هُناك تَعديلاً غَير مَحفوظ
  void markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  /// إعادة تَعيين الحالة (بَعد الحِفظ النّاجِح مَثَلاً)
  void clearDirty() {
    if (_dirty && mounted) setState(() => _dirty = false);
  }

  /// رَبط مُتَحَكِّم نَصّيّ لِيُؤَشِّر دَفتَر التَعديلات تِلقائيّاً عِند الكِتابة
  void track(TextEditingController c) => c.addListener(markDirty);

  /// رَبط عِدّة مُتَحَكِّمات مَرّة واحِدة
  void trackAll(Iterable<TextEditingController> cs) {
    for (final c in cs) {
      track(c);
    }
  }
}

/// نافِذة تَأكيد قَبل التَراجُع عَن تَعديلات غَير مَحفوظة
Future<bool?> showM7DiscardDialog(BuildContext context, {bool? isAr}) {
  // ignore: invalid_use_of_protected_member
  final ar = isAr ?? (Directionality.of(context) == TextDirection.rtl);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 36),
      title: Text(
        ar ? 'تَعديلات غَير مَحفوظة' : 'Unsaved changes',
        textAlign: TextAlign.center,
      ),
      content: Text(
        ar
            ? 'لَم يَتِمّ حِفظ تَعديلاتك. هَل تُريد تَرك الصَفحة وَفُقدان التَغييرات؟'
            : 'Your changes have not been saved. Discard and leave?',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ar ? 'البَقاء' : 'Stay'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(ar ? 'تَرك وَفُقدان' : 'Discard'),
        ),
      ],
    ),
  );
}
