import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/shared_display_prefix.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/cascading_filter_toolbar.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart';

/// Fictional dataset prefix only — never a real customer name.
const kFixturePrefix = 'سلسلة تجريبية XYZ - ';
const kStoreAlpha = 'سلسلة تجريبية XYZ - مخزن ألفا';
const kStoreBeta = 'سلسلة تجريبية XYZ - فرع بيتا';

SellOutRecordModel _record({
  required String id,
  required String storeId,
  required String storeName,
}) {
  return SellOutRecordModel(
    recordId: id,
    retailerChain: 'fathalla',
    storeId: storeId,
    storeName: storeName,
    barcode: '6221001$id',
    skuName: 'صنف تجريبي $id',
    category: 'زيوت',
    quantitySold: 10,
    unitPrice: 5,
    netRevenue: 50,
    transactionDate: '2026-10-12',
  );
}

void main() {
  test('fixture prefix strips to the remainder', () {
    expect(stripSharedLeadingPrefix([kStoreAlpha, kStoreBeta]), [
      'مخزن ألفا',
      'فرع بيتا',
    ]);
  });

  testWidgets(
      'Sell-Out store dropdown shows stripped labels and keeps original values',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selectedId;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CascadingFilterToolbar(
              selectedChain: 'gomla',
              selectedStoreId: null,
              selectedCategory: null,
              searchQuery: '',
              chainStoresOverride: const {
                'gomla': [
                  {'id': 'store_alpha', 'name': kStoreAlpha},
                  {'id': 'store_beta', 'name': kStoreBeta},
                ],
              },
              onChainChanged: (_) {},
              onStoreChanged: (id) => selectedId = id,
              onCategoryChanged: (_) {},
              onSearchChanged: (_) {},
              onExportExcel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<M3Dropdown<String?>>(
      find.byKey(const ValueKey('sellout_store_dropdown')),
    );
    expect(
      dropdown.options.map((o) => o.label).toList(),
      containsAll(['مخزن ألفا', 'فرع بيتا']),
    );
    expect(
      dropdown.options.map((o) => o.value).toList(),
      containsAll(['store_alpha', 'store_beta']),
    );
    expect(
      dropdown.options.any((o) => o.label.contains(kFixturePrefix)),
      isFalse,
    );
    expect(find.text(kStoreAlpha), findsNothing);
    expect(find.text(kStoreBeta), findsNothing);

    // Selecting the stripped label still reports the original store id.
    dropdown.onChanged?.call('store_alpha');
    expect(selectedId, 'store_alpha');
  });

  testWidgets('Sell-Out SKU table shows stripped store names only',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VirtualizedSkuTable(
              records: [
                _record(id: '001', storeId: 'a', storeName: kStoreAlpha),
                _record(id: '002', storeId: 'b', storeName: kStoreBeta),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مخزن ألفا'), findsWidgets);
    expect(find.text('فرع بيتا'), findsWidgets);
    expect(find.text(kStoreAlpha), findsNothing);
    expect(find.text(kStoreBeta), findsNothing);
    expect(find.textContaining(kFixturePrefix), findsNothing);
  });
}
