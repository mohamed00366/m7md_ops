// builds the Odoo invoices live workbook: 1 Power Query (paged link) + filtered sheets + summary
const fs = require('fs');
const JSZip = require('jszip');
const { DOMParser, XMLSerializer } = require('@xmldom/xmldom');
global.DOMParser = DOMParser; global.XMLSerializer = XMLSerializer;
const { generateSingleQueryWorkbook } = require('@microsoft/connected-workbooks').workbookManager;

const TOKEN = process.argv[2] || 'XLTOKEN_PLACEHOLDER_0000000000000000';
const REFRESH = Number(process.argv[3] || 5);
const OUT = process.argv[4] || 'out.xlsx';
const KEY = 'sb_publishable_mpGl1t33_k36OPXVYeflHA_HVTonx_V';
const MODE = process.env.MODE || 'detail';   // detail | totals
const TOT = MODE === 'totals';
const COLS = TOT ? ['Date','Type','Journal','Status','Payment method','Valet','Point','Area','Client','Invoices','Untaxed','VAT','Total','Amount due'] : ['Invoice','Type','Journal','Status','Invoice date','Due date','Customer','Reference','Untaxed','VAT','Total','Amount due','Payment status','Payment method','Paid via','Paid on','Valet','Ticket','Point','Area','Client','Currency','Created','Updated','Odoo ID'];
const TYPES = TOT ? {'Date':'type date','Invoices':'Int64.Type','Untaxed':'type number','VAT':'type number','Total':'type number','Amount due':'type number'} : {'Invoice date':'type date','Due date':'type date','Paid on':'type date','Untaxed':'type number','VAT':'type number','Total':'type number','Amount due':'type number','Created':'type datetime','Updated':'type datetime','Odoo ID':'Int64.Type'};

const mashup = `let
    Base = "https://weftpekmmesgfhdawutj.supabase.co/rest/v1/rpc/",
    Key = "${KEY}",
    Token = "${TOKEN}",
    Get = (fn as text, extra as record) => Json.Document(Web.Contents(Base, [RelativePath = fn, Query = Record.Combine({[apikey = Key, p_token = Token], extra}), Headers = [Accept = "application/json"], Timeout = #duration(0, 0, 2, 0)])),
${TOT ? `    Info = Get("vx_odoo_totals_info", []),
    Rows = List.Combine(List.Transform(Info[months], each Get("vx_odoo_totals_month", [p_month = _]))),` : `    From = "XLFROM_PLACEHOLDER",
    To = "XLTO_PLACEHOLDER",
    Period = Record.Combine({if From = "" then [] else [p_from = From], if To = "" then [] else [p_to = To]}),
    Info = Get("vx_odoo_invoices_info", Period),
    Pages = List.Numbers(0, Number.RoundUp(Info[count] / Info[page_size])),
    Rows = List.Combine(List.Transform(Pages, each Get("vx_odoo_invoices_page", Record.Combine({[p_page = Text.From(_)], Period})))),`}
    Columns = {${COLS.map(c => `"${c}"`).join(', ')}},
    Table = Table.FromRecords(Rows, Columns, MissingField.UseNull),
    Typed = Table.TransformColumnTypes(Table, {${Object.entries(TYPES).map(([c, t]) => `{"${c}", ${t}}`).join(', ')}}, "en-US")
in
    Typed`;

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const colLetter = (n) => { let s = ''; n++; while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); } return s; };

function sheetXml(rows, opts = {}) {
  // rows: array of arrays of cells {v} | {f, dyn} | string | number
  let out = '';
  rows.forEach((r, i) => {
    if (!r) return;
    out += `<row r="${i + 1}">`;
    r.forEach((c, j) => {
      if (c === null || c === undefined) return;
      const ref = colLetter(j) + (i + 1);
      if (typeof c === 'number') out += `<c r="${ref}"><v>${c}</v></c>`;
      else if (typeof c === 'string') out += `<c r="${ref}" t="inlineStr"${opts.bold && i === 0 ? ' s="0"' : ''}><is><t xml:space="preserve">${esc(c)}</t></is></c>`;
      else if (c.f && c.dyn) out += `<c r="${ref}" cm="1"${c.s ? ` s="${c.s}"` : ''}><f t="array" ref="${ref}">${esc(c.f)}</f></c>`;
      else if (c.f) out += `<c r="${ref}"${c.s ? ` s="${c.s}"` : ''}><f>${esc(c.f)}</f></c>`;
      else if (c.t) out += `<c r="${ref}" t="inlineStr"${c.s ? ` s="${c.s}"` : ''}><is><t xml:space="preserve">${esc(c.t)}</t></is></c>`;
    });
    out += '</row>';
  });
  const cols = opts.widths ? `<cols>${opts.widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')}</cols>` : '';
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0"${opts.rtl ? ' rightToLeft="1"' : ''}><pane ySplit="${opts.freeze || 1}" topLeftCell="A${(opts.freeze || 1) + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>${cols}<sheetData>${out}</sheetData></worksheet>`;
}

(async () => {
  const seed = process.env.SEED ? JSON.parse(fs.readFileSync(process.env.SEED, 'utf8')) : [];
  for (const r of seed) for (const c of ['Invoice date', 'Due date', 'Paid on', 'Date']) if (r[c]) r[c] = Math.round((Date.parse(r[c] + 'T00:00:00Z') - Date.UTC(1899, 11, 30)) / 86400000);
  const grid = { data: [COLS, ...(seed.length ? seed.map((r) => COLS.map((c) => (r[c] === null || r[c] === undefined ? '' : r[c]))) : [COLS.map(() => '')])], config: { promoteHeaders: true, adjustColumnNames: false } };
  const blob = await generateSingleQueryWorkbook({ queryMashup: mashup, refreshOnOpen: true, queryName: TOT ? 'Totals' : 'Invoices' }, grid, {
    docProps: { title: TOT ? 'Odoo invoice totals – live' : 'Odoo invoices – live', createdBy: 'VIP Valet', description: 'Live copy of the Odoo customer invoices (refreshes itself)' },
    templateSettings: { sheetName: 'Sheet1' },
  });
  const buf = Buffer.from(await blob.arrayBuffer());
  const zip = await JSZip.loadAsync(buf);
  const names = Object.keys(zip.files);
  // ---- the query table sheet: rename to "All invoices", table to "Invoices"
  let wb = await zip.file('xl/workbook.xml').async('string');
  wb = wb.replace(/<sheet name="Sheet1"/, `<sheet name="${TOT ? 'Totals' : 'All invoices'}"`).replace(/>Sheet1!/g, TOT ? '>Totals!' : ">'All invoices'!");
  let app = await zip.file('docProps/app.xml').async('string');
  zip.file('docProps/app.xml', app.replace('>Sheet1<', TOT ? '>Totals<' : '>All invoices<'));
  const tableFile = names.find((n) => /^xl\/tables\/table\d+\.xml$/.test(n));
  let table = await zip.file(tableFile).async('string');
  // ---- refresh every N minutes (connection) + on open
  let conn = await zip.file('xl/connections.xml').async('string');
  conn = conn.replace(/<connection ([^>]*?)>/, (m, a) => `<connection ${a.replace(/ interval="\d+"/, '')}${REFRESH > 0 ? ` interval="${REFRESH}"` : ''}>`);
  if (!/refreshOnLoad="1"/.test(conn)) conn = conn.replace('<connection ', '<connection refreshOnLoad="1" ');
  zip.file('xl/connections.xml', conn);

  // ---- styles: add a bold font + a number format + a date format
  let styles = await zip.file('xl/styles.xml').async('string');
  const fontCount = Number((styles.match(/<fonts count="(\d+)"/) || [0, 1])[1]);
  styles = styles.replace(/<fonts count="(\d+)"([^>]*)>([\s\S]*?)<\/fonts>/, (m, c, a, inner) => `<fonts count="${+c + 2}"${a}>${inner}<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="15"/><name val="Calibri"/><family val="2"/></font></fonts>`);
  if (!/<numFmts/.test(styles)) styles = styles.replace('<fonts', '<numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.00"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd"/></numFmts><fonts');
  const xfCount = Number(styles.match(/<cellXfs count="(\d+)"/)[1]);
  styles = styles.replace(/<cellXfs count="(\d+)"([^>]*)>([\s\S]*?)<\/cellXfs>/, (m, c, a, inner) =>
    `<cellXfs count="${+c + 4}"${a}>${inner}` +
    `<xf numFmtId="0" fontId="${fontCount}" fillId="0" borderId="0" xfId="0" applyFont="1"/>` +       // bold
    `<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>` +         // money
    `<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>` +         // date
    `<xf numFmtId="0" fontId="${fontCount + 1}" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>`); // title
  zip.file('xl/styles.xml', styles);
  const S = { bold: xfCount, money: xfCount + 1, date: xfCount + 2, title: xfCount + 3 };

  // ---- the data sheet: numbers as numbers (not t="1"), dates with a date format
  const sheetFile = 'xl/worksheets/sheet1.xml';
  let sh = await zip.file(sheetFile).async('string');
  const dateCols = ['Invoice date', 'Due date', 'Paid on', 'Date'].filter((c) => COLS.includes(c)).map((c) => colLetter(COLS.indexOf(c)));
  const moneyCols = ['Untaxed', 'VAT', 'Total', 'Amount due'].map((c) => colLetter(COLS.indexOf(c)));
  sh = sh.replace(/<c r="([A-Z]+)(\d+)" t="1">/g, (m, col, row) => (row === '1' ? m : `<c r="${col}${row}"${dateCols.includes(col) ? ` s="${S.date}"` : moneyCols.includes(col) ? ` s="${S.money}"` : ''}>`));
  zip.file(sheetFile, sh);

  // ---- extra sheets
  const T = TOT ? 'Totals' : 'Invoices';
  const DT = TOT ? 'Date' : 'Invoice date';
  const filt = (cond, label) => [
    [{ f: `_xlfn._xlws.FILTER(${T}[#Headers],TRUE)`, dyn: true, s: S.bold }],
    [{ f: `_xlfn._xlws.FILTER(${T},${cond},"No ${label} invoices yet")`, dyn: true }],
  ];
  const sheets = TOT ? [] : [
    ['Cash', filt(`${T}[Payment method]="Cash"`, 'cash')],
    ['Card', filt(`${T}[Payment method]="Card"`, 'card')],
    ['Free', filt(`${T}[Payment method]="Free"`, 'free')],
    ['Unpaid', filt(`(${T}[Payment method]="Unpaid")+(${T}[Payment method]="Draft")`, 'unpaid')],
    ['Credit notes', filt(`${T}[Type]="Credit note"`, 'credit note')],
    ['Other invoices', filt(`${T}[Valet]="No"`, 'non-valet')],
  ];
  // summary: by month and by day (last 31 days), posted only
  const methods = ['Cash', 'Card', 'Free', 'Split', 'Bank / other', 'Unpaid'];
  const sum = (dateCond, m) => `SUMIFS(${T}[Total],${T}[Status],"Posted",${T}[Payment method],"${m}",${dateCond})`;
  const cnt = (dateCond) => (TOT ? `SUMIFS(${T}[Invoices],${T}[Status],"Posted",${dateCond})` : `COUNTIFS(${T}[Status],"Posted",${dateCond})`);
  const summary = [];
  summary.push([{ t: 'Odoo invoices – summary (posted invoices, AED, credit notes are negative)', s: S.title }]);
  summary.push([{ t: 'Last refresh of this file:' }, { f: 'NOW()', s: S.date }]);
  summary.push(null);
  summary.push([{ t: 'Month', s: S.bold }, ...methods.map((m) => ({ t: m, s: S.bold })), { t: 'Total', s: S.bold }, { t: 'Invoices', s: S.bold }]);
  const mStart = summary.length;
  for (let i = 0; i < 24; i++) {
    const r = summary.length + 1;
    const d = `DATE(YEAR(TODAY()),MONTH(TODAY())-${i},1)`;
    const cond = `${T}[${DT}],">="&A${r},${T}[${DT}],"<"&EDATE(A${r},1)`;
    summary.push([{ f: d, s: S.date }, ...methods.map((m) => ({ f: sum(cond, m), s: S.money })), { f: `SUMIFS(${T}[Total],${T}[Status],"Posted",${cond})`, s: S.money }, { f: cnt(cond) }]);
  }
  summary.push(null);
  summary.push([{ t: 'Day', s: S.bold }, ...methods.map((m) => ({ t: m, s: S.bold })), { t: 'Total', s: S.bold }, { t: 'Invoices', s: S.bold }]);
  for (let i = 0; i < 31; i++) {
    const r = summary.length + 1;
    const cond = `${T}[${DT}],A${r}`;
    summary.push([{ f: `TODAY()-${i}`, s: S.date }, ...methods.map((m) => ({ f: sum(cond, m), s: S.money })), { f: `SUMIFS(${T}[Total],${T}[Status],"Posted",${cond})`, s: S.money }, { f: cnt(cond) }]);
  }
  void mStart;
  const about = [
    [{ t: 'Odoo invoices – live file', s: S.title }],
    null,
    [{ t: 'What it is' }, { t: 'A live copy of every customer invoice and credit note in Odoo (all journals). Read only: nothing in Odoo is changed from here.' }],
    [{ t: 'Updates' }, { t: `Refreshes when the file opens${REFRESH > 0 ? ` and every ${REFRESH} min while it is open` : ''}. Data → Refresh All to refresh now. Odoo → the system: about every minute.` }],
    [{ t: 'First time' }, { t: 'If Excel asks: "Enable content" / "Enable editing", and for the web link choose Anonymous → Connect.' }],
    [{ t: 'Sheets' }, { t: 'All invoices (the data) · Cash · Card · Free · Unpaid · Credit notes · Other invoices (not valet) · Summary (per month and per day).' }],
    [{ t: 'Payment method' }, { t: 'From the journal the payment was registered in (Cash / Card / Bank), Free = 0 AED, Split = more than one, Unpaid / Draft / Cancelled.' }],
    [{ t: 'Valet columns' }, { t: 'Ticket, point, area and client come from the valet system (valet invoices only).' }],
    [{ t: 'Link' }, { t: 'Private. If the link is renewed in the dashboard, this file stops and a new one must be downloaded.' }],
    null,
    [{ t: 'Millions of rows', s: S.bold }, { t: 'A sheet holds about 1 million rows. To keep every invoice anyway, load the query into the Data Model (once):' }],
    [{ t: '' }, { t: `1. Data → Queries & Connections → right click "${TOT ? 'Totals' : 'Invoices'}" → Load To…` }],
    [{ t: '' }, { t: '2. Choose "PivotTable Report" (or "Only Create Connection") and tick "Add this data to the Data Model" → OK (Excel asks to delete the sheet table: yes).' }],
    [{ t: '' }, { t: '3. The PivotTable reads the Data Model (millions of rows) and refreshes with the query. The filtered sheets and the Summary need the sheet table, so use the PivotTable instead.' }],
    [{ t: '' }, { t: 'Or download the "Totals" file (one row per day / point / payment method) or a "Period" file from the dashboard – they stay small.' }],
  ];
  if (TOT) {
    about[2] = [{ t: 'What it is' }, { t: 'Totals of the Odoo customer invoices: one row per day × type × journal × status × payment method × point × area × client, with the number of invoices and the amounts. Read only.' }];
    about[5] = [{ t: 'Sheets' }, { t: 'Totals (the data) · Summary (per month and per day) · use PivotTables on the Totals table for any other view.' }];
  }
  const all = [...sheets, ['Summary', summary], ['About', about]];
  let rels = await zip.file('xl/_rels/workbook.xml.rels').async('string');
  let ct = await zip.file('[Content_Types].xml').async('string');
  let maxSheetId = Math.max(...[...wb.matchAll(/sheetId="(\d+)"/g)].map((m) => +m[1]));
  let rid = 100;
  let sheetTags = '';
  all.forEach(([name, rows], i) => {
    const file = `xl/worksheets/sheet_x${i + 1}.xml`;
    const widths = name === 'Summary' ? [14, 14, 14, 14, 14, 14, 14, 16, 10] : name === 'About' ? [18, 120] : COLS.map((c) => (c === 'Customer' || c === 'Point' ? 28 : c === 'Invoice' || c === 'Reference' || c === 'Paid via' ? 20 : 14));
    zip.file(file, sheetXml(rows, { widths, freeze: name === 'Summary' ? 4 : 1 }));
    rels = rels.replace('</Relationships>', `<Relationship Id="rId${rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet_x${i + 1}.xml"/></Relationships>`);
    ct = ct.replace('</Types>', `<Override PartName="/${file}" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`);
    sheetTags += `<sheet name="${esc(name)}" sheetId="${++maxSheetId}" r:id="rId${rid}"/>`;
    rid++;
  });
  wb = wb.replace('</sheets>', sheetTags + '</sheets>');
  // dynamic arrays metadata
  zip.file('xl/metadata.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:xda="http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray"><metadataTypes count="1"><metadataType name="XLDAPR" minSupportedVersion="120000" copy="1" pasteAll="1" pasteValues="1" merge="1" splitFirst="1" rowColShift="1" clearFormats="1" clearComments="1" assign="1" coerce="1" cellMeta="1"/></metadataTypes><futureMetadata name="XLDAPR" count="1"><bk><extLst><ext uri="{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}"><xda:dynamicArrayProperties fDynamic="1" fCollapsed="0"/></ext></extLst></bk></futureMetadata><cellMetadata count="1"><bk><rc t="1" v="0"/></bk></cellMetadata></metadata>`);
  rels = rels.replace('</Relationships>', `<Relationship Id="rId${rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata" Target="metadata.xml"/></Relationships>`);
  ct = ct.replace('</Types>', `<Override PartName="/xl/metadata.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheetMetadata+xml"/></Types>`);
  // recalc on open (formulas)
  if (/<calcPr[^>]*\/>/.test(wb)) wb = wb.replace(/<calcPr([^>]*)\/>/, (m, a) => `<calcPr${a.replace(/ fullCalcOnLoad="\d"/, '')} fullCalcOnLoad="1"/>`);
  else wb = wb.replace('</workbook>', '<calcPr fullCalcOnLoad="1"/></workbook>');
  zip.file('xl/workbook.xml', wb);
  zip.file('xl/_rels/workbook.xml.rels', rels);
  zip.file('[Content_Types].xml', ct);
  // table name
  table = table.replace(/ name="[^"]*"/, ` name="${T}"`).replace(/ displayName="[^"]*"/, ` displayName="${T}"`);
  zip.file(tableFile, table);
  fs.writeFileSync(OUT, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  fs.writeFileSync(OUT + '.m', mashup);
  console.log('ok', OUT, names.filter((n) => /xl\//.test(n)).join(' '));
})().catch((e) => { console.error(e); process.exit(1); });
