import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';

/// Adeco Canonical Product Master & Official Price List Screen (`كارتة الأصناف والأسعار`).
/// Provides:
/// 1. Full 389-SKU Catalog searchable by Item Code (`كود الصنف` e.g. FGCL-0550-0001 / FGSL),
///    Barcode (`الباركود`), Arabic SKU Name, Brand, Prefix, Packaging, and Item Type (`عادي` / `عرض`).
/// 2. Interactive Product ID Card Modal (`بطاقة تعريف الصنف`) with inline editing & persistence.
/// 3. Interactive Carton/Unit Order, VAT (14%), Discount & Retailer Margin Calculator.
/// 4. Product Master Excel Workbook Upload & Archive History (`الشيتات المرفوعة وتحديث الكارتة`).
class ProductMasterScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String? initialSearchQuery;

  const ProductMasterScreen({
    super.key,
    required this.apiClient,
    this.initialSearchQuery,
  });

  /// Opens the Canonical Product ID Card Modal (`بطاقة تعريف الصنف`) from any screen.
  static Future<ProductMasterItemModel?> showProductIdCardModal(
    BuildContext context, {
    required ApiClient apiClient,
    required ProductMasterItemModel item,
    ValueChanged<ProductMasterSummaryModel>? onUpdated,
  }) {
    return showDialog<ProductMasterItemModel>(
      context: context,
      builder: (ctx) => _ProductIdCardDialog(
        apiClient: apiClient,
        item: item,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<ProductMasterScreen> createState() => _ProductMasterScreenState();
}

class _ProductMasterScreenState extends State<ProductMasterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currFmt = NumberFormat('#,##0.00', 'en_US');
  final NumberFormat _intFmt = NumberFormat('#,###', 'en_US');

  bool _isLoading = true;
  bool _isUploading = false;
  String? _errorMessage;

  ProductMasterSummaryModel? _summary;
  List<ArchivedExcelFileModel> _archivedMasterFiles = const [];

  String _selectedPrefix = 'all';
  String _selectedBrand = 'all';
  String _selectedItemType = 'all';
  String _selectedPackaging = 'all';
  String _selectedPullStatus = 'all';
  int _currentPage = 0;
  static const int _pageSize = 50;

  // Calculator state
  ProductMasterItemModel? _calcSelectedSku;
  final TextEditingController _calcCartonsCtrl = TextEditingController(text: '10');
  final TextEditingController _calcInvoiceDiscCtrl = TextEditingController(text: '10.0');
  final TextEditingController _calcExtraDiscCtrl = TextEditingController(text: '0.0');
  final TextEditingController _calcRetailPriceCtrl = TextEditingController(text: '0.0');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!.trim();
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _calcCartonsCtrl.dispose();
    _calcInvoiceDiscCtrl.dispose();
    _calcExtraDiscCtrl.dispose();
    _calcRetailPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await widget.apiClient.getProductMaster();
      List<ArchivedExcelFileModel> pmArchives = const [];
      try {
        final archiveResp = await widget.apiClient.getUploadedFilesArchive(
          fileType: 'product_master',
        );
        pmArchives = archiveResp.files
            .where((f) =>
                f.fileType == 'product_master' ||
                f.retailChain == 'product-master' ||
                f.fileName.toLowerCase().contains('product_master') ||
                f.fileName.contains('اسعار') ||
                f.fileName.contains('أصناف'))
            .toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _archivedMasterFiles = pmArchives;
        if (_calcSelectedSku == null && summary.items.isNotEmpty) {
          _selectCalculatorSku(summary.items.first);
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _selectCalculatorSku(ProductMasterItemModel sku) {
    _calcSelectedSku = sku;
    _calcInvoiceDiscCtrl.text = sku.invoiceDiscountPct.toStringAsFixed(1);
    _calcExtraDiscCtrl.text = sku.extraDiscountPct.toStringAsFixed(1);
    final suggestedShelf = sku.unitPriceInclVat > 0
        ? (sku.unitPriceInclVat * 1.12)
        : 25.0;
    _calcRetailPriceCtrl.text = suggestedShelf.toStringAsFixed(2);
  }

  List<ProductMasterItemModel> get _filteredItems {
    final all = _summary?.items ?? const [];
    final q = _searchController.text.trim();
    return all.where((item) {
      if (_selectedPrefix != 'all') {
        if (_selectedPrefix.toUpperCase() == 'PR') {
          if (!item.itemCodePrefix.toUpperCase().startsWith('PR')) {
            return false;
          }
        } else if (item.itemCodePrefix.toUpperCase() !=
            _selectedPrefix.toUpperCase()) {
          return false;
        }
      }
      if (_selectedBrand != 'all' && item.brand != _selectedBrand) {
        return false;
      }
      if (_selectedItemType != 'all' && item.itemType != _selectedItemType) {
        return false;
      }
      if (_selectedPackaging != 'all' &&
          item.packagingType != _selectedPackaging) {
        return false;
      }
      if (_selectedPullStatus == 'active' && !item.isActiveInChains) {
        return false;
      }
      if (_selectedPullStatus == 'unpulled' && item.isActiveInChains) {
        return false;
      }
      if (q.isNotEmpty) {
        return ApiClient.matchesProductSearch(
          q,
          itemCode: item.itemCode,
          barcode: item.barcode,
          skuName: item.officialName,
          brand: item.brand,
          category: item.category,
          packagingType: item.packagingType,
        );
      }
      return true;
    }).toList();
  }

  Future<void> _handleUploadMasterWorkbook() async {
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final res = await widget.apiClient.uploadProductMasterFile(
        filename: picked.name,
        fileBytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _summary = res.summary;
        _isUploading = false;
        _currentPage = 0;
      });
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F766E),
          content: Text(
            'تم رفع وتحديث كارتة الأصناف بنجاح (${res.summary.totalSkus} صنف من ${picked.name})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('تعذر رفع شيت كارتة الأصناف: $e'),
        ),
      );
    }
  }

  void _exportFilteredCatalogToCsv() {
    final items = _filteredItems;
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'م (Serial)',
        'كود الصنف (Item Code)',
        'الاسم الرسمي للصنف (Official Name)',
        'الباركود (Barcode)',
        'العلامة التجارية (Brand)',
        'الفئة (Category)',
        'التعبئة (Packaging)',
        'الشدة بالكرتونة (Units/Carton)',
        'سعر الوحدة ق.ض (Unit Excl VAT)',
        'ضريبة القيمة المضافة (VAT %)',
        'سعر الوحدة ش.ض (Unit Incl VAT)',
        'سعر الكرتونة ش.ض (Carton Incl VAT)',
        'خصم الفاتورة % (Invoice Discount %)',
        'صافي تكلفة الوحدة (Net Unit Cost)',
        'صافي تكلفة الكرتونة (Net Carton Cost)',
        'نوع الصنف (Item Type)',
      ],
      rows: items
          .map((e) => [
                e.serialNo.toString(),
                e.itemCode,
                e.officialName,
                e.barcode,
                e.brand,
                e.category,
                e.packagingType,
                e.unitsPerCarton.toString(),
                e.unitPriceExclVat.toStringAsFixed(2),
                '${(e.vatRate * 100).toStringAsFixed(0)}%',
                e.unitPriceInclVat.toStringAsFixed(2),
                e.cartonPriceInclVat.toStringAsFixed(2),
                '${e.invoiceDiscountPct.toStringAsFixed(1)}%',
                e.netUnitInvoiceCost.toStringAsFixed(2),
                e.netCartonInvoiceCost.toStringAsFixed(2),
                e.itemType,
              ])
          .toList(),
    );
    ExcelExportService.downloadCsv(
      'Adeco_Product_Master_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv,
    );
  }

  void _copyToClipboard(String value, String labelAr) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('تم نسخ $labelAr: $value'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _summary!;
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderBanner(theme, cs, summary),
                  const SizedBox(height: 16.0),
                  _buildKpiCardsRow(theme, cs, summary, filtered.length),
                  const SizedBox(height: 16.0),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14.0),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: cs.primary,
                      unselectedLabelColor: cs.onSurfaceVariant,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: [
                        _buildBilingualTab(
                          icon: Icons.qr_code_2_rounded,
                          titleAr: 'كارتة تعريف الأصناف والأسعار (${filtered.length})',
                          titleEn: 'Official SKU Catalog & Price List',
                        ),
                        _buildBilingualTab(
                          icon: Icons.calculate_outlined,
                          titleAr: 'حاسبة الطلبيات والخصومات والهامش',
                          titleEn: 'Order, VAT & Margin Calculator',
                        ),
                        _buildBilingualTab(
                          icon: Icons.cloud_upload_outlined,
                          titleAr: 'الشيتات المرفوعة وتحديث الكارتة (${_archivedMasterFiles.length})',
                          titleEn: 'Uploaded Price Sheets & Sync',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCatalogTab(theme, cs, summary, filtered),
            _buildCalculatorTab(theme, cs, summary),
            _buildUploadAndArchiveTab(theme, cs, summary),
          ],
        ),
      ),
    );
  }

  Widget _buildBilingualTab({
    required IconData icon,
    required String titleAr,
    required String titleEn,
  }) {
    return Tab(
      height: 54.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18.0),
          const SizedBox(width: 8.0),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleAr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  titleEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.55),
            cs.surfaceContainer,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 14.0,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14.0),
                ),
                child: Icon(
                  Icons.inventory_rounded,
                  color: cs.onPrimary,
                  size: 28.0,
                ),
              ),
              const SizedBox(width: 14.0),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كارتة الأصناف والأسعار المعتمدة • أدكو (Adeco)',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'Canonical Product Master, Item Codes (كود الصنف), Barcodes & Official Carton/Unit Pricing',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      children: [
                        _buildMetaChip(
                          cs,
                          Icons.verified_rounded,
                          summary.sheetDateLabel,
                        ),
                        _buildMetaChip(
                          cs,
                          Icons.discount_outlined,
                          'خصم الفاتورة الأساسي: ${summary.defaultDiscountPct.toStringAsFixed(0)}%',
                        ),
                        _buildMetaChip(
                          cs,
                          Icons.receipt_long_outlined,
                          'ضريبة القيمة المضافة: ${(summary.defaultVatRate * 100).toStringAsFixed(0)}%',
                        ),
                        _buildMetaChip(
                          cs,
                          Icons.description_outlined,
                          summary.sourceFilename,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10.0,
            runSpacing: 8.0,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('product_master_export_csv_btn'),
                onPressed: _exportFilteredCatalogToCsv,
                icon: const Icon(Icons.download_rounded, size: 18.0),
                label: const Text('تصدير Excel (CSV)'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('product_master_add_sku_btn'),
                onPressed: () async {
                  final newItem = ProductMasterItemModel(
                    serialNo: summary.totalSkus + 1,
                    itemCode: 'FGCL-0550-0999',
                    itemCodePrefix: 'FGCL',
                    officialName: '',
                    barcode: '6221133000000',
                    category: 'الكلور والمطهرات (Chlorine & Disinfectants)',
                    brand: 'كلوريل (Clorel)',
                    packagingType: 'عبوة',
                    unitsPerCarton: 12,
                    unitPriceExclVat: 20.0,
                    vatRate: 0.14,
                    unitPriceInclVat: 22.80,
                    cartonPriceExclVat: 240.0,
                    cartonPriceInclVat: 273.60,
                    invoiceDiscountPct: 10.0,
                    extraDiscountPct: 0.0,
                    netUnitInvoiceCost: 20.52,
                    netCartonInvoiceCost: 246.24,
                    itemType: 'عادي',
                  );
                  await ProductMasterScreen.showProductIdCardModal(
                    context,
                    apiClient: widget.apiClient,
                    item: newItem,
                    onUpdated: (updatedSummary) {
                      if (mounted) {
                        setState(() => _summary = updatedSummary);
                      }
                    },
                  );
                },
                icon: const Icon(Icons.add_box_outlined, size: 18.0),
                label: const Text('إضافة صنف جديد'),
              ),
              FilledButton.icon(
                key: const ValueKey('product_master_upload_btn'),
                onPressed: _isUploading ? null : _handleUploadMasterWorkbook,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18.0),
                label: Text(
                  _isUploading
                      ? 'جاري تحديث الكارتة...'
                      : 'رفع تحديث شيت الأسعار',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.0, color: cs.primary),
          const SizedBox(width: 5.0),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCardsRow(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    int filteredCount,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;
        final cards = [
          _buildKpiCard(
            theme: theme,
            cs: cs,
            titleAr: 'إجمالي الأصناف المسجلة بالكارتة',
            titleEn: 'Total Registered Master SKUs',
            value: '${_intFmt.format(summary.totalSkus)} صنف',
            subtitle: 'المعروض بالفلتر الحالي: ${_intFmt.format(filteredCount)} صنف',
            icon: Icons.qr_code_scanner_rounded,
            accentColor: cs.primary,
          ),
          _buildKpiCard(
            theme: theme,
            cs: cs,
            titleAr: 'أصناف البيع العادي (Regular)',
            titleEn: 'Standard Catalog SKUs',
            value: '${_intFmt.format(summary.regularSkusCount)} صنف عادي',
            subtitle:
                'تمثل ${summary.totalSkus > 0 ? ((summary.regularSkusCount / summary.totalSkus) * 100).toStringAsFixed(1) : 0}% من إجمالي الكارتة',
            icon: Icons.check_circle_outline_rounded,
            accentColor: const Color(0xFF0F766E),
          ),
          _buildKpiCard(
            theme: theme,
            cs: cs,
            titleAr: 'أصناف العروض الترويجية (Promos)',
            titleEn: 'Promotional & Bundle SKUs (PR)',
            value: '${_intFmt.format(summary.promoSkusCount)} عرض ترويجي',
            subtitle: 'أكواد العروض الخاصة والشرنك والـ Bundles',
            icon: Icons.local_offer_outlined,
            accentColor: const Color(0xFFD97706),
          ),
          _buildKpiCard(
            theme: theme,
            cs: cs,
            titleAr: 'الباركودات الفريدة والشدود',
            titleEn: 'Unique Barcodes & Avg Pack Size',
            value: '${_intFmt.format(summary.uniqueBarcodesCount)} باركود',
            subtitle:
                'متوسط الشدة: ${summary.avgUnitsPerCarton.toStringAsFixed(1)} وحدة/كرتونة',
            icon: Icons.view_in_ar_rounded,
            accentColor: const Color(0xFF4F46E5),
          ),
          _buildKpiCard(
            theme: theme,
            cs: cs,
            titleAr: 'التغطية والسحب بالسلاسل',
            titleEn: 'Chain Assortment & Pull Coverage',
            value: '${_intFmt.format(summary.activeInChainsCount)} نشط بالسلاسل',
            subtitle:
                'غير مسحوب (فرصة توزيع): ${_intFmt.format(summary.unpulledSkusCount)} صنف',
            icon: Icons.storefront_rounded,
            accentColor: const Color(0xFF0284C7),
          ),
        ];

        if (isWide) {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5.0),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        }
        return Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          children: cards
              .map((c) => SizedBox(
                    width: (constraints.maxWidth - 12.0) / 2,
                    child: c,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required ThemeData theme,
    required ColorScheme cs,
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(icon, color: accentColor, size: 20.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      titleEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10.5,
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
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _buildEffectivePrefixChips(ProductMasterSummaryModel summary) {
    final raw = summary.availablePrefixes;
    final hasSubPr = raw.any((p) => p.toUpperCase().startsWith('PR') && p.toUpperCase() != 'PR');
    final hasExactPr = raw.any((p) => p.toUpperCase() == 'PR');
    if (hasSubPr && !hasExactPr) {
      return [...raw, 'PR'];
    }
    return raw;
  }

  Widget _buildCatalogTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    List<ProductMasterItemModel> filtered,
  ) {
    final totalPages = (filtered.length / _pageSize).ceil();
    final safePage = totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = (startIdx + _pageSize) > filtered.length
        ? filtered.length
        : (startIdx + _pageSize);
    final pageItems = filtered.isEmpty
        ? const <ProductMasterItemModel>[]
        : filtered.sublist(startIdx, endIdx);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 32.0),
      children: [
        // Search & Filter Bar
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const ValueKey('product_master_search_input'),
                      controller: _searchController,
                      onChanged: (_) => setState(() => _currentPage = 0),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _currentPage = 0);
                                },
                              )
                            : null,
                        hintText:
                            'ابحث بكود الصنف (مثل FGCL-0550-0001 أو FGSL) أو الباركود (6221133...) أو اسم الصنف أو البراند...',
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  if (_selectedPrefix != 'all' ||
                      _selectedBrand != 'all' ||
                      _selectedItemType != 'all' ||
                      _selectedPackaging != 'all' ||
                      _selectedPullStatus != 'all' ||
                      _searchController.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _selectedPrefix = 'all';
                          _selectedBrand = 'all';
                          _selectedItemType = 'all';
                          _selectedPackaging = 'all';
                          _selectedPullStatus = 'all';
                          _currentPage = 0;
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18.0),
                      label: const Text('إعادة ضبط الفلاتر'),
                    ),
                ],
              ),
              const SizedBox(height: 12.0),
              // Prefix quick chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'بادئة كود الصنف (Item Code Prefix):',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    _buildFilterChip(
                      label: 'الكل (All)',
                      selected: _selectedPrefix == 'all',
                      onSelected: () => setState(() {
                        _selectedPrefix = 'all';
                        _currentPage = 0;
                      }),
                    ),
                    ..._buildEffectivePrefixChips(summary).map(
                      (pfx) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6.0),
                        child: _buildFilterChip(
                          label: '$pfx (${_prefixDescriptionAr(pfx)})',
                          selected: _selectedPrefix == pfx,
                          onSelected: () => setState(() {
                            _selectedPrefix = pfx;
                            _currentPage = 0;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 10.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Brand filter
                  _buildDropdownFilter(
                    labelAr: 'العلامة التجارية (Brand)',
                    value: _selectedBrand,
                    items: {
                      'all': 'كل العلامات التجارية (${summary.availableBrands.length})',
                      for (final b in summary.availableBrands) b: b,
                    },
                    onChanged: (v) => setState(() {
                      _selectedBrand = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Item Type filter
                  _buildDropdownFilter(
                    labelAr: 'نوع الصنف (Item Type)',
                    value: _selectedItemType,
                    items: {
                      'all': 'الكل (عادي + عرض)',
                      'عادي': 'عادي (Regular - ${summary.regularSkusCount})',
                      'عرض': 'عرض ترويجي (Promo - ${summary.promoSkusCount})',
                    },
                    onChanged: (v) => setState(() {
                      _selectedItemType = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Packaging filter
                  _buildDropdownFilter(
                    labelAr: 'نوع التعبئة (Packaging)',
                    value: _selectedPackaging,
                    items: {
                      'all': 'كل أنواع التعبئة',
                      for (final p in summary.availablePackaging) p: p,
                    },
                    onChanged: (v) => setState(() {
                      _selectedPackaging = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Chain Pull Status filter
                  _buildDropdownFilter(
                    labelAr: 'حالة السحب بالسلاسل (Pull Status)',
                    value: _selectedPullStatus,
                    items: {
                      'all': 'الكل (${summary.totalSkus})',
                      'active': 'مسحوب ونشط بالسلاسل (${summary.activeInChainsCount})',
                      'unpulled': 'غير مسحوب - فرصة توزيع (${summary.unpulledSkusCount})',
                    },
                    onChanged: (v) => setState(() {
                      _selectedPullStatus = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Table Header & Pagination Top Bar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0,
                  runSpacing: 8.0,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'جدول كارتة الأصناف والأسعار الرسمية (${_intFmt.format(filtered.length)} صنف)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Official SKU Master Table • اضغط على أي صنف لفتح بطاقة تعريف الصنف أو تعديل السعر والباركود',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filtered.isEmpty
                              ? '0 من 0'
                              : 'عرض ${startIdx + 1} - $endIdx من ${filtered.length}',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          tooltip: 'الصفحة السابقة',
                          onPressed: safePage > 0
                              ? () => setState(() => _currentPage = safePage - 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          tooltip: 'الصفحة التالية',
                          onPressed: safePage < totalPages - 1
                              ? () => setState(() => _currentPage = safePage + 1)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1.0),
              if (pageItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد أصناف مطابقة لمعايير البحث الحالية',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    ),
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: 68.0,
                    columnSpacing: 18.0,
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: _buildColHeader('م', '#')),
                      DataColumn(
                        label: _buildColHeader('كود الصنف', 'Item Code'),
                      ),
                      DataColumn(
                        label: _buildColHeader(
                          'الاسم الرسمي للصنف والعلامة',
                          'Official SKU Name & Brand',
                        ),
                      ),
                      DataColumn(
                        label: _buildColHeader('الباركود', 'Barcode (GTIN)'),
                      ),
                      DataColumn(
                        label: _buildColHeader(
                          'التعبئة والشدة',
                          'Pack & Units/Carton',
                        ),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _buildColHeader(
                          'سعر الوحدة (ق.ض)',
                          'Unit Excl. VAT',
                        ),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _buildColHeader(
                          'سعر الوحدة (ش.ض 14%)',
                          'Unit Incl. VAT',
                        ),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _buildColHeader(
                          'سعر الكرتونة (ش.ض)',
                          'Carton Incl. VAT',
                        ),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _buildColHeader(
                          'صافي الوحدة بعد الخصم',
                          'Net Unit Cost (-${summary.defaultDiscountPct.toStringAsFixed(0)}%)',
                        ),
                      ),
                      DataColumn(
                        label: _buildColHeader('نوع الصنف والسحب', 'Type & Chain Pull'),
                      ),
                      DataColumn(
                        label: _buildColHeader('إجراءات', 'Actions'),
                      ),
                    ],
                    rows: pageItems.map((item) {
                      final isPromo = item.itemType == 'عرض';
                      return DataRow(
                        onSelectChanged: (_) async {
                          await ProductMasterScreen.showProductIdCardModal(
                            context,
                            apiClient: widget.apiClient,
                            item: item,
                            onUpdated: (updatedSummary) {
                              if (mounted) {
                                setState(() => _summary = updatedSummary);
                              }
                            },
                          );
                        },
                        cells: [
                          DataCell(
                            Text(
                              item.serialNo.toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          // Item Code pill
                          DataCell(
                            InkWell(
                              onTap: () =>
                                  _copyToClipboard(item.itemCode, 'كود الصنف'),
                              borderRadius: BorderRadius.circular(8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.itemCode,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 12.0,
                                      color: cs.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Official Name & Brand
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 290),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.officialName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2.0),
                                  Text(
                                    '${item.brand} • ${item.category}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Barcode
                          DataCell(
                            InkWell(
                              onTap: () =>
                                  _copyToClipboard(item.barcode, 'الباركود'),
                              borderRadius: BorderRadius.circular(8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.qr_code_rounded,
                                      size: 13.0,
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      item.barcode,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Pack & Units/Carton
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.unitsPerCarton} وحدة / كرتونة',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'التعبئة: ${item.packagingType}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Unit Price Excl VAT
                          DataCell(
                            Text(
                              '${_currFmt.format(item.unitPriceExclVat)} ج.م',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Unit Price Incl VAT
                          DataCell(
                            Text(
                              '${_currFmt.format(item.unitPriceInclVat)} ج.م',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          // Carton Price Incl VAT
                          DataCell(
                            Text(
                              '${_currFmt.format(item.cartonPriceInclVat)} ج.م',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          // Net Unit Cost
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${_currFmt.format(item.netUnitInvoiceCost)} ج.م',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F766E),
                                  ),
                                ),
                                Text(
                                  'كرتونة: ${_currFmt.format(item.netCartonInvoiceCost)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10.0,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Item Type & Pull Status badge
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10.0,
                                    vertical: 3.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPromo
                                        ? const Color(0xFFD97706)
                                            .withValues(alpha: 0.15)
                                        : const Color(0xFF0F766E)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999.0),
                                  ),
                                  child: Text(
                                    isPromo ? 'عرض (Promo)' : 'عادي (Regular)',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: isPromo
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF0F766E),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3.0),
                                Text(
                                  item.isActiveInChains
                                      ? 'مسحوب بالسلاسل (${_intFmt.format(item.totalPosUnitsSold)} وحدة)'
                                      : 'غير مسحوب • فرصة توزيع',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w700,
                                    color: item.isActiveInChains
                                        ? const Color(0xFF0284C7)
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Actions
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.badge_outlined,
                                    size: 18.0,
                                  ),
                                  tooltip: 'بطاقة تعريف الصنف وتعديل السعر',
                                  onPressed: () async {
                                    await ProductMasterScreen
                                        .showProductIdCardModal(
                                      context,
                                      apiClient: widget.apiClient,
                                      item: item,
                                      onUpdated: (updatedSummary) {
                                        if (mounted) {
                                          setState(
                                              () => _summary = updatedSummary);
                                        }
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.calculate_outlined,
                                    size: 18.0,
                                  ),
                                  tooltip: 'حساب طلبية وهامش ربح لهذا الصنف',
                                  onPressed: () {
                                    setState(() {
                                      _selectCalculatorSku(item);
                                      _tabController.animateTo(1);
                                    });
                                  },
                                ),
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
      ],
    );
  }

  Widget _buildColHeader(String ar, String en) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ar,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.0),
        ),
        Text(
          en,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 10.0),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDropdownFilter({
    required String labelAr,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.containsKey(value) ? value : 'all';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$labelAr:',
          style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6.0),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.6),
              ),
            ),
            child: DropdownButton<String>(
              value: safeValue,
              isDense: true,
              items: items.entries
                  .map((e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(
                          e.value,
                          style: const TextStyle(fontSize: 12.0),
                        ),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  String _prefixDescriptionAr(String prefix) {
    final p = prefix.toUpperCase();
    switch (p) {
      case 'FGCL':
        return 'كلور ومبيضات';
      case 'FGDG':
        return 'سائل أطباق فيبا';
      case 'FGDW':
        return 'غسالات أطباق أوتوماتيك';
      case 'FGLC':
        return 'العناية بالملابس والمنسوجات';
      case 'FGGC':
        return 'منظف وملمع زجاج';
      case 'FGHC':
        return 'عناية منزلية ومطهرات';
      case 'FGPC':
        return 'عناية شخصية وصابون';
      default:
        if (p.startsWith('PR')) {
          return 'عروض ترويجية';
        }
        return 'أصناف أدكو';
    }
  }

  void _exportCalculatorOrderToCsv({
    required ProductMasterItemModel sku,
    required double cartons,
    required int totalUnits,
    required double grossExclVat,
    required double vatAmount,
    required double grossInclVat,
    required double invDiscPct,
    required double extraDiscPct,
    required double totalDiscountEgp,
    required double netPayable,
    required double netUnitCost,
    required double shelfUnitPrice,
    required double retailerProfitEgp,
    required double retailerMarginPct,
  }) {
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'كود الصنف (Item Code)',
        'الاسم الرسمي للصنف (Official Name)',
        'الباركود (Barcode)',
        'الكمية بالكرتونة (Cartons)',
        'الشدة بالكرتونة (Units/Carton)',
        'إجمالي الوحدات (Total Units)',
        'إجمالي القيمة قبل الضريبة (Gross Excl VAT)',
        'ضريبة القيمة المضافة 14% (VAT EGP)',
        'الإجمالي شامل الضريبة (Gross Incl VAT)',
        'خصم الفاتورة % (Invoice Disc %)',
        'خصم إضافي % (Extra Disc %)',
        'إجمالي الخصومات (Total Discount EGP)',
        'صافي الفاتورة المستحق لأدكو (Net Payable EGP)',
        'صافي تكلفة الوحدة (Net Unit Cost EGP)',
        'سعر بيع السلسلة للمستهلك (Shelf Price EGP)',
        'هامش ربح السلسلة المتوقع % (Retailer Margin %)',
        'إجمالي ربح السلسلة (Retailer Profit EGP)',
      ],
      rows: [
        [
          sku.itemCode,
          sku.officialName,
          sku.barcode,
          cartons.toStringAsFixed(1),
          sku.unitsPerCarton.toString(),
          totalUnits.toString(),
          grossExclVat.toStringAsFixed(2),
          vatAmount.toStringAsFixed(2),
          grossInclVat.toStringAsFixed(2),
          '${invDiscPct.toStringAsFixed(1)}%',
          '${extraDiscPct.toStringAsFixed(1)}%',
          totalDiscountEgp.toStringAsFixed(2),
          netPayable.toStringAsFixed(2),
          netUnitCost.toStringAsFixed(2),
          shelfUnitPrice.toStringAsFixed(2),
          '${retailerMarginPct.toStringAsFixed(1)}%',
          retailerProfitEgp.toStringAsFixed(2),
        ],
      ],
    );
    ExcelExportService.downloadCsv(
      'Adeco_Order_${sku.itemCode}_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv,
    );
  }

  Widget _buildCalculatorTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    final sku = _calcSelectedSku ??
        (summary.items.isNotEmpty ? summary.items.first : null);
    if (sku == null) {
      return const Center(child: Text('لا توجد أصناف متاحة بالحاسبة'));
    }

    final cartons = double.tryParse(_calcCartonsCtrl.text.trim()) ?? 1.0;
    final invDiscPct =
        double.tryParse(_calcInvoiceDiscCtrl.text.trim()) ?? sku.invoiceDiscountPct;
    final extraDiscPct =
        double.tryParse(_calcExtraDiscCtrl.text.trim()) ?? sku.extraDiscountPct;
    final shelfUnitPrice =
        double.tryParse(_calcRetailPriceCtrl.text.trim()) ?? sku.unitPriceInclVat;

    final totalUnits = (cartons * sku.unitsPerCarton).round();
    final grossExclVat = cartons * sku.cartonPriceExclVat;
    final vatAmount = grossExclVat * sku.vatRate;
    final grossInclVat = cartons * sku.cartonPriceInclVat;

    final afterInvDisc = grossInclVat * (1.0 - (invDiscPct / 100.0));
    final netPayable = afterInvDisc * (1.0 - (extraDiscPct / 100.0));
    final totalDiscountEgp = grossInclVat - netPayable;
    final netUnitCost = totalUnits > 0 ? netPayable / totalUnits : 0.0;

    final totalShelfRevenue = totalUnits * shelfUnitPrice;
    final retailerProfitEgp = totalShelfRevenue - netPayable;
    final retailerMarginPct = totalShelfRevenue > 0
        ? (retailerProfitEgp / totalShelfRevenue) * 100.0
        : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 32.0),
      children: [
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12.0,
                runSpacing: 8.0,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حاسبة الطلبيات والخصومات وضريبة القيمة المضافة وهامش ربح السلسلة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Order Economics, VAT (14%), Trade Discounts & Retailer Shelf Margin Simulator',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('product_master_export_order_csv_btn'),
                    onPressed: () => _exportCalculatorOrderToCsv(
                      sku: sku,
                      cartons: cartons,
                      totalUnits: totalUnits,
                      grossExclVat: grossExclVat,
                      vatAmount: vatAmount,
                      grossInclVat: grossInclVat,
                      invDiscPct: invDiscPct,
                      extraDiscPct: extraDiscPct,
                      totalDiscountEgp: totalDiscountEgp,
                      netPayable: netPayable,
                      netUnitCost: netUnitCost,
                      shelfUnitPrice: shelfUnitPrice,
                      retailerProfitEgp: retailerProfitEgp,
                      retailerMarginPct: retailerMarginPct,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18.0),
                    label: const Text('تصدير أمر التوريد Excel (CSV)'),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              DropdownButtonFormField<ProductMasterItemModel>(
                value: summary.items.contains(sku) ? sku : summary.items.first,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'اختر الصنف من كارتة الأصناف (Select SKU)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                items: summary.items
                    .take(200)
                    .map(
                      (item) => DropdownMenuItem<ProductMasterItemModel>(
                        value: item,
                        child: Text(
                          '[${item.itemCode}] ${item.officialName} • باركود: ${item.barcode} (${item.unitsPerCarton} وحدة/كرتونة)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectCalculatorSku(val));
                  }
                },
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 16.0,
                runSpacing: 12.0,
                children: [
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcCartonsCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'الكمية بالكرتونة (Cartons)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcInvoiceDiscCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'خصم الفاتورة % (Invoice Disc %)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcExtraDiscCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'خصم إضافي % (Extra Disc %)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _calcRetailPriceCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'سعر بيع السلسلة للمستهلك (Shelf EGP)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              const Divider(),
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: [
                  _buildCalcResultTile(
                    cs,
                    'إجمالي الوحدات بالطلبية',
                    'Total Units Ordered',
                    '${_intFmt.format(totalUnits)} وحدة (${sku.packagingType})',
                    cs.primary,
                  ),
                  _buildCalcResultTile(
                    cs,
                    'إجمالي القيمة قبل الضريبة',
                    'Gross Value Excl. VAT',
                    '${_currFmt.format(grossExclVat)} ج.م',
                    cs.onSurface,
                  ),
                  _buildCalcResultTile(
                    cs,
                    'قيمة ضريبة القيمة المضافة (14%)',
                    'VAT Amount (14%)',
                    '${_currFmt.format(vatAmount)} ج.م',
                    const Color(0xFFD97706),
                  ),
                  _buildCalcResultTile(
                    cs,
                    'إجمالي قيمة الخصومات التجارية',
                    'Total Invoice & Extra Discounts',
                    '-${_currFmt.format(totalDiscountEgp)} ج.م',
                    const Color(0xFFDC2626),
                  ),
                  _buildCalcResultTile(
                    cs,
                    'صافي الفاتورة المستحق لأدكو',
                    'Net Payable Invoice Value',
                    '${_currFmt.format(netPayable)} ج.م (الوحدة: ${_currFmt.format(netUnitCost)})',
                    const Color(0xFF0F766E),
                  ),
                  _buildCalcResultTile(
                    cs,
                    'هامش ربح السلسلة المتوقع',
                    'Projected Retailer Shelf Margin',
                    '${retailerMarginPct.toStringAsFixed(1)}% (${_currFmt.format(retailerProfitEgp)} ج.م)',
                    const Color(0xFF4F46E5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalcResultTile(
    ColorScheme cs,
    String titleAr,
    String titleEn,
    String value,
    Color color,
  ) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleAr,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          Text(
            titleEn,
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8.0),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadAndArchiveTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 32.0),
      children: [
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                size: 48.0,
                color: cs.primary,
              ),
              const SizedBox(height: 12.0),
              Text(
                'رفع وتحديث شيت كارتة الأصناف والأسعار (Excel .xlsx / .csv)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                'يقوم النظام تلقائياً بقراءة أكواد الأصناف (FGCL, FGDW, PR...) والباركودات والشدود والأسعار وتحديث جميع شاشات المبيعات والنواقص والتسعير فوراً',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16.0),
              FilledButton.icon(
                onPressed: _isUploading ? null : _handleUploadMasterWorkbook,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختيار شيت كارتة الأصناف من الجهاز'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20.0),
        Text(
          'أرشيف شيتات كارتة الأصناف والأسعار المرفوعة (${_archivedMasterFiles.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10.0),
        if (_archivedMasterFiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14.0),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    'النسخة المعتمدة الحالية: ${summary.sourceFilename} (${summary.sheetDateLabel}) • إجمالي ${summary.totalSkus} صنف مفعل بالنظام.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ..._archivedMasterFiles.map(
            (file) => Card(
              margin: const EdgeInsets.only(bottom: 10.0),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.table_view_rounded, color: cs.primary),
                ),
                title: Text(
                  file.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'عدد الأصناف: ${file.rowsIngested} صنف • تاريخ الرفع: ${file.uploadedAt}',
                ),
                trailing: Text(
                  '${(file.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProductIdCardDialog extends StatefulWidget {
  final ApiClient apiClient;
  final ProductMasterItemModel item;
  final ValueChanged<ProductMasterSummaryModel>? onUpdated;

  const _ProductIdCardDialog({
    required this.apiClient,
    required this.item,
    this.onUpdated,
  });

  @override
  State<_ProductIdCardDialog> createState() => _ProductIdCardDialogState();
}

class _ProductIdCardDialogState extends State<_ProductIdCardDialog> {
  late final TextEditingController _itemCodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _packagingCtrl;
  late final TextEditingController _unitsPerCartonCtrl;
  late final TextEditingController _unitPriceInclVatCtrl;
  late final TextEditingController _discountPctCtrl;
  late String _itemType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _itemCodeCtrl = TextEditingController(text: i.itemCode);
    _nameCtrl = TextEditingController(text: i.officialName);
    _barcodeCtrl = TextEditingController(text: i.barcode);
    _brandCtrl = TextEditingController(text: i.brand);
    _categoryCtrl = TextEditingController(text: i.category);
    _packagingCtrl = TextEditingController(text: i.packagingType);
    _unitsPerCartonCtrl =
        TextEditingController(text: i.unitsPerCarton.toString());
    _unitPriceInclVatCtrl =
        TextEditingController(text: i.unitPriceInclVat.toStringAsFixed(2));
    _discountPctCtrl =
        TextEditingController(text: i.invoiceDiscountPct.toStringAsFixed(1));
    _itemType = i.itemType == 'عرض' ? 'عرض' : 'عادي';
  }

  @override
  void dispose() {
    _itemCodeCtrl.dispose();
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _brandCtrl.dispose();
    _categoryCtrl.dispose();
    _packagingCtrl.dispose();
    _unitsPerCartonCtrl.dispose();
    _unitPriceInclVatCtrl.dispose();
    _discountPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final code = _itemCodeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final barcode = _barcodeCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) return;

    final units = int.tryParse(_unitsPerCartonCtrl.text.trim()) ?? 12;
    final unitIncl =
        double.tryParse(_unitPriceInclVatCtrl.text.trim()) ?? 0.0;
    final discPct = double.tryParse(_discountPctCtrl.text.trim()) ?? 10.0;
    final vatRate = widget.item.vatRate > 0 ? widget.item.vatRate : 0.14;
    final unitExcl = unitIncl / (1.0 + vatRate);
    final cartonIncl = unitIncl * units;
    final cartonExcl = unitExcl * units;
    final netUnit = unitIncl * (1.0 - (discPct / 100.0));
    final netCarton = cartonIncl * (1.0 - (discPct / 100.0));

    final updatedItem = widget.item.copyWith(
      itemCode: code,
      itemCodePrefix: code.contains('-') ? code.split('-').first : code,
      officialName: name,
      barcode: barcode,
      brand: _brandCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      packagingType: _packagingCtrl.text.trim(),
      unitsPerCarton: units,
      unitPriceExclVat: double.parse(unitExcl.toStringAsFixed(2)),
      unitPriceInclVat: double.parse(unitIncl.toStringAsFixed(2)),
      cartonPriceExclVat: double.parse(cartonExcl.toStringAsFixed(2)),
      cartonPriceInclVat: double.parse(cartonIncl.toStringAsFixed(2)),
      invoiceDiscountPct: discPct,
      netUnitInvoiceCost: double.parse(netUnit.toStringAsFixed(2)),
      netCartonInvoiceCost: double.parse(netCarton.toStringAsFixed(2)),
      itemType: _itemType,
    );

    setState(() => _isSaving = true);
    try {
      final summary =
          await widget.apiClient.updateProductMasterItem(updatedItem);
      widget.onUpdated?.call(summary);
      if (!mounted) return;
      Navigator.of(context).pop(updatedItem);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ تعديلات الصنف: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i = widget.item;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.badge_rounded, color: cs.primary),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بطاقة تعريف الصنف الرسمية (Product ID Card)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  Text(
                    'كود الصنف: ${i.itemCode} • الباركود: ${i.barcode}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Official Factory Pricing & Chain Pull Status Summary Card
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12.0,
                        runSpacing: 6.0,
                        children: [
                          Text(
                            'القسم: ${i.departmentAr.isNotEmpty ? i.departmentAr : i.itemCodePrefix}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            '• صافي تكلفة الوحدة: ${i.netUnitInvoiceCost.toStringAsFixed(2)} ج.م',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F766E),
                            ),
                          ),
                          Text(
                            '• صافي تكلفة الكرتونة: ${i.netCartonInvoiceCost.toStringAsFixed(2)} ج.م',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            i.isActiveInChains
                                ? '• حالة السحب: نشط بالسلاسل (${i.totalPosUnitsSold} وحدة / ${i.totalPosCartonsSold.toStringAsFixed(1)} كرتونة)'
                                : '• حالة السحب: غير مسحوب بالسلاسل (فرصة توزيع)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: i.isActiveInChains
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'كود الصنف (Item Code)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _barcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الباركود (Barcode GTIN)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الرسمي للصنف في كارتة أدكو (Official Name)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _brandCtrl,
                        decoration: const InputDecoration(
                          labelText: 'العلامة التجارية (Brand)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _packagingCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نوع التعبئة (Packaging)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _unitsPerCartonCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'عدد الوحدات بالكرتونة (Units/Carton)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _unitPriceInclVatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سعر الوحدة شامل الضريبة (Unit Incl VAT)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _discountPctCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'خصم الفاتورة % (Discount %)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                DropdownButtonFormField<String>(
                  value: _itemType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الصنف (Item Type)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'عادي',
                      child: Text('عادي (Regular SKU)'),
                    ),
                    DropdownMenuItem(
                      value: 'عرض',
                      child: Text('عرض ترويجي (Promotional Bundle)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _itemType = v);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveChanges,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ وتحديث الكارتة'),
          ),
        ],
      ),
    );
  }
}
