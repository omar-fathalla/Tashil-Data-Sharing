import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_feedback.dart';
import 'barcode_scanner_dialog.dart';
import 'sell_table_shared.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';

/// CascadingFilterToolbar provides multi-dimensional cascading filter controls
/// where selecting a chain filters the available stores, and category filters SKUs.
/// Strictly follows Material Design 3 with unified heights (42dp), unified borders,
/// English export & date range labels, and a compact date range bubble dialog.
class CascadingFilterToolbar extends StatefulWidget {
  final String? selectedChain;
  final String? selectedStoreId;
  final String? selectedCategory;
  final DateTimeRange? selectedDateRange;
  final int? selectedYear;
  final String searchQuery;
  final List<String>? availableCategories;
  final Map<String, List<Map<String, String>>>? chainStoresOverride;
  final ValueChanged<String?> onChainChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;
  final ValueChanged<int?>? onYearChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onExportExcel;
  final VoidCallback? onExportPdf;
  final VoidCallback? onUpload;
  final bool isUploading;

  const CascadingFilterToolbar({
    super.key,
    required this.selectedChain,
    required this.selectedStoreId,
    required this.selectedCategory,
    this.selectedDateRange,
    this.selectedYear,
    required this.searchQuery,
    this.availableCategories,
    this.chainStoresOverride,
    required this.onChainChanged,
    required this.onStoreChanged,
    required this.onCategoryChanged,
    this.onDateRangeChanged,
    this.onYearChanged,
    required this.onSearchChanged,
    required this.onExportExcel,
    this.onExportPdf,
    this.onUpload,
    this.isUploading = false,
  });

  @override
  State<CascadingFilterToolbar> createState() => _CascadingFilterToolbarState();
}

class _CascadingFilterToolbarState extends State<CascadingFilterToolbar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant CascadingFilterToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    final scanned = await BarcodeScannerDialog.show(context);
    if (!mounted) return;
    if (scanned != null && scanned.trim().isNotEmpty) {
      final code = scanned.trim();
      setState(() {
        _searchController.text = code;
      });
      widget.onSearchChanged(code);
      M3Feedback.showSuccess(context, 'تم مسح الباركود: $code');
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Compact M3 Date Range Bubble Dialog (Pop-up bubble instead of full screen)
  Future<void> _showCompactDateRangeBubble(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    DateTime? tempStart = widget.selectedDateRange?.start ?? DateTime(2026, 1, 1);
    DateTime? tempEnd = widget.selectedDateRange?.end ?? DateTime(2026, 1, 31);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: const RoundedRectangleBorder(
                borderRadius: M3Shape.radiusLg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440.0),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                color: colorScheme.primary,
                                size: 24.0,
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                'الفترة',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20.0),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            tooltip: 'إغلاق',
                          ),
                        ],
                      ),
                      const Divider(height: 20.0),

                      // Quick preset chips
                      Text(
                        'اختيارات سريعة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 6.0,
                        children: [
                          ActionChip(
                            label: const Text('يناير 2026'),
                            avatar: const Icon(Icons.verified_rounded, size: 18.0),
                            onPressed: () {
                              setDialogState(() {
                                tempStart = DateTime(2026, 1, 1);
                                tempEnd = DateTime(2026, 1, 31);
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('آخر 7 أيام'),
                            onPressed: () {
                              final now = DateTime.now();
                              setDialogState(() {
                                tempStart = now.subtract(const Duration(days: 7));
                                tempEnd = now;
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('آخر 30 يومًا'),
                            onPressed: () {
                              final now = DateTime.now();
                              setDialogState(() {
                                tempStart = now.subtract(const Duration(days: 30));
                                tempEnd = now;
                              });
                            },
                          ),
                          ActionChip(
                            label: Text('سنة ${DateTime.now().year}'),
                            onPressed: () {
                              setDialogState(() {
                                tempStart = DateTime(DateTime.now().year, 1, 1);
                                tempEnd = DateTime(DateTime.now().year, 12, 31);
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),

                      // Date Range Pickers (Start & End)
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: M3Shape.radiusSm,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: tempStart ?? DateTime(DateTime.now().year, 1, 1),
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2030, 12, 31),
                                  helpText: 'تاريخ البداية',
                                );
                                if (picked != null) {
                                  setDialogState(() => tempStart = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                                  borderRadius: M3Shape.radiusSm,
                                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'من:',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4.0),
                                    Text(
                                      tempStart != null ? _formatDate(tempStart!) : 'YYYY-MM-DD',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: InkWell(
                              borderRadius: M3Shape.radiusSm,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: tempEnd ?? DateTime.now(),
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2030, 12, 31),
                                  helpText: 'تاريخ النهاية',
                                );
                                if (picked != null) {
                                  setDialogState(() => tempEnd = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                                  borderRadius: M3Shape.radiusSm,
                                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إلى:',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4.0),
                                    Text(
                                      tempEnd != null ? _formatDate(tempEnd!) : 'YYYY-MM-DD',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20.0),

                      // Actions
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.clear_all_rounded, size: 18.0),
                            label: const Text('إعادة الضبط'),
                            onPressed: () {
                              widget.onDateRangeChanged?.call(null);
                              Navigator.of(dialogCtx).pop();
                            },
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                                child: const Text('إلغاء'),
                              ),
                              const SizedBox(width: 8.0),
                              FilledButton(
                                key: const ValueKey('apply_date_range_button'),
                                onPressed: () {
                                  if (tempStart != null && tempEnd != null) {
                                    final start = tempStart!.isBefore(tempEnd!) ? tempStart! : tempEnd!;
                                    final end = tempEnd!.isAfter(tempStart!) ? tempEnd! : tempStart!;
                                    widget.onDateRangeChanged?.call(DateTimeRange(start: start, end: end));
                                  }
                                  Navigator.of(dialogCtx).pop();
                                },
                                child: const Text('تطبيق'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectedChain = widget.selectedChain;
    final selectedStoreId = widget.selectedStoreId;
    final selectedCategory = widget.selectedCategory;
    final selectedDateRange = widget.selectedDateRange;
    final availableCategories = widget.availableCategories;
    final chainStoresOverride = widget.chainStoresOverride;
    final onChainChanged = widget.onChainChanged;
    final onStoreChanged = widget.onStoreChanged;
    final onCategoryChanged = widget.onCategoryChanged;
    final onDateRangeChanged = widget.onDateRangeChanged;
    final onSearchChanged = widget.onSearchChanged;
    final onExportExcel = widget.onExportExcel;
    final onExportPdf = widget.onExportPdf;

    // Build complete Fathalla 34 stores list
    final defaultFathallaStores = ApiClient.defaultFathalla34Branches.map((b) {
      return {
        'id': b['id'].toString(),
        'name': b['branch_name'].toString(),
      };
    }).toList();

    final defaultChainStores = <String, List<Map<String, String>>>{
      'fathalla': defaultFathallaStores,
    };

    final chainStores = (chainStoresOverride != null && chainStoresOverride.isNotEmpty)
        ? Map<String, List<Map<String, String>>>.from(chainStoresOverride)
        : defaultChainStores;

    // Ensure fathalla has all 34 branches if override was incomplete
    if (!chainStores.containsKey('fathalla') || chainStores['fathalla']!.length < 10) {
      chainStores['fathalla'] = defaultFathallaStores;
    }

    // Determine available stores based on selectedChain
    List<Map<String, String>> availableStores;
    if (selectedChain != null) {
      availableStores = chainStores[selectedChain] ?? const <Map<String, String>>[];
    } else {
      // Show all stores (or all Fathalla 34 branches)
      final all = <Map<String, String>>[];
      final seenIds = <String>{};
      for (final storesList in chainStores.values) {
        for (final st in storesList) {
          if (seenIds.add(st['id']!)) {
            all.add(st);
          }
        }
      }
      availableStores = all.isNotEmpty ? all : defaultFathallaStores;
    }

    final validStoreId = (selectedStoreId != null &&
            availableStores.any((s) => s['id'] == selectedStoreId))
        ? selectedStoreId
        : null;

    // Available categories from Excel "المجموعة"
    final categories = (availableCategories != null && availableCategories.isNotEmpty)
        ? List<String>.from(availableCategories)
        : List<String>.from(ApiClient.defaultAdco27Categories);

    for (final cat in ApiClient.defaultAdco27Categories) {
      if (!categories.contains(cat)) {
        categories.add(cat);
      }
    }
    if (selectedCategory != null &&
        selectedCategory.isNotEmpty &&
        !categories.contains(selectedCategory)) {
      categories.add(selectedCategory);
    }

    final hasDateRange = selectedDateRange != null;
    final dateRangeLabel = hasDateRange
        ? '${_formatDate(selectedDateRange.start)} – ${_formatDate(selectedDateRange.end)}'
        : 'الفترة';

    // Unified control container decoration
    final controlDecoration = BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
      borderRadius: M3Shape.radiusSm,
      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
    );

    const searchHint = 'ابحث بالصنف أو الباركود';
    final searchHintStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'Cairo',
      color: colorScheme.onSurfaceVariant.withOpacity(0.65),
      fontWeight: FontWeight.normal,
    );

    Widget buildSearchField({required double? width}) {
      final fixed = width != null && width.isFinite;
      final box = Container(
        width: fixed ? null : width,
        height: M3ToolbarButton.height,
        decoration: controlDecoration,
        alignment: Alignment.center,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _searchController,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            onChanged: (val) {
              setState(() {});
              onSearchChanged(val);
            },
            decoration: InputDecoration(
              hintText: searchHint,
              hintStyle: searchHintStyle,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0.0),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20.0,
                color: colorScheme.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 38.0, minHeight: M3ToolbarButton.height),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18.0),
                      tooltip: 'مسح',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32.0, minHeight: M3ToolbarButton.height),
                      splashRadius: 18.0,
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                        });
                        onSearchChanged('');
                      },
                    ),
                  IconButton(
                    key: const ValueKey('barcode_camera_scanner_button'),
                    icon: Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 20.0,
                      color: colorScheme.primary,
                    ),
                    tooltip: 'امسح الباركود',
                    padding: const EdgeInsetsDirectional.only(end: 6.0),
                    constraints: const BoxConstraints(minWidth: 38.0, minHeight: M3ToolbarButton.height),
                    splashRadius: 18.0,
                    onPressed: _openBarcodeScanner,
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: M3ToolbarButton.height),
            ),
          ),
        ),
      );
      // v127: never narrower than the full placeholder (38dp search icon,
      // 38dp barcode button, 10dp padding each side).
      return fixed
          ? M3SearchFieldWidth(
              hintText: searchHint,
              hintStyle: searchHintStyle,
              width: width,
              chrome: 38.0 + 38.0 + 20.0,
              child: box,
            )
          : box;
    }

    Widget buildChainDropdown({required bool expand}) {
      return M3Dropdown<String?>(
        key: const ValueKey('sellout_chain_dropdown'),
        expand: expand,
        width: expand ? null : 190.0,
        value: selectedChain,
        hint: 'كل السلاسل',
        options: const [
          M3DropdownOption(null, 'كل السلاسل'),
          M3DropdownOption('fathalla', 'أسواق فتح الله'),
          M3DropdownOption('beet-elgomla', 'بيت الجملة'),
          M3DropdownOption('institutions', 'المؤسسات'),
          M3DropdownOption('carrefour', 'كارفور'),
          M3DropdownOption('gomla', 'جملة ماركت'),
          M3DropdownOption('spinneys', 'سبينيس'),
        ],
        onChanged: (val) {
          onChainChanged(val);
          onStoreChanged(null); // Reset cascaded store
        },
      );
    }

    Widget buildStoreDropdown({required bool expand}) {
      return M3Dropdown<String?>(
        key: const ValueKey('sellout_store_dropdown'),
        expand: expand,
        width: expand ? null : 220.0,
        value: validStoreId,
        hint: 'كل الفروع (${availableStores.length})',
        options: [
          M3DropdownOption(null, 'كل الفروع (${availableStores.length})'),
          ...availableStores.map((s) => M3DropdownOption<String?>(s['id'], s['name']!)),
        ],
        onChanged: onStoreChanged,
      );
    }

    Widget buildCategoryDropdown({required bool expand}) {
      return M3Dropdown<String?>(
        key: const ValueKey('sellout_category_dropdown'),
        expand: expand,
        width: expand ? null : 200.0,
        value: selectedCategory,
        hint: 'كل الفئات',
        options: [
          const M3DropdownOption(null, 'كل الفئات'),
          ...categories.map((cat) => M3DropdownOption<String?>(cat, cat)),
        ],
        onChanged: onCategoryChanged,
      );
    }

    Widget buildYearSelectorPill() {
      if (widget.onYearChanged == null) return const SizedBox.shrink();
      final activeYr = widget.selectedYear ?? DateTime.now().year;
      final nowYr = DateTime.now().year;
      final years = [nowYr, nowYr - 1, nowYr - 2];
      return KeyedSubtree(
        key: const ValueKey('sellout_year_selector_pill'),
        child: M3Dropdown<int>(
          width: 210.0,
          value: [...years, 0].contains(activeYr) ? activeYr : nowYr,
          leadingIcon: AppIcons.calendar,
          options: [
            for (final y in years) M3DropdownOption(y, '$y'),
            const M3DropdownOption(0, 'كل السنوات'),
          ],
          onChanged: (val) => widget.onYearChanged!(val),
        ),
      );
    }

    Widget buildDateRangeButton({bool expand = false}) {
      final child = InkWell(
        key: const ValueKey('sellout_date_range_chip'),
        borderRadius: M3ToolbarButton.radius,
        onTap: () => _showCompactDateRangeBubble(context),
        child: AnimatedContainer(
          duration: M3Motion.short4,
          curve: M3Motion.standard,
          height: M3ToolbarButton.height,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            color: hasDateRange
                ? colorScheme.primaryContainer.withOpacity(0.55)
                : colorScheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: M3ToolbarButton.radius,
            border: Border.all(
              color: hasDateRange
                  ? colorScheme.primary.withOpacity(0.6)
                  : colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: M3ToolbarButton.iconSize,
                color: hasDateRange ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  dateRangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: hasDateRange ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  ),
                ),
              ),
              if (hasDateRange) ...[
                const SizedBox(width: 4.0),
                InkWell(
                  onTap: () => onDateRangeChanged?.call(null),
                  borderRadius: M3Shape.radiusSm,
                  child: Icon(
                    Icons.close_rounded,
                    size: M3ToolbarButton.iconSize,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    Widget buildUploadSellOutButton({bool expand = false}) {
      if (widget.onUpload == null) return const SizedBox.shrink();
      return SellActionButtons.upload(
        context,
        label: 'رفع ملف Sell-Out',
        onTap: widget.onUpload,
        isUploading: widget.isUploading,
        expand: expand,
      );
    }

    Widget buildPrintPdfButton({bool expand = false}) {
      if (onExportPdf == null) return const SizedBox.shrink();
      return SellActionButtons.printPdf(context, onTap: onExportPdf, expand: expand);
    }

    Widget buildExportExcelButton({bool expand = false}) {
      return SellActionButtons.exportExcel(context, onTap: onExportExcel, expand: expand);
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: M3Spacing.pSm,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isCompact) ...[
                  buildSearchField(width: double.infinity),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Expanded(child: buildChainDropdown(expand: true)),
                      const SizedBox(width: 8.0),
                      Expanded(child: buildCategoryDropdown(expand: true)),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  buildStoreDropdown(expand: true),
                ] else ...[
                  // Primary Filter Controls Row (Search SKU + Cascading Hierarchy)
                  Wrap(
                    spacing: M3Spacing.sm,
                    runSpacing: M3Spacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      buildSearchField(width: 220.0),
                      buildChainDropdown(expand: false),
                      buildStoreDropdown(expand: false),
                      buildCategoryDropdown(expand: false),
                    ],
                  ),
                ],
                M3Spacing.gapSM,
                // Scope & Actions Row: Date Range, Upload, Print PDF, and Export Excel
                if (constraints.maxWidth < 750.0) ...[
                  Row(
                    children: [
                      Expanded(child: buildDateRangeButton(expand: false)),
                      if (widget.onUpload != null) ...[
                        const SizedBox(width: 8.0),
                        Expanded(child: buildUploadSellOutButton(expand: false)),
                      ],
                      const SizedBox(width: 8.0),
                      Expanded(child: buildPrintPdfButton(expand: false)),
                      const SizedBox(width: 8.0),
                      Expanded(child: buildExportExcelButton(expand: false)),
                    ],
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.onYearChanged != null) ...[
                        buildYearSelectorPill(),
                        const SizedBox(width: 8.0),
                      ],
                      // Flexible so a long active date-range label ellipsizes
                      // instead of overflowing the actions row.
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: buildDateRangeButton(expand: false),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      if (widget.onUpload != null) ...[
                        buildUploadSellOutButton(expand: false),
                        const SizedBox(width: 8.0),
                      ],
                      buildPrintPdfButton(expand: false),
                      const SizedBox(width: 8.0),
                      buildExportExcelButton(expand: false),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
