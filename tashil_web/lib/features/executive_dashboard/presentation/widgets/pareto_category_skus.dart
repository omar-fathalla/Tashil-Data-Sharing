import 'package:tashil_web/core/network/api_client.dart';

/// Identity used by the category card's product count: the barcode, or the
/// SKU name when the barcode is empty.
String categorySkuIdentity(ParetoSkuItemModel sku) {
  final barcode = sku.barcode.trim();
  if (barcode.isNotEmpty) return barcode;
  return sku.skuName.trim();
}

/// Every own-brand SKU in [category], one row per distinct barcode.
///
/// Sorted by sales descending. [ParetoSkuItemModel.revenueSharePct] and
/// [ParetoSkuItemModel.cumulativeSharePct] are the SKU's share of this
/// category (rounded to 0.1 and summing to 100). [ParetoSkuItemModel.isTop80Contributor]
/// is an A/B/C badge only — rows past 80% stay in the list.
List<ParetoSkuItemModel> skusForCategory({
  required List<ParetoSkuItemModel> paretoSkus,
  required String category,
}) {
  final selected = category.trim().toLowerCase();
  if (selected.isEmpty) return const [];

  final buckets = <String, _SkuBucket>{};
  for (final sku in paretoSkus) {
    if (sku.category.trim().toLowerCase() != selected) continue;
    final id = categorySkuIdentity(sku);
    if (id.isEmpty) continue;
    final name = sku.skuName.trim();
    final bucket = buckets.putIfAbsent(id, () => _SkuBucket(sku));
    bucket.revenue += sku.totalRevenue;
    bucket.units += sku.totalUnits;
    if (name.isNotEmpty) {
      bucket.nameRevenue[name] =
          (bucket.nameRevenue[name] ?? 0) + sku.totalRevenue;
    }
    if (sku.totalRevenue > bucket.displayRevenue) {
      bucket.display = sku;
      bucket.displayRevenue = sku.totalRevenue;
    }
  }

  final merged = buckets.values.toList()
    ..sort((a, b) {
      final byRevenue = b.revenue.compareTo(a.revenue);
      if (byRevenue != 0) return byRevenue;
      return categorySkuIdentity(
        a.display,
      ).compareTo(categorySkuIdentity(b.display));
    });

  if (merged.isEmpty) return const [];

  final total = merged.fold<double>(0, (sum, b) => sum + b.revenue);
  final tenths = List<int>.filled(merged.length, 0);
  if (total > 0) {
    final remainders = <double>[];
    var allocated = 0;
    for (var i = 0; i < merged.length; i++) {
      final exact = merged[i].revenue / total * 1000.0;
      final base = exact.floor();
      tenths[i] = base;
      remainders.add(exact - base);
      allocated += base;
    }
    var left = 1000 - allocated;
    final order = List<int>.generate(merged.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        if (byRemainder != 0) return byRemainder;
        return a.compareTo(b);
      });
    for (var k = 0; k < left && k < order.length; k++) {
      tenths[order[k]] += 1;
    }
  }

  var rawCum = 0.0;
  var runningTenths = 0;
  final out = <ParetoSkuItemModel>[];
  for (var i = 0; i < merged.length; i++) {
    final bucket = merged[i];
    final src = bucket.display;
    final rawShare = total > 0 ? bucket.revenue / total * 100.0 : 0.0;
    final prevRaw = rawCum;
    rawCum += rawShare;
    runningTenths += tenths[i];
    final share = tenths[i] / 10.0;
    final cum = i == merged.length - 1 && total > 0
        ? 100.0
        : runningTenths / 10.0;
    final bestName = _bestName(bucket.nameRevenue, src.skuName.trim());
    out.add(
      ParetoSkuItemModel(
        itemCode: src.itemCode,
        barcode: src.barcode.trim(),
        skuName: bestName.isNotEmpty ? bestName : src.skuName,
        category: src.category,
        unitsPerCarton: src.unitsPerCarton,
        itemType: src.itemType,
        factoryUnitCost: src.factoryUnitCost,
        totalRevenue: bucket.revenue,
        totalUnits: bucket.units,
        unitPrice: bucket.units > 0
            ? bucket.revenue / bucket.units
            : src.unitPrice,
        revenueSharePct: share,
        cumulativeSharePct: cum,
        isTop80Contributor: i == 0 || prevRaw < 80.0,
      ),
    );
  }
  return out;
}

String _bestName(Map<String, double> nameRevenue, String fallback) {
  var best = '';
  var bestRev = -1.0;
  nameRevenue.forEach((name, rev) {
    if (rev > bestRev ||
        (rev == bestRev && (best.isEmpty || name.compareTo(best) < 0))) {
      best = name;
      bestRev = rev;
    }
  });
  return best.isNotEmpty ? best : fallback;
}

class _SkuBucket {
  _SkuBucket(ParetoSkuItemModel sku)
    : display = sku,
      displayRevenue = sku.totalRevenue;

  ParetoSkuItemModel display;
  double displayRevenue;
  double revenue = 0;
  int units = 0;
  final Map<String, double> nameRevenue = {};
}
