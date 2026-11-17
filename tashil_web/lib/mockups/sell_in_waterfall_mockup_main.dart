// MOCKUP ONLY (scratch branch, not wired into the app). Run with:
//   flutter run -d web-server -t lib/mockups/sell_in_waterfall_mockup_main.dart
// Compact two-row redesign of the Sell-In card «من السعر الرسمي إلى الفاتورة».
// Row 1 = what the chain's saved terms (Product Master → حاسبة الطلبيات) say the net should be.
// Row 2 = what the uploaded Sell-In file actually invoiced, then VAT and the invoice total.
// Values are the example numbers from the live screen; «المتوقع» and «بلا سعر رسمي» are derived.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/m3_shape.dart';
import '../core/theme/m3_spacing.dart';
import '../core/theme/m3_status_colors.dart';
import '../core/theme/m3_typography.dart';
import '../core/utils/currency_formatter.dart';

void main() => runApp(const _MockupApp());

class _MockupApp extends StatelessWidget {
  const _MockupApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Directionality(textDirection: TextDirection.rtl, child: _MockupPage()),
    );
  }
}

/// Example values (EGP) from the live Sell-In screen.
class _Example {
  static const official = 166.37e6;
  static const invoicePct = 10.0;
  static const invoiceDisc = 16.64e6;
  static const extraPct = 0.0;
  static const extraDisc = 0.0;
  static const expected = official - invoiceDisc - extraDisc; // 149.73M (derived)
  static const otherDiff = 20.47e6;
  static const net = 133.19e6;
  static const unpriced = net - (expected - otherDiff); // 3.93M (derived)
  static const vatPct = 14.0;
  static const vat = 18.65e6;
  static const invoices = 151.84e6;
  static const cartons = 221171;
  static const units = 1624921;
}

class _MockupPage extends StatelessWidget {
  const _MockupPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        children: [
          Container(
            width: 248,
            color: cs.surfaceContainerLow,
            alignment: Alignment.topCenter,
            padding: M3Spacing.pSm,
            child: Text('الشريط الجانبي', style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(M3Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sell-In — مقترح تصميم بطاقة «من السعر الرسمي إلى الفاتورة»',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  M3Spacing.gapSM,
                  const SellInWaterfallCompact(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Op { minus, plus, equals }

class _Step {
  final String label;
  final double value;
  final String? badge;
  final String sub;
  final Color accent;
  final bool emphasis;
  final String? tooltip;
  const _Step(this.label, this.value, this.sub, this.accent,
      {this.badge, this.emphasis = false, this.tooltip});
}

class SellInWaterfallCompact extends StatelessWidget {
  const SellInWaterfallCompact({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = M3StatusColors.of(context).accents;
    String pct(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%';
    const otherPct = _Example.otherDiff / _Example.official * 100;

    final template = <Object>[
      _Step('السعر الرسمي', _Example.official, 'قائمة الأسعار × الكمية', ac.neutral,
          tooltip: 'سعر الكرتونة الرسمي (Product Master) × الكميات في ملف Sell-In'),
      _Op.minus,
      _Step('خصم الفاتورة', _Example.invoiceDisc, 'من السعر الرسمي', ac.alert, badge: pct(_Example.invoicePct)),
      _Op.minus,
      _Step('خصم إضافي', _Example.extraDisc, 'بعد خصم الفاتورة', ac.alert, badge: pct(_Example.extraPct)),
      _Op.equals,
      _Step('الصافي المتوقع', _Example.expected, 'حسب إعدادات السلسلة', cs.primary,
          tooltip: 'السعر الرسمي × (1 − خصم الفاتورة) × (1 − الخصم الإضافي)'),
    ];
    final actual = <Object>[
      _Op.minus,
      _Step('فروق التنفيذ', _Example.otherDiff, 'عروض / انحراف سعر', ac.caution, badge: pct(otherPct),
          tooltip: 'الصافي المتوقع − صافي الأصناف المسعّرة في الملف'),
      _Op.plus,
      _Step('بلا سعر رسمي', _Example.unpriced, 'أصناف غير مطابقة', ac.neutral,
          tooltip: 'صافي أصناف في الملف بدون سعر في قائمة الأسعار'),
      _Op.equals,
      _Step('صافي التوريد', _Example.net, '${CurrencyFormatter.formatNumber(_Example.cartons)} كرتونة', cs.primary,
          emphasis: true, tooltip: '${CurrencyFormatter.formatNumber(_Example.units)} وحدة • قبل الضريبة'),
      _Op.plus,
      _Step('الضريبة', _Example.vat, 'على صافي التوريد', ac.purple, badge: pct(_Example.vatPct)),
      _Op.equals,
      _Step('الفواتير', _Example.invoices, 'شامل الضريبة', ac.tealStrong, emphasis: true),
    ];

    return Container(
      padding: const EdgeInsets.all(M3Spacing.s12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 18, color: cs.primary),
              const SizedBox(width: M3Spacing.xs),
              Text('من السعر الرسمي إلى الفاتورة',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(width: M3Spacing.xs),
              _Tag('كل السلاسل • كل سلسلة بإعداداتها', cs.secondaryContainer, cs.onSecondaryContainer),
              const Spacer(),
              _Tag('قيم توضيحية', ac.highlightSurface, ac.cautionStrong, icon: Icons.science_outlined),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          _StepRow(rowLabel: 'إعدادات السلسلة', rowHint: 'حاسبة الطلبيات', items: template),
          const SizedBox(height: M3Spacing.xs),
          _StepRow(rowLabel: 'الفعلي', rowHint: 'ملف Sell-In', items: actual),
          const SizedBox(height: M3Spacing.xs),
          Text(
            'الخصم الإضافي يُحسب بعد خصم الفاتورة • الضريبة على صافي التوريد الفعلي • '
            'المتوقع و«بلا سعر رسمي» مشتقان من أرقام الشاشة الحالية',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: M3FontSize.labelSmall),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  const _Tag(this.text, this.bg, this.fg, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.s2),
      decoration: BoxDecoration(color: bg, borderRadius: M3Shape.radiusSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: M3Spacing.xxs)],
        Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String rowLabel;
  final String rowHint;
  final List<Object> items;
  const _StepRow({required this.rowLabel, required this.rowHint, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 104,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.xxs),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: M3Shape.radiusMd),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rowLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                  Text(rowHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: M3FontSize.tiny)),
                ],
              ),
            ),
          ),
          const SizedBox(width: M3Spacing.xxs),
          if (items.first is! _Op) const SizedBox(width: 20),
          for (final it in items)
            if (it is _Op) _OpIcon(it) else Expanded(child: _StepChip(it as _Step)),
        ],
      ),
    );
  }
}

class _OpIcon extends StatelessWidget {
  final _Op op;
  const _OpIcon(this.op);

  @override
  Widget build(BuildContext context) {
    final icon = switch (op) {
      _Op.minus => Icons.remove_rounded,
      _Op.plus => Icons.add_rounded,
      _Op.equals => Icons.drag_handle_rounded,
    };
    return SizedBox(
      width: 20,
      child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _StepChip extends StatelessWidget {
  final _Step s;
  const _StepChip(this.s);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: 6),
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
              child: Text(s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
            if (s.badge != null) ...[
              const SizedBox(width: M3Spacing.xxs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                decoration: BoxDecoration(color: s.accent.withOpacity(0.12), borderRadius: M3Shape.radiusXs),
                child: Text(s.badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: M3FontSize.tiny, fontWeight: FontWeight.w800, color: s.accent)),
              ),
            ],
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              s.value == 0 ? '0 ج.م' : CurrencyFormatter.formatCompactEGP(s.value),
              maxLines: 1,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: s.emphasis ? M3FontSize.bodyMediumLarge : M3FontSize.bodyMedium,
                  fontWeight: FontWeight.w900,
                  color: s.accent),
            ),
          ),
          Text(s.sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: M3FontSize.tiny)),
        ],
      ),
    );
    return s.tooltip == null ? chip : Tooltip(message: s.tooltip!, child: chip);
  }
}
