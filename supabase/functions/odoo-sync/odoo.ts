// Odoo JSON-2 API client + "ticket -> customer invoice" logic (no Deno / Supabase imports: unit-testable in Node).

export type Cfg = {
  base_url: string; database: string | null; api_key: string;
  walkin_partner: string; product_code: string; product_name: string; lost_code: string; lost_name: string;
  overnight_code?: string | null; overnight_name?: string | null;
  sales_journal: string | null; cash_journal: string | null; card_journal: string | null;
  post_invoice: boolean; register_payment: boolean;
};

export type Ticket = {
  ticket_id: string; ticket_code: string; plate: string | null; ticket_name: string | null; ticket_mode: string | null;
  payment_mode: string | null; total_price: number; lost_card: number; vat_rate: number;
  entry_time: string; exit_time: string; point_code: string | null; point_name: string | null;
  currency: string | null; client: string | null; client_code?: string | null; color?: string | null;
  point_analytic?: number | null; client_analytic?: number | null; odoo_move_id: number | null; odoo_payment: boolean;
  point_odoo_id?: number | null; branch_odoo_id?: number | null;
  over_night_fee?: number | null; over_night_nights?: number | null; manual_cars?: number | null;
  member_start?: string | null; member_end?: string | null;   // membership sale: revenue deferred over this period
  sale_no?: string | null;   // company sale number (numbering system) – payment reference of the invoice
};

export type Result = { status: 'done' | 'error'; move_id?: number; move_name?: string; payment?: boolean; error?: string };

export class OdooError extends Error {}

export class Odoo {
  private cfg: Cfg;
  private fetchFn: typeof fetch;
  constructor(cfg: Cfg, fetchFn: typeof fetch = fetch) {
    this.cfg = cfg;
    this.fetchFn = fetchFn;
  }

  async call(model: string, method: string, params: Record<string, unknown> = {}): Promise<any> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8',
      Authorization: `bearer ${this.cfg.api_key}`,
      'User-Agent': 'VIP-Valet-Sync',
    };
    if (this.cfg.database) headers['X-Odoo-Database'] = this.cfg.database;
    const url = `${this.cfg.base_url.replace(/\/+$/, '')}/json/2/${model}/${method}`;
    const res = await this.fetchFn(url, { method: 'POST', headers, body: JSON.stringify(params) });
    const text = await res.text();
    let data: any = null;
    try { data = text ? JSON.parse(text) : null; } catch { /* html error page */ }
    if (!res.ok) {
      const msg = data?.message || data?.name || text.slice(0, 300) || res.statusText;
      if (res.status === 401) throw new OdooError(`Odoo refused the API key (401). ${msg}`);
      if (res.status === 404 && !data) throw new OdooError(`Odoo API not found (404): is the address right and the plan allows API access? ${url}`);
      throw new OdooError(`Odoo ${model}.${method} failed (${res.status}): ${msg}`);
    }
    return data;
  }

  async one(model: string, domain: unknown[], fields: string[] = ['id']): Promise<any | null> {
    const r = await this.call(model, 'search_read', { domain, fields, limit: 1 });
    return Array.isArray(r) && r.length ? r[0] : null;
  }

  async create(model: string, vals: Record<string, unknown>, context?: Record<string, unknown>): Promise<number> {
    const r = await this.call(model, 'create', context ? { vals_list: [vals], context } : { vals_list: [vals] });
    const id = Array.isArray(r) ? r[0] : r;
    if (typeof id !== 'number') throw new OdooError(`Odoo ${model}.create returned no id`);
    return id;
  }
}

/** Dubai calendar date of an ISO time. */
export function dubaiDate(iso: string): string {
  const d = new Date(new Date(iso).getTime() + 4 * 3600 * 1000);
  return d.toISOString().slice(0, 10);
}

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

/** Looked up once per run and reused for every ticket. */
export class Refs {
  private cache = new Map<string, Promise<any>>();
  private o: Odoo;
  private cfg: Cfg;
  constructor(o: Odoo, cfg: Cfg) {
    this.o = o;
    this.cfg = cfg;
  }

  private memo<T>(k: string, f: () => Promise<T>): Promise<T> {
    if (!this.cache.has(k)) this.cache.set(k, f().catch((e) => { this.cache.delete(k); throw e; }));
    return this.cache.get(k)!;
  }

  tax(rate: number): Promise<{ id: number; included: boolean } | null> {
    if (!rate) return Promise.resolve(null);
    return this.memo(`tax:${rate}`, async () => {
      const pct = r2(rate * 100);
      const base = [['type_tax_use', '=', 'sale'], ['amount_type', '=', 'percent'], ['amount', '=', pct]];
      const t = await this.o.one('account.tax', base, ['id', 'name', 'price_include']);
      if (!t) throw new OdooError(`No ${pct}% sales tax found in Odoo (Accounting > Configuration > Taxes).`);
      return { id: t.id, included: !!t.price_include };
    });
  }

  partner(): Promise<number> {
    return this.memo('partner', async () => {
      const p = await this.o.one('res.partner', [['name', '=', this.cfg.walkin_partner]]);
      return p ? p.id : this.o.create('res.partner', { name: this.cfg.walkin_partner, customer_rank: 1 });
    });
  }

  product(code: string, name: string, tax: number | null): Promise<number> {
    return this.memo(`product:${code}`, async () => {
      const p = await this.o.one('product.product', [['default_code', '=', code]]);
      if (p) return p.id;
      return this.o.create('product.product', {
        name, default_code: code, type: 'service', sale_ok: true, purchase_ok: false,
        taxes_id: tax ? [[6, 0, [tax]]] : [[6, 0, []]],
      });
    });
  }

  journal(kind: 'sale' | 'cash' | 'bank', code: string | null): Promise<number | null> {
    return this.memo(`journal:${kind}:${code ?? ''}`, async () => {
      if (code) {
        const j = await this.o.one('account.journal', [['code', '=', code]]);
        if (!j) throw new OdooError(`Journal with code "${code}" not found in Odoo.`);
        return j.id;
      }
      if (kind === 'sale') return null; // Odoo default sales journal
      const j = await this.o.one('account.journal', [['type', '=', kind]]);
      if (!j) throw new OdooError(`No ${kind} journal in Odoo.`);
      return j.id;
    });
  }

  /** x_valet_point / x_valet_client / x_valet_ticket_type on invoices + columns in the invoice list. false = no rights. */
  /** Analytic account in plan [plan] (created when missing). null = analytic not available. */
  analytic(plan: string, code: string | null, name: string | null): Promise<number | null> {
    const label = (name || code || '').trim();
    if (!label) return Promise.resolve(null);
    return this.memo(`analytic:${plan}:${code ?? label}`, async () => {
      try {
        const p = await this.memo(`plan:${plan}`, async () => {
          const x = await this.o.one('account.analytic.plan', [['name', '=', plan]], ['id']);
          return x ? x.id : await this.o.create('account.analytic.plan', { name: plan });
        });
        const a = code
          ? await this.o.one('account.analytic.account', [['code', '=', code], ['plan_id', '=', p]], ['id'])
          : await this.o.one('account.analytic.account', [['name', '=', label], ['plan_id', '=', p]], ['id']);
        if (a) return a.id;
        return await this.o.create('account.analytic.account', { name: label, code: code || false, plan_id: p });
      } catch {
        return null;
      }
    });
  }

  /** {point: 100, client: 100} – one account per plan. With a Valet branch, the branch's account replaces the point's. */
  async distribution(t: Ticket, branchAnalytic: number | string | null = null): Promise<Record<string, number> | null> {
    // Valet branch: its three tags (point, client, service type) as one key – set by Odoo on the branch
    if (typeof branchAnalytic === 'string' && branchAnalytic) return { [branchAnalytic]: 100 };
    // linked in the dashboard to an existing Odoo account (e.g. "CHAPLIN L") or automatic
    const ids = [
      (typeof branchAnalytic === 'number' ? branchAnalytic : null) || t.point_analytic || await this.analytic('Valet Points', t.point_code, t.point_name),
      t.client_analytic || await this.analytic('Valet Clients', t.client_code ?? null, t.client),
    ].filter((x): x is number => !!x);
    return ids.length ? Object.fromEntries(ids.map((i) => [String(i), 100])) : null;
  }

  /** Valet branch (x_valet_branch) of a ticket line: the merchant's branch at the point, else the point's shared
   *  branch of [kind] (visitor / vip / lost_ticket / overnight). null = model missing or nothing found. */
  branch(t: Ticket, kind: 'visitor' | 'vip' | 'lost_ticket' | 'overnight' | 'merchant'): Promise<{ id: number; analytic: number | string | null } | null> {
    if (!t.point_odoo_id) return Promise.resolve(null);
    return this.memo(`branch:${t.point_odoo_id}:${kind}:${kind === 'merchant' ? t.branch_odoo_id ?? '' : ''}`, async () => {
      try {
        const fields = ['id', 'x_analytic_id', 'x_analytic_key'];
        let b = null;
        if (kind === 'merchant') {
          if (!t.branch_odoo_id) return null;
          b = await this.o.one('x_valet_branch', [['x_partner_id', '=', t.branch_odoo_id], ['x_point_id', '=', t.point_odoo_id]], fields)
            ?? await this.o.one('x_valet_branch', [['x_partner_id', '=', t.branch_odoo_id]], fields);
        } else {
          b = await this.o.one('x_valet_branch', [['x_point_id', '=', t.point_odoo_id], ['x_branch_type', '=', kind]], fields);
        }
        if (!b) return null;
        return { id: b.id, analytic: b.x_analytic_key || (Array.isArray(b.x_analytic_id) ? b.x_analytic_id[0] : (b.x_analytic_id || null)) };
      } catch {
        return null;
      }
    });
  }

  /** Main line: merchant branch, else VIP (VIP ticket) or Visitor. Lost-ticket line: the point's Lost Ticket branch. */
  async ticketBranches(t: Ticket) {
    const vip = /\bvip\b/i.test(`${t.ticket_name ?? ''} ${t.ticket_mode ?? ''}`);
    const main = (await this.branch(t, 'merchant')) ?? (vip ? await this.branch(t, 'vip') : null) ?? (await this.branch(t, 'visitor'));
    const lost = (await this.branch(t, 'lost_ticket')) ?? main;
    const night = (await this.branch(t, 'overnight')) ?? main;
    return { main, lost, night };
  }

  /** Invoices also carry the Odoo point / branch ids (Valet master data built in this Odoo). */
  hasIds = false;

  fields(): Promise<boolean> {
    return this.memo('fields', async () => {
      try { this.hasIds = await ensureValetFields(this.o); return true; } catch { return false; }
    });
  }

  currency(code: string | null): Promise<number | null> {
    if (!code) return Promise.resolve(null);
    return this.memo(`cur:${code}`, async () => {
      const c = await this.o.one('res.currency', [['name', '=', code.toUpperCase()]]);
      return c ? c.id : null;
    });
  }
}

export const VALET_FIELDS: [string, string][] = [
  ['x_valet_point', 'Valet Point'],
  ['x_valet_client', 'Valet Client'],
  ['x_valet_ticket_type', 'Ticket Type'],
  ['x_valet_plate', 'Plate No.'],
  ['x_valet_color', 'Car Color'],
];

async function viewId(o: Odoo, xmlid: string): Promise<number | null> {
  const [module, name] = xmlid.split('.');
  const r = await o.one('ir.model.data', [['module', '=', module], ['name', '=', name], ['model', '=', 'ir.ui.view']], ['res_id']);
  return r ? r.res_id : null;
}

async function inheritView(o: Odoo, key: string, parents: string[], archs: string[]) {
  const existing = await o.one('ir.ui.view', [['name', '=', key]], ['id', 'arch_db']);
  if (existing) {
    // update the columns when new fields were added
    for (const arch of archs) {
      if (existing.arch_db && String(existing.arch_db).replace(/\s/g, '').includes(arch.replace(/\s/g, ''))) return;
      try { await o.call('ir.ui.view', 'write', { ids: [existing.id], vals: { arch_db: arch } }); return; } catch { /* next */ }
    }
    return;
  }
  for (const p of parents) {
    const id = await viewId(o, p);
    if (!id) continue;
    for (const arch of archs) {
      try {
        await o.create('ir.ui.view', { name: key, model: 'account.move', inherit_id: id, mode: 'extension', priority: 99, arch_db: arch });
        return;
      } catch { /* try the next anchor */ }
    }
  }
}

/** Point / branch links on invoices (only when the Valet master data exists in Odoo). */
export const VALET_ID_FIELDS: [string, string, string][] = [
  ['x_valet_point_id', 'Valet Point (link)', 'x_valet_point'],
  ['x_valet_branch_id', 'Valet Branch', 'res.partner'],
];

/** Creates the custom fields on account.move and shows them as columns (list) and in the invoice form. Idempotent.
 *  Returns true when the point / branch link fields exist too. */
export async function ensureValetFields(o: Odoo): Promise<boolean> {
  const model = await o.one('ir.model', [['model', '=', 'account.move']], ['id']);
  if (!model) throw new OdooError('account.move model not found');
  for (const [name, label] of VALET_FIELDS) {
    const f = await o.one('ir.model.fields', [['model', '=', 'account.move'], ['name', '=', name]]);
    if (!f) {
      await o.create('ir.model.fields', {
        name, field_description: label, model_id: model.id, ttype: 'char', store: true, copied: false, state: 'manual',
      });
    }
  }
  let ids = false;
  if (await o.one('ir.model', [['model', '=', 'x_valet_point']], ['id'])) {
    for (const [name, label, relation] of VALET_ID_FIELDS) {
      const f = await o.one('ir.model.fields', [['model', '=', 'account.move'], ['name', '=', name]]);
      if (!f) {
        await o.create('ir.model.fields', {
          name, field_description: label, model_id: model.id, ttype: 'many2one', relation, store: true, copied: false, state: 'manual', index: true,
        });
      }
    }
    ids = true;
  }
  const cols = VALET_FIELDS.map(([n]) => `<field name="${n}" optional="show"/>`).join('');
  await inheritView(o, 'vip_valet.invoice_list_columns', ['account.view_out_invoice_tree', 'account.view_invoice_tree'], [
    `<xpath expr="//field[@name='invoice_partner_display_name']" position="after">${cols}</xpath>`,
    `<xpath expr="/*" position="inside">${cols}</xpath>`,
  ]);
  const formFields = VALET_FIELDS.map(([n]) => `<field name="${n}" readonly="1" invisible="not ${n}"/>`).join('');
  await inheritView(o, 'vip_valet.invoice_form_fields', ['account.view_move_form'], [
    `<xpath expr="//field[@name='ref']" position="after">${formFields}</xpath>`,
    `<xpath expr="//field[@name='partner_id']" position="after">${formFields}</xpath>`,
  ]);
  return ids;
}

function valetVals(t: Ticket, ids: boolean): Record<string, unknown> {
  return {
    ...(ids ? { x_valet_point_id: t.point_odoo_id || false, x_valet_branch_id: t.branch_odoo_id || false } : {}),
    x_valet_point: t.point_name || t.point_code || false,
    x_valet_client: t.client || false,
    x_valet_ticket_type: t.ticket_name || t.ticket_mode || false,
    x_valet_plate: t.plate || false,
    x_valet_color: t.color || false,
  };
}

/** One ticket -> one posted customer invoice (+ payment). Safe to repeat: finds the invoice by its reference. */
export async function syncTicket(o: Odoo, refs: Refs, cfg: Cfg, t: Ticket, onMove?: (id: number, name: string | null) => Promise<void>): Promise<Result> {
  const gross = r2(Number(t.total_price) || 0);
  const lost = r2(Number(t.lost_card) || 0);
  const night = r2(Number(t.over_night_fee) || 0);
  const free = gross + lost + night <= 0; // free ticket: 0 invoice, posted, no payment (kept for car counts)

  const tax = await refs.tax(Number(t.vat_rate) || 0);
  const price = (g: number) => (tax && !tax.included ? r2(g / (1 + Number(t.vat_rate))) : g);
  const taxIds = tax ? [[6, 0, [tax.id]]] : [[6, 0, []]];

  // 1) the invoice (existing one first: same ticket code as reference)
  let move = t.odoo_move_id
    ? await o.one('account.move', [['id', '=', t.odoo_move_id]], ['id', 'name', 'state', 'payment_state', 'amount_total'])
    : null;
  if (!move || move.state === 'cancel') {
    move = await o.one('account.move',
      [['move_type', '=', 'out_invoice'], ['ref', '=', t.ticket_code], ['state', '!=', 'cancel']],
      ['id', 'name', 'state', 'payment_state', 'amount_total']);
  }
  if (!move) {
    let [partner, prod, journal, currency] = await Promise.all([
      refs.partner(), refs.product(cfg.product_code, cfg.product_name, tax?.id ?? null),
      refs.journal('sale', cfg.sales_journal), refs.currency(t.currency),
    ]);
    // manual sale "on account": the invoice is on the client (the site's company), left unpaid
    if (t.payment_mode === 'Credit') {
      if (!t.branch_odoo_id) throw new OdooError(`Credit ticket ${t.ticket_code}: the client is not linked to Odoo yet.`);
      const cp = await o.one('res.partner', [['id', '=', t.branch_odoo_id]], ['commercial_partner_id']);
      partner = Array.isArray(cp?.commercial_partner_id) ? cp.commercial_partner_id[0] : t.branch_odoo_id;
    }
    const desc = [
      `${cfg.product_name} – ${t.ticket_code}`,
      t.plate ? `Plate ${t.plate}` : null,
      t.point_name ? `Point ${t.point_name}` : null,
      t.ticket_name ? `${t.ticket_name}` : null,
      t.client ? `Client ${t.client}` : null,
      t.manual_cars && t.manual_cars > 1 ? `${t.manual_cars} cars` : null,
    ].filter(Boolean).join(' | ');
    const lines: unknown[] = [];
    const br = await refs.ticketBranches(t);
    const lineVals = async (b: { id: number; analytic: number | string | null } | null) => {
      const dd = await refs.distribution(t, b?.analytic ?? null);
      return { ...(dd ? { analytic_distribution: dd } : {}), ...(b ? { x_branch_id: b.id } : {}) };
    };
    // membership sale: Odoo spreads the revenue over the subscription (company deferred revenue account 476101)
    const deferred = t.ticket_mode === 'Member' && t.member_start && t.member_end && t.member_end > t.member_start && gross > 0
      ? { deferred_start_date: t.member_start, deferred_end_date: t.member_end } : {};
    if (gross > 0 || free) lines.push([0, 0, { product_id: prod, name: desc, quantity: 1, price_unit: price(gross), tax_ids: taxIds, ...deferred, ...(await lineVals(br.main)) }]);
    if (lost > 0) {
      const lp = await refs.product(cfg.lost_code, cfg.lost_name, tax?.id ?? null);
      lines.push([0, 0, { product_id: lp, name: `${cfg.lost_name} – ${t.ticket_code}`, quantity: 1, price_unit: price(lost), tax_ids: taxIds, ...(await lineVals(br.lost)) }]);
    }
    if (night > 0) {
      const nc = cfg.overnight_code || 'VALET-OVERNIGHT', nn = cfg.overnight_name || 'Overnight Parking Fee';
      const np = await refs.product(nc, nn, tax?.id ?? null);
      const nights = Number(t.over_night_nights) || 1;
      lines.push([0, 0, { product_id: np, name: `${nn}${nights > 1 ? ' x' + nights : ''} – ${t.ticket_code}`, quantity: 1, price_unit: price(night), tax_ids: taxIds, ...(await lineVals(br.night)) }]);
    }
    const vals: Record<string, unknown> = {
      move_type: 'out_invoice', partner_id: partner, invoice_date: dubaiDate(t.exit_time),
      ref: t.ticket_code, invoice_origin: t.ticket_code,
      narration: `VIP Valet ticket ${t.ticket_code}${t.sale_no ? ' · sale ' + t.sale_no : ''}${t.point_code ? ' / ' + t.point_code : ''} · payment ${t.payment_mode ?? '-'}`,
      ...(t.sale_no ? { payment_reference: t.sale_no } : {}),
      invoice_line_ids: lines,
      // cars for the allocation / P&L: a paper-ticket summary counts all its cars
      x_cars: Number(t.manual_cars) > 0 ? Number(t.manual_cars) : 1,
    };
    if (journal) vals.journal_id = journal;
    if (currency) vals.currency_id = currency;
    if (br.main) vals.x_branch_id = br.main.id;
    if (await refs.fields()) Object.assign(vals, valetVals(t, refs.hasIds));
    const id = await o.create('account.move', vals, { default_move_type: 'out_invoice' });
    move = { id, name: null, state: 'draft', payment_state: 'not_paid' };
    await onMove?.(id, null);
  }

  else if (await refs.fields()) {
    const want = valetVals(t, refs.hasIds);
    const cur = await o.one('account.move', [['id', '=', move.id]], Object.keys(want));
    const val = (v: any) => (Array.isArray(v) ? v[0] : v);
    if (cur && Object.keys(want).some((k) => val((cur as any)[k]) !== want[k] && want[k])) {
      await o.call('account.move', 'write', { ids: [move.id], vals: want });
    }
  }

  // existing invoice without analytic / branch on its lines (sent before): add it
  if (t.odoo_move_id || move.state !== 'draft') {
    const br = await refs.ticketBranches(t);
    const lines = await o.call('account.move.line', 'search_read', {
      domain: [['move_id', '=', move.id], ['display_type', '=', 'product']], fields: ['id', 'analytic_distribution', 'product_id'],
    });
    const lostProd = await o.one('product.product', [['default_code', '=', cfg.lost_code]], ['id']);
    const nightProd = await o.one('product.product', [['default_code', '=', cfg.overnight_code || 'VALET-OVERNIGHT']], ['id']);
    const same = (x: any, dd: Record<string, number>) => {
      const a = x || {};
      const ka = Object.keys(a).sort(), kd = Object.keys(dd).sort();
      return ka.length === kd.length && ka.every((k, i) => k === kd[i] && Number(a[k]) === dd[k]);
    };
    for (const l of lines ?? []) {
      const isLost = lostProd && Array.isArray(l.product_id) && l.product_id[0] === lostProd.id;
      const isNight = nightProd && Array.isArray(l.product_id) && l.product_id[0] === nightProd.id;
      const b = isLost ? br.lost : isNight ? br.night : br.main;
      const dd = await refs.distribution(t, b?.analytic ?? null);
      if (!dd || same(l.analytic_distribution, dd)) continue;
      try {
        await o.call('account.move.line', 'write', { ids: [l.id], vals: { analytic_distribution: dd, ...(b ? { x_branch_id: b.id } : {}) } });
      } catch { /* posted & locked */ }
    }
    if (br.main) {
      try { await o.call('account.move', 'write', { ids: [move.id], vals: { x_branch_id: br.main.id } }); } catch { /* field missing */ }
    }
  }

  // 2) post
  if (cfg.post_invoice && move.state === 'draft') {
    await o.call('account.move', 'action_post', { ids: [move.id] });
    move = await o.one('account.move', [['id', '=', move.id]], ['id', 'name', 'state', 'payment_state', 'amount_total']);
  }

  // 3) payment (cash / card) on a posted invoice
  let paid = t.odoo_payment || ['paid', 'in_payment'].includes(move.payment_state);
  if (cfg.register_payment && !paid && !free && move.state === 'posted' && (t.payment_mode === 'Cash' || t.payment_mode === 'C-Card')) {
    const journal = t.payment_mode === 'Cash'
      ? await refs.journal('cash', cfg.cash_journal)
      : await refs.journal('bank', cfg.card_journal);
    const ctx = { active_model: 'account.move', active_ids: [move.id] };
    const wiz = await o.create('account.payment.register', { journal_id: journal, payment_date: dubaiDate(t.exit_time) }, ctx);
    await o.call('account.payment.register', 'action_create_payments', { ids: [wiz], context: ctx });
    paid = true;
  }
  return { status: 'done', move_id: move.id, move_name: move.name ?? undefined, payment: paid };
}

/** "Test connection" for the dashboard: what the link will use in Odoo. */
export async function testConnection(o: Odoo, refs: Refs, cfg: Cfg, vatRate = 0.05) {
  const out: Record<string, unknown> = {};
  const company = await o.call('res.company', 'search_read', { domain: [], fields: ['name', 'currency_id', 'vat'], limit: 5 });
  out.companies = (company ?? []).map((c: any) => ({ name: c.name, currency: c.currency_id?.[1] ?? c.currency_id, trn: c.vat || null }));
  out.journals = (await o.call('account.journal', 'search_read', {
    domain: [['type', 'in', ['sale', 'cash', 'bank']]], fields: ['name', 'code', 'type'], limit: 40,
  })).map((j: any) => ({ name: j.name, code: j.code, type: j.type }));
  try {
    const t = await refs.tax(vatRate);
    out.tax = t ? { id: t.id, included: t.included } : null;
  } catch (e) { out.tax_error = (e as Error).message; }
  const p = await o.one('product.product', [['default_code', '=', cfg.product_code]], ['id', 'name']);
  out.product = p ? p.name : `will be created: ${cfg.product_name} (${cfg.product_code})`;
  const pa = await o.one('res.partner', [['name', '=', cfg.walkin_partner]], ['id', 'name']);
  out.partner = pa ? pa.name : `will be created: ${cfg.walkin_partner}`;
  out.columns = (await refs.fields()) ? VALET_FIELDS.map(([, l]) => l).join(' · ') : 'no rights to add columns (use an admin API key)';
  return out;
}

/** All analytic accounts (for the dashboard dropdown). */
export async function listAnalytics(o: Odoo) {
  const rows = await o.call('account.analytic.account', 'search_read', {
    domain: [['active', '=', true]], fields: ['id', 'name', 'code', 'plan_id'], limit: 2000, order: 'name',
  });
  return (rows ?? []).map((r: any) => ({ id: r.id, name: r.name, code: r.code || null, plan: Array.isArray(r.plan_id) ? r.plan_id[1] : null }));
}
