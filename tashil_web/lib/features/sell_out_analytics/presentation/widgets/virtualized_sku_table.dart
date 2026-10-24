import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';

/// VirtualizedSkuTable renders sell-out transactions with pinned columns
/// (GTIN Barcode & SKU Name remain sticky/fixed while metric columns scroll horizontally),
/// interactive column sorting, and Material Design 3 pagination.
class VirtualizedSkuTable extends StatefulWidget {
  final List<SellOutRecordModel> records;
  final bool isLoading;
  final ValueChanged<SellOutRecordModel>? onRecordTap;

  const VirtualizedSkuTable({
    super.key,
    required this.records,
    this.isLoading = false,
    this.onRecordTap,
  });

  @override
  State<VirtualizedSkuTable> createState() => _VirtualizedSkuTableState();
}

class _VirtualizedSkuTableState extends State<VirtualizedSkuTable> {
  static const double _rowHeight = 52.0;
  static const double _headerHeight = 56.0;

  String? _sortColumn;
  bool _sortAscending = true;
  int _rowsPerPage = 10;
  int _currentPage = 0;
  bool _forceTableOnMobile = false;

  @override
  void didUpdateWidget(covariant VirtualizedSkuTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      final maxPage = _computeTotalPages(widget.records.length) - 1;
      if (_currentPage > maxPage) {
        _currentPage = maxPage < 0 ? 0 : maxPage;
      }
    }
  }

  int _computeTotalPages(int totalItems) {
    if (totalItems <= 0) return 1;
    return (totalItems / _rowsPerPage).ceil();
  }

  void _handleSort(String columnKey) {
    setState(() {
      if (_sortColumn == columnKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnKey;
        _sortAscending = true;
      }
      _currentPage = 0;
    });
  }

  List<SellOutRecordModel> get _sortedRecords {
    final list = List<SellOutRecordModel>.from(widget.records);
    if (_sortColumn == null) return list;

    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'barcode':
          cmp = a.barcode.compareTo(b.barcode);
          break;
        case 'skuName':
          cmp = a.skuName.compareTo(b.skuName);
          break;
        case 'retailerChain':
          cmp = a.retailerChain.compareTo(b.retailerChain);
          break;
        case 'storeName':
          cmp = a.storeName.compareTo(b.storeName);
          break;
        case 'quantitySold':
          cmp = a.quantitySold.compareTo(b.quantitySold);
          break;
        case 'unitPrice':
          cmp = a.unitPrice.compareTo(b.unitPrice);
          break;
        case 'netRevenue':
          cmp = a.netRevenue.compareTo(b.netRevenue);
          break;
        case 'transactionDate':
          cmp = a.transactionDate.compareTo(b.transactionDate);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  Widget _buildSortableHeaderCell({
    required BuildContext context,
    required String columnKey,
    required String label,
    required double? width,
    TextAlign textAlign = TextAlign.start,
    bool expand = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSorted = _sortColumn == columnKey;

    AlignmentGeometry alignment = AlignmentDirectional.centerStart;
    MainAxisAlignment rowAlign = MainAxisAlignment.start;
    if (textAlign == TextAlign.end) {
      alignment = AlignmentDirectional.centerEnd;
      rowAlign = MainAxisAlignment.end;
    } else if (textAlign == TextAlign.center) {
      alignment = Alignment.center;
      rowAlign = MainAxisAlignment.center;
    }

    final content = InkWell(
      key: ValueKey('sort_header_$columnKey'),
      borderRadius: M3Shape.radiusSm,
      onTap: () => _handleSort(columnKey),
      child: Container(
        height: _headerHeight,
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: rowAlign,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.0,
                  color: isSorted ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 4.0),
              Icon(
                _sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 14.0,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );

    if (expand) {
      return Expanded(child: content);
    }
    return SizedBox(width: width, child: content);
  }

  Widget _buildMobileSkuCards(
    BuildContext context,
    List<SellOutRecordModel> pageRecords,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Material Design 3 Connected Button Group for Mobile Sorting
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Sort Title Label without colon (ترتيب حسب)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8.0, end: 4.0, start: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 16.0,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        'ترتيب حسب',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          fontSize: 13.0,
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Row: 4-segment full-width Button Group
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'netRevenue',
                        label: const Text('المبيعات'),
                        icon: Icon(
                          _sortColumn == 'netRevenue'
                              ? (_sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded)
                              : Icons.payments_rounded,
                          size: 14.0,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'quantitySold',
                        label: const Text('الكمية'),
                        icon: Icon(
                          _sortColumn == 'quantitySold'
                              ? (_sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded)
                              : Icons.shopping_basket_rounded,
                          size: 14.0,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'skuName',
                        label: const Text('الصنف'),
                        icon: Icon(
                          _sortColumn == 'skuName'
                              ? (_sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded)
                              : Icons.category_rounded,
                          size: 14.0,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'transactionDate',
                        label: const Text('التاريخ'),
                        icon: Icon(
                          _sortColumn == 'transactionDate'
                              ? (_sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded)
                              : Icons.calendar_today_rounded,
                          size: 14.0,
                        ),
                      ),
                    ],
                    selected: {_sortColumn ?? 'netRevenue'},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<String> newSelection) {
                      if (newSelection.isNotEmpty) {
                        _handleSort(newSelection.first);
                      }
                    },
                    style: SegmentedButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: M3Shape.radiusXl,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      selectedBackgroundColor: colorScheme.primary,
                      selectedForegroundColor: colorScheme.onPrimary,
                      backgroundColor: colorScheme.surfaceContainerLow,
                      foregroundColor: colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withOpacity(0.6),
                      ),
                      textStyle: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6.0),
          ...pageRecords.map((r) {
            final brandStyle = _getChainBrandStyle(r.retailerChain, colorScheme);
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: M3Shape.radiusLg,
                side: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1.0,
                ),
              ),
              color: colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12.0),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Retailer Chain Branded Accent Stripe
                    Container(
                      width: 5.0,
                      color: brandStyle.accent,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Row: Retailer Chain Badge Chip & Transaction Date
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8.0,
                              runSpacing: 6.0,
                              children: [
                                // Retailer Chain Distinct Branded Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9.0,
                                    vertical: 4.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: brandStyle.background,
                                    borderRadius: M3Shape.radiusLg,
                                    border: Border.all(
                                      color: brandStyle.border,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        brandStyle.icon,
                                        size: 13.0,
                                        color: brandStyle.foreground,
                                      ),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        brandStyle.displayNameAr,
                                        style: TextStyle(
                                          color: brandStyle.foreground,
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Transaction Date Badge Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withOpacity(0.5),
                                    borderRadius: M3Shape.radiusSm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 11.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        r.transactionDate,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10.0),

                            // Product Title
                            Text(
                              r.skuName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: colorScheme.onSurface,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8.0),

                            // Metadata Wrap: Item Code, Barcode, Store Name, Category
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 6.0,
                              children: [
                                if (r.itemCode.isNotEmpty)
                                  InkWell(
                                    onTap: widget.onRecordTap != null
                                        ? () => widget.onRecordTap!(r)
                                        : null,
                                    borderRadius: M3Shape.radiusSm,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7.0,
                                        vertical: 3.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer
                                            .withOpacity(0.55),
                                        borderRadius: M3Shape.radiusSm,
                                      ),
                                      child: Text(
                                        r.itemCode,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.primary,
                                          decoration: widget.onRecordTap != null
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Barcode Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7.0,
                                    vertical: 3.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withOpacity(0.4),
                                    borderRadius: M3Shape.radiusSm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.qr_code_2_rounded,
                                        size: 13.0,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4.0),
                                      SelectableText(
                                        r.barcode,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Store Name Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7.0,
                                    vertical: 3.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withOpacity(0.4),
                                    borderRadius: M3Shape.radiusSm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.storefront_rounded,
                                        size: 13.0,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        r.storeName,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (r.category.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7.0,
                                      vertical: 3.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest
                                          .withOpacity(0.4),
                                      borderRadius: M3Shape.radiusSm,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sell_rounded,
                                          size: 12.0,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4.0),
                                        Text(
                                          r.category,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12.0),

                            // Financial Metrics Bento Container
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 10.0,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withOpacity(0.4),
                                borderRadius: M3Shape.radiusMd,
                                border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withOpacity(0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Column 1: Quantity, Cartons & Unit Price
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'الكمية وسعر الوحدة',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11.0,
                                          ),
                                        ),
                                        const SizedBox(height: 3.0),
                                        Text(
                                          '${CurrencyFormatter.formatUnits(r.quantitySold)} وحدة (${r.cartonsSold.toStringAsFixed(1)} كرتونة)',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        Text(
                                          (r.recommendedPrice > 0 || r.factoryUnitCost > 0)
                                              ? 'كاشير ${r.unitPrice.toStringAsFixed(2)} • كارتة ${r.recommendedPrice.toStringAsFixed(2)} • مصنع ${r.factoryUnitCost.toStringAsFixed(2)} ج.م'
                                              : '× ${r.unitPrice.toStringAsFixed(2)} ج.م',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    height: 36.0,
                                    width: 1.0,
                                    color: colorScheme.outlineVariant
                                        .withOpacity(0.4),
                                  ),
                                  const SizedBox(width: 12.0),
                                  // Column 2: Net Revenue & Chain Margin
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'صافي المبيعات وهامش السلسلة',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11.0,
                                          ),
                                        ),
                                        const SizedBox(height: 2.0),
                                        Text(
                                          '${CurrencyFormatter.formatUnits(r.netRevenue.round())} ج.م',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: colorScheme.primary,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        Text(
                                          (r.retailerMarginPct != 0 || r.retailerGrossProfit != 0)
                                              ? 'هامش ${r.retailerMarginPct.toStringAsFixed(1)}% (${CurrencyFormatter.formatUnits(r.retailerGrossProfit.round())} ج.م)'
                                              : 'EGP ${r.netRevenue.toStringAsFixed(2)}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: r.retailerMarginPct < 0
                                                ? colorScheme.error
                                                : colorScheme.primary.withOpacity(0.75),
                                            fontSize: 10.5,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobileScreen = MediaQuery.sizeOf(context).width < 600.0;

    if (widget.isLoading) {
      return M3FadeThroughSwitcher(
        duration: M3Motion.medium1,
        child: Card(
          key: const ValueKey('sku_table_loading'),
          child: Container(
            height: 350.0,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (widget.records.isEmpty) {
      return M3FadeThroughSwitcher(
        duration: M3Motion.medium1,
        child: Card(
          key: const ValueKey('sku_table_empty'),
          child: Container(
            height: 250.0,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_rounded, size: 40.0, color: colorScheme.onSurfaceVariant),
                M3Spacing.gapSM,
                Text(
                  'لا توجد سجلات تطابق معايير الفلترة المحددة',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sorted = _sortedRecords;
    final totalCount = sorted.length;
    final totalPages = _computeTotalPages(totalCount);
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final startIndex = safePage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage > totalCount)
        ? totalCount
        : startIndex + _rowsPerPage;
    final pageRecords = sorted.sublist(startIndex, endIndex);

    return M3FadeThroughSwitcher(
      duration: M3Motion.medium1,
      child: Card(
        key: const ValueKey('sku_table_populated'),
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Title Bar with Pinned Column Indicator & Mobile View Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 16.0, color: colorScheme.primary),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Sell-Out Analytics Data Table (Pinned SKU & Barcode)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8.0),
                if (isMobileScreen) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _forceTableOnMobile ? 'عرض كبطاقات موبايل' : 'عرض كجدول',
                    icon: Icon(
                      _forceTableOnMobile
                          ? Icons.view_agenda_rounded
                          : Icons.table_chart_rounded,
                      size: 18.0,
                      color: colorScheme.primary,
                    ),
                    onPressed: () =>
                        setState(() => _forceTableOnMobile = !_forceTableOnMobile),
                  ),
                  const SizedBox(width: 4.0),
                ],
                Text(
                  'Total ${widget.records.length} rows',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Adaptive Content: M3 Mobile Cards on Compact (< 600dp) or Two-Pane Pinned Table
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;
              if (maxW < 420.0 && !_forceTableOnMobile) {
                return _buildMobileSkuCards(context, pageRecords);
              }
              final double pinnedWidth;
              final double barcodeColWidth;

              if (maxW >= 1200.0) {
                pinnedWidth = 420.0;
                barcodeColWidth = 140.0;
              } else if (maxW >= 840.0) {
                pinnedWidth = 360.0;
                barcodeColWidth = 130.0;
              } else if (maxW >= 560.0) {
                pinnedWidth = 320.0;
                barcodeColWidth = 120.0;
              } else {
                pinnedWidth = (maxW * 0.52).clamp(170.0, 280.0);
                barcodeColWidth = pinnedWidth < 240.0 ? 80.0 : 100.0;
              }

              final remainingWidth = (maxW - pinnedWidth).clamp(0.0, double.infinity);
              const minScrollableWidth = 760.0;
              final scrollableWidth = math.max(remainingWidth, minScrollableWidth);
              final contentWidth = scrollableWidth - 32.0;
              const baseContentWidth = 728.0;
              final factor = contentWidth / baseContentWidth;

              final colChainWidth = 100.0 * factor;
              final colStoreWidth = 160.0 * factor;
              final colQtyWidth = 100.0 * factor;
              final colUnitPriceWidth = 110.0 * factor;
              final colNetRevenueWidth = 138.0 * factor;
              final colDateWidth = 120.0 * factor;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. PINNED PANE (Fixed on Leading edge)
                  SizedBox(
                    width: pinnedWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        border: BorderDirectional(
                          end: BorderSide(
                            color: colorScheme.outlineVariant,
                            width: 2.0,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Pinned Header
                          Container(
                            height: _headerHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                              border: Border(
                                bottom: BorderSide(color: colorScheme.outlineVariant),
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildSortableHeaderCell(
                                  context: context,
                                  columnKey: 'barcode',
                                  label: 'GTIN / Barcode',
                                  width: barcodeColWidth,
                                ),
                                const SizedBox(width: 8.0),
                                _buildSortableHeaderCell(
                                  context: context,
                                  columnKey: 'skuName',
                                  label: 'Product / SKU Name',
                                  width: null,
                                  expand: true,
                                ),
                              ],
                            ),
                          ),
                          // Pinned Data Rows
                          ...pageRecords.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final r = entry.value;
                            final isEven = idx % 2 == 0;

                            return Container(
                              height: _rowHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              decoration: BoxDecoration(
                                color: isEven
                                    ? Colors.transparent
                                    : colorScheme.surfaceContainerHighest.withOpacity(0.12),
                                border: Border(
                                  bottom: BorderSide(
                                    color: colorScheme.outlineVariant.withOpacity(0.3),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: barcodeColWidth,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (r.itemCode.isNotEmpty)
                                          InkWell(
                                            onTap: widget.onRecordTap != null
                                                ? () => widget.onRecordTap!(r)
                                                : null,
                                            child: Text(
                                              r.itemCode,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 10.0,
                                                fontWeight: FontWeight.w800,
                                                color: colorScheme.primary,
                                                decoration: widget.onRecordTap != null
                                                    ? TextDecoration.underline
                                                    : TextDecoration.none,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            Icon(Icons.qr_code_2_rounded, size: 13.0, color: colorScheme.onSurfaceVariant),
                                            const SizedBox(width: 3.0),
                                            Expanded(
                                              child: SelectableText(
                                                r.barcode,
                                                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onRecordTap != null
                                          ? () => widget.onRecordTap!(r)
                                          : null,
                                      child: Tooltip(
                                        message: r.itemCode.isNotEmpty
                                            ? '${r.skuName}\nكود الصنف: ${r.itemCode} • الباركود: ${r.barcode} • شد الكرتونة: ${r.unitsPerCarton}'
                                            : r.skuName,
                                        child: Text(
                                          r.skuName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.0),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // 2. HORIZONTALLY SCROLLABLE METRICS PANE (Expands to 100% of container)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Scrollable Header
                            Container(
                              height: _headerHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                border: Border(
                                  bottom: BorderSide(color: colorScheme.outlineVariant),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'retailerChain',
                                    label: 'Chain',
                                    width: colChainWidth,
                                  ),
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'storeName',
                                    label: 'Store / Branch',
                                    width: colStoreWidth,
                                  ),
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'quantitySold',
                                    label: 'Quantity Sold',
                                    width: colQtyWidth,
                                    textAlign: TextAlign.end,
                                  ),
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'unitPrice',
                                    label: 'Unit Price',
                                    width: colUnitPriceWidth,
                                    textAlign: TextAlign.end,
                                  ),
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'netRevenue',
                                    label: 'Net Revenue (EGP)',
                                    width: colNetRevenueWidth,
                                    textAlign: TextAlign.end,
                                  ),
                                  _buildSortableHeaderCell(
                                    context: context,
                                    columnKey: 'transactionDate',
                                    label: 'Sales Date',
                                    width: colDateWidth,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            // Scrollable Data Rows
                            ...pageRecords.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final r = entry.value;
                              final isEven = idx % 2 == 0;
                              final brandStyle = _getChainBrandStyle(r.retailerChain, colorScheme);

                              return Container(
                                height: _rowHeight,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                decoration: BoxDecoration(
                                  color: isEven
                                      ? Colors.transparent
                                      : colorScheme.surfaceContainerHighest.withOpacity(0.12),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: colorScheme.outlineVariant.withOpacity(0.3),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: colChainWidth,
                                      child: Align(
                                        alignment: AlignmentDirectional.centerStart,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                          decoration: BoxDecoration(
                                            color: brandStyle.background,
                                            borderRadius: M3Shape.radiusSm,
                                            border: Border.all(
                                              color: brandStyle.border,
                                              width: 1.0,
                                            ),
                                          ),
                                          child: Text(
                                            brandStyle.displayNameEn,
                                            style: TextStyle(
                                              color: brandStyle.foreground,
                                              fontSize: 11.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: colStoreWidth,
                                      child: Text(
                                        r.storeName,
                                        style: const TextStyle(fontSize: 12.0),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: colQtyWidth,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${CurrencyFormatter.formatUnits(r.quantitySold)} units',
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                          ),
                                          if (r.cartonsSold > 0)
                                            Text(
                                              '${r.cartonsSold.toStringAsFixed(1)} كرتونة (${r.unitsPerCarton}/ك)',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: colUnitPriceWidth,
                                      child: Tooltip(
                                        message: (r.recommendedPrice > 0 || r.factoryUnitCost > 0)
                                            ? 'سعر الكارتة: ${r.recommendedPrice.toStringAsFixed(2)} ج.م • تكلفة المصنع للقطعة: ${r.factoryUnitCost.toStringAsFixed(2)} ج.م • صافي الكرتونة: ${r.netCartonInvoiceCost.toStringAsFixed(2)} ج.م • انحراف السعر: ${r.priceDeltaPct >= 0 ? "+" : ""}${r.priceDeltaPct.toStringAsFixed(1)}%'
                                            : '${r.unitPrice.toStringAsFixed(2)} EGP',
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${r.unitPrice.toStringAsFixed(2)} EGP',
                                              textAlign: TextAlign.end,
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                            ),
                                            if (r.recommendedPrice > 0 || r.factoryUnitCost > 0)
                                              Text(
                                                'كارتة ${r.recommendedPrice.toStringAsFixed(2)} • مصنع ${r.factoryUnitCost.toStringAsFixed(2)}',
                                                textAlign: TextAlign.end,
                                                style: TextStyle(
                                                  fontSize: 9.0,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: colNetRevenueWidth,
                                      child: Tooltip(
                                        message: (r.retailerMarginPct != 0 || r.retailerGrossProfit != 0)
                                            ? 'مجمل ربح السلسلة: ${CurrencyFormatter.formatUnits(r.retailerGrossProfit.round())} ج.م (${r.retailerMarginPct.toStringAsFixed(1)}%) • انحراف السعر: ${r.priceDeltaPct >= 0 ? "+" : ""}${r.priceDeltaPct.toStringAsFixed(1)}%'
                                            : '${CurrencyFormatter.formatUnits(r.netRevenue.round())} EGP',
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${CurrencyFormatter.formatUnits(r.netRevenue.round())} EGP',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11.5,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                            if (r.retailerMarginPct != 0 || r.retailerGrossProfit != 0)
                                              Text(
                                                'هامش ${r.retailerMarginPct.toStringAsFixed(1)}% (${CurrencyFormatter.formatUnits(r.retailerGrossProfit.round())} ج)',
                                                textAlign: TextAlign.end,
                                                style: TextStyle(
                                                  fontSize: 9.0,
                                                  fontWeight: FontWeight.w700,
                                                  color: r.retailerMarginPct < 0
                                                      ? colorScheme.error
                                                      : colorScheme.secondary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: colDateWidth,
                                      child: Text(
                                        r.transactionDate,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 11.0),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // M3 Pagination Footer Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.25),
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16.0,
              runSpacing: 8.0,
              children: [
                Text(
                  'Showing ${startIndex + 1} - $endIndex of $totalCount rows',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Rows per page:',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6.0),
                        M3Dropdown<int>(
                          key: const ValueKey('rows_per_page_dropdown'),
                          width: 96.0,
                          value: _rowsPerPage,
                          options: const [
                            M3DropdownOption(10, '10'),
                            M3DropdownOption(25, '25'),
                            M3DropdownOption(50, '50'),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _rowsPerPage = val;
                              _currentPage = 0;
                            });
                          },
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('pagination_prev_btn'),
                          icon: const Icon(Icons.chevron_left_rounded, size: 20.0),
                          tooltip: 'Previous Page',
                          visualDensity: VisualDensity.compact,
                          onPressed: safePage > 0
                              ? () => setState(() => _currentPage = safePage - 1)
                              : null,
                        ),
                        Text(
                          'Page ${safePage + 1} of $totalPages',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('pagination_next_btn'),
                          icon: const Icon(Icons.chevron_right_rounded, size: 20.0),
                          tooltip: 'Next Page',
                          visualDensity: VisualDensity.compact,
                          onPressed: safePage < totalPages - 1
                              ? () => setState(() => _currentPage = safePage + 1)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  ChainBrandStyle _getChainBrandStyle(String chain, ColorScheme colorScheme) {
    final c = chain.toLowerCase().trim();
    if (c.contains('beet') || c.contains('بيت الجملة') || c.contains('بيت_الجملة')) {
      return const ChainBrandStyle(
        background: Color(0xFFF3E8FF),
        border: Color(0xFFD8B4FE),
        foreground: Color(0xFF6B21A8),
        accent: Color(0xFF9333EA),
        icon: Icons.storefront_rounded,
        displayNameAr: 'بيت الجملة',
        displayNameEn: 'Beet El-Gomla',
      );
    }
    if (c.contains('مؤسسات') ||
        c.contains('institution') ||
        c.contains('corporate') ||
        c.contains('شركات') ||
        c.contains('b2b')) {
      return const ChainBrandStyle(
        background: Color(0xFFCCFBF1),
        border: Color(0xFF99F6E4),
        foreground: Color(0xFF0F766E),
        accent: Color(0xFF0D9488),
        icon: Icons.corporate_fare_rounded,
        displayNameAr: 'قطاع المؤسسات',
        displayNameEn: 'Institutions',
      );
    }
    if (c.contains('fathalla') || c.contains('فتح الله')) {
      return const ChainBrandStyle(
        background: Color(0xFFDBEAFE),
        border: Color(0xFFBFDBFE),
        foreground: Color(0xFF1D4ED8),
        accent: Color(0xFF2563EB),
        icon: Icons.shopping_bag_rounded,
        displayNameAr: 'أسواق فتح الله',
        displayNameEn: 'Fathalla',
      );
    }
    if (c.contains('gomla') || c.contains('جملة')) {
      return const ChainBrandStyle(
        background: Color(0xFFFEF3C7),
        border: Color(0xFFFDE68A),
        foreground: Color(0xFFB45309),
        accent: Color(0xFFD97706),
        icon: Icons.local_offer_rounded,
        displayNameAr: 'جملة ماركت',
        displayNameEn: 'Gomla Market',
      );
    }
    if (c.contains('carrefour') || c.contains('كارفور')) {
      return const ChainBrandStyle(
        background: Color(0xFFE0F2FE),
        border: Color(0xFFBAE6FD),
        foreground: Color(0xFF0369A1),
        accent: Color(0xFF0284C7),
        icon: Icons.local_grocery_store_rounded,
        displayNameAr: 'كارفور مصر',
        displayNameEn: 'Carrefour',
      );
    }
    if (c.contains('spinneys') || c.contains('سبينيس')) {
      return const ChainBrandStyle(
        background: Color(0xFFD1FAE5),
        border: Color(0xFFA7F3D0),
        foreground: Color(0xFF047857),
        accent: Color(0xFF059669),
        icon: Icons.shopping_basket_rounded,
        displayNameAr: 'سبينيس مصر',
        displayNameEn: 'Spinneys',
      );
    }
    if (c.contains('metro') || c.contains('مترو')) {
      return const ChainBrandStyle(
        background: Color(0xFFFFE4E6),
        border: Color(0xFFFECDD3),
        foreground: Color(0xFFBE123C),
        accent: Color(0xFFE11D48),
        icon: Icons.store_mall_directory_rounded,
        displayNameAr: 'مترو ماركت',
        displayNameEn: 'Metro',
      );
    }
    if (c.contains('seoudi') || c.contains('سعودي')) {
      return const ChainBrandStyle(
        background: Color(0xFFFEF9C3),
        border: Color(0xFFFEF08A),
        foreground: Color(0xFFA16207),
        accent: Color(0xFFCA8A04),
        icon: Icons.stars_rounded,
        displayNameAr: 'سعودي ماركت',
        displayNameEn: 'Seoudi',
      );
    }
    return ChainBrandStyle(
      background: colorScheme.surfaceContainerHigh,
      border: colorScheme.outlineVariant,
      foreground: colorScheme.onSurface,
      accent: colorScheme.primary,
      icon: Icons.store_rounded,
      displayNameAr: chain,
      displayNameEn: chain,
    );
  }
}

/// Design tokens and visual styling for a retailer chain badge.
class ChainBrandStyle {
  final Color background;
  final Color border;
  final Color foreground;
  final Color accent;
  final IconData icon;
  final String displayNameAr;
  final String displayNameEn;

  const ChainBrandStyle({
    required this.background,
    required this.border,
    required this.foreground,
    required this.accent,
    required this.icon,
    required this.displayNameAr,
    required this.displayNameEn,
  });
}
