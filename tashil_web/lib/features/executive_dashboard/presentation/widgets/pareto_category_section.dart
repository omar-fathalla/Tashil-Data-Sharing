import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'chain_share_pie.dart';

/// ParetoCategorySection renders Competing Suppliers Market Share, Category Contribution bars,
/// and Pareto 80/20 Power SKUs with interactive category drilldown.
class ParetoCategorySection extends StatefulWidget {
  final List<CategoryContributionModel> categories;
  final List<ParetoSkuItemModel> paretoSkus;
  final List<SupplierShareModel> supplierShares;
  final double totalMarketRevenue;
  final double tenantMarketSharePct;
  final int competitorsCount;

  const ParetoCategorySection({
    super.key,
    required this.categories,
    required this.paretoSkus,
    this.supplierShares = const [],
    this.totalMarketRevenue = 0.0,
    this.tenantMarketSharePct = 0.0,
    this.competitorsCount = 0,
  });

  @override
  State<ParetoCategorySection> createState() => _ParetoCategorySectionState();
}

class _ParetoCategorySectionState extends State<ParetoCategorySection> {
  String? _selectedCategory;

  void _handleCategorySelect(String? cat) {
    setState(() {
      if (_selectedCategory == cat) {
        _selectedCategory = null;
      } else {
        _selectedCategory = cat;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty &&
        widget.paretoSkus.isEmpty &&
        widget.supplierShares.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.supplierShares.isNotEmpty) ...[
          _SupplierMarketShareCard(
            supplierShares: widget.supplierShares,
            totalMarketRevenue: widget.totalMarketRevenue,
            tenantMarketSharePct: widget.tenantMarketSharePct,
            competitorsCount: widget.competitorsCount,
          ),
          M3Spacing.gapMD,
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _CategoryContributionCard(
                      categories: widget.categories,
                      selectedCategory: _selectedCategory,
                      onCategorySelected: _handleCategorySelect,
                    ),
                  ),
                  M3Spacing.hGapSM,
                  Expanded(
                    flex: 7,
                    child: _ParetoPowerSkusCard(
                      paretoSkus: widget.paretoSkus,
                      selectedCategory: _selectedCategory,
                      onClearCategory: () => _handleCategorySelect(null),
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryContributionCard(
                  categories: widget.categories,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: _handleCategorySelect,
                ),
                M3Spacing.gapSM,
                _ParetoPowerSkusCard(
                  paretoSkus: widget.paretoSkus,
                  selectedCategory: _selectedCategory,
                  onClearCategory: () => _handleCategorySelect(null),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SupplierMarketShareCard extends StatefulWidget {
  final List<SupplierShareModel> supplierShares;
  final double totalMarketRevenue;
  final double tenantMarketSharePct;
  final int competitorsCount;

  const _SupplierMarketShareCard({
    required this.supplierShares,
    required this.totalMarketRevenue,
    required this.tenantMarketSharePct,
    required this.competitorsCount,
  });

  @override
  State<_SupplierMarketShareCard> createState() => _SupplierMarketShareCardState();
}

class _SupplierMarketShareCardState extends State<_SupplierMarketShareCard> {
  bool _showAll = false;

  static String _cleanSupplierName(String rawName, bool isTenant) {
    if (isTenant ||
        rawName.contains('أديكو') ||
        rawName.contains('ادكو') ||
        rawName.contains('الإسكندرية للمنظفات')) {
      return 'شركة أديكو';
    }
    var clean = rawName.trim();
    if (clean.contains('بروكتور و جامبل') || clean.contains('بروكتر و جامبل')) {
      return 'بروكتر آند جامبل مصر (P&G)';
    }
    if (clean.contains('بروكر')) {
      return 'بروكتر آند جامبل (حساب 2)';
    }
    if (clean.contains('ارما التجارية') || clean.contains('أرما التجارية')) {
      return 'أرما التجارية - منظفات (Arma)';
    }
    if (clean.contains('329')) {
      return 'أرما للصناعات (حساب 329)';
    }
    if (clean.contains('ارما منظفات') || clean.contains('أرما منظفات')) {
      return 'أرما للمنظفات والعناية المنزلية';
    }
    if (clean.contains('311')) {
      return 'هنكل - برسيل (حساب 311)';
    }
    if (clean.contains('هنكل برسيل')) {
      return 'هنكل - برسيل مصر (Henkel)';
    }
    if (clean.contains('فريدال')) {
      return 'فريدال للصناعات (Fridal)';
    }
    if (clean.contains('كلوركس')) {
      return 'كلوركس مصر (Clorox)';
    }
    if (clean.contains('سافو')) {
      return 'سافو للصناعات الكيماوية';
    }
    clean = clean.replaceAll(RegExp(r'\s*/\s*\d+'), '');
    clean = clean.replaceAll(RegExp(r'\s*\(\d+\)'), '');
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine tenant rank dynamically
    final adecoIndex = widget.supplierShares.indexWhere((s) =>
        s.isTenantBrand ||
        s.supplierName.contains('أديكو') ||
        s.supplierName.contains('ادكو') ||
        s.supplierName.contains('الإسكندرية للمنظفات'));
    final adecoRank = adecoIndex >= 0
        ? (widget.supplierShares[adecoIndex].rank > 0
            ? widget.supplierShares[adecoIndex].rank
            : adecoIndex + 1)
        : 1;

    final displayedSuppliers =
        _showAll ? widget.supplierShares : widget.supplierShares.take(8).toList();

    // Sum revenue of displayed items
    final displayedRevenue =
        displayedSuppliers.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
    final displayedShare =
        displayedSuppliers.fold<double>(0.0, (sum, s) => sum + s.marketSharePct);

    // Calculate remaining market revenue and share
    final remainingRevenue =
        (widget.totalMarketRevenue - displayedRevenue).clamp(0.0, double.infinity);
    final remainingSharePct = widget.totalMarketRevenue > 0
        ? ((remainingRevenue / widget.totalMarketRevenue) * 100.0).clamp(0.0, 100.0)
        : (100.0 - displayedShare).clamp(0.0, 100.0);

    final remainingCount = (widget.competitorsCount + 1 > displayedSuppliers.length)
        ? (widget.competitorsCount + 1 - displayedSuppliers.length)
        : (widget.supplierShares.length > displayedSuppliers.length
            ? widget.supplierShares.length - displayedSuppliers.length
            : 0);

    final hasOthers =
        !_showAll && (remainingRevenue > 1000.0 || remainingSharePct > 0.05);

    return Card.filled(
      key: const ValueKey('supplier_market_share_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.xs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.65),
                        borderRadius: M3Shape.radiusSm,
                      ),
                      child: Icon(
                        AppIcons.pieChart,
                        size: 20.0,
                        color: colorScheme.primary,
                      ),
                    ),
                    M3Spacing.hGapXS,
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الحصة السوقية مقارنة بالمنافسين',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1.0),
                          Text(
                            'Market Share vs. Competitors',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'الحصة السوقية لشركة أديكو مقارنة بالموردين المنافسين عبر كافة المجموعات',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 6.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.leaderboard,
                            size: 15.0,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 5.0),
                          Flexible(
                            child: Text(
                              'حصة أديكو السوقية: ${widget.tenantMarketSharePct.toStringAsFixed(2)}% (#$adecoRank)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.totalMarketRevenue > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 6.0,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: M3Shape.radiusSm,
                          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.storeMatrix,
                              size: 15.0,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5.0),
                            Flexible(
                              child: Text(
                                'إجمالي السوق: ${CurrencyFormatter.formatCompactEGP(widget.totalMarketRevenue)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 6.0,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: M3Shape.radiusSm,
                          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.groups,
                              size: 15.0,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5.0),
                            Flexible(
                              child: Text(
                                '${widget.competitorsCount} مورد منافس',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.supplierShares.length > 8)
                      InkWell(
                        onTap: () => setState(() => _showAll = !_showAll),
                        borderRadius: M3Shape.radiusSm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: _showAll
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: M3Shape.radiusSm,
                            border: Border.all(
                              color: _showAll
                                  ? colorScheme.primary.withOpacity(0.4)
                                  : colorScheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showAll
                                    ? AppIcons.collapseAll
                                    : AppIcons.expandAll,
                                size: 15.0,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 5.0),
                              Text(
                                _showAll
                                    ? 'عرض أهم 8 موردين'
                                    : 'عرض كافة الموردين (${widget.supplierShares.length})',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            M3Spacing.gapMD,
            ...displayedSuppliers.asMap().entries.map((entry) {
              final idx = entry.key;
              final sup = entry.value;
              final rank = (sup.rank > 0) ? sup.rank : (idx + 1);
              final isTenant = sup.isTenantBrand ||
                  sup.supplierName.contains('أديكو') ||
                  sup.supplierName.contains('ادكو') ||
                  sup.supplierName.contains('الإسكندرية للمنظفات');
              final supplierDisplayName = _cleanSupplierName(sup.supplierName, isTenant);
              final supplierParts = ChainSharePie.splitBilingualLabel(supplierDisplayName);
              final ratio = (sup.marketSharePct / 25.0).clamp(0.02, 1.0);
              final barColor = isTenant
                  ? colorScheme.primary
                  : colorScheme.secondary.withOpacity(0.75);

              return Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: isTenant
                      ? colorScheme.primaryContainer.withOpacity(0.18)
                      : colorScheme.surfaceContainerLow,
                  borderRadius: M3Shape.radiusMd,
                  border: Border.all(
                    color: isTenant
                        ? colorScheme.primary.withOpacity(0.45)
                        : colorScheme.outlineVariant.withOpacity(0.55),
                    width: isTenant ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;

                        final supplierIdentity = Wrap(
                          spacing: 10.0,
                          runSpacing: 8.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // 1. Rank Chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                              decoration: BoxDecoration(
                                color: isTenant
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: M3Shape.radiusSm,
                                border: isTenant
                                    ? null
                                    : Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                              ),
                              child: Text(
                                '#$rank',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isTenant
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // 2. Company Name (Arabic on Line 1, English on Line 2)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  supplierParts.ar,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isTenant ? colorScheme.primary : colorScheme.onSurface,
                                    fontSize: isTenant ? M3FontSize.bodyMediumLarge : M3FontSize.bodyMedium,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (supplierParts.en != null)
                                  Text(
                                    supplierParts.en!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            // 3. Barcode Count Chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withOpacity(0.65),
                                borderRadius: M3Shape.radiusLg,
                                border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.barcode,
                                    size: 14.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Flexible(
                                    child: Text(
                                      '${sup.skuCount} باركود',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        fontSize: M3FontSize.labelSmall,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 4. Leader Status Chip (For Adeco)
                            if (isTenant)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: M3Shape.radiusLg,
                                  border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.premium,
                                      size: 15.0,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 5.0),
                                    Flexible(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rank == 1
                                                ? 'الشركة الرائدة (#1)'
                                                : 'المركز التنافسي (#$rank)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: colorScheme.onPrimaryContainer,
                                              fontWeight: FontWeight.bold,
                                              fontSize: M3FontSize.labelSmall,
                                            ),
                                          ),
                                          if (rank == 1)
                                            Text(
                                              'Market Leader',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: colorScheme.onPrimaryContainer.withOpacity(0.85),
                                                fontWeight: FontWeight.w600,
                                                fontSize: M3FontSize.tiny,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );

                        final financialChips = Wrap(
                          spacing: 8.0,
                          runSpacing: 6.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Market Share % Chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.5),
                              decoration: BoxDecoration(
                                color: isTenant
                                    ? colorScheme.primary
                                    : colorScheme.secondaryContainer,
                                borderRadius: M3Shape.radiusSm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.pieChart,
                                    size: 14.0,
                                    color: isTenant
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Flexible(
                                    child: Text(
                                      '${sup.marketSharePct.toStringAsFixed(2)}%',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: isTenant
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Revenue EGP Chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.5),
                              decoration: BoxDecoration(
                                color: isTenant
                                    ? colorScheme.primaryContainer.withOpacity(0.65)
                                    : colorScheme.surfaceContainerHighest,
                              borderRadius: M3Shape.radiusSm,
                              border: Border.all(
                                color: isTenant
                                    ? colorScheme.primary.withOpacity(0.3)
                                    : colorScheme.outlineVariant.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.money,
                                  size: 14.0,
                                  color: isTenant
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5.0),
                                Flexible(
                                  child: Text(
                                    CurrencyFormatter.formatCompactEGP(sup.totalRevenue),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: isTenant ? colorScheme.primary : colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      if (isWide) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: supplierIdentity),
                            const SizedBox(width: 16.0),
                            financialChips,
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          supplierIdentity,
                          const SizedBox(height: 10.0),
                          financialChips,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12.0),
                  // Progress Bar
                  ClipRRect(
                    borderRadius: M3Shape.radiusSm,
                    child: LinearProgressIndicator(
year2023: false,
                      value: ratio,
                      minHeight: 8.0,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Summary row for Remaining Competitors to make total equal 100% of the market
          if (hasOthers)
            Container(
              margin: const EdgeInsets.only(bottom: 12.0),
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                borderRadius: M3Shape.radiusMd,
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.45),
                ),
              ),
              child: InkWell(
                onTap: widget.supplierShares.length > 8
                    ? () => setState(() => _showAll = true)
                    : null,
                borderRadius: M3Shape.radiusSm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;

                        final otherIdentity = Wrap(
                          spacing: 10.0,
                          runSpacing: 8.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0, vertical: 5.0),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: M3Shape.radiusSm,
                                border: Border.all(
                                    color: colorScheme.outlineVariant.withOpacity(0.5)),
                              ),
                              child: Text(
                                '#9+',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              'باقي الموردين والمنافسين ${remainingCount > 0 ? '($remainingCount مورد آخر)' : ''}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                                fontSize: M3FontSize.bodyMedium,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9.0, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withOpacity(0.65),
                                borderRadius: M3Shape.radiusLg,
                                border: Border.all(
                                    color: colorScheme.outlineVariant.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.groups,
                                    size: 14.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Text(
                                    'تغطية باقي السوق',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      fontSize: M3FontSize.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.supplierShares.length > 8)
                              Text(
                                '(انقر لعرض الكل)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: M3FontSize.labelSmall,
                                ),
                              ),
                          ],
                        );

                        final otherFinancialChips = Wrap(
                          spacing: 8.0,
                          runSpacing: 6.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0, vertical: 5.5),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer.withOpacity(0.7),
                                borderRadius: M3Shape.radiusSm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.pieChart,
                                    size: 14.0,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Text(
                                    '${remainingSharePct.toStringAsFixed(2)}%',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0, vertical: 5.5),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: M3Shape.radiusSm,
                                border: Border.all(
                                    color: colorScheme.outlineVariant.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.money,
                                    size: 14.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Text(
                                    CurrencyFormatter.formatCompactEGP(remainingRevenue),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );

                        if (isWide) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: otherIdentity),
                              const SizedBox(width: 16.0),
                              otherFinancialChips,
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            otherIdentity,
                            const SizedBox(height: 10.0),
                            otherFinancialChips,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12.0),
                    ClipRRect(
                      borderRadius: M3Shape.radiusSm,
                      child: LinearProgressIndicator(
year2023: false,
                        value: (remainingSharePct / 25.0).clamp(0.02, 1.0),
                        minHeight: 8.0,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.secondary.withOpacity(0.4)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
}

class _CategoryContributionCard extends StatefulWidget {
  final List<CategoryContributionModel> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  const _CategoryContributionCard({
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  State<_CategoryContributionCard> createState() => _CategoryContributionCardState();
}

class _CategoryContributionCardState extends State<_CategoryContributionCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Categorical series colours come from the theme's chart palette.
    final palette = M3StatusColors.of(context).chartPalette;

    final hasActiveFilter = widget.selectedCategory != null && widget.selectedCategory!.isNotEmpty;

    final displayedCategories =
        _showAll ? widget.categories : widget.categories.take(10).toList();

    final displayedSharePct =
        displayedCategories.fold<double>(0.0, (sum, c) => sum + c.sharePct);
    final displayedRevenue =
        displayedCategories.fold<double>(0.0, (sum, c) => sum + c.totalRevenue);
    final displayedUnits =
        displayedCategories.fold<int>(0, (sum, c) => sum + c.totalUnits);

    final totalRev =
        widget.categories.fold<double>(0.0, (sum, c) => sum + c.totalRevenue);
    final totalUnits =
        widget.categories.fold<int>(0, (sum, c) => sum + c.totalUnits);

    final remainingSharePct = (100.0 - displayedSharePct).clamp(0.0, 100.0);
    final remainingRevenue = (totalRev - displayedRevenue).clamp(0.0, double.infinity);
    final remainingUnits = (totalUnits - displayedUnits).clamp(0, 999999999);
    final remainingCount = widget.categories.length - displayedCategories.length;
    final hasOtherCategories =
        !_showAll && (remainingCount > 0 || remainingSharePct > 0.1);

    return Card.outlined(
      key: const ValueKey('category_contribution_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.55),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Icon(
                    AppIcons.productMaster,
                    size: 20.0,
                    color: colorScheme.primary,
                  ),
                ),
                M3Spacing.hGapXS,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مساهمة الفئات والمجموعات السلعية',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 1.0),
                      Text(
                        'Category Contribution',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'توزيع الإيرادات والحصة السوقية داخل كل مجموعة رئيسية',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.categories.length > 10) ...[
                  InkWell(
                    onTap: () => setState(() => _showAll = !_showAll),
                    borderRadius: M3Shape.radiusSm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: _showAll
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(
                          color: _showAll
                              ? colorScheme.primary.withOpacity(0.4)
                              : colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showAll
                                ? AppIcons.collapseAll
                                : AppIcons.expandAll,
                            size: 14.0,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            _showAll
                                ? 'أهم 10 فقط'
                                : 'كافة الفئات (${widget.categories.length})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                ],
                if (hasActiveFilter)
                  InkWell(
                    onTap: () => widget.onCategorySelected(null),
                    borderRadius: M3Shape.radiusSm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.clearAll, size: 14.0, color: colorScheme.primary),
                          const SizedBox(width: 4.0),
                          Text(
                            'عرض الكل',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            M3Spacing.gapMD,
            // Column Guide Header Bar to explicitly clarify both percentage metrics
            Container(
              margin: const EdgeInsets.only(bottom: 12.0),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: M3Shape.radiusSm,
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Wrap(
                spacing: 16.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.pieChart,
                          size: 13.0,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'حصة الشركة من السوق',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.75),
                          borderRadius: M3Shape.radiusSm,
                        ),
                        child: Text(
                          'حصتنا بالسوق %',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: M3FontSize.microPlus,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.donutChart,
                          size: 13.0,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        'المساهمة في مبيعات الشركة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withOpacity(0.75),
                          borderRadius: M3Shape.radiusSm,
                        ),
                        child: Text(
                          '% من مبيعاتنا',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: M3FontSize.microPlus,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ...displayedCategories.asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value;
              final barColor = palette[idx % palette.length];
              final ratio = (cat.sharePct / 100.0).clamp(0.0, 1.0);
              final isSelected = widget.selectedCategory != null &&
                  cat.category.trim().toLowerCase() == widget.selectedCategory!.trim().toLowerCase();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Material(
                  color: isSelected
                      ? colorScheme.primaryContainer.withOpacity(0.3)
                      : Colors.transparent,
                  borderRadius: M3Shape.radiusSm,
                  child: InkWell(
                    borderRadius: M3Shape.radiusSm,
                    onTap: () => widget.onCategorySelected(cat.category),
                    hoverColor: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                    child: AnimatedContainer(
                      duration: M3Motion.short4,
                      curve: M3Motion.standard,
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withOpacity(0.2),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 4.0,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      cat.category,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6.0,
                                        vertical: 2.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: M3Shape.radiusSm,
                                      ),
                                      child: Text(
                                        '${cat.skuCount} صنف',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: M3FontSize.tinyPlus,
                                        ),
                                      ),
                                    ),
                                    if (cat.tenantCategorySharePct > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 2.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer.withOpacity(0.75),
                                          borderRadius: M3Shape.radiusSm,
                                        ),
                                        child: Text(
                                          'حصتنا بالسوق: ${cat.tenantCategorySharePct.toStringAsFixed(1)}%',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                            fontSize: M3FontSize.tiny,
                                          ),
                                        ),
                                      ),
                                    if (isSelected)
                                      Icon(
                                        AppIcons.success,
                                        size: 16.0,
                                        color: colorScheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '${cat.sharePct.toStringAsFixed(1)}%',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: barColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    'من مبيعاتنا',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: M3FontSize.tiny,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6.0),
                          ClipRRect(
                            borderRadius: M3Shape.radiusSm,
                            child: LinearProgressIndicator(
year2023: false,
                              value: ratio,
                              minHeight: 8.0,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  cat.categoryMarketRevenue > 0
                                      ? '${CurrencyFormatter.formatCompactEGP(cat.totalRevenue)} مبيعاتنا من إجمالي ${CurrencyFormatter.formatCompactEGP(cat.categoryMarketRevenue)} بالسوق'
                                      : '${CurrencyFormatter.formatCompactEGP(cat.totalRevenue)} مبيعاتنا',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: M3FontSize.labelSmallPlus,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                '${CurrencyFormatter.formatUnits(cat.totalUnits)} عبوة',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: M3FontSize.labelSmallPlus,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            // Summary row for other categories so that portfolio contributions sum to 100%
            if (hasOtherCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: M3Shape.radiusSm,
                  child: InkWell(
                    borderRadius: M3Shape.radiusSm,
                    onTap: widget.categories.length > 10
                        ? () => setState(() => _showAll = true)
                        : null,
                    hoverColor: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        borderRadius: M3Shape.radiusSm,
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 4.0,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'باقي الفئات الأخرى ${remainingCount > 0 ? '($remainingCount فئات أخرى)' : ''}',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6.0,
                                        vertical: 2.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: M3Shape.radiusSm,
                                      ),
                                      child: Text(
                                        'فئات إضافية',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: M3FontSize.tinyPlus,
                                        ),
                                      ),
                                    ),
                                    if (widget.categories.length > 10)
                                      Text(
                                        '(انقر لعرض الكل)',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: M3FontSize.tinyPlus,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '${remainingSharePct.toStringAsFixed(1)}%',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.secondary,
                                    ),
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    'من مبيعاتنا',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: M3FontSize.tiny,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6.0),
                          ClipRRect(
                            borderRadius: M3Shape.radiusSm,
                            child: LinearProgressIndicator(
year2023: false,
                              value: (remainingSharePct / 100.0).clamp(0.0, 1.0),
                              minHeight: 8.0,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.secondary.withOpacity(0.55)),
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '${CurrencyFormatter.formatCompactEGP(remainingRevenue)} مبيعاتنا',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: M3FontSize.labelSmallPlus,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                '${CurrencyFormatter.formatUnits(remainingUnits)} عبوة',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: M3FontSize.labelSmallPlus,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParetoPowerSkusCard extends StatelessWidget {
  final List<ParetoSkuItemModel> paretoSkus;
  final String? selectedCategory;
  final VoidCallback? onClearCategory;

  const _ParetoPowerSkusCard({
    required this.paretoSkus,
    this.selectedCategory,
    this.onClearCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFiltered = selectedCategory != null && selectedCategory!.isNotEmpty;

    // Filter SKUs if category selected, otherwise take top 10 for balanced vertical height
    final List<ParetoSkuItemModel> skusToDisplay;
    if (isFiltered) {
      final cleanSel = selectedCategory!.trim().toLowerCase();
      final filtered = paretoSkus.where((s) {
        final cat = s.category.trim().toLowerCase();
        return cat == cleanSel || cat.contains(cleanSel) || cleanSel.contains(cat);
      }).toList();

      if (filtered.isNotEmpty) {
        final catTotalRev = filtered.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
        var runningCumulative = 0.0;
        skusToDisplay = filtered.asMap().entries.map((entry) {
          final idx = entry.key;
          final s = entry.value;
          final share = catTotalRev > 0 ? (s.totalRevenue / catTotalRev) * 100.0 : 0.0;
          final prevCum = runningCumulative;
          runningCumulative += share;
          final cum = runningCumulative.clamp(0.0, 100.0);
          final isTop80 = idx == 0 || prevCum < 80.0;

          return ParetoSkuItemModel(
            barcode: s.barcode,
            itemCode: s.itemCode,
            skuName: s.skuName,
            category: s.category,
            unitsPerCarton: s.unitsPerCarton,
            itemType: s.itemType,
            totalRevenue: s.totalRevenue,
            totalUnits: s.totalUnits,
            unitPrice: s.unitPrice,
            factoryUnitCost: s.factoryUnitCost,
            revenueSharePct: double.parse(share.toStringAsFixed(1)),
            cumulativeSharePct: double.parse(cum.toStringAsFixed(1)),
            isTop80Contributor: isTop80,
          );
        }).toList();
      } else {
        skusToDisplay = [];
      }
    } else {
      skusToDisplay = paretoSkus.take(10).toList();
    }

    return Card.outlined(
      key: const ValueKey('pareto_80_20_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.55),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Icon(
                    AppIcons.insights,
                    size: 20.0,
                    color: colorScheme.primary,
                  ),
                ),
                M3Spacing.hGapXS,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الأصناف القائدة للمبيعات (باريتو 80/20)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 1.0),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                            'Pareto 80/20 Power SKUs',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          ),
                          const SizedBox(width: 6.0),
                          Badge.count(
                            key: const ValueKey('pareto_class_a_badge'),
                            count: paretoSkus.where((s) => s.isTop80Contributor).length,
                            backgroundColor: colorScheme.primary,
                            textColor: colorScheme.onPrimary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        isFiltered
                            ? 'الأصناف المحركة لـ 80% من مبيعات ($selectedCategory) سهم تراكمي'
                            : 'الأصناف المحركة لـ 80% من إجمالي المبيعات (سهم تراكمي %)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            M3Spacing.gapMD,

            // Filter status banner
            if (isFiltered) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.35),
                  borderRadius: M3Shape.radiusSm,
                  border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.filterAlt, size: 16.0, color: colorScheme.primary),
                        const SizedBox(width: 6.0),
                        Text(
                          'أصناف فئة: $selectedCategory (${skusToDisplay.length} صنف)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: onClearCategory,
                      child: Row(
                        children: [
                          Text(
                            'عرض كافة الفئات',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 2.0),
                          Icon(AppIcons.close, size: 14.0, color: colorScheme.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (skusToDisplay.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(AppIcons.units, size: 36.0, color: colorScheme.outline),
                      const SizedBox(height: 8.0),
                      Text(
                        'لا توجد أصناف مسجلة لهذه الفئة حالياً',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      FilledButton.tonal(
                        onPressed: onClearCategory,
                        child: const Text('Show All'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...skusToDisplay.map((sku) {
                final isClassA = sku.isTop80Contributor;
                return LayoutBuilder(
                  builder: (context, cardConstraints) {
                    final isCompact = cardConstraints.maxWidth < 460;
                    return Container(
                      width: double.infinity,
                      constraints: BoxConstraints(minHeight: isCompact ? 76.0 : 62.0),
                      margin: const EdgeInsets.only(bottom: 8.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: isClassA
                            ? colorScheme.primaryContainer.withOpacity(0.22)
                            : colorScheme.surfaceContainerLowest,
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(
                          color: isClassA
                              ? colorScheme.primary.withOpacity(0.25)
                              : colorScheme.outlineVariant.withOpacity(0.45),
                        ),
                      ),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        sku.skuName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8.0),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: isClassA
                                            ? colorScheme.primaryContainer
                                            : colorScheme.surfaceContainerHighest,
                                        borderRadius: M3Shape.radiusSm,
                                      ),
                                      child: Text(
                                        isClassA ? 'فئة A • 80%' : 'فئة B/C',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: isClassA
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.bold,
                                          fontSize: M3FontSize.tiny,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '${sku.category} • ${sku.itemCode.isNotEmpty ? "كود: ${sku.itemCode} • " : ""}باركود: ${sku.barcode} • ${CurrencyFormatter.formatCompactEGP(sku.totalRevenue)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: M3FontSize.labelSmall,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  'حصة: ${sku.revenueSharePct.toStringAsFixed(1)}% • تراكمي: ${sku.cumulativeSharePct.toStringAsFixed(1)}%',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                    fontSize: M3FontSize.tinyPlus,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 1. SKU Name & Category / Barcode / Revenue
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        sku.skuName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3.0),
                                      Text(
                                        '${sku.category} • ${sku.itemCode.isNotEmpty ? "كود: ${sku.itemCode} • " : ""}باركود: ${sku.barcode} • ${CurrencyFormatter.formatCompactEGP(sku.totalRevenue)}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: M3FontSize.labelSmall,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                // 2. Share & Cumulative Share %
                                ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 95.0, maxWidth: 120.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'حصة: ${sku.revenueSharePct.toStringAsFixed(1)}%',
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 2.0),
                                      Text(
                                        'تراكمي: ${sku.cumulativeSharePct.toStringAsFixed(1)}%',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: M3FontSize.tinyPlus,
                                        ),
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                // 3. Category Class Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9.0,
                                    vertical: 5.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isClassA
                                        ? colorScheme.primaryContainer
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: M3Shape.radiusSm,
                                  ),
                                  child: Text(
                                    isClassA ? 'فئة A • 80% من المبيعات' : 'فئة B/C',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isClassA
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                      fontSize: M3FontSize.tinyPlus,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}
