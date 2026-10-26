// shifts.ts — closed valet shifts -> Odoo x_valet_shift (Valet ▸ Shift Cash), where the office receives the cash.
// Created once per shift (found again by x_uid). A shift already received in Odoo is never changed.
import { Odoo, OdooError } from './odoo.ts';

export type Shift = {
  shift_id: string; shift_code: string; point_odoo_id: number | null; point_code: string | null; point_name: string | null;
  opened_by_code: string | null; opened_by_name: string | null; closed_by_code: string | null; closed_by_name: string | null;
  start_time: string | null; end_time: string | null; tickets: number | null; cash_expected: number | null; card_expected: number | null;
  free_count: number | null; cash_tips: number | null; cash_counted: number | null; cash_note: string | null;
  terminals?: string | null;   // card machines used in the shift
  card_tips?: number | null;
  sale_gaps?: string[] | null;   // sale numbers missing in the shift (inside the tablet blocks)
};

const odt = (s: string | null) => (s ? new Date(s).toISOString().replace('T', ' ').slice(0, 19) : false);
const who = (code: string | null, name: string | null) => [code, name].filter(Boolean).join(' ') || false;

const pointCache = new Map<number, number | false>();
const empCache = new Map<string, number>();

/** res.partner of an employee (ref EMP-<code>) – the shortage receivable is kept per employee. */
async function employeePartner(o: Odoo, code: string | null, name: string | null): Promise<number | false> {
  if (!code) return false;
  const ref = `EMP-${code}`;
  if (empCache.has(ref)) return empCache.get(ref)!;
  const p = await o.one('res.partner', [['ref', '=', ref]], ['id']);
  const id = p?.id ?? await o.create('res.partner', { name: `${code} ${name ?? ''}`.trim(), ref, is_company: false, comment: 'Valet employee' });
  empCache.set(ref, id);
  return id;
}

export async function syncShift(o: Odoo, s: Shift): Promise<number> {
  if (!s.point_odoo_id) throw new OdooError(`Point ${s.point_code ?? ''} is not linked to Odoo yet (will retry).`);
  let analytic = pointCache.get(s.point_odoo_id);
  if (analytic === undefined) {
    const p = await o.one('x_valet_point', [['id', '=', s.point_odoo_id]], ['x_analytic_id']);
    const a: number | false = Array.isArray(p?.x_analytic_id) ? p.x_analytic_id[0] : false;
    pointCache.set(s.point_odoo_id, a);
    analytic = a;
  }
  const counted = s.cash_counted !== null && s.cash_counted !== undefined;
  const vals: Record<string, unknown> = {
    x_name: s.shift_code, x_uid: s.shift_id, x_point_id: s.point_odoo_id, x_analytic_id: analytic || false,
    x_opened_by: who(s.opened_by_code, s.opened_by_name), x_closed_by: who(s.closed_by_code, s.closed_by_name),
    x_start: odt(s.start_time), x_end: odt(s.end_time),
    x_tickets: s.tickets ?? 0, x_free: s.free_count ?? 0,
    x_cash_expected: Number(s.cash_expected ?? 0), x_card_expected: Number(s.card_expected ?? 0), x_cash_tips: Number(s.cash_tips ?? 0),
    x_counted: counted, x_cash_counted: counted ? Number(s.cash_counted) : 0, x_cash_note: s.cash_note || false,
    x_terminals: s.terminals || false, x_card_tips: Number(s.card_tips ?? 0),
    x_seq_gap_count: (s.sale_gaps ?? []).length, x_seq_gaps: (s.sale_gaps ?? []).join(', ') || false,
  };
  const ex = await o.one('x_valet_shift', [['x_uid', '=', s.shift_id]], ['id', 'x_state', 'x_tips_move_id', 'x_employee_partner_id', 'x_cash_received', 'x_cash_expected', 'x_counted', 'x_cash_counted']);
  if (ex) {
    // the shift changed after it was sent (paper ticket approved late, void...): the office has not received it yet, so
    // "Cash received" follows the new number unless the office already typed its own amount
    const untouched = Math.abs(Number(ex.x_cash_received) - Number(ex.x_counted ? ex.x_cash_counted : ex.x_cash_expected)) < 0.005;
    if (untouched) vals.x_cash_received = counted ? Number(s.cash_counted) : Number(s.cash_expected ?? 0);
    if (ex.x_state !== 'received') await o.call('x_valet_shift', 'write', { ids: [ex.id], vals });
    if (!ex.x_tips_move_id) await tipsEntry(o, ex.id, s, Array.isArray(ex.x_employee_partner_id) ? ex.x_employee_partner_id[0] : false, analytic || false);
    return ex.id;
  }
  vals.x_employee_partner_id = await employeePartner(o, s.closed_by_code ?? s.opened_by_code, s.closed_by_code ? s.closed_by_name : s.opened_by_name);
  vals.x_cash_received = counted ? Number(s.cash_counted) : Number(s.cash_expected ?? 0);   // the office changes it if different
  vals.x_state = 'to_receive';
  const id = await o.create('x_valet_shift', vals);
  await tipsEntry(o, id, s, vals.x_employee_partner_id as number | false, analytic || false);
  return id;
}

const accCache = new Map<string, number>();
/** Account of a Valet accounting setting (Valet ▸ Configuration ▸ Accounting settings), else the account code. */
async function acc(o: Odoo, code: string, key?: string): Promise<number> {
  const k = key ?? code;
  if (!accCache.has(k)) {
    let id: number | null = null;
    if (key) {
      try {
        const s = await o.one('x_valet_acc_setting', [['x_key', '=', key]], ['x_default_account_id']);
        if (s && Array.isArray(s.x_default_account_id)) id = s.x_default_account_id[0];
      } catch { /* settings page not there */ }
    }
    if (!id) {
      const a = await o.one('account.account', [['code', '=', code]], ['id']);
      if (!a) throw new OdooError(`Account ${code} not found in Odoo.`);
      id = a.id;
    }
    accCache.set(k, id!);
  }
  return accCache.get(k)!;
}

/** Tips are not revenue: they belong to the employees. Dr 531001 (cash tips) + Dr 512002 (card tips) / Cr 461001, once per shift. */
async function tipsEntry(o: Odoo, shiftId: number, s: Shift, partner: number | false, analytic: number | false) {
  const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
  const cash = r2(Number(s.cash_tips ?? 0)), card = r2(Number(s.card_tips ?? 0));
  if (cash + card <= 0) return;
  const jr = await o.one('account.journal', [['code', '=', 'MISC']], ['id']);
  const label = `Shift ${s.shift_code} tips (employees)`;
  const lines: unknown[] = [];
  if (cash > 0) lines.push([0, 0, { account_id: await acc(o, '531001', 'cash_points'), name: label + ' – cash', debit: cash, credit: 0 }]);
  if (card > 0) lines.push([0, 0, { account_id: await acc(o, '512002', 'card_clearing'), name: label + ' – card', debit: card, credit: 0 }]);
  lines.push([0, 0, { account_id: await acc(o, '461001', 'tips_payable'), name: label, debit: 0, credit: r2(cash + card), partner_id: partner || false,
                      ...(analytic ? { analytic_distribution: { [String(analytic)]: 100 } } : {}) }]);
  const date = s.end_time ? new Date(new Date(s.end_time).getTime() + 4 * 3600e3).toISOString().slice(0, 10) : undefined;
  const mv = await o.create('account.move', { move_type: 'entry', journal_id: jr?.id, ref: label, ...(date ? { date } : {}), line_ids: lines });
  await o.call('account.move', 'action_post', { ids: [mv] });
  await o.call('x_valet_shift', 'write', { ids: [shiftId], vals: { x_tips_move_id: mv } });
}
