-- ============================================================
-- M7 Nexus - Roster Job Title Filter
-- يضيف عمود job_title_ids للروستر بحيث يكون الروستر مخصصاً لمسمى/مسميات وظيفية محددة
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='weekly_rosters' AND column_name='job_title_ids'
  ) THEN
    ALTER TABLE public.weekly_rosters
      ADD COLUMN job_title_ids uuid[] NOT NULL DEFAULT '{}'::uuid[];
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_weekly_rosters_job_title_ids
  ON public.weekly_rosters USING GIN (job_title_ids);
