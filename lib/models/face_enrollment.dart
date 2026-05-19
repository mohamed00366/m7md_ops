/// 👤 وضعيّات تسجيل بصمة الوجه
enum FacePose {
  /// نظر مباشر للأمام (المرجع الأساسي)
  front,

  /// إمالة بسيطة لليمين (~15-25°)
  right,

  /// إمالة بسيطة لليسار (~15-25°)
  left,

  /// ابتسامة (تنوّع التعابير)
  smile,

  /// عينان مغمضتان قليلاً / إضاءة أو زاوية مختلفة
  variation,
}

extension FacePoseX on FacePose {
  String key() {
    switch (this) {
      case FacePose.front:
        return 'front';
      case FacePose.right:
        return 'right';
      case FacePose.left:
        return 'left';
      case FacePose.smile:
        return 'smile';
      case FacePose.variation:
        return 'variation';
    }
  }

  String labelAr() {
    switch (this) {
      case FacePose.front:
        return 'الوجه أمامي';
      case FacePose.right:
        return 'إمالة لليمين';
      case FacePose.left:
        return 'إمالة لليسار';
      case FacePose.smile:
        return 'ابتسامة';
      case FacePose.variation:
        return 'إغلاق العينين';
    }
  }

  String labelEn() {
    switch (this) {
      case FacePose.front:
        return 'Front';
      case FacePose.right:
        return 'Tilt right';
      case FacePose.left:
        return 'Tilt left';
      case FacePose.smile:
        return 'Smile';
      case FacePose.variation:
        return 'Eyes closed';
    }
  }

  String hintAr() {
    switch (this) {
      case FacePose.front:
        return 'انظر مباشرةً إلى الكاميرا واحتفظ بوجهك ضمن الإطار';
      case FacePose.right:
        return 'أدر رأسك قليلاً إلى اليمين (~20°)';
      case FacePose.left:
        return 'أدر رأسك قليلاً إلى اليسار (~20°)';
      case FacePose.smile:
        return 'ابتسم ابتسامة طبيعيّة';
      case FacePose.variation:
        return 'أغمض عينيك قليلاً (للتنوّع في التعرّف)';
    }
  }

  String hintEn() {
    switch (this) {
      case FacePose.front:
        return 'Look directly at the camera and keep your face in frame';
      case FacePose.right:
        return 'Turn your head slightly to the right (~20°)';
      case FacePose.left:
        return 'Turn your head slightly to the left (~20°)';
      case FacePose.smile:
        return 'Smile naturally';
      case FacePose.variation:
        return 'Close your eyes slightly (for variety)';
    }
  }

  static FacePose fromKey(String? k) {
    switch (k) {
      case 'right':
        return FacePose.right;
      case 'left':
        return FacePose.left;
      case 'smile':
        return FacePose.smile;
      case 'variation':
        return FacePose.variation;
      case 'front':
      default:
        return FacePose.front;
    }
  }
}

/// نموذج صورة تسجيل وجه واحد
class FaceEnrollment {
  final String id;
  final String employeeId;
  final String? accountId;
  final FacePose pose;
  final String? photoPath;     // المسار في bucket
  final String? photoUrl;      // signed URL
  final List<double>? embedding; // متّجه التعرّف (يُحسب لاحقاً في Phase D)
  final double qualityScore;   // 0..1
  final double faceWidthRatio; // عرض الوجه/عرض الصورة
  final double brightness;     // 0..1
  final double headAngleY;
  final double smileProbability;
  final DateTime enrolledAt;
  final String? enrolledBy;

  FaceEnrollment({
    required this.id,
    required this.employeeId,
    this.accountId,
    required this.pose,
    this.photoPath,
    this.photoUrl,
    this.embedding,
    required this.qualityScore,
    required this.faceWidthRatio,
    required this.brightness,
    required this.headAngleY,
    required this.smileProbability,
    required this.enrolledAt,
    this.enrolledBy,
  });
}
