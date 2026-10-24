import 'package:flutter/material.dart';
import '../theme/m3_shape.dart';
import 'table_scroll_container.dart';

/// Shared M3 data table: a themed [DataTable] (see `dataTableTheme`) inside an
/// outlined container with horizontal scrolling via [TableScrollContainer].
class M3DataTable extends StatelessWidget {
  const M3DataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.title,
    this.subtitle,
    this.trailing,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.showCheckboxColumn = false,
    this.compact = false,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final int? sortColumnIndex;
  final bool sortAscending;
  final bool showCheckboxColumn;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final table = DataTable(
      columns: columns,
      rows: rows,
      sortColumnIndex: sortColumnIndex,
      sortAscending: sortAscending,
      showCheckboxColumn: showCheckboxColumn,
      dataRowMinHeight: compact ? 36.0 : null,
      dataRowMaxHeight: compact ? 40.0 : null,
      headingRowHeight: compact ? 40.0 : null,
    );
    return TableScrollContainer(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: table,
    );
  }
}
