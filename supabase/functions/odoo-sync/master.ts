// Odoo master data: "Valet" menu with Points (x_valet_point), clients = companies, branches = their child contacts.
// ensureValetMaster() builds the structure once (idempotent, versioned); pullMaster() reads it for the system.
import { Odoo, OdooError } from './odoo.ts';

const VERSION = '4';
const PARAM = 'vip_valet.master_version';
export let lastNotes: string[] = [];

async function xmlid(o: Odoo, module: string, name: string): Promise<number | null> {
  const r = await o.one('ir.model.data', [['module', '=', module], ['name', '=', name]], ['res_id']);
  return r ? r.res_id : null;
}

async function ensureField(o: Odoo, model: string, modelId: number, vals: Record<string, unknown>) {
  const f = await o.one('ir.model.fields', [['model', '=', model], ['name', '=', vals.name]]);
  if (f) return f.id;
  return o.create('ir.model.fields', { model_id: modelId, state: 'manual', ...vals });
}

async function ensureView(o: Odoo, name: string, vals: Record<string, unknown>) {
  const v = await o.one('ir.ui.view', [['name', '=', name]], ['id']);
  if (v) {
    await o.call('ir.ui.view', 'write', { ids: [v.id], vals: { arch_db: vals.arch_db } });
    return v.id;
  }
  return o.create('ir.ui.view', { name, ...vals });
}

async function ensureMenu(o: Odoo, name: string, parent: number | false, action: string | false, seq: number) {
  const m = await o.one('ir.ui.menu', [['name', '=', name], ['parent_id', '=', parent]], ['id']);
  const vals: Record<string, unknown> = { name, parent_id: parent, sequence: seq };
  if (action) vals.action = action;
  if (m) { await o.call('ir.ui.menu', 'write', { ids: [m.id], vals }); return m.id; }
  return o.create('ir.ui.menu', vals);
}

async function ensureAction(o: Odoo, name: string, vals: Record<string, unknown>) {
  const a = await o.one('ir.actions.act_window', [['name', '=', name]], ['id']);
  if (a) { await o.call('ir.actions.act_window', 'write', { ids: [a.id], vals }); return a.id; }
  return o.create('ir.actions.act_window', { name, ...vals });
}

async function ensureServerAction(o: Odoo, name: string, modelId: number, code: string): Promise<number> {
  const a = await o.one('ir.actions.server', [['name', '=', name]], ['id']);
  const vals = { name, model_id: modelId, state: 'code', code };
  if (a) { await o.call('ir.actions.server', 'write', { ids: [a.id], vals }); return a.id; }
  return o.create('ir.actions.server', vals);
}

/** Split code: a cost line on a point's analytic account (100%) also gets the branches' accounts with their shares. */
export const SPLIT_CODE = `for line in records:
    move = line.move_id
    if move.move_type in ('out_invoice', 'out_refund', 'out_receipt'):
        continue
    dist = line.analytic_distribution or {}
    if len(dist) != 1:
        continue
    key = list(dist.keys())[0]
    if ',' in key or not key.isdigit():
        continue
    point = env['x_valet_point'].search([('x_analytic_id', '=', int(key))], limit=1)
    if not point:
        continue
    parts = []
    for r in point.x_stat_ids:
        acc = r.x_partner_id.x_valet_analytic_id or r.x_partner_id.parent_id.x_valet_analytic_id
        if r.x_share > 0 and acc:
            parts.append((str(acc.id), r.x_share))
    total = sum(p[1] for p in parts)
    if not total:
        continue
    new = {key: dist[key]}
    done = 0.0
    for i, (k, share) in enumerate(parts):
        pct = round(share * 100.0 / total, 2) if i < len(parts) - 1 else round(100.0 - done, 2)
        done += pct
        new[k] = round(new.get(k, 0) + pct, 2)
    line.write({'analytic_distribution': new})`;

async function ensureExpenseSplit(o: Odoo, notes: string[]) {
  try {
    const aml = await o.one('ir.model', [['model', '=', 'account.move.line']], ['id']);
    if (!aml) throw new Error('account.move.line not found');
    const field = await o.one('ir.model.fields', [['model', '=', 'account.move.line'], ['name', '=', 'analytic_distribution']], ['id']);
    const name = 'Valet: split point costs over branches';
    const act = await ensureServerAction(o, name, aml.id, SPLIT_CODE);
    const fg = await o.call('base.automation', 'fields_get', { attributes: ['type'] });
    const vals: Record<string, unknown> = {
      name, model_id: aml.id, trigger: 'on_create_or_write', active: true,
    };
    if (field && fg.trigger_field_ids) vals.trigger_field_ids = [[6, 0, [field.id]]];
    if (fg.action_server_ids) vals.action_server_ids = [[6, 0, [act]]];
    else if (fg.action_server_id) vals.action_server_id = act;
    const au = await o.one('base.automation', [['name', '=', name]], ['id']);
    if (au) await o.call('base.automation', 'write', { ids: [au.id], vals });
    else await o.create('base.automation', vals);
    try { await o.call('ir.actions.server', 'write', { ids: [act], vals: { usage: 'base_automation' } }); } catch { /* older */ }
    notes.push('expense split: automation ok');
  } catch (e) {
    notes.push('expense split: ' + (e as Error).message.slice(0, 200));
  }
}

/** Odoo 20: one ir.access "crud" rule for internal users (older: ir.model.access). */
async function ensureAccess(o: Odoo, modelId: number, name: string, groupUser: number | null, notes: string[]) {
  try {
    const fg = await o.call('ir.access', 'fields_get', { attributes: ['type'] });
    const rules = await o.call('ir.access', 'search_read', { domain: [['model_id', '=', modelId]], fields: ['id', 'operation'] });
    const keep = rules.find((r: any) => r.operation === 'crud');
    const extra = rules.filter((r: any) => r !== keep).map((r: any) => r.id);
    if (extra.length) await o.call('ir.access', 'unlink', { ids: extra });
    const vals: Record<string, unknown> = { name, model_id: modelId, operation: 'crud' };
    if (fg.group_ids) vals.group_ids = [[6, 0, [groupUser]]];
    else if (fg.group_id) vals.group_id = groupUser;
    if (keep) await o.call('ir.access', 'write', { ids: [keep.id], vals });
    else await o.create('ir.access', vals);
    notes.push(`${name}: crud, removed ${extra.length}`);
  } catch (e) {
    notes.push(`${name}: ` + (e as Error).message.slice(0, 200));
    try {
      if (!(await o.one('ir.model.access', [['model_id', '=', modelId]]))) {
        await o.create('ir.model.access', {
          name: name.replace(/\W+/g, '_').toLowerCase(), model_id: modelId, group_id: groupUser,
          perm_read: true, perm_write: true, perm_create: true, perm_unlink: true,
        });
      }
    } catch (e2) { notes.push('ir.model.access: ' + (e2 as Error).message.slice(0, 120)); }
  }
}

/** Builds Valet > Points / Clients / Branches in Odoo. Returns true when something was (re)built. */
export async function ensureValetMaster(o: Odoo, force = false): Promise<boolean> {
  if (!force) {
    const p = await o.one('ir.config_parameter', [['key', '=', PARAM]], ['value']);
    if (p && p.value === VERSION) return false;
  }
  // 1) model
  let model = await o.one('ir.model', [['model', '=', 'x_valet_point']], ['id']);
  const modelId: number = model ? model.id : await o.create('ir.model', { name: 'Valet Point', model: 'x_valet_point', state: 'manual' });
  const partnerModel = await o.one('ir.model', [['model', '=', 'res.partner']], ['id']);
  if (!partnerModel) throw new OdooError('res.partner model not found');

  // 2) fields
  await ensureField(o, 'x_valet_point', modelId, { name: 'x_code', field_description: 'Code', ttype: 'char', copied: false });
  await ensureField(o, 'x_valet_point', modelId, { name: 'x_closed', field_description: 'Closed', ttype: 'boolean' });
  await ensureField(o, 'x_valet_point', modelId, { name: 'x_country_id', field_description: 'Country', ttype: 'many2one', relation: 'res.country' });
  await ensureField(o, 'x_valet_point', modelId, { name: 'x_city', field_description: 'City', ttype: 'char' });
  await ensureField(o, 'x_valet_point', modelId, { name: 'x_address', field_description: 'Address', ttype: 'char' });
  await ensureField(o, 'x_valet_point', modelId, {
    name: 'x_analytic_id', field_description: 'Analytic Account', ttype: 'many2one', relation: 'account.analytic.account', copied: false,
  });
  await ensureField(o, 'x_valet_point', modelId, {
    name: 'x_branch_ids', field_description: 'Branches', ttype: 'many2many', relation: 'res.partner',
    relation_table: 'x_valet_point_branch_rel', column1: 'x_point_id', column2: 'x_partner_id',
  });
  await ensureField(o, 'res.partner', partnerModel.id, {
    name: 'x_valet_point_ids', field_description: 'Valet Points', ttype: 'many2many', relation: 'x_valet_point',
    relation_table: 'x_valet_point_branch_rel', column1: 'x_partner_id', column2: 'x_point_id',
  });
  await ensureField(o, 'res.partner', partnerModel.id, {
    name: 'x_valet_analytic_id', field_description: 'Valet Analytic Account', ttype: 'many2one', relation: 'account.analytic.account', copied: false,
  });

  // 3) access for internal users
  const groupUser = await xmlid(o, 'base', 'group_user');
  const notes: string[] = [];
  await ensureAccess(o, modelId, 'Valet Point: internal users', groupUser, notes);

  // 3b) ticket counts per branch (filled by the system every 5 minutes, read-only in Odoo)
  const stat = await o.one('ir.model', [['model', '=', 'x_valet_point_stat']], ['id']);
  const statId: number = stat ? stat.id : await o.create('ir.model', { name: 'Valet Branch Tickets', model: 'x_valet_point_stat', state: 'manual' });
  await ensureField(o, 'x_valet_point_stat', statId, {
    name: 'x_point_id', field_description: 'Point', ttype: 'many2one', relation: 'x_valet_point', on_delete: 'cascade', index: true,
  });
  await ensureField(o, 'x_valet_point_stat', statId, { name: 'x_partner_id', field_description: 'Branch', ttype: 'many2one', relation: 'res.partner' });
  await ensureField(o, 'x_valet_point_stat', statId, { name: 'x_client_id', field_description: 'Client', ttype: 'many2one', relation: 'res.partner' });
  for (const [name, label] of [['x_active', 'Active now'], ['x_today', 'Today'], ['x_month', 'This month'], ['x_total', 'Total']]) {
    await ensureField(o, 'x_valet_point_stat', statId, { name, field_description: label, ttype: 'integer' });
  }
  await ensureField(o, 'x_valet_point_stat', statId, { name: 'x_last', field_description: 'Last ticket', ttype: 'datetime' });
  await ensureField(o, 'x_valet_point_stat', statId, { name: 'x_share', field_description: 'Expense share %', ttype: 'float' });
  await ensureField(o, 'x_valet_point_stat', statId, { name: 'x_suggested', field_description: 'Suggested % (tickets this month)', ttype: 'float' });
  await ensureAccess(o, statId, 'Valet Branch Tickets: internal users', groupUser, notes);
  await ensureField(o, 'x_valet_point', modelId, {
    name: 'x_stat_ids', field_description: 'Branches & tickets', ttype: 'one2many', relation: 'x_valet_point_stat', relation_field: 'x_point_id',
  });
  for (const [name, label] of [['x_tickets_active', 'Active now'], ['x_tickets_today', 'Tickets today'], ['x_tickets_month', 'Tickets this month'], ['x_tickets_total', 'Tickets total']]) {
    await ensureField(o, 'x_valet_point', modelId, { name, field_description: label, ttype: 'integer', copied: false });
  }
  lastNotes = notes;

  // 3c) actions: tickets of a branch / of a point, expense split automation
  const aRow = await ensureServerAction(o, 'Valet: tickets of the branch', statId, `r = record
action = {
    'type': 'ir.actions.act_window',
    'name': 'Tickets – %s' % (r.x_partner_id.display_name or ''),
    'res_model': 'account.move',
    'view_mode': 'list,form',
    'views': [(False, 'list'), (False, 'form')],
    'domain': [('x_valet_point_id', '=', r.x_point_id.id), ('x_valet_branch_id', '=', r.x_partner_id.id)],
    'context': {'create': False, 'search_default_group_by_invoice_date': 0},
}`);
  const aPoint = await ensureServerAction(o, 'Valet: tickets of the point', modelId, `action = {
    'type': 'ir.actions.act_window',
    'name': 'Tickets – %s' % (record.x_name or ''),
    'res_model': 'account.move',
    'view_mode': 'list,form',
    'views': [(False, 'list'), (False, 'form')],
    'domain': [('x_valet_point_id', '=', record.id)],
    'context': {'create': False},
}`);
  // expense split by Expense share % retired: the allocation engine in Odoo splits costs now (old automation kept inactive)

  // 4) views
  await ensureView(o, 'vip_valet.point_list', {
    model: 'x_valet_point', type: 'list',
    arch_db: `<list>
      <field name="x_code"/><field name="x_name"/><field name="x_city"/><field name="x_country_id"/>
      <field name="x_branch_ids" widget="many2many_tags"/>
      <field name="x_tickets_active" string="Active" sum="Active"/><field name="x_tickets_today" string="Today" sum="Today"/>
      <field name="x_tickets_month" string="Month" sum="Month"/>
      <field name="x_analytic_id" optional="hide"/><field name="x_closed" optional="hide"/>
    </list>`,
  });
  await ensureView(o, 'vip_valet.point_form', {
    model: 'x_valet_point', type: 'form',
    arch_db: `<form><sheet>
      <div class="oe_button_box" name="button_box">
        <button name="${aPoint}" type="action" class="oe_stat_button" icon="fa-car">
          <field name="x_tickets_total" widget="statinfo" string="Tickets"/>
        </button>
      </div>
      <div class="oe_title"><h1><field name="x_name" placeholder="Point name"/></h1></div>
      <group>
        <group><field name="x_code" placeholder="auto – e.g. AE-POS-0053"/><field name="x_country_id"/><field name="x_city"/><field name="x_address"/></group>
        <group><field name="x_analytic_id" placeholder="auto"/><field name="x_closed"/></group>
      </group>
      <group string="Tickets (updated every 5 minutes)">
        <group><field name="x_tickets_active" string="Active now"/><field name="x_tickets_today"/></group>
        <group><field name="x_tickets_month"/><field name="x_tickets_total"/></group>
      </group>
      <notebook>
      <page string="Branches &amp; tickets">
        <div class="text-muted mb-2">Expense share %: the costs booked on this point's analytic account are split over the branches
          with these percentages (any total is scaled to 100%). Suggested % = share of this month's tickets.</div>
        <field name="x_stat_ids">
          <list editable="bottom" default_order="x_month desc" create="0" delete="0">
            <field name="x_client_id" string="Client" readonly="1"/><field name="x_partner_id" string="Branch" readonly="1"/>
            <field name="x_active" sum="Active" readonly="1" optional="hide"/><field name="x_today" sum="Today" readonly="1"/>
            <field name="x_month" sum="Month" readonly="1"/><field name="x_total" sum="Total" readonly="1"/>
            <field name="x_last" readonly="1" optional="show"/>
            <field name="x_share" sum="Total %" string="Expense share %"/>
            <field name="x_suggested" readonly="1" string="Suggested %"/>
            <button name="${aRow}" type="action" string="Tickets" icon="fa-list"/>
          </list>
        </field>
      </page>
      <page string="Branches (clients served at this point)">
        <field name="x_branch_ids" widget="many2many" domain="[('parent_id', '!=', False)]" context="{'default_type': 'other'}">
          <list><field name="parent_id" string="Client"/><field name="name" string="Branch"/><field name="vat"/><field name="x_valet_analytic_id"/></list>
        </field>
      </page></notebook>
    </sheet></form>`,
  });
  await ensureView(o, 'vip_valet.point_search', {
    model: 'x_valet_point', type: 'search',
    arch_db: `<search><field name="x_name"/><field name="x_code"/><field name="x_branch_ids"/>
      <filter name="open" string="Open" domain="[('x_closed', '=', False)]"/>
      <filter name="closed" string="Closed" domain="[('x_closed', '=', True)]"/>
      <filter name="by_country" string="Country" context="{'group_by': 'x_country_id'}"/></search>`,
  });
  const partnerForm = await xmlid(o, 'base', 'view_partner_form');
  if (partnerForm) {
    for (const anchor of [`//field[@name='vat']`, `//field[@name='category_id']`]) {
      try {
        await ensureView(o, 'vip_valet.partner_form', {
          model: 'res.partner', type: 'form', inherit_id: partnerForm, mode: 'extension', priority: 99,
          arch_db: `<xpath expr="${anchor}" position="after">
            <field name="x_valet_point_ids" widget="many2many_tags" invisible="is_company"/>
            <field name="x_valet_analytic_id"/>
          </xpath>`,
        });
        break;
      } catch { /* next anchor */ }
    }
  }

  // 5) actions + menu "Valet"
  const aPoints = await ensureAction(o, 'Valet Points', {
    res_model: 'x_valet_point', view_mode: 'list,form', context: "{'search_default_open': 1}",
    help: '<p class="o_view_nocontent_smiling_face">Create the first valet point</p><p>Then add the client branches served at it.</p>',
  });
  const aClients = await ensureAction(o, 'Valet Clients', {
    res_model: 'res.partner', view_mode: 'kanban,list,form', domain: "[('is_company', '=', True)]",
    context: "{'default_is_company': True}",
  });
  const aBranches = await ensureAction(o, 'Valet Branches', {
    res_model: 'res.partner', view_mode: 'list,form', domain: "[('parent_id', '!=', False), ('is_company', '=', False)]",
    context: "{'default_type': 'other'}",
  });
  const root = await ensureMenu(o, 'Valet', false, `ir.actions.act_window,${aPoints}`, 90);
  await ensureMenu(o, 'Points', root, `ir.actions.act_window,${aPoints}`, 10);
  await ensureMenu(o, 'Clients', root, `ir.actions.act_window,${aClients}`, 20);
  await ensureMenu(o, 'Branches', root, `ir.actions.act_window,${aBranches}`, 30);

  // 6) done
  const p = await o.one('ir.config_parameter', [['key', '=', PARAM]], ['id']);
  if (p) await o.call('ir.config_parameter', 'write', { ids: [p.id], vals: { value: VERSION } });
  else await o.create('ir.config_parameter', { key: PARAM, value: VERSION });
  return true;
}

const k = (v: any) => !!v.selection;
const m2o = (v: any): number | null => (Array.isArray(v) ? v[0] : (typeof v === 'number' ? v : null));
const m2oName = (v: any): string | null => (Array.isArray(v) ? String(v[1]) : null);

/** Reads points + branches; creates missing analytic accounts (and writes them back). */
export async function pullMaster(
  o: Odoo,
  analytic: (plan: string, code: string | null, name: string) => Promise<number | null>,
) {
  const pts: any[] = await o.call('x_valet_point', 'search_read', {
    domain: [], fields: ['id', 'x_name', 'x_code', 'x_closed', 'x_country_id', 'x_city', 'x_address', 'x_analytic_id', 'x_branch_ids', 'write_date',
      ...(areaFieldReady ? ['x_area_id'] : [])],
    limit: 5000,
  });
  const countryIds = [...new Set(pts.map((p) => m2o(p.x_country_id)).filter((x): x is number => !!x))];
  const countries: Record<number, string> = {};
  if (countryIds.length) {
    for (const c of await o.call('res.country', 'search_read', { domain: [['id', 'in', countryIds]], fields: ['id', 'code'] })) {
      countries[c.id] = c.code;
    }
  }
  // Valet > Branches (x_valet_branch): contract branches carry their invoicing contact (x_partner_id), which keeps
  // the partner id the system already knows. Shared branches (Visitor, VIP, ...) stay in Odoo only.
  let vbs: any[] = [];
  try {
    vbs = await o.call('x_valet_branch', 'search_read', {
      domain: [['x_branch_type', '=', 'contract'], ['x_partner_id', '!=', false]],
      fields: ['id', 'x_partner_id', 'x_point_id', 'x_status'], limit: 10000,
    });
  } catch { vbs = []; }
  const vbByPartner = new Map<number, { points: Set<number>; active: boolean }>();
  for (const v of vbs) {
    const pid = m2o(v.x_partner_id);
    if (!pid) continue;
    const e = vbByPartner.get(pid) ?? { points: new Set<number>(), active: false };
    const pt = m2o(v.x_point_id);
    if (pt && v.x_status !== 'stopped') e.points.add(pt);   // 281: a stopped branch is no longer served at that point
    if (v.x_status !== 'stopped') e.active = true;
    vbByPartner.set(pid, e);
  }
  const branchIds = [...new Set([...pts.flatMap((p) => p.x_branch_ids ?? []), ...vbByPartner.keys()])];
  const brs: any[] = branchIds.length
    ? await o.call('res.partner', 'search_read', {
      domain: [['id', 'in', branchIds], ['active', 'in', [true, false]]],
      fields: ['id', 'name', 'vat', 'active', 'parent_id', 'x_valet_point_ids', 'x_valet_analytic_id'],
      limit: 10000,
    })
    : [];
  const parentIds = [...new Set(brs.map((b) => m2o(b.parent_id)).filter((x): x is number => !!x))];
  const parents: Record<number, any> = {};
  if (parentIds.length) {
    for (const p of await o.call('res.partner', 'search_read', {
      domain: [['id', 'in', parentIds]], fields: ['id', 'name', 'vat', 'x_valet_analytic_id'],
    })) parents[p.id] = p;
  }

  const points = [];
  for (const p of pts) {
    let an = m2o(p.x_analytic_id), anName = m2oName(p.x_analytic_id);
    if (!an) {
      an = await analytic('Valet Points', p.x_code || null, p.x_name);
      if (an) { await o.call('x_valet_point', 'write', { ids: [p.id], vals: { x_analytic_id: an } }); anName = p.x_name; }
    }
    points.push({
      id: p.id, name: p.x_name, code: p.x_code || null, closed: !!p.x_closed,
      country: countries[m2o(p.x_country_id) ?? 0] ?? null, city: p.x_city || null, address: p.x_address || null,
      analytic_id: an, analytic_name: anName, area_id: m2o(p.x_area_id), write_date: p.write_date ?? null,
    });
  }
  const branches = [];
  for (const b of brs) {
    const parent = parents[m2o(b.parent_id) ?? 0];
    // analytic: the branch's own, else the client's, else automatic (written back on the branch)
    let an = m2o(b.x_valet_analytic_id) ?? m2o(parent?.x_valet_analytic_id), anName = m2oName(b.x_valet_analytic_id) ?? m2oName(parent?.x_valet_analytic_id);
    if (!an) {
      an = await analytic('Valet Clients', null, b.name);
      if (an) { await o.call('res.partner', 'write', { ids: [b.id], vals: { x_valet_analytic_id: an } }); anName = b.name; }
    }
    const vb = vbByPartner.get(b.id);
    branches.push({
      id: b.id, name: b.name, vat: b.vat || null, active: vb ? vb.active && b.active !== false : b.active !== false,
      parent_id: parent?.id ?? null, parent_name: parent?.name ?? null, parent_vat: parent?.vat || null,
      point_ids: vb ? [...vb.points] : (b.x_valet_point_ids ?? []), analytic_id: an, analytic_name: anName,
    });
  }
  return { points, branches };
}


type StatRow = { point: number; partner: number; active: number; today: number; month: number; total: number; last: string | null };

/** Writes the per-branch ticket counts under each point (create / update changed / remove stale). */
export async function pushBranchStats(o: Odoo, rows: StatRow[]) {
  // x_active ("Active now") is also Odoo's archive flag on manual models: rows with 0 are archived, so read them too
  const have: any[] = await o.call('x_valet_point_stat', 'search_read', {
    context: { active_test: false }, domain: [], fields: ['id', 'x_point_id', 'x_partner_id', 'x_client_id', 'x_active', 'x_today', 'x_month', 'x_total', 'x_last', 'x_suggested'], limit: 20000,
  });
  const byKey = new Map<string, any>();
  for (const h of have) byKey.set(`${m2o(h.x_point_id)}|${m2o(h.x_partner_id)}`, h);
  // client (company) of each branch
  const partnerIds = [...new Set(rows.map((r) => r.partner))];
  const parentOf: Record<number, number | false> = {};
  if (partnerIds.length) {
    for (const p of await o.call('res.partner', 'search_read', { domain: [['id', 'in', partnerIds], ['active', 'in', [true, false]]], fields: ['id', 'parent_id'] })) {
      parentOf[p.id] = m2o(p.parent_id) ?? p.id;
    }
  }
  const odooTime = (t: string | null) => (t ? new Date(t).toISOString().replace('T', ' ').slice(0, 19) : false);
  // suggested share: tickets this month (else all tickets) of each branch at its point
  const base = new Map<number, { month: number; total: number }>();
  for (const r of rows) {
    const b = base.get(r.point) ?? { month: 0, total: 0 };
    b.month += r.month; b.total += r.total; base.set(r.point, b);
  }
  const suggested = (r: StatRow) => {
    const b = base.get(r.point)!;
    const v = b.month ? (r.month * 100) / b.month : b.total ? (r.total * 100) / b.total : 0;
    return Math.round(v * 10) / 10;
  };
  let created = 0, updated = 0;
  const seen = new Set<number>();
  const toCreate: Record<string, unknown>[] = [];
  for (const r of rows) {
    if (!(r.partner in parentOf)) continue; // branch deleted in Odoo
    const vals = {
      x_point_id: r.point, x_partner_id: r.partner, x_client_id: parentOf[r.partner] || false,
      x_active: r.active, x_today: r.today, x_month: r.month, x_total: r.total, x_last: odooTime(r.last),
      x_suggested: suggested(r),
    };
    const h = byKey.get(`${r.point}|${r.partner}`);
    if (!h) { toCreate.push(vals); continue; }
    seen.add(h.id);
    const same = h.x_active === r.active && h.x_today === r.today && h.x_month === r.month && h.x_total === r.total &&
      (h.x_last || false) === vals.x_last && m2o(h.x_client_id) === (vals.x_client_id || null) && h.x_suggested === vals.x_suggested;
    if (!same) {
      await o.call('x_valet_point_stat', 'write', { ids: [h.id], vals });
      updated++;
    }
  }
  if (toCreate.length) {
    await o.call('x_valet_point_stat', 'create', { vals_list: toCreate });
    created = toCreate.length;
  }
  const stale = have.filter((h) => !seen.has(h.id)).map((h) => h.id);
  // rows just created are not in `have`, so only old ids can be stale
  if (stale.length) await o.call('x_valet_point_stat', 'unlink', { ids: stale });

  // totals on the points
  const tot = new Map<number, { active: number; today: number; month: number; total: number }>();
  for (const r of rows) {
    const t = tot.get(r.point) ?? { active: 0, today: 0, month: 0, total: 0 };
    t.active += r.active; t.today += r.today; t.month += r.month; t.total += r.total;
    tot.set(r.point, t);
  }
  const pts: any[] = await o.call('x_valet_point', 'search_read', {
    domain: [], fields: ['id', 'x_tickets_active', 'x_tickets_today', 'x_tickets_month', 'x_tickets_total'], limit: 5000,
  });
  for (const p of pts) {
    const t = tot.get(p.id) ?? { active: 0, today: 0, month: 0, total: 0 };
    if (p.x_tickets_active !== t.active || p.x_tickets_today !== t.today || p.x_tickets_month !== t.month || p.x_tickets_total !== t.total) {
      await o.call('x_valet_point', 'write', {
        ids: [p.id], vals: { x_tickets_active: t.active, x_tickets_today: t.today, x_tickets_month: t.month, x_tickets_total: t.total },
      });
    }
  }
  return { created, updated, removed: stale.length };
}


// ============================================================ 281: areas (Valet > Areas) + deletions
const AREA_PARAM = 'vip_valet.areas_version';
const AREA_VERSION = '1';
let areaFieldReady = false;

/** Valet > Areas in Odoo (x_valet_area) and the Area field on every point. Idempotent, versioned. */
export async function ensureAreas(o: Odoo): Promise<void> {
  const p = await o.one('ir.config_parameter', [['key', '=', AREA_PARAM]], ['value']);
  if (p && p.value === AREA_VERSION) { areaFieldReady = true; return; }
  const notes: string[] = [];
  const area = await o.one('ir.model', [['model', '=', 'x_valet_area']], ['id']);
  const areaId: number = area ? area.id : await o.create('ir.model', { name: 'Valet Area', model: 'x_valet_area', state: 'manual' });
  await ensureField(o, 'x_valet_area', areaId, { name: 'x_code', field_description: 'Code', ttype: 'char', copied: false });
  await ensureField(o, 'x_valet_area', areaId, { name: 'x_closed', field_description: 'Closed', ttype: 'boolean' });
  const point = await o.one('ir.model', [['model', '=', 'x_valet_point']], ['id']);
  if (!point) throw new OdooError('x_valet_point model not found');
  await ensureField(o, 'x_valet_point', point.id, { name: 'x_area_id', field_description: 'Area', ttype: 'many2one', relation: 'x_valet_area', on_delete: 'set null', index: true });
  await ensureField(o, 'x_valet_area', areaId, { name: 'x_point_ids', field_description: 'Points', ttype: 'one2many', relation: 'x_valet_point', relation_field: 'x_area_id' });
  const groupUser = await xmlid(o, 'base', 'group_user');
  await ensureAccess(o, areaId, 'Valet Area: internal users', groupUser, notes);

  await ensureView(o, 'vip_valet.area_list', {
    model: 'x_valet_area', type: 'list',
    arch_db: `<list><field name="x_code"/><field name="x_name"/><field name="x_point_ids" widget="many2many_tags" string="Points"/><field name="x_closed" optional="hide"/></list>`,
  });
  await ensureView(o, 'vip_valet.area_form', {
    model: 'x_valet_area', type: 'form',
    arch_db: `<form><sheet>
      <div class="oe_title"><h1><field name="x_name" placeholder="Area name, e.g. Dubai Hills"/></h1></div>
      <group><group><field name="x_code"/></group><group><field name="x_closed"/></group></group>
      <notebook><page string="Points in this area">
        <field name="x_point_ids"><list><field name="x_code"/><field name="x_name"/><field name="x_city"/><field name="x_closed" optional="hide"/></list></field>
      </page></notebook>
    </sheet></form>`,
  });
  const pointForm = await o.one('ir.ui.view', [['name', '=', 'vip_valet.point_form']], ['id']);
  if (pointForm) {
    await ensureView(o, 'vip_valet.point_form_area', {
      model: 'x_valet_point', type: 'form', inherit_id: pointForm.id, mode: 'extension', priority: 50,
      arch_db: `<xpath expr="//field[@name='x_code']" position="before"><field name="x_area_id"/></xpath>`,
    });
  }
  const pointList = await o.one('ir.ui.view', [['name', '=', 'vip_valet.point_list']], ['id']);
  if (pointList) {
    await ensureView(o, 'vip_valet.point_list_area', {
      model: 'x_valet_point', type: 'list', inherit_id: pointList.id, mode: 'extension', priority: 50,
      arch_db: `<xpath expr="//field[@name='x_name']" position="after"><field name="x_area_id"/></xpath>`,
    });
  }
  const pointSearch = await o.one('ir.ui.view', [['name', '=', 'vip_valet.point_search']], ['id']);
  if (pointSearch) {
    await ensureView(o, 'vip_valet.point_search_area', {
      model: 'x_valet_point', type: 'search', inherit_id: pointSearch.id, mode: 'extension', priority: 50,
      arch_db: `<xpath expr="//field[@name='x_code']" position="after"><field name="x_area_id"/>
        <filter name="by_area" string="Area" context="{'group_by': 'x_area_id'}"/></xpath>`,
    });
  }
  const aAreas = await ensureAction(o, 'Valet Areas', {
    res_model: 'x_valet_area', view_mode: 'list,form',
    help: '<p class="o_view_nocontent_smiling_face">Create the first area</p><p>Then choose the area on every point.</p>',
  });
  const root = await o.one('ir.ui.menu', [['name', '=', 'Valet'], ['parent_id', '=', false]], ['id']);
  if (root) await ensureMenu(o, 'Areas', root.id, `ir.actions.act_window,${aAreas}`, 5);

  if (p) await o.call('ir.config_parameter', 'write', { ids: [p.id], vals: { value: AREA_VERSION } });
  else await o.create('ir.config_parameter', { key: AREA_PARAM, value: AREA_VERSION });
  areaFieldReady = true;
}

export async function pullAreas(o: Odoo): Promise<any[]> {
  const rows: any[] = await o.call('x_valet_area', 'search_read', { domain: [], fields: ['id', 'x_name', 'x_code', 'x_closed', 'write_date'], limit: 2000 });
  return (rows ?? []).map((a) => ({ id: a.id, name: a.x_name, code: a.x_code || null, closed: !!a.x_closed, write_date: a.write_date ?? null }));
}

/** Ids the system knows that no longer exist in Odoo (archived ones still exist). Empty on any doubt. */
export async function goneIds(o: Odoo, known: { points: number[]; partners: number[]; areas: number[] }) {
  const ctx = { active_test: false };
  const check = async (model: string, ids: number[]) => {
    if (!ids.length) return [];
    const have = new Set<number>();
    for (let i = 0; i < ids.length; i += 500) {
      const part = ids.slice(i, i + 500);
      const found: number[] = await o.call(model, 'search', { domain: [['id', 'in', part]], context: ctx });
      for (const id of found ?? []) have.add(id);
    }
    const gone = ids.filter((id) => !have.has(id));
    // safety: never treat more than a quarter of the records as deleted in one run
    return gone.length > Math.max(3, ids.length / 4) ? [] : gone;
  };
  return {
    points: await check('x_valet_point', known.points ?? []),
    partners: await check('res.partner', known.partners ?? []),
    areas: await check('x_valet_area', known.areas ?? []),
  };
}
