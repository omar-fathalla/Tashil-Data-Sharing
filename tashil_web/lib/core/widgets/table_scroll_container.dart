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

  /// Optional column pinned at the inline end (left in RTL), outside the
  /// horizontal scroll view, e.g. a row-actions column that must stay on
  /// screen. Its rows must use the same heights as the table's rows.
  final Widget? pinnedEnd;

  /// Optional key column pinned at the inline start (right in RTL), outside
  /// the horizontal scroll view, e.g. the item name, so it stays on screen
  /// while the other columns scroll. Its rows must use the table's heights.
  final Widget? pinnedStart;

  /// Optional relative widths for a DataTable child. The table still fills the
  /// available width, but the extra space is split by these weights instead of
  /// equally, so a wide column (e.g. a status chip) gets more room and narrow
  /// ones less. Length must match the column count; otherwise ignored.
  final List<double>? columnFlex;

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
    this.pinnedEnd,
    this.columnFlex,
    this.pinnedStart,
  });

  @override
  State<TableScrollContainer> createState() => _TableScrollContainerState();
}

class _TableScrollContainerState extends State<TableScrollContainer> {
  ScrollController? _internalController;

  ScrollController get _effectiveController =>
      widget.controller ?? (_internalController ??= ScrollController());

  /// The 'يمين / شمال' controls only show while the table really overflows
  /// horizontally (maxScrollExtent > 0); re-checked after every layout and
  /// whenever the scroll metrics change (resize, data change).
  bool _overflows = false;

  /// Thickness of the horizontal scrollbar. While the table overflows, the
  /// scroll area reserves this (plus a small gap) below the rows so the
  /// scrollbar never covers the last row's content.
  static const double _scrollbarThickness = 9.0;
  static const double _scrollbarGap = 4.0;

  /// DataTable fitting: column shares from [columnFlex] are only minimums, so
  /// a column whose content is wider than its share pushes the table past
  /// the available width even when the natural columns would fit. When that
  /// happens the shares are computed for a width reduced by the overflow
  /// (others give up slack, content-bound columns keep their size) until the
  /// table fits or the shares run out. Reset when the width or row count
  /// changes. The table never ends up narrower than the available width.
  double _shrink = 0.0;
  int _shrinkSteps = 0;
  double _shrinkForWidth = -1.0;
  int _shrinkForRows = -1;
  bool _fitsDataTable = false;
  bool _shrinkPending = false;
  static const int _maxShrinkSteps = 8;

  void _setOverflow(double maxScrollExtent) {
    // Ignore sub-pixel rounding (< 2dp) from intrinsic column layout.
    final next = maxScrollExtent > 2.0;
    // Shrink even for a sub-2dp remainder so a fitting table ends with no
    // scroll extent at all (nothing for the scrollbar to paint).
    if (maxScrollExtent > 0.01 &&
        _fitsDataTable &&
        !_shrinkPending &&
        _shrinkSteps < _maxShrinkSteps &&
        mounted) {
      _shrinkPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _shrinkPending = false;
        if (!mounted) return;
        setState(() {
          _shrink += maxScrollExtent.ceilToDouble() + 1.0;
          _shrinkSteps++;
        });
      });
    }
    if (next == _overflows || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overflows != next) setState(() => _overflows = next);
    });
  }

  void _checkOverflowAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _effectiveController;
      if (!c.hasClients) return;
      final positions = c.positions.where((p) => p.hasContentDimensions);
      if (positions.isEmpty) return;
      _setOverflow(positions.first.maxScrollExtent);
    });
  }

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
              size: 18.0,
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
          OutlinedButton.icon(
            onPressed: _scrollRight,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('يمين'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
          const SizedBox(width: 6.0),
          OutlinedButton.icon(
            onPressed: _scrollLeft,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('شمال'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
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

    _checkOverflowAfterLayout();
    final showControls = widget.showControls && _overflows;
    final hasHeader = widget.title != null ||
        widget.subtitle != null ||
        widget.trailing != null ||
        showControls;

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
                      if (showControls)
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: _buildScrollControls(context,
                                compact: isVeryNarrow),
                          ),
                        ),
                    ],
                  );

                  final hasTitleOrIcon =
                      widget.title != null || widget.icon != null;

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
          if (widget.pinnedEnd != null || widget.pinnedStart != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.pinnedStart != null)
                  _pinWithScrollbarGutter(widget.pinnedStart!),
                Expanded(child: _buildScrollArea()),
                if (widget.pinnedEnd != null)
                  _pinWithScrollbarGutter(widget.pinnedEnd!),
              ],
            )
          else
            _buildScrollArea(),
        ],
      ),
    );
  }

  /// Keep frozen columns aligned with the scrollable rows when the
  /// horizontal scrollbar reserves space under the last row.
  Widget _pinWithScrollbarGutter(Widget child) {
    if (!_overflows) return child;
    return Padding(
      padding: const EdgeInsets.only(
        bottom: _scrollbarThickness + _scrollbarGap,
      ),
      child: child,
    );
  }

  Widget _buildScrollArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        return Scrollbar(
          controller: _effectiveController,
          // Only shown while the table really overflows (no empty track
          // painted over a table that fits).
          thumbVisibility: _overflows,
          trackVisibility: _overflows,
          interactive: true,
          thickness: _scrollbarThickness,
          radius: const Radius.circular(8.0),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.horizontal && n.depth == 0) {
                _setOverflow(n.metrics.maxScrollExtent);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _effectiveController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Padding(
                // Room for the scrollbar so it never covers row content.
                padding: EdgeInsets.only(
                    bottom:
                        _overflows ? _scrollbarThickness + _scrollbarGap : 0.0),
                child: _buildExpandedChild(widget.child, availableWidth),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Columns that opt in with `headingRowAlignment: MainAxisAlignment.center`
  /// get their cells centred too (header and content share one axis).
  static List<DataRow> _centerCells(DataTable dt) =>
      centerCellsUnderCenteredHeadings(dt.columns, dt.rows);

  Widget _buildExpandedChild(Widget child, double availableWidth) {
    if (availableWidth <= 0) return child;

    DataTable? dt;
    if (child is DataTable) {
      dt = child;
    } else if (child is ConstrainedBox && child.child is DataTable) {
      dt = child.child as DataTable;
    }

    _fitsDataTable = dt != null && dt.columns.isNotEmpty;
    if (dt != null && dt.columns.isNotEmpty) {
      if (availableWidth != _shrinkForWidth ||
          dt.rows.length != _shrinkForRows) {
        _shrinkForWidth = availableWidth;
        _shrinkForRows = dt.rows.length;
        _shrink = 0.0;
        _shrinkSteps = 0;
      }
      final fitWidth = (availableWidth - _shrink).clamp(0.0, double.infinity);
      final colCount = dt.columns.length;
      final hMargin = dt.horizontalMargin ?? 24.0;
      final colSpacing = dt.columnSpacing ??
          ((availableWidth - (colCount * 115.0)) /
                  (colCount > 1 ? colCount - 1 : 1))
              .clamp(24.0, 56.0);
      final rawMinColWidth =
          (fitWidth - (2 * hMargin) - ((colCount - 1) * colSpacing)) / colCount;
      final minColWidth = rawMinColWidth.clamp(0.0, double.infinity);

      final flex = widget.columnFlex;
      final useFlex =
          flex != null && flex.length == colCount && flex.every((f) => f > 0);
      final flexSum = useFlex ? flex.fold<double>(0, (a, b) => a + b) : 0.0;
      var colIndex = 0;
      final expandedColumns = dt.columns.map((col) {
        final i = colIndex++;
        final share =
            useFlex ? minColWidth * colCount * flex[i] / flexSum : minColWidth;
        // A sortable header adds the arrow (16 + 2); a centred one adds the
        // same spacer on the other side to keep the label centred.
        final sortAllowance = col.onSort == null
            ? 0.0
            : col.headingRowAlignment == MainAxisAlignment.center
                ? 36.0
                : 20.0;
        final colMin = (share - sortAllowance).clamp(0.0, double.infinity);
        return DataColumn(
          numeric: col.numeric,
          tooltip: col.tooltip,
          onSort: col.onSort,
          mouseCursor: col.mouseCursor,
          headingRowAlignment: col.headingRowAlignment,
          label: ConstrainedBox(
            constraints: BoxConstraints(minWidth: colMin),
            child: Align(
              alignment: col.headingRowAlignment == MainAxisAlignment.center
                  ? AlignmentDirectional.center
                  : col.numeric
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
          rows: _centerCells(dt),
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

/// Centres the cells of every column whose heading uses
/// `headingRowAlignment: MainAxisAlignment.center`, so header and content
/// share one axis. For DataTables not wrapped in [TableScrollContainer].
List<DataRow> centerCellsUnderCenteredHeadings(
    List<DataColumn> columns, List<DataRow> rows) {
  final centered = [
    for (final c in columns) c.headingRowAlignment == MainAxisAlignment.center,
  ];
  if (!centered.contains(true)) return rows;
  return [
    for (final r in rows)
      DataRow(
        key: r.key,
        selected: r.selected,
        onSelectChanged: r.onSelectChanged,
        onLongPress: r.onLongPress,
        color: r.color,
        mouseCursor: r.mouseCursor,
        cells: [
          for (var i = 0; i < r.cells.length; i++)
            i < centered.length && centered[i]
                ? DataCell(
                    Center(child: r.cells[i].child),
                    placeholder: r.cells[i].placeholder,
                    showEditIcon: r.cells[i].showEditIcon,
                    onTap: r.cells[i].onTap,
                    onLongPress: r.cells[i].onLongPress,
                    onTapDown: r.cells[i].onTapDown,
                    onDoubleTap: r.cells[i].onDoubleTap,
                    onTapCancel: r.cells[i].onTapCancel,
                  )
                : r.cells[i],
        ],
      ),
  ];
}
