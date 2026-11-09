import 'package:flutter/material.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

import '../../domain/sell_in_returns_models.dart';

/// Top returned products table with shared fixed column widths so RTL headers
/// stay aligned with body cells (avoids DataTable + TableScrollContainer expand mismatch).
class ReturnsTopProductsTable extends StatelessWidget {
  const ReturnsTopProductsTable({
    super.key,
    required this.products,
  });

  /// Stable keys for widget tests (filter dropdown also labels «الصنف»).
  static const Key productHeaderKey = Key('returns-top-products-col-product');
  static const Key returnsValueHeaderKey = Key('returns-top-products-col-returns-value');

  final List<SellInReturnsTopProduct> products;

  static const double _rowH = 44;
  static const double _rankW = 36;
  static const double _nameW = 240;
  static const double _numW = 112;

  /// Exposed for widget tests (rank col must stay narrow next to the name).
  static final Map<int, TableColumnWidth> columnWidths = {
    0: const FixedColumnWidth(_rankW),
    1: const FixedColumnWidth(_nameW),
    2: const FixedColumnWidth(_numW),
    3: const FixedColumnWidth(_numW),
    4: const FixedColumnWidth(_numW),
    5: const FixedColumnWidth(_numW),
    6: const FixedColumnWidth(_numW),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    Widget head(String text, {TextAlign align = TextAlign.start, Key? key}) => SizedBox(
          height: _rowH,
          child: Align(
            alignment: align == TextAlign.end
                ? AlignmentDirectional.centerEnd
                : align == TextAlign.center
                    ? Alignment.center
                    : AlignmentDirectional.centerStart,
            child: Text(key: key, text, style: headerStyle, textAlign: align, maxLines: 2),
          ),
        );

    Widget cell(String text, {TextAlign align = TextAlign.start, TextStyle? style}) => SizedBox(
          height: _rowH,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );

    return TableScrollContainer(
      showSwipeHint: true,
      child: Table(
        columnWidths: columnWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(0.45)),
            children: [
              head('#', align: TextAlign.center),
              head('الصنف', key: productHeaderKey),
              head('قيمة المرتجع', align: TextAlign.end, key: returnsValueHeaderKey),
              head('الكمية', align: TextAlign.end),
              head('نسبة من الإجمالي', align: TextAlign.end),
              head('حصة المرتجعات', align: TextAlign.end),
              head('صافي بعد المرتجعات', align: TextAlign.end),
            ],
          ),
          for (final p in products)
            TableRow(
              children: [
                cell('${p.rank}', align: TextAlign.center),
                cell(
                  p.productCode.isEmpty
                      ? p.productName
                      : '${p.productName} (${p.productCode})',
                ),
                cell(CurrencyFormatter.formatCompactEGP(p.returnsValueEgp), align: TextAlign.end),
                cell(CurrencyFormatter.formatNumber(p.returnsQty.round()), align: TextAlign.end),
                cell('${p.returnPctOfGross.toStringAsFixed(1)}%', align: TextAlign.end),
                cell('${p.shareOfReturns.toStringAsFixed(1)}%', align: TextAlign.end),
                cell(CurrencyFormatter.formatCompactEGP(p.netValueEgp), align: TextAlign.end),
              ],
            ),
        ],
      ),
    );
  }
}
