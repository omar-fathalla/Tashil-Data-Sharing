import 'package:flutter/material.dart';
import '../theme/m3_shape.dart';

/// A Material Design 3 container for DataTables and wide tabular content.
///
/// Features:
/// 1. Prominent Right & Left arrow navigation buttons ("يمين" and "شمال") to smoothly
///    slide wide tables horizontally on touch screens and desktop.
/// 2. Always-visible, interactive horizontal scrollbar with track visibility and comfortable touch thickness.
/// 3. Directionality-aware scrolling (automatically handles Arabic RTL and English LTR correctly).
/// 4. Integrated touch swipe hint indicator.
/// 5. Automatically handles its own ScrollController if none is provided.
class TableScrollContainer extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final String? title;
  final String? subtitle;
  final Widget? icon;
  final Widget? trailing;
  final double scrollStep;
  final bool showControls;
  final bool showSwipeHint;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;

  const TableScrollContainer({
    super.key,
    required this.child,
    this.controller,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.scrollStep = 320.0,
    this.showControls = true,
    this.showSwipeHint = true,
    this.padding,
    this.decoration,
  });

  @override
  State<TableScrollContainer> createState() => _TableScrollContainerState();
}

class _TableScrollContainerState extends State<TableScrollContainer> {
  ScrollController? _internalController;

  ScrollController get _effectiveController =>
      widget.controller ?? (_internalController ??= ScrollController());

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _scrollRight() {
    final controller = _effectiveController;
    if (!controller.hasClients) return;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final max = controller.position.maxScrollExtent;
    // In RTL, 0.0 is the far right (start). Decreasing offset scrolls back towards the right.
    // In LTR, increasing offset scrolls towards the right.
    final delta = isRtl ? -widget.scrollStep : widget.scrollStep;
    final target = (controller.offset + delta).clamp(0.0, max);

    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollLeft() {
    final controller = _effectiveController;
    if (!controller.hasClients) return;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final max = controller.position.maxScrollExtent;
    // In RTL, increasing offset scrolls towards the left (remaining hidden columns).
    // In LTR, decreasing offset scrolls towards the left.
    final delta = isRtl ? widget.scrollStep : -widget.scrollStep;
    final target = (controller.offset + delta).clamp(0.0, max);

    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildScrollControls(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withOpacity(0.5),
        borderRadius: M3Shape.radiusSm,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSwipeHint && !compact) ...[
            Icon(
              Icons.swipe_rounded,
              size: 15.0,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6.0),
            Text(
              'اسحب أو تحرك:',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8.0),
          ],
          // Right Button
          Tooltip(
            message: 'تحريك الجدول لليمين (الأعمدة الأولى)',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: M3Shape.radiusSm,
                onTap: _scrollRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 5.0,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: M3Shape.radiusSm,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14.0,
                        color: colorScheme.onSurface,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        'يمين',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6.0),
          // Left Button
          Tooltip(
            message: 'تحريك الجدول لليسار (باقي الأعمدة)',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: M3Shape.radiusSm,
                onTap: _scrollLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 5.0,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: M3Shape.radiusSm,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'شمال',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 14.0,
                        color: colorScheme.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasHeader = widget.title != null ||
        widget.subtitle != null ||
        widget.trailing != null ||
        widget.showControls;

    return Container(
      decoration: widget.decoration,
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 640;

                  final titleSection = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        widget.icon!,
                        const SizedBox(width: 8.0),
                      ],
                      if (widget.title != null)
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title!,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2.0),
                                Text(
                                  widget.subtitle!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  );

                  final isVeryNarrow = constraints.maxWidth < 460;
                  final actionsSection = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.trailing != null) ...[
                        widget.trailing!,
                        const SizedBox(width: 8.0),
                      ],
                      if (widget.showControls)
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: _buildScrollControls(context, compact: isVeryNarrow),
                          ),
                        ),
                    ],
                  );

                  final hasTitleOrIcon = widget.title != null || widget.icon != null;

                  if (!hasTitleOrIcon) {
                    return Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actionsSection,
                    );
                  }

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titleSection,
                        const SizedBox(height: 8.0),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: actionsSection,
                        ),
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: titleSection),
                      const SizedBox(width: 12.0),
                      actionsSection,
                    ],
                  );
                },
              ),
            ),
          ],

          // Scrollable Table Area with Always-Visible Scrollbar & Full-Width Column Expansion
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              return Scrollbar(
                controller: _effectiveController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                thickness: 9.0,
                radius: const Radius.circular(8.0),
                child: SingleChildScrollView(
                  controller: _effectiveController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: _buildExpandedChild(widget.child, availableWidth),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedChild(Widget child, double availableWidth) {
    if (availableWidth <= 0) return child;

    DataTable? dt;
    if (child is DataTable) {
      dt = child;
    } else if (child is ConstrainedBox && child.child is DataTable) {
      dt = child.child as DataTable;
    }

    if (dt != null && dt.columns.isNotEmpty) {
      final colCount = dt.columns.length;
      final hMargin = dt.horizontalMargin ?? 24.0;
      final colSpacing = dt.columnSpacing ??
          ((availableWidth - (colCount * 115.0)) /
                  (colCount > 1 ? colCount - 1 : 1))
              .clamp(24.0, 56.0);
      final rawMinColWidth =
          (availableWidth - (2 * hMargin) - ((colCount - 1) * colSpacing)) /
              colCount;
      final minColWidth = rawMinColWidth.clamp(0.0, double.infinity);

      final expandedColumns = dt.columns.map((col) {
        final sortAllowance = col.onSort != null ? 20.0 : 0.0;
        final colMin =
            (minColWidth - sortAllowance).clamp(0.0, double.infinity);
        return DataColumn(
          numeric: col.numeric,
          tooltip: col.tooltip,
          onSort: col.onSort,
          mouseCursor: col.mouseCursor,
          headingRowAlignment: col.headingRowAlignment,
          label: ConstrainedBox(
            constraints: BoxConstraints(minWidth: colMin),
            child: Align(
              alignment: col.numeric
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              widthFactor: 1.0,
              child: col.label,
            ),
          ),
        );
      }).toList();

      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: availableWidth),
        child: DataTable(
          key: dt.key,
          columns: expandedColumns,
          sortColumnIndex: dt.sortColumnIndex,
          sortAscending: dt.sortAscending,
          onSelectAll: dt.onSelectAll,
          decoration: dt.decoration,
          dataRowColor: dt.dataRowColor,
          dataRowMinHeight: dt.dataRowMinHeight,
          dataRowMaxHeight: dt.dataRowMaxHeight,
          dataTextStyle: dt.dataTextStyle,
          headingRowColor: dt.headingRowColor,
          headingRowHeight: dt.headingRowHeight,
          headingTextStyle: dt.headingTextStyle,
          horizontalMargin: hMargin,
          columnSpacing: colSpacing,
          showCheckboxColumn: dt.showCheckboxColumn,
          showBottomBorder: dt.showBottomBorder,
          dividerThickness: dt.dividerThickness,
          rows: dt.rows,
          checkboxHorizontalMargin: dt.checkboxHorizontalMargin,
          border: dt.border,
          clipBehavior: dt.clipBehavior,
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: availableWidth),
      child: child,
    );
  }
}
