-- 333: valet touches on the tablet (key tag, ticket tear line, parking bays in the board bar, empty board / loading car)
-- option of the point, on by default (E design only); off = the plain look
alter table public.valet_point_settings add column if not exists nt_valet_touches boolean not null default true;
notify pgrst, 'reload schema';
