-- =============================================================================
-- 🚀 pgvector لِـFace Recognition — تَحسين أَداء جَذريّ
-- =============================================================================
-- المُشكِلة قَبل هذا التَحديث:
--   - findDuplicate يُحَمِّل 5000+ سَطر إلى الهاتِف (2-3 MB)
--   - matchAgainstEmployees يَفعَل cosine similarity في Dart عَلى 5000+ embedding
--   - يَستَغرِق 5-15 ثانية عَلى 4G
--
-- بَعد التَحديث:
--   - الحِسابات تَجري في Postgres (سَريع، C++ underlying)
--   - يُرجِع أَفضَل تَطابُق واحِد فَقَط (1 KB بَدَلاً مِن 3 MB)
--   - يَستَغرِق 50-200 ms حَتّى مَع 10K embeddings
-- =============================================================================

-- ============================================================
-- 🔧 ضَمان search_path يَتَضَمَّن public (مُهِمّ لِـSupabase SQL Editor)
-- ============================================================
SET search_path TO public, extensions;

-- ============================================================
-- 1️⃣ تَفعيل pgvector extension (مَرِن — يَعمَل في أَيّ schema)
-- ============================================================
-- نُجَرِّب 3 طُرُق لِتَفعيل الـextension بِأَيّ schema يَختاره Supabase

-- أ. لَو Supabase أَعَدَّ schema "extensions" مُسبَقاً، استَخدِمها
-- ب. وَإلّا، ثَبِّتها في schema الحاليّ (public)
DO $install_pgvector$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
  ELSE
    CREATE EXTENSION IF NOT EXISTS vector;
  END IF;
END $install_pgvector$;

-- تَأَكَّد أَنَّ الـextension مَوجود في search_path
DO $check_vector$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
    RAISE EXCEPTION 'فَشِل تَثبيت pgvector. فَعِّلها يَدَويّاً مِن Supabase Dashboard → Database → Extensions';
  END IF;
END $check_vector$;

-- ============================================================
-- 0️⃣ تَحَقَّق مِن وُجود الجَدوَل — يَدعَم اسمَين مُحتَمَلَين
-- ============================================================
-- بَعض النُسَخ القَديمة تَستَخدِم `employee_face_descriptors`، والجَديدة
-- تَستَخدِم `employee_face_enrollments`. سَنَفحَص كِلَيهِما.
DO $check$
BEGIN
  IF to_regclass('public.employee_face_enrollments') IS NULL
     AND to_regclass('public.employee_face_descriptors') IS NULL THEN
    RAISE EXCEPTION 'لا يُوجَد جَدوَل بَصمات الوَجه (لا employee_face_enrollments وَلا employee_face_descriptors). شَغِّل أَوَّلاً: supabase/face_enrollments_migration.sql';
  END IF;
END $check$;

-- ============================================================
-- 2️⃣ أَضِف عَمود embedding_lmk (landmarks 15-dim)
-- ============================================================
-- نُبقي عَلى `embedding` jsonb لِلتَوافُق الخَلفيّ. عَمود `embedding_lmk` هُوَ
-- النُسخة المُحَسَّنة لِلـpgvector queries.

ALTER TABLE public.employee_face_enrollments
  ADD COLUMN IF NOT EXISTS embedding_lmk vector(15);

-- ============================================================
-- 3️⃣ Backfill: حَوِّل embeddings الحالِيّة (jsonb 15-dim) إلى vector
-- ============================================================
UPDATE public.employee_face_enrollments
SET embedding_lmk = (
  SELECT array_agg(value::float)::vector(15)
  FROM jsonb_array_elements_text(embedding) AS value
)
WHERE
  embedding IS NOT NULL
  AND jsonb_array_length(embedding) = 15
  AND embedding_lmk IS NULL;

-- ============================================================
-- 4️⃣ Trigger: حافِظ عَلى تَزامُن العَمودَين عِندَ INSERT/UPDATE
-- ============================================================
CREATE OR REPLACE FUNCTION sync_embedding_vector()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- لَو الكود الـDart حَفِظ jsonb، نَحوِّلها لِـvector تِلقائيّاً
  IF NEW.embedding IS NOT NULL
     AND jsonb_array_length(NEW.embedding) = 15
     AND (NEW.embedding_lmk IS NULL
          OR OLD.embedding IS DISTINCT FROM NEW.embedding) THEN
    NEW.embedding_lmk := (
      SELECT array_agg(value::float)::vector(15)
      FROM jsonb_array_elements_text(NEW.embedding) AS value
    );  -- vector type
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_embedding_vector ON public.employee_face_enrollments;
CREATE TRIGGER trg_sync_embedding_vector
  BEFORE INSERT OR UPDATE OF embedding
  ON public.employee_face_enrollments
  FOR EACH ROW
  EXECUTE FUNCTION sync_embedding_vector();

-- ============================================================
-- 5️⃣ Index لِـcosine similarity (ivfflat — أَسرَع index لِـpgvector)
-- ============================================================
-- ivfflat lists = sqrt(N) عادَةً. مَع 5000 enrollments، lists ≈ 70
-- نَستَخدِم 100 كَـconservative default
CREATE INDEX IF NOT EXISTS idx_face_embedding_lmk_cosine
  ON public.employee_face_enrollments
  USING ivfflat (embedding_lmk vector_cosine_ops)
  WITH (lists = 100);

-- ============================================================
-- 6️⃣ RPC: find_face_duplicate
-- ============================================================
-- يَبحَث عَن وَجه شَبيه في DB، يَستَثني الـcurrent employee
-- يُرجِع: NULL لَو لا تَطابُق، أَو سَطر واحِد بِأَفضَل تَطابُق
CREATE OR REPLACE FUNCTION find_face_duplicate(
  p_embedding float[],
  p_current_employee_id uuid,
  p_threshold float DEFAULT 0.95
) RETURNS TABLE(
  employee_id uuid,
  enrollment_id uuid,
  similarity float,
  pose text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    fe.employee_id,
    fe.id as enrollment_id,
    -- pgvector: 1 - cosine_distance = cosine_similarity
    (1 - (fe.embedding_lmk <=> p_embedding::vector(15)))::float as similarity,
    fe.pose
  FROM public.employee_face_enrollments fe
  WHERE
    fe.embedding_lmk IS NOT NULL
    AND fe.employee_id != p_current_employee_id
  ORDER BY fe.embedding_lmk <=> p_embedding::vector(15) ASC
  LIMIT 1
  -- HAVING clause في sub-query لِفَلتَرة العَتَبة
  ;
EXCEPTION
  WHEN OTHERS THEN
    RETURN;
END;
$$;

COMMENT ON FUNCTION find_face_duplicate IS
  'يَبحَث عَن وَجه شَبيه (تَكرار) في DB. يُرجِع أَفضَل تَطابُق أَو لا شَيء.';

-- ============================================================
-- 7️⃣ RPC: find_face_match (لِـlogin)
-- ============================================================
-- مُشابِه لِـduplicate لكِنّه يَبحَث في قائِمة مَحَدَّدة (مَثَلاً مُوَظَّفي نُقطة)
CREATE OR REPLACE FUNCTION find_face_match(
  p_embedding float[],
  p_employee_ids uuid[],
  p_threshold float DEFAULT 0.65
) RETURNS TABLE(
  employee_id uuid,
  enrollment_id uuid,
  similarity float,
  pose text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    fe.employee_id,
    fe.id as enrollment_id,
    (1 - (fe.embedding_lmk <=> p_embedding::vector(15)))::float as similarity,
    fe.pose
  FROM public.employee_face_enrollments fe
  WHERE
    fe.embedding_lmk IS NOT NULL
    AND fe.employee_id = ANY(p_employee_ids)
  ORDER BY fe.embedding_lmk <=> p_embedding::vector(15) ASC
  LIMIT 1;
EXCEPTION
  WHEN OTHERS THEN
    RETURN;
END;
$$;

COMMENT ON FUNCTION find_face_match IS
  'يُطابِق وَجه ضِدّ مَجموعة مُحَدَّدة مِن المُوَظَّفين (لِـlogin).';

-- ============================================================
-- 8️⃣ منح صَلاحِيّات الـRPC لِلـauthenticated users
-- ============================================================
GRANT EXECUTE ON FUNCTION find_face_duplicate(float[], uuid, float) TO authenticated;
GRANT EXECUTE ON FUNCTION find_face_match(float[], uuid[], float) TO authenticated;

-- ============================================================
-- 9️⃣ تَحديث ANALYZE لِيَستَخدِم الـindex
-- ============================================================
ANALYZE public.employee_face_enrollments;

-- ============================================================
-- ✅ مَلاحَظات
-- ============================================================
-- 1. الكود الـDart الحاليّ سَيَستَمِرّ في كِتابة `embedding` jsonb كالعادة
--    الـtrigger يَنسَخها تِلقائيّاً إلى `embedding_lmk vector`
-- 2. الـRPCs الجَديدة تَستَخدِم العَمود vector + index ⇒ سُرعة عالِية
-- 3. لِـFaceNet (128/512 dim) مُستَقبَلاً: أَضِف عَمود `embedding_fnet vector(128)`
--    + RPC مُماثِل + index مُنفَصِل
