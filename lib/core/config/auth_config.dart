/// إعدادات المصادقة المركزية
class AuthConfig {
  /// الإيميل الرئيسي للنظام - كل بريد Supabase Auth يصل عليه
  /// يستخدم Plus-Aliases (Gmail/Outlook/إلخ) لتوليد إيميل فريد لكل حساب
  ///
  /// مثال:
  ///   centralEmail = 'admin@m7w.com'
  ///   user 'mohamed.ae' → 'admin+mohamed.ae@m7w.com'
  ///   كل البريد يصل لـ admin@m7w.com في صندوق واحد
  ///
  /// ⚠️ غيّر هذا الإيميل لإيميل شركتك الفعلي قبل الإطلاق
  static const String centralEmail = 'admin@m7w.com';

  /// يبني email Auth فريد لكل user من اسمه
  /// تنسيق: <local-part>+<username>@<domain>
  ///
  /// لو centralEmail = 'admin@example.com' وusername = 'mohamed'
  /// → 'admin+mohamed@example.com'
  static String emailFor(String username) {
    final clean = username.trim().toLowerCase();
    final parts = centralEmail.split('@');
    if (parts.length != 2) {
      // fallback لو الإيميل المركزي غير صحيح
      return '$clean@m7w.local';
    }
    final localPart = parts[0];
    final domain = parts[1];
    return '$localPart+$clean@$domain';
  }
}
