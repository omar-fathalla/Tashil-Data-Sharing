import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';

const String kDqOpen = 'مفتوحة';
const String kDqResolved = 'اتصلّحت';
const String kDqIgnored = 'متجاهلة';
const String kDqCritical = 'حرجة';
const String kDqWarning = 'تحذير';

const Map<String, String> kDqSourceLabels = {
  'product_master': 'كارتة الأصناف',
  'sell_out': 'Sell-Out',
  'sell_in': 'Sell-In',
};

/// Label for a data-quality source; Sell-In uploads use "sellin_upload:<file>".
String dqSourceLabel(String source) {
  if (source.startsWith('sellin_upload:')) return 'ملف توريد: ${source.substring('sellin_upload:'.length)}';
  return kDqSourceLabels[source] ?? source;
}

double? _num(dynamic v) => v is num ? v.toDouble() : null;
DateTime? _date(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class DataQualityIssue {
  final String id;
  final String source;
  final String type;
  final String typeLabel;
  final String severity;
  final String sheet;
  final int row;
  final String column;
  final String itemCode;
  final String barcode;
  final String itemName;
  final String foundValue;
  final String expectedValue;
  final double? impactEgp;
  final String status;
  final String statusReason;
  final DateTime? firstSeen;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final bool autoClosed;

  const DataQualityIssue({
    required this.id,
    required this.source,
    required this.type,
    required this.typeLabel,
    required this.severity,
    this.sheet = '',
    this.row = 0,
    this.column = '',
    this.itemCode = '',
    this.barcode = '',
    this.itemName = '',
    this.foundValue = '',
    this.expectedValue = '',
    this.impactEgp,
    required this.status,
    this.statusReason = '',
    this.firstSeen,
    this.updatedAt,
    this.resolvedAt,
    this.autoClosed = false,
  });

  factory DataQualityIssue.fromJson(Map<String, dynamic> j) => DataQualityIssue(
        id: j['id'] as String? ?? '',
        source: j['source'] as String? ?? '',
        type: j['type'] as String? ?? '',
        typeLabel: j['type_label'] as String? ?? (j['type'] as String? ?? ''),
        severity: j['severity'] as String? ?? '',
        sheet: j['sheet'] as String? ?? '',
        row: (j['row'] as num?)?.toInt() ?? 0,
        column: j['column'] as String? ?? '',
        itemCode: j['item_code'] as String? ?? '',
        barcode: j['barcode'] as String? ?? '',
        itemName: j['sku_name'] as String? ?? '',
        foundValue: j['found_value'] as String? ?? '',
        expectedValue: j['expected_value'] as String? ?? '',
        impactEgp: _num(j['impact_egp']),
        status: j['status'] as String? ?? kDqOpen,
        statusReason: j['status_reason'] as String? ?? '',
        firstSeen: _date(j['first_seen']),
        updatedAt: _date(j['updated_at']),
        resolvedAt: _date(j['resolved_at']),
        autoClosed: j['auto_closed'] as bool? ?? false,
      );
}

class DataQualityTypeSummary {
  final String source;
  final String type;
  final String typeLabel;
  final String severity;
  final int total;
  final int open;
  final double impactEgp;
  const DataQualityTypeSummary({
    required this.source,
    required this.type,
    required this.typeLabel,
    required this.severity,
    required this.total,
    required this.open,
    required this.impactEgp,
  });
  factory DataQualityTypeSummary.fromJson(Map<String, dynamic> j) => DataQualityTypeSummary(
        source: j['source'] as String? ?? '',
        type: j['type'] as String? ?? '',
        typeLabel: j['type_label'] as String? ?? '',
        severity: j['severity'] as String? ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        open: (j['open'] as num?)?.toInt() ?? 0,
        impactEgp: _num(j['impact_egp']) ?? 0,
      );
}

class DataQualitySummary {
  final List<DataQualityTypeSummary> types;
  final int totalRows;
  final int criticalRows;
  final double cleanlinessPct;
  final int open;
  final int resolved;
  final int ignored;
  final DateTime? updatedAt;
  const DataQualitySummary({
    this.types = const [],
    this.totalRows = 0,
    this.criticalRows = 0,
    this.cleanlinessPct = 100,
    this.open = 0,
    this.resolved = 0,
    this.ignored = 0,
    this.updatedAt,
  });
  factory DataQualitySummary.fromJson(Map<String, dynamic> j) => DataQualitySummary(
        types: ((j['types'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DataQualityTypeSummary.fromJson)
            .toList(),
        totalRows: (j['total_rows'] as num?)?.toInt() ?? 0,
        criticalRows: (j['critical_rows'] as num?)?.toInt() ?? 0,
        cleanlinessPct: _num(j['cleanliness_pct']) ?? 100,
        open: (j['open'] as num?)?.toInt() ?? 0,
        resolved: (j['resolved'] as num?)?.toInt() ?? 0,
        ignored: (j['ignored'] as num?)?.toInt() ?? 0,
        updatedAt: _date(j['updated_at']),
      );
}

class DataQualityFilter {
  final String source;
  final String type;
  final String severity;

  /// '' = open (server default), 'all', or a status label.
  final String status;
  const DataQualityFilter({this.source = '', this.type = '', this.severity = '', this.status = ''});
  DataQualityFilter copyWith({String? source, String? type, String? severity, String? status}) => DataQualityFilter(
        source: source ?? this.source,
        type: type ?? this.type,
        severity: severity ?? this.severity,
        status: status ?? this.status,
      );
}

class DataQualityException implements Exception {
  final String message;
  const DataQualityException(this.message);
  @override
  String toString() => message;
}

/// Reads / updates the Errors page data (`/api/v1/data-quality/*`). Never invents issues:
/// without a backend it returns an empty list.
abstract class DataQualityDataSource {
  Future<DataQualitySummary> summary();
  Future<List<DataQualityIssue>> issues(DataQualityFilter f);
  Future<DataQualityIssue> updateStatus(String id, String status, String reason);
}

class DataQualityRepository implements DataQualityDataSource {
  final ApiClient api;
  DataQualityRepository(this.api);

  Map<String, dynamic> _decode(List<int> b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>;

  @override
  Future<DataQualitySummary> summary() async {
    try {
      final res = await BackendHttp.get(Uri.parse(ApiEndpoints.dataQualitySummary), headers: api.requestHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return DataQualitySummary.fromJson(_decode(res.bodyBytes));
      if (!api.allowMockFallback) throw DataQualityException('تعذر تحميل ملخص الأخطاء (HTTP ${res.statusCode})');
    } catch (e) {
      if (!api.allowMockFallback) rethrow;
    }
    return const DataQualitySummary();
  }

  @override
  Future<List<DataQualityIssue>> issues(DataQualityFilter f) async {
    final q = <String, String>{
      if (f.source.isNotEmpty) 'source': f.source,
      if (f.type.isNotEmpty) 'type': f.type,
      if (f.severity.isNotEmpty) 'severity': f.severity,
      if (f.status.isNotEmpty) 'status': f.status,
    };
    try {
      final uri = Uri.parse(ApiEndpoints.dataQualityIssues).replace(queryParameters: q.isEmpty ? null : q);
      final res = await BackendHttp.get(uri, headers: api.requestHeaders).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final list = (_decode(res.bodyBytes)['issues'] as List?) ?? const [];
        return list.whereType<Map<String, dynamic>>().map(DataQualityIssue.fromJson).toList();
      }
      if (!api.allowMockFallback) throw DataQualityException('تعذر تحميل الأخطاء (HTTP ${res.statusCode})');
    } catch (e) {
      if (!api.allowMockFallback) rethrow;
    }
    return const [];
  }

  @override
  Future<DataQualityIssue> updateStatus(String id, String status, String reason) async {
    final res = await BackendHttp.patch(
      Uri.parse('${ApiEndpoints.dataQualityIssues}/${Uri.encodeComponent(id)}'),
      headers: api.requestHeaders,
      body: jsonEncode({'status': status, 'reason': reason}),
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) return DataQualityIssue.fromJson(_decode(res.bodyBytes));
    String msg = 'تعذر تغيير الحالة (HTTP ${res.statusCode})';
    try {
      final err = _decode(res.bodyBytes)['error'];
      if (err != null) msg = '$msg: $err';
    } catch (_) {}
    throw DataQualityException(msg);
  }
}
