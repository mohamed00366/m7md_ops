-- 335: Printing tab of a point — membership receipt and key rack report layouts (like receipt_layout / shift_layout),
-- and the paper width for the point (null = each device decides, the old way).
alter table public.valet_point_settings add column if not exists member_layout jsonb;
alter table public.valet_point_settings add column if not exists keyrack_layout jsonb;
alter table public.valet_point_settings add column if not exists paper_mm integer check (paper_mm in (58, 80));
notify pgrst, 'reload schema';
