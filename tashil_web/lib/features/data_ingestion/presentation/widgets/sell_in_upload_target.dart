import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/data/available_years.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
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
        if (isExplicitChain(c.code))
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

/// The longest the screen waits for a Sell-In upload job before it stops the spinner.
const sellInUploadTimeout = Duration(minutes: 5);

/// Arabic text for an upload failure. The server's own Arabic message wins when there is one.
String uploadFailureMessage(Object error) {
  if (error is UploadRejectedException) return error.message;
  if (error is TimeoutException) {
    return 'الرفع أخد وقت أطول من المتوقع، فوقفنا الانتظار. راجع أرشيف الملفات بعد شوية قبل ما ترفع تاني.';
  }
  if (error is ServerConnectionException) return error.message;
  return 'تعذّر رفع الملف. حاول تاني.';
}

/// Shows an upload failure in an M3 dialog that stays until the user closes it.
Future<void> showUploadFailureDialog(BuildContext context, String fileName, Object error) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(AppIcons.error, color: theme.colorScheme.error),
        title: const Text('الملف اترفض ومفيش حاجة اتحفظت'),
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
