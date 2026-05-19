import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_method_settings.dart';

/// 🔒 متعقّب محاولات بصمة الوجه الفاشلة
///
/// المنطق المتدرّج:
///   1) فشل المحاولات الأولى (1، 2، 3) → تهدئة 3 دقائق
///   2) أثناء التهدئة، التطبيق يُغلق ولا يفتح
///   3) فشل الجولة الثانية (4، 5، 6) → قفل الحساب
///   4) المسؤول يفكّ القفل من شاشة المستخدمين
///
/// يعمل لكلّ حساب على حدة.
class FaceAttemptTracker extends ChangeNotifier {
  FaceAttemptTracker._();
  static final instance = FaceAttemptTracker._();

  static const _kFailedCount = 'face_fail_count_';     // + accountId
  static const _kCooldownUntil = 'face_cooldown_until_'; // + accountId
  static const _kLockedFlag = 'face_locked_';          // + accountId

  // ===== Public API =====

  /// تسجيل فشل محاولة. يُرجع الحالة الجديدة.
  Future<FaceAttemptStatus> recordFailure(String accountId) async {
    await LoginMethodSettings.instance.load();
    final settings = LoginMethodSettings.instance;
    final p = await SharedPreferences.getInstance();
    var count = (p.getInt('$_kFailedCount$accountId') ?? 0) + 1;
    await p.setInt('$_kFailedCount$accountId', count);

    final maxAttempts = settings.maxAttempts; // 3 بالافتراضي
    final cooldown = settings.cooldownMinutes; // 3 دقائق

    // الجولة الأولى انتهت → ابدأ التهدئة
    if (count == maxAttempts) {
      final until = DateTime.now()
          .add(Duration(minutes: cooldown))
          .toIso8601String();
      await p.setString('$_kCooldownUntil$accountId', until);
      notifyListeners();
      return FaceAttemptStatus(
        outcome: FaceAttemptOutcome.cooldown,
        failedCount: count,
        cooldownUntil: DateTime.parse(until),
      );
    }

    // الجولة الثانية انتهت → قفل
    if (count >= maxAttempts * 2) {
      await p.setBool('$_kLockedFlag$accountId', true);
      await p.remove('$_kCooldownUntil$accountId');
      notifyListeners();
      return FaceAttemptStatus(
        outcome: FaceAttemptOutcome.locked,
        failedCount: count,
      );
    }

    // فشل عادي
    notifyListeners();
    return FaceAttemptStatus(
      outcome: FaceAttemptOutcome.failed,
      failedCount: count,
    );
  }

  /// تسجيل نجاح → نُصفّر العدّاد
  Future<void> recordSuccess(String accountId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_kFailedCount$accountId');
    await p.remove('$_kCooldownUntil$accountId');
    notifyListeners();
  }

  /// فحص الحالة الحاليّة للحساب
  Future<FaceAttemptStatus> currentStatus(String accountId) async {
    final p = await SharedPreferences.getInstance();
    final locked = p.getBool('$_kLockedFlag$accountId') ?? false;
    final count = p.getInt('$_kFailedCount$accountId') ?? 0;

    if (locked) {
      return FaceAttemptStatus(
        outcome: FaceAttemptOutcome.locked,
        failedCount: count,
      );
    }

    final cooldownStr = p.getString('$_kCooldownUntil$accountId');
    if (cooldownStr != null) {
      final until = DateTime.tryParse(cooldownStr);
      if (until != null && DateTime.now().isBefore(until)) {
        return FaceAttemptStatus(
          outcome: FaceAttemptOutcome.cooldown,
          failedCount: count,
          cooldownUntil: until,
        );
      } else {
        // التهدئة انتهت → امسحها
        await p.remove('$_kCooldownUntil$accountId');
      }
    }

    return FaceAttemptStatus(
      outcome: FaceAttemptOutcome.allowed,
      failedCount: count,
    );
  }

  /// فكّ القفل (Admin only)
  Future<void> unlockAccount(String accountId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_kLockedFlag$accountId');
    await p.remove('$_kFailedCount$accountId');
    await p.remove('$_kCooldownUntil$accountId');
    notifyListeners();
  }

  /// قفل يدوي (Admin only)
  Future<void> lockAccount(String accountId) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('$_kLockedFlag$accountId', true);
    notifyListeners();
  }

  /// معرفة كل الحسابات المقفلة (للوحة المسؤول)
  Future<List<String>> lockedAccounts() async {
    final p = await SharedPreferences.getInstance();
    return p
        .getKeys()
        .where((k) =>
            k.startsWith(_kLockedFlag) &&
            (p.getBool(k) ?? false))
        .map((k) => k.substring(_kLockedFlag.length))
        .toList();
  }
}

enum FaceAttemptOutcome {
  allowed,    // يُسمح بالمحاولة
  failed,     // فشلت محاولة لكن لم تكتمل الجولة
  cooldown,   // في فترة التهدئة (3 دقائق)
  locked,     // الحساب مقفل (يحتاج المسؤول)
}

class FaceAttemptStatus {
  final FaceAttemptOutcome outcome;
  final int failedCount;
  final DateTime? cooldownUntil;

  const FaceAttemptStatus({
    required this.outcome,
    required this.failedCount,
    this.cooldownUntil,
  });

  Duration? get remainingCooldown {
    if (cooldownUntil == null) return null;
    final r = cooldownUntil!.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }
}
