-- ============================================================
-- 🔧 إصلاح خاصّ: دمج "Operation Manager" مع "Operations Manager"
-- ============================================================
-- المشكلة: سجلّان مختلفان بنفس name_ar (مدير العمليات):
--   1. 'Operation Manager'  (مفرد — من البذر القديم)
--   2. 'Operations Manager' (جمع — من التحديثات)
-- نريد توحيدهما في سجلّ واحد.
-- ============================================================

do $$
declare
  v_canonical uuid;
  v_dup uuid;
begin
  -- canonical = 'Operations Manager' (الجمع — الرسمي حسب الهرم)
  select id into v_canonical from job_titles
  where name_en = 'Operations Manager' limit 1;

  -- إذا لم يوجد بالجمع، خذ المفرد كـ canonical وحدّث اسمه
  if v_canonical is null then
    select id into v_canonical from job_titles
    where name_en = 'Operation Manager' limit 1;
    if v_canonical is not null then
      update job_titles
      set name_en = 'Operations Manager'
      where id = v_canonical;
    end if;
  end if;

  if v_canonical is null then
    raise notice 'لا يوجد Operations Manager في DB';
    return;
  end if;

  -- ابحث عن المكرّر (المفرد) ودمج
  for v_dup in
    select id from job_titles
    where (name_en = 'Operation Manager' or name_ar = 'مدير العمليات')
      and id <> v_canonical
  loop
    update employees set job_title_id = v_canonical
      where job_title_id = v_dup;
    update job_title_reports_to set job_title_id = v_canonical
      where job_title_id = v_dup
      and not exists (
        select 1 from job_title_reports_to r2
        where r2.job_title_id = v_canonical
          and r2.reports_to_id = job_title_reports_to.reports_to_id
      );
    delete from job_title_reports_to where job_title_id = v_dup;
    update job_title_reports_to set reports_to_id = v_canonical
      where reports_to_id = v_dup
      and not exists (
        select 1 from job_title_reports_to r2
        where r2.reports_to_id = v_canonical
          and r2.job_title_id = job_title_reports_to.job_title_id
      );
    delete from job_title_reports_to where reports_to_id = v_dup;
    delete from job_titles where id = v_dup;
    raise notice 'دُمج: %', v_dup;
  end loop;

  -- ضبط الـ canonical نهائياً
  update job_titles
  set name_ar = 'مدير العمليات',
      name_en = 'Operations Manager',
      level = 2
  where id = v_canonical;
end $$;

-- ============================================================
-- نفس المنطق لكلّ مسمّى مكرّر بنفس name_ar
-- (احتياط لأيّ مسمّى مكرّر مماثل)
-- ============================================================
do $$
declare
  rec record;
  v_canonical uuid;
  v_dup uuid;
begin
  for rec in
    select name_ar, count(*) as cnt
    from job_titles
    where name_ar is not null
    group by name_ar
    having count(*) > 1
  loop
    -- canonical = الذي له role_id (إن أمكن)، وإلا الأقدم
    select id into v_canonical from job_titles
    where name_ar = rec.name_ar
    order by (case when role_id is not null then 0 else 1 end), id
    limit 1;

    for v_dup in
      select id from job_titles
      where name_ar = rec.name_ar and id <> v_canonical
    loop
      update employees set job_title_id = v_canonical
        where job_title_id = v_dup;
      delete from job_title_reports_to
        where job_title_id = v_dup or reports_to_id = v_dup;
      delete from job_titles where id = v_dup;
    end loop;

    raise notice 'دُمج المكرّرات لـ: %', rec.name_ar;
  end loop;
end $$;

-- ============================================================
-- التحقّق
-- ============================================================
-- لا يوجد مسمّى عربي مكرّر
select name_ar, count(*) as cnt
from job_titles
group by name_ar
having count(*) > 1;
-- يجب أن يكون فارغاً ✅

-- لا يوجد مسمّى إنجليزي مكرّر
select name_en, count(*) as cnt
from job_titles
where name_en is not null
group by name_en
having count(*) > 1;
-- يجب أن يكون فارغاً ✅

-- إجمالي المسمّيات
select count(*) as total_job_titles from job_titles;
