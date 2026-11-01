import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/sheet_name_utils.dart';

void main() {
  test('keeps a short first word as is', () {
    expect(sheetShortName('plan 10 aswak.xlsx'), 'plan');
  });

  test('cuts a long first word to 6 characters', () {
    expect(sheetShortName('Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx'), 'Adco');
    expect(sheetShortName('SellInPlan2026.xlsx'), 'SellIn…');
  });

  test('handles Arabic names', () {
    expect(sheetShortName('توريدات_يناير.xlsx'), 'توريدا…');
  });
}
