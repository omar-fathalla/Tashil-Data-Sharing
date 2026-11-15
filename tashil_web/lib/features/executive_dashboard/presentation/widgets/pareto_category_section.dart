import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:tashil_web/core/widgets/m3_fill_layout.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/core/widgets/m3_tonal_surface.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
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
              // Both cards stretch to the taller one; 24dp gap like the
              // other section rows.
              return M3EqualHeightGrid(
                key: const ValueKey('pareto_category_row'),
                columns: 2,
                flex: const [5, 7],
                spacing: M3Spacing.md,
                children: [
                  _CategoryContributionCard(
                    categories: widget.categories,
                    selectedCategory: _selectedCategory,
                    onCategorySelected: _handleCategorySelect,
                  ),
                  _ParetoPowerSkusCard(
                    paretoSkus: widget.paretoSkus,
                    selectedCategory: _selectedCategory,
                    onClearCategory: () => _handleCategorySelect(null),
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
                M3Spacing.gapMD,
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
  State<_SupplierMarketShareCard> createState() =>
      _SupplierMarketShareCardState();
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
      return 'بروكتر آند جامبل';
    }
    if (clean.contains('ارما التجارية') || clean.contains('أرما التجارية')) {
      return 'أرما التجارية - منظفات (Arma)';
    }
    if (clean.contains('329')) {
      return 'أرما للصناعات';
    }
    if (clean.contains('ارما منظفات') || clean.contains('أرما منظفات')) {
      return 'أرما للمنظفات والعناية المنزلية';
    }
    if (clean.contains('311')) {
      return 'هنكل - برسيل';
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

    final displayedSuppliers = _showAll
        ? widget.supplierShares
        : widget.supplierShares.take(8).toList();

    // Sum revenue of displayed items
    final displayedRevenue =
        displayedSuppliers.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
    final displayedShare = displayedSuppliers.fold<double>(
        0.0, (sum, s) => sum + s.marketSharePct);

    // Calculate remaining market revenue and share
    final remainingRevenue = (widget.totalMarketRevenue - displayedRevenue)
        .clamp(0.0, double.infinity);
    final remainingSharePct = widget.totalMarketRevenue > 0
        ? ((remainingRevenue / widget.totalMarketRevenue) * 100.0)
            .clamp(0.0, 100.0)
        : (100.0 - displayedShare).clamp(0.0, 100.0);

    final remainingCount =
        (widget.competitorsCount + 1 > displayedSuppliers.length)
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
                    Icon(AppIcons.pieChart,
                        size: 20.0, color: colorScheme.onSurfaceVariant),
                    M3Spacing.hGapXS,
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const M3SectionTitle(
                              'الحصة السوقية مقارنة بالمنافسين'),
                          const SizedBox(height: 2.0),
                          Text(
                            'حصتنا مقارنة بالمنافسين في كل الفئات',
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
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    // Short chip + description (TM / Compare pattern).
                    _ShortChipWithDesc(
                      key: const ValueKey('pareto_share_chip'),
                      icon: AppIcons.leaderboard,
                      shortLabel:
                          '${widget.tenantMarketSharePct.toStringAsFixed(2)}%',
                      description: 'حصتنا السوقية · المركز $adecoRank',
                    ),
                    if (widget.totalMarketRevenue > 0) ...[
                      _ShortChipWithDesc(
                        key: const ValueKey('pareto_market_total_chip'),
                        icon: AppIcons.storeMatrix,
                        shortLabel: CurrencyFormatter.formatCompactEGP(
                            widget.totalMarketRevenue),
                        description: 'إجمالي السوق',
                      ),
                      _ShortChipWithDesc(
                        key: const ValueKey('pareto_competitors_chip'),
                        icon: AppIcons.groups,
                        shortLabel: countCompetitors(widget.competitorsCount),
                      ),
                    ],
                    if (widget.supplierShares.length > 8)
                      FilterChip(
                        label: Text(_showAll
                            ? 'أهم 8 موردين'
                            : 'كل الموردين (${widget.supplierShares.length})'),
                        avatar: Icon(
                            _showAll
                                ? AppIcons.collapseAll
                                : AppIcons.expandAll,
                            size: 18.0),
                        showCheckmark: false,
                        selected: _showAll,
                        onSelected: (_) => setState(() => _showAll = !_showAll),
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
              final supplierDisplayName =
                  _cleanSupplierName(sup.supplierName, isTenant);
              final supplierParts =
                  ChainSharePie.splitBilingualLabel(supplierDisplayName);
              final ratio = (sup.marketSharePct / 25.0).clamp(0.02, 1.0);
              final barColor =
                  isTenant ? colorScheme.primary : colorScheme.secondary;

              return Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.s12),
                child: M3TonalSurface(
                  color: isTenant
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderColor: isTenant ? null : colorScheme.outlineVariant,
                  borderWidth: isTenant ? 1.5 : 1.0,
                  borderRadius: M3Shape.radiusMd,
                  padding: const EdgeInsets.all(M3Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 720;

                          final supplierIdentity = Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // 1. Rank Chip
                              Semantics(
                                  label: 'المركز $rank',
                                  excludeSemantics: true,
                                  child: M3ChipSurface(
                                    color: isTenant
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHighest,
                                    borderColor: isTenant
                                        ? null
                                        : colorScheme.outlineVariant,
                                    // Bare rank number: the coloured chip already
                                    // reads as a rank (no '#', mockup is Arabic).
                                    child: Text(
                                      '$rank',
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: isTenant
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )),
                              // 2. Company Name (Arabic on Line 1, English on Line 2)
                              // Wrap ≤3 like Sell-Out / stock / category tiles — no ellipsis.
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    supplierParts.ar,
                                    key: ValueKey(
                                        'pareto_supplier_name_$rank'),
                                    style: (isTenant
                                            ? theme.textTheme.titleMedium
                                            : theme.textTheme.bodyMedium)
                                        ?.copyWith(
                                      color: isTenant
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurface,
                                      fontWeight:
                                          isTenant ? FontWeight.w500 : null,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.clip,
                                  ),
                                  if (supplierParts.en != null)
                                    Text(
                                      supplierParts.en!,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.clip,
                                    ),
                                ],
                              ),
                              // 3. SKU count: short number + «أصناف» (TM / Errors).
                              _ShortChipWithDesc(
                                key: ValueKey(
                                    'pareto_supplier_sku_count_$rank'),
                                shortLabel: '${sup.skuCount}',
                                description: 'أصناف',
                              ),
                              // 4. Leader status: short chip + description (TM pattern).
                              if (isTenant)
                                _ShortChipWithDesc(
                                  key: const ValueKey('pareto_leader_chip'),
                                  icon: AppIcons.premium,
                                  shortLabel:
                                      rank == 1 ? 'الأولى' : 'المركز $rank',
                                  description:
                                      rank == 1 ? 'في السوق' : 'بين الموردين',
                                  shortColor:
                                      colorScheme.onSecondaryContainer,
                                ),
                            ],
                          );

                          final financialChips = Wrap(
                            spacing: 8.0,
                            runSpacing: 6.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Market Share % Chip
                              M3ChipSurface(
                                color: isTenant
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerLowest,
                                borderColor: isTenant
                                    ? null
                                    : colorScheme.outlineVariant,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.pieChart,
                                      size: 14.0,
                                      color: isTenant
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Flexible(
                                      child: Text(
                                        '${sup.marketSharePct.toStringAsFixed(2)}%',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: isTenant
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Revenue EGP Chip
                              M3ChipSurface(
                                color: isTenant
                                    ? colorScheme.secondaryContainer
                                    : colorScheme.surfaceContainerLowest,
                                borderColor: isTenant
                                    ? null
                                    : colorScheme.outlineVariant,
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
                                    const SizedBox(width: 8.0),
                                    Flexible(
                                      child: Text(
                                        CurrencyFormatter.formatCompactEGP(
                                            sup.totalRevenue),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: isTenant
                                              ? colorScheme.primary
                                              : colorScheme.onSurface,
                                          fontWeight: FontWeight.w600,
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
                              const SizedBox(height: 8.0),
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
                ),
              );
            }),
            // Summary row for Remaining Competitors to make total equal 100% of the market
            if (hasOthers)
              Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.s12),
                child: M3TonalSurface(
                  onTap: widget.supplierShares.length > 8
                      ? () => setState(() => _showAll = true)
                      : null,
                  color: colorScheme.surfaceContainer,
                  borderColor: colorScheme.outlineVariant,
                  borderRadius: M3Shape.radiusMd,
                  padding: const EdgeInsets.all(M3Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 720;

                          final otherIdentity = Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              M3ChipSurface(
                                color: colorScheme.surfaceContainerLowest,
                                borderColor: colorScheme.outlineVariant,
                                child: Text(
                                  // "9 and beyond", isolated so '+' stays left
                                  // of the digit in RTL.
                                  '\u2066+9\u2069',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'موردون آخرون${remainingCount > 0 ? ' ($remainingCount)' : ''}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              M3ChipSurface(
                                color: colorScheme.surfaceContainerLowest,
                                borderColor: colorScheme.outlineVariant,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.groups,
                                      size: 14.0,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Text(
                                      'باقي السوق',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.supplierShares.length > 8)
                                Text(
                                  'عرض الكل',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          );

                          final otherFinancialChips = Wrap(
                            spacing: 8.0,
                            runSpacing: 6.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              M3ChipSurface(
                                color: colorScheme.surfaceContainerLowest,
                                borderColor: colorScheme.outlineVariant,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.pieChart,
                                      size: 14.0,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Text(
                                      '${remainingSharePct.toStringAsFixed(2)}%',
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              M3ChipSurface(
                                color: colorScheme.surfaceContainerLowest,
                                borderColor: colorScheme.outlineVariant,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.money,
                                      size: 14.0,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Text(
                                      CurrencyFormatter.formatCompactEGP(
                                          remainingRevenue),
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
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
                              const SizedBox(height: 8.0),
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
                              colorScheme.secondary),
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
  State<_CategoryContributionCard> createState() =>
      _CategoryContributionCardState();
}

class _CategoryContributionCardState extends State<_CategoryContributionCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Categorical series colours come from the theme's chart palette.
    final palette = M3StatusColors.of(context).chartPalette;

    final hasActiveFilter =
        widget.selectedCategory != null && widget.selectedCategory!.isNotEmpty;

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
    final remainingRevenue =
        (totalRev - displayedRevenue).clamp(0.0, double.infinity);
    final remainingUnits = (totalUnits - displayedUnits).clamp(0, 999999999);
    final remainingCount =
        widget.categories.length - displayedCategories.length;
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
                Icon(AppIcons.productMaster,
                    size: 20.0, color: colorScheme.onSurfaceVariant),
                M3Spacing.hGapXS,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const M3SectionTitle('مساهمة الفئات'),
                      const SizedBox(height: 2.0),
                      Text(
                        'المبيعات والحصة السوقية لكل فئة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.categories.length > 10) ...[
                  FilterChip(
                    label: Text(_showAll
                        ? 'أهم 10'
                        : 'كل الفئات (${widget.categories.length})'),
                    avatar: Icon(
                        _showAll ? AppIcons.collapseAll : AppIcons.expandAll,
                        size: 18.0),
                    showCheckmark: false,
                    selected: _showAll,
                    onSelected: (_) => setState(() => _showAll = !_showAll),
                  ),
                  const SizedBox(width: 6.0),
                ],
                if (hasActiveFilter)
                  TextButton.icon(
                    onPressed: () => widget.onCategorySelected(null),
                    icon: const Icon(AppIcons.clearAll, size: 18.0),
                    label: const Text('عرض الكل'),
                  ),
              ],
            ),
            M3Spacing.gapMD,
            // Column guide: one tag per metric (was icon + text + chip).
            Padding(
              key: const ValueKey('category_metric_legend'),
              padding: const EdgeInsets.only(bottom: M3Spacing.s12),
              child: M3TonalSurface(
                color: colorScheme.surfaceContainer,
                borderColor: colorScheme.outlineVariant,
                borderRadius: M3Shape.radiusSm,
                padding: const EdgeInsets.symmetric(
                    horizontal: M3Spacing.s12, vertical: M3Spacing.xs),
                child: const Wrap(
                  spacing: 16.0,
                  runSpacing: 8.0,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    M3StatusTag(
                        label: 'حصتنا السوقية %', icon: AppIcons.pieChart),
                    M3StatusTag(
                        label: '% من مبيعاتنا', icon: AppIcons.donutChart),
                  ],
                ),
              ),
            ),
            ...displayedCategories.asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value;
              final barColor = palette[idx % palette.length];
              final ratio = (cat.sharePct / 100.0).clamp(0.0, 1.0);
              final isSelected = widget.selectedCategory != null &&
                  cat.category.trim().toLowerCase() ==
                      widget.selectedCategory!.trim().toLowerCase();

              return Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.xs),
                child: M3TonalSurface(
                  onTap: () => widget.onCategorySelected(cat.category),
                  color: isSelected
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderColor: isSelected ? null : colorScheme.outlineVariant,
                  borderRadius: M3Shape.radiusSm,
                  padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.xs, vertical: M3Spacing.xs),
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
                                  key: ValueKey(
                                      'pareto_category_name_${cat.category}'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.clip,
                                ),
                                _ShortChipWithDesc(
                                  key: ValueKey(
                                      'pareto_cat_sku_count_${cat.category}'),
                                  shortLabel: '${cat.skuCount}',
                                  description: 'أصناف',
                                ),
                                if (cat.tenantCategorySharePct > 0)
                                  _ShortChipWithDesc(
                                    key: ValueKey(
                                        'pareto_cat_share_${cat.category}'),
                                    shortLabel:
                                        '${cat.tenantCategorySharePct.toStringAsFixed(1)}%',
                                    description: 'حصتنا السوقية',
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
                                  fontWeight: FontWeight.w600,
                                  // Palette colour stays on the bar; text ≥ 4.5:1.
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                '% من مبيعاتنا',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
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
                                  ? '${CurrencyFormatter.formatCompactEGP(cat.totalRevenue)} من إجمالي سوق ${CurrencyFormatter.formatCompactEGP(cat.categoryMarketRevenue)}'
                                  : '${CurrencyFormatter.formatCompactEGP(cat.totalRevenue)} مبيعاتنا',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Text(
                            '${CurrencyFormatter.formatUnits(cat.totalUnits)} وحدة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            // Summary row for other categories so that portfolio contributions sum to 100%
            if (hasOtherCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.xs),
                child: M3TonalSurface(
                  onTap: widget.categories.length > 10
                      ? () => setState(() => _showAll = true)
                      : null,
                  color: colorScheme.surfaceContainer,
                  borderColor: colorScheme.outlineVariant,
                  borderWidth: 1.0,
                  borderRadius: M3Shape.radiusSm,
                  padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.xs, vertical: M3Spacing.xs),
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
                                  'فئات أخرى${remainingCount > 0 ? ' ($remainingCount)' : ''}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                M3ChipSurface(
                                  color: colorScheme.surfaceContainerLowest,
                                  borderColor: colorScheme.outlineVariant,
                                  child: Text(
                                    'فئات أخرى',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (widget.categories.length > 10)
                                  Text(
                                    'عرض الكل',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
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
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                '% من مبيعاتنا',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
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
                              colorScheme.secondary),
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
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Text(
                            '${CurrencyFormatter.formatUnits(remainingUnits)} وحدة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
        return cat == cleanSel ||
            cat.contains(cleanSel) ||
            cleanSel.contains(cat);
      }).toList();

      if (filtered.isNotEmpty) {
        final catTotalRev =
            filtered.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
        var runningCumulative = 0.0;
        skusToDisplay = filtered.asMap().entries.map((entry) {
          final idx = entry.key;
          final s = entry.value;
          final share =
              catTotalRev > 0 ? (s.totalRevenue / catTotalRev) * 100.0 : 0.0;
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
      // Up to 30 candidates; 10 always shown, more only when the card is
      // stretched to the category card's height (M3FillRows).
      skusToDisplay = paretoSkus.take(30).toList();
    }

    return Card.outlined(
      key: const ValueKey('pareto_80_20_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        // Last child (the SKU rows) gets any extra height from the equal-
        // height row, so the card fills with rows instead of blank space.
        child: M3FillColumn(
          children: [
            Row(
              children: [
                Icon(AppIcons.insights,
                    size: 20.0, color: colorScheme.onSurfaceVariant),
                M3Spacing.hGapXS,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const M3SectionTitle('الأصناف الأعلى مبيعًا (80/20)'),
                      const SizedBox(height: 1.0),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          M3StatusTag(
                            key: const ValueKey('pareto_class_a_badge'),
                            label: countSku(paretoSkus
                                .where((s) => s.isTop80Contributor)
                                .length),
                            tone: M3StatusTone.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        isFiltered
                            ? 'الأصناف التي تحقق 80% من مبيعات $selectedCategory'
                            : 'الأصناف التي تحقق 80% من المبيعات',
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
              Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.s12),
                child: M3TonalSurface(
                  color: colorScheme.surfaceContainerLowest,
                  borderColor: colorScheme.outlineVariant,
                  borderRadius: M3Shape.radiusSm,
                  padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.s12, vertical: M3Spacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.filterAlt,
                              size: 16.0, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6.0),
                          Text(
                            '$selectedCategory · ${countSku(skusToDisplay.length)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: onClearCategory,
                        icon: const Icon(AppIcons.close, size: 18.0),
                        iconAlignment: IconAlignment.end,
                        label: const Text('عرض كل الفئات'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (skusToDisplay.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(AppIcons.units,
                          size: 36.0, color: colorScheme.outline),
                      const SizedBox(height: 8.0),
                      Text(
                        'لا توجد أصناف في هذه الفئة',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      FilledButton.tonal(
                        onPressed: onClearCategory,
                        child: const Text('عرض الكل'),
                      ),
                    ],
                  ),
                ),
              )
            else
              M3FillRows(
                key: const ValueKey('pareto_sku_rows'),
                minRows: isFiltered ? skusToDisplay.length : 10,
                children: [
                  ...skusToDisplay.map((sku) {
                    final isClassA = sku.isTop80Contributor;
                    return LayoutBuilder(
                      builder: (context, cardConstraints) {
                        final isCompact = cardConstraints.maxWidth < 460;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: M3Spacing.xs),
                          child: M3TonalSurface(
                            // Tonal row strip (surfaceContainerLow) so rows stay
                            // visible at wide shells — Errors / Returns / Pricing.
                            color: colorScheme.surfaceContainerLow,
                            borderColor: colorScheme.outlineVariant,
                            borderRadius: M3Shape.radiusSm,
                            padding: const EdgeInsets.symmetric(
                              horizontal: M3Spacing.sm,
                              vertical: M3Spacing.xs,
                            ),
                            width: double.infinity,
                            constraints: BoxConstraints(
                                minHeight: isCompact ? 76.0 : 62.0),
                            child: isCompact
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sku.skuName,
                                              key: const ValueKey(
                                                  'pareto_sku_name'),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.clip,
                                            ),
                                          ),
                                          const SizedBox(width: 8.0),
                                          M3ChipSurface(
                                            color: isClassA
                                                ? colorScheme.secondaryContainer
                                                : colorScheme
                                                    .surfaceContainerHighest,
                                            child: Text(
                                              isClassA
                                                  ? 'تصنيف A'
                                                  : 'تصنيف B/C',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: isClassA
                                                    ? colorScheme
                                                        .onSecondaryContainer
                                                    : colorScheme
                                                        .onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4.0),
                                      Text(
                                        '${sku.category} • ${sku.itemCode.isNotEmpty ? "كود الصنف: ${sku.itemCode} • " : ""}الباركود: ${sku.barcode} • ${CurrencyFormatter.formatCompactEGP(sku.totalRevenue)}',
                                        key: const ValueKey('pareto_sku_meta'),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.clip,
                                      ),
                                      const SizedBox(height: 2.0),
                                      Text(
                                        'الحصة ${sku.revenueSharePct.toStringAsFixed(1)}% • التراكمي ${sku.cumulativeSharePct.toStringAsFixed(1)}%',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // 1. SKU Name & Category / Barcode / Revenue
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              sku.skuName,
                                              key: const ValueKey(
                                                  'pareto_sku_name'),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.clip,
                                            ),
                                            const SizedBox(height: 3.0),
                                            Text(
                                              '${sku.category} • ${sku.itemCode.isNotEmpty ? "كود الصنف: ${sku.itemCode} • " : ""}الباركود: ${sku.barcode} • ${CurrencyFormatter.formatCompactEGP(sku.totalRevenue)}',
                                              key: const ValueKey(
                                                  'pareto_sku_meta'),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.clip,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12.0),
                                      // 2. Share & Cumulative Share %
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            minWidth: 95.0, maxWidth: 120.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'الحصة ${sku.revenueSharePct.toStringAsFixed(1)}%',
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                            ),
                                            const SizedBox(height: 2.0),
                                            Text(
                                              'التراكمي ${sku.cumulativeSharePct.toStringAsFixed(1)}%',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12.0),
                                      // 3. Category Class Badge
                                      M3ChipSurface(
                                        color: isClassA
                                            ? colorScheme.secondaryContainer
                                            : colorScheme
                                                .surfaceContainerHighest,
                                        child: Text(
                                          isClassA ? 'تصنيف A' : 'تصنيف B/C',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: isClassA
                                                ? colorScheme
                                                    .onSecondaryContainer
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Short [M3ChipSurface] label with an optional description underneath
/// (Trade Marketing / Compare pattern). Keeps long explanatory copy out of
/// the chip so geometry stays 32dp and text is never ellipsized inside it.
class _ShortChipWithDesc extends StatelessWidget {
  const _ShortChipWithDesc({
    super.key,
    required this.shortLabel,
    this.description,
    this.icon,
    this.shortColor,
  });

  final String shortLabel;
  final String? description;
  final IconData? icon;
  final Color? shortColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelColor = shortColor ?? cs.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        M3ChipSurface(
          color: cs.surfaceContainerLowest,
          borderColor: cs.outlineVariant,
          child: icon == null
              ? Text(
                  shortLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15.0, color: labelColor),
                    const SizedBox(width: 8.0),
                    Flexible(
                      child: Text(
                        shortLabel,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 2.0),
          Text(
            description!,
            maxLines: 2,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
