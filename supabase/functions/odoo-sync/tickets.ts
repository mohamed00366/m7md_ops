// tickets.ts — every valet ticket (all its columns) -> Odoo x_valet_ticket (Valet ▸ Tickets), linked to its shift and point.
// One Odoo field per database column (x_t_<column>), created the first time the column is seen: a new column in the
// database shows up in Odoo by itself. Found again by x_uid (= ticket id); only changed tickets are sent.
import { Odoo, OdooError } from './odoo.ts';

export type TicketRow = {
  ticket_id: string;
  point_odoo_id: number | null;
  shift_odoo_id: number | null;     // x_valet_shift of the shift that closed the ticket
  branch_odoo_id: number | null;    // x_valet_branch (merchant branch, else the point's visitor / vip branch)
  area_odoo_id?: number | null;     // 281: x_valet_area of the point
  client_odoo_id?: number | null;   // 281: client company (res.partner)
  branch_partner_odoo_id?: number | null; // 281: branch contact (res.partner)
  data: Record<string, unknown>;    // the whole valet_tickets row
};

// columns not worth a field (big blobs) – kept in x_data only
const SKIP = new Set(['photo_in', 'photo_out', 'photos', 'signature', 'raw', 'search_vector']);
const ISO_DT = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)?$/;
const ISO_D = /^\d{4}-\d{2}-\d{2}$/;

const fieldName = (col: string) => ('x_t_' + col.toLowerCase().replace(/[^a-z0-9_]/g, '_')).slice(0, 60);

type Kind = 'char' | 'float' | 'boolean' | 'datetime' | 'date' | 'text';
function kindOf(v: unknown): Kind | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'boolean') return 'boolean';
  if (typeof v === 'number') return 'float';
  if (typeof v === 'string') return ISO_DT.test(v) ? 'datetime' : ISO_D.test(v) ? 'date' : v.length > 250 ? 'text' : 'char';
  return 'text';
}

function odooValue(kind: string, v: unknown): unknown {
  if (v === null || v === undefined || v === '') return false;
  switch (kind) {
    case 'boolean': return !!v;
    case 'float': case 'integer': case 'monetary': { const n = Number(v); return Number.isFinite(n) ? n : false; }
    case 'datetime': { const d = new Date(String(v)); return isNaN(d.getTime()) ? false : d.toISOString().replace('T', ' ').slice(0, 19); }
    case 'date': return String(v).slice(0, 10);
    case 'text': case 'html': return typeof v === 'string' ? v : JSON.stringify(v);
    default: return typeof v === 'string' ? v.slice(0, 1000) : JSON.stringify(v);
  }
}

let modelId: number | null = null;
let fields: Map<string, string> | null = null;   // odoo field name -> ttype

async function ensureModel(o: Odoo): Promise<void> {
  if (modelId && fields) return;
  const m = await o.one('ir.model', [['model', '=', 'x_valet_ticket']], ['id']);
  modelId = m ? m.id : await o.create('ir.model', {
    name: 'Valet Ticket', model: 'x_valet_ticket', state: 'manual', order: 'x_t_created_at desc, id desc',
    field_id: [
      [0, 0, { name: 'x_name', field_description: 'Ticket', ttype: 'char', state: 'manual' }],
    ],
  });
  if (!m) {
    // everyone with Valet access reads it; the sync (admin key) writes it
    try { await o.create('ir.access', { name: 'x_valet_ticket all', model_id: modelId, group_id: 1, operation: 'cru' }); } catch { /* exists */ }
  }
  const have = (await o.call('ir.model.fields', 'search_read', { domain: [['model_id', '=', modelId]], fields: ['name', 'ttype'] })) ?? [];
  fields = new Map(have.map((f: any) => [f.name, f.ttype]));
  const base: [string, string, string, string?][] = [
    ['x_uid', 'char', 'Ticket id (database)'],
    ['x_point_id', 'many2one', 'Point', 'x_valet_point'],
    ['x_shift_id', 'many2one', 'Shift', 'x_valet_shift'],
    ['x_branch_id', 'many2one', 'Branch', 'x_valet_branch'],
    ['x_data', 'text', 'All data (JSON)'],
    ['x_synced_at', 'datetime', 'Synced at'],
  ];
  for (const [name, ttype, label, relation] of base) {
    if (fields.has(name)) continue;
    await o.create('ir.model.fields', {
      model_id: modelId, name, ttype, field_description: label, state: 'manual', ...(relation ? { relation, on_delete: 'set null' } : {}),
      ...(name === 'x_uid' ? { index: true } : {}),
    });
    fields.set(name, ttype);
  }
  // 281: area · client · branch of the ticket (follow the current links); skipped until Valet > Areas exists
  const tree: [string, string, string][] = [
    ['x_area_id', 'Area', 'x_valet_area'], ['x_client_id', 'Client', 'res.partner'], ['x_branch_partner_id', 'Branch (contact)', 'res.partner'],
  ];
  for (const [name, label, relation] of tree) {
    if (fields.has(name)) continue;
    try {
      await o.create('ir.model.fields', { model_id: modelId, name, ttype: 'many2one', field_description: label, state: 'manual', relation, on_delete: 'set null', index: true });
      fields.set(name, 'many2one');
    } catch { /* model not ready yet: next run */ }
  }
}

/** Creates the Odoo fields for columns seen for the first time. */
async function ensureColumns(o: Odoo, rows: TicketRow[]): Promise<void> {
  const want = new Map<string, { col: string; kind: Kind }>();
  for (const r of rows) {
    for (const [col, v] of Object.entries(r.data)) {
      if (SKIP.has(col)) continue;
      const f = fieldName(col);
      if (fields!.has(f) || want.has(f)) continue;
      const k = kindOf(v);
      if (k) want.set(f, { col, kind: k });
    }
  }
  for (const [name, { col, kind }] of want) {
    const label = col.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    try {
      await o.create('ir.model.fields', { model_id: modelId, name, ttype: kind, field_description: label, state: 'manual' });
      fields!.set(name, kind);
    } catch (e) {
      throw new OdooError(`Could not add the ticket column "${col}" in Odoo: ${(e as Error).message}`);
    }
  }
}

function vals(r: TicketRow): Record<string, unknown> {
  const v: Record<string, unknown> = {
    x_name: String(r.data.ticket_code ?? r.data.code ?? r.ticket_id),
    x_uid: r.ticket_id,
    x_point_id: r.point_odoo_id || false,
    x_shift_id: r.shift_odoo_id || false,
    x_branch_id: r.branch_odoo_id || false,
    ...(fields!.has('x_area_id') ? { x_area_id: r.area_odoo_id || false } : {}),
    ...(fields!.has('x_client_id') ? { x_client_id: r.client_odoo_id || false } : {}),
    ...(fields!.has('x_branch_partner_id') ? { x_branch_partner_id: r.branch_partner_odoo_id || false } : {}),
    x_data: JSON.stringify(r.data),
    x_synced_at: new Date().toISOString().replace('T', ' ').slice(0, 19),
  };
  for (const [col, val] of Object.entries(r.data)) {
    const f = fieldName(col);
    const kind = fields!.get(f);
    if (kind) v[f] = odooValue(kind, val);
  }
  return v;
}

/** Upserts a batch of tickets; returns ticket id -> Odoo id. */
export async function syncTicketRows(o: Odoo, rows: TicketRow[]): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (!rows.length) return out;
  await ensureModel(o);
  await ensureColumns(o, rows);
  const ex = (await o.call('x_valet_ticket', 'search_read', {
    domain: [['x_uid', 'in', rows.map((r) => r.ticket_id)]], fields: ['id', 'x_uid'],
  })) ?? [];
  const byUid = new Map<string, number>(ex.map((e: any) => [e.x_uid, e.id]));
  const create: Record<string, unknown>[] = [];
  const createUids: string[] = [];
  for (const r of rows) {
    const id = byUid.get(r.ticket_id);
    if (id) {
      await o.call('x_valet_ticket', 'write', { ids: [id], vals: vals(r) });
      out.set(r.ticket_id, id);
    } else {
      create.push(vals(r));
      createUids.push(r.ticket_id);
    }
  }
  if (create.length) {
    const ids = await o.call('x_valet_ticket', 'create', { vals_list: create });
    (Array.isArray(ids) ? ids : [ids]).forEach((id: number, i: number) => out.set(createUids[i], id));
  }
  return out;
}
