-- ============================================================
-- 🎓 إضافة صلاحيّات OnPoint Training إلى نظام RBAC
-- ============================================================
-- 3 صلاحيّات جديدة:
--   1. training.onpoint.view     — رؤية صفحة "تدريب الجدد"
--   2. training.onpoint.evaluate — اعتماد/رفض المتدرّب
--   3. training.onpoint.manage   — إعدادات صفحة التدريب
-- ============================================================

-- 1) أنشئ الصلاحيّات في جدول permissions
insert into public.permissions (key, module, name_ar, name_en, description_ar, description_en)
values
  (
    'training.onpoint.view',
    'training',
    'رؤية تدريب الجدد',
    'View OnPoint Training',
    'يمكنه فتح صفحة تدريب الموظفين الجدد',
    'Can open the new-employee training page'
  ),
  (
    'training.onpoint.evaluate',
    'training',
    'اعتماد/رفض المتدرّب',
    'Approve/Reject Trainee',
    'يحقّ له اعتماد أو رفض المتدرّب بعد انتهاء فترة التدريب',
    'Can approve or reject a trainee after training'
  ),
  (
    'training.onpoint.manage',
    'training',
    'إدارة إعدادات تدريب الجدد',
    'Manage OnPoint Settings',
    'يحقّ له تعديل إعدادات صفحة التدريب (المدّة، المعتمِدون، التوقيعات)',
    'Can edit training page settings (duration, approvers, signatures)'
  )
on conflict (key) do update
  set name_ar = excluded.name_ar,
      name_en = excluded.name_en,
      description_ar = excluded.description_ar,
      description_en = excluded.description_en;

-- 2) أعطِ الصلاحيّات للأدوار المناسبة
-- Super Admin: تلقائيّاً (له كلّ الصلاحيّات بدون role_permissions)
-- Operation Manager: view + evaluate
-- HR Manager: view + manage (لتعديل الإعدادات)
-- Admin: الكل
do $$
declare
  v_view_id uuid;
  v_eval_id uuid;
  v_manage_id uuid;
  v_role record;
begin
  select id into v_view_id from public.permissions where key = 'training.onpoint.view';
  select id into v_eval_id from public.permissions where key = 'training.onpoint.evaluate';
  select id into v_manage_id from public.permissions where key = 'training.onpoint.manage';

  -- Operation Manager: view + evaluate
  for v_role in select id from public.roles where key in ('operation','operation_manager')
  loop
    insert into public.role_permissions (role_id, permission_id) values
      (v_role.id, v_view_id),
      (v_role.id, v_eval_id)
    on conflict do nothing;
  end loop;

  -- HR / HR Manager: view + manage
  for v_role in select id from public.roles where key in ('hr','hr_manager')
  loop
    insert into public.role_permissions (role_id, permission_id) values
      (v_role.id, v_view_id),
      (v_role.id, v_manage_id)
    on conflict do nothing;
  end loop;

  -- Admin: الكل
  for v_role in select id from public.roles where key in ('admin','manager')
  loop
    insert into public.role_permissions (role_id, permission_id) values
      (v_role.id, v_view_id),
      (v_role.id, v_eval_id),
      (v_role.id, v_manage_id)
    on conflict do nothing;
  end loop;

  raise notice '✅ صلاحيّات OnPoint Training أُضيفت ووُزّعت على الأدوار';
end $$;

-- ============================================================
-- التحقّق
-- ============================================================
-- الصلاحيّات الـ3 موجودة
select key, name_ar, name_en
from public.permissions
where key like 'training.onpoint.%'
order by key;
-- المتوقّع 3 صفوف ✅

-- مَن مَنُحَت له
select r.key as role, p.key as permission
from public.role_permissions rp
join public.roles r on r.id = rp.role_id
join public.permissions p on p.id = rp.permission_id
where p.key like 'training.onpoint.%'
order by r.key, p.key;
