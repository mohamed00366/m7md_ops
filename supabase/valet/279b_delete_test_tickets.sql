-- 279b (applied 2026-10-26, approved by Mohamed): the 699 load-test tickets (ticket_code 'TEST-%', created 2026-10-21)
-- were deleted with their 2 test credit notes. Copies (tickets, valet_odoo_sync, valet_odoo_ticket_sync, credits)
-- are kept in public.valet_deleted_test_backup (RLS on, no policies). Their Odoo invoices (posted + paid, ref = ticket code)
-- are NOT touched by this; Odoo needs its own clean-up.
create table if not exists public.valet_deleted_test_backup (src text not null, ticket_id uuid, data jsonb not null, deleted_at timestamptz not null default now());
alter table public.valet_deleted_test_backup enable row level security;
