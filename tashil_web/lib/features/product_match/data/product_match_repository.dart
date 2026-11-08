import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';

/// Success / review KPIs for product↔Product Master matching.
class ProductMatchMetrics {
  final int totalMatched;
  final int exact;
  final int high;
  final int uncertain;
  final int none;
  final int autoResolved;
  final int queued;
  final int pending;
  final int approved;
  final int rejected;
  final double autoResolveRate;
  final double reviewRate;
  final double approvalRate;
  final int inventedBarcodes;
  final Map<String, String> labelsAr;

  const ProductMatchMetrics({
    this.totalMatched = 0,
    this.exact = 0,
    this.high = 0,
    this.uncertain = 0,
    this.none = 0,
    this.autoResolved = 0,
    this.queued = 0,
    this.pending = 0,
    this.approved = 0,
    this.rejected = 0,
    this.autoResolveRate = 0,
    this.reviewRate = 0,
    this.approvalRate = 0,
    this.inventedBarcodes = 0,
    this.labelsAr = const {},
  });

  factory ProductMatchMetrics.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ProductMatchMetrics();
    final labels = <String, String>{};
    final raw = j['labels_ar'];
    if (raw is Map) {
      raw.forEach((k, v) => labels['$k'] = '$v');
    }
    return ProductMatchMetrics(
      totalMatched: _i(j['total_matched']),
      exact: _i(j['exact']),
      high: _i(j['high']),
      uncertain: _i(j['uncertain']),
      none: _i(j['none']),
      autoResolved: _i(j['auto_resolved']),
      queued: _i(j['queued']),
      pending: _i(j['pending']),
      approved: _i(j['approved']),
      rejected: _i(j['rejected']),
      autoResolveRate: _d(j['auto_resolve_rate']),
      reviewRate: _d(j['review_rate']),
      approvalRate: _d(j['approval_rate']),
      inventedBarcodes: _i(j['invented_barcodes']),
      labelsAr: labels,
    );
  }
}

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

class ProductMatchCandidate {
  final String itemCode;
  final String barcode;
  final String officialName;
  final String brand;
  final double confidence;
  final String reasonAr;

  const ProductMatchCandidate({
    this.itemCode = '',
    this.barcode = '',
    this.officialName = '',
    this.brand = '',
    this.confidence = 0,
    this.reasonAr = '',
  });

  factory ProductMatchCandidate.fromJson(Map<String, dynamic> j) => ProductMatchCandidate(
        itemCode: '${j['item_code'] ?? ''}',
        barcode: '${j['barcode'] ?? ''}',
        officialName: '${j['official_name'] ?? ''}',
        brand: '${j['brand'] ?? ''}',
        confidence: _d(j['confidence']),
        reasonAr: '${j['reason_ar'] ?? ''}',
      );
}

class ProductMatchReviewItem {
  final String id;
  final String status;
  final String itemCode;
  final String barcode;
  final String skuName;
  final String sourceFile;
  final int rows;
  final double value;
  final String decision;
  final double confidence;
  final String reasonAr;
  final String matchedItemCode;
  final String matchedName;
  final String suggestedBarcode;
  final String barcodePolicy;
  final List<ProductMatchCandidate> candidates;
  final String chosenItemCode;
  final String chosenBarcode;

  const ProductMatchReviewItem({
    required this.id,
    this.status = 'pending',
    this.itemCode = '',
    this.barcode = '',
    this.skuName = '',
    this.sourceFile = '',
    this.rows = 0,
    this.value = 0,
    this.decision = '',
    this.confidence = 0,
    this.reasonAr = '',
    this.matchedItemCode = '',
    this.matchedName = '',
    this.suggestedBarcode = '',
    this.barcodePolicy = '',
    this.candidates = const [],
    this.chosenItemCode = '',
    this.chosenBarcode = '',
  });

  factory ProductMatchReviewItem.fromJson(Map<String, dynamic> j) {
    final q = (j['query'] is Map) ? Map<String, dynamic>.from(j['query'] as Map) : const <String, dynamic>{};
    final r = (j['result'] is Map) ? Map<String, dynamic>.from(j['result'] as Map) : const <String, dynamic>{};
    final cands = <ProductMatchCandidate>[];
    for (final c in (r['candidates'] as List?) ?? const []) {
      if (c is Map) cands.add(ProductMatchCandidate.fromJson(Map<String, dynamic>.from(c)));
    }
    return ProductMatchReviewItem(
      id: '${j['id'] ?? ''}',
      status: '${j['status'] ?? 'pending'}',
      itemCode: '${q['item_code'] ?? ''}',
      barcode: '${q['barcode'] ?? ''}',
      skuName: '${q['sku_name'] ?? ''}',
      sourceFile: '${q['source_file'] ?? ''}',
      rows: _i(q['rows']),
      value: _d(q['value']),
      decision: '${r['decision'] ?? ''}',
      confidence: _d(r['confidence']),
      reasonAr: '${r['reason_ar'] ?? ''}',
      matchedItemCode: '${r['matched_item_code'] ?? ''}',
      matchedName: '${r['matched_name'] ?? ''}',
      suggestedBarcode: '${r['suggested_barcode'] ?? ''}',
      barcodePolicy: '${r['barcode_policy'] ?? ''}',
      candidates: cands,
      chosenItemCode: '${j['chosen_item_code'] ?? ''}',
      chosenBarcode: '${j['chosen_barcode'] ?? ''}',
    );
  }
}

/// Coarse priority for Phase B prioritized review UI.
enum ProductMatchPriority { high, medium, low }

extension ProductMatchReviewItemPriority on ProductMatchReviewItem {
  ProductMatchPriority get priority {
    if (value >= 10000 || rows >= 50) return ProductMatchPriority.high;
    if (value >= 1000 || rows >= 10) return ProductMatchPriority.medium;
    return ProductMatchPriority.low;
  }

  String get priorityLabelAr {
    switch (priority) {
      case ProductMatchPriority.high:
        return 'أولوية عالية';
      case ProductMatchPriority.medium:
        return 'أولوية متوسطة';
      case ProductMatchPriority.low:
        return 'أولوية منخفضة';
    }
  }

  /// Bulk-approve only when a Product Master suggestion already carries a barcode.
  bool get bulkApproveEligible =>
      status == 'pending' &&
      decision == 'uncertain' &&
      matchedItemCode.isNotEmpty &&
      suggestedBarcode.isNotEmpty;

  double get priorityScore {
    final band = switch (priority) {
      ProductMatchPriority.high => 3e12,
      ProductMatchPriority.medium => 2e12,
      ProductMatchPriority.low => 1e12,
    };
    final conf = confidence.clamp(0.0, 1.0);
    return band + value * 1e6 + rows * 1e3 + (1 - conf) * 100;
  }
}

/// Sorts review rows: high impact first (matches backend SortReviewItemsByPriority).
List<ProductMatchReviewItem> sortProductMatchByPriority(List<ProductMatchReviewItem> items) {
  final out = List<ProductMatchReviewItem>.from(items);
  out.sort((a, b) {
    final c = b.priorityScore.compareTo(a.priorityScore);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  });
  return out;
}

class ProductMatchBulkDecideResult {
  final int approved;
  final int skipped;
  final int failed;
  final ProductMatchMetrics metrics;

  const ProductMatchBulkDecideResult({
    this.approved = 0,
    this.skipped = 0,
    this.failed = 0,
    this.metrics = const ProductMatchMetrics(),
  });
}

abstract class ProductMatchDataSource {
  Future<List<ProductMatchReviewItem>> list({String status = 'pending'});
  Future<ProductMatchMetrics> metrics();
  Future<ProductMatchMetrics> decide({
    required String id,
    required String status,
    String reasonAr = '',
    String chosenItemCode = '',
    String chosenBarcode = '',
  });
  Future<ProductMatchBulkDecideResult> bulkDecide({
    required List<String> ids,
    required String status,
    String reasonAr = '',
  });
}

class HttpProductMatchDataSource implements ProductMatchDataSource {
  final ApiClient api;
  HttpProductMatchDataSource(this.api);

  @override
  Future<List<ProductMatchReviewItem>> list({String status = 'pending'}) async {
    final uri = Uri.parse(ApiEndpoints.productMatchReview)
        .replace(queryParameters: {if (status.isNotEmpty) 'status': status});
    final res = await BackendHttp.get(uri, headers: api.requestHeaders).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل قائمة مراجعة الأصناف (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = [
      for (final e in (j['items'] as List?) ?? const [])
        if (e is Map) ProductMatchReviewItem.fromJson(Map<String, dynamic>.from(e)),
    ];
    return sortProductMatchByPriority(items);
  }

  @override
  Future<ProductMatchMetrics> metrics() async {
    final res = await BackendHttp.get(
      Uri.parse(ApiEndpoints.productMatchMetrics),
      headers: api.requestHeaders,
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل مؤشرات المطابقة (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ProductMatchMetrics.fromJson(j);
  }

  @override
  Future<ProductMatchMetrics> decide({
    required String id,
    required String status,
    String reasonAr = '',
    String chosenItemCode = '',
    String chosenBarcode = '',
  }) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.productMatchDecide),
      headers: api.requestHeaders,
      body: jsonEncode({
        'id': id,
        'status': status,
        'reason_ar': reasonAr,
        'chosen_item_code': chosenItemCode,
        'chosen_barcode': chosenBarcode,
      }),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      String msg = 'تعذر تسجيل القرار (HTTP ${res.statusCode})';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        if (j is Map && j['error'] != null) msg = '${j['error']}';
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ProductMatchMetrics.fromJson(
      j['metrics'] is Map ? Map<String, dynamic>.from(j['metrics'] as Map) : null,
    );
  }

  @override
  Future<ProductMatchBulkDecideResult> bulkDecide({
    required List<String> ids,
    required String status,
    String reasonAr = '',
  }) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.productMatchBulkDecide),
      headers: api.requestHeaders,
      body: jsonEncode({
        'ids': ids,
        'status': status,
        'reason_ar': reasonAr,
      }),
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      String msg = 'تعذر الاعتماد الجماعي (HTTP ${res.statusCode})';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        if (j is Map && j['error'] != null) msg = '${j['error']}';
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ProductMatchBulkDecideResult(
      approved: _i(j['approved']),
      skipped: _i(j['skipped']),
      failed: _i(j['failed']),
      metrics: ProductMatchMetrics.fromJson(
        j['metrics'] is Map ? Map<String, dynamic>.from(j['metrics'] as Map) : null,
      ),
    );
  }
}
