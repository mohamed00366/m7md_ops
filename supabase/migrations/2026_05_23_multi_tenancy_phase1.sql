-- =============================================================================
-- 🏢 Multi-tenancy — Phase 1: Scaffolding (tenant_id + helpers + RLS layer)
-- =============================================================================
-- **النَطاق:** هذه أَوَّل مَرحَلة فَقَط. تُضيف:
--   1. جَدوَل `tenants` (المُؤَسَّسات)
--   2. `tenant_id` كَعَمود اختِياريّ عَلى كُلّ جَدوَل مُهِمّ
--   3. دالّة `auth_tenant_id()` لِقِراءة الـtenant مِن JWT claim
--   4. RLS scaffolding: السياسات الجَديدة تَفلِتر بِناءً عَلى `tenant_id`
--      (مَع backward compatibility — السَجِلّات الحالِيّة بِـtenant_id=NULL
--      تَبقى مَرئيّة لِكُلّ المُستَخدِمين، حَتّى نُهاجِر تَدريجيّاً).
--
-- **ما لا تُغَيِّره هذه المَرحَلة:**
--   • لا تُجبِر tenant_id على السَجِلّات الجَديدة (NULL مَسموح حالياً)
--   • لا تُدخِل tenant_id في الـJWT تِلقائيّاً (يَحتاج Auth Hook لاحِقاً)
--   • لا تُغَيِّر RLS الحالِيّ — تُضيف policies جَديدة كَطَبَقة فَوقِيّة
--
-- المَرحَلة 2 (لاحِقاً): إجبار tenant_id + JWT claim + backfill.
-- =============================================================================

-- ============================================================================
-- 1️⃣ جَدوَل tenants
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.tenants (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar     TEXT NOT NULL,
  name_en     TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL, -- مَثَلاً 'h-holding'
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO tenants (name_ar, name_en, slug)
VALUES ('H Holding', 'H Holding', 'h-holding')
ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- 2️⃣ tenant_id عَلى الجَداوِل الرَئيسيّة
-- ============================================================================
-- نُضيف tenant_id كَـnullable حالياً. الـmigration الـ2 سَيَفرِض NOT NULL.

DO $migrate$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'accounts', 'employees', 'sites', 'points', 'departments',
    'job_titles', 'roles', 'permissions',
    'rosters', 'roster_approvals',
    'deductions', 'leave_requests', 'attendances',
    'driver_tips', 'custom_reports',
    'employee_documents', 'employee_status_changes',
    'database_backups', 'settings_audit_log'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = t) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id)',
        t
      );
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS idx_%I_tenant_id ON public.%I(tenant_id) WHERE tenant_id IS NOT NULL',
        t, t
      );
    END IF;
  END LOOP;
END;
$migrate$;

-- ============================================================================
-- 3️⃣ دالّة auth_tenant_id() — تَقرَأ tenant مِن JWT claim
-- ============================================================================
-- المُتَوَقَّع: claim باسم 'tenant_id' في الـJWT يُضاف عَبر Supabase Auth Hook
-- (سَيُضاف في المَرحَلة 2). حالياً تُرجِع NULL — وَذلِك يَجعَل كُلّ السَجِلّات
-- مَرئيّة (backward compatible).

CREATE OR REPLACE FUNCTION public.auth_tenant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v UUID;
BEGIN
  -- مُحاوَلة 1: مِن JWT claim
  BEGIN
    v := (current_setting('request.jwt.claims', true)::jsonb -> 'tenant_id')::text::uuid;
  EXCEPTION WHEN OTHERS THEN
    v := NULL;
  END;
  -- مُحاوَلة 2: مِن accounts.tenant_id إذا الـclaim مَفقود
  IF v IS NULL AND auth.uid() IS NOT NULL THEN
    BEGIN
      SELECT tenant_id INTO v
      FROM accounts
      WHERE id = auth.uid()
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v := NULL;
    END;
  END IF;
  RETURN v;
END;
$func$;

COMMENT ON FUNCTION public.auth_tenant_id() IS
  'يُرجِع tenant_id لِلمُستَخدِم الحاليّ. NULL = خاصِيّة backward-compat تَجعَل كُلّ السَجِلّات مَرئيّة (Phase 1 فَقَط).';

-- ============================================================================
-- 4️⃣ مُساعِد is_tenant_match — فَلتَر RLS بِناءً عَلى tenant
-- ============================================================================
-- مَنطِق:
--   • لَو السَجِلّ tenant_id = NULL → مَرئيّ لِلكُلّ (backward compat)
--   • لَو المُستَخدِم بِدون tenant claim → مَرئيّ لِلكُلّ (Super Admin أَو مَرحَلة 1)
--   • وَإلّا: tenant مُطابِق

CREATE OR REPLACE FUNCTION public.is_tenant_match(record_tenant UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  user_tenant UUID;
BEGIN
  user_tenant := auth_tenant_id();
  -- Phase 1: لَو لا tenant عَلى السَجِلّ أَو لا tenant لِلمُستَخدِم → اِسمَح
  IF record_tenant IS NULL OR user_tenant IS NULL THEN
    RETURN TRUE;
  END IF;
  RETURN record_tenant = user_tenant;
END;
$func$;

COMMENT ON FUNCTION public.is_tenant_match(UUID) IS
  'يُرجِع TRUE لَو tenant السَجِلّ يُطابِق tenant المُستَخدِم (مَع backward compat لِـNULL).';

-- ============================================================================
-- 5️⃣ RLS layer: نُضيف policy جَديدة لِكُلّ جَدوَل تَفلِتر بِالـtenant
-- ============================================================================
-- لا نَحذِف الـpolicies الحالِيّة — نُضيف فَوقها. النِظام يَتَطَلَّب أَن
-- تُوافِق كُلّ الـpolicies (USING)، فَإضافة policy جَديدة بِشَرط tenant
-- لا يَكسِر شَيء بِسَبَب الـbackward compat في is_tenant_match.

DO $tenant_rls$
DECLARE
  t TEXT;
  policy_name TEXT;
  tables TEXT[] := ARRAY[
    'employees', 'sites', 'points', 'departments', 'job_titles',
    'rosters', 'deductions', 'leave_requests', 'attendances',
    'driver_tips', 'custom_reports'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = t
                 AND column_name = 'tenant_id') THEN
      policy_name := 'rls_tenant_scope_' || t;
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', policy_name, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL '
        'USING (is_tenant_match(tenant_id))',
        policy_name, t
      );
    END IF;
  END LOOP;
END;
$tenant_rls$;

-- ============================================================================
-- 6️⃣ تَوثيق سَريع
-- ============================================================================
COMMENT ON TABLE tenants IS 'المُؤَسَّسات المُسَجَّلة في النِظام (Multi-tenancy Phase 1)';
