import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/utils/shared_display_prefix.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

import '../../domain/sell_in_returns_models.dart';

/// Branch × month returns heatmap.
///
/// One shared row-height model: the frozen branch column, the month cells and
/// the total column all use the same header height and the same per-row
/// height (branch names wrap up to 3 lines and the whole row grows with
/// them). Month columns expand to fill the width when they fit; otherwise
/// the table scrolls with a reserved scrollbar gutter and no arrow buttons.
class ReturnsHeatmapMatrix extends StatelessWidget {
  const ReturnsHeatmapMatrix({
    super.key,
    required this.months,
    required this.branches,
    required this.columnTotals,
    required this.grandTotal,
    required this.monthLabelsAr,
    required this.showPct,
    this.branchDisplayNames = const {},
  });

  final List<int> months;
  final List<SellInReturnsBranchRow> branches;
  final Map<int, SellInReturnsCell> columnTotals;
  final SellInReturnsCell grandTotal;
  final List<String> monthLabelsAr;
  final bool showPct;

  /// Optional original → display map (shared prefix already stripped).
  /// When empty, the widget derives the map from [branches].
  final Map<String, String> branchDisplayNames;

  static const double minRowH = 44;
  static const double branchW = 168;
  static const double preferredMonthW = 72;

  /// Floor used when shrinking months so a 10-month matrix still fits
  /// the live 1280×800 shell (250dp sidebar + page/card padding).
  static const double minMonthW = 56;
  static const double totalW = 108;
  static const double hPad = 8;
  static const double vPad = 6;
  static const double cellGap = 1;

  static Key branchCellKey(String branchKey) =>
      ValueKey('returns-matrix-branch-$branchKey');
  static Key monthsRowKey(String branchKey) =>
      ValueKey('returns-matrix-months-$branchKey');
  static Key totalCellKey(String branchKey) =>
      ValueKey('returns-matrix-total-$branchKey');
  static const Key headerRowKey = ValueKey('returns-matrix-header');
  static const Key branchHeaderKey = ValueKey('returns-matrix-branch-header');
  static const Key totalHeaderKey = ValueKey('returns-matrix-total-header');
  static const Key totalsRowKey = ValueKey('returns-matrix-totals');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = M3StatusColors.of(context);
    final dir = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final boldStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w900,
    );

    final display = branchDisplayNames.isNotEmpty
        ? branchDisplayNames
        : displayNamesWithoutSharedPrefix(branches.map((b) => b.branchName));

    String labelOf(SellInReturnsBranchRow b) =>
        display[b.branchName] ?? b.branchName;

    double? rawOf(SellInReturnsCell? c) {
      if (c == null) return null;
      return showPct ? c.returnPctOfGross : c.returnsValueEgp;
    }

    /// Missing month → «—» (never fabricate 0 / 0.0%). Present zeros stay 0.
    String fmt(SellInReturnsCell? c) {
      if (c == null) return '—';
      if (showPct) return '${c.returnPctOfGross.toStringAsFixed(1)}%';
      return CurrencyFormatter.formatCompactEGP(c.returnsValueEgp);
    }

    var maxRet = 0.0;
    for (final b in branches) {
      for (final cell in b.byMonth.values) {
        final v = rawOf(cell);
        if (v != null && v > maxRet) maxRet = v;
      }
    }

    double measure({
      required String text,
      required TextStyle? style,
      required double maxWidth,
      required int maxLines,
    }) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, maxWidth));
      return tp.height;
    }

    double measureWidth(String text, TextStyle? style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return tp.width;
    }

    /// Prefer a single compact line (`993.0K ج.م`). If that overflows the
    /// cell, put the currency on a second line so the value never ellipsizes.
    String fitValue(String text, TextStyle? style, double maxWidth) {
      if (maxWidth <= 0 || measureWidth(text, style) <= maxWidth + 0.5) {
        return text;
      }
      final idx = text.lastIndexOf(' ');
      if (idx <= 0) return text;
      return '${text.substring(0, idx)}\n${text.substring(idx + 1)}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;

        var labelW = 0.0;
        for (final m in months) {
          final label = (m >= 1 && m < monthLabelsAr.length)
              ? monthLabelsAr[m]
              : '$m';
          labelW = math.max(labelW, measureWidth(label, headerStyle));
        }
        final comfortableMonth = math.max(preferredMonthW, labelW + hPad * 2);
        final tightMonth = math.max(minMonthW, labelW + 8);

        final leftover = available - branchW - totalW;
        final double monthW;
        if (months.isEmpty) {
          monthW = comfortableMonth;
        } else if (leftover / months.length >= comfortableMonth) {
          monthW = leftover / months.length;
        } else if (leftover / months.length >= tightMonth) {
          monthW = leftover / months.length;
        } else {
          monthW = comfortableMonth;
        }

        final headerH = math.max(
          minRowH,
          math.max(
                measure(
                  text: 'الفرع',
                  style: headerStyle,
                  maxWidth: branchW - hPad * 2,
                  maxLines: 2,
                ),
                math.max(
                  measure(
                    text: 'الإجمالي',
                    style: headerStyle,
                    maxWidth: totalW - hPad * 2,
                    maxLines: 2,
                  ),
                  measure(
                    text: 'سبتمبر',
                    style: headerStyle,
                    maxWidth: monthW - cellGap - hPad * 2,
                    maxLines: 1,
                  ),
                ),
              ) +
              vPad * 2,
        );

        final valueW = math.max(0.0, monthW - cellGap);
        final totalInnerW = math.max(0.0, totalW - hPad * 2);

        double valueBlockH(String text, TextStyle? style, double maxWidth) {
          final fitted = fitValue(text, style, maxWidth);
          final lines = fitted.contains('\n') ? 2 : 1;
          return measure(
            text: fitted,
            style: style,
            maxWidth: maxWidth,
            maxLines: lines,
          );
        }

        // One shared height model: branch label, month cells, and total all
        // include the same vertical padding so pinned columns stay aligned.
        final rowHeights = <double>[
          for (final b in branches)
            math.max(
              minRowH,
              math.max(
                    measure(
                      text: labelOf(b),
                      style: bodyStyle,
                      maxWidth: branchW - hPad * 2,
                      maxLines: 3,
                    ),
                    math.max(
                      valueBlockH(fmt(b.total), boldStyle, totalInnerW),
                      months.isEmpty
                          ? 0.0
                          : months
                                .map(
                                  (m) => valueBlockH(
                                    fmt(b.byMonth[m]),
                                    bodyStyle,
                                    valueW,
                                  ),
                                )
                                .reduce(math.max),
                    ),
                  ) +
                  vPad * 2,
            ),
        ];

        var totalsH = minRowH;
        if (months.isNotEmpty) {
          totalsH = math.max(
            totalsH,
            months
                    .map(
                      (m) => valueBlockH(
                        fmt(columnTotals[m]),
                        boldStyle,
                        valueW,
                      ),
                    )
                    .reduce(math.max) +
                vPad * 2,
          );
        }
        totalsH = math.max(
          totalsH,
          valueBlockH(fmt(grandTotal), boldStyle, totalInnerW) + vPad * 2,
        );

        Widget box({
          required double width,
          required double height,
          required Widget child,
          Color? bg,
          Color? border,
          bool boldEdge = false,
          Key? key,
        }) {
          return SizedBox(
            key: key,
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                  left: boldEdge
                      ? BorderSide(color: cs.outlineVariant.withOpacity(0.55))
                      : BorderSide.none,
                  right: boldEdge
                      ? BorderSide(color: cs.outlineVariant.withOpacity(0.55))
                      : BorderSide.none,
                ),
              ),
              child: child,
            ),
          );
        }

        Widget textCell({
          required String text,
          required double width,
          required double height,
          required TextStyle? style,
          required TextAlign align,
          int maxLines = 1,
          TextOverflow overflow = TextOverflow.ellipsis,
          Color? bg,
          bool boldEdge = false,
          Key? key,
        }) {
          final alignment = align == TextAlign.center
              ? Alignment.center
              : align == TextAlign.end
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart;
          return box(
            key: key,
            width: width,
            height: height,
            bg: bg,
            boldEdge: boldEdge,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: hPad,
                vertical: vPad,
              ),
              child: Align(
                alignment: alignment,
                child: Text(
                  text,
                  style: style,
                  textAlign: align,
                  maxLines: maxLines,
                  overflow: overflow,
                ),
              ),
            ),
          );
        }

        Widget heatCell(
          SellInReturnsCell? cell,
          double height, {
          TextStyle? style,
        }) {
          final raw = rawOf(cell);
          final t = (raw == null || maxRet <= 0)
              ? 0.0
              : (raw / maxRet).clamp(0.0, 1.0);
          final bg = (raw == null || raw <= 0)
              ? cs.surface
              : Color.lerp(
                  cs.surface,
                  status.warningContainer.withOpacity(0.9),
                  t,
                );
          final label = fitValue(fmt(cell), style ?? bodyStyle, valueW);
          return Padding(
            padding: const EdgeInsets.all(cellGap / 2),
            child: SizedBox(
              width: monthW - cellGap,
              height: height - cellGap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.25),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: style ?? bodyStyle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ),
          );
        }

        Widget monthHeader(int m) {
          final label = (m >= 1 && m < monthLabelsAr.length)
              ? monthLabelsAr[m]
              : '$m';
          return Padding(
            padding: const EdgeInsets.all(cellGap / 2),
            child: SizedBox(
              width: monthW - cellGap,
              height: headerH - cellGap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.45),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.25),
                  ),
                ),
                child: Center(
                  child: TestSemantics(
                    identifier: 'returns-month-col-$m',
                    label: label,
                    child: Text(
                      label,
                      style: headerStyle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget monthsRow({
          required double height,
          required Key key,
          bool isHeader = false,
          SellInReturnsBranchRow? branch,
          bool isTotals = false,
        }) {
          return SizedBox(
            key: key,
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in months)
                  if (isHeader)
                    monthHeader(m)
                  else if (isTotals)
                    heatCell(
                      columnTotals[m],
                      height,
                      style: boldStyle,
                    )
                  else
                    heatCell(
                      branch!.byMonth[m],
                      height,
                    ),
              ],
            ),
          );
        }

        final headerBg = cs.surfaceContainerHighest.withOpacity(0.45);
        final totalsBg = cs.surfaceContainerHighest.withOpacity(0.5);

        final pinnedStart = SizedBox(
          width: branchW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textCell(
                key: branchHeaderKey,
                text: 'الفرع',
                width: branchW,
                height: headerH,
                style: headerStyle,
                align: TextAlign.center,
                maxLines: 2,
                bg: headerBg,
                boldEdge: true,
              ),
              for (var i = 0; i < branches.length; i++)
                textCell(
                  key: branchCellKey(branches[i].branchKey),
                  text: labelOf(branches[i]),
                  width: branchW,
                  height: rowHeights[i],
                  style: bodyStyle,
                  align: TextAlign.center,
                  maxLines: 3,
                  boldEdge: true,
                ),
              textCell(
                text: 'الإجمالي',
                width: branchW,
                height: totalsH,
                style: boldStyle,
                align: TextAlign.center,
                bg: totalsBg,
                boldEdge: true,
              ),
            ],
          ),
        );

        final pinnedEnd = SizedBox(
          width: totalW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textCell(
                key: totalHeaderKey,
                text: 'الإجمالي',
                width: totalW,
                height: headerH,
                style: headerStyle,
                align: TextAlign.center,
                bg: headerBg,
                boldEdge: true,
              ),
              for (var i = 0; i < branches.length; i++)
                textCell(
                  key: totalCellKey(branches[i].branchKey),
                  text: fitValue(
                    fmt(branches[i].total),
                    boldStyle,
                    totalInnerW,
                  ),
                  width: totalW,
                  height: rowHeights[i],
                  style: boldStyle,
                  align: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  boldEdge: true,
                ),
              textCell(
                text: fitValue(fmt(grandTotal), boldStyle, totalInnerW),
                width: totalW,
                height: totalsH,
                style: boldStyle,
                align: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.clip,
                bg: totalsBg,
                boldEdge: true,
              ),
            ],
          ),
        );

        final monthsStrip = Column(
          key: const ValueKey('returns-matrix-months-strip'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            monthsRow(height: headerH, key: headerRowKey, isHeader: true),
            for (var i = 0; i < branches.length; i++)
              monthsRow(
                height: rowHeights[i],
                key: monthsRowKey(branches[i].branchKey),
                branch: branches[i],
              ),
            monthsRow(height: totalsH, key: totalsRowKey, isTotals: true),
          ],
        );

        return TableScrollContainer(
          showControls: false,
          showSwipeHint: false,
          pinnedStart: pinnedStart,
          pinnedEnd: pinnedEnd,
          child: monthsStrip,
        );
      },
    );
  }
}
