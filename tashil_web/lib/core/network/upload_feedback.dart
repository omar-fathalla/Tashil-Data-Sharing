import 'dart:convert';

/// Upload findings returned with an ingestion result (warnings) or instead of it (a question).

/// One month of an upload, for the period and partial-month dialogs.
class UploadMonthSlice {
  final String period; // "2026-03" or "chain|2026-03"
  final int rows;
  final double value;
  final double units;
  final int existingRows;
  final double existingValue;

  const UploadMonthSlice({
    required this.period,
    this.rows = 0,
    this.value = 0,
    this.units = 0,
    this.existingRows = 0,
    this.existingValue = 0,
  });

  factory UploadMonthSlice.fromJson(Map<String, dynamic> j) => UploadMonthSlice(
        period: '${j['period'] ?? ''}',
        rows: (j['rows'] as num?)?.toInt() ?? 0,
        value: (j['value'] as num?)?.toDouble() ?? 0,
        units: (j['units'] as num?)?.toDouble() ?? 0,
        existingRows: (j['existing_rows'] as num?)?.toInt() ?? 0,
        existingValue: (j['existing_value'] as num?)?.toDouble() ?? 0,
      );

  /// "2026-03" without the chain prefix.
  String get month => period.contains('|') ? period.split('|').last : period;
}

class UploadConfirmOption {
  final String value;
  final String labelAr;
  final bool recommended;
  const UploadConfirmOption({required this.value, required this.labelAr, this.recommended = false});

  factory UploadConfirmOption.fromJson(Map<String, dynamic> j) => UploadConfirmOption(
        value: '${j['value'] ?? ''}',
        labelAr: '${j['label_ar'] ?? j['value'] ?? ''}',
        recommended: j['recommended'] == true,
      );
}

/// HTTP 409 from an upload or commit: nothing was saved; the user must answer and resend.
class UploadConfirmationRequiredException implements Exception {
  final String kind; // period_conflict | partial_month | chain_required
  final String messageAr;
  final String param; // period_choice | replace_confirmed | chain
  final List<UploadConfirmOption> options;
  final List<UploadMonthSlice> breakdown;
  final String formPeriod;

  const UploadConfirmationRequiredException({
    required this.kind,
    required this.messageAr,
    required this.param,
    this.options = const [],
    this.breakdown = const [],
    this.formPeriod = '',
  });

  /// Parses a 409 body; null when the body is not a confirmation request.
  static UploadConfirmationRequiredException? tryParse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['error'] != 'confirmation_required') return null;
      final c = (j['confirmation'] is Map) ? Map<String, dynamic>.from(j['confirmation'] as Map) : <String, dynamic>{};
      return UploadConfirmationRequiredException(
        kind: '${c['kind'] ?? ''}',
        messageAr: '${c['message_ar'] ?? j['message'] ?? ''}',
        param: '${c['param'] ?? ''}',
        options: [
          for (final o in (c['options'] as List?) ?? const [])
            if (o is Map) UploadConfirmOption.fromJson(Map<String, dynamic>.from(o)),
        ],
        breakdown: [
          for (final b in (c['breakdown'] as List?) ?? const [])
            if (b is Map) UploadMonthSlice.fromJson(Map<String, dynamic>.from(b)),
        ],
        formPeriod: '${c['form_period'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => messageAr;
}

/// A non-blocking upload warning (unknown customers held out of totals, unknown items, missing units...).
class UploadWarning {
  final String code;
  final String severity;
  final String messageAr;
  final int count;
  final double value;
  final List<String> samples;

  const UploadWarning({
    required this.code,
    required this.messageAr,
    this.severity = 'warning',
    this.count = 0,
    this.value = 0,
    this.samples = const [],
  });

  factory UploadWarning.fromJson(Map<String, dynamic> j) => UploadWarning(
        code: '${j['code'] ?? ''}',
        severity: '${j['severity'] ?? 'warning'}',
        messageAr: '${j['message_ar'] ?? ''}',
        count: (j['count'] as num?)?.toInt() ?? 0,
        value: (j['value'] as num?)?.toDouble() ?? 0,
        samples: [for (final s in (j['samples'] as List?) ?? const []) '$s'],
      );
}

/// A customer name held out of all totals until an admin confirms it.
class QuarantinedCustomerInfo {
  final String name;
  final int rows;
  final double value;
  final double units;
  final List<String> months;
  final String suggestedName;
  final String suggestionReason;

  const QuarantinedCustomerInfo({
    required this.name,
    this.rows = 0,
    this.value = 0,
    this.units = 0,
    this.months = const [],
    this.suggestedName = '',
    this.suggestionReason = '',
  });

  factory QuarantinedCustomerInfo.fromJson(Map<String, dynamic> j) => QuarantinedCustomerInfo(
        name: '${j['name'] ?? ''}',
        rows: (j['rows'] as num?)?.toInt() ?? 0,
        value: (j['value'] as num?)?.toDouble() ?? 0,
        units: (j['units'] as num?)?.toDouble() ?? 0,
        months: [for (final m in (j['months'] as List?) ?? const []) '$m'],
        suggestedName: '${j['suggested_name'] ?? ''}',
        suggestionReason: '${j['suggestion_reason'] ?? ''}',
      );
}

List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) f) => [
      for (final e in (raw as List?) ?? const [])
        if (e is Map) f(Map<String, dynamic>.from(e)),
    ];
