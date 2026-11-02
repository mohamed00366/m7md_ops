-- 338: the real RTA message (owner, 2 Nov 2026): "CC57843 317AP1" = the plate, a space, the zone code and right after it
-- the hours. New default template; points still on the first default get the new one (a changed template is kept).
alter table public.valet_point_settings alter column rta_template set default '{plate} {zone}{hours}';
update public.valet_point_settings set rta_template = '{plate} {zone}{hours}' where rta_template = '{zone} {plate} {hours}';
notify pgrst, 'reload schema';
