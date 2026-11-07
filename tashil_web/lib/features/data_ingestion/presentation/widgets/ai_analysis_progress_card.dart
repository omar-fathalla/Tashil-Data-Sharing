import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';

/// AiAnalysisProgressCard displays real-time ingestion execution stages
/// and highlights Gemini 3.8 Flash semantic structured extraction.
class AiAnalysisProgressCard extends StatelessWidget {
  final bool isAnalyzing;
  final IngestionResultModel? result;

  const AiAnalysisProgressCard({
    super.key,
    required this.isAnalyzing,
    required this.result,
  });

  static String statusSubtitle({
    required bool isAnalyzing,
    IngestionResultModel? result,
  }) {
    if (isAnalyzing) {
      return 'جارٍ فحص الملف واستخراج الفروع والأصناف والأسعار تلقائياً...';
    }
    if (result == null) return '';
    final sourceLabel = mappingSourceLabel(result);
    if (result.isStaged) {
      return '$sourceLabel • بانتظار المراجعة والاعتماد';
    }
    return '$sourceLabel • اكتملت المعالجة والتحميل في Google BigQuery بنجاح';
  }

  /// Honest Arabic label from mapping_source (never claims AI for deterministic/mock).
  static String mappingSourceLabel(IngestionResultModel result) {
    switch (result.mappingSource) {
      case 'ai':
        final model = result.aiModelUsed.trim();
        return model.isEmpty
            ? 'تم الاستخراج بمساعدة الذكاء الاصطناعي'
            : 'تم الاستخراج بالذكاء الاصطناعي ($model)';
      case 'cache':
        return 'تم الاستخراج بخطة أعمدة محفوظة (بدون استدعاء جديد للذكاء الاصطناعي)';
      case 'mock':
        return 'معاينة تجريبية (بيانات محاكاة — ليست من الملف)';
      case 'deterministic':
        return 'تم الاستخراج بقواعد القراءة المحددة (بدون ذكاء اصطناعي)';
      default:
        if (result.aiModelUsed.trim().isNotEmpty) {
          return 'تم الاستخراج (${result.aiModelUsed.trim()})';
        }
        return 'تم تحليل الملف واستخراج السجلات';
    }
  }

  static String? aiConfidenceLabel(IngestionResultModel result) {
    if (!result.usedAiMapping) return null;
    final conf = result.mappingConfidence > 0
        ? result.mappingConfidence
        : result.confidenceScore;
    if (conf <= 0) return null;
    return 'درجة ثقة الذكاء الاصطناعي: ${(conf * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isAnalyzing && result == null) {
      return const SizedBox.shrink();
    }

    final confidenceText = result == null ? null : aiConfidenceLabel(result!);

    return Card(
      child: Padding(
        padding: M3Spacing.pLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: M3Spacing.md,
              runSpacing: M3Spacing.sm,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.12),
                        borderRadius: M3Shape.radiusSm,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.purple,
                        size: 22.0,
                      ),
                    ),
                    M3Spacing.gapSM,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'محرك الاستيعاب الذكي للبيانات',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          statusSubtitle(isAnalyzing: isAnalyzing, result: result),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (result != null)
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (result!.isStaged)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.18),
                            borderRadius: M3Shape.radiusLg,
                            border: Border.all(color: Colors.amber.shade700.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pending_actions_rounded, size: 14.0, color: Colors.amber.shade900),
                              const SizedBox(width: 4.0),
                              Text(
                                'معاينة قيد المراجعة (لم تُحفظ بعد)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (confidenceText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: M3Shape.radiusLg,
                          ),
                          child: Text(
                            confidenceText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),

              ],
            ),

            M3Spacing.gapMD,

            if (isAnalyzing) ...[
              const LinearProgressIndicator(),
              M3Spacing.gapMD,
              _buildStageItem('1. استخراج المجموعات الرئيسية والموردين المنافسين والباركود الكامل', true, true),
              _buildStageItem('2. اكتشاف وإنشاء الفروع تلقائياً (سموحة، جاردينيا، هانوفيل، إلخ)', true, false),
              _buildStageItem('3. استنتاج سعر البيع وسعر المنتج (RRP) والحصة السوقية بالذكاء الاصطناعي', false, false),
              _buildStageItem('4. التوزيع المباشر على الفروع والتحميل في Google BigQuery & Firestore', false, false),
            ] else if (result != null) ...[
              // Summary Metrics Row
              Container(
                padding: M3Spacing.pSm,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Wrap(
                  spacing: M3Spacing.md,
                  runSpacing: M3Spacing.sm,
                  alignment: WrapAlignment.spaceAround,
                  children: [
                    _buildStatCol('السلسلة المكتشفة', result!.retailerDetected.toUpperCase(), colorScheme.primary),
                    _buildStatCol('إجمالي السجلات', '${result!.totalRows} صف', null),
                    _buildStatCol('السجلات الصالحة', '${result!.validRows} صف', Colors.green),
                    _buildStatCol('الفروع المنشأة تلقائياً', '${result!.autoCreatedStoresCount} فرع', colorScheme.primary),
                    if (result!.competitorsDetected > 0)
                      _buildStatCol('الموردون المنافسون', '${result!.competitorsDetected} مورد', colorScheme.tertiary),
                    if (result!.tenantMarketSharePct > 0)
                      _buildStatCol('حصة أديكو السوقية', '${result!.tenantMarketSharePct.toStringAsFixed(2)}%', Colors.green.shade800),
                    _buildStatCol('الشذوذ المكتشف', '${result!.anomalyRows} ملاحظة', Colors.amber.shade800),
                    _buildStatCol('إجمالي المبيعات', CurrencyFormatter.formatCompactEGP(result!.totalRevenue), colorScheme.primary),
                  ],
                ),
              ),
              if (result!.detectedSheets.isNotEmpty || result!.sheetsProcessed.isNotEmpty) ...[
                M3Spacing.gapMD,
                Container(
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withOpacity(0.25),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(color: colorScheme.secondary.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_rounded, size: 18.0, color: colorScheme.secondary),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              'التابات المكتشفة داخل ملف الإكسيل (${result!.sheetsDetectedCount > 0 ? result!.sheetsDetectedCount : (result!.detectedSheets.isNotEmpty ? result!.detectedSheets.length : result!.sheetsProcessed.length)} تابات):',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: M3Shape.radiusSm,
                            ),
                            child: Text(
                              result!.usedAiMapping
                                  ? 'استيعاب بمساعدة الذكاء الاصطناعي'
                                  : 'استيعاب بقواعد القراءة المحددة',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: M3FontSize.tiny,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 6.0,
                        children: (result!.detectedSheets.isNotEmpty
                                ? result!.detectedSheets
                                : result!.sheetsProcessed
                                    .map((s) => DiscoveredSheetInfoModel(
                                        name: s,
                                        state: 'visible',
                                        rowCount: 0,
                                        recordsCount: 0,
                                        totalRevenue: 0,
                                        totalUnits: 0))
                                    .toList())
                            .map((sh) {
                          final isHidden = sh.state.toLowerCase() == 'hidden';
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: isHidden
                                  ? colorScheme.surfaceContainerHighest.withOpacity(0.5)
                                  : colorScheme.surface,
                              borderRadius: M3Shape.radiusSm,
                              border: Border.all(
                                color: isHidden
                                    ? colorScheme.outlineVariant.withOpacity(0.4)
                                    : colorScheme.secondary.withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isHidden ? Icons.visibility_off_rounded : Icons.tab_rounded,
                                  size: 13.0,
                                  color: isHidden
                                      ? colorScheme.onSurfaceVariant
                                      : colorScheme.secondary,
                                ),
                                const SizedBox(width: 4.0),
                                Text(
                                  sh.name +
                                      (sh.totalRevenue > 0
                                          ? ' • ${CurrencyFormatter.formatCompactEGP(sh.totalRevenue)}'
                                          : (isHidden ? ' • مخفي' : '')),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isHidden
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              if (result!.discoveredBranches.isNotEmpty || result!.discoveredCategories.isNotEmpty) ...[
                M3Spacing.gapMD,
                Container(
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.22),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.store_mall_directory_rounded, size: 18.0, color: colorScheme.primary),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              'الفروع التي تم إنشاؤها وتوزيع المبيعات والكميات عليها تلقائياً (${result!.autoCreatedStoresCount} فرع):',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 6.0,
                        children: result!.discoveredBranches.take(18).map((b) {
                          final name = (b['branch_name'] ?? b['id'] ?? '').toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: M3Shape.radiusSm,
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            child: Text(
                              name,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (result!.discoveredCategories.isNotEmpty) ...[
                        M3Spacing.gapSM,
                        Row(
                          children: [
                            Icon(Icons.category_rounded, size: 18.0, color: colorScheme.tertiary),
                            const SizedBox(width: 6.0),
                            Expanded(
                              child: Text(
                                'المجموعات الرئيسية المستنتجة مع حساب سعر البيع وسعر المنتج (${result!.discoveredCategories.length} مجموعة):',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.tertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        Wrap(
                          spacing: 6.0,
                          runSpacing: 6.0,
                          children: result!.discoveredCategories.take(14).map((cat) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer.withOpacity(0.55),
                                borderRadius: M3Shape.radiusSm,
                              ),
                              child: Text(
                                cat,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStageItem(String title, bool isDone, bool isInProgress) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : (isInProgress ? Icons.hourglass_top_rounded : Icons.radio_button_unchecked_rounded),
            size: 16.0,
            color: isDone ? Colors.green : (isInProgress ? Colors.amber : Colors.grey),
          ),
          const SizedBox(width: 8.0),
          Text(title, style: const TextStyle(fontSize: M3FontSize.bodySmall)),
        ],
      ),
    );
  }

  Widget _buildStatCol(String title, String val, Color? valColor) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: M3FontSize.labelSmall, color: Colors.grey)),
        const SizedBox(height: 2.0),
        Text(
          val,
          style: TextStyle(
            fontSize: M3FontSize.bodyMedium,
            fontWeight: FontWeight.bold,
            color: valColor,
          ),
        ),
      ],
    );
  }
}
