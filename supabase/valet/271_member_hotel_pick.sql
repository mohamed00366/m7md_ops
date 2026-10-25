-- 271 (applied live 2026-10-25): Add ticket – member / hotel buttons under the plate, per point (dashboard).
alter table valet_point_settings add column if not exists show_member_pick boolean not null default true,
  add column if not exists show_hotel_pick boolean not null default true;
