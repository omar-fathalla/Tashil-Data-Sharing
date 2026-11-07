/// Models for POST /api/v1/ingest/precheck (Arabic fix list, no server writes).

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

  bool get hasBlockingFixes => !ok || blockingCount > 0 || fixes.any((f) => f.isBlocking);
}
