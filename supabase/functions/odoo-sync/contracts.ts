// contracts.ts — Odoo contracts (x_valet_contract + price lines) -> Supabase valet_contracts (read-only copy for the
// dashboard), every master run (5 min). The signed PDF stays in Odoo and is fetched on demand (contractPdf).
import { Odoo, OdooError } from './odoo.ts';

const m2o = (v: any) => (Array.isArray(v) ? { id: v[0], name: v[1] } : null);
const d = (v: any) => (v ? String(v).slice(0, 10) : null);

const FIELDS = [
  'id', 'x_name', 'x_client_id', 'x_branch_ids', 'x_signed_date', 'x_start', 'x_end', 'x_auto_renew', 'x_renew_months',
  'x_notice_days', 'x_notice_deadline', 'x_termination_days', 'x_breach_days', 'x_payment_change_days', 'x_pricing',
  'x_customer_price', 'x_vat_included', 'x_revenue_note', 'x_drivers_weekday', 'x_drivers_weekend', 'x_schedule',
  'x_absence_penalty', 'x_exclusive', 'x_non_compete', 'x_insurance', 'x_pdf_name', 'x_notes', 'x_state', 'x_alert',
  'x_version', 'x_previous_id', 'x_source', 'x_site_ref', 'x_notice_given_on', 'x_termination_date', 'write_date',
];

/** All contracts with their branches (point names) and price lines. */
export async function pullContracts(o: Odoo) {
  if (!(await o.one('ir.model', [['model', '=', 'x_valet_contract']], ['id']))) return [];
  const rows: any[] = (await o.call('x_valet_contract', 'search_read', { domain: [], fields: FIELDS, limit: 5000 })) ?? [];
  // has a signed PDF? (binary not read here: only whether it is set)
  const withPdf = new Set<number>(
    ((await o.call('x_valet_contract', 'search_read', { domain: [['x_pdf', '!=', false]], fields: ['id'], limit: 5000 })) ?? []).map((r: any) => r.id),
  );
  const branchIds = [...new Set(rows.flatMap((r) => r.x_branch_ids ?? []))];
  const branches = new Map<number, any>();
  if (branchIds.length) {
    for (const b of (await o.call('x_valet_branch', 'read', { ids: branchIds, fields: ['x_name', 'x_point_id', 'x_status'] })) ?? []) branches.set(b.id, b);
  }
  const lines: any[] = (await o.call('x_valet_contract_line', 'search_read', {
    domain: [['x_contract_id', '!=', false]],
    fields: ['x_contract_id', 'x_name', 'x_branch_id', 'x_type', 'x_invoiced_by', 'x_qty', 'x_price', 'x_extra_price', 'x_ticket_price', 'x_start', 'x_end', 'x_active'],
    limit: 20000, context: { active_test: false },
  })) ?? [];
  const byContract = new Map<number, any[]>();
  for (const l of lines) {
    const k = Array.isArray(l.x_contract_id) ? l.x_contract_id[0] : l.x_contract_id;
    if (!byContract.has(k)) byContract.set(k, []);
    byContract.get(k)!.push({
      name: l.x_name || null, branch: m2o(l.x_branch_id)?.name ?? null, type: l.x_type || null, invoiced_by: l.x_invoiced_by || null,
      qty: l.x_qty, price: l.x_price, extra_price: l.x_extra_price, ticket_price: l.x_ticket_price,
      start: d(l.x_start), end: d(l.x_end), active: !!l.x_active,
    });
  }
  return rows.map((r) => ({
    odoo_id: r.id, name: r.x_name || null, client: m2o(r.x_client_id)?.name ?? null, client_odoo_id: m2o(r.x_client_id)?.id ?? null,
    state: r.x_state || 'draft', alert: !!r.x_alert, start_date: d(r.x_start), end_date: d(r.x_end), notice_deadline: d(r.x_notice_deadline),
    branch_odoo_ids: r.x_branch_ids ?? [],
    data: {
      branches: (r.x_branch_ids ?? []).map((id: number) => {
        const b = branches.get(id);
        return { id, name: b?.x_name ?? null, point: m2o(b?.x_point_id)?.name ?? null, status: b?.x_status ?? null };
      }),
      signed: d(r.x_signed_date), auto_renew: !!r.x_auto_renew, renew_months: r.x_renew_months, notice_days: r.x_notice_days,
      termination_days: r.x_termination_days, breach_days: r.x_breach_days, payment_change_days: r.x_payment_change_days,
      pricing: r.x_pricing || null, customer_price: r.x_customer_price, vat_included: !!r.x_vat_included, revenue_note: r.x_revenue_note || null,
      drivers_weekday: r.x_drivers_weekday, drivers_weekend: r.x_drivers_weekend, schedule: r.x_schedule || null,
      absence_penalty: r.x_absence_penalty, exclusive: !!r.x_exclusive, non_compete: !!r.x_non_compete, insurance: !!r.x_insurance,
      has_pdf: withPdf.has(r.id), pdf_name: r.x_pdf_name || null, notes: r.x_notes || null,
      version: r.x_version, previous: m2o(r.x_previous_id), source: r.x_source || null, site_ref: r.x_site_ref || null,
      notice_given_on: d(r.x_notice_given_on), termination_date: d(r.x_termination_date), odoo_updated: r.write_date || null,
      lines: byContract.get(r.id) ?? [],
    },
  }));
}

/** The signed PDF of one contract (base64), for the dashboard. */
export async function contractPdf(o: Odoo, id: number): Promise<{ name: string; data: string }> {
  const r = await o.one('x_valet_contract', [['id', '=', id]], ['x_pdf', 'x_pdf_name', 'x_name']);
  if (!r?.x_pdf) throw new OdooError('No signed PDF on this contract in Odoo.');
  return { name: r.x_pdf_name || `${r.x_name || 'contract'}.pdf`, data: String(r.x_pdf) };
}

export type NewSite = {
  site_ref: string; client: string | null; branch_name: string | null; point_odoo_id: number | null;
  start: string | null; months: number | null; pricing_mode: string | null; customer_price: number | null;
  monthly_amount: number | null; vat_pct: number | null; notes: string | null;
};

/** A new site approved in the dashboard -> draft contract in Odoo (once: found again by x_site_ref). */
export async function newSiteContract(o: Odoo, s: NewSite): Promise<number> {
  const ex = await o.one('x_valet_contract', [['x_site_ref', '=', s.site_ref]], ['id']);
  if (ex) return ex.id;
  let client: number | false = false;
  if (s.client) {
    const p = await o.one('res.partner', [['name', '=ilike', s.client], ['is_company', '=', true]], ['id'])
      ?? await o.one('res.partner', [['name', '=ilike', s.client]], ['id']);
    client = p?.id ?? false;
  }
  // New Sites Tracker pricing modes
  const pricing = s.pricing_mode === 'cash_to_company' ? 'customer_pays'
    : s.pricing_mode === 'cash_with_client_share' ? 'client_invoices'
    : s.pricing_mode === 'cash_to_client_we_invoice' || s.pricing_mode === 'free_we_invoice' ? 'monthly'
    : (s.pricing_mode ? 'mixed' : false);
  let end: string | false = false;
  if (s.start && s.months) {
    const e = new Date(s.start + 'T00:00:00Z');
    e.setUTCMonth(e.getUTCMonth() + Number(s.months));
    e.setUTCDate(e.getUTCDate() - 1);
    end = e.toISOString().slice(0, 10);
  }
  return await o.create('x_valet_contract', {
    x_name: `${s.client || s.branch_name || 'New site'} (new site)`, x_client_id: client, x_source: 'new_site', x_site_ref: s.site_ref,
    x_state: 'draft', x_start: s.start || false, x_end: end, x_renew_months: s.months || 12, x_pricing: pricing,
    x_customer_price: s.customer_price ?? 0, x_vat_included: true,
    x_notes: [`From the New Sites Tracker (${s.branch_name || ''}).`, s.monthly_amount ? `Monthly amount: ${s.monthly_amount}` : null,
      s.notes, client ? null : `Client "${s.client ?? ''}" not found in Odoo – choose it.`, 'Complete the terms, add the price lines, upload the signed PDF, then set it Active.']
      .filter(Boolean).join('\n'),
  });
}
