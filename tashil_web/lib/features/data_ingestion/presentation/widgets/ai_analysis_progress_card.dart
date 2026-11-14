import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_chip_surface.dart';

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

  /// Short status chip + description under it (Sell-Out / TM / Compare pattern).
  static (String, String) stagedStatusParts() =>
      ('معاينة', 'لم تُحفظ بعد');

  /// Short confidence chip + percentage description. Null when not AI-mapped.
  static (String, String)? confidenceStatusParts(IngestionResultModel result) {
    if (!result.usedAiMapping) return null;
    final conf = result.mappingConfidence > 0
        ? result.mappingConfidence
        : result.confidenceScore;
    if (conf <= 0) return null;
    return ('ثقة', '${(conf * 100).toStringAsFixed(1)}%');
  }

  /// Arabic branch-normalization summary from payload.branch_norm.summary_ar.
  static String? branchNormLabel(IngestionResultModel result) {
    final text = result.branchNormSummaryAr.trim();
    if (text.isEmpty) return null;
    return text;
  }

  /// Arabic totals-difference explanation from payload.validation.explanation_ar.
  static String? totalsExplanationLabel(IngestionResultModel result) {
    final text = result.validationExplanationAr.trim();
    if (text.isEmpty) return null;
    return text;
  }

  static String? validationStatusLabel(IngestionResultModel result) {
    switch (result.validationStatus) {
      case 'flagged':
        return 'تنبيه على الإجماليات';
      case 'rejected':
        return 'رفض بسبب الإجماليات';
      case 'ok':
        return result.validationExplanationAr.trim().isEmpty
            ? null
            : 'الإجماليات متطابقة';
      default:
        return null;
    }
  }

  /// Arabic human-approval banner copy (Phase A7 guardrails).
  static String? humanApprovalBanner(IngestionResultModel result) {
    if (!result.needsHumanApproval) return null;
    if (result.guardrailArabicSummary.trim().isNotEmpty) {
      return result.guardrailArabicSummary.trim();
    }
    return 'يلزم الاعتماد البشري قبل الحفظ النهائي';
  }

  /// Compact Arabic success-metrics line for the review card.
  static String successMetricsLine(IngestionResultModel result) {
    final parts = <String>[
      if (result.guardrailSchemaValid)
        'المخطط سليم'
      else if (result.usedAiMapping)
        'المخطط مرفوض',
      if (result.guardrailPiiMinimized) 'تقليل البيانات الشخصية',
      if (result.guardrailPerCallLogged)
        'تم تسجيل الاستدعاء'
      else
        'بدون استدعاء ذكاء اصطناعي',
      if (result.needsHumanApproval) 'بانتظار الاعتماد',
      if (result.branchNormSummaryAr.trim().isNotEmpty) 'توحيد أسماء الفروع',
      if (result.branchNormChanged > 0) '${result.branchNormChanged} فرع وُحِّد',
    ];
    return parts.join(' • ');
  }

  /// Stat value honesty: never advertise a fake measured 0 for revenue / share.
  static String revenueStatValue(IngestionResultModel result) =>
      result.totalRevenue > 0
          ? CurrencyFormatter.formatCompactEGP(result.totalRevenue)
          : '—';

  static String? marketShareStatValue(IngestionResultModel result) =>
      result.tenantMarketSharePct > 0
          ? '${result.tenantMarketSharePct.toStringAsFixed(2)}%'
          : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = M3StatusColors.of(context);

    if (!isAnalyzing && result == null) {
      return const SizedBox.shrink();
    }

    final confidenceParts =
        result == null ? null : confidenceStatusParts(result!);

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
                // Constrained so long honest mapping_source labels wrap instead of overflowing.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary.withOpacity(0.12),
                          borderRadius: M3Shape.radiusSm,
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: colorScheme.tertiary,
                          size: 22.0,
                        ),
                      ),
                      M3Spacing.gapSM,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'محرك الاستيعاب الذكي للبيانات',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              statusSubtitle(
                                  isAnalyzing: isAnalyzing, result: result),
                              softWrap: true,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (result != null)
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (result!.isStaged)
                        _statusChipWithDesc(
                          key: const ValueKey('upload_status_staged_chip'),
                          shortLabel: stagedStatusParts().$1,
                          description: stagedStatusParts().$2,
                          bg: status.warningContainer,
                          fg: status.onWarningContainer,
                          icon: Icons.pending_actions_rounded,
                          theme: theme,
                        ),
                      if (confidenceParts != null)
                        _statusChipWithDesc(
                          key: const ValueKey('upload_status_confidence_chip'),
                          shortLabel: confidenceParts.$1,
                          description: confidenceParts.$2,
                          bg: status.successContainer,
                          fg: status.onSuccessContainer,
                          theme: theme,
                        ),
                    ],
                  ),
              ],
            ),

            M3Spacing.gapMD,

            if (result != null && humanApprovalBanner(result!) != null) ...[
              Container(
                width: double.infinity,
                padding: M3Spacing.pSm,
                decoration: BoxDecoration(
                  color: status.warningContainer.withOpacity(0.55),
                  borderRadius: M3Shape.radiusMd,
                  border: Border.all(
                      color: status.warning.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      humanApprovalBanner(result!)!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: status.onWarningContainer,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      successMetricsLine(result!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (result!.guardrailReasonsAr.isNotEmpty) ...[
                      const SizedBox(height: 6.0),
                      ...result!.guardrailReasonsAr.take(3).map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: Text(
                                '• $r',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: status.onWarningContainer,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
              M3Spacing.gapMD,
            ],

            if (isAnalyzing) ...[
              const LinearProgressIndicator(),
              M3Spacing.gapMD,
              _buildStageItem(
                  '1. استخراج المجموعات الرئيسية والموردين المنافسين والباركود الكامل',
                  true,
                  true,
                  status),
              _buildStageItem(
                  '2. اكتشاف وإنشاء الفروع تلقائياً (سموحة، جاردينيا، هانوفيل، إلخ)',
                  true,
                  false,
                  status),
              _buildStageItem(
                  '3. استنتاج سعر البيع وسعر المنتج (RRP) والحصة السوقية بالذكاء الاصطناعي',
                  false,
                  false,
                  status),
              _buildStageItem(
                  '4. التوزيع المباشر على الفروع والتحميل في Google BigQuery & Firestore',
                  false,
                  false,
                  status),
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
                    _buildStatCol('السلسلة المكتشفة',
                        result!.retailerDetected.toUpperCase(),
                        colorScheme.primary),
                    _buildStatCol(
                        'إجمالي السجلات', '${result!.totalRows} صف', null),
                    _buildStatCol('السجلات الصالحة', '${result!.validRows} صف',
                        status.success),
                    _buildStatCol(
                        'الفروع المنشأة تلقائياً',
                        '${result!.autoCreatedStoresCount} فرع',
                        colorScheme.primary),
                    if (result!.competitorsDetected > 0)
                      _buildStatCol('الموردون المنافسون',
                          '${result!.competitorsDetected} مورد',
                          colorScheme.tertiary),
                    if (marketShareStatValue(result!) != null)
                      _buildStatCol('حصة أديكو السوقية',
                          marketShareStatValue(result!)!, status.success),
                    _buildStatCol('الشذوذ المكتشف',
                        '${result!.anomalyRows} ملاحظة', status.warning),
                    _buildStatCol('إجمالي المبيعات', revenueStatValue(result!),
                        colorScheme.primary),
                  ],
                ),
              ),
              if (result!.detectedSheets.isNotEmpty ||
                  result!.sheetsProcessed.isNotEmpty) ...[
                M3Spacing.gapMD,
                Container(
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withOpacity(0.25),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(
                        color: colorScheme.secondary.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_rounded,
                              size: 18.0, color: colorScheme.secondary),
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
                          M3ChipSurface(
                            color: colorScheme.surface,
                            child: Text(
                              result!.usedAiMapping
                                  ? 'ذكاء اصطناعي'
                                  : 'قواعد قراءة',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: status.success,
                                fontWeight: FontWeight.bold,
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
                          final revenueBit = sh.totalRevenue > 0
                              ? ' • ${CurrencyFormatter.formatCompactEGP(sh.totalRevenue)}'
                              : (isHidden ? ' • مخفي' : '');
                          return M3ChipSurface(
                            color: isHidden
                                ? colorScheme.surfaceContainerHighest
                                    .withOpacity(0.5)
                                : colorScheme.surface,
                            borderColor: isHidden
                                ? colorScheme.outlineVariant.withOpacity(0.4)
                                : colorScheme.secondary.withOpacity(0.4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isHidden
                                      ? Icons.visibility_off_rounded
                                      : Icons.tab_rounded,
                                  size: 13.0,
                                  color: isHidden
                                      ? colorScheme.onSurfaceVariant
                                      : colorScheme.secondary,
                                ),
                                const SizedBox(width: 4.0),
                                Text(
                                  sh.name + revenueBit,
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
              if (totalsExplanationLabel(result!) != null) ...[
                M3Spacing.gapMD,
                Container(
                  width: double.infinity,
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: result!.validationStatus == 'rejected'
                        ? colorScheme.errorContainer.withOpacity(0.35)
                        : colorScheme.tertiaryContainer.withOpacity(0.28),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(
                      color: result!.validationStatus == 'rejected'
                          ? colorScheme.error.withOpacity(0.45)
                          : colorScheme.tertiary.withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            result!.validationStatus == 'rejected'
                                ? Icons.error_outline_rounded
                                : Icons.calculate_rounded,
                            size: 18.0,
                            color: result!.validationStatus == 'rejected'
                                ? colorScheme.error
                                : colorScheme.tertiary,
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              validationStatusLabel(result!) ??
                                  'تفسير فرق الإجماليات',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: result!.validationStatus == 'rejected'
                                    ? colorScheme.error
                                    : colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        totalsExplanationLabel(result!)!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (branchNormLabel(result!) != null) ...[
                M3Spacing.gapMD,
                Container(
                  width: double.infinity,
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withOpacity(0.28),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(
                      color: colorScheme.secondary.withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 18.0,
                            color: colorScheme.secondary,
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              'توحيد أسماء الفروع',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        branchNormLabel(result!)!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (result!.discoveredBranches.isNotEmpty ||
                  result!.discoveredCategories.isNotEmpty) ...[
                M3Spacing.gapMD,
                Container(
                  padding: M3Spacing.pSm,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.22),
                    borderRadius: M3Shape.radiusMd,
                    border:
                        Border.all(color: colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.store_mall_directory_rounded,
                              size: 18.0, color: colorScheme.primary),
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
                        children: () {
                          final rawNames = result!.discoveredBranches
                              .map((b) =>
                                  (b['branch_name'] ?? b['id'] ?? '').toString())
                              .toList();
                          final labels =
                              displayNamesWithoutSharedPrefix(rawNames);
                          return result!.discoveredBranches.take(18).map((b) {
                            final name = labels[(b['branch_name'] ??
                                        b['id'] ??
                                        '')
                                    .toString()] ??
                                (b['branch_name'] ?? b['id'] ?? '').toString();
                            return M3ChipSurface(
                              color: colorScheme.surface,
                              borderColor: colorScheme.outlineVariant,
                              child: Text(
                                name,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList();
                        }(),
                      ),
                      if (result!.discoveredCategories.isNotEmpty) ...[
                        M3Spacing.gapSM,
                        Row(
                          children: [
                            Icon(Icons.category_rounded,
                                size: 18.0, color: colorScheme.tertiary),
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
                          children: result!.discoveredCategories
                              .take(14)
                              .map((cat) {
                            return M3ChipSurface(
                              color: colorScheme.tertiaryContainer
                                  .withOpacity(0.55),
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

  /// Short M3ChipSurface + smaller description underneath (TM / Compare).
  static Widget _statusChipWithDesc({
    Key? key,
    required String shortLabel,
    required String description,
    required Color bg,
    required Color fg,
    required ThemeData theme,
    IconData? icon,
  }) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        M3ChipSurface(
          color: bg,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14.0, color: fg),
                const SizedBox(width: 4.0),
              ],
              Text(
                shortLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: M3Spacing.xxs),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildStageItem(
      String title, bool isDone, bool isInProgress, M3StatusColors status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isDone
                ? Icons.check_circle_rounded
                : (isInProgress
                    ? Icons.hourglass_top_rounded
                    : Icons.radio_button_unchecked_rounded),
            size: 16.0,
            color: isDone
                ? status.success
                : (isInProgress
                    ? status.warning
                    : Colors.grey),
          ),
          const SizedBox(width: 8.0),
          Text(title,
              style: const TextStyle(fontSize: M3FontSize.bodySmall)),
        ],
      ),
    );
  }

  Widget _buildStatCol(String title, String val, Color? valColor) {
    return Column(
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: M3FontSize.labelSmall, color: Colors.grey)),
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
