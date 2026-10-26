// prices.ts — copies the valet app prices to Odoo (read-only there).
// App (Supabase) is the master: valet_prices, valet_vip_prices, valet_point_settings.
// Odoo: x_valet_price lines + lost / overnight / VAT fields on x_valet_point.
import type { Odoo } from './odoo.ts';

type Db = { from: (t: string) => any };

const DAY = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const m2o = (v: any): number | false => (Array.isArray(v) ? v[0] : (typeof v === 'number' ? v : false));
const num = (v: unknown) => Math.round((Number(v) || 0) * 100) / 100;
const odooNow = () => new Date().toISOString().replace('T', ' ').slice(0, 19);

/** ISO weekdays (1 = Mon … 7 = Sun) -> "Mon, Tue, Thu–Sun" / "All". */
export function daysLabel(days: number[] | null | undefined): string {
  if (!days || !days.length) return 'All';
  const d = [...new Set(days.map(Number))].filter((x) => x >= 1 && x <= 7).sort((a, b) => a - b);
  if (d.length === 7) return 'All';
  const parts: string[] = [];
  for (let i = 0; i < d.length; i++) {
    let j = i;
    while (j + 1 < d.length && d[j + 1] === d[j] + 1) j++;
    parts.push(j - i >= 2 ? `${DAY[d[i]]}–${DAY[d[j]]}` : d.slice(i, j + 1).map((x) => DAY[x]).join(', '));
    i = j;
  }
  return parts.join(', ');
}

const MODE: Record<string, string> = { HOURLY: 'Hourly', TICKET: 'Ticket' };
const PAY: Record<string, string> = { BASE_ONCE: 'Base once', PER_UNIT: 'Per unit' };
const startHour = (s: string | null) => parseInt(String(s ?? '').split(':')[0], 10) || 0;

async function all(db: Db, table: string, cols: string): Promise<any[]> {
  const out: any[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from(table).select(cols).range(from, from + 999);
    if (error) throw new Error(`${table}: ${error.message}`);
    out.push(...(data ?? []));
    if (!data || data.length < 1000) return out;
  }
}

export async function pushPrices(o: Odoo, db: Db) {
  const [points, sites, prices, vips, settings] = await Promise.all([
    all(db, 'points', 'id,odoo_id'),
    all(db, 'sites', 'id,odoo_partner_id,system_kind'),
    all(db, 'valet_prices', 'id,point_id,site_id,ticket_name,ticket_mode,start_time,finish_time,payment_mode,price,tax,total,is_active,notes,days,vat_included'),
    all(db, 'valet_vip_prices', 'id,point_id,ticket_name,ticket_price,is_active,vat_included'),
    all(db, 'valet_point_settings', 'point_id,lost_ticket_enabled,lost_ticket_price,over_night_enabled,over_night_price,currency,vat_rate'),
  ]);
  // only points that still exist in Odoo (a point deleted in Odoo keeps its odoo_id in the app)
  const live = new Set<number>((await o.call('x_valet_point', 'search_read', { domain: [], fields: ['id'], limit: 5000 })).map((p: any) => p.id));
  const pointOdoo = new Map<string, number>();
  for (const p of points) if (p.odoo_id && live.has(Number(p.odoo_id))) pointOdoo.set(p.id, Number(p.odoo_id));
  const siteById = new Map<string, any>(sites.map((s: any) => [s.id, s]));

  // Odoo branches: merchant by invoicing contact, shared by point + type
  const branches: any[] = await o.call('x_valet_branch', 'search_read', {
    domain: [], fields: ['id', 'x_point_id', 'x_partner_id', 'x_branch_type'], limit: 20000,
  });
  const byContact = new Map<number, number>();
  const shared = new Map<string, number>();
  for (const b of branches) {
    const c = m2o(b.x_partner_id);
    if (c && b.x_branch_type === 'contract') byContact.set(c, b.id);
    if (b.x_branch_type !== 'contract') shared.set(`${m2o(b.x_point_id)}|${b.x_branch_type}`, b.id);
  }
  const branchOf = (siteId: string | null, odooPoint: number): number | false => {
    const s = siteId ? siteById.get(siteId) : null;
    if (!s) return false;
    if (s.odoo_partner_id && byContact.has(Number(s.odoo_partner_id))) return byContact.get(Number(s.odoo_partner_id))!;
    if (s.system_kind) return shared.get(`${odooPoint}|${s.system_kind}`) ?? false;
    return false;
  };

  // wanted lines
  const want = new Map<string, Record<string, unknown>>();
  for (const p of prices) {
    const pt = pointOdoo.get(p.point_id);
    if (!pt) continue;
    const mode = String(p.ticket_mode ?? '').toUpperCase();
    want.set(`p:${p.id}`, {
      x_app_id: `p:${p.id}`, x_point_id: pt, x_branch_id: branchOf(p.site_id, pt),
      x_kind: mode === 'HOURLY' ? 'hourly' : 'ticket', x_name: p.ticket_name || mode || 'Price',
      x_mode: MODE[mode] ?? (p.ticket_mode || false), x_days: daysLabel(p.days),
      x_start: mode === 'HOURLY' ? (p.start_time || false) : false, x_finish: mode === 'HOURLY' ? (p.finish_time || false) : false,
      x_payment: PAY[String(p.payment_mode ?? '')] ?? (p.payment_mode || false),
      x_price: num(p.price), x_tax: num(p.tax), x_total: num(p.total), x_vat_included: !!p.vat_included,
      x_active: !!p.is_active, x_removed: false, x_sort: mode === 'HOURLY' ? startHour(p.start_time) : 0, x_notes: p.notes || false,
    });
  }
  for (const v of vips) {
    const pt = pointOdoo.get(v.point_id);
    if (!pt) continue;
    const base = num(v.ticket_price);
    // the app stores the price before VAT when "VAT included" is on (333.33 = 350 / 1.05)
    const total = num(base * 1.05);
    want.set(`v:${v.id}`, {
      x_app_id: `v:${v.id}`, x_point_id: pt, x_branch_id: shared.get(`${pt}|vip`) ?? false,
      x_kind: 'vip', x_name: v.ticket_name || 'VIP', x_mode: 'VIP', x_days: 'All', x_start: false, x_finish: false,
      x_payment: false, x_price: base, x_tax: num(total - base), x_total: total, x_vat_included: !!v.vat_included,
      x_active: !!v.is_active, x_removed: false, x_sort: 0, x_notes: false,
    });
  }

  // compare with Odoo
  // x_active is Odoo's archive flag on manual models: read archived lines too
  const have: any[] = await o.call('x_valet_price', 'search_read', {
    context: { active_test: false }, domain: [], fields: ['id', 'x_app_id', ...Object.keys([...want.values()][0] ?? { x_point_id: 1 }).filter((k) => k !== 'x_app_id')], limit: 20000,
  });
  const norm = (k: string, v: unknown) => (k.endsWith('_id') ? m2o(v) : (v === null ? false : v));
  let created = 0, updated = 0, removed = 0;
  const seen = new Set<string>();
  const toCreate: Record<string, unknown>[] = [];
  for (const h of have) {
    const w = want.get(h.x_app_id);
    if (!w) {
      if (h.x_active || !h.x_removed) { await o.call('x_valet_price', 'write', { ids: [h.id], vals: { x_active: false, x_removed: true } }); removed++; }
      continue;
    }
    seen.add(h.x_app_id);
    const diff: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(w)) if (k !== 'x_app_id' && norm(k, h[k]) !== norm(k, v)) diff[k] = v;
    if (Object.keys(diff).length) { await o.call('x_valet_price', 'write', { ids: [h.id], vals: diff }); updated++; }
  }
  for (const [k, w] of want) if (!seen.has(k)) toCreate.push(w);
  if (toCreate.length) { await o.call('x_valet_price', 'create', { vals_list: toCreate }); created = toCreate.length; }

  // lost / overnight / VAT on the points
  const setBy = new Map<number, any>();
  for (const s of settings) { const pt = pointOdoo.get(s.point_id); if (pt) setBy.set(pt, s); }
  const pts: any[] = await o.call('x_valet_point', 'search_read', {
    domain: [], fields: ['id', 'x_lost_enabled', 'x_lost_price', 'x_overnight_enabled', 'x_overnight_price', 'x_vat_rate', 'x_currency'], limit: 5000,
  });
  const now = odooNow();
  let pointsUpdated = 0;
  const unchanged: number[] = [];
  for (const p of pts) {
    const s = setBy.get(p.id);
    const vals: Record<string, unknown> = s ? {
      x_lost_enabled: !!s.lost_ticket_enabled, x_lost_price: num(s.lost_ticket_price),
      x_overnight_enabled: !!s.over_night_enabled, x_overnight_price: num(s.over_night_price),
      x_vat_rate: num(Number(s.vat_rate) * 100), x_currency: s.currency || false,
    } : {};
    const changed = Object.entries(vals).some(([k, v]) => (p[k] === null ? false : p[k]) !== v);
    if (changed) { await o.call('x_valet_point', 'write', { ids: [p.id], vals: { ...vals, x_prices_synced: now } }); pointsUpdated++; }
    else unchanged.push(p.id);
  }
  if (unchanged.length) await o.call('x_valet_point', 'write', { ids: unchanged, vals: { x_prices_synced: now } });
  return { lines: want.size, created, updated, removed, points: pointsUpdated };
}
