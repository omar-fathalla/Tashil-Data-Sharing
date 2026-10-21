import 'package:flutter/material.dart';
import '../../../../core/theme/m3_spacing.dart';

/// AnomalyResolutionTable lists anomalies detected and resolved by Gemini 3.8 Flash.
class AnomalyResolutionTable extends StatelessWidget {
  final List<dynamic> anomalies;

  const AnomalyResolutionTable({
    super.key,
    required this.anomalies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (anomalies.isEmpty) {
      return Card(
        child: Padding(
          padding: M3Spacing.pMd,
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 20.0),
              M3Spacing.gapSM,
              Text(
                'لم يتم رصد أي شذوذ في البيانات؛ جميع السجلات مطابقة للمعايير القياسية بنسبة 100%.',
                style: theme.textTheme.bodyMedium,
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
                const Icon(Icons.rule_folder_rounded, color: Colors.amber, size: 20.0),
                M3Spacing.gapSM,
                Text(
                  'تقرير المعالجة الدلالية وكشف الشذوذ (Semantic Resolutions)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'سجل الحالات التي تم فحصها وتصحيحها تلقائياً بواسطة وكيل الذكاء الاصطناعي',
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
                final rowNum = a['row_number'] ?? (index + 1);
                final issueType = a['issue_type']?.toString() ?? 'issue';
                final desc = a['description']?.toString() ?? '';

                final badgeColor = issueType == 'invalid_barcode'
                    ? Colors.purple
                    : (issueType == 'unmapped_store' ? Colors.blue : Colors.amber.shade800);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Text(
                        'صف $rowNum: $issueType',
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    M3Spacing.gapSM,
                    Expanded(
                      child: Text(
                        desc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.0,
                        ),
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
