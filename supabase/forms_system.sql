-- ============================================================
-- 📋 نظام النماذج الديناميكيّة (Forms System)
-- المكوّنات: قوالب + طلبات + إجراءات (workflow)
-- ============================================================

-- ============================================================
-- 1) قوالب النماذج
-- ============================================================
create table if not exists form_templates (
  id              uuid primary key default gen_random_uuid(),
  code            text unique,                      -- LEAVE-REQ / LOAN-REQ / SALARY-CERT...
  name_ar         text not null,
  name_en         text not null,
  description_ar  text,
  description_en  text,
  category        text not null default 'general',  -- leave/loan/certificate/training/...
  icon            text,                             -- اسم Material icon
  reference_file_url text,                          -- صورة/PDF المرجعي
  schema_json     jsonb not null default '[]'::jsonb,  -- تعريف الحقول
  workflow_json   jsonb not null default '[]'::jsonb,  -- خطوات الموافقة
  permissions_json jsonb not null default '{}'::jsonb, -- من يَملأ، من يَطّلع
  country_id      uuid references countries(id) on delete set null,
  is_active       boolean not null default true,
  sort_order      int     not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists idx_form_templates_category
  on form_templates(category);
create index if not exists idx_form_templates_active
  on form_templates(is_active, sort_order);

-- ============================================================
-- 2) طلبات (نسخ من القوالب)
-- ============================================================
create table if not exists form_submissions (
  id              uuid primary key default gen_random_uuid(),
  form_no         text not null,                    -- LV-AE-0001 رقم تسلسلي
  template_id     uuid not null references form_templates(id) on delete restrict,
  employee_id     uuid references employees(id) on delete cascade,
  submitted_by    uuid,                             -- معرّف الحساب الذي قدّم
  country_id      uuid references countries(id),
  data_json       jsonb not null default '{}'::jsonb,  -- الإجابات
  status          text not null default 'draft',
  -- draft | submitted | in_review | approved | rejected | cancelled
  current_step    int  not null default 0,          -- خطوة الـ workflow الحالية
  total_steps     int  not null default 0,
  rejection_reason text,
  created_at      timestamptz not null default now(),
  submitted_at    timestamptz,
  completed_at    timestamptz
);

create index if not exists idx_form_submissions_employee
  on form_submissions(employee_id);
create index if not exists idx_form_submissions_status
  on form_submissions(status, current_step);
create index if not exists idx_form_submissions_template
  on form_submissions(template_id);
create index if not exists idx_form_submissions_country
  on form_submissions(country_id);

-- ============================================================
-- 3) إجراءات / سجلّ الموافقات
-- ============================================================
create table if not exists form_submission_actions (
  id              uuid primary key default gen_random_uuid(),
  submission_id   uuid not null references form_submissions(id) on delete cascade,
  step_index      int  not null,
  actor_id        uuid,                             -- الحساب الذي نفّذ الإجراء
  actor_role      text,                             -- supervisor / manager / hr ...
  action          text not null,                    -- approve | reject | comment | submit
  comment         text,
  signature_data  text,                             -- بيانات التوقيع (إن وُجد)
  created_at      timestamptz not null default now()
);

create index if not exists idx_form_actions_submission
  on form_submission_actions(submission_id);

-- ============================================================
-- RLS — قراءة وكتابة للدورين anon + authenticated
-- ============================================================
alter table form_templates enable row level security;
alter table form_submissions enable row level security;
alter table form_submission_actions enable row level security;

-- form_templates
drop policy if exists "Read form_templates" on form_templates;
drop policy if exists "Write form_templates" on form_templates;
create policy "Read form_templates" on form_templates for select
  to anon, authenticated using (true);
create policy "Write form_templates" on form_templates for all
  to anon, authenticated using (true) with check (true);

-- form_submissions
drop policy if exists "Read form_submissions" on form_submissions;
drop policy if exists "Write form_submissions" on form_submissions;
create policy "Read form_submissions" on form_submissions for select
  to anon, authenticated using (true);
create policy "Write form_submissions" on form_submissions for all
  to anon, authenticated using (true) with check (true);

-- form_submission_actions
drop policy if exists "Read form_actions" on form_submission_actions;
drop policy if exists "Write form_actions" on form_submission_actions;
create policy "Read form_actions" on form_submission_actions for select
  to anon, authenticated using (true);
create policy "Write form_actions" on form_submission_actions for all
  to anon, authenticated using (true) with check (true);

-- ============================================================
-- 4) قاعدة الترقيم (FRM-{COUNTRY}-{####})
-- ============================================================
insert into entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values (
  'form_submission', 'طلب نموذج', 'Form Submission',
  'FRM', '-', 4, 1, true
) on conflict (technical_id) do nothing;

-- ============================================================
-- 5) قالب جاهز: «طلب إجازة» (مطابق للـ docx المرفق)
-- ============================================================
insert into form_templates (
  code, name_ar, name_en, description_ar, description_en,
  category, icon, schema_json, workflow_json, sort_order
) values (
  'LEAVE-REQ',
  'طلب إجازة',
  'Leave Request',
  'تقديم طلب إجازة سنويّة/مرضيّة/أمومة/وفاة/غير مدفوعة',
  'Submit annual / sick / maternity / bereavement / unpaid leave',
  'leave',
  'beach_access',
  '[
    {"key":"name","type":"text","label_ar":"الاسم","label_en":"Name","auto":"employee.fullName","required":true},
    {"key":"number","type":"text","label_ar":"الرقم","label_en":"Number","auto":"employee.code","required":true},
    {"key":"site","type":"text","label_ar":"الموقع","label_en":"Site","auto":"employee.point","required":false},
    {"key":"date","type":"date","label_ar":"التاريخ","label_en":"Date","auto":"today","required":true},
    {"key":"leave_type","type":"radio","label_ar":"نوع الإجازة","label_en":"Leave Type","required":true,
     "options":[
       {"value":"annual","label_ar":"سنوية","label_en":"Annual"},
       {"value":"sick","label_ar":"مرضية","label_en":"Sick"},
       {"value":"maternity","label_ar":"أمومة/أبوّة","label_en":"Maternity/Paternity"},
       {"value":"in_lieu","label_ar":"بدل عن يوم عطلة","label_en":"In Lieu of Day Off"},
       {"value":"bereavement","label_ar":"وفاة","label_en":"Bereavement"},
       {"value":"unpaid","label_ar":"غير مدفوعة","label_en":"Unpaid"}
     ]},
    {"key":"days","type":"number","label_ar":"عدد الأيام","label_en":"Days","required":true,"min":1,"max":90},
    {"key":"from","type":"date","label_ar":"من","label_en":"From","required":true},
    {"key":"to","type":"date","label_ar":"إلى","label_en":"To","required":true},
    {"key":"reason","type":"textarea","label_ar":"السبب","label_en":"Reason","required":false},
    {"key":"employee_signature","type":"signature","label_ar":"توقيع الموظف","label_en":"Employee Signature","required":true}
  ]'::jsonb,
  '[
    {"step":0,"role":"manager","label_ar":"المدير المباشر","label_en":"Direct Manager","require_signature":true},
    {"step":1,"role":"hr","label_ar":"الموارد البشرية","label_en":"HR Department","require_signature":true}
  ]'::jsonb,
  10
) on conflict (code) do nothing;

-- ============================================================
-- 6) قوالب أخرى جاهزة
-- ============================================================
insert into form_templates (code, name_ar, name_en, category, icon, schema_json, workflow_json, sort_order)
values
  ('LOAN-REQ', 'طلب سلفة', 'Loan Request', 'loan', 'attach_money',
   '[
     {"key":"name","type":"text","label_ar":"الاسم","label_en":"Name","auto":"employee.fullName","required":true},
     {"key":"amount","type":"number","label_ar":"المبلغ","label_en":"Amount","required":true,"min":1},
     {"key":"reason","type":"textarea","label_ar":"السبب","label_en":"Reason","required":true},
     {"key":"installments","type":"number","label_ar":"عدد الأقساط","label_en":"Installments","required":true,"min":1,"max":12},
     {"key":"signature","type":"signature","label_ar":"توقيع","label_en":"Signature","required":true}
   ]'::jsonb,
   '[
     {"step":0,"role":"manager","label_ar":"المدير المباشر","label_en":"Direct Manager","require_signature":true},
     {"step":1,"role":"hr","label_ar":"الموارد البشرية","label_en":"HR","require_signature":true}
   ]'::jsonb, 20),
  ('SALARY-CERT', 'طلب شهادة راتب', 'Salary Certificate', 'certificate', 'description',
   '[
     {"key":"purpose","type":"textarea","label_ar":"الغرض من الشهادة","label_en":"Purpose","required":true},
     {"key":"signature","type":"signature","label_ar":"توقيع","label_en":"Signature","required":true}
   ]'::jsonb,
   '[
     {"step":0,"role":"hr","label_ar":"الموارد البشرية","label_en":"HR","require_signature":true}
   ]'::jsonb, 30),
  ('RESIGNATION', 'استقالة', 'Resignation', 'resignation', 'logout',
   '[
     {"key":"last_day","type":"date","label_ar":"آخر يوم عمل","label_en":"Last Working Day","required":true},
     {"key":"reason","type":"textarea","label_ar":"السبب","label_en":"Reason","required":true},
     {"key":"signature","type":"signature","label_ar":"توقيع","label_en":"Signature","required":true}
   ]'::jsonb,
   '[
     {"step":0,"role":"manager","label_ar":"المدير المباشر","label_en":"Direct Manager","require_signature":true},
     {"step":1,"role":"hr","label_ar":"الموارد البشرية","label_en":"HR","require_signature":true}
   ]'::jsonb, 40)
on conflict (code) do nothing;
