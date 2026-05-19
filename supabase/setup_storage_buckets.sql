-- ============================================================
-- 🪣 إعداد Storage Buckets على Supabase
-- ============================================================
-- ينشئ الـ buckets المطلوبة لرفع الصور عبر التطبيق:
--   • employee_photos      — صور الموظفين (Public)
--   • id_cards             — صور الهويّات (Private)
--   • licenses             — صور الرخص (Private)
--   • work_letters         — خطابات العمل (Private)
--   • training_certificates — شهادات التدريب (Public للعرض)
--   • onpoint_attachments  — مرفقات تدريب OnPoint (Private)
-- ============================================================

-- ⚠️ ملاحظة: في Supabase Dashboard → Storage
-- يمكنك إنشاء الـ buckets يدويّاً أو عبر SQL أدناه

-- 1) buckets عامّة (الصور الظاهرة في الواجهة)
insert into storage.buckets (id, name, public)
values
  ('employee_photos', 'employee_photos', true),
  ('training_certificates', 'training_certificates', true)
on conflict (id) do update set public = excluded.public;

-- 2) buckets خاصّة (وثائق حسّاسة)
insert into storage.buckets (id, name, public)
values
  ('id_cards', 'id_cards', false),
  ('licenses', 'licenses', false),
  ('work_letters', 'work_letters', false),
  ('onpoint_attachments', 'onpoint_attachments', false)
on conflict (id) do update set public = excluded.public;

-- ============================================================
-- 3) سياسات RLS للـ buckets
-- ============================================================

-- ===== employee_photos (Public) =====
-- قراءة: مفتوح للجميع (Public bucket = signed URL ليس مطلوباً)
-- رفع: المصادَق عليه فقط
drop policy if exists "employee_photos_upload" on storage.objects;
create policy "employee_photos_upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'employee_photos');

drop policy if exists "employee_photos_update" on storage.objects;
create policy "employee_photos_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'employee_photos');

drop policy if exists "employee_photos_delete" on storage.objects;
create policy "employee_photos_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'employee_photos');

-- ===== id_cards / licenses / work_letters (Private) =====
-- يقرأها فقط من له صلاحيّة employees.view
drop policy if exists "private_docs_read" on storage.objects;
create policy "private_docs_read"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('id_cards','licenses','work_letters','onpoint_attachments')
    and (
      public.is_super_admin()
      or public.has_permission('employees.view')
    )
  );

drop policy if exists "private_docs_upload" on storage.objects;
create policy "private_docs_upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('id_cards','licenses','work_letters','onpoint_attachments')
    and (
      public.is_super_admin()
      or public.has_permission('employees.edit')
      or public.has_permission('employee.documents.manage')
    )
  );

drop policy if exists "private_docs_update" on storage.objects;
create policy "private_docs_update"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('id_cards','licenses','work_letters','onpoint_attachments')
    and (
      public.is_super_admin()
      or public.has_permission('employees.edit')
    )
  );

-- ===== training_certificates (Public للعرض) =====
drop policy if exists "training_certs_upload" on storage.objects;
create policy "training_certs_upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'training_certificates'
    and (
      public.is_super_admin()
      or public.has_permission('training.onpoint.evaluate')
      or public.has_permission('training.onpoint.manage')
    )
  );

-- ============================================================
-- ✅ التحقّق
-- ============================================================
-- الـ buckets موجودة
select id, name, public
from storage.buckets
where id in (
  'employee_photos',
  'id_cards',
  'licenses',
  'work_letters',
  'training_certificates',
  'onpoint_attachments'
)
order by id;
-- المتوقّع: 6 صفوف ✅

-- السياسات مفعّلة
select policyname, cmd
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like '%employee_photos%'
     or policyname like '%private_docs%'
     or policyname like '%training_certs%'
order by policyname;
