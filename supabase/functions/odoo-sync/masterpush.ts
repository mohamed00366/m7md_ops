// 281: local changes of areas / clients / points / branches / point-branch links -> Odoo (the other direction of pullMaster).
// Latest change wins: when Odoo changed the record after the local change, the local change is dropped (the pull brings Odoo's).
// Delete: deleted in Odoo when nothing uses it there, else archived (partner inactive, point / area closed, branch stopped).
import { Odoo } from './odoo.ts';

export type OutRow = {
  entity: 'area' | 'master' | 'point' | 'site' | 'link';
  ref_id: string; op: 'upsert' | 'delete'; changed_at: string; odoo_id: number | null; exists?: boolean;
  payload?: Record<string, any>; [k: string]: any;
};
export type Ack = { entity: string; ref_id: string; changed_at: string; ok: boolean; odoo_id?: number | null; error?: string | null; note?: string;
  extra?: { entity: string; ref_id: string; odoo_id: number }[] };

const odooTime = (s: string | null | undefined) => (s ? new Date(s.replace(' ', 'T') + 'Z').getTime() : 0);
const isNewer = (writeDate: string | null | undefined, changedAt: string) => odooTime(writeDate) > new Date(changedAt).getTime() + 1000;

async function read(o: Odoo, model: string, id: number, fields: string[]) {
  const r = await o.call(model, 'search_read', { domain: [['id', '=', id]], fields: ['id', 'write_date', ...fields], context: { active_test: false }, limit: 1 });
  return Array.isArray(r) && r.length ? r[0] : null;
}

async function count(o: Odoo, model: string, domain: unknown[]): Promise<number> {
  try { return Number(await o.call(model, 'search_count', { domain, context: { active_test: false } })) || 0; } catch { return -1; }
}

/** Delete when nothing uses it, else archive. */
async function removeOrArchive(o: Odoo, model: string, id: number, used: number, archive: Record<string, unknown>): Promise<string> {
  if (used === 0) {
    try { await o.call(model, 'unlink', { ids: [id] }); return 'deleted'; } catch { /* still referenced somewhere: archive */ }
  }
  await o.call(model, 'write', { ids: [id], vals: archive });
  return 'archived';
}

async function upsertPartner(o: Odoo, row: OutRow, vals: Record<string, unknown>, createOnly: Record<string, unknown> = {}): Promise<{ id: number; note?: string }> {
  if (row.odoo_id) {
    const cur = await read(o, 'res.partner', row.odoo_id, ['name', 'vat', 'parent_id', 'active', 'is_company']);
    if (cur) {
      if (isNewer(cur.write_date, row.changed_at)) return { id: row.odoo_id, note: 'odoo newer' };
      // only what really changed (an unchanged VAT is not re-validated, the contact type is kept)
      const diff: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(vals)) {
        const now = Array.isArray(cur[k]) ? cur[k][0] : cur[k];
        if ((now ?? false) !== (v ?? false)) diff[k] = v;
      }
      if (Object.keys(diff).length) await o.call('res.partner', 'write', { ids: [row.odoo_id], vals: diff });
      return { id: row.odoo_id, note: Object.keys(diff).length ? undefined : 'same' };
    }
  }
  return { id: await o.create('res.partner', { ...vals, ...createOnly }) };
}

async function pushOne(o: Odoo, r: OutRow): Promise<Ack> {
  const ack: Ack = { entity: r.entity, ref_id: r.ref_id, changed_at: r.changed_at, ok: true };
  const p = r.payload ?? {};

  // ------------------------------------------------ deletes
  if (r.op === 'delete' || r.exists === false) {
    if (r.entity === 'link') {
      const pt = Number(p.point_odoo_id), pa = Number(p.site_odoo_id);
      if (pt && pa) {
        const vbs: any[] = await o.call('x_valet_branch', 'search_read', {
          domain: [['x_point_id', '=', pt], ['x_partner_id', '=', pa], ['x_branch_type', '=', 'contract']], fields: ['id', 'x_contract_line_ids'],
        });
        for (const vb of vbs ?? []) {
          const used = (vb.x_contract_line_ids?.length ?? 0) + Math.max(0, await count(o, 'x_valet_ticket', [['x_branch_id', '=', vb.id]]));
          ack.note = await removeOrArchive(o, 'x_valet_branch', vb.id, used, { x_status: 'stopped' });
        }
        await o.call('x_valet_point', 'write', { ids: [pt], vals: { x_branch_ids: [[3, pa]] } });
      }
      return ack;
    }
    const id = r.odoo_id;
    if (!id) return ack;
    if (r.entity === 'area') {
      ack.note = await removeOrArchive(o, 'x_valet_area', id, 0, { x_closed: true });
    } else if (r.entity === 'point') {
      const used = Math.max(0, await count(o, 'x_valet_ticket', [['x_point_id', '=', id]])) + Math.max(0, await count(o, 'account.move', [['x_valet_point_id', '=', id]]));
      ack.note = await removeOrArchive(o, 'x_valet_point', id, used, { x_closed: true });
    } else {
      const inv = await count(o, 'account.move', [['partner_id', 'child_of', id]]);
      const used = inv < 0 ? 1 : inv + Math.max(0, await count(o, 'x_valet_branch', [['x_partner_id', '=', id]]));
      ack.note = await removeOrArchive(o, 'res.partner', id, used, { active: false });
    }
    return ack;
  }

  // ------------------------------------------------ create / update
  if (r.entity === 'area') {
    const vals = { x_name: r.name, x_code: r.code || false, x_closed: r.active === false };
    if (r.odoo_id) {
      const cur = await read(o, 'x_valet_area', r.odoo_id, ['x_name']);
      if (cur) {
        if (isNewer(cur.write_date, r.changed_at)) { ack.note = 'odoo newer'; ack.odoo_id = r.odoo_id; return ack; }
        await o.call('x_valet_area', 'write', { ids: [r.odoo_id], vals });
        ack.odoo_id = r.odoo_id;
        return ack;
      }
    }
    ack.odoo_id = await o.create('x_valet_area', vals);
    return ack;
  }

  if (r.entity === 'master') {
    const vals: Record<string, unknown> = { name: r.name, is_company: true, active: r.active !== false };
    if (r.vat) vals.vat = r.vat;
    const res = await upsertPartner(o, r, vals);
    ack.odoo_id = res.id; ack.note = res.note;
    return ack;
  }

  if (r.entity === 'site') {
    let parent: number | false = r.master_odoo_id || false;
    if (!parent && r.master_ref && r.master_name) {
      // its client was never in Odoo: create it now (same company name if it already exists there)
      const ex = await o.one('res.partner', [['name', '=ilike', r.master_name], ['is_company', '=', true]], ['id']);
      parent = ex ? ex.id : await o.create('res.partner', { name: r.master_name, is_company: true, ...(r.master_vat ? { vat: r.master_vat } : {}) });
      ack.extra = [{ entity: 'master', ref_id: r.master_ref, odoo_id: parent as number }];
    }
    const vals: Record<string, unknown> = { name: r.name, parent_id: parent, active: r.active !== false };
    if (r.vat) vals.vat = r.vat;
    const res = await upsertPartner(o, r, vals, { type: 'other', is_company: false });
    ack.odoo_id = res.id; ack.note = res.note;
    return ack;
  }

  if (r.entity === 'point') {
    const vals: Record<string, unknown> = {
      x_name: r.name, x_address: r.address || false, x_closed: r.active === false, x_area_id: r.area_odoo_id || false,
    };
    if (r.code) vals.x_code = r.code;
    if (r.odoo_id) {
      const cur = await read(o, 'x_valet_point', r.odoo_id, ['x_name']);
      if (cur) {
        if (isNewer(cur.write_date, r.changed_at)) { ack.note = 'odoo newer'; ack.odoo_id = r.odoo_id; return ack; }
        await o.call('x_valet_point', 'write', { ids: [r.odoo_id], vals });
        ack.odoo_id = r.odoo_id;
        return ack;
      }
    }
    ack.odoo_id = await o.create('x_valet_point', vals);
    return ack;
  }

  // link: the branch is served at the point (Valet > Branches contract row + the point's Branches tab)
  const pt = Number(r.point_odoo_id), pa = Number(r.site_odoo_id);
  if (!pt || !pa) throw new Error('the point or the branch is not in Odoo yet');
  const vb = await o.one('x_valet_branch', [['x_point_id', '=', pt], ['x_partner_id', '=', pa], ['x_branch_type', '=', 'contract']], ['id', 'x_status']);
  if (vb) {
    if (vb.x_status === 'stopped') await o.call('x_valet_branch', 'write', { ids: [vb.id], vals: { x_status: 'active' } });
  } else {
    await o.create('x_valet_branch', {
      x_name: r.site_name || 'Branch', x_branch_type: 'contract', x_status: 'active', x_partner_id: pa, x_point_id: pt,
      ...(r.master_odoo_id ? { x_client_id: r.master_odoo_id } : {}),
    });
  }
  await o.call('x_valet_point', 'write', { ids: [pt], vals: { x_branch_ids: [[4, pa]] } });
  return ack;
}

/** Pushes the outbox rows (already in order: areas, clients, points, branches, links). */
export async function pushMaster(o: Odoo, rows: OutRow[]): Promise<Ack[]> {
  const acks: Ack[] = [];
  const madeIds = new Map<string, number>();   // ref -> odoo id created in this run (a site right after its client, ...)
  for (const r0 of rows) {
    const r = { ...r0 };
    if (r.entity === 'site' && !r.master_odoo_id && r.master_ref && madeIds.has(r.master_ref)) r.master_odoo_id = madeIds.get(r.master_ref);
    if (r.entity === 'point' && !r.area_odoo_id && r.area_ref && madeIds.has(r.area_ref)) r.area_odoo_id = madeIds.get(r.area_ref);
    if (r.entity === 'link') {
      if (!r.point_odoo_id && r.point_ref && madeIds.has(r.point_ref)) r.point_odoo_id = madeIds.get(r.point_ref);
      if (!r.site_odoo_id && r.site_ref && madeIds.has(r.site_ref)) r.site_odoo_id = madeIds.get(r.site_ref);
    }
    try {
      const a = await pushOne(o, r);
      if (a.odoo_id) madeIds.set(r.ref_id, a.odoo_id);
      for (const e of a.extra ?? []) madeIds.set(e.ref_id, e.odoo_id);
      acks.push(a);
    } catch (e) {
      acks.push({ entity: r.entity, ref_id: r.ref_id, changed_at: r.changed_at, ok: false, error: (e as Error).message.slice(0, 400) });
      if (/\(429\)/.test((e as Error).message)) break;   // Odoo throttles: the rest waits for the next run
    }
  }
  return acks;
}
