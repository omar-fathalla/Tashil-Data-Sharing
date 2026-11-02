import 'package:flutter/material.dart';

import '../../../../core/network/upload_feedback.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_icons.dart';

/// What the user answered to an upload question: the parameter to resend and its value.
class UploadConfirmAnswer {
  final bool replaceConfirmed;
  final String? periodChoice;
  const UploadConfirmAnswer({this.replaceConfirmed = false, this.periodChoice});
}

const _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// "2026-03" -> "مارس 2026"; anything else is returned as is.
String arabicMonthLabel(String period) {
  final p = period.contains('|') ? period.split('|').last : period;
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(p);
  if (m == null) return p;
  final mi = int.parse(m.group(2)!);
  if (mi < 1 || mi > 12) return p;
  return '${_arMonths[mi - 1]} ${m.group(1)}';
}

/// Asks the question in a 409 response. Returns null when the user cancels (nothing is saved).
Future<UploadConfirmAnswer?> askUploadConfirmation(
  BuildContext context,
  UploadConfirmationRequiredException q,
) {
  return showDialog<UploadConfirmAnswer>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final isPartial = q.kind == 'partial_month';
      return AlertDialog(
        key: const Key('upload_confirm_dialog'),
        icon: Icon(isPartial ? AppIcons.warning : AppIcons.calendar, color: cs.tertiary),
        title: Text(isPartial ? 'الملف هيستبدل بيانات موجودة' : 'محتاجين تأكيدك قبل الحفظ'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(q.messageAr, style: theme.textTheme.bodyMedium),
                if (q.breakdown.isNotEmpty) ...[
                  const SizedBox(height: M3Spacing.sm),
                  for (final b in q.breakdown)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.calendarToday),
                      title: Text(arabicMonthLabel(b.period)),
                      subtitle: Text(isPartial
                          ? 'الملف: ${b.rows} صف • ${CurrencyFormatter.formatCompactEGP(b.value)} — الموجود حالياً: ${b.existingRows} صف • ${CurrencyFormatter.formatCompactEGP(b.existingValue)}'
                          : '${b.rows} صف • ${CurrencyFormatter.formatCompactEGP(b.value)}'),
                    ),
                ],
                if (q.kind == 'chain_required') ...[
                  const SizedBox(height: M3Spacing.sm),
                  Text('اختار السلسلة من الفورم وارفع الملف تاني.', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            key: const Key('upload_confirm_cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء (مفيش حاجة هتتحفظ)'),
          ),
          if (isPartial)
            FilledButton.icon(
              key: const Key('upload_confirm_replace'),
              onPressed: () => Navigator.of(ctx).pop(const UploadConfirmAnswer(replaceConfirmed: true)),
              icon: const Icon(AppIcons.check),
              label: const Text('أيوه، استبدل الشهر ده'),
            ),
          if (q.kind == 'period_conflict')
            for (final o in q.options)
              o.recommended
                  ? FilledButton(
                      key: Key('upload_confirm_option_${o.value}'),
                      onPressed: () => Navigator.of(ctx).pop(UploadConfirmAnswer(periodChoice: o.value)),
                      child: Text(o.labelAr),
                    )
                  : OutlinedButton(
                      key: Key('upload_confirm_option_${o.value}'),
                      onPressed: () => Navigator.of(ctx).pop(UploadConfirmAnswer(periodChoice: o.value)),
                      child: Text(o.labelAr),
                    ),
        ],
      );
    },
  );
}

/// Warnings that came back with an upload: held-out customers, unknown items, other notes.
class UploadChecksPanel extends StatelessWidget {
  final List<UploadWarning> warnings;
  final List<QuarantinedCustomerInfo> quarantined;
  final List<Map<String, dynamic>> unknownBarcodes;

  const UploadChecksPanel({
    super.key,
    this.warnings = const [],
    this.quarantined = const [],
    this.unknownBarcodes = const [],
  });

  bool get isEmpty => warnings.isEmpty && quarantined.isEmpty && unknownBarcodes.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card.outlined(
      key: const Key('upload_checks_panel'),
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(AppIcons.warning, color: cs.tertiary),
              const SizedBox(width: M3Spacing.xs),
              Expanded(child: Text('ملاحظات على الملف', style: theme.textTheme.titleMedium)),
            ]),
            for (final w in warnings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(w.severity == 'info' ? AppIcons.info : AppIcons.warning),
                title: Text(w.messageAr),
                subtitle: w.samples.isEmpty ? null : Text(w.samples.join('، ')),
              ),
            if (quarantined.isNotEmpty) ...[
              const Divider(),
              Text(
                'عملاء جداد متحطوش في أي إجمالي لحد ما الأدمن يأكدهم (${quarantined.length})',
                style: theme.textTheme.titleSmall,
              ),
              for (final q in quarantined)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.pendingCustomers),
                  title: Text(q.name),
                  subtitle: Text([
                    '${q.rows} صف • ${CurrencyFormatter.formatCompactEGP(q.value)}',
                    if (q.suggestedName.isNotEmpty) 'اسم قريب (مجرد اقتراح، مش هيتطبق لوحده): ${q.suggestedName}',
                  ].join('\n')),
                ),
            ],
            if (unknownBarcodes.isNotEmpty) ...[
              const Divider(),
              Text(
                'أصناف مش موجودة في كارتة الأصناف (${unknownBarcodes.length}) — الصفوف اتحفظت',
                style: theme.textTheme.titleSmall,
              ),
              for (final b in unknownBarcodes.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.barcode),
                  title: Text('${b['item_name'] ?? ''}'),
                  subtitle: Text([
                    if ('${b['barcode'] ?? ''}'.isNotEmpty) 'باركود ${b['barcode']}',
                    if ('${b['item_code'] ?? ''}'.isNotEmpty) 'كود ${b['item_code']}',
                    '${b['rows'] ?? 0} صف',
                  ].join(' • ')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Runs a one-step upload, asking each server question (409) and resending with the answers.
/// Returns null when the user cancels (nothing saved). Other errors are rethrown.
Future<T?> runUploadWithQuestions<T>(
  BuildContext context,
  Future<T> Function(bool replaceConfirmed, String? periodChoice) call,
) async {
  var replace = false;
  String? choice;
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      return await call(replace, choice);
    } on UploadConfirmationRequiredException catch (q) {
      if (!context.mounted) return null;
      final answer = await askUploadConfirmation(context, q);
      if (answer == null || q.kind == 'chain_required') return null;
      if (answer.replaceConfirmed) replace = true;
      if (answer.periodChoice != null) choice = answer.periodChoice;
    }
  }
  return null;
}

/// Short Arabic summary of upload warnings for a snackbar ('' when there are none).
String uploadWarningsSummary(IngestionWarningsView r) {
  final parts = <String>[
    if (r.quarantinedCount > 0) '${r.quarantinedCount} عميل جديد برّه الإجماليات لحد ما يتأكد',
    if (r.unknownBarcodeCount > 0) '${r.unknownBarcodeCount} صنف مش في كارتة الأصناف',
  ];
  return parts.join(' • ');
}

/// Minimal view so the summary works without importing the API model here.
class IngestionWarningsView {
  final int quarantinedCount;
  final int unknownBarcodeCount;
  const IngestionWarningsView(this.quarantinedCount, this.unknownBarcodeCount);
}
