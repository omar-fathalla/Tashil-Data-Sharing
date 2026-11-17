import 'package:tashil_web/core/widgets/atomic_numeric_text.dart';
import 'package:tashil_web/core/widgets/hyphenated_code_text.dart';
import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:tashil_web/core/widgets/m3_states.dart';
import 'package:tashil_web/core/widgets/m3_menu_filter.dart';
import 'package:tashil_web/core/utils/sheet_name_utils.dart';
import 'package:tashil_web/core/utils/shared_display_prefix.dart';
import 'dart:math' as math;
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_text_variants.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import '../../../../core/utils/export_columns.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/data/cache_store.dart';
import '../../../../core/data/result.dart';
import '../../data/target_repository.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../data/sell_out_explorer_repository.dart';
import '../../domain/branch_growth.dart';
import '../../domain/sell_out_upload_flow.dart';
import '../../domain/archive_delete_copy.dart';
import '../../../../core/network/backend_http.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/app_date_format.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/archive_actions_group.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../product_master/presentation/screens/product_master_screen.dart';
import '../widgets/cascading_filter_toolbar.dart';
import '../widgets/sell_table_shared.dart';
import '../widgets/target_management_panel.dart';
import '../widgets/virtualized_sku_table.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_wrap_text.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_table_surface.dart';

/// SellOutExplorerScreen provides comprehensive retailer Sell-Out analytics:
/// - Tab 0: Sell-Out Data & Operations (Transactions Table, 4 KPI cards, Upload & Export Actions)
/// - Tab 1: Performance & Branch Analytics (Pareto 80/20 Analysis, Brand & Branch Velocity Breakdown)
/// - Tab 2: Target Management (Sell-Out) (Monthly Targets, Actual vs Target Gap & Tracking)
/// - Tab 3: Uploaded Sheets (Sell-Out Cumulative Excel Sheets Archive: Replace, Download, Delete)
class SellOutExplorerScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final SellOutExplorerRepository? repository;

  const SellOutExplorerScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<SellOutExplorerScreen> createState() => _SellOutExplorerScreenState();
}

class _SellOutExplorerScreenState extends State<SellOutExplorerScreen> with DataRefreshMixin<SellOutExplorerScreen> {
  // Headers and cells centred; the item name (+ nested code) stays start-aligned.
  /// One-line short headings capped so the 11-column price table fits the
  /// live 1280+sidebar shell; full original wording lives in [tooltip].
  static DataColumn _priceHeading(
    String label, {
    bool numeric = true,
    bool center = true,
    double maxWidth = 88,
    String? tooltip,
  }) {
    return DataColumn(
      numeric: numeric,
      tooltip: tooltip,
      headingRowAlignment: center ? MainAxisAlignment.center : null,
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
        ),
      ),
    );
  }


  /// Per-column caps: numeric floors from live bodyMedium values
  /// (e.g. 11259.7, 1082.66, 87,233, −44.0%) so a number never wraps
  /// internally; header caps sized so the shortened one-line labels fit
  /// (Cairo labelMedium). Currency («ج.م») may go to the next line.
  /// Name column absorbs the former standalone code column so the official
  /// name (≤2 lines) + nested item code (1 line) stay ≤3 lines total.
  static const double _priceColName = 196;
  static const double _priceColUnitsPer = 72;
  static const double _priceColUnits = 54;
  static const double _priceColCartons = 58;
  static const double _priceColList = 64;
  static const double _priceColSell = 56;
  static const double _priceColDelta = 56;
  static const double _priceColFactory = 88;
  static const double _priceColNetCarton = 96;
  static const double _priceColNetSales = 76;
  static const double _priceColMargin = 80;

  static Widget _priceCell(
    String text, {
    TextStyle? style,
    Key? key,
    required double maxWidth,
    TextAlign textAlign = TextAlign.center,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AtomicNumericText(
        text,
        key: key,
        maxWidth: maxWidth,
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  static List<DataColumn> get _priceMatrixColumns => [
        _priceHeading('الصنف الرسمي', numeric: false, center: false, maxWidth: _priceColName),
        _priceHeading('وحدات/كرتونة', maxWidth: _priceColUnitsPer),
        _priceHeading('الوحدات', maxWidth: _priceColUnits),
        _priceHeading('الكراتين', maxWidth: _priceColCartons),
        _priceHeading(
          'سعر القائمة',
          maxWidth: _priceColList,
          tooltip: 'سعر القائمة (شامل الضريبة)',
        ),
        _priceHeading(
          'سعر البيع',
          maxWidth: _priceColSell,
          tooltip: 'سعر البيع الفعلي',
        ),
        _priceHeading(
          'فرق السعر',
          maxWidth: _priceColDelta,
          tooltip: 'فرق السعر %',
        ),
        _priceHeading(
          'تكلفة المصنع/ق',
          maxWidth: _priceColFactory,
          tooltip: 'تكلفة المصنع للقطعة',
        ),
        _priceHeading(
          'صافي سعر الكرتونة',
          maxWidth: _priceColNetCarton,
          tooltip: 'صافي سعر الكرتونة (فاتورة)',
        ),
        _priceHeading('صافي المبيعات', maxWidth: _priceColNetSales),
        _priceHeading(
          'الهامش',
          maxWidth: _priceColMargin,
          tooltip: 'هامش السلسلة',
        ),
      ];

  /// Flex shares for the price matrix at the live 1280+sidebar width.
  /// Gutters are xxs so the measured numeric caps fit without h-scroll.
  static const List<double> _priceMatrixFlex = [
    _priceColName,
    _priceColUnitsPer,
    _priceColUnits,
    _priceColCartons,
    _priceColList,
    _priceColSell,
    _priceColDelta,
    _priceColFactory,
    _priceColNetCarton,
    _priceColNetSales,
    _priceColMargin,
  ];

  static const double _branchRankWidth = 28.0;

  /// Branch-growth table column shares: grouped rank+branch, 2026, 2025, diff,
  /// YoY %, monthly average, status.
  static const List<double> _branchGrowthFlex = [2.6, 1.3, 1.3, 1.0, 1.1, 1.1, 1.1];

  @override
  void onBackendDataChanged() {
    _loadAllData();
  }

  // Active Tab Index
  // 0: Sell-Out Data & Operations
  // 1: Performance & Branch Analytics
  // 2: Target Management (Sell-Out)
  // 3: Uploaded Sheets (Archive)
  int _activeTab = 0;

  /// When true, the Sell-Out tab bar is replaced by the target detail page.
  bool _targetsDetailOpen = false;

  // Tab 0 Filter & Transaction State
  String? selectedChain;
  String? selectedStoreId;
  String? selectedCategory;
  DateTimeRange? selectedDateRange;
  static int get _currentYear => DateTime.now().year;
  static List<int> get _recentYears => [_currentYear, _currentYear - 1, _currentYear - 2];
  int _selectedYear = DateTime.now().year;
  // Bumped on every _loadRecords call; a response whose seq is stale (the user changed year/filters
  // while it was in flight) is dropped so it cannot overwrite the newer selection.
  int _recordsLoadSeq = 0;
  int _selectedMonth = 0; // 0 = All Months (كل الشهور), 1..12 = Jan..Dec
  String searchQuery = '';
  bool isLoading = true;
  String? _loadError;
  bool _isUploading = false;
  String? _replacingFileId;
  List<SellOutRecordModel> records = [];
  SellOutRecordsSummaryModel _recordsSummary = const SellOutRecordsSummaryModel();
  List<String> _availableCategories = [];
  Map<String, List<Map<String, String>>> _chainStores = {};

  // Full-Width Chain Branches Sales Ranking Chart State
  String _chartChain = 'fathalla'; // Default to Fathalla Market (أسواق فتح الله)
  bool _chartSortAscending = false; // false = High to Low (الأعلى للأقل)
  bool _branchChartExpanded = false; // Branch ranking chart starts collapsed
  List<StoreBenchmarkItem> _branchChartItems = const [];
  Map<String, StoreBenchmarkItem> _prevYearBranchMap = const {};
  double _prevYearTotalChainRevenue = 0.0;
  /// Selected-year totals restricted to months present last year — YoY only.
  Map<String, StoreBenchmarkItem> _yoyCurrentBranchMap = const {};
  double _yoyCurrentTotalChainRevenue = 0.0;
  /// Calendar months compared like-for-like (present in both years); empty when unknown.
  List<int> _matchedYoyMonths = const [];

  // Tab 1: Performance & Branch Analytics State
  String _perfChain = 'all';
  String _perfBrand = 'all';
  String _perfSearch = '';
  String _perfGrowthStatusFilter = 'all'; // 'all', 'growing', 'declining', 'new_branch'
  String _priceMatrixFilter = 'all'; // 'all', 'healthy', 'low_margin', 'negative_margin', 'promo'
  late final TextEditingController _perfSearchController;

  // Tab 3: Uploaded Sell-Out Excel Sheets Archive State
  bool _isLoadingArchive = false;
  List<ArchivedExcelFileModel> _archivedSellOutFiles = const [];
  /// The last list load failed (after transient retries): show an error with
  /// retry, never a misleading "no files" empty state.
  bool _archiveLoadFailed = false;
  String _archiveUploadChain = 'fathalla';
  int _archiveUploadYear = 0; // 0 = Auto-detect from sheet
  int _archiveUploadMonth = 0; // 0 = Auto-detect from sheet
  String? _deletingFileId;

  late String _lastTenantId;
  late SellOutExplorerRepository _repo;

  // Scroll Controllers for Responsive Data Tables & Branch Chart
  late final ScrollController _branchChartScrollController;
  late final ScrollController _branchTableScrollController;
  late final ScrollController _skuPerfTableScrollController;
  late final ScrollController _archiveSheetsScrollController;

  @override
  void initState() {
    super.initState();
    _perfSearchController = TextEditingController();
    _branchChartScrollController = ScrollController();
    _branchTableScrollController = ScrollController();
    _skuPerfTableScrollController = ScrollController();
    _archiveSheetsScrollController = ScrollController();
    _repo = widget.repository ?? SellOutExplorerRepository(widget.apiClient);
    _lastTenantId = widget.apiClient.tenantId;
    _loadAllData();
  }

  @override
  void dispose() {
    _perfSearchController.dispose();
    _branchChartScrollController.dispose();
    _branchTableScrollController.dispose();
    _skuPerfTableScrollController.dispose();
    _archiveSheetsScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SellOutExplorerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _repo = widget.repository ?? SellOutExplorerRepository(widget.apiClient);
      selectedChain = null;
      selectedStoreId = null;
      selectedCategory = null;
      selectedDateRange = null;
      _selectedYear = _currentYear;
      _selectedMonth = 0;
      _chartChain = 'fathalla';
      searchQuery = '';
      _availableCategories = [];
      _chainStores = {};
      _loadAllData();
    }
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    await Future.wait([
      _loadRecords(),
      _loadSellOutArchive(forceRefresh: forceRefresh),
    ]);
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Excel Workbook';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024.0) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _loadRecords() async {
    final seq = ++_recordsLoadSeq;
    if (mounted) {
      // Drop previous filter numbers immediately so a slow/failed reload (e.g. 429)
      // cannot leave "الأسعار وهامش السلسلة" showing the prior category's totals.
      setState(() {
        isLoading = true;
        _loadError = null;
        records = [];
        _recordsSummary = const SellOutRecordsSummaryModel();
        // Drop stale year matrices so KPI subtitles/counts cannot mix years
        // while a reload (e.g. 2025 → 2026) is in flight.
        _branchChartItems = const [];
        _prevYearBranchMap = const {};
        _prevYearTotalChainRevenue = 0.0;
        _yoyCurrentBranchMap = const {};
        _yoyCurrentTotalChainRevenue = 0.0;
        _matchedYoyMonths = const [];
      });
      // clearSnackBars after the first frame — initState's first load cannot depend on
      // ScaffoldMessenger yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      });
    }
    final effectiveYear = (selectedDateRange == null && _selectedYear > 0) ? _selectedYear : null;
    final effectiveMonth = (selectedDateRange == null && _selectedMonth > 0) ? _selectedMonth : null;
    final activeChartChain = (selectedChain != null && selectedChain!.isNotEmpty)
        ? selectedChain!
        : _chartChain;
    final compYear = (_selectedYear > 0 ? _selectedYear : _currentYear) - 1;

    final loaded = await _repo.load(SellOutExplorerQuery(
      chain: selectedChain,
      storeId: selectedStoreId,
      category: selectedCategory,
      query: searchQuery,
      startDate: selectedDateRange != null ? _formatDate(selectedDateRange!.start) : null,
      endDate: selectedDateRange != null ? _formatDate(selectedDateRange!.end) : null,
      year: effectiveYear,
      month: effectiveMonth,
      limit: 1000,
      matrixChain: activeChartChain == 'all' ? null : activeChartChain,
      matrixYear: _selectedYear > 0 ? _selectedYear : null,
      compYear: compYear,
    ));
    if (seq != _recordsLoadSeq) return;
    if (loaded case Failure(:final error)) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
        });
        setState(() {
          isLoading = false;
          _loadError = error.toString();
          records = [];
          _recordsSummary = const SellOutRecordsSummaryModel();
        });
        debugPrint('Sell-Out load failed: $error');
      }
      return;
    }
    final data = loaded.valueOrNull!;
    final res = data.records;
    final summary = data.summary ??
        SellOutRecordsSummaryModel(
          totalCount: res.length,
          totalNetRevenue: res.fold<double>(0.0, (acc, r) => acc + r.netRevenue),
          totalUnitsSold: res.fold<int>(0, (acc, r) => acc + r.quantitySold),
          activeStoresCount: res.map((r) => r.storeId.isNotEmpty ? r.storeId : r.storeName).toSet().length,
          activeSkusCount: res.map((r) => r.barcode.isNotEmpty ? r.barcode : r.skuName).toSet().length,
        );

    final dynamicStores = data.stores;
    final currentBranchMatrix = data.currentBranchMatrix;
    final prevBranchMatrix = data.prevBranchMatrix;
    final yoyCurrentBranchMatrix = data.yoyCurrentBranchMatrix;

    final prevMap = <String, StoreBenchmarkItem>{};
    double prevTotalRev = 0.0;
    for (final b in prevBranchMatrix) {
      prevMap[b.storeId.isNotEmpty ? b.storeId : b.storeName] = b;
      prevTotalRev += b.totalRevenue;
    }
    final yoyCurMap = <String, StoreBenchmarkItem>{};
    double yoyCurRev = 0.0;
    for (final b in yoyCurrentBranchMatrix) {
      yoyCurMap[b.storeId.isNotEmpty ? b.storeId : b.storeName] = b;
      yoyCurRev += b.totalRevenue;
    }

    if (mounted) {
      setState(() {
        records = res;
        _recordsSummary = summary;
        _branchChartItems = currentBranchMatrix;
        _prevYearBranchMap = prevMap;
        _prevYearTotalChainRevenue = prevTotalRev;
        _yoyCurrentBranchMap = yoyCurMap;
        _yoyCurrentTotalChainRevenue = yoyCurRev;
        _matchedYoyMonths = data.matchedMonths;
        if (_availableCategories.isEmpty || _chainStores.isEmpty) {
          final cats = <String>{};
          final storesByChain = <String, List<Map<String, String>>>{};
          final slug = ApiClient.normalizeDataTenantSlug(widget.apiClient.tenantId);
          if (slug == 'adeco' && !widget.apiClient.isCurrentTenantCleared) {
            cats.addAll(ApiClient.defaultAdco27Categories);
            final fList = storesByChain.putIfAbsent('fathalla', () => []);
            for (final b in ApiClient.defaultFathalla34Branches) {
              final id = (b['id'] ?? '').toString();
              final name = (b['branch_name'] ?? id).toString();
              if (id.isNotEmpty && !fList.any((item) => item['id'] == id)) {
                fList.add({'id': id, 'name': name});
              }
            }
          }
          for (final s in dynamicStores) {
            final chain = (s['retailer_chain'] ?? s['chain'] ?? '').toString();
            final id = (s['id'] ?? '').toString();
            final name = (s['branch_name'] ?? id).toString();
            if (chain.isNotEmpty && id.isNotEmpty) {
              final chainList = storesByChain.putIfAbsent(chain, () => []);
              if (!chainList.any((item) => item['id'] == id)) {
                chainList.add({'id': id, 'name': name});
              }
            }
          }
          for (final r in res) {
            if (r.category.isNotEmpty) {
              cats.add(r.category);
            }
            if (r.retailerChain.isNotEmpty && r.storeId.isNotEmpty) {
              final chainList = storesByChain.putIfAbsent(r.retailerChain, () => []);
              if (!chainList.any((s) => s['id'] == r.storeId)) {
                chainList.add({'id': r.storeId, 'name': r.storeName});
              }
            }
          }
          _availableCategories = cats.toList();
          _chainStores = storesByChain;
        }
        isLoading = false;
        _loadError = null;
      });
    }
  }

  Future<void> _loadSellOutArchive({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _repo.invalidateAll();
    }
    if (mounted) setState(() => _isLoadingArchive = true);
    try {
      final res = await widget.apiClient.getUploadedFilesArchive(
        fileType: 'sell_out',
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _archivedSellOutFiles = res.files;
          _archiveLoadFailed = false;
          _isLoadingArchive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _archiveLoadFailed = true;
          _isLoadingArchive = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadSellOutFile({
    String? replaceArchiveId,
    String? forceChain,
    int? forceYear,
    int? forceMonth,
  }) async {
    if (widget.apiClient.currentUser?.canUploadFiles == false) {
      M3Feedback.showError(
        context,
        'ليس لديك صلاحية رفع الملفات.',
      );
      return;
    }

    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() {
      _isUploading = true;
      if (replaceArchiveId != null) {
        _replacingFileId = replaceArchiveId;
      }
    });

    try {
      final targetChain = forceChain ??
          (selectedChain != null && selectedChain != 'all' ? selectedChain! : _archiveUploadChain);

      String? periodDate;
      if (forceYear != null && forceYear > 0) {
        final m = (forceMonth != null && forceMonth > 0) ? forceMonth.toString().padLeft(2, '0') : '01';
        periodDate = '$forceYear-$m-01';
      } else if (_archiveUploadYear > 0) {
        final m = _archiveUploadMonth > 0 ? _archiveUploadMonth.toString().padLeft(2, '0') : '01';
        periodDate = '$_archiveUploadYear-$m-01';
      }

      // Never delete [replaceArchiveId] before preview/confirm — cancel, parse
      // errors, and commit failures must leave the old archive + BQ rows intact.
      final flow = await runSellOutUploadFlow(
        filename: picked.name,
        bytes: picked.bytes,
        targetChain: targetChain,
        periodDate: periodDate,
        replaceArchiveId: replaceArchiveId,
        deps: SellOutUploadFlowDeps(
          upload: ({
            required filename,
            required bytes,
            targetChain,
            periodDate,
            required dryRun,
          }) =>
              widget.apiClient.uploadFile(
                filename,
                bytes,
                targetChain: targetChain,
                periodDate: periodDate,
                dryRun: dryRun,
              ),
          commit: ({
            required batchId,
            targetChain,
            periodDate,
          }) =>
              widget.apiClient.commitStagedUpload(
                batchId: batchId,
                targetChain: targetChain,
                periodDate: periodDate,
              ),
          discard: ({required batchId}) =>
              widget.apiClient.discardStagedUpload(batchId: batchId),
          deleteArchive: (archiveId) => widget.apiClient.deleteArchivedFile(
            archiveId,
            isSellIn: false,
          ),
          confirm: (preview) async {
            if (!mounted) return false;
            final sourceLabel = preview.mappingSource.isNotEmpty
                ? preview.mappingSource
                : 'unknown';
            final modelLabel = preview.aiModelUsed.isNotEmpty
                ? preview.aiModelUsed
                : 'n/a';
            final previewSummary =
                '${picked.name}: ${preview.validRows} صف • ${CurrencyFormatter.formatCompactEGP(preview.totalRevenue)}'
                ' • mapping_source=$sourceLabel • model=$modelLabel';
            return showDialog<bool>(
              context: context,
              builder: (ctx) {
                final cs = Theme.of(ctx).colorScheme;
                return AlertDialog(
                  shape: const RoundedRectangleBorder(
                    borderRadius: M3Shape.radiusLg,
                  ),
                  title: const Text('مراجعة رفع Sell-Out'),
                  content: Text(
                    'معاينة فقط — لم يُحفظ شيء بعد'
                    '${replaceArchiveId != null ? ' (الملف الحالي يبقى حتى تأكيد الاستبدال)' : ''}.\n'
                    '$previewSummary',
                  ),
                  actions: [
                    TestSemantics.button(
                      identifier: TestIds.uploadCommitCancel,
                      label: 'إلغاء الرفع',
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    TestSemantics.button(
                      identifier: TestIds.uploadCommitConfirm,
                      label: 'تأكيد الرفع',
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          replaceArchiveId != null
                              ? 'تأكيد الاستبدال'
                              : 'حفظ واعتماد',
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      );

      if (!mounted) return;

      final preview = flow.preview;
      final previewSummary = preview == null
          ? picked.name
          : '${picked.name}: ${preview.validRows} صف • ${CurrencyFormatter.formatCompactEGP(preview.totalRevenue)}'
              ' • mapping_source=${preview.mappingSource.isNotEmpty ? preview.mappingSource : 'unknown'}'
              ' • model=${preview.aiModelUsed.isNotEmpty ? preview.aiModelUsed : 'n/a'}';

      switch (flow.status) {
        case SellOutUploadFlowStatus.cancelled:
          M3Feedback.showInfo(
            context,
            'تم إلغاء الاعتماد — المعاينة فقط ($previewSummary)',
          );
          return;
        case SellOutUploadFlowStatus.previewFailed:
        case SellOutUploadFlowStatus.commitFailed:
          debugPrint('Sell-Out upload failed: ${flow.error}');
          M3Feedback.showError(context, 'تعذّر رفع الملف.');
          return;
        case SellOutUploadFlowStatus.committed:
          final actionLabel = replaceArchiveId != null
              ? (flow.replacedArchiveDeleted
                  ? 'تم استبدال الملف.'
                  : 'تم رفع الملف الجديد (تعذّر حذف الملف القديم).')
              : 'تم رفع الملف وإضافته للبيانات.';
          M3Feedback.showSuccess(
            context,
            '$actionLabel ($previewSummary)',
          );
          _repo.invalidateAll();
          _repo.cache.invalidatePrefix(
            CacheStore.prefix(widget.apiClient.tenantId, TargetRepository.feature),
          );
          BackendHttp.cache.invalidateAll();
          await _loadAllData(forceRefresh: true);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Sell-Out upload failed: $e');
        M3Feedback.showError(context, 'تعذّر رفع الملف.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _replacingFileId = null;
        });
      }
    }
  }

  Future<void> _handleDownloadSellOutSheet(ArchivedExcelFileModel file) async {
    try {
      await widget.apiClient.downloadArchivedFile(file);
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'جارٍ تنزيل ${file.fileName}',
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Archive download failed: $e');
        M3Feedback.showError(context, 'تعذّر تنزيل الملف.');
    }
  }

  Future<void> _confirmAndDeleteSellOutSheet(ArchivedExcelFileModel file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusLg),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: cs.error, size: 24.0),
              const SizedBox(width: 10.0),
              const Expanded(
                child: Text(
                  'حذف الملف؟',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rtlEnd('سيتم حذف هذا الملف وبياناته من ${ltrIsolate('Sell-Out')}.')),
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.35),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'السلسلة ${file.retailChain.toUpperCase()} • الصفوف ${file.rowsIngested} • صافي المبيعات ${CurrencyFormatter.formatCompactEGP(file.totalRevenue)}',
                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontSize: M3FontSize.bodySmall)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                sellOutDeleteConsequenceText(
                  coversAllMonths: archiveFileCoversAllMonths(
                    file.targetMonth,
                    isLastFile: _archivedSellOutFiles.length <= 1,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(fontSize: M3FontSize.bodySmall, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          actions: [
            TestSemantics.button(
              identifier: TestIds.deleteCancel,
              label: 'إلغاء الحذف',
              onPressed: () => Navigator.of(ctx).pop(false),
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
            ),
            TestSemantics.button(
              identifier: TestIds.deleteConfirm,
              label: 'تأكيد الحذف',
              onPressed: () => Navigator.of(ctx).pop(true),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.delete_outline_rounded, size: 18.0),
                label: const Text('حذف'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _deletingFileId = file.id);
    try {
      await widget.apiClient.deleteArchivedFile(
        file.id,
        fileName: file.fileName,
        isSellIn: false,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم حذف ${file.fileName}.',
      );
      _repo.invalidateAll();
      _repo.cache.invalidatePrefix(CacheStore.prefix(widget.apiClient.tenantId, TargetRepository.feature));
      BackendHttp.cache.invalidateAll();
      await _loadAllData(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Archive delete failed: $e');
      final msg = e is ArchiveDeleteException
          ? e.message
          : 'تعذّر حذف الملف.';
      M3Feedback.showError(context, msg);
      // Failed deletes must keep the file listed — refresh from server truth.
      await _loadAllData(forceRefresh: true);
    } finally {
      if (mounted) {
        setState(() => _deletingFileId = null);
      }
    }
  }

  void _handleExportExcel() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'ليس لديك صلاحية تصدير التقارير.',
      );
      return;
    }

    const headers = ExportColumns.sellOutRecords;

    final rows = records
        .map((r) => [
              r.barcode,
              r.skuName,
              r.retailerChain,
              r.storeName,
              r.category,
              r.quantitySold,
              r.unitPrice,
              r.netRevenue,
              r.transactionDate,
            ])
        .toList();

    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename = 'tashil_sellout_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);

    widget.apiClient.recordAuditLog(
      action: 'EXPORT_EXCEL',
      resource: filename,
      details: 'تصدير ${records.length} صف (CSV)',
    );

    M3Feedback.showSuccess(
      context,
      'تم تصدير ${records.length} صف (CSV).',
    );
  }

  void _handleExportPdf() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'ليس لديك صلاحية تصدير التقارير.',
      );
      return;
    }

    final headers = [
      'الباركود',
      'اسم الصنف',
      'السلسلة',
      'الفرع',
      'الفئة',
      'الكمية المباعة',
      'سعر الوحدة',
      'صافي المبيعات',
      'تاريخ البيع',
    ];

    final rows = records
        .map((r) => [
              r.barcode,
              r.skuName,
              r.retailerChain,
              r.storeName,
              r.category,
              r.quantitySold,
              CurrencyFormatter.formatEGP(r.unitPrice),
              CurrencyFormatter.formatEGP(r.netRevenue),
              r.transactionDate,
            ])
        .toList();

    final companyName =
        widget.apiClient.currentTenantProfile?.displayName.isNotEmpty == true
            ? widget.apiClient.currentTenantProfile!.displayName
            : ApiClient.getDisplayNameForTenant(widget.apiClient.tenantId);

    final totalNet = records.fold<double>(0.0, (acc, r) => acc + r.netRevenue);
    final totalUnits = records.fold<int>(0, (acc, r) => acc + r.quantitySold);

    final htmlData = ExcelExportService.generatePrintableReport(
      title: 'تقرير Sell-Out',
      headers: headers,
      rows: rows,
      metadata: {
        'الشركة': companyName,
        'صافي المبيعات': CurrencyFormatter.formatEGP(totalNet),
        'إجمالي الكمية المباعة': '${CurrencyFormatter.formatNumber(totalUnits)} وحدة',
        'إجمالي الصفوف': '${records.length}',
        'تاريخ التصدير': DateTime.now().toString().split(' ')[0],
      },
    );

    final filename = 'tashil_sellout_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);

    widget.apiClient.recordAuditLog(
      action: 'EXPORT_PDF',
      resource: filename,
      details: 'تقرير طباعة (${records.length} صف)',
    );

    M3Feedback.showSuccess(
      context,
      'تقرير الطباعة جاهز (${records.length} صف).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return M3ToolbarButtonTheme(
      child: SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Screen Header: Unified M3 Left English Title + Right Arabic Subtitle
            const M3PageHeader(
              titleEn: 'Sell-Out',
              subtitleAr:
                  'مبيعات السلاسل للمستهلك وأداء الفروع والمستهدفات',
            ),

            M3Spacing.gapSM,

            // Top Tab Switcher — hidden while a Sell-Out target detail page is open.
            if (!_targetsDetailOpen)
              M3ResponsiveTabBar<int>(
                textDirection: TextDirection.ltr,
                selectedValue: _activeTab,
                items: [
                  const M3ResponsiveTabItem<int>(
                    value: 0,
                    icon: Icons.point_of_sale_rounded,
                    selectedIcon: Icons.point_of_sale_rounded,
                    label: 'بيانات المبيعات',
                  ),
                  const M3ResponsiveTabItem<int>(
                    value: 1,
                    icon: Icons.insights_rounded,
                    selectedIcon: Icons.insights_rounded,
                    label: 'أداء الفروع',
                  ),
                  const M3ResponsiveTabItem<int>(
                    value: 2,
                    icon: Icons.track_changes_rounded,
                    selectedIcon: Icons.track_changes_rounded,
                    label: 'المستهدفات',
                  ),
                  M3ResponsiveTabItem<int>(
                    value: 3,
                    icon: Icons.folder_copy_rounded,
                    selectedIcon: Icons.folder_copy_rounded,
                    label: 'الملفات المرفوعة (${_archivedSellOutFiles.length})',
                    semanticsIdentifier: TestIds.selloutUploadedFiles,
                  ),
                ],
                onChanged: (next) {
                  setState(() => _activeTab = next);
                  if (next == 3) {
                    _loadSellOutArchive(forceRefresh: true);
                  }
                },
              ),

            if (!_targetsDetailOpen) M3Spacing.gapMD,

            if (_activeTab == 2)
              TargetManagementPanel(
                key: ValueKey('sell_out_targets_${widget.apiClient.tenantId}'),
                apiClient: widget.apiClient,
                targetType: 'sell_out',
                onDetailOpenChanged: (open) {
                  setState(() => _targetsDetailOpen = open);
                },
              )
            else if ((_activeTab == 0 || _activeTab == 1) &&
                !isLoading &&
                _loadError != null &&
                records.isEmpty)
              M3ErrorState(
                key: const ValueKey('sell_out_error_state'),
                title: 'تعذّر تحميل بيانات Sell-Out',
                message: 'تعذّر الاتصال بالخادم. حاول مرة أخرى.',
                retryLabel: 'إعادة المحاولة',
                onRetry: _loadRecords,
              )
            else if (_activeTab == 1)
              _buildPerformanceAndBranchAnalyticsTab(context, theme, colorScheme)
            else if (_activeTab == 3)
              _buildUploadedSellOutSheetsTab(context, theme, colorScheme)
            else
              _buildSellOutExplorerTab(context, theme, colorScheme),
          ],
        ),
      ),
      ),
    );
  }

  // ===========================================================================
  // TAB 0: SELL-OUT DATA & TRANSACTIONS EXPLORER
  // ===========================================================================
  Widget _buildSellOutExplorerTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final canExport = widget.apiClient.currentUser?.canExportFinancials ?? true;

    // Use full-dataset summary metrics from backend (not just the 250 paginated rows)
    final bool hasSubFilters = (selectedStoreId != null && selectedStoreId!.isNotEmpty) ||
        (selectedCategory != null && selectedCategory!.isNotEmpty) ||
        searchQuery.trim().isNotEmpty;
    final double branchMatrixTotalRev = _branchChartItems.fold<double>(0.0, (acc, b) => acc + b.totalRevenue);
    final int branchMatrixTotalUnits = _branchChartItems.fold<int>(0, (acc, b) => acc + b.totalUnits);

    final double fallbackRev = (!hasSubFilters && branchMatrixTotalRev > 0)
        ? branchMatrixTotalRev
        : records.fold<double>(0.0, (acc, r) => acc + r.netRevenue);
    final int fallbackUnits = (!hasSubFilters && branchMatrixTotalUnits > 0)
        ? branchMatrixTotalUnits
        : records.fold<int>(0, (acc, r) => acc + r.quantitySold);
    final int fallbackStores = records.map((r) => r.storeId.isNotEmpty ? r.storeId : r.storeName).toSet().length;
    final int fallbackSkus = records.map((r) => r.barcode.isNotEmpty ? r.barcode : r.skuName).toSet().length;

    final double totalNetRevenue = _recordsSummary.totalNetRevenue > 0 ? _recordsSummary.totalNetRevenue : fallbackRev;
    final int totalUnitsSold = _recordsSummary.totalUnitsSold > 0 ? _recordsSummary.totalUnitsSold : fallbackUnits;
    final double totalCartonsSold = _recordsSummary.totalCartonsSold > 0
        ? _recordsSummary.totalCartonsSold
        : records.fold<double>(0.0, (acc, r) => acc + r.cartonsSold);
    final int activeStoresCount = _recordsSummary.activeStoresCount > 0
        ? _recordsSummary.activeStoresCount
        : (_branchChartItems.isNotEmpty ? _branchChartItems.length : fallbackStores);
    final int activeSkusCount = _recordsSummary.activeSkusCount > 0
        ? _recordsSummary.activeSkusCount
        : fallbackSkus;
    final double avgBranchRevenue = activeStoresCount > 0 ? (totalNetRevenue / activeStoresCount) : 0.0;


    // Displayed revenue stays full-period; YoY uses like-for-like months only
    // (intersection of months present in both years — same rule as GetExecutiveKPIs).
    String yoySubtitleSuffix = '';
    if (_selectedYear == _currentYear) {
      final yoyPct = likeForLikeYoyPct(
        _yoyCurrentTotalChainRevenue,
        _prevYearTotalChainRevenue,
      );
      if (yoyPct != null) {
        yoySubtitleSuffix =
            ' • نمو ${CurrencyFormatter.formatSignedPct(yoyPct)} مقارنة بالعام السابق';
      } else if (totalNetRevenue > 0 || _branchChartItems.isNotEmpty) {
        yoySubtitleSuffix = ' • — · لا توجد بيانات للعام السابق';
      }
    }

    // Period label must mirror the selected data year (never the comparison year).
    final String shortYearAr = selectedDateRange != null
        ? '${_formatDate(selectedDateRange!.start)} – ${_formatDate(selectedDateRange!.end)}'
        : (_selectedYear > 0 ? 'سنة $_selectedYear' : 'كل السنوات');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Four Symmetrical Executive KPI Cards (Full Width Alignment)
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'صافي المبيعات',
              titleEn: 'Net Sales (EGP)',
              value: CurrencyFormatter.formatCompactEGP(totalNetRevenue),
              subtitle: '$shortYearAr$yoySubtitleSuffix',
              icon: AppIcons.money,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الكمية المباعة',
              titleEn: 'Total Units Sold',
              value: CurrencyFormatter.formatNumber(totalUnitsSold),
              subtitle: totalCartonsSold > 0
                  ? '${CurrencyFormatter.formatNumber(totalCartonsSold.round())} كرتونة'
                  : shortYearAr,
              icon: AppIcons.units,
              color: Color.lerp(colorScheme.primary, colorScheme.secondary, 0.30) ?? colorScheme.primary,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'الأصناف النشطة',
              titleEn: 'Active SKUs',
              value: '$activeSkusCount صنف نشط',
              subtitle: 'متوسط الفرع: ${CurrencyFormatter.formatCompactEGP(avgBranchRevenue)}',
              icon: AppIcons.productMaster,
              color: Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.40) ?? colorScheme.primary,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'الفروع النشطة',
              titleEn: 'Active Stores',
              value: '$activeStoresCount فرع',
              // Explicit selected-year label (regression: must not show comp year).
              subtitle: shortYearAr,
              subtitleKey: const ValueKey('kpi_subtitle_Active Stores'),
              icon: AppIcons.storeMatrix,
              color: colorScheme.secondary,
            );

            return _buildFourCardResponsiveLayout(
              constraints.maxWidth,
              card1,
              card2,
              card3,
              card4,
            );
          },
        ),

        M3Spacing.gapMD,

        // RBAC Restriction Banner
        if (!canExport) ...[
          Container(
            key: const ValueKey('rbac_export_restricted_banner'),
            padding: M3Spacing.pSm,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withOpacity(0.55),
              borderRadius: M3Shape.radiusMd,
              border: Border.all(color: colorScheme.error.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_person_rounded, color: colorScheme.error, size: 20.0),
                M3Spacing.hGapXS,
                Expanded(
                  child: Text(
                    'التصدير غير متاح لحسابك.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          M3Spacing.gapMD,
        ],

        // 2. Full-Width Chain Branches Sales Ranking Chart (High to Low with Year 2026 Default & 2025 Switcher)
        _buildFullWidthBranchSalesChart(context, theme, colorScheme),

        M3Spacing.gapMD,

        // 3. Cascading Filter Toolbar with integrated Year (2026), Date Range, Upload, Export & Search
        CascadingFilterToolbar(
          key: ValueKey('toolbar_${widget.apiClient.tenantId}'),
          selectedChain: selectedChain,
          selectedStoreId: selectedStoreId,
          selectedCategory: selectedCategory,
          selectedDateRange: selectedDateRange,
          selectedYear: _selectedYear,
          searchQuery: searchQuery,
          availableCategories: _availableCategories,
          chainStoresOverride: _chainStores,
          onChainChanged: (val) {
            setState(() {
              selectedChain = val;
              if (val != null && val.isNotEmpty) {
                _chartChain = val;
              }
            });
            _loadRecords();
          },
          onStoreChanged: (val) {
            setState(() => selectedStoreId = val);
            _loadRecords();
          },
          onCategoryChanged: (val) {
            setState(() => selectedCategory = val);
            _loadRecords();
          },
          onDateRangeChanged: (range) {
            setState(() => selectedDateRange = range);
            _loadRecords();
          },
          // One year selector per page: the data year lives in the ranking
          // card header ('سنة البيانات') and drives the whole tab; the
          // toolbar keeps only the date-range override.
          onSearchChanged: (val) {
            searchQuery = val;
            _loadRecords();
          },
          onUpload: () => _pickAndUploadSellOutFile(),
          isUploading: _isUploading,
          onExportExcel: _handleExportExcel,
          onExportPdf: _handleExportPdf,
        ),

        if (_recordsSummary.skuSummaries.isNotEmpty) ...[
          M3Spacing.gapMD,
          _buildAdecoPriceAndMarginMatrixSection(context, theme, colorScheme),
        ],

        M3Spacing.gapMD,

        // 4. Virtualized SKU Table
        VirtualizedSkuTable(
          records: records,
          isLoading: isLoading,
          onRecordTap: _openProductIdCardForRecord,
        ),
      ],
    );
  }

  Future<void> _openProductIdCardForRecord(SellOutRecordModel r) async {
    try {
      final q = r.itemCode.trim().isNotEmpty
          ? r.itemCode.trim()
          : (r.barcode.trim().isNotEmpty ? r.barcode.trim() : r.skuName.trim());
      if (q.isEmpty) return;
      final res = await widget.apiClient.getProductMaster(search: q);
      if (!mounted || res.items.isEmpty) return;
      ProductMasterItemModel matched = res.items.first;
      for (final it in res.items) {
        if (r.itemCode.isNotEmpty && it.itemCode == r.itemCode) {
          matched = it;
          break;
        }
        if (r.barcode.isNotEmpty && it.barcode == r.barcode) {
          matched = it;
          break;
        }
      }
      await ProductMasterScreen.showProductIdCardModal(
        context,
        apiClient: widget.apiClient,
        item: matched,
        onUpdated: (_) {
          _repo.invalidateAll();
          _loadRecords();
        },
      );
    } catch (_) {}
  }

  Future<void> _openProductIdCardForSummary(SellOutSkuSummaryModel s) async {
    try {
      final q = s.itemCode.trim().isNotEmpty
          ? s.itemCode.trim()
          : (s.barcode.trim().isNotEmpty ? s.barcode.trim() : s.skuName.trim());
      if (q.isEmpty) return;
      final res = await widget.apiClient.getProductMaster(search: q);
      if (!mounted || res.items.isEmpty) return;
      ProductMasterItemModel matched = res.items.first;
      for (final it in res.items) {
        if (s.itemCode.isNotEmpty && it.itemCode == s.itemCode) {
          matched = it;
          break;
        }
        if (s.barcode.isNotEmpty && it.barcode == s.barcode) {
          matched = it;
          break;
        }
      }
      await ProductMasterScreen.showProductIdCardModal(
        context,
        apiClient: widget.apiClient,
        item: matched,
        onUpdated: (_) {
          _repo.invalidateAll();
          _loadRecords();
        },
      );
    } catch (_) {}
  }

  static bool _matchesPriceMatrixFilter(SellOutSkuSummaryModel s, String filter) {
    switch (filter) {
      case 'healthy':
        return s.retailerMarginPct >= 10.0;
      case 'low_margin':
        return s.retailerMarginPct >= 0.0 && s.retailerMarginPct < 10.0 && s.factoryUnitCost > 0;
      case 'negative_margin':
        return s.retailerMarginPct < 0.0 || s.priceStatus == 'below_cost';
      case 'promo':
        return s.priceStatus == 'promo_discount' || s.priceDeltaPct <= -5.0;
      case 'all':
      default:
        return true;
    }
  }

  Widget _buildAdecoPriceAndMarginMatrixSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final allItems = _recordsSummary.skuSummaries;
    final filteredItems = allItems
        .where((s) => _matchesPriceMatrixFilter(s, _priceMatrixFilter))
        .take(25)
        .toList();

    final healthyCount = allItems.where((s) => _matchesPriceMatrixFilter(s, 'healthy')).length;
    final lowMarginCount = allItems.where((s) => _matchesPriceMatrixFilter(s, 'low_margin')).length;
    final negMarginCount = allItems.where((s) => _matchesPriceMatrixFilter(s, 'negative_margin')).length;
    final promoCount = allItems.where((s) => _matchesPriceMatrixFilter(s, 'promo')).length;

    // Readable M3 table roles: labelMedium headers, bodyMedium cells,
    // onSurfaceVariant for secondary (reference) prices.
    final headStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface);
    final cellStrong = cellStyle?.copyWith(fontWeight: FontWeight.w600);
    final cellMuted = cellStyle?.copyWith(color: colorScheme.onSurfaceVariant);

    return Card(
      key: const ValueKey('price_matrix_section'),
      elevation: 0,
      color: M3TableSurface.color(colorScheme),
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12.0,
              runSpacing: 8.0,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.price_check_rounded, color: colorScheme.onSurfaceVariant, size: 20.0),
                    const SizedBox(width: 8.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const M3SectionTitle('الأسعار وهامش السلسلة'),
                        Text(
                          'سعر البيع الفعلي مقابل قائمة الأسعار • ${_recordsSummary.matchedSkusCount} صنف مطابق',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                M3ChipSurface(
                  key: const ValueKey('price_summary_strip'),
                  color: colorScheme.surfaceContainerHigh,
                  child: Text(
                    'الكراتين المباعة ${CurrencyFormatter.formatNumber(_recordsSummary.totalCartonsSold.round())} كرتونة • تكلفة المصنع ${CurrencyFormatter.formatCompactEGP(_recordsSummary.totalFactoryCost)} • هامش السلسلة ${CurrencyFormatter.formatMarginSummary(_recordsSummary.totalRetailerGrossProfit, _recordsSummary.avgRetailerMarginPct)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            M3Spacing.gapSM,
            // Shared filter chips (same widget as the Sell-In table)
            SellTableFilterChips(
              options: SellTableFilterChips.marginOptions(
                all: allItems.length,
                healthy: healthyCount,
                lowMargin: lowMarginCount,
                negativeMargin: negMarginCount,
                promo: promoCount,
              ),
              selected: _priceMatrixFilter,
              onSelected: (v) => setState(() => _priceMatrixFilter = v),
            ),
            M3Spacing.gapSM,
            TableScrollContainer(
              key: const ValueKey('price_matrix_table'),
              showSwipeHint: false,
              columnFlex: _priceMatrixFlex,
              child: DataTable(
                headingRowHeight: 48.0,
                dataRowMinHeight: 52.0,
                // Name ≤2 lines + nested item code = ≤3 lines total.
                dataRowMaxHeight: 80.0,
                columnSpacing: M3Spacing.xxs,
                horizontalMargin: M3Spacing.xxs,
                headingTextStyle: headStyle,
                dataTextStyle: cellStyle,
                columns: _priceMatrixColumns,
                rows: centerCellsUnderCenteredHeadings(_priceMatrixColumns, filteredItems.map((s) {
                  final isNegMargin = s.retailerMarginPct < 0;
                  final marginColor = isNegMargin ? colorScheme.error : colorScheme.secondary;
                  final code = s.itemCode.isNotEmpty ? s.itemCode : s.barcode;
                  return DataRow(
                    cells: [
                      DataCell(
                        InkWell(
                          onTap: () => _openProductIdCardForSummary(s),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: _priceColName),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: s.skuName,
                                  child: Text(
                                    s.skuName,
                                    key: const ValueKey('price_matrix_sku_name'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                    style: cellStrong,
                                  ),
                                ),
                                if (code.isNotEmpty)
                                  HyphenatedCodeText(
                                    code,
                                    key: const ValueKey('price_matrix_item_code'),
                                    maxLines: 1,
                                    maxWidth: _priceColName,
                                    textAlign: TextAlign.start,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataCell(_priceCell('${s.unitsPerCarton}', style: cellMuted, maxWidth: _priceColUnitsPer)),
                      DataCell(_priceCell(CurrencyFormatter.formatNumber(s.totalUnitsSold), style: cellStrong, maxWidth: _priceColUnits)),
                      DataCell(_priceCell(s.totalCartonsSold.toStringAsFixed(1), style: cellStrong, maxWidth: _priceColCartons)),
                      DataCell(_priceCell(s.officialConsumerRsp > 0 ? '${s.officialConsumerRsp.toStringAsFixed(2)} ج.م' : '—', style: cellMuted, maxWidth: _priceColList)),
                      DataCell(_priceCell('${s.avgSellingPrice.toStringAsFixed(2)} ج.م', style: cellStrong, maxWidth: _priceColSell)),
                      DataCell(
                        _priceCell(
                          s.officialConsumerRsp > 0 ? CurrencyFormatter.formatSignedPct(s.priceDeltaPct) : '—',
                          key: const ValueKey('price_matrix_delta_pct'),
                          maxWidth: _priceColDelta,
                          style: cellStrong?.copyWith(color: s.priceDeltaPct < -5.0
                                ? colorScheme.tertiary
                                : (s.priceDeltaPct > 5.0 ? colorScheme.error : colorScheme.onSurfaceVariant)),
                        ),
                      ),
                      DataCell(_priceCell(s.factoryUnitCost > 0 ? '${s.factoryUnitCost.toStringAsFixed(2)} ج.م' : '—', style: cellMuted, maxWidth: _priceColFactory)),
                      DataCell(_priceCell(s.netCartonInvoiceCost > 0 ? '${s.netCartonInvoiceCost.toStringAsFixed(2)} ج.م' : '—', style: cellMuted, maxWidth: _priceColNetCarton)),
                      DataCell(_priceCell(CurrencyFormatter.formatCompactEGP(s.totalNetRevenue), style: cellStrong?.copyWith(color: colorScheme.primary), maxWidth: _priceColNetSales)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _priceColMargin),
                          child: M3WrapText(
                            s.retailerMarginPct != 0
                                ? CurrencyFormatter.formatMarginSummary(s.retailerGrossProfit, s.retailerMarginPct)
                                : '—',
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            style: cellStrong?.copyWith(color: marginColor),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FULL-WIDTH CHAIN BRANCHES SALES RANKING CHART (HIGHEST TO LOWEST)
  // ===========================================================================
  static String _formatChainDisplayAr(String chainCode) {
    switch (chainCode.trim().toLowerCase()) {
      case 'fathalla':
        return 'أسواق فتح الله';
      case 'gomla':
        return 'جملة ماركت';
      case 'beet-elgomla':
        return 'بيت الجملة';
      case 'carrefour':
        return 'كارفور';
      case 'spinneys':
        return 'سبينيس';
      case 'institutions':
        return 'قطاع المؤسسات';
      case 'all':
        return 'كل السلاسل';
      default:
        return chainCode.toUpperCase();
    }
  }

  /// Display-only map of store names with a shared leading prefix removed.
  /// Values, exports, and API queries keep the original name.
  Map<String, String> get _storeDisplay {
    final names = <String>{
      ...records.map((r) => r.storeName),
      ..._branchChartItems.map((b) => b.storeName),
    }..removeWhere((n) => n.trim().isEmpty);
    return displayNamesWithoutSharedPrefix(names);
  }

  String _displayStore(String raw) {
    if (raw.isEmpty || raw == '—') return raw;
    return _storeDisplay[raw] ?? raw;
  }

  Widget _buildFullWidthBranchSalesChart(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final activeChainCode = (selectedChain != null && selectedChain!.isNotEmpty)
        ? selectedChain!
        : _chartChain;

    // Build branch list from _branchChartItems (full backend store matrix for active chain & year)
    final List<StoreBenchmarkItem> rawBranches = _branchChartItems.isNotEmpty
        ? List<StoreBenchmarkItem>.from(_branchChartItems)
        : [];

    // Sort descending (High to Low) or ascending (Low to High)
    rawBranches.sort((a, b) => _chartSortAscending
        ? a.totalRevenue.compareTo(b.totalRevenue)
        : b.totalRevenue.compareTo(a.totalRevenue));

    final double totalChainRev = rawBranches.fold<double>(0.0, (acc, b) => acc + b.totalRevenue);
    final double maxBranchRev = rawBranches.isNotEmpty
        ? rawBranches.map((b) => b.totalRevenue).reduce(math.max)
        : 1.0;
    final double avgBranchRev = rawBranches.isNotEmpty ? (totalChainRev / rawBranches.length) : 0.0;

    // Identify Highest (#1) and Lowest branch regardless of current sort direction
    StoreBenchmarkItem? highestBranch;
    StoreBenchmarkItem? secondBranch;
    StoreBenchmarkItem? lowestBranch;
    if (rawBranches.isNotEmpty) {
      final descList = List<StoreBenchmarkItem>.from(rawBranches)
        ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
      highestBranch = descList.first;
      if (descList.length > 1) secondBranch = descList[1];
      lowestBranch = descList.last;
    }

    final int compYear = (_selectedYear > 0 ? _selectedYear : _currentYear) - 1;
    // Ranking header keeps full-period إجمالي السلسلة; (+x% عن YYYY) is like-for-like.
    final double? chainYoYPct = _selectedYear > 0
        ? likeForLikeYoyPct(_yoyCurrentTotalChainRevenue, _prevYearTotalChainRevenue)
        : null;

    return Container(
      key: const ValueKey('full_width_branch_sales_chart'),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Chart Header + Interactive Chain & Year (2026 Default / 2025) Controls
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                key: const ValueKey('branch_chart_header'),
                borderRadius: M3Shape.radiusMd,
                onTap: () => setState(
                    () => _branchChartExpanded = !_branchChartExpanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _branchChartExpanded
                          ? AppIcons.expandLess
                          : AppIcons.expandMore,
                      key: const ValueKey('branch_chart_expand_chevron'),
                      size: 24.0,
                    ),
                    const SizedBox(width: 6.0),
                    Flexible(child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const M3SectionTitle('ترتيب الفروع حسب المبيعات'),
                        const SizedBox(height: 4.0),
                        Text(
                          '${_formatChainDisplayAr(activeChainCode)} • ${_selectedYear > 0 ? "سنة $_selectedYear" : "كل السنوات"} • ${rawBranches.length} فرع • إجمالي السلسلة: ${CurrencyFormatter.formatCompactEGP(totalChainRev)}${chainYoYPct != null ? " (${CurrencyFormatter.formatSignedPct(chainYoYPct)} عن $compYear)" : (_selectedYear > 0 ? " (— عن $compYear)" : "")}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )),
                  ],
                ),
              ),

              // Controls: Chain Selector + Year Switcher (2026 Default, 2025) + Sort & View Mode
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Chain Dropdown inside Chart
                  M3Dropdown<String>(
                    key: const ValueKey('branch_chart_chain_dropdown'),
                    width: 240.0,
                    fitOptions: true,
                    value: const ['fathalla', 'gomla', 'beet-elgomla', 'carrefour', 'spinneys', 'all']
                            .contains(activeChainCode)
                        ? activeChainCode
                        : 'fathalla',
                    options: const [
                      M3DropdownOption('fathalla', 'أسواق فتح الله (Fathalla)'),
                      M3DropdownOption('gomla', 'جملة ماركت (Gomla)'),
                      M3DropdownOption('beet-elgomla', 'بيت الجملة'),
                      M3DropdownOption('carrefour', 'كارفور'),
                      M3DropdownOption('spinneys', 'سبينيس'),
                      M3DropdownOption('all', 'كل السلاسل'),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _chartChain = val;
                        selectedChain = val == 'all' ? null : val;
                        selectedStoreId = null;
                      });
                      _loadRecords();
                    },
                  ),

                  // Year — M3 menu filter (dashboard header pattern): one
                  // line, 40dp; outlined at the current year, tonal otherwise.
                  M3MenuFilter<int>(
                    buttonKey: const ValueKey('branch_chart_year_dropdown'),
                    tooltip: 'سنة البيانات — تُطبَّق على المؤشرات والترتيب والجداول',
                    icon: AppIcons.event,
                    label: _selectedYear == 0
                        ? 'سنة البيانات: الكل'
                        : 'سنة البيانات: $_selectedYear',
                    active: _selectedYear != _currentYear,
                    onSelected: (y) {
                      setState(() {
                        _selectedYear = y;
                        selectedDateRange = null;
                      });
                      _loadRecords();
                    },
                    items: [
                      for (final y in [_currentYear, _currentYear - 1, 0])
                        (
                          y,
                          M3MenuFilter.itemText(context,
                              y == 0 ? 'كل السنوات' : '$y', y == _selectedYear),
                        ),
                    ],
                  ),

                  // Sort High-to-Low vs Low-to-High Button
                  OutlinedButton.icon(
                    key: const ValueKey('branch_chart_sort_toggle'),
                    onPressed: () {
                      setState(() => _chartSortAscending = !_chartSortAscending);
                    },
                    icon: Icon(
                      _chartSortAscending ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 18.0,
                    ),
                    label: Text(
                      _chartSortAscending ? 'الأقل للأعلى' : 'الأعلى للأقل',
                    ),
                  ),

                  
                ],
              ),
            ],
          ),

          M3Spacing.gapSM,

          // 2. Quick Executive Branch Highlights Strip (4 Single-Line Cards on One Row + Theme-Derived Palette)
          if (_branchChartExpanded && rawBranches.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, badgeConstraints) {
                // First 3 cards derive their color directly from the unified Theme primary color
                final Color themePrimary1 = colorScheme.primary;
                final Color themePrimary2 = Color.lerp(colorScheme.primary, colorScheme.secondary, 0.25) ?? colorScheme.primary;
                final Color themePrimary3 = Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.35) ?? colorScheme.primary;
                final Color themeAccent4 = colorScheme.secondary;

                final cards = <Widget>[
                  if (highestBranch != null)
                    _buildBranchInsightBadge(
                      context,
                      label: 'الأعلى مبيعًا',
                      branchName: _displayStore(highestBranch.storeName),
                      valueText:
                          '${CurrencyFormatter.formatCompactEGP(highestBranch.totalRevenue)} (${totalChainRev > 0 ? ((highestBranch.totalRevenue / totalChainRev) * 100).toStringAsFixed(1) : "0.0"}%)',
                      color: themePrimary1,
                      icon: Icons.emoji_events_rounded,
                      isHighlighted: true,
                    ),
                  if (secondBranch != null)
                    _buildBranchInsightBadge(
                      context,
                      label: 'المركز الثاني',
                      branchName: _displayStore(secondBranch.storeName),
                      valueText:
                          '${CurrencyFormatter.formatCompactEGP(secondBranch.totalRevenue)} (${totalChainRev > 0 ? ((secondBranch.totalRevenue / totalChainRev) * 100).toStringAsFixed(1) : "0.0"}%)',
                      color: themePrimary2,
                      icon: Icons.workspace_premium_rounded,
                    ),
                  _buildBranchInsightBadge(
                    context,
                    label: 'متوسط الفرع',
                    branchName: '${rawBranches.length} فرع نشط',
                    valueText: CurrencyFormatter.formatCompactEGP(avgBranchRev),
                    color: themePrimary3,
                    icon: Icons.analytics_rounded,
                  ),
                  if (lowestBranch != null && rawBranches.length > 1)
                    _buildBranchInsightBadge(
                      context,
                      label: 'الأقل مبيعًا',
                      branchName: _displayStore(lowestBranch.storeName),
                      valueText:
                          '${CurrencyFormatter.formatCompactEGP(lowestBranch.totalRevenue)} (${totalChainRev > 0 ? ((lowestBranch.totalRevenue / totalChainRev) * 100).toStringAsFixed(1) : "0.0"}%)',
                      color: themeAccent4,
                      icon: Icons.trending_down_rounded,
                    ),
                ];

                if (badgeConstraints.maxWidth >= 860 && cards.length == 4) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[0]),
                            M3Spacing.hGapSM,
                            Expanded(child: cards[1]),
                            M3Spacing.hGapSM,
                            Expanded(child: cards[2]),
                            M3Spacing.hGapSM,
                            Expanded(child: cards[3]),
                          ],
                        ),
                      ),
                      if (selectedStoreId != null) ...[
                        const SizedBox(height: 8.0),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ActionChip(
                            avatar: const Icon(Icons.filter_alt_off_rounded, size: 18.0),
                            label: const Text('عرض كل الفروع'),
                            onPressed: () {
                              setState(() => selectedStoreId = null);
                              _loadRecords();
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                }

                return Wrap(
                  spacing: M3Spacing.sm,
                  runSpacing: M3Spacing.xs,
                  children: [
                    ...cards,
                    if (selectedStoreId != null)
                      ActionChip(
                        avatar: const Icon(Icons.filter_alt_off_rounded, size: 18.0),
                        label: const Text('عرض كل الفروع'),
                        onPressed: () {
                          setState(() => selectedStoreId = null);
                          _loadRecords();
                        },
                      ),
                  ],
                );
              },
            ),
            M3Spacing.gapSM,
          ],

          // 3. All Branches Visual Chart Area (Split Across Two Rows for Maximum Clarity & Breathing Room)
          if (!_branchChartExpanded)
            const SizedBox.shrink()
          else if (rawBranches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0),
              child: Center(
                child: Text(
                  'لا توجد بيانات فروع لهذه السنة.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            // Horizontal Ranked Bars View (All Branches)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420.0),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rawBranches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8.0),
                itemBuilder: (context, idx) {
                  final b = rawBranches[idx];
                  final ratio = maxBranchRev > 0 ? (b.totalRevenue / maxBranchRev).clamp(0.02, 1.0) : 0.0;
                  final sharePct = totalChainRev > 0 ? (b.totalRevenue / totalChainRev) * 100.0 : 0.0;
                  final branchKey = b.storeId.isNotEmpty ? b.storeId : b.storeName;
                  final prevItem = _prevYearBranchMap[branchKey];
                  final yoyCurItem = _yoyCurrentBranchMap[branchKey];
                  final double? branchYoY = _selectedYear > 0
                      ? likeForLikeYoyPct(
                          yoyCurItem?.totalRevenue ?? 0.0,
                          prevItem?.totalRevenue ?? 0.0,
                        )
                      : null;
                  final isSelected = selectedStoreId != null &&
                      (selectedStoreId == b.storeId || selectedStoreId == b.storeName);

                  final Color barColor = b.rank <= 3
                      ? colorScheme.primary
                      : (b.totalRevenue >= avgBranchRev
                          ? Color.lerp(colorScheme.primary, colorScheme.secondary, 0.35)!
                          : Color.lerp(colorScheme.primary, colorScheme.outline, 0.35)!);

                  return InkWell(
                    borderRadius: M3Shape.radiusSm,
                    onTap: () {
                      setState(() {
                        selectedStoreId = isSelected ? null : (b.storeId.isNotEmpty ? b.storeId : b.storeName);
                      });
                      _loadRecords();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primaryContainer.withOpacity(0.45)
                            : colorScheme.surfaceContainerLowest,
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 34.0,
                            child: Text(
                              '#${b.rank}',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: b.rank <= 3 ? colorScheme.primary : colorScheme.onSurfaceVariant),
                            ),
                          ),
                          SizedBox(
                            width: 190.0,
                            child: Text(
                              _displayStore(b.storeName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodySmall)),
                            ),
                          ),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: M3Shape.radiusSm,
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 14.0,
                                backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.55),
                                color: barColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          SizedBox(
                            width: 95.0,
                            child: Text(
                              CurrencyFormatter.formatCompactEGP(b.totalRevenue),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: barColor),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          SizedBox(
                            width: 52.0,
                            child: Text(
                              '${sharePct.toStringAsFixed(1)}%',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          SizedBox(
                            key: ValueKey('branch_growth_slot_${b.rank}'),
                            width: 64.0,
                            child: branchYoY == null
                                ? const SizedBox.shrink()
                                : Text(
                                    CurrencyFormatter.formatSignedPct(branchYoY, decimals: 0),
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .merge(TextStyle(
                                          fontSize: M3FontSize.labelSmall,
                                          fontWeight: FontWeight.w800,
                                          color: branchYoY >= 0
                                              ? colorScheme.primary
                                              : colorScheme.error,
                                        )),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          
        ],
      ),
    );
  }

  Widget _buildBranchInsightBadge(
    BuildContext context, {
    required String label,
    required String branchName,
    required String valueText,
    required Color color,
    required IconData icon,
    bool isHighlighted = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // Neutral strip roles (no tinted green / blue fills); the highlighted
    // card is one step higher on the same surface scale.
    return Container(
      key: ValueKey('insight_badge_$label'),
      constraints: const BoxConstraints(minHeight: 72.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(icon, size: 18.0, color: color),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  label,
                  style: M3TextVariants.denseLabelHeavy.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  branchName,
                  style: M3TextVariants.denseLabelHeavy.copyWith(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 8.0),
              M3ChipSurface(
                color: colorScheme.surfaceContainerHighest,
                child: Text(
                  valueText,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PERFORMANCE & BRANCH ANALYTICS (PARETO 80/20 & STORE VELOCITY)
  // ===========================================================================
  Widget _buildPerformanceAndBranchAnalyticsTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final effectiveRecords = _perfChain == 'all'
        ? records
        : records.where((r) => r.retailerChain.toLowerCase() == _perfChain.toLowerCase()).toList();

    // 1. Group records by Branch (use full backend StoreBenchmarkItem list if available for the selected chain)
    final branchMap = <String, ({
      String storeId,
      String storeName,
      String chain,
      String region,
      int units,
      double revenue,
    })>{};
    if (_branchChartItems.isNotEmpty &&
        (_perfChain == 'all' || _perfChain.toLowerCase() == _chartChain.toLowerCase())) {
      for (final item in _branchChartItems) {
        final chainName = item.retailerChain.isNotEmpty ? item.retailerChain : _chartChain;
        final sId = item.storeId.isNotEmpty ? item.storeId : item.storeName;
        final key = '${chainName}_$sId';
        branchMap[key] = (
          storeId: sId,
          storeName: item.storeName.isNotEmpty ? item.storeName : item.storeId,
          chain: chainName,
          region: item.region.isNotEmpty ? item.region : '—',
          units: item.totalUnits,
          revenue: item.totalRevenue,
        );
      }
    } else {
      for (final r in effectiveRecords) {
        final sId = r.storeId.isNotEmpty ? r.storeId : r.storeName;
        final key = '${r.retailerChain}_$sId';
        final existing = branchMap[key];
        if (existing == null) {
          branchMap[key] = (
            storeId: sId,
            storeName: r.storeName.isNotEmpty ? r.storeName : r.storeId,
            chain: r.retailerChain,
            region: '—',
            units: r.quantitySold,
            revenue: r.netRevenue,
          );
        } else {
          branchMap[key] = (
            storeId: existing.storeId,
            storeName: existing.storeName,
            chain: existing.chain,
            region: existing.region,
            units: existing.units + r.quantitySold,
            revenue: existing.revenue + r.netRevenue,
          );
        }
      }
    }
    final branchList = branchMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    final int compYear = (_selectedYear > 0 ? _selectedYear : _currentYear) - 1;
    final int currYearLabel = _selectedYear > 0 ? _selectedYear : _currentYear;

    // Branch growth table: the 2026 / 2025 sales columns, the difference and the
    // YoY % all use the SAME matched-month window (see buildBranchGrowthRows).
    final branchGrowthMatrix = buildBranchGrowthRows(
      branches: [
        for (final b in branchList)
          BranchGrowthBase(
            storeId: b.storeId,
            storeName: b.storeName,
            chain: b.chain,
            region: b.region,
            units: b.units,
            revenue: b.revenue,
          ),
      ],
      prevByStore: _prevYearBranchMap,
      currentLikeForLikeByStore: _yoyCurrentBranchMap,
    );
    final bool compareMatchedMonths = _selectedMonth == 0 &&
        selectedDateRange == null &&
        _matchedYoyMonths.isNotEmpty;

    final filteredGrowthBranches = branchGrowthMatrix.where((item) {
      if (_perfGrowthStatusFilter != 'all' && item.status != _perfGrowthStatusFilter) {
        return false;
      }
      if (_perfSearch.isNotEmpty) {
        final q = _perfSearch.toLowerCase();
        if (!item.storeName.toLowerCase().contains(q) &&
            !item.region.toLowerCase().contains(q) &&
            !item.chain.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final growingBranchesCount = branchGrowthMatrix.where((b) => b.status == 'growing').length;
    final decliningBranchesCount = branchGrowthMatrix.where((b) => b.status == 'declining').length;
    final newBranchesCount = branchGrowthMatrix.where((b) => b.status == 'new_branch').length;
    final totalCurrMatrixRev = _yoyCurrentTotalChainRevenue;
    final totalPrevMatrixRev = _prevYearTotalChainRevenue;
    final totalMatrixVarianceEgp = _yoyCurrentTotalChainRevenue - totalPrevMatrixRev;
    final double? totalMatrixYoYPct =
        likeForLikeYoyPct(_yoyCurrentTotalChainRevenue, totalPrevMatrixRev);

    final growingSorted = branchGrowthMatrix
        .where((b) => b.yoyGrowthPct != null)
        .toList()
      ..sort((a, b) => (b.yoyGrowthPct ?? -999).compareTo(a.yoyGrowthPct ?? -999));
    final fastestGrowingBranch = growingSorted.isNotEmpty ? growingSorted.first : null;

    // 2. Group records by SKU & infer Brand
    final skuMap = <String, ({String skuName, String itemCode, String barcode, String brand, String category, int units, double revenue})>{};
    for (final r in effectiveRecords) {
      final key = r.barcode.isNotEmpty ? r.barcode : r.skuName;
      final inferredBrand = SmartBrandExtractor.inferBrand(
        r.skuName,
        subCategory: r.category,
        itemCode: r.itemCode,
      );
      final existing = skuMap[key];
      if (existing == null) {
        skuMap[key] = (
          skuName: r.skuName,
          itemCode: r.itemCode,
          barcode: r.barcode,
          brand: inferredBrand,
          category: r.category,
          units: r.quantitySold,
          revenue: r.netRevenue,
        );
      } else {
        skuMap[key] = (
          skuName: existing.skuName,
          itemCode: existing.itemCode.isNotEmpty ? existing.itemCode : r.itemCode,
          barcode: existing.barcode.isNotEmpty ? existing.barcode : r.barcode,
          brand: existing.brand,
          category: existing.category,
          units: existing.units + r.quantitySold,
          revenue: existing.revenue + r.netRevenue,
        );
      }
    }

    final totalRevenueAll = effectiveRecords.fold<double>(0.0, (acc, r) => acc + r.netRevenue);

    // Compute Pareto 80/20 share
    final sortedByRev = skuMap.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    int top20PctCount = (sortedByRev.length * 0.2).ceil();
    if (top20PctCount < 1 && sortedByRev.isNotEmpty) top20PctCount = 1;
    final top20Revenue = sortedByRev.take(top20PctCount).fold<double>(0.0, (sum, i) => sum + i.revenue);
    final paretoSharePct = totalRevenueAll > 0 ? (top20Revenue / totalRevenueAll) * 100 : 0.0;

    final topSku = sortedByRev.isNotEmpty ? sortedByRev.first : null;
    final topBranch = branchList.isNotEmpty ? branchList.first : null;
    final branchTotalRevenueAll = branchList.fold<double>(0.0, (sum, b) => sum + b.revenue);
    final effectiveChainTotalRev = branchTotalRevenueAll > 0 ? branchTotalRevenueAll : totalRevenueAll;
    final avgBranchRevenue = branchList.isNotEmpty ? (effectiveChainTotalRev / branchList.length) : 0.0;

    const monthLabelsAr = <int, String>{
      0: 'كل الشهور',
      1: 'يناير',
      2: 'فبراير',
      3: 'مارس',
      4: 'أبريل',
      5: 'مايو',
      6: 'يونيو',
      7: 'يوليو',
      8: 'أغسطس',
      9: 'سبتمبر',
      10: 'أكتوبر',
      11: 'نوفمبر',
      12: 'ديسمبر',
    };
    final String perfPeriodBadgeAr =
        '${_selectedYear > 0 ? "سنة $_selectedYear" : "كل السنوات"} • ${monthLabelsAr[_selectedMonth] ?? "كل الشهور"}';

    // Filter SKUs for Excel export if needed
    final availableBrands = skuMap.values.map((s) => s.brand).toSet().toList()..sort();
    final filteredSkus = sortedByRev.where((sku) {
      if (_perfBrand != 'all' && sku.brand != _perfBrand) return false;
      if (_perfSearch.isNotEmpty) {
        if (!ApiClient.matchesProductSearch(
          _perfSearch,
          itemCode: sku.itemCode,
          barcode: sku.barcode,
          skuName: sku.skuName,
          category: sku.category,
          brand: sku.brand,
        )) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Executive Performance KPI Summary Cards (4 Cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'الصنف الأعلى مبيعًا',
              titleEn: 'Top SKU',
              value: topSku != null ? topSku.skuName : '—',
              textValue: true,
              // Long item names stay one line (ellipsis + hover tooltip) so
              // this card matches the height of the other three KPIs.
              singleLineValue: true,
              subtitle: topSku != null
                  ? '${CurrencyFormatter.formatCompactEGP(topSku.revenue)} (${CurrencyFormatter.formatNumber(topSku.units)} وحدة) • $perfPeriodBadgeAr'
                  : 'لا توجد مبيعات • $perfPeriodBadgeAr',
              icon: Icons.star_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'حصة أعلى 20% من الأصناف',
              titleEn: "Top 20% SKUs' Share",
              value: '${paretoSharePct.toStringAsFixed(1)}%',
              subtitle: '$top20PctCount صنف تحقق معظم المبيعات • $perfPeriodBadgeAr',
              icon: Icons.pie_chart_rounded,
              color: Color.lerp(colorScheme.primary, colorScheme.secondary, 0.30) ?? colorScheme.primary,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'الفرع الأعلى مبيعًا',
              titleEn: 'Top Store',
              value: topBranch != null ? _displayStore(topBranch.storeName) : '—',
              textValue: true,
              subtitle: topBranch != null
                  ? '${topBranch.chain.toUpperCase()} • ${CurrencyFormatter.formatCompactEGP(topBranch.revenue)} • $perfPeriodBadgeAr'
                  : 'لا توجد فروع',
              icon: Icons.leaderboard_rounded,
              color: Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.40) ?? colorScheme.primary,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'متوسط مبيعات الفرع',
              titleEn: 'Avg. Sales per Store',
              value: CurrencyFormatter.formatCompactEGP(avgBranchRevenue),
              subtitle: '${branchList.length} فرع نشط • $perfPeriodBadgeAr',
              icon: Icons.speed_rounded,
              color: colorScheme.secondary,
            );

            return _buildFourCardResponsiveLayout(
              constraints.maxWidth,
              card1,
              card2,
              card3,
              card4,
            );
          },
        ),

        M3Spacing.gapMD,

        // 2. Filter Bar for Performance Analytics
        Container(
          key: const ValueKey('perf_filter_bar'),
          padding: M3Spacing.pSm,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 1. Year Filter (Default: 2026)
                  SizedBox(
                    width: kYearDropdownWidth,
                    child: M3Dropdown<int>(
key: const ValueKey('perf_year_dropdown'),
value: [..._recentYears, 0].contains(_selectedYear)
                          ? _selectedYear
                          : _currentYear,
label: 'سنة البيانات',
leadingIcon: Icons.calendar_today_rounded,
expand: true,
options: m3OptionsFromMenuItems<int>([
                        for (final y in _recentYears) DropdownMenuItem(value: y, child: Text('$y')),
                        const DropdownMenuItem(value: 0, child: Text('كل السنوات')),
                      ]),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedYear = v;
                            selectedDateRange = null;
                          });
                          _loadRecords();
                        }
                      }),
),
                  ),

                  // 2. Month Filter (Default: All Months / 0)
                  M3Dropdown<int>(
width: 190.0,
fitOptions: true,
key: const ValueKey('perf_month_dropdown'),
value: _selectedMonth,
label: 'الشهر',
leadingIcon: Icons.date_range_rounded,
options: m3OptionsFromMenuItems<int>(monthLabelsAr.entries
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e.key,
                              child: Text(
                                e.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList()),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedMonth = v;
                            selectedDateRange = null;
                          });
                          _loadRecords();
                        }
                      }),
),

                  // 3. Chain Filter
                  M3Dropdown<String>(
width: 190.0,
fitOptions: true,
value: _perfChain,
label: 'السلسلة',
leadingIcon: Icons.storefront_rounded,
options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(value: 'all', child: Text('كل السلاسل')),
                        const DropdownMenuItem(value: 'fathalla', child: Text('أسواق فتح الله')),
                        const DropdownMenuItem(value: 'gomla', child: Text('جملة ماركت')),
                        const DropdownMenuItem(value: 'beet-elgomla', child: Text('بيت الجملة')),
                        const DropdownMenuItem(value: 'chain-1080314', child: Text('الوكالة')),
                      ]),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() {
                            _perfChain = v;
                            selectedChain = v == 'all' ? null : v;
                            if (v != 'all') _chartChain = v;
                          });
                          _loadRecords();
                        }
                      }),
),
                  M3Dropdown<String>(
width: 210.0,
fitOptions: true,
value: availableBrands.contains(_perfBrand) ? _perfBrand : 'all',
label: 'العلامة التجارية',
leadingIcon: Icons.branding_watermark_rounded,
options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(value: 'all', child: Text('كل العلامات التجارية')),
                        ...availableBrands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                      ]),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() {
                            _perfBrand = v;
                          });
                        }
                      }),
),
                  M3SearchFieldWidth(
                    hintText: 'ابحث بالفرع أو المنطقة أو الصنف',
                    hintStyle: _perfSearchHintStyle(theme, colorScheme),
                    width: 220.0,
                    child: TextField(
                      key: const ValueKey('perf_search_field'),
                      controller: _perfSearchController,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'ابحث بالفرع أو المنطقة أو الصنف',
                        hintStyle: _perfSearchHintStyle(theme, colorScheme),
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18.0),
                        suffixIcon: _perfSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18.0),
                                onPressed: () {
                                  _perfSearchController.clear();
                                  setState(() {
                                    _perfSearch = '';
                                  });
                                },
                              )
                            : null,
                        // Same 40dp field as the M3Dropdown filters beside it.
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        constraints: const BoxConstraints(maxHeight: M3ToolbarButton.height),
                        border: const OutlineInputBorder(borderRadius: M3Shape.radiusMd),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _perfSearch = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      final headers = ['الترتيب', 'اسم الصنف', 'العلامة التجارية', 'الفئة', 'الوحدات المباعة', 'صافي المبيعات (ج.م)', 'نسبة المساهمة'];
                      final rows = filteredSkus.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final s = entry.value;
                        final share = totalRevenueAll > 0 ? (s.revenue / totalRevenueAll) * 100 : 0.0;
                        return [idx, s.skuName, s.brand, s.category, s.units, s.revenue, '${share.toStringAsFixed(1)}%'];
                      }).toList();
                      final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
                      final fn = 'tashil_pareto_performance_${DateTime.now().millisecondsSinceEpoch}.csv';
                      ExcelExportService.downloadCsv(fn, csv);
                      M3Feedback.showSuccess(context, 'تم تصدير التقرير.');
                    },
                    icon: const Icon(Icons.download_rounded, size: 18.0),
                    label: const Text('تصدير'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final headers = ['الفرع', 'السلسلة', 'الوحدات المباعة', 'صافي المبيعات (ج.م)', 'الحصة %'];
                      final rows = branchList.map((b) {
                        final share = totalRevenueAll > 0 ? (b.revenue / totalRevenueAll) * 100 : 0.0;
                        return [b.storeName, b.chain.toUpperCase(), b.units, CurrencyFormatter.formatEGP(b.revenue), '${share.toStringAsFixed(1)}%'];
                      }).toList();
                      final html = ExcelExportService.generatePrintableReport(
                        title: 'تقرير أداء الفروع',
                        headers: headers,
                        rows: rows,
                        metadata: {
                          'إجمالي المبيعات': CurrencyFormatter.formatEGP(totalRevenueAll),
                          'عدد الفروع': '${branchList.length}',
                        },
                      );
                      final fn = 'tashil_branch_velocity_${DateTime.now().millisecondsSinceEpoch}.html';
                      ExcelExportService.downloadHtml(fn, html);
                      M3Feedback.showSuccess(context, 'التقرير جاهز للطباعة.');
                    },
                    icon: const Icon(Icons.print_rounded, size: 18.0),
                    label: const Text('طباعة'),
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Section A: Top Branches Sales Velocity Table
        Container(
          key: const ValueKey('branch_velocity_section'),
          decoration: BoxDecoration(
            color: M3TableSurface.color(colorScheme),
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 8.0),
                child: Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: colorScheme.onSurfaceVariant, size: 20.0),
                    const SizedBox(width: 8.0),
                    const M3SectionTitle('أداء الفروع'),
                    const Spacer(),
                    Text(
                      '${branchList.length} فرع نشط',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TableScrollContainer(
                controller: _branchTableScrollController,
                showSwipeHint: true,
                padding: const EdgeInsets.all(12.0),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  columns: [
                    _centeredColumn('الترتيب'),
                    _centeredColumn('الفرع'),
                    _centeredColumn('السلسلة'),
                    _centeredColumn('الكمية المباعة', numeric: true),
                    _centeredColumn('صافي المبيعات (ج.م)', numeric: true),
                    _centeredColumn('حصة المبيعات %', numeric: true),
                  ],
                  rows: branchList.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final b = entry.value;
                    final branchTotalRev = branchList.fold<double>(0.0, (sum, item) => sum + item.revenue);
                    final sharePct = branchTotalRev > 0 ? (b.revenue / branchTotalRev) * 100 : 0.0;
                    return DataRow(
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            key: const ValueKey('branch_rank_badge'),
                            constraints: const BoxConstraints(minWidth: M3ChipStyle.minHeight),
                            child: M3ChipSurface(
                              color: idx <= 3
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              child: Text(
                                '$idx',
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: idx <= 3 ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(_displayStore(b.storeName), style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(
                          M3ChipSurface(
                              color: colorScheme.surfaceContainerHigh,
                              child: Text(
                              b.chain.toUpperCase(),
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        DataCell(Text(CurrencyFormatter.formatNumber(b.units))),
                        DataCell(
                          Text(
                            CurrencyFormatter.formatEGP(b.revenue),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 50.0,
                                child: ClipRRect(
                                  borderRadius: M3Shape.radiusXs,
                                  child: LinearProgressIndicator(
                                    value: (sharePct / 100).clamp(0.0, 1.0),
                                    backgroundColor: colorScheme.surfaceContainerHighest,
                                    color: colorScheme.primary,
                                    minHeight: 6.0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text('${sharePct.toStringAsFixed(1)}%'),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 4. Section B: Branch YoY & MoM Growth Matrix (مقارنة نمو وتراجع الفروع سنوياً وشهرياً)
        Container(
          key: const ValueKey('branch_growth_matrix_section'),
          decoration: BoxDecoration(
            color: M3TableSurface.color(colorScheme),
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header + Period Badge
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 10.0),
                child: Wrap(
                  spacing: 12.0,
                  runSpacing: 8.0,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(0.55),
                            borderRadius: M3Shape.radiusSm,
                          ),
                          child: Icon(
                            Icons.trending_up_rounded,
                            color: colorScheme.primary,
                            size: 20.0,
                          ),
                        ),
                        const SizedBox(width: 10.0),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              M3SectionTitle(
                                'نمو الفروع: $currYearLabel مقابل $compYear',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2.0),
                              Text(
                                compareMatchedMonths
                                    ? 'مقارنة نفس الشهور: ${matchedMonthsLabelAr(_matchedYoyMonths)} • سنة $currYearLabel مقابل $compYear'
                                    : 'نمو الفروع (سنوي وشهري) • $perfPeriodBadgeAr',
                                key: const ValueKey('branch_growth_subtitle'),
                                maxLines: 2,
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Status Filter Chips
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 6.0,
                      children: [
                        ChoiceChip(
                          label: Text('الكل (${branchGrowthMatrix.length})'),
                          selected: _perfGrowthStatusFilter == 'all',
                          onSelected: (_) => setState(() => _perfGrowthStatusFilter = 'all'),
                        ),
                        ChoiceChip(
                          avatar: const Icon(AppIcons.trendingUp, size: 18.0),
                  label: Text('فروع نامية ($growingBranchesCount)'),
                          selected: _perfGrowthStatusFilter == 'growing',
                          onSelected: (_) => setState(() => _perfGrowthStatusFilter = 'growing'),
                        ),
                        ChoiceChip(
                          avatar: const Icon(AppIcons.trendingDown, size: 18.0),
                  label: Text('فروع متراجعة ($decliningBranchesCount)'),
                          selected: _perfGrowthStatusFilter == 'declining',
                          onSelected: (_) => setState(() => _perfGrowthStatusFilter = 'declining'),
                        ),
                        if (newBranchesCount > 0)
                          ChoiceChip(
                            avatar: const Icon(AppIcons.newItem, size: 18.0),
                  label: Text('فروع جديدة ($newBranchesCount)'),
                            selected: _perfGrowthStatusFilter == 'new_branch',
                            onSelected: (_) => setState(() => _perfGrowthStatusFilter = 'new_branch'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 4 Single-Row Summary Strips inside the Growth Matrix
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final tone1 = colorScheme.primary;
                    final tone2 = Color.lerp(colorScheme.primary, colorScheme.secondary, 0.30) ?? colorScheme.primary;
                    final tone3 = Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.45) ?? colorScheme.primary;
                    final tone4 = Color.lerp(colorScheme.primary, colorScheme.outline, 0.35) ?? colorScheme.primary;

                    final isPosTotal = totalMatrixVarianceEgp >= 0;
                    final totalYoYBadge = totalMatrixYoYPct != null
                        ? '${CurrencyFormatter.formatSignedPct(totalMatrixYoYPct)} (${CurrencyFormatter.formatCompactEGP(totalMatrixVarianceEgp)})'
                        : CurrencyFormatter.formatCompactEGP(totalCurrMatrixRev);

                    final stripCards = [
                      _buildBranchInsightBadge(
                        context,
                        label: 'نمو السلسلة ($currYearLabel مقابل $compYear)',
                        branchName: totalYoYBadge,
                        valueText: CurrencyFormatter.formatCompactEGP(totalCurrMatrixRev),
                        color: tone1,
                        icon: isPosTotal ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        isHighlighted: true,
                      ),
                      _buildBranchInsightBadge(
                        context,
                        label: 'أسرع فرع نمواً',
                        branchName: fastestGrowingBranch != null ? _displayStore(fastestGrowingBranch.storeName) : '—',
                        valueText: fastestGrowingBranch != null
                            ? CurrencyFormatter.formatSignedPct(fastestGrowingBranch.yoyGrowthPct ?? 0)
                            : '—',
                        color: tone2,
                        icon: Icons.rocket_launch_rounded,
                      ),
                      _buildBranchInsightBadge(
                        context,
                        label: 'الفروع الصاعدة',
                        branchName: '$growingBranchesCount فرع صاعد',
                        valueText: 'من ${branchGrowthMatrix.length}',
                        color: tone3,
                        icon: Icons.auto_graph_rounded,
                      ),
                      _buildBranchInsightBadge(
                        context,
                        label: 'تحتاج تنشيط',
                        branchName: '$decliningBranchesCount فرع',
                        valueText: 'مقارنة بـ $compYear',
                        color: tone4,
                        icon: Icons.campaign_rounded,
                      ),
                    ];

                    if (box.maxWidth >= 900) {
                      return IntrinsicHeight(
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: stripCards[0]),
                          const SizedBox(width: 8.0),
                          Expanded(child: stripCards[1]),
                          const SizedBox(width: 8.0),
                          Expanded(child: stripCards[2]),
                          const SizedBox(width: 8.0),
                          Expanded(child: stripCards[3]),
                        ],
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: stripCards
                          .map((c) => SizedBox(width: (box.maxWidth - 8.0) / 2, child: c))
                          .toList(),
                    );
                  },
                ),
              ),

              // Matrix DataTable: centred headings + flex shares fill the full width;
              // rank and branch/region live in ONE grouped first column.
              TableScrollContainer(
                key: const ValueKey('branch_growth_table'),
                controller: _skuPerfTableScrollController,
                showSwipeHint: false,
                padding: const EdgeInsets.all(12.0),
                columnFlex: _branchGrowthFlex,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  columnSpacing: M3Spacing.xs,
                  horizontalMargin: M3Spacing.xs,
                  columns: [
                    const DataColumn(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: _branchRankWidth,
                            child: Text('#', textAlign: TextAlign.center),
                          ),
                          SizedBox(width: M3Spacing.xs),
                          Text('الفرع والمنطقة'),
                        ],
                      ),
                    ),
                    DataColumn(
                      label: Text('مبيعات $currYearLabel (ج.م)', textAlign: TextAlign.center),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                    DataColumn(
                      label: Text('مبيعات $compYear (ج.م)', textAlign: TextAlign.center),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                    const DataColumn(
                      label: Text('الفرق', textAlign: TextAlign.center),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                    const DataColumn(
                      label: Text('النمو السنوي %', textAlign: TextAlign.center),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                    DataColumn(
                      label: Text(
                        _selectedMonth > 0 ? 'مبيعات الشهر الحالي' : 'المتوسط الشهري',
                        textAlign: TextAlign.center,
                      ),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                    const DataColumn(
                      label: Text('الحالة', textAlign: TextAlign.center),
                      headingRowAlignment: MainAxisAlignment.center,
                    ),
                  ],
                  rows: filteredGrowthBranches.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final item = entry.value;
                    final isPositive = item.varianceEgp >= 0;
                    final yoyPct = item.yoyGrowthPct;
                    final monthlyRunRate = _selectedMonth > 0
                        ? item.fullPeriodRevenue
                        : item.fullPeriodRevenue / 12.0;

                    Color statusBg;
                    Color statusFg;
                    String statusLabel;
                    IconData statusIcon;

                    if (item.status == 'new_branch') {
                      statusBg = colorScheme.surfaceContainerHigh;
                      statusFg = colorScheme.onSurfaceVariant;
                      statusLabel = 'فرع جديد';
                      statusIcon = AppIcons.newItem;
                    } else if (item.status == 'growing') {
                      statusBg = colorScheme.primaryContainer.withOpacity(0.75);
                      statusFg = colorScheme.onPrimaryContainer;
                      statusLabel = (yoyPct ?? 0) >= 15.0 ? 'نمو قوي' : 'نمو';
                      statusIcon = AppIcons.trendingUp;
                    } else {
                      statusBg = colorScheme.errorContainer.withOpacity(0.65);
                      statusFg = colorScheme.onErrorContainer;
                      statusLabel = 'متراجع';
                      statusIcon = AppIcons.trendingDown;
                    }

                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                key: ValueKey('branch_growth_rank_${item.storeId}'),
                                width: _branchRankWidth,
                                child: Text(
                                  '$rank',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: M3Spacing.xs),
                              Flexible(
                                child: Column(
                                  key: ValueKey('branch_growth_name_${item.storeId}'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _displayStore(item.storeName),
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodyMedium)),
                                    ),
                                    Text(
                                      '${item.chain.toUpperCase()} • ${item.region}',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            item.currentRevenue > 0 ? CurrencyFormatter.formatEGP(item.currentRevenue) : '—',
                            key: ValueKey('branch_growth_cur_${item.storeId}'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            item.hasPrevYear ? CurrencyFormatter.formatEGP(item.prevRevenue) : '—',
                            key: ValueKey('branch_growth_prev_${item.storeId}'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${isPositive ? "+" : ""}${CurrencyFormatter.formatCompactEGP(item.varianceEgp)}',
                            key: ValueKey('branch_growth_diff_${item.storeId}'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isPositive ? colorScheme.primary : colorScheme.error,
                            ),
                          ),
                        ),
                        DataCell(
                          yoyPct != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      yoyPct >= 0
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      size: 18.0,
                                      color: yoyPct >= 0 ? colorScheme.primary : colorScheme.error,
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      CurrencyFormatter.formatSignedPct(yoyPct),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: yoyPct >= 0 ? colorScheme.primary : colorScheme.error,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'جديد ($currYearLabel)',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                ),
                        ),
                        DataCell(
                          Text(
                            CurrencyFormatter.formatCompactEGP(monthlyRunRate),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        DataCell(
                          M3ChipSurface(
                            color: statusBg,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 18.0, color: statusFg),
                                const SizedBox(width: 4.0),
                                Text(
                                  statusLabel,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: statusFg),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: UPLOADED SELL-OUT EXCEL SHEETS ARCHIVE (CUMULATIVE UPLOAD / REPLACE / DELETE)
  // ===========================================================================
  Widget _buildUploadedSellOutSheetsTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Cumulative Upload Banner & Chain/Year/Month Controls
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_upload_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const M3SectionTitle('ملفات Sell-Out المرفوعة'),
                        const SizedBox(height: 4.0),
                        Text(
                          'ارفع ملف كل شهر، ويمكنك استبداله أو تنزيله أو حذفه.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 10.0,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 8.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      M3Dropdown<String>(
value: _archiveUploadChain,
fitOptions: true,
label: 'السلسلة',
options: m3OptionsFromMenuItems<String>([
                            const DropdownMenuItem(value: 'fathalla', child: Text('Fathalla Market')),
                            const DropdownMenuItem(value: 'gomla', child: Text('Gomla Market')),
                            const DropdownMenuItem(value: 'beet-elgomla', child: Text('Beet El Gomla')),
                            const DropdownMenuItem(value: 'chain-1080314', child: Text('El Wakala')),
                          ]),
onChanged: m3Legacy<String>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadChain = v);
                            }
                          }),
),
                      M3Dropdown<int>(
value: _archiveUploadYear,
fitOptions: true,
label: 'السنة (اختياري)',
options: m3OptionsFromMenuItems<int>([
                            const DropdownMenuItem(value: 0, child: Text('من الملف تلقائيًا')),
                            for (final y in _recentYears) DropdownMenuItem(value: y, child: Text('$y')),
                          ]),
onChanged: m3Legacy<int>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadYear = v);
                            }
                          }),
),
                      M3Dropdown<int>(
value: _archiveUploadMonth,
fitOptions: true,
label: 'الشهر (اختياري)',
options: m3OptionsFromMenuItems<int>([
                            const DropdownMenuItem(value: 0, child: Text('من الملف تلقائيًا')),
                            const DropdownMenuItem(value: 1, child: Text('يناير')),
                            const DropdownMenuItem(value: 2, child: Text('فبراير')),
                            const DropdownMenuItem(value: 3, child: Text('مارس')),
                            const DropdownMenuItem(value: 4, child: Text('أبريل')),
                            const DropdownMenuItem(value: 5, child: Text('مايو')),
                            const DropdownMenuItem(value: 6, child: Text('يونيو')),
                            const DropdownMenuItem(value: 7, child: Text('يوليو')),
                            const DropdownMenuItem(value: 8, child: Text('أغسطس')),
                            const DropdownMenuItem(value: 9, child: Text('سبتمبر')),
                            const DropdownMenuItem(value: 10, child: Text('أكتوبر')),
                            const DropdownMenuItem(value: 11, child: Text('نوفمبر')),
                            const DropdownMenuItem(value: 12, child: Text('ديسمبر')),
                          ]),
onChanged: m3Legacy<int>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadMonth = v);
                            }
                          }),
),
                    ],
                  ),
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 8.0,
                    children: [
                      TestSemantics.button(
                        identifier: TestIds.selloutUploadButton,
                        label: 'رفع ملف Sell-Out',
                        onPressed: _isUploading
                            ? null
                            : () => _pickAndUploadSellOutFile(
                                  forceChain: _archiveUploadChain,
                                  forceYear: _archiveUploadYear > 0
                                      ? _archiveUploadYear
                                      : null,
                                  forceMonth: _archiveUploadMonth > 0
                                      ? _archiveUploadMonth
                                      : null,
                                ),
                        child: FilledButton.icon(
                          onPressed: _isUploading
                              ? null
                              : () => _pickAndUploadSellOutFile(
                                    forceChain: _archiveUploadChain,
                                    forceYear: _archiveUploadYear > 0 ? _archiveUploadYear : null,
                                    forceMonth: _archiveUploadMonth > 0 ? _archiveUploadMonth : null,
                                  ),
                          icon: _isUploading && _replacingFileId == null
                              ? const SizedBox(
                                  width: 18.0,
                                  height: 18.0,
                                  child: CircularProgressIndicator(strokeWidth: 2.0),
                                )
                              : const Icon(Icons.upload_file_rounded, size: 20.0),
                          label: const Text('رفع ملف Sell-Out'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoadingArchive ? null : () => _loadSellOutArchive(forceRefresh: true),
                        icon: const Icon(Icons.refresh_rounded, size: 18.0),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 2. Uploaded Sell-Out Sheets Table
        TestSemantics(
          identifier: TestIds.uploadedFilesList,
          label: 'الملفات المرفوعة (${_archivedSellOutFiles.length})',
          container: true,
          child: Container(
            key: const ValueKey('uploaded_files_section'),
            decoration: BoxDecoration(
              color: M3TableSurface.color(colorScheme),
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: _isLoadingArchive
                ? const Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _archiveLoadFailed && _archivedSellOutFiles.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: M3ErrorState(
                          key: const ValueKey('sell_out_archive_load_error'),
                          title: 'تعذّر تحميل الملفات المرفوعة',
                          message: 'الخادم مشغول أو الاتصال انقطع. حاول مرة أخرى بعد لحظات.',
                          onRetry: () => _loadSellOutArchive(forceRefresh: true),
                        ),
                      )
                : _archivedSellOutFiles.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(48.0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_off_rounded,
                                size: 48.0,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12.0),
                              Text(
                                'لا توجد ملفات مرفوعة بعد.',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6.0),
                              Text(
                                'ارفع أول ملف لتبدأ.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : TableScrollContainer(
                        controller: _archiveSheetsScrollController,
                        showSwipeHint: true,
                        // File name is the widest column.
                        columnFlex: const [1.3, 0.95, 0.85, 0.85, 0.95, 0.95, 1.2],
                        // Actions pinned at the row end so they stay on
                        // screen without horizontal scrolling.
                        pinnedEnd: _buildArchiveActionsColumn(context),
                        child: DataTable(
                          key: const ValueKey('uploaded_files_table'),
                          // Compact spacing so the actions column is on
                          // screen at 1280dp without horizontal scrolling.
                          columnSpacing: M3Spacing.sm,
                          horizontalMargin: M3Spacing.sm,
                          headingRowHeight: _archiveHeadingHeight,
                          dataRowMinHeight: _archiveRowHeight,
                          dataRowMaxHeight: _archiveRowHeight,
                          headingRowColor: WidgetStatePropertyAll(
                            colorScheme.surfaceContainerHigh.withOpacity(0.5),
                          ),
                          columns: [
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الملف')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('السلسلة')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الفترة')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('المعاملات'), numeric: true),
                            DataColumn(headingRowAlignment: MainAxisAlignment.center, label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 64.0), child: const Text('الوحدات المباعة', maxLines: 2, softWrap: true, textAlign: TextAlign.center)), numeric: true),
                            DataColumn(headingRowAlignment: MainAxisAlignment.center, label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 64.0), child: const Text('صافي Sell-Out (ج.م)', maxLines: 2, softWrap: true, textAlign: TextAlign.center)), numeric: true),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('تاريخ الرفع')),
                          ],
                          rows: _archivedSellOutFiles.map((file) {
                            final periodText = file.targetMonth.isNotEmpty && file.targetMonth != 'auto'
                                ? '${file.targetMonth} / ${file.targetYear}'
                                : 'سنة ${file.targetYear}';

                            return DataRow(
                              cells: [
                                DataCell(
                                  TestSemantics(
                                    identifier: TestIds.fileRow(
                                      archiveId: file.id,
                                      fileName: file.fileName,
                                    ),
                                    label: file.fileName,
                                    container: true,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.description_rounded,
                                          color: M3StatusColors.of(context).accents.positive,
                                          size: 20.0,
                                        ),
                                        const SizedBox(width: 8.0),
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Tooltip(
                                              message: file.fileName,
                                              child: Text(
                                                sheetShortName(file.fileName),
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            Text(
                                              _formatFileSize(file.fileSizeBytes),
                                              style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                             fontSize: M3FontSize.labelSmall,                                             color: colorScheme.onSurfaceVariant,                                           )),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  M3ChipSurface(
                              color: colorScheme.surfaceContainerHigh,
                              child: Text(
                                      file.retailChain.toUpperCase(),
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    periodText,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    CurrencyFormatter.formatNumber(file.rowsIngested),
                                    key: ValueKey('file_rows_${file.id}'),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                DataCell(
                                  // Units sold (total_units), not the row count.
                                  Text(
                                    file.totalUnits == null
                                        ? '—'
                                        : CurrencyFormatter.formatNumber(file.totalUnits!.round()),
                                    key: ValueKey('file_units_${file.id}'),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    CurrencyFormatter.formatEGP(file.totalRevenue),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Tooltip(
                                    message: () {
                                      final uploaded = AppDateFormat.tryFormat(file.uploadedAt);
                                      if (file.lastIngestedAt.isEmpty ||
                                          file.lastIngestedAt == file.uploadedAt) {
                                        return uploaded;
                                      }
                                      return '$uploaded • آخر استيراد: ${AppDateFormat.tryFormat(file.lastIngestedAt)}';
                                    }(),
                                    child: Text(
                                      AppDateFormat.tryFormat(file.uploadedAt, withTime: false),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.visible,
                                      style: M3TextVariants.cell.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),

                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  static const double _archiveHeadingHeight = 48.0;
  static const double _archiveRowHeight = 72.0;

  Widget _buildArchiveActionsColumn(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final divider = Divider.createBorderSide(context, width: 1.0);
    return IntrinsicWidth(
      key: const ValueKey('uploaded_files_actions_column'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _archiveHeadingHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
              color: colorScheme.surfaceContainerHigh.withOpacity(0.5),
              child: Text('الإجراءات', style: theme.dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall),
            ),
            for (final file in _archivedSellOutFiles)
              Container(
                height: _archiveRowHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                decoration: BoxDecoration(border: Border(top: divider)),
                child: Builder(builder: (context) {
                  final isDeleting = _deletingFileId == file.id;
                  final isReplacing = _replacingFileId == file.id;
                  return ArchiveActionsGroup(
                                    archiveId: file.id,
                                    fileName: file.fileName,
                                    isEditing: isReplacing,
                                    isDeleting: isDeleting,
                                    onEdit: (isDeleting || isReplacing || _isUploading)
                                        ? null
                                        : () => _pickAndUploadSellOutFile(
                                              replaceArchiveId: file.id,
                                              forceChain: file.retailChain,
                                            ),
                                    onDownload: () => _handleDownloadSellOutSheet(file),
                                    onDelete: (isDeleting || isReplacing || _isUploading)
                                        ? null
                                        : () => _confirmAndDeleteSellOutSheet(file),
                                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RESPONSIVE LAYOUT HELPERS (SYMMETRICAL WITH SELL-IN)
  // ===========================================================================
  Widget _buildFourCardResponsiveLayout(
    double maxWidth,
    Widget card1,
    Widget card2,
    Widget card3,
    Widget card4,
  ) {
    // Same equal-height grid and 16dp gutters as the dashboard KPI row.
    final columns = M3KpiGridColumns.forWidth(maxWidth);
    return M3EqualHeightGrid(
      key: const ValueKey('kpi_cards_row'),
      columns: columns,
      spacing: M3Spacing.sm,
      runSpacing: M3Spacing.sm,
      children: [card1, card2, card3, card4],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool textValue = false,
    bool singleLineValue = false,
    Key? subtitleKey,
  }) {
    // Shared reference KPI card (Sell-Out is the reference; Compare mirrors it).
    // Arabic-only title; [titleEn] is kept as the stable key id.
    return M3SummaryKpiCard(
      key: ValueKey('kpi_card_$titleEn'),
      valueKey: ValueKey('kpi_value_$titleEn'),
      subtitleKey: subtitleKey,
      title: titleAr,
      value: value,
      subtitle: subtitle,
      icon: icon,
      color: color,
      textValue: textValue,
      valueMaxLines: singleLineValue ? 1 : 2,
      shrinkOverflowingValue: singleLineValue,
    );
  }
}

/// Placeholder for the branch-performance search. Lighter than entered text
/// (onSurfaceVariant at 70%, same treatment as the Sell-In search hint).
TextStyle? _perfSearchHintStyle(ThemeData theme, ColorScheme colorScheme) {
  return theme.textTheme.bodyLarge?.copyWith(
    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    fontWeight: FontWeight.w400,
  );
}

/// Header and cell share one centre axis. [TableScrollContainer] centres the
/// cells of every column whose heading uses [MainAxisAlignment.center] and
/// stretches the table to the full width.
DataColumn _centeredColumn(String label, {bool numeric = false}) {
  return DataColumn(
    numeric: numeric,
    headingRowAlignment: MainAxisAlignment.center,
    label: Text(label, textAlign: TextAlign.center),
  );
}
