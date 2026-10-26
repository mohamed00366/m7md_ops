// odoo-sync — sends closed valet tickets to Odoo as customer invoices.
//   POST {mode:'sync'}            header x-sync-secret  (pg_cron, every minute)
//   POST {mode:'test', token}     dashboard "Test connection" (valet admin token with settings permission)
// Deploy with verify_jwt = false (it checks the secret / admin token itself).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { ensureAreas, ensureValetMaster, goneIds, lastNotes, pullAreas, pullMaster, pushBranchStats } from './master.ts';
import { pushMaster, type OutRow } from './masterpush.ts';
import { pushPrices } from './prices.ts';
import { syncShift, type Shift } from './shifts.ts';
import { contractPdf, newSiteContract, pullContracts, type NewSite } from './contracts.ts';
import { syncCredit, type Credit } from './credits.ts';
import { syncTicketRows, type TicketRow } from './tickets.ts';
import { listAnalytics, Odoo, OdooError, Refs, syncTicket, testConnection, type Cfg, type Ticket } from './odoo.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-sync-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// 281: local changes of areas / clients / points / branches / links -> Odoo
async function pushOutbox(o: Odoo): Promise<unknown> {
  const { data: rows, error } = await db.rpc('vv__odoo_master_outbox', { p_limit: 50 });
  if (error) return { error: error.message };
  if (!Array.isArray(rows) || !rows.length) return 0;
  const acks = await pushMaster(o, rows as OutRow[]);
  const { data, error: ae } = await db.rpc('vv__odoo_master_ack', { p_rows: acks });
  return ae ? { error: ae.message } : { ...(data as object), notes: acks.filter((a) => a.note || a.error).map((a) => `${a.entity} ${a.note ?? a.error}`).slice(0, 10) };
}

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

async function config(): Promise<Cfg & { enabled: boolean; sync_secret: string | null }> {
  const { data, error } = await db.rpc('vv__odoo_config');
  if (error) throw new Error(error.message);
  return data;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'POST only' }, 405);
  let body: any = {};
  try { body = await req.json(); } catch { /* empty */ }
  const cfg = await config();

  // ------------------------------------------------ test connection (dashboard)
  if (body.mode === 'test') {
    const { data, error } = await db.rpc('vva_odoo_settings', { p_token: String(body.token ?? '') });
    if (error || !data?.ok) return json({ ok: false, error: error?.message ?? 'Not allowed' }, 401);
    if (!cfg.base_url) return json({ ok: false, error: 'Enter the Odoo address first.' });
    if (!cfg.api_key) return json({ ok: false, error: 'Enter the Odoo API key first.' });
    try {
      const o = new Odoo(cfg);
      return json({ ok: true, error: null, odoo: await testConnection(o, new Refs(o, cfg), cfg) });
    } catch (e) {
      return json({ ok: false, error: (e as Error).message });
    }
  }

  // ------------------------------------------------ analytic accounts list (dashboard)
  if (body.mode === 'analytics') {
    const { data, error } = await db.rpc('vva_odoo_settings', { p_token: String(body.token ?? '') });
    if (error || !data?.ok) return json({ ok: false, error: error?.message ?? 'Not allowed' }, 401);
    if (!cfg.base_url || !cfg.api_key) return json({ ok: false, error: 'Odoo is not linked yet.' });
    try {
      return json({ ok: true, error: null, accounts: await listAnalytics(new Odoo(cfg)) });
    } catch (e) {
      return json({ ok: false, error: (e as Error).message });
    }
  }

  // ------------------------------------------------ signed contract PDF (dashboard)
  if (body.mode === 'contract_pdf') {
    const { data, error } = await db.rpc('vva_contract_access', { p_token: String(body.token ?? '') });
    if (error || !data?.ok) return json({ ok: false, error: error?.message ?? 'Not allowed' }, 401);
    if (!cfg.base_url || !cfg.api_key) return json({ ok: false, error: 'Odoo is not linked yet.' });
    try {
      return json({ ok: true, error: null, pdf: await contractPdf(new Odoo(cfg), Number(body.id)) });
    } catch (e) {
      return json({ ok: false, error: (e as Error).message });
    }
  }

  // ------------------------------------------------ sync (cron)
  if (!cfg.sync_secret || req.headers.get('x-sync-secret') !== cfg.sync_secret) return json({ ok: false, error: 'Forbidden' }, 403);
  if (!cfg.enabled || !cfg.api_key || !cfg.base_url) return json({ ok: true, skipped: 'link is off' });

  // ------------------------------------------------ master data: Odoo points / clients / branches -> system (cron, 5 min)
  if (body.mode === 'pull' || body.mode === 'setup') {
    try {
      const o = new Odoo(cfg);
      const refs = new Refs(o, cfg);
      let built = false;
      try { built = await ensureValetMaster(o, body.mode === 'setup'); } catch (e) {
        return json({ ok: false, step: 'setup', notes: lastNotes, error: (e as Error).message });
      }
      // 281: areas in Odoo, local changes first (latest wins), then everything from Odoo + what Odoo deleted
      let areas: any[] = [];
      let areaErr: string | null = null;
      try { await ensureAreas(o); areas = await pullAreas(o); } catch (e) { areaErr = (e as Error).message; }
      let pushed: unknown = null;
      try { pushed = await pushOutbox(o); } catch (e) { pushed = { error: (e as Error).message }; }
      const data = await pullMaster(o, (plan, code, name) => refs.analytic(plan, code, name));
      let gone: unknown = {};
      try {
        const { data: known } = await db.rpc('vv__odoo_known_ids');
        if (known) gone = await goneIds(o, { ...(known as any), areas: areaErr ? [] : (known as any).areas });
      } catch { gone = {}; }
      const { data: res, error } = await db.rpc('vv__odoo_apply_master2', {
        p_points: data.points, p_branches: data.branches, p_areas: areaErr ? [] : areas, p_gone: gone,
      });
      if (error) return json({ ok: false, error: error.message }, 500);
      // codes generated by the system -> back to Odoo
      for (const c of (res?.codes ?? []) as { odoo_id: number; code: string }[]) {
        if (c.code) await o.call('x_valet_point', 'write', { ids: [c.odoo_id], vals: { x_code: c.code } });
      }
      // ticket counts per branch under each point
      let stats: unknown = null;
      try {
        const { data: rows, error: se } = await db.rpc('vv__odoo_branch_stats');
        if (se) throw new Error(se.message);
        stats = await pushBranchStats(o, rows ?? []);
      } catch (e) { stats = { error: (e as Error).message }; }
      // app prices -> Odoo (read-only copy)
      let prices: unknown = null;
      try { prices = await pushPrices(o, db); } catch (e) { prices = { error: (e as Error).message }; }
      // contracts: new sites approved in the dashboard -> draft contracts in Odoo; all contracts -> dashboard copy
      let contracts: unknown = null;
      try {
        let made = 0;
        const { data: ns } = await db.rpc('vv__odoo_new_sites', { p_limit: 10 });
        for (const s of (ns ?? []) as NewSite[]) {
          try {
            const id = await newSiteContract(o, s);
            await db.rpc('vv__odoo_new_site_result', { p_site: s.site_ref, p_odoo_id: id, p_error: null });
            made++;
          } catch (e) {
            await db.rpc('vv__odoo_new_site_result', { p_site: s.site_ref, p_odoo_id: null, p_error: (e as Error).message });
          }
        }
        const rows = await pullContracts(o);
        const { data: n, error: ce } = await db.rpc('vv__odoo_apply_contracts', { p_rows: rows });
        contracts = ce ? { error: ce.message } : { synced: n, new_sites: made };
      } catch (e) { contracts = { error: (e as Error).message }; }
      return json({ ok: true, built, notes: lastNotes, points: data.points.length, branches: data.branches.length, areas: areas.length, areaErr, pushed, gone, result: res, stats, prices, contracts });
    } catch (e) {
      await db.from('valet_odoo_settings').update({ master_result: { error: (e as Error).message } }).eq('id', 1);
      return json({ ok: false, notes: lastNotes, error: (e as Error).message });
    }
  }

  const o = new Odoo(cfg);
  const refs = new Refs(o, cfg);
  // 281: master data changed in the dashboard / apps -> Odoo within a minute
  let master: unknown = 0;
  try { master = await pushOutbox(o); } catch (e) { master = { error: (e as Error).message }; }
  const started = Date.now();
  let done = 0, failed = 0;
  while (Date.now() - started < 45_000) {
    const { data: rows, error } = await db.rpc('vv__odoo_claim', { p_limit: 10 });
    if (error) return json({ ok: false, error: error.message }, 500);
    if (!rows?.length) break;
    for (const t of rows as Ticket[]) {
      try {
        const r = await syncTicket(o, refs, cfg, t, async (id, name) => {
          await db.rpc('vv__odoo_result', { p_ticket: t.ticket_id, p_status: 'progress', p_move_id: id, p_move_name: name, p_payment: null, p_error: null });
        });
        await db.rpc('vv__odoo_result', {
          p_ticket: t.ticket_id, p_status: 'done', p_move_id: r.move_id ?? null, p_move_name: r.move_name ?? null,
          p_payment: r.payment ?? false, p_error: null,
        });
        done++;
      } catch (e) {
        failed++;
        const msg = e instanceof OdooError ? e.message : `Unexpected: ${(e as Error).message}`;
        await db.rpc('vv__odoo_result', { p_ticket: t.ticket_id, p_status: 'error', p_move_id: null, p_move_name: null, p_payment: null, p_error: msg });
        // a wrong key / address fails every ticket: stop this run
        if (/401|404|API key/.test(msg)) return json({ ok: false, done, failed, error: msg });
        // Odoo says too many requests: stop now, the queue retries these next minute
        if (/\(429\)/.test(msg)) return json({ ok: false, done, failed, throttled: true });
      }
    }
  }
  // credit notes requested in the dashboard (cancelled / wrong tickets)
  let credits = 0, creditsFailed = 0;
  const { data: crs, error: ce } = await db.rpc('vv__odoo_claim_credits', { p_limit: 10 });
  if (!ce) {
    for (const c of (crs ?? []) as Credit[]) {
      try {
        const r = await syncCredit(o, refs, cfg, c);
        await db.rpc('vv__odoo_credit_result', { p_credit: c.credit_id, p_status: 'done', p_move_id: r.credit_move_id, p_move_name: r.credit_name, p_refund: r.refund, p_error: null });
        credits++;
      } catch (e) {
        creditsFailed++;
        const msg = e instanceof OdooError ? e.message : `Unexpected: ${(e as Error).message}`;
        await db.rpc('vv__odoo_credit_result', { p_credit: c.credit_id, p_status: 'error', p_move_id: null, p_move_name: null, p_refund: null, p_error: msg });
      }
    }
  }
  // closed valet shifts -> Odoo Shift Cash (the office receives the cash there)
  let shifts = 0, shiftsFailed = 0;
  const { data: shs, error: she } = await db.rpc('vv__odoo_claim_shifts', { p_limit: 10 });
  if (!she) {
    for (const s of (shs ?? []) as Shift[]) {
      try {
        const id = await syncShift(o, s);
        await db.rpc('vv__odoo_shift_result', { p_shift: s.shift_id, p_status: 'done', p_odoo_id: id, p_error: null });
        shifts++;
      } catch (e) {
        shiftsFailed++;
        const msg = e instanceof OdooError ? e.message : `Unexpected: ${(e as Error).message}`;
        await db.rpc('vv__odoo_shift_result', { p_shift: s.shift_id, p_status: 'error', p_odoo_id: null, p_error: msg });
      }
    }
  }
  // shifts posted / reopened in Odoo -> locked / unlocked in the system (nothing can be added to a posted shift)
  let locks: unknown = 0;
  try {
    const since = new Date(Date.now() - 15 * 60e3).toISOString().replace('T', ' ').slice(0, 19);
    const rows = ((await o.call('x_valet_shift', 'search_read', { domain: [['write_date', '>=', since], ['x_uid', '!=', false]], fields: ['x_uid', 'x_state'] })) ?? []) as any[];
    if (rows.length) {
      const { data: n, error: le } = await db.rpc('vv__odoo_shift_lock', { p_rows: rows.map((r) => ({ uid: r.x_uid, state: r.x_state })) });
      locks = le ? { error: le.message } : n;
    }
  } catch (e) { locks = { error: (e as Error).message }; }
  // payment-method corrections decided at shift close in Odoo -> the ticket in the system
  let payfix: unknown = 0;
  try {
    const rows = ((await o.call('x_valet_ticket', 'search_read', { domain: [['x_paymode_done', '=', true], ['x_paymode_synced', '=', false]], fields: ['id', 'x_uid', 'x_paymode_to'], limit: 100 })) ?? []) as any[];
    if (rows.length) {
      const { data: done, error: pe } = await db.rpc('vv__odoo_payfix', { p_rows: rows.map((r) => ({ ticket_id: r.x_uid, mode: r.x_paymode_to })) });
      if (pe) throw new Error(pe.message);
      const ok = new Set((done ?? []) as string[]);
      const ids = rows.filter((r) => ok.has(r.x_uid)).map((r) => r.id);
      if (ids.length) await o.call('x_valet_ticket', 'write', { ids, vals: { x_paymode_synced: true } });
      payfix = ids.length;
    }
  } catch (e) { payfix = { error: (e as Error).message }; }
  // every ticket with all its columns -> Odoo Valet ▸ Tickets (Shift Close shows them per shift)
  let tickets = 0, ticketsFailed = 0;
  try {
    const { data: trs, error: te } = await db.rpc('vv__odoo_claim_ticket_rows', { p_limit: 200 });
    if (!te && Array.isArray(trs) && trs.length) {
      const ids = await syncTicketRows(o, trs as TicketRow[]);
      const res = (trs as any[]).map((r) => ({ ticket_id: r.ticket_id, hash: r.hash, odoo_id: ids.get(r.ticket_id) ?? null }));
      await db.rpc('vv__odoo_ticket_rows_result', { p_rows: res });
      tickets = res.length;
    }
  } catch (e) {
    ticketsFailed++;
    console.error('tickets', (e as Error).message);
  }
  return json({ ok: true, master, done, failed, credits, creditsFailed, shifts, shiftsFailed, locks, payfix, tickets, ticketsFailed });
});
