-- ============================================================
-- 👤 تسجيل بصمات الوجه للموظفين
-- ============================================================
-- لكلّ موظّف 5 صور بزوايا مختلفة + embedding (يُحسب في Phase D)
-- ============================================================

-- 1) Bucket خاصّ (private — حسّاس)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'employee_faces',
  'employee_faces',
  false,
  10485760, -- 10 MB حدّ
  array['image/jpeg','image/jpg','image/png']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 2) سياسات الـ bucket
drop policy if exists "employee_faces_upload" on storage.objects;
create policy "employee_faces_upload"
  on storage.objects for insert to public
  with check (bucket_id = 'employee_faces');

drop policy if exists "employee_faces_read" on storage.objects;
create policy "employee_faces_read"
  on storage.objects for select to public
  using (bucket_id = 'employee_faces');

drop policy if exists "employee_faces_update" on storage.objects;
create policy "employee_faces_update"
  on storage.objects for update to public
  using (bucket_id = 'employee_faces');

drop policy if exists "employee_faces_delete" on storage.objects;
create policy "employee_faces_delete"
  on storage.objects for delete to public
  using (bucket_id = 'employee_faces');

-- 3) الجدول
create table if not exists public.employee_face_enrollments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  account_id uuid references public.accounts(id) on delete set null,
  pose text not null check (pose in ('front','right','left','smile','variation')),
  photo_path text,
  photo_url text,
  embedding jsonb,                 -- يُملأ في Phase D
  quality_score real default 0,
  face_width_ratio real default 0,
  brightness real default 0,
  head_angle_y real default 0,
  smile_probability real default 0,
  notes text,
  enrolled_at timestamptz default now(),
  enrolled_by uuid references public.accounts(id) on delete set null
);

create index if not exists idx_face_enroll_employee
  on public.employee_face_enrollments(employee_id);
create index if not exists idx_face_enroll_pose
  on public.employee_face_enrollments(employee_id, pose);

-- لكلّ موظّف، صورة واحدة فقط لكلّ وضعيّة (نُحدّث عند إعادة التسجيل)
create unique index if not exists ux_face_enroll_emp_pose
  on public.employee_face_enrollments(employee_id, pose);

-- 4) RLS
alter table public.employee_face_enrollments enable row level security;

drop policy if exists "face_enroll_all" on public.employee_face_enrollments;
create policy "face_enroll_all"
  on public.employee_face_enrollments for all to public
  using (true) with check (true);

-- 5) إضافة عمود "متى تمّ تسجيل البصمة" على جدول الموظفين (للسرعة)
alter table public.employees
  add column if not exists face_enrolled_at timestamptz;

alter table public.employees
  add column if not exists face_enrollment_count integer default 0;

-- 6) دالّة مساعدة: تحديث face_enrolled_at تلقائياً
create or replace function public.refresh_employee_face_meta()
returns trigger language plpgsql as $$
begin
  update public.employees
  set
    face_enrollment_count = (
      select count(*) from public.employee_face_enrollments
      where employee_id = coalesce(new.employee_id, old.employee_id)
    ),
    face_enrolled_at = (
      select max(enrolled_at) from public.employee_face_enrollments
      where employee_id = coalesce(new.employee_id, old.employee_id)
    )
  where id = coalesce(new.employee_id, old.employee_id);
  return null;
end;
$$;

drop trigger if exists trg_face_enroll_refresh on public.employee_face_enrollments;
create trigger trg_face_enroll_refresh
  after insert or update or delete on public.employee_face_enrollments
  for each row execute function public.refresh_employee_face_meta();

-- 7) صلاحيّات
insert into public.permissions (key, module, name_ar, name_en, description_ar, description_en)
values
  (
    'employees.face.enroll',
    'employees',
    'تسجيل بصمة وجه الموظّف',
    'Enroll employee face',
    'يستطيع التقاط صور وجه الموظّف لتفعيل الدخول ببصمة الوجه',
    'Can capture face photos for face login'
  ),
  (
    'employees.face.delete',
    'employees',
    'حذف بصمة وجه الموظّف',
    'Delete employee face enrollment',
    'يستطيع مسح بصمة الوجه المسجّلة لإعادة التسجيل',
    'Can delete face enrollment for re-enrollment'
  )
on conflict (key) do update set
  module = excluded.module,
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in ('employees.face.enroll', 'employees.face.delete')
where r.key in ('super_admin', 'admin', 'manager')
on conflict do nothing;

-- ============================================================
-- ✅ تحقّق
-- ============================================================
-- 1) الجدول
select table_name from information_schema.tables
where table_schema = 'public' and table_name = 'employee_face_enrollments';

-- 2) Bucket
select id, name, public from storage.buckets where id = 'employee_faces';

-- 3) عمودان جديدان على employees
select column_name from information_schema.columns
where table_schema='public' and table_name='employees'
  and column_name in ('face_enrolled_at','face_enrollment_count');

-- 4) الصلاحيّات
select key from public.permissions where key like 'employees.face.%';
