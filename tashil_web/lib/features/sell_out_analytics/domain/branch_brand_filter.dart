import '../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../core/network/api_client.dart';

/// Folds Arabic letter variants so "فلفيتا" and "فلڤيتا" compare equal.
String normalizeBrandKey(String s) {
  var out = s.trim().toLowerCase();
  out = out.replaceAll('ڤ', 'ف').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  return out;
}

/// Splits "عربي (English)" into Arabic / English / full normalized keys.
({String ar, String en, String full}) brandLabelParts(String label) {
  final full = normalizeBrandKey(label);
  if (full.isEmpty) {
    return (ar: '', en: '', full: '');
  }
  final open = label.lastIndexOf('(');
  final close = label.lastIndexOf(')');
  if (open >= 0 && close > open) {
    return (
      ar: normalizeBrandKey(label.substring(0, open)),
      en: normalizeBrandKey(label.substring(open + 1, close)),
      full: full,
    );
  }
  return (ar: full, en: '', full: full);
}

/// Whether an inferred catalog brand matches a UI brand filter value.
/// Accepts full labels, Arabic-only, or English-only ("Diva" / "Velveta").
bool brandLabelMatches(String inferred, String filter) {
  final f = filter.trim();
  if (f.isEmpty || f == 'all' || f == 'الكل' || f == 'كل العلامات التجارية') {
    return true;
  }
  final a = brandLabelParts(inferred);
  final b = brandLabelParts(f);
  if (a.full.isEmpty || b.full.isEmpty) return false;
  if (a.full == b.full) return true;
  final aParts = <String>{a.full, if (a.ar.isNotEmpty) a.ar, if (a.en.isNotEmpty) a.en};
  final bParts = <String>{b.full, if (b.ar.isNotEmpty) b.ar, if (b.en.isNotEmpty) b.en};
  return aParts.intersection(bParts).isNotEmpty;
}

/// Infers the catalog brand for a sell-out record (SKU name + category + item code).
String inferSellOutBrand(SellOutRecordModel r) {
  return SmartBrandExtractor.inferBrand(
    r.skuName,
    subCategory: r.category,
    itemCode: r.itemCode,
  );
}

/// Filters sell-out records to those matching [brandFilter] (or all when empty/'all').
List<SellOutRecordModel> filterRecordsByBrand(
  Iterable<SellOutRecordModel> records,
  String brandFilter,
) {
  final f = brandFilter.trim();
  if (f.isEmpty || f == 'all' || f == 'الكل' || f == 'كل العلامات التجارية') {
    return List<SellOutRecordModel>.from(records);
  }
  return records.where((r) => brandLabelMatches(inferSellOutBrand(r), f)).toList();
}

bool _isGenericBrandLabel(String brand) {
  final b = brand.trim();
  if (b.isEmpty) return true;
  final n = normalizeBrandKey(b);
  return n == 'اصناف عامه' ||
      n == 'عام' ||
      n == 'other' ||
      n == 'general' ||
      n == 'منتجات الشركه' ||
      n.contains('اصناف عامه');
}

/// Revenue that does not match any *catalog* brand in [knownBrands]
/// (excludes generic «أصناف عامة» labels). all-brand total = Σ brands + this remainder.
double unbrandedRevenueRemainder(
  Iterable<SellOutRecordModel> records,
  Iterable<String> knownBrands,
) {
  final brands = knownBrands
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty && b != 'all' && !_isGenericBrandLabel(b))
      .toList();
  if (brands.isEmpty) {
    return records.fold<double>(0.0, (s, r) => s + r.netRevenue);
  }
  var rem = 0.0;
  for (final r in records) {
    final inferred = inferSellOutBrand(r);
    if (_isGenericBrandLabel(inferred)) {
      rem += r.netRevenue;
      continue;
    }
    final matched = brands.any((b) => brandLabelMatches(inferred, b));
    if (!matched) rem += r.netRevenue;
  }
  return rem;
}

/// One SKU row used by branch-performance KPIs / export.
class PerfSkuAgg {
  final String skuName;
  final String itemCode;
  final String barcode;
  final String brand;
  final String category;
  final int units;
  final double revenue;

  const PerfSkuAgg({
    required this.skuName,
    required this.itemCode,
    required this.barcode,
    required this.brand,
    required this.category,
    required this.units,
    required this.revenue,
  });
}

/// Aggregates records into SKU rows sorted by revenue descending.
List<PerfSkuAgg> aggregatePerfSkus(Iterable<SellOutRecordModel> records) {
  final map = <String, PerfSkuAgg>{};
  for (final r in records) {
    final key = r.barcode.isNotEmpty ? r.barcode : r.skuName;
    final brand = inferSellOutBrand(r);
    final existing = map[key];
    if (existing == null) {
      map[key] = PerfSkuAgg(
        skuName: r.skuName,
        itemCode: r.itemCode,
        barcode: r.barcode,
        brand: brand,
        category: r.category,
        units: r.quantitySold,
        revenue: r.netRevenue,
      );
    } else {
      map[key] = PerfSkuAgg(
        skuName: existing.skuName,
        itemCode: existing.itemCode.isNotEmpty ? existing.itemCode : r.itemCode,
        barcode: existing.barcode.isNotEmpty ? existing.barcode : r.barcode,
        brand: existing.brand,
        category: existing.category,
        units: existing.units + r.quantitySold,
        revenue: existing.revenue + r.netRevenue,
      );
    }
  }
  final list = map.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
  return list;
}

/// Pareto share of the top 20% SKUs by revenue.
({int topCount, double sharePct}) paretoTop20Share(List<PerfSkuAgg> sortedByRev) {
  final total = sortedByRev.fold<double>(0.0, (s, i) => s + i.revenue);
  var topCount = (sortedByRev.length * 0.2).ceil();
  if (topCount < 1 && sortedByRev.isNotEmpty) topCount = 1;
  final topRev = sortedByRev.take(topCount).fold<double>(0.0, (s, i) => s + i.revenue);
  final pct = total > 0 ? (topRev / total) * 100 : 0.0;
  return (topCount: topCount, sharePct: pct);
}
