/// Phase C Arabic Q&A response grounded in tenant-scoped BigQuery reads.
class ArabicQaAnswer {
  final String questionAr;
  final String answerAr;
  final String intent;
  final String period;
  final String tenantId;
  final double confidence;
  final String mappingSource;
  final bool readOnly;
  final List<String> sources;
  final Map<String, dynamic> evidence;

  const ArabicQaAnswer({
    required this.questionAr,
    required this.answerAr,
    required this.intent,
    this.period = '',
    this.tenantId = '',
    this.confidence = 0,
    this.mappingSource = '',
    this.readOnly = true,
    this.sources = const [],
    this.evidence = const {},
  });

  factory ArabicQaAnswer.fromJson(Map<String, dynamic> j) {
    return ArabicQaAnswer(
      questionAr: '${j['question_ar'] ?? ''}',
      answerAr: '${j['answer_ar'] ?? ''}',
      intent: '${j['intent'] ?? ''}',
      period: '${j['period'] ?? ''}',
      tenantId: '${j['tenant_id'] ?? ''}',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      mappingSource: '${j['mapping_source'] ?? ''}',
      readOnly: j['read_only'] != false,
      sources: [
        for (final s in (j['sources'] as List?) ?? const []) '$s',
      ],
      evidence: (j['evidence'] is Map)
          ? Map<String, dynamic>.from(j['evidence'] as Map)
          : const {},
    );
  }
}

class ArabicQaCapability {
  final String intent;
  final String titleAr;
  final List<String> examplesAr;

  const ArabicQaCapability({
    required this.intent,
    required this.titleAr,
    this.examplesAr = const [],
  });

  factory ArabicQaCapability.fromJson(Map<String, dynamic> j) {
    return ArabicQaCapability(
      intent: '${j['intent'] ?? ''}',
      titleAr: '${j['title_ar'] ?? ''}',
      examplesAr: [
        for (final e in (j['examples_ar'] as List?) ?? const []) '$e',
      ],
    );
  }
}
