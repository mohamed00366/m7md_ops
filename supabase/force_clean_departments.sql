-- ============================================================
-- 🧹 تنظيف نهائيّ صارم للأقسام
-- ============================================================
-- المشكلة: مكرّرات بنفس الاسم العربي لكن name_en مختلف
--   مثل: 'إدارة العمليات' / 'Operations'
--    و: 'إدارة العمليات' / 'Operations Department'
--
-- الحلّ:
--   1. لكلّ قسم رسميّ → اختر canonical (الأقدم بنفس name_ar)
--   2. ادمج كلّ المكرّرات إلى الـ canonical
--   3. وحّد الاسم الإنجليزي
--   4. احذف أيّ قسم لا يطابق القائمة الرسميّة
-- ============================================================

-- ===== 1) دمج المكرّرات حسب name_ar =====
do $$
declare
  rec record;
  v_canonical uuid;
  v_dup uuid;
begin
  for rec in
    select name_ar, count(*) as cnt
    from departments
    where name_ar is not null
    group by name_ar
    having count(*) > 1
  loop
    -- canonical = الأقدم
    select id into v_canonical
    from departments
    where name_ar = rec.name_ar
    order by id
    limit 1;

    -- ادمج كلّ المكرّرات
    for v_dup in
      select id from departments
      where name_ar = rec.name_ar and id <> v_canonical
    loop
      -- نقل الموظفين
      update employees set department_id = v_canonical
      where department_id = v_dup;

      -- نقل parent_id (لو قسم آخر يشير للمكرّر)
      update departments set parent_id = v_canonical
      where parent_id = v_dup;

      -- احذف المكرّر
      delete from departments where id = v_dup;
    end loop;

    raise notice 'دُمج: %', rec.name_ar;
  end loop;
end $$;

-- ===== 2) توحيد الأسماء الإنجليزيّة للأسماء الرسميّة =====
update departments set name_en = 'Operations Department'
  where name_ar = 'إدارة العمليات';
update departments set name_en = 'Transportation Department'
  where name_ar = 'إدارة النقل';
update departments set name_en = 'Human Resources Department'
  where name_ar = 'إدارة الموارد البشرية';
update departments set name_en = 'Finance Department'
  where name_ar = 'الإدارة المالية';
update departments set name_en = 'Customer Service Department'
  where name_ar = 'إدارة خدمة العملاء';
update departments set name_en = 'IT Department'
  where name_ar = 'إدارة تقنية المعلومات';
update departments set name_en = 'Procurement & Maintenance Department'
  where name_ar = 'إدارة المشتريات والصيانة';

-- ===== 3) حذف الأقسام غير الرسميّة (التي لا تطابق القائمة) =====
-- أوّلاً: انقل أيّ موظف على قسم غير رسميّ إلى NULL
update employees set department_id = null
where department_id in (
  select id from departments
  where name_ar not in (
    'إدارة العمليات',
    'إدارة النقل',
    'إدارة الموارد البشرية',
    'الإدارة المالية',
    'إدارة خدمة العملاء',
    'إدارة تقنية المعلومات',
    'إدارة المشتريات والصيانة'
  )
);

-- فكّ علاقات parent_id
update departments set parent_id = null
where parent_id in (
  select id from departments
  where name_ar not in (
    'إدارة العمليات',
    'إدارة النقل',
    'إدارة الموارد البشرية',
    'الإدارة المالية',
    'إدارة خدمة العملاء',
    'إدارة تقنية المعلومات',
    'إدارة المشتريات والصيانة'
  )
);

-- احذف الأقسام غير الرسميّة
delete from departments
where name_ar not in (
  'إدارة العمليات',
  'إدارة النقل',
  'إدارة الموارد البشرية',
  'الإدارة المالية',
  'إدارة خدمة العملاء',
  'إدارة تقنية المعلومات',
  'إدارة المشتريات والصيانة'
);

-- ===== 4) إن نقص قسم رسميّ → أضِفه =====
insert into departments (name_ar, name_en, category)
select * from (values
  ('إدارة العمليات', 'Operations Department', 'operations'),
  ('إدارة النقل', 'Transportation Department', 'operations'),
  ('إدارة الموارد البشرية', 'Human Resources Department', 'admin'),
  ('الإدارة المالية', 'Finance Department', 'admin'),
  ('إدارة خدمة العملاء', 'Customer Service Department', 'operations'),
  ('إدارة تقنية المعلومات', 'IT Department', 'admin'),
  ('إدارة المشتريات والصيانة',
    'Procurement & Maintenance Department', 'operations')
) as v(name_ar, name_en, category)
where not exists (
  select 1 from departments d where d.name_ar = v.name_ar
);

-- ===== 5) ضبط category =====
update departments set category = 'operations'
where name_ar in (
  'إدارة العمليات',
  'إدارة النقل',
  'إدارة خدمة العملاء',
  'إدارة المشتريات والصيانة'
);

update departments set category = 'admin'
where name_ar in (
  'إدارة الموارد البشرية',
  'الإدارة المالية',
  'إدارة تقنية المعلومات'
);

-- ===== 6) التحقّق =====
-- يجب أن يُرجع 7 أسطر فقط
select name_ar, name_en, category
from departments
order by name_en;

-- ولا تكرارات
select name_ar, count(*) as cnt
from departments
group by name_ar
having count(*) > 1;
-- يجب أن يكون فارغاً ✅
