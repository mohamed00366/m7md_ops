/// إعدادات Supabase
///
/// **انتبه**: استخدم publishable (anon) key فقط في كود التطبيق.
/// مفتاح secret_role لا يجوز أن يكون في تطبيق العميل أبداً.
class SupabaseConfig {
  /// رابط مشروعك
  static const String url = 'https://weftpekmmesgfhdawutj.supabase.co';

  /// publishable (anon) key — آمن للاستخدام في التطبيق
  static const String anonKey =
      'sb_publishable_mpGl1t33_k36OPXVYeflHA_HVTonx_V';

  /// تفعيل/تعطيل الاتصال بـ Supabase
  /// عند false: التطبيق يستخدم MockRepository فقط
  /// عند true: التطبيق يحاول الاتصال بـ Supabase عند الإقلاع
  static const bool enabled = true;
}
