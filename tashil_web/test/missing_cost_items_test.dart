import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';

void main() {
  test('MissingCostItemModel parses backend payload', () {
    final m = MissingCostItemModel.fromJson({
      'item_code': 'A1',
      'barcode': '111',
      'sku_name': 'صنف',
      'chains': ['fathalla', 'kazyon'],
      'units_sold': 6,
      'sales_value_egp': 60.5,
      'reason': 'not_in_master',
      'reason_ar': 'غير موجود في كارتة الأصناف',
    });
    expect(m.chains.length, 2);
    expect(m.unitsSold, 6);
    expect(m.salesValueEgp, 60.5);
    expect(m.reason, 'not_in_master');
  });

  test('missing_cost_items defaults to empty list', () {
    expect(const MissingCostItemModel().chains, isEmpty);
  });
}
