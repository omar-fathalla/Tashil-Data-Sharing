import 'package:flutter/material.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';

/// Compact AI top-3 competitor cards shown under spotlight KPI metrics.
/// Clicking a card selects it for head-to-head compare (no approve required).
class CompetitorAiPicksRow extends StatelessWidget {
  final bool loading;
  final List<CompetitorSkuComparisonModel> picks;
  final String? selectedBarcode;
  final ValueChanged<CompetitorSkuComparisonModel> onSelect;
  final String? emptyHintAr;

  const CompetitorAiPicksRow({
    super.key,
    required this.loading,
    required this.picks,
    required this.onSelect,
    this.selectedBarcode,
    this.emptyHintAr,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
            M3Spacing.gapXS,
            Expanded(
              child: Text(
                'اقتراحات الذكاء الاصطناعي (أعلى 3)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        M3Spacing.gapXS,
        Text(
          'اضغط على بطاقة لفتح المقارنة وجهاً لوجه. التعيينات المعتمدة من المالك لها الأولوية.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        M3Spacing.gapSM,
        if (loading)
          const _AiPicksSkeleton()
        else if (picks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyHintAr?.isNotEmpty == true
                  ? emptyHintAr!
                  : 'لا توجد اقتراحات متاحة لهذا الصنف',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < picks.length; i++) ...[
                        Expanded(
                          child: _AiPickCard(
                            competitor: picks[i],
                            isSelected: picks[i].barcode == selectedBarcode,
                            onTap: () => onSelect(picks[i]),
                          ),
                        ),
                        if (i < picks.length - 1) M3Spacing.gapSM,
                      ],
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < picks.length; i++) ...[
                    _AiPickCard(
                      competitor: picks[i],
                      isSelected: picks[i].barcode == selectedBarcode,
                      onTap: () => onSelect(picks[i]),
                    ),
                    if (i < picks.length - 1) M3Spacing.gapSM,
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _AiPickCard extends StatelessWidget {
  final CompetitorSkuComparisonModel competitor;
  final bool isSelected;
  final VoidCallback onTap;

  const _AiPickCard({
    required this.competitor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const accent = M3Palette.dangerAccent;

    return Material(
      color: isSelected ? accent.withValues(alpha: 0.08) : cs.surface,
      borderRadius: M3Shape.radiusLg,
      elevation: isSelected ? 2 : 0,
      child: InkWell(
        key: ValueKey('ai-pick-${competitor.barcode}'),
        borderRadius: M3Shape.radiusLg,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: isSelected
                  ? accent
                  : cs.outlineVariant.withValues(alpha: 0.7),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  M3ChipSurface(
                    color: accent.withValues(alpha: 0.12),
                    child: Text(
                      'اختيار AI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: M3FontSize.labelSmallPlus,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    competitor.packSizeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              M3Spacing.gapXS,
              Text(
                competitor.brand,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              Text(
                competitor.skuName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              M3Spacing.gapXS,
              Text(
                '${competitor.unitPrice.toStringAsFixed(1)} ج.م',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPicksSkeleton extends StatelessWidget {
  const _AiPicksSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget box() => Container(
          height: 96,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: M3Shape.radiusLg,
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            children: [
              Expanded(child: box()),
              M3Spacing.gapSM,
              Expanded(child: box()),
              M3Spacing.gapSM,
              Expanded(child: box()),
            ],
          );
        }
        return Column(
          children: [
            box(),
            M3Spacing.gapSM,
            box(),
            M3Spacing.gapSM,
            box(),
          ],
        );
      },
    );
  }
}
