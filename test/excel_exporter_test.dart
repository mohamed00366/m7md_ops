import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m7md_ops/core/services/excel_exporter.dart';

void main() {
  test('first sheet keeps its headers and rows after the rename', () async {
    final ok = await ExcelExporter.export(fileName: 'x.xlsx', sheets: const [
      ExcelSheet(name: 'Cards', headers: ['#', 'Card number'], rows: [
        [1, 'VIP-000001'],
        [2, 'VIP-000002'],
      ]),
      ExcelSheet(name: 'Second', headers: ['A'], rows: [
        ['x'],
      ]),
    ]);
    expect(ok, isTrue);
    final x = Excel.decodeBytes(ExcelExporter.lastBytes!);
    final s = x.tables['Cards']!;
    expect(s.maxRows, 3);
    expect(s.cell(CellIndex.indexByString('B1')).value.toString(), 'Card number');
    expect(s.cell(CellIndex.indexByString('B3')).value.toString(), 'VIP-000002');
    expect(x.tables['Second']!.maxRows, 2);
  });
}
