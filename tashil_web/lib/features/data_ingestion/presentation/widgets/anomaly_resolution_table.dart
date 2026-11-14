import 'package:flutter/material.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/widgets/m3_chip_surface.dart';

/// AnomalyResolutionTable lists anomalies detected and resolved by Gemini 3.8 Flash.
class AnomalyResolutionTable extends StatelessWidget {
  final List<dynamic> anomalies;

  const AnomalyResolutionTable({
    super.key,
    required this.anomalies,
  });

  /// Short chip label + description under it (Sell-Out / TM / Compare pattern).
  static (String, String) issueParts(String issueType, int rowNum) {
    switch (issueType) {
      case 'invalid_barcode':
        return ('باركود', 'صف $rowNum • باركود غير صالح');
      case 'unmapped_store':
        return ('فرع', 'صف $rowNum • فرع غير مربوط');
      case 'price_outlier':
        return ('سعر', 'صف $rowNum • شذوذ سعري');
      case 'missing_sku':
        return ('صنف', 'صف $rowNum • صنف مفقود');
      default:
        final short = issueType.isEmpty ? 'ملاحظة' : issueType.split('_').first;
        return (short, 'صف $rowNum • $issueType');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = M3StatusColors.of(context);

    if (anomalies.isEmpty) {
      return Card(
        child: Padding(
          padding: M3Spacing.pMd,
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  color: status.success, size: 20.0),
              M3Spacing.gapSM,
              Expanded(
                child: Text(
                  'لم يتم رصد أي شذوذ في البيانات؛ جميع السجلات مطابقة للمعايير القياسية بنسبة 100%.',
                  maxLines: 3,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_folder_rounded,
                    color: status.warning, size: 20.0),
                M3Spacing.gapSM,
                Expanded(
                  child: Text(
                    'تقرير المعالجة الدلالية وكشف الشذوذ (Semantic Resolutions)',
                    maxLines: 3,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'سجل الحالات التي تم فحصها وتصحيحها تلقائياً بواسطة وكيل الذكاء الاصطناعي',
              maxLines: 3,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            M3Spacing.gapMD,
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: anomalies.length,
              separatorBuilder: (_, __) => const Divider(height: 12.0),
              itemBuilder: (context, index) {
                final a = anomalies[index] as Map<String, dynamic>;
                final rowNum = (a['row_number'] as num?)?.toInt() ?? (index + 1);
                final issueType = a['issue_type']?.toString() ?? 'issue';
                final desc = a['description']?.toString() ?? '';
                final (shortLabel, chipDesc) = issueParts(issueType, rowNum);

                final Color badgeBg;
                final Color badgeFg;
                if (issueType == 'invalid_barcode') {
                  badgeBg = colorScheme.tertiaryContainer;
                  badgeFg = colorScheme.onTertiaryContainer;
                } else if (issueType == 'unmapped_store') {
                  badgeBg = status.infoContainer;
                  badgeFg = status.onInfoContainer;
                } else {
                  badgeBg = status.warningContainer;
                  badgeFg = status.onWarningContainer;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      key: ValueKey('anomaly_chip_$index'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        M3ChipSurface(
                          color: badgeBg,
                          child: Text(
                            shortLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeFg,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: M3Spacing.xxs),
                        Text(
                          chipDesc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    M3Spacing.gapSM,
                    Expanded(
                      child: Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
