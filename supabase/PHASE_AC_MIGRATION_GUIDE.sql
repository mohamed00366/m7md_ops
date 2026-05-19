-- ============================================================
-- 🚀 Phase A: ترحيل Org Hierarchy + Workflow Engine إلى Supabase
-- ------------------------------------------------------------
-- هذا الملف هو **دليل الترتيب** لتشغيل ملفات الـ SQL.
-- شغّل الملفات بالترتيب التالي عبر Supabase SQL Editor:
--
--   1) org_hierarchy.sql           — يضيف parent_id/level + reports_to
--   2) extend_job_titles.sql       — يضيف color/dashboard_type/approval_power
--   3) seed_operational_roles.sql  — يبذر 26 مسمّى مع الهرم الكامل
--   4) forms_system.sql            — يُنشئ form_templates/submissions/actions
--   5) dedupe_roles.sql            — تنظيف الأدوار المكرّرة (إن وُجدت)
--   6) هذا الملف                   — يحلّ التحقّق النهائيّ
--
-- بعد تشغيل كل الملفات أعلاه، شغّل المقاطع التالية للتحقّق:
-- ============================================================

-- ===== 1) تحقّق: حقول job_titles الجديدة موجودة =====
do $$
declare
  missing_cols text;
begin
  select string_agg(col, ', ')
    into missing_cols
    from (
      select unnest(array['level','color','dashboard_type','allowed_screens',
                          'approval_power','kpi_targets','notification_rules'])
        as col
    ) needed
    where col not in (
      select column_name
        from information_schema.columns
        where table_name = 'job_titles'
    );
  if missing_cols is not null then
    raise exception '❌ حقول مفقودة في job_titles: %', missing_cols;
  else
    raise notice '✅ كل حقول job_titles الغنيّة موجودة';
  end if;
end $$;

-- ===== 2) تحقّق: جدول job_title_reports_to موجود =====
do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_name = 'job_title_reports_to'
  ) then
    raise exception '❌ جدول job_title_reports_to مفقود — شغّل org_hierarchy.sql';
  end if;
  raise notice '✅ جدول job_title_reports_to موجود';
end $$;

-- ===== 3) تحقّق: حقول departments الجديدة =====
do $$
declare
  missing_cols text;
begin
  select string_agg(col, ', ')
    into missing_cols
    from (
      select unnest(array['parent_id','level']) as col
    ) needed
    where col not in (
      select column_name from information_schema.columns
        where table_name = 'departments'
    );
  if missing_cols is not null then
    raise exception '❌ حقول مفقودة في departments: %', missing_cols;
  else
    raise notice '✅ حقول departments الهرميّة موجودة';
  end if;
end $$;

-- ===== 4) تحقّق: جداول النماذج موجودة =====
do $$
declare
  missing_tables text;
begin
  select string_agg(t, ', ')
    into missing_tables
    from (
      select unnest(array['form_templates','form_submissions','form_submission_actions']) as t
    ) needed
    where t not in (
      select table_name from information_schema.tables
    );
  if missing_tables is not null then
    raise exception '❌ جداول نماذج مفقودة: %', missing_tables;
  else
    raise notice '✅ كل جداول النماذج موجودة';
  end if;
end $$;

-- ===== 5) إحصاءات التحقّق =====
select
  (select count(*) from job_titles)                       as total_job_titles,
  (select count(*) from job_titles where dashboard_type is not null)
                                                          as titles_with_dashboard,
  (select count(*) from job_titles where approval_power > 0)
                                                          as approver_titles,
  (select count(*) from job_title_reports_to)             as hierarchy_links,
  (select count(*) from departments where parent_id is not null)
                                                          as nested_departments,
  (select count(*) from form_templates)                   as form_templates,
  (select count(*) from form_submissions)                 as form_submissions;

-- ===== 6) RLS — تأكّد أن كل الجداول الجديدة مفتوحة للقراءة =====
-- (سياسات مبسّطة — التطبيق يستخدم RBAC داخلياً)

alter table job_title_reports_to enable row level security;

drop policy if exists "open read job_title_reports_to" on job_title_reports_to;
create policy "open read job_title_reports_to" on job_title_reports_to
  for select to anon, authenticated using (true);

drop policy if exists "open write job_title_reports_to" on job_title_reports_to;
create policy "open write job_title_reports_to" on job_title_reports_to
  for all to anon, authenticated using (true) with check (true);

-- ===== 7) ✅ كل شيء جاهز =====
do $$
begin
  raise notice '════════════════════════════════════════';
  raise notice '✅ Phase A جاهز للاستخدام في التطبيق';
  raise notice '════════════════════════════════════════';
end $$;
