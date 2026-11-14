import 'package:flutter/material.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/utils/glue_hyphen_tokens.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

import '../../domain/sell_in_returns_models.dart';

/// Top returned products table with shared column widths so RTL headers
/// stay aligned with body cells. Rank stays narrow; name + numeric columns
/// flex so the table fills the available width (Sell-Out / TM treatment).
class ReturnsTopProductsTable extends StatelessWidget {
  const ReturnsTopProductsTable({
    super.key,
    required this.products,
  });

  /// Stable keys for widget tests (filter dropdown also labels «الصنف»).
  static const Key productHeaderKey = Key('returns-top-products-col-product');
  static const Key returnsValueHeaderKey =
      Key('returns-top-products-col-returns-value');

  final List<SellInReturnsTopProduct> products;

  static const double _rowH = 44;
  static const double _rankW = 36;

  /// Exposed for widget tests (rank col must stay narrow next to the name).
  static final Map<int, TableColumnWidth> columnWidths = {
    0: const FixedColumnWidth(_rankW),
    1: const FlexColumnWidth(3.2),
    2: const FlexColumnWidth(1.1),
    3: const FlexColumnWidth(1.0),
    4: const FlexColumnWidth(1.1),
    5: const FlexColumnWidth(1.1),
    6: const FlexColumnWidth(1.2),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
    );
    final bodyStyle =
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    Widget head(String text, {TextAlign align = TextAlign.start, Key? key}) =>
        SizedBox(
          height: _rowH,
          child: Align(
            alignment: align == TextAlign.end
                ? AlignmentDirectional.centerEnd
                : align == TextAlign.center
                    ? Alignment.center
                    : AlignmentDirectional.centerStart,
            child: Text(
                key: key,
                text,
                style: headerStyle,
                textAlign: align,
                maxLines: 2),
          ),
        );

    // Rows grow so long names wrap to 3 lines without ellipsis.
    Widget cell(String text,
            {TextAlign align = TextAlign.start, TextStyle? style}) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowH),
          child: Align(
            alignment: align == TextAlign.end
                ? AlignmentDirectional.centerEnd
                : align == TextAlign.center
                    ? Alignment.center
                    : AlignmentDirectional.centerStart,
            child: Text(
              text,
              style: style ?? bodyStyle,
              textAlign: align,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );

    String productLabel(SellInReturnsTopProduct p) {
      final name = p.productName;
      if (p.productCode.isEmpty) return name;
      return '$name (${glueHyphenTokens(p.productCode)})';
    }

    return TableScrollContainer(
      showControls: false,
      showSwipeHint: false,
      child: Table(
        columnWidths: columnWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside:
              BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.45)),
            children: [
              head('#', align: TextAlign.center),
              head('الصنف', key: productHeaderKey),
              head('قيمة المرتجع',
                  align: TextAlign.center, key: returnsValueHeaderKey),
              head('الكمية', align: TextAlign.center),
              head('نسبة من الإجمالي', align: TextAlign.center),
              head('حصة المرتجعات', align: TextAlign.center),
              head('صافي بعد المرتجعات', align: TextAlign.center),
            ],
          ),
          for (final p in products)
            TableRow(
              children: [
                cell('${p.rank}', align: TextAlign.center),
                cell(productLabel(p)),
                cell(CurrencyFormatter.formatCompactEGP(p.returnsValueEgp),
                    align: TextAlign.center),
                cell(CurrencyFormatter.formatNumber(p.returnsQty.round()),
                    align: TextAlign.center),
                cell('${p.returnPctOfGross.toStringAsFixed(1)}%',
                    align: TextAlign.center),
                cell('${p.shareOfReturns.toStringAsFixed(1)}%',
                    align: TextAlign.center),
                cell(CurrencyFormatter.formatCompactEGP(p.netValueEgp),
                    align: TextAlign.center),
              ],
            ),
        ],
      ),
    );
  }
}
