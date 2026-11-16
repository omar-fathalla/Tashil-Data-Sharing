import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_palette.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_table_surface.dart';

/// Catalog columns in reading order (RTL: first = rightmost).
enum PmCatalogColumn {
  barcode,
  name,
  brand,
  pack,
  priceExcl,
  priceIncl,
  carton,
  net,
  type,
  actions,
}

/// Layout spec of one catalog column. [width] includes the cell's 8dp
/// inline padding on both sides (16dp between cell contents).
class PmColumnSpec {
  final PmCatalogColumn id;
  final String label;
  final String tooltip;
  final double width;
  final bool numeric;

  /// null = always shown. Otherwise, when the table is too narrow, columns
  /// with the lowest priority are hidden first (the user can bring them back
  /// from the columns menu).
  final int? priority;

  const PmColumnSpec(
    this.id,
    this.label,
    this.tooltip,
    this.width, {
    this.numeric = false,
    this.priority,
  });

  bool get hideable => priority != null;
}

/// Catalog table geometry (M3 data table).
abstract final class PmCatalogTableStyle {
  static const double headerHeight = 56.0;
  static const double rowHeight = 56.0;
  static const double cellPadding = 8.0;
  static const double outerPadding = 24.0;

  /// Product name: flexible, never below this.
  static const double nameMinWidth = 240.0;

  /// Floor for the name column when the user forces more columns than fit.
  static const double nameHardMinWidth = 160.0;

  static const double outerExtra = 2 * (outerPadding - cellPadding);

  static const List<PmColumnSpec> columns = [
    PmColumnSpec(PmCatalogColumn.barcode, 'الباركود / الكود',
        'Barcode / Item code', 156.0),
    PmColumnSpec(
        PmCatalogColumn.name, 'اسم الصنف', 'Official SKU name', nameMinWidth),
    PmColumnSpec(
        PmCatalogColumn.brand, 'العلامة / الفئة', 'Brand / Category', 140.0,
        priority: 60),
    PmColumnSpec(
        PmCatalogColumn.pack, 'التعبئة', 'Units per carton / Pack', 104.0,
        numeric: true, priority: 10),
    PmColumnSpec(
        PmCatalogColumn.priceExcl, 'سعر الوحدة', 'Unit price excl. VAT', 104.0,
        numeric: true, priority: 20),
    PmColumnSpec(
        PmCatalogColumn.priceIncl, 'السعر ش.ض', 'Unit price incl. VAT', 112.0,
        numeric: true),
    PmColumnSpec(
        PmCatalogColumn.carton, 'سعر الكرتونة', 'Carton price incl. VAT', 104.0,
        numeric: true, priority: 40),
    PmColumnSpec(PmCatalogColumn.net, 'الصافي', 'Net invoice cost', 104.0,
        numeric: true, priority: 70),
    PmColumnSpec(PmCatalogColumn.type, 'النوع / السحب',
        'Item type / Chain pull status', 120.0),
    PmColumnSpec(PmCatalogColumn.actions, '', 'Actions', 56.0),
  ];

  static PmColumnSpec spec(PmCatalogColumn id) =>
      columns.firstWhere((c) => c.id == id);

  /// Columns shown at [tableWidth] before any user override: every
  /// always-on column, then hideable ones by priority while they fit.
  static Set<PmCatalogColumn> autoVisible(double tableWidth) {
    final visible = <PmCatalogColumn>{
      for (final c in columns)
        if (!c.hideable) c.id,
    };
    var used = outerExtra +
        columns
            .where((c) => !c.hideable)
            .fold<double>(0, (a, c) => a + c.width);
    final byPriority = columns.where((c) => c.hideable).toList()
      ..sort((a, b) => b.priority!.compareTo(a.priority!));
    for (final c in byPriority) {
      if (used + c.width > tableWidth) break;
      used += c.width;
      visible.add(c.id);
    }
    return visible;
  }

  /// Visible columns after applying the user's [overrides] (true = show).
  static List<PmCatalogColumn> visibleColumns(
      double tableWidth, Map<PmCatalogColumn, bool> overrides) {
    final auto = autoVisible(tableWidth);
    return [
      for (final c in columns)
        if (!c.hideable || (overrides[c.id] ?? auto.contains(c.id))) c.id,
    ];
  }

  /// Column widths for [visible] that fill [tableWidth] exactly.
  /// Spare width goes to the name column. When the user forced more columns
  /// than fit, the name column shrinks first, then every column except the
  /// barcode (which must show 13 digits) shrinks proportionally, so nothing
  /// is cut off at the edge.
  static Map<PmCatalogColumn, double> widths(
      double tableWidth, List<PmCatalogColumn> visible) {
    final w = {for (final id in visible) id: spec(id).width};
    final available = tableWidth - outerExtra;
    final sum = w.values.fold<double>(0, (a, b) => a + b);
    var leftover = available - sum;
    if (leftover >= 0) {
      w[PmCatalogColumn.name] = w[PmCatalogColumn.name]! + leftover;
      return w;
    }
    final nameCut =
        math.min(-leftover, w[PmCatalogColumn.name]! - nameHardMinWidth);
    w[PmCatalogColumn.name] = w[PmCatalogColumn.name]! - nameCut;
    leftover += nameCut;
    if (leftover < 0) {
      final shrinkable = w.entries
          .where((e) => e.key != PmCatalogColumn.barcode)
          .fold<double>(0, (a, e) => a + e.value);
      final factor = math.max(0.0, (shrinkable + leftover) / shrinkable);
      for (final id in w.keys.toList()) {
        if (id != PmCatalogColumn.barcode) w[id] = w[id]! * factor;
      }
    }
    return w;
  }
}

/// Merged barcode (top) + item code (below) cell. Tap copies the barcode.
class PmBarcodeCodeCell extends StatelessWidget {
  final String barcode;
  final String itemCode;
  final VoidCallback? onCopy;

  const PmBarcodeCodeCell({
    super.key,
    required this.barcode,
    required this.itemCode,
    this.onCopy,
  });

  static String semanticsLabelFor(String barcode, String itemCode) =>
      'باركود $barcode، كود $itemCode';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const tabular = [FontFeature.tabularFigures()];
    final lines = Directionality(
      textDirection: TextDirection.ltr,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              barcode.isEmpty ? '—' : barcode,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              itemCode,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: semanticsLabelFor(barcode, itemCode),
      button: onCopy != null,
      excludeSemantics: true,
      child: Tooltip(
        message: 'نسخ الباركود',
        child: InkWell(
          onTap: onCopy,
          borderRadius: M3Shape.radiusSm,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: lines,
          ),
        ),
      ),
    );
  }
}

/// Product Master catalog table: sticky 56dp header, 56dp two-line rows,
/// 1dp dividers, onSurface 8% hover, footer with the row range and paging.
/// Returns slivers so the header can stay pinned while the page scrolls.
class PmCatalogTable {
  PmCatalogTable._();

  static final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _int = NumberFormat('#,###', 'en_US');
  static const _tabular = [FontFeature.tabularFigures()];

  static List<Widget> slivers({
    required BuildContext context,
    required double tableWidth,
    required List<PmCatalogColumn> visible,
    required List<ProductMasterItemModel> pageItems,
    required int totalCount,
    required int startIndex,
    required int page,
    required int pageCount,
    required double defaultDiscountPct,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<ProductMasterItemModel> onOpenItem,
  }) {
    final cs = Theme.of(context).colorScheme;
    final widths = PmCatalogTableStyle.widths(tableWidth, visible);
    final surface = M3TableSurface.color(cs);
    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _HeaderDelegate(
          visible: visible,
          widths: widths,
          background: surface,
          defaultDiscountPct: defaultDiscountPct,
        ),
      ),
      if (pageItems.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded,
                    size: 48, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('لا توجد أصناف مطابقة لمعايير البحث الحالية',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: pageItems.length,
          itemBuilder: (context, i) => _Row(
            key: ValueKey('pm_catalog_row_${pageItems[i].itemCode}'),
            item: pageItems[i],
            visible: visible,
            widths: widths,
            onOpen: () => onOpenItem(pageItems[i]),
          ),
        ),
      SliverToBoxAdapter(
        child: _Footer(
          totalCount: totalCount,
          startIndex: startIndex,
          shown: pageItems.length,
          page: page,
          pageCount: pageCount,
          onPageChanged: onPageChanged,
        ),
      ),
    ];
  }

  static EdgeInsetsDirectional _cellPadding(
      List<PmCatalogColumn> visible, PmCatalogColumn id) {
    const p = PmCatalogTableStyle.cellPadding;
    const outer = PmCatalogTableStyle.outerPadding;
    return EdgeInsetsDirectional.only(
      start: id == visible.first ? outer : p,
      end: id == visible.last ? outer : p,
    );
  }

  static double _cellWidth(List<PmCatalogColumn> visible,
      Map<PmCatalogColumn, double> widths, PmCatalogColumn id) {
    const extra =
        PmCatalogTableStyle.outerPadding - PmCatalogTableStyle.cellPadding;
    var w = widths[id]!;
    if (id == visible.first) w += extra;
    if (id == visible.last) w += extra;
    return w;
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<PmCatalogColumn> visible;
  final Map<PmCatalogColumn, double> widths;
  final Color background;
  final double defaultDiscountPct;

  _HeaderDelegate({
    required this.visible,
    required this.widths,
    required this.background,
    required this.defaultDiscountPct,
  });

  static const double _extent = PmCatalogTableStyle.headerHeight + 1.0;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      key: const ValueKey('pm_catalog_header'),
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final id in visible)
            SizedBox(
              width: PmCatalogTable._cellWidth(visible, widths, id),
              height: PmCatalogTableStyle.headerHeight,
              child: Padding(
                padding: PmCatalogTable._cellPadding(visible, id),
                child: Align(
                  alignment: PmCatalogTableStyle.spec(id).numeric
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Tooltip(
                    message: _tooltip(id),
                    child: Text(
                      PmCatalogTableStyle.spec(id).label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: PmCatalogTableStyle.spec(id).numeric
                          ? TextAlign.end
                          : TextAlign.start,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _tooltip(PmCatalogColumn id) => id == PmCatalogColumn.net
      ? 'صافي تكلفة الفاتورة بعد خصم ${defaultDiscountPct.toStringAsFixed(0)}%'
      : PmCatalogTableStyle.spec(id).tooltip;

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.visible != visible ||
      old.widths.toString() != widths.toString() ||
      old.background != background ||
      old.defaultDiscountPct != defaultDiscountPct;
}

class _Row extends StatelessWidget {
  final ProductMasterItemModel item;
  final List<PmCatalogColumn> visible;
  final Map<PmCatalogColumn, double> widths;
  final VoidCallback onOpen;

  const _Row({
    super.key,
    required this.item,
    required this.visible,
    required this.widths,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        hoverColor: cs.onSurface.withValues(alpha: 0.08),
        child: Container(
          constraints:
              const BoxConstraints(minHeight: PmCatalogTableStyle.rowHeight),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              for (final id in visible)
                SizedBox(
                  width: PmCatalogTable._cellWidth(visible, widths, id),
                  child: Padding(
                    padding: PmCatalogTable._cellPadding(visible, id)
                        .add(const EdgeInsets.symmetric(vertical: 2.0)),
                    child: Align(
                      alignment: PmCatalogTableStyle.spec(id).numeric
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: _cell(context, id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, PmCatalogColumn id) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primary = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      fontFeatures: PmCatalogTable._tabular,
    );
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontFeatures: PmCatalogTable._tabular,
    );
    Widget twoLine(String top, String? bottom,
        {TextStyle? topStyle, bool numeric = false, Key? key}) {
      return Column(
        key: key,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            numeric ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(top,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: topStyle ?? primary),
          if (bottom != null && bottom.isNotEmpty) ...[
            const SizedBox(height: 2.0),
            Text(bottom,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
          ],
        ],
      );
    }

    final money = PmCatalogTable._money;
    switch (id) {
      case PmCatalogColumn.barcode:
        return PmBarcodeCodeCell(
          key: ValueKey('pm_barcode_cell_${item.itemCode}'),
          barcode: item.barcode,
          itemCode: item.itemCode,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: item.barcode));
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('تم النسخ')));
          },
        );
      case PmCatalogColumn.name:
        return Tooltip(
          message: item.officialName,
          child: Text(
            item.officialName,
            key: ValueKey('pm_row_name_${item.itemCode}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case PmCatalogColumn.brand:
        return twoLine(item.brand, item.category);
      case PmCatalogColumn.pack:
        return twoLine('${item.unitsPerCarton} / كرتونة', item.packagingType,
            numeric: true);
      case PmCatalogColumn.priceExcl:
        return Text(money.format(item.unitPriceExclVat), style: primary);
      case PmCatalogColumn.priceIncl:
        return _priceWithChange(context, primary, secondary);
      case PmCatalogColumn.carton:
        return Text(money.format(item.cartonPriceInclVat), style: primary);
      case PmCatalogColumn.net:
        return twoLine(
          money.format(item.netUnitInvoiceCost),
          'كرتونة: ${money.format(item.netCartonInvoiceCost)}',
          topStyle: primary?.copyWith(
              color: M3Palette.teal, fontWeight: FontWeight.w700),
          numeric: true,
        );
      case PmCatalogColumn.type:
        return _typeCell(context);
      case PmCatalogColumn.actions:
        return IconButton(
          icon: const Icon(Icons.badge_rounded, size: 20.0),
          tooltip: 'بطاقة تعريف الصنف وتعديل السعر',
          onPressed: onOpen,
        );
    }
  }

  Widget _priceWithChange(
      BuildContext context, TextStyle? primary, TextStyle? secondary) {
    final dir = item.priceChangeDirection.toLowerCase();
    final isUp = dir == 'up', isDown = dir == 'down', isNew = dir == 'new';
    final hasPrev = item.prevUnitPriceInclVat > 0;
    final price = Text(
      PmCatalogTable._money.format(item.unitPriceInclVat),
      maxLines: 1,
      style: primary?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!isUp && !isDown && !isNew) return price;
    final color = isUp
        ? M3Palette.danger
        : isDown
            ? M3Palette.teal
            : M3Palette.info;
    final label = isNew
        ? 'جديد'
        : (!hasPrev || item.priceChangePct == 0)
            ? '—'
            : CurrencyFormatter.formatSignedPct(item.priceChangePct);
    final tip = isNew
        ? 'صنف جديد في آخر شيت'
        : hasPrev
            ? 'كان: ${PmCatalogTable._money.format(item.prevUnitPriceInclVat)} ج.م'
            : 'لا يوجد سعر سابق للمقارنة';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        price,
        const SizedBox(height: 2.0),
        Tooltip(
          message: tip,
          child: Row(
            key: ValueKey('price_indicator_${item.itemCode}_$dir'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp
                    ? Icons.trending_up_rounded
                    : isDown
                        ? Icons.trending_down_rounded
                        : Icons.fiber_new_rounded,
                size: 14.0,
                color: color,
              ),
              const SizedBox(width: 2.0),
              Text(label, style: secondary?.copyWith(color: color)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeCell(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPromo = item.itemType == 'عرض';
    final typeColor = isPromo ? M3Palette.amberDeep : M3Palette.teal;
    final caption = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final detail = item.isActiveInChains
        ? (item.totalPosUnitsSold > 0
            ? 'مسحوب ونشط بالسلاسل · ${PmCatalogTable._int.format(item.totalPosUnitsSold)} وحدة'
            : 'مسحوب ونشط بالسلاسل')
        : 'غير مسحوب · فرصة توزيع';
    return DecoratedBox(
      key: ValueKey('pm_row_type_strip_${item.itemCode}'),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start:
              BorderSide(color: typeColor.withValues(alpha: 0.55), width: 4.0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            M3ChipSurface(
              key: ValueKey('pm_row_type_chip_${item.itemCode}'),
              color: typeColor.withValues(alpha: 0.14),
              child: Text(
                isPromo ? 'عرض' : 'عادي',
                maxLines: 1,
                softWrap: false,
                style: M3ChipStyle.labelStyle(context, color: typeColor),
              ),
            ),
            const SizedBox(height: 2.0),
            Tooltip(
              message: detail,
              child: Text(
                item.isActiveInChains ? 'مسحوب' : 'غير مسحوب',
                key: ValueKey('pm_row_pull_${item.itemCode}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int totalCount;
  final int startIndex;
  final int shown;
  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  const _Footer({
    required this.totalCount,
    required this.startIndex,
    required this.shown,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = PmCatalogTable._int;
    final label = totalCount == 0
        ? '0 صنف'
        : 'عرض ${fmt.format(startIndex + 1)}–${fmt.format(startIndex + shown)} من ${fmt.format(totalCount)} صنف';
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 4.0, 16.0, 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              key: const ValueKey('pm_catalog_footer_count'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: PmCatalogTable._tabular,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('pm_catalog_prev_page'),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'الصفحة السابقة',
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
          ),
          IconButton(
            key: const ValueKey('pm_catalog_next_page'),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'الصفحة التالية',
            onPressed:
                page < pageCount - 1 ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}
