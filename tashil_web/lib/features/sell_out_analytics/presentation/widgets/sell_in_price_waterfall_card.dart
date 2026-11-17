import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/theme/m3_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_states.dart';

/// «من السعر الرسمي إلى الفاتورة» for the Sell-In tab, in two compact rows:
///  * إعدادات السلسلة: official − invoice discount − extra discount = expected net (chain terms
///    from Product Master › حاسبة الطلبيات, else invoice 10% / extra 0% / VAT 14%);
///  * الفعلي: − execution differences + unpriced = net supply (Excel Net V) + VAT = invoices.
/// The backend rounds every line so both rows add up to the piastre.
class SellInPriceWaterfallCard extends StatelessWidget {
  const SellInPriceWaterfallCard({
    super.key,
    required this.data,
    required this.chainLabel,
    this.loading = false,
  });

  final SellInExplorerResponse data;
  final String Function(String chain) chainLabel;
  final bool loading;

  /// Floor for a chip's width; a row also never squeezes a chip below its measured label/badge.
  static const double minChipWidth = 112.0;
  static const double _opWidth = 20.0;
  static const double _rowLabelWidth = 108.0;

  static String pct(double v, {int decimals = 2}) {
    final s = v.toStringAsFixed(decimals).replaceFirst(RegExp(r'\.?0+$'), '');
    return '${s == '-0' ? '0' : s}%';
  }

  /// Saved terms show exactly; a weighted average is rounded to one decimal (exact in the tooltip).
  String _badge(double v) => data.termsAveraged ? 'متوسط ${pct(v, decimals: 1)}' : pct(v);

  String? _breakdown(String Function(SellInChainTerms t) line) {
    if (data.chainTerms.isEmpty) return null;
    return [for (final t in data.chainTerms) '${chainLabel(t.chain)}: ${line(t)}${t.saved ? '' : ' (افتراضي)'}']
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = M3StatusColors.of(context).accents;
    final d = data;
    final expected = d.totalExpectedNetEgp;
    final net = d.totalNetExclVatEgp;
    final execution = d.totalExecutionDifferenceEgp;
    final averaged = d.termsAveraged;
    String full(double v) => CurrencyFormatter.formatEGP(v, showDecimals: true);
    String avgNote(String what) => averaged ? '\nمتوسط مرجّح بالسعر الرسمي — $what لكل سلسلة:' : '';

    final settings = <Object>[
      _Step(
        key: 'official',
        label: 'السعر الرسمي',
        value: d.totalOfficialListExclVatEgp,
        sub: 'القائمة × الكمية',
        accent: ac.neutral,
        tooltip: '${full(d.totalOfficialListExclVatEgp)}\nسعر الكرتونة الرسمي (بدون ضريبة) × كميات ملف Sell-In',
      ),
      _Op.minus,
      _Step(
        key: 'invoice',
        label: 'خصم الفاتورة',
        value: d.totalInvoiceDiscountEgp,
        badge: _badge(d.invoiceDiscountPct),
        sub: 'من السعر الرسمي',
        accent: ac.alert,
        tooltip: [
          '${full(d.totalInvoiceDiscountEgp)}${averaged ? ' • ${pct(d.invoiceDiscountPct)}' : ''}${avgNote('خصم الفاتورة')}',
          if (averaged) _breakdown((t) => pct(t.invoiceDiscountPct)),
        ].whereType<String>().join('\n'),
      ),
      _Op.minus,
      _Step(
        key: 'extra',
        label: 'خصم إضافي',
        value: d.totalExtraChainDiscountEgp,
        badge: _badge(d.extraDiscountPct),
        sub: 'بعد خصم الفاتورة',
        accent: ac.alert,
        tooltip: [
          '${full(d.totalExtraChainDiscountEgp)}${averaged ? ' • ${pct(d.extraDiscountPct)}' : ''}\nيُحسب على السعر بعد خصم الفاتورة${avgNote('الخصم الإضافي')}',
          if (averaged) _breakdown((t) => pct(t.extraDiscountPct)),
        ].whereType<String>().join('\n'),
      ),
      _Op.equals,
      _Step(
        key: 'expected',
        label: 'الصافي المتوقع',
        value: expected,
        sub: 'حسب إعدادات السلسلة',
        accent: cs.primary,
        tooltip: '${full(expected)}\nالسعر الرسمي × (1 − خصم الفاتورة) × (1 − الخصم الإضافي)',
      ),
    ];
    final actual = <Object>[
      _Op.minus,
      _Step(
        key: 'execution',
        label: 'فروق التنفيذ',
        value: execution,
        badge: expected != 0 ? pct(execution / expected * 100) : null,
        sub: execution < 0 ? 'أعلى من المتوقع' : 'عروض / انحراف سعر',
        accent: ac.caution,
        tooltip: '${full(execution)}\nالصافي المتوقع − صافي الأصناف المسعّرة في الملف'
            '${execution < 0 ? '\nسالب: الفعلي أعلى من المتوقع' : ''}',
      ),
      _Op.plus,
      _Step(
        key: 'unpriced',
        label: 'بلا سعر رسمي',
        value: d.totalUnpricedNetEgp,
        sub: 'أصناف غير مطابقة',
        accent: ac.neutral,
        tooltip: '${full(d.totalUnpricedNetEgp)}\nصافي أصناف الملف بدون سعر في قائمة الأسعار',
      ),
      _Op.equals,
      _Step(
        key: 'net',
        label: 'صافي التوريد',
        value: net,
        sub: '${CurrencyFormatter.formatNumber(d.totalCases.round())} كرتونة',
        accent: cs.primary,
        emphasis: true,
        tooltip:
            '${full(net)}\n${CurrencyFormatter.formatNumber(d.totalUnitsPieces)} وحدة • بعد المرتجعات، قبل الضريبة',
      ),
      _Op.plus,
      _Step(
        key: 'vat',
        label: 'الضريبة',
        value: d.totalVat14Egp,
        badge: _badge(d.vatRatePct),
        sub: 'على صافي التوريد',
        accent: cs.secondary,
        tooltip: [
          '${full(d.totalVat14Egp)}${averaged ? ' • ${pct(d.vatRatePct)}' : ''}${avgNote('الضريبة')}',
          if (averaged) _breakdown((t) => pct(t.vatRatePct)),
        ].whereType<String>().join('\n'),
      ),
      _Op.equals,
      _Step(
        key: 'invoices',
        label: 'الفواتير',
        value: d.totalGrossInclVatEgp,
        sub: 'شامل الضريبة',
        accent: ac.tealStrong,
        emphasis: true,
        tooltip: full(d.totalGrossInclVatEgp),
      ),
    ];

    final scope = _scopeTag();
    return Container(
      key: const ValueKey('sellin_waterfall_strip'),
      padding: const EdgeInsets.all(M3Spacing.s12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.account_tree_rounded, size: 18, color: cs.primary),
              Text('من السعر الرسمي إلى الفاتورة',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
              if (scope != null)
                _Tag(
                  key: const ValueKey('sellin_waterfall_scope'),
                  text: scope,
                  bg: cs.secondaryContainer,
                  fg: cs.onSecondaryContainer,
                  tooltip: _breakdown((t) =>
                      'فاتورة ${pct(t.invoiceDiscountPct)} • إضافي ${pct(t.extraDiscountPct)} • ضريبة ${pct(t.vatRatePct)}'),
                ),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          _StepRow(
            key: const ValueKey('sellin_waterfall_row_settings'),
            rowLabel: 'إعدادات السلسلة',
            rowHint: 'حاسبة الطلبيات',
            items: settings,
            loading: loading,
          ),
          const SizedBox(height: M3Spacing.xs),
          _StepRow(
            key: const ValueKey('sellin_waterfall_row_actual'),
            rowLabel: 'الفعلي',
            rowHint: 'ملف Sell-In',
            items: actual,
            loading: loading,
          ),
        ],
      ),
    );
  }

  String? _scopeTag() {
    final terms = data.chainTerms;
    if (data.termsAveraged) return 'كل السلاسل • كل سلسلة بإعداداتها';
    if (terms.length != 1) return null;
    final t = terms.single;
    return '${chainLabel(t.chain)} • ${t.saved ? 'إعدادات محفوظة' : 'الافتراضي'}';
  }
}

enum _Op { minus, plus, equals }

class _Step {
  const _Step({
    required this.key,
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    this.badge,
    this.emphasis = false,
    this.tooltip,
  });

  final String key;
  final String label;
  final double value;
  final String sub;
  final Color accent;
  final String? badge;
  final bool emphasis;
  final String? tooltip;
}

class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.text, required this.bg, required this.fg, this.tooltip});

  final String text;
  final Color bg;
  final Color fg;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.s2),
      decoration: BoxDecoration(color: bg, borderRadius: M3Shape.radiusSm),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w700, color: fg)),
    );
    return tooltip == null ? tag : Tooltip(message: tooltip!, child: tag);
  }
}

/// One labelled row of chips joined by − / + / = icons. When a chip would be narrower than its
/// label + badge (or sub-line) the row wraps instead of ellipsizing them.
class _StepRow extends StatelessWidget {
  const _StepRow(
      {super.key, required this.rowLabel, required this.rowHint, required this.items, required this.loading});

  final String rowLabel;
  final String rowHint;
  final List<Object> items;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const opW = SellInPriceWaterfallCard._opWidth;
    final label = Container(
      width: SellInPriceWaterfallCard._rowLabelWidth,
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.xxs),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: M3Shape.radiusMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rowLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
          Text(rowHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: M3FontSize.labelSmall, color: cs.onSurfaceVariant)),
        ],
      ),
    );
    final steps = items.whereType<_Step>().length;
    final ops = items.length - steps;
    // Row 1 starts with a chip, row 2 with an operator; the spacer keeps their chips aligned.
    final lead = items.first is _Op ? 0.0 : opW;
    final minChipWidth = items
        .whereType<_Step>()
        .fold(SellInPriceWaterfallCard.minChipWidth, (double m, s) => math.max(m, _StepChip.minWidth(context, s)));
    return LayoutBuilder(builder: (context, c) {
      final avail = c.maxWidth - SellInPriceWaterfallCard._rowLabelWidth - M3Spacing.xxs - lead;
      final fits = (avail - ops * opW) / steps >= minChipWidth;
      if (fits) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(width: M3Spacing.xxs),
              if (lead > 0) SizedBox(width: lead),
              for (final it in items)
                if (it is _Op) _OpIcon(it) else Expanded(child: _StepChip(it as _Step, loading: loading)),
            ],
          ),
        );
      }
      // Narrow: label on top, chips wrap at the minimum width (an operator stays before its chip).
      final perLine = ((c.maxWidth + opW) / (minChipWidth + opW)).floor().clamp(1, steps);
      final chipW = (c.maxWidth - perLine * opW) / perLine;
      final children = <Widget>[];
      _Op? pending;
      for (final it in items) {
        if (it is _Op) {
          pending = it;
          continue;
        }
        children.add(Row(mainAxisSize: MainAxisSize.min, children: [
          pending != null ? _OpIcon(pending) : const SizedBox(width: opW),
          SizedBox(width: chipW, child: _StepChip(it as _Step, loading: loading)),
        ]));
        pending = null;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: M3Spacing.xxs),
          Wrap(runSpacing: M3Spacing.xxs, children: children),
        ],
      );
    });
  }
}

class _OpIcon extends StatelessWidget {
  const _OpIcon(this.op);

  final _Op op;

  @override
  Widget build(BuildContext context) {
    final icon = switch (op) {
      _Op.minus => Icons.remove_rounded,
      _Op.plus => Icons.add_rounded,
      _Op.equals => Icons.drag_handle_rounded,
    };
    return SizedBox(
      width: SellInPriceWaterfallCard._opWidth,
      child: Center(child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip(this.s, {required this.loading});

  final _Step s;
  final bool loading;

  static const double _padH = M3Spacing.xxs + M3Spacing.s2;

  static TextStyle? _labelStyle(ThemeData t) => t.textTheme.labelMedium
      ?.copyWith(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w700, color: t.colorScheme.onSurfaceVariant);

  static TextStyle? _badgeStyle(ThemeData t, Color accent) =>
      t.textTheme.labelSmall?.copyWith(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w800, color: accent);

  static TextStyle? _subStyle(ThemeData t) =>
      t.textTheme.bodySmall?.copyWith(fontSize: M3FontSize.labelSmall, color: t.colorScheme.onSurfaceVariant);

  /// Width the chip needs so its label + badge and sub-line fit on one line (the amount scales down).
  static double minWidth(BuildContext context, _Step s) {
    final theme = Theme.of(context);
    double w(String text, TextStyle? style) => (TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout())
            .width;
    var head = w(s.label, _labelStyle(theme));
    if (s.badge != null) head += M3Spacing.xxs + w(s.badge!, _badgeStyle(theme, s.accent)) + 2 * M3Spacing.xxs;
    // Padding, 1dp borders and a little slack for sub-pixel layout.
    return math.max(head, w(s.sub, _subStyle(theme))) + 2 * _padH + 2 + M3Spacing.xxs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chip = Container(
      key: ValueKey('sellin_waterfall_${s.key}'),
      padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: M3Spacing.xxs + M3Spacing.s2),
      decoration: BoxDecoration(
        color: s.emphasis ? s.accent.withOpacity(0.08) : cs.surface,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: s.accent.withOpacity(s.emphasis ? 0.6 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Flexible(
              child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _labelStyle(theme)),
            ),
            if (s.badge != null) ...[
              const SizedBox(width: M3Spacing.xxs),
              Container(
                key: ValueKey('sellin_waterfall_${s.key}_badge'),
                padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xxs),
                decoration: BoxDecoration(color: s.accent.withOpacity(0.12), borderRadius: M3Shape.radiusXs),
                child: Text(s.badge!, maxLines: 1, style: _badgeStyle(theme, s.accent)),
              ),
            ],
          ]),
          if (loading) ...[
            const SizedBox(height: M3Spacing.xxs),
            const M3SkeletonBox(key: ValueKey('sell_in_waterfall_skeleton'), width: 72.0, height: 16.0),
            const SizedBox(height: M3Spacing.xxs),
          ] else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                CurrencyFormatter.formatCompactEGP(s.value),
                key: ValueKey('sellin_waterfall_${s.key}_value'),
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: s.emphasis ? M3FontSize.bodyLarge : M3FontSize.bodyMedium,
                    fontWeight: FontWeight.w900,
                    color: s.accent),
              ),
            ),
          Text(s.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _subStyle(theme)),
        ],
      ),
    );
    return s.tooltip == null ? chip : Tooltip(message: s.tooltip!, child: chip);
  }
}
