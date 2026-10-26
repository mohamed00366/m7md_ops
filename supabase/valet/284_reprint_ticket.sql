-- 284 – Print again from "Show / print" (app 2.3.3), per point:
--   'customer' = only the customer copy (default), 'all' = every part set for the ticket, 'off' = no Print button (show only).
alter table public.valet_point_settings
  add column if not exists reprint_ticket text not null default 'customer'
  check (reprint_ticket in ('customer', 'all', 'off'));
