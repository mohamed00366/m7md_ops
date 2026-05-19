-- ============================================================
-- 🆕 إضافة صلاحيّات Forms و Org إلى نظام RBAC
-- ============================================================
-- يُضيف 5 صلاحيّات جديدة:
--   - forms.submit   : تقديم طلبات/نماذج
--   - forms.approve  : الموافقة على طلبات
--   - forms.manage   : إدارة قوالب النماذج
--   - org.view       : عرض الهيكل التنظيمي
--   - org.manage     : تعديل الهيكل + إسناد النقاط
--
-- وأيضاً تُمنح كلّها لـ Super Admin تلقائياً (لكن Super Admin
-- يتجاوز الصلاحيّات في الكود، لذلك هذه احتياطيّة فقط)
-- ============================================================

insert into permissions (key, name_ar, name_en, module, description_ar, description_en)
values
  ('forms.submit', 'تقديم نموذج', 'Submit Form',
    'forms', 'تقديم طلبات النماذج', 'Submit form requests'),
  ('forms.approve', 'موافقة على نموذج', 'Approve Form',
    'forms', 'الموافقة على طلبات النماذج', 'Approve form requests'),
  ('forms.manage', 'إدارة قوالب النماذج', 'Manage Form Templates',
    'forms', 'إنشاء/تعديل/حذف قوالب النماذج', 'Create/edit/delete form templates'),
  ('org.view', 'عرض الهيكل التنظيمي', 'View Org Chart',
    'org', 'عرض شجرة الأقسام والمسمّيات', 'View department & title tree'),
  ('org.manage', 'إدارة الهيكل + الإسناد', 'Manage Org & Assignment',
    'org', 'تعديل الهيكل + إعدادات إسناد النقاط', 'Edit hierarchy + point assignment settings')
on conflict (key) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  module = excluded.module,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en;

-- ===== منح الصلاحيّات لـ Super Admin (احتياطيّاً) =====
-- ملاحظة: في الكود، Super Admin يتجاوز كلّ الصلاحيّات في `ModulesRegistry.visibleFor`
-- لكن نمنحها صراحةً هنا حتى تظهر بشكل صحيح في شاشة الصلاحيّات
do $$
declare
  v_super_admin_role uuid;
  v_perm_id uuid;
  perm_key text;
begin
  -- ابحث عن دور Super Admin
  select id into v_super_admin_role from roles where key = 'super_admin' limit 1;
  if v_super_admin_role is null then
    raise notice 'Super Admin role not found — skipping grant';
    return;
  end if;

  -- امنح كلّ صلاحيّة جديدة
  for perm_key in
    select unnest(array[
      'forms.submit', 'forms.approve', 'forms.manage',
      'org.view', 'org.manage'
    ])
  loop
    select id into v_perm_id from permissions where key = perm_key limit 1;
    if v_perm_id is not null then
      insert into role_permissions (role_id, permission_id)
      values (v_super_admin_role, v_perm_id)
      on conflict do nothing;
    end if;
  end loop;

  raise notice '✅ تمّ منح كلّ الصلاحيّات الجديدة لـ Super Admin';
end $$;

-- ===== التحقّق =====
select key, name_ar, name_en, module
from permissions
where key in (
  'forms.submit', 'forms.approve', 'forms.manage',
  'org.view', 'org.manage'
)
order by module, key;
