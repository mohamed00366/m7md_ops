-- 277 · Removed the old Point Terminal kiosk app (dashboard) — applied 2026-10-25.
-- Dropped (used only by the kiosk):
drop function if exists public.can_register_new_device(uuid);
drop function if exists public.register_terminal_device(uuid,text,text,double precision,double precision);
drop function if exists public.verify_device_in_zone(uuid,text,double precision,double precision);
drop table if exists public.point_terminal_sessions;        -- had 4 rows: test sessions of 1 account (labels "1", "ahmed")
drop table if exists public.point_terminal_out_of_zone_log; -- was empty
-- KEPT on purpose (used by the valet app / reports):
--   accounts with account_type = 'point_terminal'  -> valet app point (tablet) sign-in
--   point_terminal_clock_logs                      -> valet app check-in / check-out, attendance reports, late alerts
--   PointTerminalSettings (late threshold, face exclusions by job title)
