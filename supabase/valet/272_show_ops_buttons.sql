-- 272 (applied live 2026-10-25): show / hide the Driver in, Parking and Driver out buttons per point (dashboard).
alter table valet_point_settings add column if not exists show_driver_in boolean not null default true,
  add column if not exists show_parking boolean not null default true,
  add column if not exists show_driver_out boolean not null default true;
