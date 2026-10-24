import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_feedback.dart';
import 'barcode_scanner_dialog.dart';

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
      M3Feedback.showSuccess(context, 'تم مسح الباركود بنجاح: $code');
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
                                size: 22.0,
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                'Filter by Date Range',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20.0),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const Divider(height: 20.0),

                      // Quick preset chips
                      Text(
                        'Quick Presets:',
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
                            label: const Text('January 2026'),
                            avatar: const Icon(Icons.verified_rounded, size: 16.0),
                            onPressed: () {
                              setDialogState(() {
                                tempStart = DateTime(2026, 1, 1);
                                tempEnd = DateTime(2026, 1, 31);
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('Last 7 Days'),
                            onPressed: () {
                              final now = DateTime.now();
                              setDialogState(() {
                                tempStart = now.subtract(const Duration(days: 7));
                                tempEnd = now;
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('Last 30 Days'),
                            onPressed: () {
                              final now = DateTime.now();
                              setDialogState(() {
                                tempStart = now.subtract(const Duration(days: 30));
                                tempEnd = now;
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('Full Year 2026'),
                            onPressed: () {
                              setDialogState(() {
                                tempStart = DateTime(2026, 1, 1);
                                tempEnd = DateTime(2026, 12, 31);
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
                                  initialDate: tempStart ?? DateTime(2026, 1, 1),
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2030, 12, 31),
                                  helpText: 'Select Start Date',
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
                                      'From:',
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
                                  initialDate: tempEnd ?? DateTime(2026, 1, 31),
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2030, 12, 31),
                                  helpText: 'Select End Date',
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
                                      'To:',
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
                            label: const Text('Reset All'),
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
                                child: const Text('Cancel'),
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
                                child: const Text('Apply Range'),
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
      'beet-elgomla': [
        {'id': 'beet_mohandessin', 'name': 'بيت الجملة - المهندسين'},
        {'id': 'beet_tagamoa', 'name': 'بيت الجملة - التجمع الخامس'},
        {'id': 'beet_nasrcity', 'name': 'بيت الجملة - مدينة نصر'},
      ],
      'institutions': [
        {'id': 'inst_giza_b2b', 'name': 'قطاع المؤسسات والفنادق - توريد الجيزة'},
        {'id': 'inst_hospitals', 'name': 'قطاع المستشفيات والشركات - التوريدات الطبية'},
        {'id': 'inst_ministries', 'name': 'قطاع الوزارات والهيئات - التوريد المركزي'},
      ],
      'carrefour': [
        {'id': 'crf_cairo_maadi', 'name': 'كارفور المعادي سيتي سنتر'},
        {'id': 'crf_giza_dandy', 'name': 'كارفور داندي مول'},
        {'id': 'crf_cairo_citystars', 'name': 'كارفور سيتي ستارز'},
      ],
      'gomla': [
        {'id': 'gom_cairo_nasrcity', 'name': 'جملة ماركت - مدينة نصر'},
        {'id': 'gom_loran', 'name': 'جملة ماركت - لوران الإسكندرية'},
        {'id': 'gom_giza_dokki', 'name': 'جملة ماركت - الدقي'},
      ],
      'spinneys': [
        {'id': 'spi_giza_mollarab', 'name': 'سبينيس - مول العرب'},
      ],
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
    if (selectedChain != null && chainStores.containsKey(selectedChain)) {
      availableStores = chainStores[selectedChain]!;
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
        ? 'Date: ${_formatDate(selectedDateRange.start)} -> ${_formatDate(selectedDateRange.end)}'
        : 'Date Range';

    // Unified control container decoration
    final controlDecoration = BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
      borderRadius: M3Shape.radiusSm,
      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
    );

    Widget buildSearchField({required double? width}) {
      return Container(
        width: width,
        height: 44.0,
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
              hintText: 'Search SKU or Barcode...',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Cairo',
                color: colorScheme.onSurfaceVariant.withOpacity(0.65),
                fontWeight: FontWeight.normal,
              ),
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
              prefixIconConstraints: const BoxConstraints(minWidth: 38.0, minHeight: 44.0),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18.0),
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32.0, minHeight: 44.0),
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
                    tooltip: 'Scan Barcode with Camera / مسح الباركود بالكاميرا',
                    padding: const EdgeInsetsDirectional.only(end: 6.0),
                    constraints: const BoxConstraints(minWidth: 38.0, minHeight: 44.0),
                    splashRadius: 18.0,
                    onPressed: _openBarcodeScanner,
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 44.0),
            ),
          ),
        ),
      );
    }

    Widget buildChainDropdown({required bool expand}) {
      return M3Dropdown<String?>(
        key: const ValueKey('sellout_chain_dropdown'),
        expand: expand,
        width: expand ? null : 190.0,
        value: selectedChain,
        hint: 'All Chains',
        options: const [
          M3DropdownOption(null, 'All Chains'),
          M3DropdownOption('fathalla', 'Fathalla Market'),
          M3DropdownOption('beet-elgomla', 'Beet El-Gomla'),
          M3DropdownOption('institutions', 'Institutions'),
          M3DropdownOption('carrefour', 'Carrefour'),
          M3DropdownOption('gomla', 'Gomla Market'),
          M3DropdownOption('spinneys', 'Spinneys'),
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
        hint: 'All Branches (${availableStores.length})',
        options: [
          M3DropdownOption(null, 'All Branches (${availableStores.length})'),
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
        hint: 'All Categories',
        options: [
          const M3DropdownOption(null, 'All Categories'),
          ...categories.map((cat) => M3DropdownOption<String?>(cat, cat)),
        ],
        onChanged: onCategoryChanged,
      );
    }

    Widget buildYearSelectorPill() {
      if (widget.onYearChanged == null) return const SizedBox.shrink();
      final activeYr = widget.selectedYear ?? 2026;
      return KeyedSubtree(
        key: const ValueKey('sellout_year_selector_pill'),
        child: M3Dropdown<int>(
          width: 210.0,
          value: const [2026, 2025, 2024, 0].contains(activeYr) ? activeYr : 2026,
          leadingIcon: AppIcons.calendar,
          options: const [
            M3DropdownOption(2026, 'Year: 2026 (Default)'),
            M3DropdownOption(2025, 'Year: 2025'),
            M3DropdownOption(2024, 'Year: 2024'),
            M3DropdownOption(0, 'All Years (2025–2026)'),
          ],
          onChanged: (val) => widget.onYearChanged!(val),
        ),
      );
    }

    Widget buildDateRangeButton({bool expand = false}) {
      final child = InkWell(
        key: const ValueKey('sellout_date_range_chip'),
        borderRadius: M3Shape.radiusLg,
        onTap: () => _showCompactDateRangeBubble(context),
        child: AnimatedContainer(
          duration: M3Motion.short4,
          curve: M3Motion.standard,
          height: 38.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: hasDateRange
                ? colorScheme.primaryContainer.withOpacity(0.55)
                : colorScheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: M3Shape.radiusLg,
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
                size: 15.0,
                color: hasDateRange ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5.0),
              Flexible(
                child: Text(
                  dateRangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 11.0,
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
                    size: 14.0,
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
      final isUp = widget.isUploading;
      final child = InkWell(
        key: const ValueKey('upload_sellout_button'),
        borderRadius: M3Shape.radiusLg,
        onTap: isUp ? null : widget.onUpload,
        child: Container(
          height: 38.0,
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          decoration: BoxDecoration(
            color: colorScheme.secondary,
            borderRadius: M3Shape.radiusLg,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isUp)
                const SizedBox(
                  width: 14.0,
                  height: 14.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  Icons.upload_file_rounded,
                  size: 16.0,
                  color: colorScheme.onSecondary,
                ),
              const SizedBox(width: 6.0),
              Flexible(
                child: Text(
                  'Upload Sell-Out',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                    color: colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    Widget buildPrintPdfButton({bool expand = false}) {
      if (onExportPdf == null) return const SizedBox.shrink();
      final child = InkWell(
        key: const ValueKey('export_pdf_button'),
        borderRadius: M3Shape.radiusLg,
        onTap: onExportPdf,
        child: Container(
          height: 38.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: M3Shape.radiusLg,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.print_rounded, size: 15.0, color: colorScheme.onPrimary),
              const SizedBox(width: 5.0),
              Flexible(
                child: Text(
                  'Print PDF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    Widget buildExportExcelButton({bool expand = false}) {
      final child = InkWell(
        key: const ValueKey('export_excel_button'),
        borderRadius: M3Shape.radiusLg,
        onTap: onExportExcel,
        child: Container(
          height: 38.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.file_download_rounded, size: 15.0, color: colorScheme.onSurface),
              const SizedBox(width: 5.0),
              Flexible(
                child: Text(
                  'Export Excel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                const SizedBox(height: 12.0),
                // Scope & Actions Row: Date Range, Upload, Print PDF, and Export Excel
                if (constraints.maxWidth < 750.0) ...[
                  Row(
                    children: [
                      Expanded(child: buildDateRangeButton(expand: false)),
                      if (widget.onUpload != null) ...[
                        const SizedBox(width: 6.0),
                        Expanded(child: buildUploadSellOutButton(expand: false)),
                      ],
                      const SizedBox(width: 6.0),
                      Expanded(child: buildPrintPdfButton(expand: false)),
                      const SizedBox(width: 6.0),
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
                      Flexible(child: buildDateRangeButton(expand: false)),
                      const Spacer(),
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
