-- 340: dashboard reads of DB 337 / 339 call vva__auth, which writes (the session's last seen): they must not be STABLE
-- ("cannot execute UPDATE in a read-only transaction" on the VIP Fleet page).
alter function public.vva_fleet_devices(text) volatile;
alter function public.vva_fleet_log(text, uuid, date, date, text, text, integer) volatile;
alter function public.vva_rta_log(text, uuid, date, date, integer) volatile;
alter function public.vva_rta_devices(text, uuid) volatile;
alter function public.vv_rta_ticket(text, uuid) volatile;
alter function public.vva_pending(text) volatile;
notify pgrst, 'reload schema';
