-- ============================================================
-- 🧹 MEGA CLEAN — يُصلح كلّ التكرارات والمسمّيات الزائدة
-- ============================================================
-- شغّل هذا الملفّ مرّة واحدة في Supabase SQL Editor
-- يُصلح:
--   1. الأقسام المكرّرة + الزائدة (يُبقي 7 فقط)
--   2. المسمّيات الوظيفيّة المكرّرة + الزائدة (~21)
--   3. الأدوار المكرّرة
--   4. علاقات reports_to تُعاد بناؤها صحيحة
--   5. المستويات تُضبط حسب الهرم الرسميّ
-- ============================================================

-- ============================================================
-- PART 1: تنظيف الأقسام
-- ============================================================

-- 1A) دمج المكرّرات حسب name_ar
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
    select id into v_canonical from departments
    where name_ar = rec.name_ar order by id limit 1;

    for v_dup in
      select id from departments
      where name_ar = rec.name_ar and id <> v_canonical
    loop
      update employees set department_id = v_canonical
        where department_id = v_dup;
      update departments set parent_id = v_canonical
        where parent_id = v_dup;
      delete from departments where id = v_dup;
    end loop;
  end loop;
end $$;

-- 1B) فكّ ربط الموظفين عن الأقسام غير الرسميّة
update employees set department_id = null
where department_id in (
  select id from departments
  where name_ar not in (
    'إدارة العمليات', 'إدارة النقل', 'إدارة الموارد البشرية',
    'الإدارة المالية', 'إدارة خدمة العملاء',
    'إدارة تقنية المعلومات', 'إدارة المشتريات والصيانة'
  )
);

-- 1C) فكّ علاقات parent_id قبل الحذف
update departments set parent_id = null
where parent_id in (
  select id from departments
  where name_ar not in (
    'إدارة العمليات', 'إدارة النقل', 'إدارة الموارد البشرية',
    'الإدارة المالية', 'إدارة خدمة العملاء',
    'إدارة تقنية المعلومات', 'إدارة المشتريات والصيانة'
  )
);

-- 1D) حذف الأقسام الزائدة
delete from departments
where name_ar not in (
  'إدارة العمليات', 'إدارة النقل', 'إدارة الموارد البشرية',
  'الإدارة المالية', 'إدارة خدمة العملاء',
  'إدارة تقنية المعلومات', 'إدارة المشتريات والصيانة'
);

-- 1E) إضافة أيّ قسم رسميّ ناقص
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

-- 1F) توحيد name_en
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

-- ============================================================
-- PART 2: تنظيف الأدوار
-- ============================================================

-- 2A) دمج المكرّرات حسب key
do $$
declare
  rec record;
  v_canonical uuid;
  v_dup uuid;
begin
  for rec in
    select key, count(*) as cnt from roles
    group by key having count(*) > 1
  loop
    select id into v_canonical from roles
    where key = rec.key order by id limit 1;

    for v_dup in
      select id from roles where key = rec.key and id <> v_canonical
    loop
      update user_roles set role_id = v_canonical
        where role_id = v_dup
        and user_id not in (select user_id from user_roles where role_id = v_canonical);
      delete from user_roles where role_id = v_dup;

      insert into role_permissions (role_id, permission_id)
      select v_canonical, permission_id from role_permissions
      where role_id = v_dup
      on conflict do nothing;
      delete from role_permissions where role_id = v_dup;

      update job_titles set role_id = v_canonical where role_id = v_dup;
      delete from roles where id = v_dup;
    end loop;
  end loop;
end $$;

-- ============================================================
-- PART 3: تنظيف المسمّيات الوظيفيّة
-- ============================================================

-- 3A) دمج المكرّرات حسب name_en
do $$
declare
  rec record;
  v_canonical uuid;
  v_dup uuid;
begin
  for rec in
    select name_en, count(*) as cnt from job_titles
    where name_en is not null
    group by name_en having count(*) > 1
  loop
    select id into v_canonical from job_titles
    where name_en = rec.name_en order by id limit 1;

    for v_dup in
      select id from job_titles
      where name_en = rec.name_en and id <> v_canonical
    loop
      update employees set job_title_id = v_canonical
        where job_title_id = v_dup;
      delete from job_title_reports_to
        where job_title_id = v_dup or reports_to_id = v_dup;
      delete from job_titles where id = v_dup;
    end loop;
  end loop;
end $$;

-- 3B) فكّ ربط الموظفين عن المسمّيات الزائدة
update employees set job_title_id = null
where job_title_id in (
  select id from job_titles
  where name_en in (
    'Employee', 'Shift Leader', 'Dispatch Coordinator',
    'Transport Supervisor', 'Bus Coordinator', 'Cashier',
    'Recruiter', 'Timekeeper', 'Customer Service Agent',
    'Complaint Officer', 'IT Support', 'Workshop Supervisor',
    'Technician'
  )
  or (name_ar in ('موظف', 'مشرف', 'مدير', 'سكرتير') and (
    name_en is null or name_en = '' or
    name_en not in (
      'Owner / Chairman', 'CEO / General Manager',
      'Operations Manager', 'Operation Manager',
      'Transportation Manager', 'HR Manager', 'Finance Manager',
      'Customer Service Supervisor', 'IT Manager',
      'Procurement Officer', 'Maintenance Supervisor',
      'Area Manager', 'Camp Boss', 'HR Officer', 'Accountant',
      'System Administrator', 'Site Supervisor', 'Bus Driver',
      'Auditor', 'Marshal', 'Key Controller', 'Valet Driver'
    )
  ))
);

-- 3C) حذف علاقات reports_to المرتبطة بالمسمّيات الزائدة
delete from job_title_reports_to
where job_title_id in (
  select id from job_titles
  where name_en in (
    'Employee', 'Shift Leader', 'Dispatch Coordinator',
    'Transport Supervisor', 'Bus Coordinator', 'Cashier',
    'Recruiter', 'Timekeeper', 'Customer Service Agent',
    'Complaint Officer', 'IT Support', 'Workshop Supervisor',
    'Technician'
  )
)
or reports_to_id in (
  select id from job_titles
  where name_en in (
    'Employee', 'Shift Leader', 'Dispatch Coordinator',
    'Transport Supervisor', 'Bus Coordinator', 'Cashier',
    'Recruiter', 'Timekeeper', 'Customer Service Agent',
    'Complaint Officer', 'IT Support', 'Workshop Supervisor',
    'Technician'
  )
);

-- 3D) حذف المسمّيات الزائدة
delete from job_titles
where name_en in (
  'Employee', 'Shift Leader', 'Dispatch Coordinator',
  'Transport Supervisor', 'Bus Coordinator', 'Cashier',
  'Recruiter', 'Timekeeper', 'Customer Service Agent',
  'Complaint Officer', 'IT Support', 'Workshop Supervisor',
  'Technician'
);

-- 3E) حذف المسمّيات اليتيمة بالعربيّة فقط (بدون role_id ولا تطابق الرسمي)
delete from job_titles
where name_ar in ('موظف', 'مشرف', 'مدير', 'سكرتير', 'موظف خدمة عملاء')
  and name_en not in (
    'Owner / Chairman', 'CEO / General Manager',
    'Operations Manager', 'Operation Manager',
    'Transportation Manager', 'HR Manager', 'Finance Manager',
    'Customer Service Supervisor', 'IT Manager',
    'Procurement Officer', 'Maintenance Supervisor',
    'Area Manager', 'Camp Boss', 'HR Officer', 'Accountant',
    'System Administrator', 'Site Supervisor', 'Bus Driver',
    'Auditor', 'Marshal', 'Key Controller', 'Valet Driver'
  );

-- 3F) ضبط المستويات النهائيّة
update job_titles set level = 1 where name_en in (
  'Owner / Chairman', 'CEO / General Manager');
update job_titles set level = 2 where name_en in (
  'Operations Manager', 'Operation Manager',
  'Transportation Manager', 'HR Manager', 'Finance Manager',
  'Customer Service Supervisor', 'IT Manager',
  'Procurement Officer', 'Maintenance Supervisor');
update job_titles set level = 3 where name_en in (
  'Area Manager', 'Camp Boss', 'HR Officer',
  'Accountant', 'System Administrator');
update job_titles set level = 4 where name_en in (
  'Site Supervisor', 'Bus Driver', 'Auditor');
update job_titles set level = 6 where name_en in (
  'Marshal', 'Key Controller', 'Valet Driver');

-- ============================================================
-- PART 4: التحقّق
-- ============================================================
select 'departments' as type, count(*) from departments
union all
select 'job_titles', count(*) from job_titles
union all
select 'job_titles_with_role', count(*) from job_titles where role_id is not null
union all
select 'roles', count(*) from roles
union all
select 'reports_to_links', count(*) from job_title_reports_to;

-- يجب أن يكون:
--   departments         = 7
--   job_titles          ≈ 21
--   job_titles_with_role ≈ 21
--   reports_to_links     ≈ 20
