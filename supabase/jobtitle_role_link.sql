-- ============================================================
-- M7 Nexus - JobTitle ↔ Role Hard Link
-- 1) Adds role_id FK on job_titles
-- 2) For each existing job_title without a role: create + link a role
-- 3) Trigger to auto-create role when a new job_title is inserted
-- 4) Trigger to keep role names in sync with job_title names
-- Idempotent.
-- ============================================================

-- ====== A) Add role_id column =============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='role_id'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN role_id uuid REFERENCES public.role_defs(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_job_titles_role_id ON public.job_titles(role_id);


-- ====== B) Helper: derive a role key from English name =====================
CREATE OR REPLACE FUNCTION public._jt_role_key(p_name_en text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v_key text;
BEGIN
  v_key := lower(coalesce(p_name_en,''));
  v_key := regexp_replace(v_key, '[^a-z0-9]+', '_', 'g');
  v_key := trim(both '_' from v_key);
  IF v_key IS NULL OR v_key = '' THEN
    v_key := 'role_' || substr(md5(random()::text), 1, 8);
  END IF;
  RETURN v_key;
END;
$$;


-- ====== C) Backfill: create role for each unlinked job_title ===============
DO $$
DECLARE
  r RECORD;
  v_role_id uuid;
  v_key text;
BEGIN
  FOR r IN
    SELECT id, name_ar, name_en
      FROM public.job_titles
     WHERE role_id IS NULL
  LOOP
    v_key := public._jt_role_key(r.name_en);

    -- Ensure the key is unique across role_defs
    IF EXISTS (SELECT 1 FROM public.role_defs WHERE key = v_key) THEN
      v_key := v_key || '_' || substr(md5(r.id::text), 1, 4);
    END IF;

    INSERT INTO public.role_defs (id, key, name_ar, name_en, is_system, priority)
    VALUES (uuid_generate_v4(), v_key, r.name_ar, r.name_en, false, 10)
    RETURNING id INTO v_role_id;

    UPDATE public.job_titles SET role_id = v_role_id WHERE id = r.id;
  END LOOP;
END $$;


-- ====== D) Trigger: auto-create role on job_title insert ==================
CREATE OR REPLACE FUNCTION public.fn_jt_auto_create_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_role_id uuid;
  v_key text;
BEGIN
  IF NEW.role_id IS NOT NULL THEN
    RETURN NEW; -- already linked
  END IF;

  v_key := public._jt_role_key(NEW.name_en);
  IF EXISTS (SELECT 1 FROM public.role_defs WHERE key = v_key) THEN
    v_key := v_key || '_' || substr(md5(NEW.id::text), 1, 4);
  END IF;

  INSERT INTO public.role_defs (id, key, name_ar, name_en, is_system, priority)
  VALUES (uuid_generate_v4(), v_key, NEW.name_ar, NEW.name_en, false, 10)
  RETURNING id INTO v_role_id;

  NEW.role_id := v_role_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jt_auto_create_role ON public.job_titles;
CREATE TRIGGER trg_jt_auto_create_role
  BEFORE INSERT ON public.job_titles
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_jt_auto_create_role();


-- ====== E) Trigger: keep role names synced with job_title names ===========
CREATE OR REPLACE FUNCTION public.fn_jt_sync_role_names()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.role_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF (NEW.name_ar IS DISTINCT FROM OLD.name_ar)
     OR (NEW.name_en IS DISTINCT FROM OLD.name_en) THEN
    UPDATE public.role_defs
       SET name_ar = NEW.name_ar,
           name_en = NEW.name_en
     WHERE id = NEW.role_id
       AND is_system = false; -- never rename system roles
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jt_sync_role_names ON public.job_titles;
CREATE TRIGGER trg_jt_sync_role_names
  AFTER UPDATE OF name_ar, name_en ON public.job_titles
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_jt_sync_role_names();


-- ====== F) Verification ====================================================
-- SELECT j.name_ar AS jt, r.name_ar AS role, r.key
--   FROM public.job_titles j
--   LEFT JOIN public.role_defs r ON r.id = j.role_id
--   ORDER BY j.name_ar;
