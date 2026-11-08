// Models for POST /api/v1/ingest/precheck and dry-run preupload_blocked (Arabic fix list).

import 'dart:convert';

class PreuploadFixItem {
  final String code;
  final String severity;
  final String messageAr;
  final String howToFixAr;
  final String column;
  final List<String> samples;
  final int count;

  const PreuploadFixItem({
    required this.code,
    required this.severity,
    required this.messageAr,
    required this.howToFixAr,
    this.column = '',
    this.samples = const [],
    this.count = 0,
  });

  factory PreuploadFixItem.fromJson(Map<String, dynamic> json) {
    return PreuploadFixItem(
      code: '${json['code'] ?? ''}',
      severity: '${json['severity'] ?? 'error'}',
      messageAr: '${json['message_ar'] ?? ''}',
      howToFixAr: '${json['how_to_fix_ar'] ?? ''}',
      column: '${json['column'] ?? ''}',
      samples: (json['samples'] as List?)?.map((e) => '$e').toList() ?? const [],
      count: (json['count'] is num) ? (json['count'] as num).toInt() : 0,
    );
  }

  bool get isBlocking => severity == 'error';

  String get codeLabelAr {
    switch (code) {
      case 'missing_column':
        return 'عمود ناقص';
      case 'unclear_month':
        return 'شهر مش واضح';
      case 'unreadable_cell':
        return 'خلايا مش مقروءة';
      case 'empty_file':
        return 'ملف فاضي';
      default:
        return 'مشكلة في الملف';
    }
  }
}

class PreuploadCheckReport {
  final bool ok;
  final String filename;
  final String kind;
  final bool wroteNothing;
  final int blockingCount;
  final List<PreuploadFixItem> fixes;

  const PreuploadCheckReport({
    required this.ok,
    required this.filename,
    required this.kind,
    required this.wroteNothing,
    required this.blockingCount,
    required this.fixes,
  });

  factory PreuploadCheckReport.fromJson(Map<String, dynamic> json) {
    final fixes = (json['fixes'] as List?)
            ?.whereType<Map>()
            .map((e) => PreuploadFixItem.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <PreuploadFixItem>[];
    return PreuploadCheckReport(
      ok: json['ok'] == true,
      filename: '${json['filename'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      wroteNothing: json['wrote_nothing'] != false,
      blockingCount: (json['blocking_count'] is num)
          ? (json['blocking_count'] as num).toInt()
          : fixes.where((f) => f.isBlocking).length,
      fixes: fixes,
    );
  }

  /// Parses a 422 `preupload_blocked` body; null when the body is something else.
  static PreuploadCheckReport? tryParseBlocked(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if ('${map['error'] ?? ''}' != 'preupload_blocked') return null;
      return PreuploadCheckReport.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  bool get hasBlockingFixes => !ok || blockingCount > 0 || fixes.any((f) => f.isBlocking);
}

/// True when a standalone precheck HTTP failure must not block dry-run (404/5xx/network).
bool precheckFailureShouldContinue(int? statusCode) {
  if (statusCode == null) return true;
  return statusCode != 200;
}

/// Thrown when dry-run/upload is refused by the folded preupload checker (nothing saved).
class PreuploadBlockedException implements Exception {
  final PreuploadCheckReport report;
  const PreuploadBlockedException(this.report);

  @override
  String toString() => report.fixes.isNotEmpty
      ? report.fixes.first.messageAr
      : 'الملف محتاج تصليح قبل الرفع. مفيش حاجة اتحفظت.';
}
