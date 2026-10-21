import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../widgets/cascading_filter_toolbar.dart';
import '../widgets/target_management_panel.dart';
import '../widgets/virtualized_sku_table.dart';

/// SellOutExplorerScreen provides comprehensive retailer Sell-Out analytics:
/// - Tab 0: Sell-Out Data & Operations (Transactions Table, 4 KPI cards, Upload & Export Actions)
/// - Tab 1: Performance & Branch Analytics (Pareto 80/20 Analysis, Brand & Branch Velocity Breakdown)
/// - Tab 2: Target Management (Sell-Out) (Monthly Targets, Actual vs Target Gap & Tracking)
/// - Tab 3: Uploaded Sheets (Sell-Out Cumulative Excel Sheets Archive: Replace, Download, Delete)
class SellOutExplorerScreen extends StatefulWidget {
  final ApiClient apiClient;

  const SellOutExplorerScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<SellOutExplorerScreen> createState() => _SellOutExplorerScreenState();
}

class _SellOutExplorerScreenState extends State<SellOutExplorerScreen> {
  // Active Tab Index
  // 0: Sell-Out Data & Operations
  // 1: Performance & Branch Analytics
  // 2: Target Management (Sell-Out)
  // 3: Uploaded Sheets (Archive)
  int _activeTab = 0;

  // Tab 0 Filter & Transaction State
  String? selectedChain;
  String? selectedStoreId;
  String? selectedCategory;
  DateTimeRange? selectedDateRange;
  String searchQuery = '';
  bool isLoading = true;
  bool _isUploading = false;
  String? _replacingFileId;
  List<SellOutRecordModel> records = [];
  List<String> _availableCategories = [];
  Map<String, List<Map<String, String>>> _chainStores = {};

  // Tab 1: Performance & Branch Analytics State
  String _perfChain = 'all';
  String _perfBrand = 'all';
  String _perfSearch = '';
  int _perfSortColumnIndex = 3; // 3: Net Revenue (EGP)
  bool _perfSortAscending = false; // Descending by default for highest value
  int _perfCurrentPage = 0;
  final int _perfPageSize = 25; // 25 items per page
  late final TextEditingController _perfSearchController;

  // Tab 3: Uploaded Sell-Out Excel Sheets Archive State
  bool _isLoadingArchive = false;
  List<ArchivedExcelFileModel> _archivedSellOutFiles = const [];
  String _archiveUploadChain = 'fathalla';
  int _archiveUploadYear = 0; // 0 = Auto-detect from sheet
  int _archiveUploadMonth = 0; // 0 = Auto-detect from sheet
  String? _deletingFileId;

  late String _lastTenantId;

  // Scroll Controllers for Responsive Data Tables
  late final ScrollController _branchTableScrollController;
  late final ScrollController _skuPerfTableScrollController;
  late final ScrollController _archiveSheetsScrollController;

  @override
  void initState() {
    super.initState();
    _perfSearchController = TextEditingController();
    _branchTableScrollController = ScrollController();
    _skuPerfTableScrollController = ScrollController();
    _archiveSheetsScrollController = ScrollController();
    _lastTenantId = widget.apiClient.tenantId;
    _loadAllData();
  }

  @override
  void dispose() {
    _perfSearchController.dispose();
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
      selectedChain = null;
      selectedStoreId = null;
      selectedCategory = null;
      selectedDateRange = null;
      searchQuery = '';
      _availableCategories = [];
      _chainStores = {};
      _loadAllData();
    }
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadRecords(),
      _loadSellOutArchive(),
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
    if (mounted) setState(() => isLoading = true);
    final res = await widget.apiClient.getRecords(
      chain: selectedChain,
      storeId: selectedStoreId,
      category: selectedCategory,
      query: searchQuery,
      startDate: selectedDateRange != null ? _formatDate(selectedDateRange!.start) : null,
      endDate: selectedDateRange != null ? _formatDate(selectedDateRange!.end) : null,
      limit: 250,
    );
    final dynamicStores = await widget.apiClient.getStores();
    if (mounted) {
      setState(() {
        records = res;
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
      });
    }
  }

  Future<void> _loadSellOutArchive() async {
    if (mounted) setState(() => _isLoadingArchive = true);
    try {
      final res = await widget.apiClient.getUploadedFilesArchive(
        fileType: 'sell_out',
      );
      if (mounted) {
        setState(() {
          _archivedSellOutFiles = res.files;
          _isLoadingArchive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingArchive = false);
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
        'غير مصرح: دور المشرف الميداني مقيد ولا يملك صلاحية رفع الملفات (RBAC)',
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

      if (replaceArchiveId != null) {
        await widget.apiClient.deleteArchivedFile(replaceArchiveId, isSellIn: false);
      }

      final res = await widget.apiClient.uploadFile(
        picked.name,
        picked.bytes,
        targetChain: targetChain,
        periodDate: periodDate,
        dryRun: false,
      );

      if (res.isStaged && !res.isCommitted) {
        await widget.apiClient.commitStagedUpload(
          batchId: res.batchId,
          targetChain: targetChain,
          periodDate: periodDate,
        );
      }

      if (!mounted) return;
      final actionLabel = replaceArchiveId != null
          ? 'تم استبدال وتحديث شيت الـ Sell-Out بنجاح'
          : 'تم رفع ودمج شيت الـ Sell-Out تراكمياً بنجاح';
      M3Feedback.showSuccess(
        context,
        '$actionLabel (${picked.name}): ${res.validRows} حركة مبيعات بإجمالي ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)}',
      );
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر رفع ملف الـ Sell-Out: $e');
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
        'تم بدء تحميل شيت الـ Sell-Out الأصلي: ${file.fileName}',
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر تحميل الشيت المؤرشف: $e');
    }
  }

  Future<void> _confirmAndDeleteSellOutSheet(ArchivedExcelFileModel file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: cs.error, size: 26.0),
              const SizedBox(width: 10.0),
              const Expanded(
                child: Text(
                  'تأكيد حذف شيت الـ Sell-Out',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('هل أنت متأكد من حذف شيت الإكسيل التالي من بيانات مبيعات الـ Sell-Out؟'),
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'السلسلة: ${file.retailChain.toUpperCase()} • الحركات: ${file.rowsIngested} • القيمة: ${CurrencyFormatter.formatCompactEGP(file.totalRevenue)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                'ملاحظة: سيتم حذف حركات هذا الشيت فقط وإعادة احتساب صافي المبيعات والكميات تلقائياً دون المساس ببقية الشهور المرفوعة أو بيانات التوريد (Sell-In).',
                style: TextStyle(fontSize: 12.0, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18.0),
              label: const Text('حذف الشيت نهائياً (Delete)'),
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
        'تم حذف شيت (${file.fileName}) وتحديث حركات الـ Sell-Out بنجاح',
      );
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'خطأ أثناء حذف الشيت: $e');
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
        'غير مصرح: دور المشرف الميداني لا يملك صلاحية تصدير التقارير المالية (RBAC)',
      );
      return;
    }

    final headers = [
      'الباركود الدولي',
      'اسم الصنف',
      'السلسلة',
      'الفرع',
      'الفئة',
      'الكمية المباعة',
      'سعر الوحدة',
      'صافي المبيعات (ج.م)',
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
      details: 'تصدير ${records.length} صف مبيعات إلى ملف Excel/CSV',
    );

    M3Feedback.showSuccess(
      context,
      'تم تصدير ${records.length} صف إلى ملف Excel/CSV بنجاح',
    );
  }

  void _handleExportPdf() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'غير مصرح: دور المشرف الميداني لا يملك صلاحية تصدير التقارير المالية (RBAC)',
      );
      return;
    }

    final headers = [
      'الباركود الدولي',
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
      title: 'تقرير حركة مبيعات التجزئة (Sell-Out Analytics)',
      headers: headers,
      rows: rows,
      metadata: {
        'الشركة': companyName,
        'إجمالي صافي المبيعات': CurrencyFormatter.formatEGP(totalNet),
        'إجمالي الكمية المباعة': '${CurrencyFormatter.formatNumber(totalUnits)} قطعة',
        'إجمالي الصفوف': '${records.length}',
        'تاريخ التصدير': DateTime.now().toString().split(' ')[0],
      },
    );

    final filename = 'tashil_sellout_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);

    widget.apiClient.recordAuditLog(
      action: 'EXPORT_PDF',
      resource: filename,
      details: 'تصدير ${records.length} صف مبيعات إلى تقرير PDF/HTML للطباعة',
    );

    M3Feedback.showSuccess(
      context,
      'تم إعداد تقرير الطباعة و PDF بنجاح (${records.length} صف)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Screen Header: Unified M3 Left English Title + Right Arabic Subtitle
            const M3PageHeader(
              titleEn: 'Sell-Out Analytics, Branch Performance & Sheets Archive',
              subtitleAr:
                  'منظومة مبيعات التجزئة (Sell-Out)، تحليلات باريتو وأداء الفروع، المستهدفات، وإدارة الشيتات المرفوعة تراكمياً',
            ),

            M3Spacing.gapSM,

            // Top Tab Switcher: 100% Responsive Full-Width MD3 Large Tab Bar (4 Symmetrical Tabs)
            M3ResponsiveTabBar<int>(
              textDirection: TextDirection.ltr,
              selectedValue: _activeTab,
              items: [
                const M3ResponsiveTabItem<int>(
                  value: 0,
                  icon: Icons.point_of_sale_outlined,
                  selectedIcon: Icons.point_of_sale_rounded,
                  label: 'Sell-Out Data & Operations',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 1,
                  icon: Icons.insights_outlined,
                  selectedIcon: Icons.insights_rounded,
                  label: 'Performance & Branch Analytics',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 2,
                  icon: Icons.track_changes_outlined,
                  selectedIcon: Icons.track_changes_rounded,
                  label: 'Target Management (Sell-Out)',
                ),
                M3ResponsiveTabItem<int>(
                  value: 3,
                  icon: Icons.folder_copy_outlined,
                  selectedIcon: Icons.folder_copy_rounded,
                  label: 'Uploaded Sheets (${_archivedSellOutFiles.length})',
                ),
              ],
              onChanged: (next) {
                setState(() => _activeTab = next);
                if (next == 3) {
                  _loadSellOutArchive();
                }
              },
            ),

            M3Spacing.gapMD,

            if (_activeTab == 2)
              TargetManagementPanel(
                key: ValueKey('sell_out_targets_${widget.apiClient.tenantId}'),
                apiClient: widget.apiClient,
                targetType: 'sell_out',
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

    // Compute Executive KPIs dynamically from active records
    final double totalNetRevenue = records.fold<double>(0.0, (acc, r) => acc + r.netRevenue);
    final double totalUnitsSold = records.fold<double>(0.0, (acc, r) => acc + r.quantitySold.toDouble());
    final double avgUnitPrice = totalUnitsSold > 0 ? (totalNetRevenue / totalUnitsSold) : 0.0;
    final int activeStoresCount = records.map((r) => r.storeId.isNotEmpty ? r.storeId : r.storeName).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Four Symmetrical Executive KPI Cards (Full Width Alignment)
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي صافي المبيعات',
              titleEn: 'Total Net Revenue (EGP)',
              value: CurrencyFormatter.formatCompactEGP(totalNetRevenue),
              subtitle: '${records.length} حركة مبيعات مسجلة (${_archivedSellOutFiles.length} شيت مرفوع)',
              icon: Icons.payments_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الكمية المباعة',
              titleEn: 'Total Units Sold',
              value: CurrencyFormatter.formatNumber(totalUnitsSold.round()),
              subtitle: 'قطعة / وحدة مباعة للمستهلك',
              icon: Icons.shopping_bag_rounded,
              color: Colors.teal.shade700,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'متوسط سعر الوحدة',
              titleEn: 'Average Unit Price (EGP)',
              value: CurrencyFormatter.formatEGP(avgUnitPrice),
              subtitle: 'متوسط سعر الصنف بالجنيه',
              icon: Icons.price_check_rounded,
              color: Colors.indigo.shade700,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الفروع النشطة',
              titleEn: 'Active Stores & Outlets',
              value: '$activeStoresCount فرع',
              subtitle: 'موزعة على السلاسل التجارية',
              icon: Icons.storefront_rounded,
              color: Colors.orange.shade800,
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
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: colorScheme.error.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_person_rounded, color: colorScheme.error, size: 20.0),
                M3Spacing.hGapXS,
                Expanded(
                  child: Text(
                    'تنبيه الصلاحيات (RBAC): دور المشرف الميداني مقيد بالعمليات التشغيلية ولا يسمح بتصدير التقارير المالية',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          M3Spacing.gapSM,
        ],

        // 2. Cascading Filter Toolbar with integrated Upload, Export & Search
        CascadingFilterToolbar(
          key: ValueKey('toolbar_${widget.apiClient.tenantId}'),
          selectedChain: selectedChain,
          selectedStoreId: selectedStoreId,
          selectedCategory: selectedCategory,
          selectedDateRange: selectedDateRange,
          searchQuery: searchQuery,
          availableCategories: _availableCategories,
          chainStoresOverride: _chainStores,
          onChainChanged: (val) {
            setState(() => selectedChain = val);
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
          onSearchChanged: (val) {
            searchQuery = val;
            _loadRecords();
          },
          onUpload: () => _pickAndUploadSellOutFile(),
          isUploading: _isUploading,
          onExportExcel: _handleExportExcel,
          onExportPdf: _handleExportPdf,
        ),

        M3Spacing.gapMD,

        // 3. Virtualized SKU Table
        VirtualizedSkuTable(
          records: records,
          isLoading: isLoading,
        ),
      ],
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

    // 1. Group records by Branch
    final branchMap = <String, ({String storeName, String chain, int units, double revenue})>{};
    for (final r in effectiveRecords) {
      final key = '${r.retailerChain}_${r.storeId.isNotEmpty ? r.storeId : r.storeName}';
      final existing = branchMap[key];
      if (existing == null) {
        branchMap[key] = (
          storeName: r.storeName.isNotEmpty ? r.storeName : r.storeId,
          chain: r.retailerChain,
          units: r.quantitySold,
          revenue: r.netRevenue,
        );
      } else {
        branchMap[key] = (
          storeName: existing.storeName,
          chain: existing.chain,
          units: existing.units + r.quantitySold,
          revenue: existing.revenue + r.netRevenue,
        );
      }
    }
    final branchList = branchMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // 2. Group records by SKU & infer Brand
    final skuMap = <String, ({String skuName, String brand, String category, int units, double revenue})>{};
    for (final r in effectiveRecords) {
      final key = r.barcode.isNotEmpty ? r.barcode : r.skuName;
      final inferredBrand = SmartBrandExtractor.inferBrand(r.skuName, subCategory: r.category);
      final existing = skuMap[key];
      if (existing == null) {
        skuMap[key] = (
          skuName: r.skuName,
          brand: inferredBrand,
          category: r.category,
          units: r.quantitySold,
          revenue: r.netRevenue,
        );
      } else {
        skuMap[key] = (
          skuName: existing.skuName,
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
    final avgBranchRevenue = branchList.isNotEmpty ? (totalRevenueAll / branchList.length) : 0.0;

    // Filter SKUs for display table
    final availableBrands = skuMap.values.map((s) => s.brand).toSet().toList()..sort();
    final filteredSkus = sortedByRev.where((sku) {
      if (_perfBrand != 'all' && sku.brand != _perfBrand) return false;
      if (_perfSearch.isNotEmpty) {
        final q = _perfSearch.toLowerCase();
        if (!sku.skuName.toLowerCase().contains(q) &&
            !sku.brand.toLowerCase().contains(q) &&
            !sku.category.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sort filtered SKUs
    filteredSkus.sort((a, b) {
      int cmp = 0;
      switch (_perfSortColumnIndex) {
        case 0:
          cmp = a.skuName.compareTo(b.skuName);
          break;
        case 1:
          cmp = a.brand.compareTo(b.brand);
          break;
        case 2:
          cmp = a.units.compareTo(b.units);
          break;
        case 3:
        default:
          cmp = a.revenue.compareTo(b.revenue);
          break;
      }
      return _perfSortAscending ? cmp : -cmp;
    });

    // Pagination for SKU table
    final totalSkuPages = (filteredSkus.length / _perfPageSize).ceil().clamp(1, 9999);
    final pageIndex = _perfCurrentPage.clamp(0, totalSkuPages - 1);
    final startOffset = pageIndex * _perfPageSize;
    final pagedSkus = filteredSkus.skip(startOffset).take(_perfPageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Executive Performance KPI Summary Cards (4 Cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'أعلى صنف مبيعاً',
              titleEn: 'Top Performing SKU',
              value: topSku != null ? topSku.skuName : '—',
              subtitle: topSku != null
                  ? '${CurrencyFormatter.formatCompactEGP(topSku.revenue)} (${topSku.units} قطعة)'
                  : 'لا توجد مبيعات',
              icon: Icons.star_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'مؤشر باريتو (Pareto 80/20)',
              titleEn: 'Top 20% SKU Revenue Share',
              value: '${paretoSharePct.toStringAsFixed(1)}%',
              subtitle: '$top20PctCount صنف تمثل القوة الدافعة للمبيعات',
              icon: Icons.pie_chart_rounded,
              color: Colors.teal.shade700,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'أعلى فرع مبيعاً',
              titleEn: 'Top Revenue Branch',
              value: topBranch != null ? topBranch.storeName : '—',
              subtitle: topBranch != null
                  ? '${topBranch.chain.toUpperCase()} • ${CurrencyFormatter.formatCompactEGP(topBranch.revenue)}'
                  : 'لا توجد فروع',
              icon: Icons.leaderboard_rounded,
              color: Colors.indigo.shade700,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'متوسط مبيعات الفرع',
              titleEn: 'Average Store Velocity',
              value: CurrencyFormatter.formatCompactEGP(avgBranchRevenue),
              subtitle: '${branchList.length} فرع محقق مبيعات فعلية',
              icon: Icons.speed_rounded,
              color: Colors.deepOrange.shade800,
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
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
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
                  SizedBox(
                    width: 180.0,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _perfChain,
                      decoration: InputDecoration(
                        labelText: 'Chain',
                        isDense: true,
                        prefixIcon: const Icon(Icons.storefront_rounded, size: 18.0),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Chains')),
                        DropdownMenuItem(value: 'fathalla', child: Text('Fathalla')),
                        DropdownMenuItem(value: 'gomla', child: Text('Gomla')),
                        DropdownMenuItem(value: 'beet-elgomla', child: Text('Beet El Gomla')),
                        DropdownMenuItem(value: 'chain-1080314', child: Text('El Wakala')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _perfChain = v;
                            _perfCurrentPage = 0;
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220.0,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: availableBrands.contains(_perfBrand) ? _perfBrand : 'all',
                      decoration: InputDecoration(
                        labelText: 'Brand Filter (AI Inferred)',
                        isDense: true,
                        prefixIcon: const Icon(Icons.branding_watermark_rounded, size: 18.0),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Brands (الكل)')),
                        ...availableBrands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _perfBrand = v;
                            _perfCurrentPage = 0;
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 240.0,
                    child: TextField(
                      controller: _perfSearchController,
                      decoration: InputDecoration(
                        hintText: 'بحث باسم الصنف أو الماركة',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18.0),
                        suffixIcon: _perfSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16.0),
                                onPressed: () {
                                  _perfSearchController.clear();
                                  setState(() {
                                    _perfSearch = '';
                                    _perfCurrentPage = 0;
                                  });
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _perfSearch = val;
                          _perfCurrentPage = 0;
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
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    ),
                    onPressed: () {
                      final headers = ['الرتبة', 'اسم الصنف', 'العلامة التجارية', 'الفئة', 'الكمية المباعة', 'صافي المبيعات (ج.م)', 'نسبة المساهمة'];
                      final rows = filteredSkus.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final s = entry.value;
                        final share = totalRevenueAll > 0 ? (s.revenue / totalRevenueAll) * 100 : 0.0;
                        return [idx, s.skuName, s.brand, s.category, s.units, s.revenue, '${share.toStringAsFixed(1)}%'];
                      }).toList();
                      final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
                      final fn = 'tashil_pareto_performance_${DateTime.now().millisecondsSinceEpoch}.csv';
                      ExcelExportService.downloadCsv(fn, csv);
                      M3Feedback.showSuccess(context, 'تم تصدير تقرير تحليل أداء الأصناف بنجاح');
                    },
                    icon: const Icon(Icons.download_rounded, size: 18.0),
                    label: const Text('Export Excel'),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    ),
                    onPressed: () {
                      final headers = ['الفرع', 'السلسلة', 'القطع المباعة', 'صافي المبيعات (ج.م)', 'الحصة %'];
                      final rows = branchList.map((b) {
                        final share = totalRevenueAll > 0 ? (b.revenue / totalRevenueAll) * 100 : 0.0;
                        return [b.storeName, b.chain.toUpperCase(), b.units, CurrencyFormatter.formatEGP(b.revenue), '${share.toStringAsFixed(1)}%'];
                      }).toList();
                      final html = ExcelExportService.generatePrintableReport(
                        title: 'تقرير تحليل مبيعات الفروع ومعدلات التصريف (Branch Velocity)',
                        headers: headers,
                        rows: rows,
                        metadata: {
                          'إجمالي المبيعات': CurrencyFormatter.formatEGP(totalRevenueAll),
                          'عدد الفروع': '${branchList.length}',
                        },
                      );
                      final fn = 'tashil_branch_velocity_${DateTime.now().millisecondsSinceEpoch}.html';
                      ExcelExportService.downloadHtml(fn, html);
                      M3Feedback.showSuccess(context, 'تم إعداد تقرير طباعة أداء الفروع بنجاح');
                    },
                    icon: const Icon(Icons.print_rounded, size: 18.0),
                    label: const Text('Print PDF'),
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Section A: Top Branches Sales Velocity Table
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 22.0),
                    const SizedBox(width: 8.0),
                    Text(
                      'أداء الفروع ونقاط البيع (Branch Sales Velocity)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${branchList.length} فرع نشط',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                  columns: const [
                    DataColumn(label: Text('الترتيب')),
                    DataColumn(label: Text('اسم الفرع / نقطة البيع')),
                    DataColumn(label: Text('السلسلة التجارية')),
                    DataColumn(label: Text('الكمية المباعة'), numeric: true),
                    DataColumn(label: Text('صافي المبيعات (ج.م)'), numeric: true),
                    DataColumn(label: Text('حصة المبيعات %'), numeric: true),
                  ],
                  rows: branchList.take(15).toList().asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final b = entry.value;
                    final sharePct = totalRevenueAll > 0 ? (b.revenue / totalRevenueAll) * 100 : 0.0;
                    return DataRow(
                      cells: [
                        DataCell(
                          CircleAvatar(
                            radius: 12.0,
                            backgroundColor: idx <= 3
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            foregroundColor: idx <= 3
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                            child: Text('$idx', style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        DataCell(Text(b.storeName, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(999.0),
                            ),
                            child: Text(
                              b.chain.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSecondaryContainer,
                              ),
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
                                  borderRadius: BorderRadius.circular(4.0),
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

        // 4. Section B: SKU & Brand Pareto Analysis Table (With Pagination & Sorting)
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_rounded, color: colorScheme.primary, size: 22.0),
                    const SizedBox(width: 8.0),
                    Text(
                      'تحليل الأصناف ومساهمة الماركات (SKU Pareto Breakdown)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'صفحة ${pageIndex + 1} من $totalSkuPages (${filteredSkus.length} صنف)',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TableScrollContainer(
                controller: _skuPerfTableScrollController,
                showSwipeHint: true,
                padding: const EdgeInsets.all(12.0),
                child: DataTable(
                  sortColumnIndex: _perfSortColumnIndex,
                  sortAscending: _perfSortAscending,
                  headingRowColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  columns: [
                    DataColumn(
                      label: const Text('اسم الصنف (SKU Name)'),
                      onSort: (col, asc) {
                        setState(() {
                          _perfSortColumnIndex = col;
                          _perfSortAscending = asc;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('الماركة (Brand)'),
                      onSort: (col, asc) {
                        setState(() {
                          _perfSortColumnIndex = col;
                          _perfSortAscending = asc;
                        });
                      },
                    ),
                    const DataColumn(
                      label: Text('الفئة (Category)'),
                    ),
                    DataColumn(
                      label: const Text('القطع المباعة (Units)'),
                      numeric: true,
                      onSort: (col, asc) {
                        setState(() {
                          _perfSortColumnIndex = col;
                          _perfSortAscending = asc;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('صافي المبيعات (EGP)'),
                      numeric: true,
                      onSort: (col, asc) {
                        setState(() {
                          _perfSortColumnIndex = col;
                          _perfSortAscending = asc;
                        });
                      },
                    ),
                    const DataColumn(
                      label: Text('تصنيف باريتو (Pareto Class)'),
                    ),
                  ],
                  rows: pagedSkus.map((sku) {
                    final sharePct = totalRevenueAll > 0 ? (sku.revenue / totalRevenueAll) * 100 : 0.0;
                    final isClassA = sharePct >= 2.0;
                    final isClassB = sharePct >= 0.5 && sharePct < 2.0;
                    final tagLabel = isClassA ? 'Class A (قائد)' : (isClassB ? 'Class B (متوسط)' : 'Class C (عادي)');
                    final tagColor = isClassA
                        ? Colors.green.shade700
                        : (isClassB ? Colors.amber.shade800 : Colors.blueGrey.shade600);

                    return DataRow(
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240.0),
                            child: Text(
                              sku.skuName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(sku.brand, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(sku.category)),
                        DataCell(Text(CurrencyFormatter.formatNumber(sku.units))),
                        DataCell(
                          Text(
                            CurrencyFormatter.formatEGP(sku.revenue),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: tagColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: tagColor.withOpacity(0.3)),
                            ),
                            child: Text(
                              tagLabel,
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: tagColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

              // Pagination Controller Bar (25 items per page)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عرض ${startOffset + 1} - ${math.min(startOffset + _perfPageSize, filteredSkus.length)} من أصل ${filteredSkus.length} صنف',
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                    ),
                    Row(
                      children: [
                        IconButton.outlined(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: pageIndex > 0
                              ? () => setState(() => _perfCurrentPage = pageIndex - 1)
                              : null,
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          '${pageIndex + 1} / $totalSkuPages',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton.outlined(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: pageIndex < totalSkuPages - 1
                              ? () => setState(() => _perfCurrentPage = pageIndex + 1)
                              : null,
                        ),
                      ],
                    ),
                  ],
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
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      Icons.cloud_upload_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 24.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إدارة شيتات الإكسيل المرفوعة للـ Sell-Out (الرفع التراكمي شهر بشهر)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'يمكنك رفع شيت مبيعات السلاسل لكل شهر بشكل تراكمي، استبدال أي شيت سابق، تحميل الشيت الأصلي بصيغة Excel، أو حذفه لإعادة احتساب مؤشرات المبيعات بدقة.',
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
                      SizedBox(
                        width: 200.0,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _archiveUploadChain,
                          decoration: InputDecoration(
                            labelText: 'Target Chain',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'fathalla', child: Text('Fathalla Market')),
                            DropdownMenuItem(value: 'gomla', child: Text('Gomla Market')),
                            DropdownMenuItem(value: 'beet-elgomla', child: Text('Beet El Gomla')),
                            DropdownMenuItem(value: 'chain-1080314', child: Text('El Wakala')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadChain = v);
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 155.0,
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _archiveUploadYear,
                          decoration: InputDecoration(
                            labelText: 'Year (Optional)',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Auto from Sheet')),
                            DropdownMenuItem(value: 2026, child: Text('2026')),
                            DropdownMenuItem(value: 2025, child: Text('2025')),
                            DropdownMenuItem(value: 2024, child: Text('2024')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadYear = v);
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 175.0,
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _archiveUploadMonth,
                          decoration: InputDecoration(
                            labelText: 'Month (Optional)',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Auto from Sheet')),
                            DropdownMenuItem(value: 1, child: Text('January (01)')),
                            DropdownMenuItem(value: 2, child: Text('February (02)')),
                            DropdownMenuItem(value: 3, child: Text('March (03)')),
                            DropdownMenuItem(value: 4, child: Text('April (04)')),
                            DropdownMenuItem(value: 5, child: Text('May (05)')),
                            DropdownMenuItem(value: 6, child: Text('June (06)')),
                            DropdownMenuItem(value: 7, child: Text('July (07)')),
                            DropdownMenuItem(value: 8, child: Text('August (08)')),
                            DropdownMenuItem(value: 9, child: Text('September (09)')),
                            DropdownMenuItem(value: 10, child: Text('October (10)')),
                            DropdownMenuItem(value: 11, child: Text('November (11)')),
                            DropdownMenuItem(value: 12, child: Text('December (12)')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadMonth = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 8.0,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44.0),
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                        ),
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
                        label: const Text('Upload Sell Out'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44.0),
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        ),
                        onPressed: _isLoadingArchive ? null : _loadSellOutArchive,
                        icon: const Icon(Icons.refresh_rounded, size: 18.0),
                        label: const Text('تحديث القائمة'),
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
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: _isLoadingArchive
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _archivedSellOutFiles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 48.0,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12.0),
                            Text(
                              'لا توجد شيتات إكسيل مرفوعة في أرشيف الـ Sell-Out حالياً.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Text(
                              'اضغط على زر "Upload Sell Out" لرفع شيت مبيعات أول شهر وبدء المتابعة التراكمية.',
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
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          colorScheme.surfaceContainerHigh.withOpacity(0.5),
                        ),
                        columns: const [
                          DataColumn(label: Text('اسم شيت الإكسيل (Excel File)')),
                          DataColumn(label: Text('السلسلة (Chain)')),
                          DataColumn(label: Text('الشهور المغطاة (Period)')),
                          DataColumn(label: Text('عدد الحركات'), numeric: true),
                          DataColumn(label: Text('إجمالي القطع المباعة'), numeric: true),
                          DataColumn(label: Text('صافي المبيعات (Net Sell-Out EGP)'), numeric: true),
                          DataColumn(label: Text('تاريخ الرفع')),
                          DataColumn(label: Text('إجراءات التحكم (تعديل / تحميل / حذف)')),
                        ],
                        rows: _archivedSellOutFiles.map((file) {
                          final isDeleting = _deletingFileId == file.id;
                          final isReplacing = _replacingFileId == file.id;
                          final periodText = file.targetMonth.isNotEmpty && file.targetMonth != 'auto'
                              ? '${file.targetMonth} / ${file.targetYear}'
                              : 'سنة ${file.targetYear}';

                          return DataRow(
                            cells: [
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.description_rounded,
                                      color: Colors.green.shade700,
                                      size: 20.0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.fileName,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        Text(
                                          _formatFileSize(file.fileSizeBytes),
                                          style: TextStyle(
                                            fontSize: 11.0,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(999.0),
                                  ),
                                  child: Text(
                                    file.retailChain.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
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
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatNumber(file.rowsIngested),
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
                                Text(
                                  file.uploadedAt.length >= 16
                                      ? file.uploadedAt.substring(0, 16).replaceAll('T', ' ')
                                      : file.uploadedAt,
                                  style: TextStyle(
                                    fontSize: 12.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 1. Replace / Edit Sheet Button
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                      ),
                                      onPressed: (isDeleting || isReplacing || _isUploading)
                                          ? null
                                          : () => _pickAndUploadSellOutFile(
                                                replaceArchiveId: file.id,
                                                forceChain: file.retailChain,
                                              ),
                                      icon: isReplacing
                                          ? const SizedBox(
                                              width: 14.0,
                                              height: 14.0,
                                              child: CircularProgressIndicator(strokeWidth: 2.0),
                                            )
                                          : const Icon(Icons.edit_document, size: 16.0),
                                      label: const Text('تعديل / استبدال'),
                                    ),
                                    const SizedBox(width: 6.0),
                                    // 2. Download Original Excel Sheet Button
                                    IconButton.outlined(
                                      tooltip: 'تحميل ملف الإكسيل الأصلي',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _handleDownloadSellOutSheet(file),
                                      icon: const Icon(Icons.download_rounded, size: 18.0),
                                    ),
                                    const SizedBox(width: 6.0),
                                    // 3. Delete Sheet Button
                                    IconButton.outlined(
                                      tooltip: 'حذف الشيت من المنظومة',
                                      visualDensity: VisualDensity.compact,
                                      style: IconButton.styleFrom(
                                        foregroundColor: colorScheme.error,
                                        side: BorderSide(
                                          color: colorScheme.error.withOpacity(0.5),
                                        ),
                                      ),
                                      onPressed: (isDeleting || isReplacing || _isUploading)
                                          ? null
                                          : () => _confirmAndDeleteSellOutSheet(file),
                                      icon: isDeleting
                                          ? const SizedBox(
                                              width: 14.0,
                                              height: 14.0,
                                              child: CircularProgressIndicator(strokeWidth: 2.0),
                                            )
                                          : const Icon(Icons.delete_outline_rounded, size: 18.0),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
        ),
      ],
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
    if (maxWidth >= 960) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: card1),
          const SizedBox(width: 12.0),
          Expanded(child: card2),
          const SizedBox(width: 12.0),
          Expanded(child: card3),
          const SizedBox(width: 12.0),
          Expanded(child: card4),
        ],
      );
    } else if (maxWidth >= 580) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: card1),
              const SizedBox(width: 12.0),
              Expanded(child: card2),
            ],
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              Expanded(child: card3),
              const SizedBox(width: 12.0),
              Expanded(child: card4),
            ],
          ),
        ],
      );
    } else {
      return Column(
        children: [
          card1,
          const SizedBox(height: 12.0),
          card2,
          const SizedBox(height: 12.0),
          card3,
          const SizedBox(height: 12.0),
          card4,
        ],
      );
    }
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(icon, color: color, size: 20.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleAr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1.0),
                    Text(
                      titleEn,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
