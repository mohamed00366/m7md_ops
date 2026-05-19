-- ============================================================
-- M7 W Management - بيانات اختبار: موظفون
-- آمن من التكرار: لو الموظف موجود (نفس الجوال) يتجاهل.
-- يستخدم consume_next_code RPC لتوليد رموز EMP-XX-####
-- ============================================================

-- ====== الدولة المستهدفة (غيّر 'SA' أو 'AE' أو 'EG') ======
do $$
declare
  v_country_id uuid;
  v_jt_supervisor uuid;
  v_jt_security uuid;
  v_jt_driver uuid;
  v_jt_cleaner uuid;
  v_dept_ops uuid;
  v_nat_eg uuid;
  v_nat_sa uuid;
  v_visa_work uuid;
  v_code text;
  v_inserted int := 0;

  -- نوع المصفوفة لكل موظف
  emp record;
begin
  -- اختر الدولة
  select id into v_country_id from public.countries where code = 'SA' limit 1;
  if v_country_id is null then
    raise exception 'Country SA not found. Add country first.';
  end if;

  -- ========== المسميات الوظيفية ==========
  insert into public.job_titles (name_ar, name_en)
    select 'مشرف', 'Supervisor'
    where not exists (select 1 from public.job_titles where name_en = 'Supervisor');
  insert into public.job_titles (name_ar, name_en)
    select 'حارس أمن', 'Security Guard'
    where not exists (select 1 from public.job_titles where name_en = 'Security Guard');
  insert into public.job_titles (name_ar, name_en)
    select 'سائق', 'Driver'
    where not exists (select 1 from public.job_titles where name_en = 'Driver');
  insert into public.job_titles (name_ar, name_en)
    select 'عامل نظافة', 'Cleaner'
    where not exists (select 1 from public.job_titles where name_en = 'Cleaner');

  select id into v_jt_supervisor from public.job_titles where name_en = 'Supervisor' limit 1;
  select id into v_jt_security   from public.job_titles where name_en = 'Security Guard' limit 1;
  select id into v_jt_driver     from public.job_titles where name_en = 'Driver' limit 1;
  select id into v_jt_cleaner    from public.job_titles where name_en = 'Cleaner' limit 1;

  -- ========== القسم ==========
  insert into public.departments (name_ar, name_en)
    select 'العمليات', 'Operations'
    where not exists (select 1 from public.departments where name_en = 'Operations');
  select id into v_dept_ops from public.departments where name_en = 'Operations' limit 1;

  -- ========== الجنسيات ==========
  insert into public.nationalities (name_ar, name_en)
    select 'مصري', 'Egyptian'
    where not exists (select 1 from public.nationalities where name_en = 'Egyptian');
  insert into public.nationalities (name_ar, name_en)
    select 'سعودي', 'Saudi'
    where not exists (select 1 from public.nationalities where name_en = 'Saudi');
  select id into v_nat_eg from public.nationalities where name_en = 'Egyptian' limit 1;
  select id into v_nat_sa from public.nationalities where name_en = 'Saudi' limit 1;

  -- ========== نوع التأشيرة ==========
  insert into public.visa_types (name_ar, name_en)
    select 'عمل', 'Work'
    where not exists (select 1 from public.visa_types where name_en = 'Work');
  select id into v_visa_work from public.visa_types where name_en = 'Work' limit 1;

  -- ========== الموظفون التجريبيون (8 موظفين) ==========
  for emp in
    select * from (values
      ('+966500000001', 'أحمد محمد علي',       'ahmad.ali@test.com',  'supervisor', v_nat_eg, 4500, null::text,  null::date, (current_date - 365)),
      ('+966500000002', 'خالد عبدالله السعيد',  'khaled.s@test.com',   'supervisor', v_nat_sa, 5500, null::text,  null::date, (current_date - 600)),
      ('+966500000003', 'محمود حسن إبراهيم',    null::text,            'security',   v_nat_eg, 2500, null::text,  null::date, (current_date - 200)),
      ('+966500000004', 'يوسف سامي رضا',        null::text,            'security',   v_nat_eg, 2500, null::text,  null::date, (current_date - 150)),
      ('+966500000005', 'كريم مصطفى عمر',       null::text,            'security',   v_nat_eg, 2500, null::text,  null::date, (current_date - 100)),
      ('+966500000006', 'عمر فاروق طارق',       null::text,            'driver',     v_nat_eg, 3000, 'DL-998877', (current_date + 730), (current_date - 400)),
      ('+966500000007', 'سعيد ناصر القحطاني',   null::text,            'driver',     v_nat_sa, 3500, 'DL-112233', (current_date + 540), (current_date - 800)),
      ('+966500000008', 'إبراهيم سيد رشاد',     null::text,            'cleaner',    v_nat_eg, 2000, null::text,  null::date, (current_date - 50))
    ) as t(mobile, full_name, email, role, nat_id, salary, license_no, license_expiry, joining_date)
  loop
    -- تخطّى لو الجوال موجود
    if exists (select 1 from public.employees where mobile = emp.mobile) then
      continue;
    end if;

    -- ولّد كود من العدّاد
    v_code := public.consume_next_code('employee', v_country_id);

    insert into public.employees (
      code, full_name, mobile, email,
      job_title_id, department_id, nationality_id, visa_type_id,
      basic_salary, status, country_id, joining_date,
      license_number, license_expiry
    ) values (
      v_code,
      emp.full_name,
      emp.mobile,
      emp.email,
      case emp.role
        when 'supervisor' then v_jt_supervisor
        when 'security'   then v_jt_security
        when 'driver'     then v_jt_driver
        when 'cleaner'    then v_jt_cleaner
      end,
      v_dept_ops,
      emp.nat_id,
      case when emp.nat_id = v_nat_sa then null else v_visa_work end,
      emp.salary,
      'active',
      v_country_id,
      emp.joining_date,
      emp.license_no,
      emp.license_expiry
    );
    v_inserted := v_inserted + 1;
  end loop;

  raise notice 'Seed completed. % new employees inserted (others already existed) for country %',
    v_inserted, v_country_id;
end $$;

-- ====== التحقق ======
select e.code, e.full_name, e.mobile, jt.name_ar as job_title, e.basic_salary, e.status
from public.employees e
left join public.job_titles jt on jt.id = e.job_title_id
where e.country_id = (select id from public.countries where code = 'SA')
order by e.code;
