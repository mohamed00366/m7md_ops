// credits.ts — ticket credit notes requested in the dashboard -> Odoo credit notes linked to the ticket invoice.
// Full or partial amount (gross, VAT included). Money goes back on the ticket's payment method (cash / card).
import { dubaiDate, Odoo, OdooError, Refs, type Cfg } from './odoo.ts';

export type Credit = {
  credit_id: string; ticket_id: string; ticket_code: string; amount: number; reason: string;
  created_at: string; payment_mode: string | null; odoo_move_id: number | null; requested_by_name?: string | null; approved_by_name?: string | null;
};
export type CreditResult = { credit_move_id: number; credit_name: string | null; refund: boolean };

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export async function syncCredit(o: Odoo, refs: Refs, cfg: Cfg, c: Credit): Promise<CreditResult> {
  const amount = r2(Number(c.amount) || 0);
  if (amount <= 0) throw new OdooError('Credit amount must be more than zero.');
  const origin = `CN:${c.credit_id}`;
  const F = ['id', 'name', 'state', 'payment_state', 'amount_total', 'journal_id'];

  // 1) the ticket invoice
  let inv = c.odoo_move_id ? await o.one('account.move', [['id', '=', c.odoo_move_id], ['move_type', '=', 'out_invoice']], F) : null;
  if (!inv) inv = await o.one('account.move', [['move_type', '=', 'out_invoice'], ['ref', '=', c.ticket_code], ['state', '=', 'posted']], F);
  if (!inv || inv.state !== 'posted') throw new OdooError(`Ticket ${c.ticket_code} has no posted invoice in Odoo yet (will retry).`);
  if (amount > r2(inv.amount_total) + 0.001) throw new OdooError(`Credit ${amount} is more than the invoice ${inv.amount_total}.`);

  // 2) the credit note (idempotent: found again by its origin)
  let cn = await o.one('account.move', [['move_type', '=', 'out_refund'], ['invoice_origin', '=', origin], ['state', '!=', 'cancel']], F);
  if (!cn) {
    const ctx = { active_model: 'account.move', active_ids: [inv.id] };
    const reason = `${c.reason}${c.requested_by_name ? ' | requested by ' + c.requested_by_name : ''}${c.approved_by_name ? ' | approved by ' + c.approved_by_name : ''}`;
    const wiz = await o.create('account.move.reversal', {
      move_ids: [[6, 0, [inv.id]]], reason, date: dubaiDate(c.created_at),
      journal_id: Array.isArray(inv.journal_id) ? inv.journal_id[0] : inv.journal_id,
    }, ctx);
    const act = await o.call('account.move.reversal', 'reverse_moves', { ids: [wiz], context: ctx });
    let id: number | null = act?.res_id ?? null;
    if (!id) {
      const f = await o.one('account.move', [['reversed_entry_id', '=', inv.id], ['state', '=', 'draft'], ['move_type', '=', 'out_refund']], ['id'], );
      id = f?.id ?? null;
    }
    if (!id) throw new OdooError('Odoo did not return the credit note.');
    await o.call('account.move', 'write', { ids: [id], vals: { invoice_origin: origin, ref: `${c.ticket_code} / credit` } });
    cn = await o.one('account.move', [['id', '=', id]], F);

    // partial credit: scale the lines so the credit note total is the requested amount
    if (amount < r2(inv.amount_total) - 0.001) {
      const lines = await o.call('account.move.line', 'search_read', {
        domain: [['move_id', '=', id], ['display_type', '=', 'product']], fields: ['id', 'price_unit'],
      });
      const k = amount / inv.amount_total;
      for (const l of lines ?? []) {
        await o.call('account.move.line', 'write', { ids: [l.id], vals: { price_unit: r2(l.price_unit * k) } });
      }
      // rounding: put the last cents on the first line
      cn = await o.one('account.move', [['id', '=', id]], F);
      const diff = r2(amount - cn.amount_total);
      if (Math.abs(diff) >= 0.01 && lines?.length) {
        const l0 = await o.one('account.move.line', [['id', '=', lines[0].id]], ['price_unit', 'tax_ids']);
        const vat = (await o.call('account.tax', 'read', { ids: l0.tax_ids, fields: ['amount', 'price_include'] }) ?? [])
          .filter((t: any) => !t.price_include).reduce((s: number, t: any) => s + t.amount / 100, 0);
        await o.call('account.move.line', 'write', { ids: [l0.id], vals: { price_unit: r2(l0.price_unit + diff / (1 + vat)) } });
        cn = await o.one('account.move', [['id', '=', id]], F);
      }
    }
  }

  // 3) post
  if (cn.state === 'draft') {
    await o.call('account.move', 'action_post', { ids: [cn.id] });
    cn = await o.one('account.move', [['id', '=', cn.id]], F);
  }

  // 4) money back on the ticket's payment method (only when the ticket was paid)
  let refund = ['paid', 'in_payment', 'reversed'].includes(cn.payment_state);
  const invPaid = ['paid', 'in_payment'].includes(inv.payment_state);
  if (!refund && invPaid && cn.state === 'posted' && (c.payment_mode === 'Cash' || c.payment_mode === 'C-Card')) {
    const journal = c.payment_mode === 'Cash'
      ? await refs.journal('cash', cfg.cash_journal)
      : await refs.journal('bank', cfg.card_journal);
    const ctx = { active_model: 'account.move', active_ids: [cn.id] };
    const wiz = await o.create('account.payment.register', { journal_id: journal, payment_date: dubaiDate(c.created_at) }, ctx);
    await o.call('account.payment.register', 'action_create_payments', { ids: [wiz], context: ctx });
    refund = true;
  }
  return { credit_move_id: cn.id, credit_name: cn.name ?? null, refund };
}
