-- 300 – site opening hours drive the overnight fee.
-- The dashboard "Tickets and charges" panel sets: works 24 hours, or opens at / closes at.
-- Overnight = the car is still parked when the site closes (one fee for every closing time passed).
-- Stored as over_night_rule 'cutoff' at the closing time, so every app version already prices it.
-- A 24-hour site has no closing time → no overnight fee.
alter table public.valet_point_settings add column if not exists site_24h boolean not null default false;
alter table public.valet_point_settings add column if not exists site_open_at time;
alter table public.valet_point_settings add column if not exists site_close_at time;
update public.valet_point_settings set site_close_at = over_night_at
 where site_close_at is null and over_night_rule = 'cutoff' and over_night_at is not null and over_night_enabled;
