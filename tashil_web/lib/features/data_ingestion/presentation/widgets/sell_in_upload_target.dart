import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/data/available_years.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/backend_http.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_dropdown.dart';

/// Where a Sell-In file goes. TOP RULE: the chain is always chosen by the user (no default chain,
/// no guess from the file). Year and month are optional: null means "read them from the file".
class SellInUploadTarget {
  final String chain;
  final int? year;
  final int? month;
  const SellInUploadTarget({required this.chain, this.year, this.month});
}

/// True when [chain] names one real chain (not empty and not "all").
bool isExplicitChain(String? chain) {
  final c = (chain ?? '').trim().toLowerCase();
  return c.isNotEmpty && c != 'all' && c != 'الكل';
}

/// Chain options from the tenant chains API (the same source as the upload portal).
List<M3DropdownOption<String>> chainOptions(List<RetailChainModel> chains) => [
      for (final c in chains)
        if (isExplicitChain(c.code) && c.registered)
          M3DropdownOption<String>(c.code, c.displayName.isNotEmpty ? c.displayName : c.code),
    ];

const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// Asks for the chain (required) and an optional period before a Sell-In file is picked.
/// [initialChain] is preselected only when it names one chain. Returns null on cancel.
Future<SellInUploadTarget?> askSellInUploadTarget(
  BuildContext context, {
  required List<RetailChainModel> chains,
  String? initialChain,
}) {
  return showDialog<SellInUploadTarget>(
    context: context,
    builder: (ctx) => _SellInUploadTargetDialog(
      chains: chains,
      initialChain: initialChain,
    ),
  );
}

class _SellInUploadTargetDialog extends StatefulWidget {
  final List<RetailChainModel> chains;
  final String? initialChain;
  const _SellInUploadTargetDialog({required this.chains, this.initialChain});

  @override
  State<_SellInUploadTargetDialog> createState() => _SellInUploadTargetDialogState();
}

class _SellInUploadTargetDialogState extends State<_SellInUploadTargetDialog> {
  late String _chain;
  int _year = 0;
  int _month = 0;

  @override
  void initState() {
    super.initState();
    final codes = widget.chains.map((c) => c.code).toSet();
    final init = widget.initialChain ?? '';
    _chain = isExplicitChain(init) && codes.contains(init) ? init : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = chainOptions(widget.chains);
    return AlertDialog(
      icon: const Icon(AppIcons.uploadFile),
      title: const Text('رفع ملف Sell-In'),
      content: SizedBox(
        width: 360.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اختار السلسلة اللي الملف ده تبعها. مفيش سلسلة بتتختار لوحدها.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: M3Spacing.sm),
            if (options.isEmpty)
              Text('مفيش سلاسل متسجلة. ضيف السلسلة من صفحة الأدمن الأول.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
            else
              M3Dropdown<String>(
                key: const ValueKey('sellInUploadChain'),
                value: _chain,
                label: 'السلسلة',
                hint: 'اختار السلسلة',
                expand: true,
                options: options,
                onChanged: (v) => setState(() => _chain = v),
              ),
            const SizedBox(height: M3Spacing.sm),
            M3Dropdown<int>(
              value: _year,
              label: 'السنة',
              expand: true,
              options: [
                const M3DropdownOption<int>(0, 'من الملف'),
                for (final y in AvailableYears.current.including(_year)) M3DropdownOption<int>(y, '$y'),
              ],
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: M3Spacing.sm),
            M3Dropdown<int>(
              value: _month,
              label: 'الشهر',
              expand: true,
              options: [
                const M3DropdownOption<int>(0, 'من الملف'),
                for (var m = 1; m <= 12; m++) M3DropdownOption<int>(m, _monthsAr[m - 1]),
              ],
              onChanged: (v) => setState(() => _month = v),
            ),
            const SizedBox(height: M3Spacing.xs),
            Text(
              sellInPeriodHelpText,
              key: const ValueKey('sellInUploadPeriodHelp'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          key: const ValueKey('sellInUploadChooseFile'),
          onPressed: isExplicitChain(_chain)
              ? () => Navigator.of(context).pop(SellInUploadTarget(
                    chain: _chain,
                    year: _year > 0 ? _year : null,
                    month: _month > 0 ? _month : null,
                  ))
              : null,
          child: const Text('اختار الملف'),
        ),
      ],
    );
  }
}

/// "شهور الملف (أغسطس، سبتمبر 2026)" for the months of a file when the user chose the sheet's
/// own months; [months] are "2026-08" or "chain|2026-08".
String describeSheetPeriod(Iterable<String> months) {
  final byYear = <int, Set<int>>{};
  for (final raw in months) {
    final p = (raw.contains('|') ? raw.split('|').last : raw).split('-');
    final y = p.isNotEmpty ? int.tryParse(p[0]) : null;
    final m = p.length > 1 ? int.tryParse(p[1]) : null;
    if (y == null || m == null || m < 1 || m > 12) continue;
    (byYear[y] ??= <int>{}).add(m);
  }
  if (byYear.isEmpty) return 'شهور الملف';
  final years = byYear.keys.toList()..sort();
  final parts = [
    for (final y in years) '${(byYear[y]!.toList()..sort()).map((m) => _monthsAr[m - 1]).join('، ')} $y',
  ];
  return 'شهور الملف (${parts.join(' • ')})';
}

/// Shown under the year/month fields of the upload dialog.
const sellInPeriodHelpText = 'سيبها "من الملف" (موصى بيه). لو اخترت شهر والملف فيه شهور تانية، هنسألك تختار.';

/// Client-side ceiling while following a Sell-In background job. Prefer a terminal
/// job status; this bound only stops the spinner if the server never answers.
/// Matches [BackendHttp.defaultJobMaxWait] so the UI `.timeout` does not cut polling short.
const sellInUploadTimeout = BackendHttp.defaultJobMaxWait;

/// Neutral copy when the client stops waiting while the server may still be saving.
const sellInUploadStillProcessingMessage =
    'الملف لسه بيتعالج على السيرفر. شوف قائمة الملفات بعد شوية — متترفعش تاني لو لقيته هناك.';

/// Dialog title when the wait stopped without a server rejection (not "nothing was saved").
const sellInUploadStillProcessingTitle = 'الملف لسه بيتعالج';

/// True when the error means the client stopped waiting — not that the server rejected the file.
bool isUploadWaitTimeout(Object error) =>
    error is TimeoutException || error is UploadStillProcessingException;

/// Arabic text for an upload failure. The server's own Arabic message wins when there is one.
String uploadFailureMessage(Object error) {
  if (error is UploadRejectedException) return error.message;
  if (isUploadWaitTimeout(error)) return sellInUploadStillProcessingMessage;
  if (error is ServerConnectionException) return error.message;
  return 'تعذّر رفع الملف. حاول تاني.';
}

/// Shows an upload failure in an M3 dialog that stays until the user closes it.
/// Wait-timeouts use a neutral title — never "nothing was saved" unless the server rejected.
/// [title] defaults from the error kind; a failed commit may pass its own.
Future<void> showUploadFailureDialog(BuildContext context, String fileName, Object error, {String? title}) {
  final waitTimeout = isUploadWaitTimeout(error);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final scheme = theme.colorScheme;
      return AlertDialog(
        icon: Icon(
          waitTimeout ? AppIcons.info : AppIcons.error,
          color: waitTimeout ? scheme.tertiary : scheme.error,
        ),
        title: Text(title ??
            (waitTimeout ? sellInUploadStillProcessingTitle : 'الملف اترفض ومفيش حاجة اتحفظت')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fileName, style: theme.textTheme.titleSmall),
              const SizedBox(height: M3Spacing.xs),
              SelectableText(uploadFailureMessage(error), style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('تمام')),
        ],
      );
    },
  );
}

/// A saved upload where some customer names were held out of the totals until an admin confirms
/// them. Never says "rejected": the counted rows are saved. [onOpenPending] opens the
/// "customers needing confirmation" screen (the button is hidden when null).
Future<void> showQuarantineSavedDialog(
  BuildContext context, {
  required String fileName,
  required int validRows,
  required double validValue,
  required List<QuarantinedCustomerInfo> customers,
  VoidCallback? onOpenPending,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        key: const ValueKey('quarantineSavedDialog'),
        icon: Icon(AppIcons.warning, color: theme.colorScheme.tertiary),
        title: const Text('الملف اتحفظ، وفيه صفوف محجوزة'),
        content: SizedBox(
          width: 420.0,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(fileName, style: theme.textTheme.titleSmall),
                const SizedBox(height: M3Spacing.xs),
                Text('اتحسب: $validRows صف • ${CurrencyFormatter.formatCompactEGP(validValue)}',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: M3Spacing.xs),
                Text('الصفوف دي برّه كل الإجماليات لحد ما الأدمن يأكد اسم العميل:',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: M3Spacing.sm),
                Table(
                  columnWidths: const {0: FlexColumnWidth(3), 1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth()},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(children: [
                      Text('العميل', style: theme.textTheme.labelMedium),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: M3Spacing.sm),
                        child: Text('الصفوف', style: theme.textTheme.labelMedium),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: M3Spacing.sm),
                        child: Text('القيمة', style: theme.textTheme.labelMedium),
                      ),
                    ]),
                    for (final c in customers)
                      TableRow(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(c.name, style: theme.textTheme.bodyMedium),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: M3Spacing.sm),
                          child: Text('${c.rows}', style: theme.textTheme.bodyMedium),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: M3Spacing.sm),
                          child: Text(CurrencyFormatter.formatCompactEGP(c.value), style: theme.textTheme.bodyMedium),
                        ),
                      ]),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('تمام')),
          if (onOpenPending != null)
            FilledButton.icon(
              key: const ValueKey('openPendingCustomers'),
              onPressed: () {
                Navigator.of(ctx).pop();
                onOpenPending();
              },
              icon: const Icon(AppIcons.pendingCustomers),
              label: const Text('عملاء محتاجين تأكيد'),
            ),
        ],
      );
    },
  );
}
