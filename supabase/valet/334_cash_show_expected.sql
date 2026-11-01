-- 334: Close shift – show the expected cash before the count (option of the point)
-- off (default) = blind count, the old way: the closer counts first, the expected cash shows after closing
alter table public.valet_point_settings add column if not exists nt_cash_show_expected boolean not null default false;
notify pgrst, 'reload schema';
