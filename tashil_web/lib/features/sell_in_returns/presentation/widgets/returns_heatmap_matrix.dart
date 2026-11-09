import 'package:flutter/material.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

import '../../domain/sell_in_returns_models.dart';

/// Branch × month returns heatmap with:
/// - shared fixed month column widths (header + body aligned, including RTL)
/// - sticky branch + total columns
/// - uniform full-cell heat fill (no uneven white chips)
class ReturnsHeatmapMatrix extends StatefulWidget {
  const ReturnsHeatmapMatrix({
    super.key,
    required this.months,
    required this.branches,
    required this.columnTotals,
    required this.grandTotal,
    required this.monthLabelsAr,
    required this.showPct,
  });

  final List<int> months;
  final List<SellInReturnsBranchRow> branches;
  final Map<int, SellInReturnsCell> columnTotals;
  final SellInReturnsCell grandTotal;
  final List<String> monthLabelsAr;
  final bool showPct;

  static const double rowH = 44;
  static const double branchW = 168;
  static const double monthW = 92;
  static const double totalW = 108;
  static const double cellGap = 1;

  @override
  State<ReturnsHeatmapMatrix> createState() => _ReturnsHeatmapMatrixState();
}

class _ReturnsHeatmapMatrixState extends State<ReturnsHeatmapMatrix> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  double _raw(SellInReturnsCell c) =>
      widget.showPct ? c.returnPctOfGross : c.returnsValueEgp;

  String _fmt(SellInReturnsCell c) {
    if (widget.showPct) return '${c.returnPctOfGross.toStringAsFixed(1)}%';
    return CurrencyFormatter.formatCompactEGP(c.returnsValueEgp);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = M3StatusColors.of(context);
    final months = widget.months;
    final branches = widget.branches;

    final maxRet = branches.fold<double>(0, (m, b) {
      for (final cell in b.byMonth.values) {
        final v = _raw(cell);
        if (v > m) m = v;
      }
      return m;
    });

    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final boldStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900);

    Widget labelCell({
      required String text,
      required double width,
      TextStyle? style,
      Color? bg,
      TextAlign align = TextAlign.start,
      bool boldEdge = false,
    }) {
      return SizedBox(
        width: width,
        height: ReturnsHeatmapMatrix.rowH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
              left: boldEdge ? BorderSide(color: cs.outlineVariant.withOpacity(0.55)) : BorderSide.none,
              right: boldEdge ? BorderSide(color: cs.outlineVariant.withOpacity(0.55)) : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: align == TextAlign.center
                  ? Alignment.center
                  : align == TextAlign.end
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
              child: Text(
                text,
                style: style,
                textAlign: align,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    Widget heatCell(SellInReturnsCell cell, {TextStyle? style}) {
      final raw = _raw(cell);
      final t = maxRet <= 0 ? 0.0 : (raw / maxRet).clamp(0.0, 1.0);
      final bg = raw <= 0
          ? cs.surface
          : Color.lerp(cs.surface, status.warningContainer.withOpacity(0.9), t);
      return Padding(
        padding: const EdgeInsets.all(ReturnsHeatmapMatrix.cellGap / 2),
        child: SizedBox(
          width: ReturnsHeatmapMatrix.monthW - ReturnsHeatmapMatrix.cellGap,
          height: ReturnsHeatmapMatrix.rowH - ReturnsHeatmapMatrix.cellGap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
            ),
            child: Center(
              child: Text(
                _fmt(cell),
                style: style ?? bodyStyle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    Widget monthHeader(int m) {
      final label = (m >= 1 && m < widget.monthLabelsAr.length)
          ? widget.monthLabelsAr[m]
          : '$m';
      return Padding(
        padding: const EdgeInsets.all(ReturnsHeatmapMatrix.cellGap / 2),
        child: SizedBox(
          width: ReturnsHeatmapMatrix.monthW - ReturnsHeatmapMatrix.cellGap,
          height: ReturnsHeatmapMatrix.rowH - ReturnsHeatmapMatrix.cellGap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.45),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
            ),
            child: Center(
              child: TestSemantics(
                identifier: 'returns-month-col-$m',
                label: label,
                child: Text(label, style: headerStyle, textAlign: TextAlign.center, maxLines: 1),
              ),
            ),
          ),
        ),
      );
    }

    Widget monthsStrip({required bool isHeader, SellInReturnsBranchRow? branch, bool isTotals = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in months)
            if (isHeader)
              monthHeader(m)
            else if (isTotals)
              heatCell(widget.columnTotals[m] ?? const SellInReturnsCell(), style: boldStyle)
            else
              heatCell(branch!.byMonth[m] ?? const SellInReturnsCell()),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            labelCell(
              text: 'الفرع',
              width: ReturnsHeatmapMatrix.branchW,
              style: headerStyle,
              bg: cs.surfaceContainerHighest.withOpacity(0.45),
              boldEdge: true,
            ),
            for (final b in branches)
              labelCell(
                text: b.branchName,
                width: ReturnsHeatmapMatrix.branchW,
                style: bodyStyle,
                boldEdge: true,
              ),
            labelCell(
              text: 'الإجمالي',
              width: ReturnsHeatmapMatrix.branchW,
              style: boldStyle,
              bg: cs.surfaceContainerHighest.withOpacity(0.5),
              boldEdge: true,
            ),
          ],
        ),
        Expanded(
          child: TableScrollContainer(
            controller: _scrollCtrl,
            showControls: true,
            showSwipeHint: months.length > 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                monthsStrip(isHeader: true),
                for (final b in branches) monthsStrip(isHeader: false, branch: b),
                monthsStrip(isHeader: false, isTotals: true),
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            labelCell(
              text: 'الإجمالي',
              width: ReturnsHeatmapMatrix.totalW,
              style: headerStyle,
              bg: cs.surfaceContainerHighest.withOpacity(0.45),
              align: TextAlign.center,
              boldEdge: true,
            ),
            for (final b in branches)
              labelCell(
                text: _fmt(b.total),
                width: ReturnsHeatmapMatrix.totalW,
                style: boldStyle,
                align: TextAlign.center,
                boldEdge: true,
              ),
            labelCell(
              text: _fmt(widget.grandTotal),
              width: ReturnsHeatmapMatrix.totalW,
              style: boldStyle,
              bg: cs.surfaceContainerHighest.withOpacity(0.5),
              align: TextAlign.center,
              boldEdge: true,
            ),
          ],
        ),
      ],
    );
  }
}
