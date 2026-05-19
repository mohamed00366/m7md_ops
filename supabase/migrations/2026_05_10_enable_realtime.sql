-- ============================================================
-- ⚡ تَفعيل Realtime على الجَداول الحَسّاسة
-- ============================================================
-- يَجعَل التَطبيق يَستَقبِل تَحديثات مُباشِرة عند تَغيير البيانات
-- من أيّ جِهاز/مُستَخدِم آخَر — بدون الحاجة لإعادة فَتح التَطبيق.
--
-- يَعتَمد على publication `supabase_realtime` المُتَوَفِّر افتراضيّاً.
-- ============================================================


-- ============================================================
-- 🆕 الخَطوة 1: أَضِف الجَداول إلى publication
-- ============================================================
-- لو الجَدول مَوجود مُسبَقاً في الـpublication، الإضافة تُتَجاهَل.

DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'notifications',          -- 🔔 الإشعارات (الأَهَمّ)
    'employees',              -- 👥 الموظَّفون
    'accounts',               -- 🔐 الحسابات
    'rosters',                -- 📅 الروسترات
    'roster_assignments',     -- 📋 توزيع الورديات
    'bus_plans',              -- 🚌 خُطط الباصات
    'bus_plan_details',
    'employee_bus_assignments',
    'employee_daily_memos',   -- 📝 المذكّرات
    'employee_daily_memo_entries',
    'employee_leave_requests',-- 🏖️ الإجازات
    'employee_leave_balances',
    'app_config',             -- ⚙ الإعدادات
    'points',                 -- 📍 النِقاط
    'sites',                  -- 🏢 المَواقع
    'buses',                  -- 🚐 الباصات
    'violations',             -- ⚠ المخالفات
    'rooms',                  -- 🛏 الغُرَف
    'audit_log'               -- 📜 السِجلّ (للمُتابَعة)
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    BEGIN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE %I',
        v_table
      );
      RAISE NOTICE '✅ أُضيف: %', v_table;
    EXCEPTION
      WHEN duplicate_object THEN
        RAISE NOTICE '⏭ مَوجود مُسبَقاً: %', v_table;
      WHEN undefined_table THEN
        RAISE NOTICE '⏭ الجَدول غَير مَوجود: %', v_table;
      WHEN OTHERS THEN
        RAISE NOTICE '⚠ خَطأ في %: %', v_table, SQLERRM;
    END;
  END LOOP;
END $$;


-- ============================================================
-- ✅ تَحقُّق
-- ============================================================
SELECT
  '✅ الجَداول المُفَعَّلة' AS step,
  string_agg(tablename, ', ' ORDER BY tablename) AS tables,
  COUNT(*) AS count
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';


-- ============================================================
-- 🆕 الخَطوة 2: تَأكَّد من REPLICA IDENTITY = FULL
-- ============================================================
-- يُساعِد Supabase Realtime في إرسال البيانات الكامِلة عند DELETE.
-- (افتراضيّاً يُرسِل id فَقَط)

ALTER TABLE notifications              REPLICA IDENTITY FULL;
ALTER TABLE accounts                   REPLICA IDENTITY FULL;
-- الباقي اختياريّ — فَعِّله لو احتَجتَ DELETE events:
-- ALTER TABLE employees                  REPLICA IDENTITY FULL;
-- ALTER TABLE rosters                    REPLICA IDENTITY FULL;
-- ALTER TABLE employee_leave_requests    REPLICA IDENTITY FULL;


-- ============================================================
-- 🧪 لِحَذف جَدول من Realtime لاحِقاً (لو لَزم)
-- ============================================================
-- ALTER PUBLICATION supabase_realtime DROP TABLE table_name;


-- ============================================================
-- 📊 الجَداول الحاليّة في publication
-- ============================================================
SELECT
  tablename AS realtime_table
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;
