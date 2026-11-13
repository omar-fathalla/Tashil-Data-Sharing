import 'package:flutter/material.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_card.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';

/// Phase C: shows the grounded Arabic monthly narrative from executive KPIs.
/// CI re-run after Mac test-flutter cancellation (gate treats cancelled as fail).
class MonthlySummaryCard extends StatelessWidget {
  final MonthlySummaryModel summary;

  const MonthlySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.narrativeAr.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sourceLabel = switch (summary.mappingSource) {
      'ai' => 'Gemini',
      'mock' => 'Mock',
      _ => 'محسوب',
    };

    return Semantics(
      identifier: 'executive-monthly-summary',
      label: 'الملخص الشهري',
      child: M3Card.outlined(
        key: const ValueKey('executive_monthly_summary'),
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(AppIcons.insights, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                const Expanded(
                  child: M3SectionTitle('الملخص الشهري التلقائي'),
                ),
                Text(
                  '$sourceLabel · ${(summary.confidence * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            M3Spacing.gapSM,
            Text(
              summary.narrativeAr,
              textDirection: TextDirection.rtl,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            if (!summary.grounded) ...[
              M3Spacing.gapSM,
              Text(
                'تنبيه: النص غير موثّق بالكامل مقابل أرقام اللوحة.',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
