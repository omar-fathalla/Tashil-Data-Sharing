import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/utils/export_columns.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../domain/cpfr_models.dart';

/// CPFRDashboardScreen implements the multi-company, multi-chain
/// Collaborative Planning, Forecasting & Replenishment (CPFR) system:
/// 1. Sell-In vs. Sell-Out Reconciliation (مطابقة التوريد مع البيع الفعلي والفجوة المخزنية)
/// 2. Stock Disposition Options & Smart Replenishment PO Generator (خيارات بيع الأرصدة وأوامر التوريد)
/// 3. Run-Rate Month-End Forecasting Engine (محرك التنبؤ EXP) & Promotions/Returns Analytics
/// 4. Field Sales Team & Key Account Hierarchy Tracking across all Retail Chains
class CPFRDashboardScreen extends StatefulWidget {
  final ApiClient apiClient;

  const CPFRDashboardScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<CPFRDashboardScreen> createState() => _CPFRDashboardScreenState();
}

class _CPFRDashboardScreenState extends State<CPFRDashboardScreen> {
  int _activeTab =
      0; // 0: Reconciliation, 1: Stock & PO, 2: Forecast & Promos, 3: Sales Team
  bool _isLoading = true;
  bool _isReloadingWorkbook = false;
  bool _isUploadingSellIn = false;
  bool _showDataGuideBanner = false;
  String? _error;
  CPFRDashboardModel? _data;

  // Dynamic Company Retail Chains
  List<RetailChainModel> _companyChains = const [];
  String _selectedChain = 'all'; // all or specific chain code
  String _uploadTargetChain =
      'fathalla'; // target chain when uploading a Sell-In file
  String? _lastUploadedSellInFilename;

  // Horizontal ScrollController for Monthly Reconciliation Table
  final ScrollController _reconciliationTableScrollController =
      ScrollController();

  // Interactive Filters & Replenishment Parameters
  String _selectedSector = 'all'; // all, MT, CC
  String _selectedRegion = 'all'; // all, ALX, CIR, TNT, BHR, MNS
  String _selectedStockStatus =
      'all'; // all, urgent_replenishment, optimal, overstock
  int _leadTimeDays = 4;
  int _safetyStockDays = 7;

  @override
  void initState() {
    super.initState();
    _initChainsAndLoadDashboard();
  }

  @override
  void dispose() {
    _reconciliationTableScrollController.dispose();
    super.dispose();
  }

  Future<void> _initChainsAndLoadDashboard() async {
    try {
      final chains = await widget.apiClient.getRetailChains();
      if (mounted) {
        setState(() {
          _companyChains = chains;
          if (_companyChains.isNotEmpty &&
              (_uploadTargetChain == 'all' ||
                  !_companyChains.any((c) => c.code == _uploadTargetChain))) {
            _uploadTargetChain = _companyChains.first.code;
          }
        });
      }
    } catch (_) {}
    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.fetchCPFRDashboard(
        chain: _selectedChain,
        sector: _selectedSector,
        region: _selectedRegion,
        stockStatus: _selectedStockStatus,
        leadTimeDays: _leadTimeDays,
        safetyStockDays: _safetyStockDays,
      );
      if (!mounted) return;
      setState(() {
        _data = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _reloadSellInWorkbook() async {
    setState(() => _isReloadingWorkbook = true);
    try {
      final res = await widget.apiClient.loadSellInPlanWorkbook(
        chain: _selectedChain,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم تحديث بيانات التوريد والمخزون (${res.validRows} سجل - ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)})',
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر تحديث بيانات التوريد: $e');
    } finally {
      if (mounted) {
        setState(() => _isReloadingWorkbook = false);
      }
    }
  }

  Future<void> _pickAndUploadSellInFile() async {
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() => _isUploadingSellIn = true);
    try {
      final targetChain =
          _uploadTargetChain != 'all' ? _uploadTargetChain : _selectedChain;
      final res = await widget.apiClient.uploadSellInFile(
        filename: picked.name,
        fileBytes: picked.bytes,
        chain: targetChain,
      );
      if (!mounted) return;
      setState(() {
        _lastUploadedSellInFilename = picked.name;
      });
      M3Feedback.showSuccess(
        context,
        'تم رفع ومعالجة ملف التوريد (Sell-In): ${picked.name} (${res.validRows} سجل بإجمالي ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)})',
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر رفع ملف التوريد: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingSellIn = false);
      }
    }
  }

  void _downloadSellInGuidedDemoTemplate() {
    const headers = [
      'السنة (Year)',
      'رقم الشهر (Month_Num)',
      'اسم الشهر (Month_Name)',
      'حالة الفترة (Period_Status)',
      'سلسلة التجزئة (Retail_Chain)',
      'كود الإقليم (Region_Code)',
      'المحافظة (Governorate)',
      'اسم الفرع أو المخزن (Branch_Name)',
      'القطاع السلعي (Sector)',
      'العلامة التجارية (Brand)',
      'الفئة الفرعية (Sub_Category)',
      'باركود أو كود الصنف (Barcode_SKU)',
      'اسم الصنف (Item_Name)',
      'نوع الحركة أو العرض (Promo_Type)',
      'مدير المبيعات (Sales_Manager)',
      'مسؤول كبار العملاء (KA_Officer)',
      'مندوب المبيعات (Sales_Rep)',
      'كمية التوريد بالكرتونة (Sell_In_Cases)',
      'قيمة التوريد بالجنيه (Sell_In_Value_EGP)',
      'الوزن بالطن (Weight_Tons)',
      'الكمية المتوقعة بنهاية الشهر بالكرتونة (Expected_Cases_EXP)',
      'القيمة المتوقعة بنهاية الشهر بالجنيه (Expected_Value_EXP_EGP)',
    ];

    final rows = <List<dynamic>>[
      [
        'سطر إرشادي (يتم تخطيه تلقائياً)',
        'أدخل رقم الشهر من 1 إلى 12',
        'يناير .. ديسمبر أو Jan .. Dec',
        'Full Month للشهر المغلق أو W1 / W2 للتنبؤ',
        'اسم السلسلة (فتح الله / بيت الجملة / جملة ماركت / الوكالة / أو أي سلسلة)',
        'ALX / CIR / TNT / BHR / MNS',
        'اسم المحافظة',
        'اسم الفرع أو التوزيع المركزي',
        'اسم القطاع (مثال: المنظفات / الأغذية / المشروبات / العناية)',
        'اسم العلامة التجارية للشركة',
        'الفئة الفرعية للمنتج',
        'باركود أو كود الصنف الداخلي',
        'الاسم الكامل للصنف ومقاس العبوة',
        'عادي / عرض / مرتجع',
        'اسم مدير المبيعات',
        'اسم مسؤول السلسلة (Key Account)',
        'اسم مندوب المبيعات الميداني',
        'عدد الكراتين الموردة فعلياً (سالب في حالة المرتجع)',
        'صافي قيمة التوريد بالجنيه (Sell-In EGP)',
        'إجمالي الوزن بالطن (مثال: 1.440)',
        'الكمية المتوقعة لنهاية الشهر بالكرتونة (EXP)',
        'القيمة المتوقعة لنهاية الشهر بالجنيه (EXP EGP)',
      ],
      [
        2026,
        1,
        'يناير',
        'Full Month',
        'أسواق فتح الله (Fathalla Market)',
        'ALX',
        'الاسكندرية',
        'فرع سموحة الرئيسي',
        'المنظفات',
        'العلامة الأولى',
        'منظف أطباق سائل',
        '622100000101',
        'منظف أطباق مركز 4 لتر × 4 عبوة',
        'عادي',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'أحمد محمود حسن',
        120,
        57600.00,
        1.440,
        120,
        57600.00,
      ],
      [
        2026,
        1,
        'يناير',
        'Full Month',
        'بيت الجملة (Beet El Gomla)',
        'ALX',
        'الاسكندرية',
        'فرع مصطفى كامل',
        'المنظفات',
        'العلامة الأولى',
        'مطهر ومنظف أرضيات',
        '622100000102',
        'مطهر عام برائحة الصنوبر 2 لتر × 6 عبوة',
        'عرض',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'محمد سعيد إبراهيم',
        95,
        42750.00,
        1.140,
        105,
        47250.00,
      ],
      [
        2026,
        1,
        'يناير',
        'Full Month',
        'جملة ماركت (Gomla Market)',
        'CIR',
        'القاهرة الكبرى',
        'فرع مدينة نصر',
        'المنظفات',
        'العلامة الثانية',
        'منعم أقمشة',
        '622100000103',
        'منعم ومعطر ملابس 2 لتر × 6 عبوة',
        'عادي',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'كريم عادل فتحي',
        80,
        38400.00,
        0.960,
        85,
        40800.00,
      ],
      [
        2026,
        7,
        'يوليو',
        'Full Month',
        'الوكالة (El Wakala)',
        'ALX',
        'الاسكندرية',
        'المخزن الرئيسي - الوكالة',
        'المنظفات',
        'العلامة الأولى',
        'منظف أطباق سائل',
        '622100000104',
        'سائل تنظيف أطباق عبوة اقتصادية 3 لتر × 4',
        'عادي',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'طارق عبد الرحمن',
        210,
        96600.00,
        2.520,
        225,
        103500.00,
      ],
      [
        2026,
        10,
        'أكتوبر',
        'W2',
        'أسواق فتح الله (Fathalla Market)',
        'TNT',
        'الغربية',
        'فرع طنطا',
        'المنظفات',
        'العلامة الأولى',
        'جل غسيل أوتوماتيك',
        '622100000105',
        'جل غسيل ملابس أوتوماتيك 3 لتر × 4 عبوة',
        'عرض',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'ياسر كمال الشناوي',
        65,
        35100.00,
        0.780,
        130,
        70200.00,
      ],
      [
        2026,
        10,
        'أكتوبر',
        'W2',
        'بيت الجملة (Beet El Gomla)',
        'BHR',
        'البحيرة',
        'فرع دمنهور',
        'المنظفات',
        'العلامة الثانية',
        'ملمع زجاج',
        '622100000106',
        'ملمع زجاج وأسطح بخاخ 700 مل × 12 عبوة',
        'مرتجع',
        'مدير قطاع التجزئة',
        'مسؤول حسابات السلاسل',
        'عمرو نبيل فؤاد',
        -5,
        -2100.00,
        -0.050,
        0,
        0.00,
      ],
    ];

    final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
    const filename = 'Tashil_CPFR_Sell_In_Guided_Demo_Template.csv';
    ExcelExportService.downloadCsv(filename, csv);

    M3Feedback.showSuccess(
      context,
      'تم تحميل النموذج الإرشادي لبيانات التوريد ($filename) بنجاح',
    );
  }

  void _downloadSellOutGuidedDemoTemplate() {
    const headers = [
      'تاريخ الحركة أو الشهر (Transaction_Date)',
      'سلسلة التجزئة (Retail_Chain)',
      'اسم الفرع (Branch_Name)',
      'الباركود (Barcode)',
      'اسم الصنف (SKU_Name)',
      'الفئة أو القطاع (Category)',
      'اسم الشركة أو المورد (Supplier_Brand)',
      'الكمية المباعة بالقطعة (Sell_Out_Units)',
      'صافي قيمة مبيعات الكاشير بالجنيه (Sell_Out_Revenue_EGP)',
      'سعر بيع الوحدة للمستهلك (Unit_Price_EGP)',
      'الرصيد الفعلي بالفرع إن وجد (On_Hand_Stock_Units)',
    ];

    final rows = <List<dynamic>>[
      [
        'سطر إرشادي (يرفع هذا الملف في صفحة Upload للسلسلة المختارة)',
        'اسم السلسلة (فتح الله / بيت الجملة / جملة ماركت / الوكالة)',
        'اسم فرع السلسلة',
        'الباركود الدولي أو كود الصنف',
        'اسم المنتج كما يظهر في كاشير السلسلة',
        'المنظفات / الأغذية / المشروبات / إلخ',
        'اسم الشركة الموردة',
        'إجمالي القطع المباعة فعلياً من الكاشير',
        'إجمالي قيمة البيع الفعلي بالجنيه (Sell-Out EGP)',
        'سعر الوحدة على الكاشير',
        'الرصيد المتبقي بالفرع (لرصد النواقص OOS والفجوة)',
      ],
      [
        '2026-01-31',
        'أسواق فتح الله (Fathalla Market)',
        'سموحة',
        '622100000101',
        'منظف أطباق مركز 4 لتر',
        'المنظفات',
        'اسم الشركة الموردة',
        450,
        54000.00,
        120.00,
        30,
      ],
      [
        '2026-01-31',
        'بيت الجملة (Beet El Gomla)',
        'مصطفى كامل',
        '622100000102',
        'مطهر عام برائحة الصنوبر 2 لتر',
        'المنظفات',
        'اسم الشركة الموردة',
        520,
        39000.00,
        75.00,
        50,
      ],
      [
        '2026-07-31',
        'الوكالة (El Wakala)',
        'الفرع الرئيسي',
        '622100000104',
        'سائل تنظيف أطباق عبوة اقتصادية 3 لتر',
        'المنظفات',
        'اسم الشركة الموردة',
        780,
        89700.00,
        115.00,
        60,
      ],
    ];

    final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
    const filename = 'Tashil_CPFR_Sell_Out_Guided_Demo_Template.csv';
    ExcelExportService.downloadCsv(filename, csv);

    M3Feedback.showSuccess(
      context,
      'تم تحميل النموذج الإرشادي لبيانات مبيعات الكاشير ($filename) بنجاح',
    );
  }

  void _showRequiredDataGuideModal() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.menu_book_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'دليل البيانات المطلوبة لمحرك CPFR (Sell-In & Sell-Out)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.titleMediumPlus),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'يعمل نظام CPFR بشكل موحد لجميع الشركات وجميع سلاسل التجزئة من خلال مطابقة ملفين أساسيين:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildGuideSectionCard(
                  theme: theme,
                  colorScheme: colorScheme,
                  icon: Icons.local_shipping_rounded,
                  title:
                      '1. ملف التوريد والتنبؤ (Sell-In File) — يُرفع مباشرة هنا في صفحة CPFR',
                  items: const [
                    '• الفترة والسلسلة: السنة (Year)، الشهر (Month)، حالة الفترة (Full Month أو W1/W2)، واسم سلسلة التجزئة (Retail_Chain).',
                    '• التوزيع الجغرافي: كود الإقليم (Region_Code)، المحافظة (Governorate)، واسم الفرع أو المخزن (Branch_Name).',
                    '• بيانات الصنف: القطاع السلعي (Sector مثل المنظفات أو الأغذية)، العلامة التجارية (Brand)، الباركود، واسم الصنف (Item_Name).',
                    '• كميات وقيم التوريد: كمية التوريد بالكرتونة (Sell_In_Cases)، صافي قيمة التوريد بالجنيه (Sell_In_Value_EGP)، والوزن بالطن (Weight_Tons).',
                    '• التنبؤ وهيكل المبيعات: المتوقع بنهاية الشهر بالكرتونة والقيمة (Expected EXP)، نوع الحركة (عادي / عرض / مرتجع)، واسم المندوب ومسؤول السلسلة.',
                  ],
                ),
                const SizedBox(height: 12),
                _buildGuideSectionCard(
                  theme: theme,
                  colorScheme: colorScheme,
                  icon: Icons.point_of_sale_rounded,
                  title:
                      '2. ملف المبيعات الفعلية للكاشير (Sell-Out File) — يُرفع في صفحة Upload لكل سلسلة',
                  items: const [
                    '• اسم السلسلة والفرع (Branch Name) وتاريخ/شهر المبيعات.',
                    '• كود أو باركود الصنف (Barcode) واسم الصنف (SKU Name) والفئة.',
                    '• الكمية المباعة فعلياً للمستهلك (Sell-Out Units) وصافي قيمة مبيعات الكاشير بالجنيه (Sell-Out Revenue EGP).',
                  ],
                ),
                const SizedBox(height: 12),
                _buildGuideSectionCard(
                  theme: theme,
                  colorScheme: colorScheme,
                  icon: Icons.calculate_rounded,
                  title: '3. المعادلات والمؤشرات التي يحسبها النظام تلقائياً',
                  items: const [
                    '• معدل دوران المخزون (Sell-Through Rate %): (مبيعات الكاشير Sell-Out ÷ صافي التوريد Sell-In) × 100.',
                    '• الفجوة المخزنية والرصيد المرحّل (Inventory Gap): صافي التوريد (Sell-In) - مبيعات الكاشير (Sell-Out) - المرتجعات.',
                    '• الوزن المورد بالطن (Weight Tons): إجمالي أوزان الشحنات الموردة للسلسلة بالطن ومتوسط وزن الكرتونة.',
                    '• المتوقع بنهاية الشهر (Projected EXP): التنبؤ بإغلاق الشهر بناءً على مسحوبات الأسابيع الأولى (W1 + W2 Run-Rate).',
                    '• أمر التوريد المقترح (Suggested PO): [(مهلة التوريد Lead Time + حد الأمان Safety Stock) × معدل السحب اليومي] - الرصيد التقديري الحالي.',
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadSellOutGuidedDemoTemplate();
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تحميل نموذج Sell-Out (Demo)'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadSellInGuidedDemoTemplate();
            },
            icon: const Icon(Icons.download_for_offline_rounded, size: 18),
            label: const Text('تحميل نموذج Sell-In الإرشادي (Demo)'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSectionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                item,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
        ],
      ),
    );
  }

  String _selectedChainDisplayName() {
    if (_selectedChain == 'all' || _selectedChain.isEmpty) {
      return 'جميع السلاسل';
    }
    for (final c in _companyChains) {
      if (c.code.toLowerCase() == _selectedChain.toLowerCase()) {
        return c.displayName;
      }
    }
    return ApiClient.getRetailChainDisplayName(_selectedChain);
  }

  void _exportReplenishmentPOExcel(CPFRDashboardModel d) {
    const headers = ExportColumns.cpfrReplenishment;

    final rows = d.inventoryAndPoItems
        .where((item) => item.suggestedPoCases > 0)
        .map((item) => [
              item.skuName,
              item.brand,
              item.sector,
              item.regionCode,
              item.governorate,
              item.salesRep,
              item.sellInCases.toStringAsFixed(2),
              item.sellOutEstCases.toStringAsFixed(2),
              item.returnCases.toStringAsFixed(2),
              item.estimatedStockCases.toStringAsFixed(2),
              item.estimatedStockValueEgp.toStringAsFixed(2),
              item.dailyRunRateCases.toStringAsFixed(2),
              item.daysOfInventory.toStringAsFixed(1),
              item.stockStatusAr,
              item.suggestedPoCases,
              item.suggestedPoValueEgp.toStringAsFixed(2),
              item.suggestedPoTons.toStringAsFixed(3),
            ])
        .toList();

    final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final chainSlug = _selectedChain == 'all' ? 'All_Chains' : _selectedChain;
    final filename =
        'Tashil_Suggested_Replenishment_PO_${chainSlug}_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csv);

    widget.apiClient.recordAuditLog(
      action: 'EXPORT_EXCEL',
      resource: filename,
      details:
          'تصدير أمر توريد مقترح ذكي (${rows.length} صنف بإجمالي ${d.totalSuggestedPoCases} كرتونة - ${CurrencyFormatter.formatCompactEGP(d.totalSuggestedPoEgp)})',
    );

    M3Feedback.showSuccess(
      context,
      'تم تصدير أمر التوريد المقترح ($filename) بنجاح (${rows.length} صنف)',
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
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: M3Spacing.md),
            _buildSellInIngestionAndTemplateCard(theme, colorScheme),
            const SizedBox(height: M3Spacing.md),
            _buildTopControlBar(theme, colorScheme),
            const SizedBox(height: M3Spacing.lg),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorCard(theme, colorScheme)
            else if (_data != null) ...[
              _buildTabSelector(theme, colorScheme),
              const SizedBox(height: M3Spacing.lg),
              if (_activeTab == 0)
                _buildReconciliationTab(theme, colorScheme, _data!),
              if (_activeTab == 1)
                _buildInventoryAndPOTab(theme, colorScheme, _data!),
              if (_activeTab == 2)
                _buildForecastAndPromosTab(theme, colorScheme, _data!),
              if (_activeTab == 3)
                _buildSalesRepsTab(theme, colorScheme, _data!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return M3PageHeader(
      titleEn: 'CPFR & Inventory Replenishment',
      subtitleAr:
          'منظومة التخطيط المشترك ومطابقة التوريد (Sell-In) مع مبيعات الكاشير (Sell-Out) وحساب دوران المخزون وأوامر التوريد لجميع السلاسل',
      actions: M3ActionButtonGroup(
        actions: [
          M3ActionItem(
            label: 'نموذج التوريد الإرشادي',
            icon: Icons.download_for_offline_rounded,
            onPressed: _downloadSellInGuidedDemoTemplate,
          ),
          M3ActionItem(
            label: 'رفع ملف Sell-In',
            icon: Icons.upload_file_rounded,
            isLoading: _isUploadingSellIn,
            onPressed: _isUploadingSellIn ? null : _pickAndUploadSellInFile,
          ),
          M3ActionItem(
            label: 'تحديث التوريد',
            icon: Icons.sync_rounded,
            isLoading: _isReloadingWorkbook,
            onPressed: _isReloadingWorkbook ? null : _reloadSellInWorkbook,
          ),
          if (_data != null)
            M3ActionItem(
              label: 'تصدير PO',
              icon: Icons.shopping_cart_checkout_rounded,
              isPrimary: true,
              onPressed: () => _exportReplenishmentPOExcel(_data!),
            ),
        ],
      ),
    );
  }

  /// Dedicated CPFR Sell-In Upload & Guided Demo Template Card directly inside the CPFR page.
  Widget _buildSellInIngestionAndTemplateCard(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final activeFile = _lastUploadedSellInFilename ??
        (_data?.sourceFilename.isNotEmpty == true
            ? _data!.sourceFilename
            : 'CPFR_MultiChain_Sell_In_Reconciliation.xlsx');

    return Container(
      padding: const EdgeInsets.all(M3Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.22),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.primary.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: M3Spacing.md,
            runSpacing: M3Spacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.14),
                      borderRadius: M3Shape.radiusMd,
                    ),
                    child: Icon(
                      Icons.cloud_upload_rounded,
                      color: colorScheme.primary,
                      size: 22.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Text(
                    'بوابة رفع بيانات التوريد Sell-In',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Target chain selector for Sell-In upload
                  M3Dropdown<String?>(
                    value:
                        _companyChains.any((c) => c.code == _uploadTargetChain)
                            ? _uploadTargetChain
                            : (_companyChains.isNotEmpty
                                ? _companyChains.first.code
                                : null),
                    hint: 'اختر سلسلة التجزئة',
                    options: m3OptionsFromMenuItems<String?>([
                      for (final chain in _companyChains)
                        DropdownMenuItem(
                          value: chain.code,
                          child: Text(chain.displayName),
                        ),
                    ]),
                    onChanged: m3Legacy<String?>((val) {
                      if (val == null) return;
                      setState(() => _uploadTargetChain = val);
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadSellInGuidedDemoTemplate,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Demo Sell-In'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadSellOutGuidedDemoTemplate,
                    icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                    label: const Text('Demo Sell-Out'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(
                          () => _showDataGuideBanner = !_showDataGuideBanner);
                    },
                    icon: Icon(
                      _showDataGuideBanner
                          ? Icons.expand_less_rounded
                          : Icons.help_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('ما هي البيانات المطلوبة؟'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          // Independent standalone row for the Sell-In Upload Action Button
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isUploadingSellIn ? null : _pickAndUploadSellInFile,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 22.0,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: M3Shape.radiusSm,
                  ),
                ),
                icon: _isUploadingSellIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 20),
                label: const Text(
                  'رفع ملف Sell-In هنا',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: M3FontSize.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(width: 12.0),
              Flexible(
                child: Text(
                  'اختر ملف التوريد الخاص بالسلسلة المحددة لمطابقته الفورية مع مبيعات الكاشير وحساب الفجوة المخزنية',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10.0),
          Wrap(
            spacing: 16.0,
            runSpacing: 6.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'مصدر بيانات التوريد النشط: $activeFile (${_data?.totalRecords ?? 0} سجل)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showRequiredDataGuideModal,
                child: Text(
                  'عرض جدول مواصفات الحقول والمعادلات بالكامل',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          if (_showDataGuideBanner) ...[
            const SizedBox(height: M3Spacing.sm),
            const Divider(),
            const SizedBox(height: M3Spacing.xs),
            Wrap(
              spacing: M3Spacing.md,
              runSpacing: M3Spacing.sm,
              children: [
                _buildCompactSpecChip(
                  theme,
                  colorScheme,
                  '1. التوريد (Sell-In)',
                  'السنة، الشهر، السلسلة، الإقليم، الصنف، الكراتين (Cases)، القيمة (EGP)، الوزن (Tons)، المتوقع (EXP)',
                ),
                _buildCompactSpecChip(
                  theme,
                  colorScheme,
                  '2. مبيعات الكاشير (Sell-Out)',
                  'التاريخ، السلسلة، الفرع، الباركود، الصنف، الكمية المباعة بالقطعة، صافي مبيعات الكاشير (EGP)',
                ),
                _buildCompactSpecChip(
                  theme,
                  colorScheme,
                  '3. مخرجات النظام التلقائية',
                  'معدل دوران المخزون (STR %) • الوزن بالطن • المتوقع (EXP) • الفجوة المخزنية • أوامر التوريد (PO)',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSpecChip(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    String desc,
  ) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.85),
        borderRadius: M3Shape.radiusSm,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControlBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: M3Spacing.md,
        vertical: M3Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Wrap(
        spacing: M3Spacing.md,
        runSpacing: M3Spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 1. Multi-Chain Filter (سلسلة التجزئة)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_rounded,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'سلسلة التجزئة:',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          M3Dropdown<String>(
            value: _companyChains.any((c) => c.code == _selectedChain) ||
                    _selectedChain == 'all'
                ? _selectedChain
                : 'all',
            options: m3OptionsFromMenuItems<String>([
              DropdownMenuItem(
                value: 'all',
                child: Text(
                  'جميع السلاسل (${_companyChains.isNotEmpty ? _companyChains.length : 4})',
                ),
              ),
              for (final chain in _companyChains)
                DropdownMenuItem(
                  value: chain.code,
                  child: Text(chain.displayName),
                ),
            ]),
            onChanged: m3Legacy<String>((val) {
              if (val == null || _selectedChain == val) return;
              setState(() => _selectedChain = val);
              _loadDashboard();
            }),
          ),

          const SizedBox(width: M3Spacing.sm),

          // 2. Product Sector Filter (القطاع السلعي)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'القطاع السلعي:',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          M3SegmentedButtonGroup<String>(
            selectedValue: _selectedSector,
            segments: const [
              M3SegmentItem(
                value: 'all',
                label: 'الكل',
                icon: Icons.dashboard_customize_rounded,
              ),
              M3SegmentItem(
                value: 'MT',
                label: 'المنظفات والعناية المنزلية',
                icon: Icons.cleaning_services_rounded,
              ),
              M3SegmentItem(
                value: 'CC',
                label: 'العناية المتخصصة',
                icon: Icons.category_rounded,
              ),
            ],
            onSelectionChanged: (sector) {
              if (_selectedSector != sector) {
                setState(() => _selectedSector = sector);
                _loadDashboard();
              }
            },
          ),

          const SizedBox(width: M3Spacing.sm),

          // 3. Region Filter (الإقليم)
          Text(
            'الإقليم:',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          M3Dropdown<String>(
            value: _selectedRegion,
            options: m3OptionsFromMenuItems<String>([
              const DropdownMenuItem(value: 'all', child: Text('جميع الأقاليم')),
              const DropdownMenuItem(
                  value: 'ALX', child: Text('ALX - الإسكندرية ومطروح')),
              const DropdownMenuItem(
                  value: 'CIR', child: Text('CIR - القاهرة الكبرى')),
              const DropdownMenuItem(
                  value: 'TNT', child: Text('TNT - الغربية (طنطا)')),
              const DropdownMenuItem(value: 'BHR', child: Text('BHR - البحيرة')),
              const DropdownMenuItem(
                  value: 'MNS', child: Text('MNS - المنصورة والدلتا')),
            ]),
            onChanged: m3Legacy<String>((val) {
              if (val == null) return;
              setState(() => _selectedRegion = val);
              _loadDashboard();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(ThemeData theme, ColorScheme colorScheme) {
    final tabs = [
      (
        0,
        Icons.compare_arrows_rounded,
        '1. Sell-In vs Sell-Out',
      ),
      (
        1,
        Icons.calculate_rounded,
        '2. Suggested PO & Replenishment',
      ),
      (
        2,
        Icons.trending_up_rounded,
        '3. Demand Forecasting & Promos (EXP)',
      ),
      (
        3,
        Icons.badge_rounded,
        '4. أداء فريق المبيعات وهيكل الحسابات',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        final isTablet =
            constraints.maxWidth >= 600 && constraints.maxWidth < 960;

        if (isDesktop) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: M3Spacing.sm),
                  Expanded(
                    child: _buildTabButton(
                      theme: theme,
                      colorScheme: colorScheme,
                      tabIndex: tabs[i].$1,
                      icon: tabs[i].$2,
                      title: tabs[i].$3,
                      isSelected: _activeTab == tabs[i].$1,
                    ),
                  ),
                ],
              ],
            ),
          );
        } else if (isTablet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        theme: theme,
                        colorScheme: colorScheme,
                        tabIndex: tabs[0].$1,
                        icon: tabs[0].$2,
                        title: tabs[0].$3,
                        isSelected: _activeTab == tabs[0].$1,
                      ),
                    ),
                    const SizedBox(width: M3Spacing.sm),
                    Expanded(
                      child: _buildTabButton(
                        theme: theme,
                        colorScheme: colorScheme,
                        tabIndex: tabs[1].$1,
                        icon: tabs[1].$2,
                        title: tabs[1].$3,
                        isSelected: _activeTab == tabs[1].$1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: M3Spacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        theme: theme,
                        colorScheme: colorScheme,
                        tabIndex: tabs[2].$1,
                        icon: tabs[2].$2,
                        title: tabs[2].$3,
                        isSelected: _activeTab == tabs[2].$1,
                      ),
                    ),
                    const SizedBox(width: M3Spacing.sm),
                    Expanded(
                      child: _buildTabButton(
                        theme: theme,
                        colorScheme: colorScheme,
                        tabIndex: tabs[3].$1,
                        icon: tabs[3].$2,
                        title: tabs[3].$3,
                        isSelected: _activeTab == tabs[3].$1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(height: M3Spacing.sm),
                _buildTabButton(
                  theme: theme,
                  colorScheme: colorScheme,
                  tabIndex: tabs[i].$1,
                  icon: tabs[i].$2,
                  title: tabs[i].$3,
                  isSelected: _activeTab == tabs[i].$1,
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildTabButton({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int tabIndex,
    required IconData icon,
    required String title,
    required bool isSelected,
  }) {
    return InkWell(
      borderRadius: M3Shape.radiusMd,
      onTap: () => setState(() => _activeTab = tabIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: M3Shape.radiusMd,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18.0,
              color: isSelected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8.0),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveCardGrid(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int columns;
        if (width >= 1050) {
          columns = cards.length <= 5 ? cards.length : 4;
        } else if (width >= 680) {
          columns = 2;
        } else {
          columns = 1;
        }

        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          final chunk = cards.sublist(i, (i + columns).clamp(0, cards.length));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < chunk.length; j++) ...[
                    if (j > 0) const SizedBox(width: M3Spacing.md),
                    Expanded(child: chunk[j]),
                  ],
                  for (var k = chunk.length; k < columns; k++) ...[
                    const SizedBox(width: M3Spacing.md),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
          if (i + columns < cards.length) {
            rows.add(const SizedBox(height: M3Spacing.md));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  // ===========================================================================
  // TAB 1: SELL-IN VS SELL-OUT RECONCILIATION
  // ===========================================================================
  Widget _buildReconciliationTab(
    ThemeData theme,
    ColorScheme colorScheme,
    CPFRDashboardModel d,
  ) {
    final chainLabel = _selectedChainDisplayName();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Spotlight KPI Cards for Multi-Chain / Selected Chain Reconciliation
        _buildResponsiveCardGrid([
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'إجمالي التوريد للسلاسل',
            titleEn: 'Sell-In',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026SellInEgp),
            subtitle:
                'القيمة الدقيقة: ${CurrencyFormatter.formatEGP(d.jan2026SellInEgp)}',
            icon: Icons.local_shipping_rounded,
            accentColor: colorScheme.primary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'مبيعات الكاشير الفعلية',
            titleEn: 'Sell-Out',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026SellOutEgp),
            subtitle:
                'القيمة الدقيقة: ${CurrencyFormatter.formatEGP(d.jan2026SellOutEgp)}',
            icon: Icons.point_of_sale_rounded,
            accentColor: colorScheme.secondary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'معدل دوران المخزون',
            titleEn: 'Sell-Through Rate',
            value: '${d.jan2026SellThroughPct.toStringAsFixed(1)}%',
            subtitle:
                'نسبة تصريف المبيعات الفعلية مقابل التوريد (المعيار القياسي 85%)',
            icon: Icons.autorenew_rounded,
            accentColor: colorScheme.primary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'الفجوة المخزنية والرصيد المرحّل',
            titleEn: 'Inventory Gap',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026GapEgp),
            subtitle:
                'فرق التوريد عن البيع (${CurrencyFormatter.formatEGP(d.jan2026GapEgp)})',
            icon: Icons.warehouse_rounded,
            accentColor: colorScheme.tertiary,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // YTD Multi-Chain Summary Strip
        Container(
          padding: const EdgeInsets.all(M3Spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border:
                Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Wrap(
            spacing: M3Spacing.xl,
            runSpacing: M3Spacing.sm,
            alignment: WrapAlignment.spaceAround,
            children: [
              _buildMiniStat(
                theme,
                'إجمالي التوريد الفعلي (YTD Sell-In)',
                CurrencyFormatter.formatCompactEGP(d.ytd2026SellInEgp),
              ),
              _buildMiniStat(
                theme,
                'إجمالي الكراتين الموردة',
                '${CurrencyFormatter.formatUnits(d.ytd2026SellInCases.round())} كرتونة',
              ),
              _buildMiniStat(
                theme,
                'إجمالي الأوزان الموردة (الوزن بالطن)',
                '${d.ytd2026WeightTons.toStringAsFixed(1)} طن',
              ),
              _buildMiniStat(
                theme,
                'المتوقع بنهاية الفترة (Forecast EXP)',
                CurrencyFormatter.formatCompactEGP(d.ytd2026ExpectedEgp),
              ),
              _buildMiniStat(
                theme,
                'عدد الأصناف النشطة بالسلاسل',
                '${d.activeSkusCount} صنف نشط',
              ),
            ],
          ),
        ),
        const SizedBox(height: M3Spacing.lg),

        // Monthly Reconciliation DataTable
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side:
                BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'جدول مطابقة التوريد الشهري مع البيع الفعلي (Sell-In vs. Sell-Out Reconciliation) — $chainLabel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'يوضح مطابقة كميات وقيم التوريد (Sell-In) بالكرتونة والعملة والوزن بالطن مقابل المبيعات الفعلية للكاشير (Sell-Out) والفجوة المخزنية ومعدل الدوران والمتوقع (EXP)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          // Scrolls toward the reading start (right in RTL,
                          // left in LTR); the chevron mirrors automatically.
                          message: 'تمرير الجدول للبداية',
                          child: IconButton.outlined(
                            key: const ValueKey('cpfr_scroll_start'),
                            icon: const Icon(AppIcons.chevronStart, size: 18),
                            onPressed: () {
                              if (_reconciliationTableScrollController
                                  .hasClients) {
                                _reconciliationTableScrollController.animateTo(
                                  (_reconciliationTableScrollController.offset -
                                          300)
                                      .clamp(
                                    0.0,
                                    _reconciliationTableScrollController
                                        .position.maxScrollExtent,
                                  ),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'تمرير الجدول للنهاية',
                          child: IconButton.outlined(
                            key: const ValueKey('cpfr_scroll_end'),
                            icon: const Icon(AppIcons.chevronEnd, size: 18),
                            onPressed: () {
                              if (_reconciliationTableScrollController
                                  .hasClients) {
                                _reconciliationTableScrollController.animateTo(
                                  (_reconciliationTableScrollController.offset +
                                          300)
                                      .clamp(
                                    0.0,
                                    _reconciliationTableScrollController
                                        .position.maxScrollExtent,
                                  ),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.md),
                Scrollbar(
                  controller: _reconciliationTableScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: _reconciliationTableScrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1450),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        ),
                        columns: const [
                          DataColumn(label: Text('الشهر')),
                          DataColumn(label: Text('حالة الفترة')),
                          DataColumn(
                              label: Text('الأصناف النشطة'), numeric: true),
                          DataColumn(
                              label: Text('رصيد أول الشهر'), numeric: true),
                          DataColumn(
                              label: Text('التوريد (كرتونة)'), numeric: true),
                          DataColumn(
                              label: Text('قيمة التوريد (Sell-In)'),
                              numeric: true),
                          DataColumn(
                              label: Text('مبيعات الكاشير (Sell-Out)'),
                              numeric: true),
                          DataColumn(
                              label: Text('صافي حركة الشهر'), numeric: true),
                          DataColumn(
                              label: Text('الرصيد المتبقي آخر الشهر'),
                              numeric: true),
                          DataColumn(
                              label: Text('معدل الدوران (STR %)'),
                              numeric: true),
                          DataColumn(label: Text('الوزن (طن)'), numeric: true),
                          DataColumn(
                              label: Text('المتوقع بنهاية الشهر (EXP)'),
                              numeric: true),
                        ],
                        rows: d.monthlyReconciliation.map((m) {
                          final isJan = m.monthNum == 1;
                          final isOct = m.monthNum == 10;
                          return DataRow(
                            color: isJan
                                ? WidgetStateProperty.all(colorScheme
                                    .primaryContainer
                                    .withOpacity(0.22))
                                : (isOct
                                    ? WidgetStateProperty.all(colorScheme
                                        .tertiaryContainer
                                        .withOpacity(0.22))
                                    : null),
                            cells: [
                              DataCell(Text(
                                '${m.monthNum} - ${m.monthAr} (${m.monthEn}) ${m.year}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              )),
                              DataCell(_buildBadge(
                                m.periodStatus,
                                isOct
                                    ? colorScheme.tertiary
                                    : colorScheme.secondary,
                              )),
                              DataCell(Text('${m.activeSkusCount}')),
                              DataCell(Text(
                                '${CurrencyFormatter.formatNumber(m.openingStockCases.round())} كرتونة',
                                style: TextStyle(
                                  fontSize: M3FontSize.bodySmall,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )),
                              DataCell(Text(m.sellInCases.toStringAsFixed(1))),
                              DataCell(Text(
                                CurrencyFormatter.formatEGP(m.sellInValueEgp),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              )),
                              DataCell(Text(
                                CurrencyFormatter.formatEGP(m.sellOutValueEgp),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.secondary,
                                ),
                              )),
                              DataCell(Text(
                                CurrencyFormatter.formatEGP(
                                    m.monthlyNetValueEgp),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.tertiary,
                                ),
                              )),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatEGP(
                                          m.closingStockValueEgp),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    Text(
                                      '${CurrencyFormatter.formatNumber(m.closingStockCases.round())} كرتونة',
                                      style: TextStyle(
                                        fontSize: M3FontSize.labelSmall,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(_buildBadge(
                                '${m.sellThroughRatePct.toStringAsFixed(1)}%',
                                m.sellThroughRatePct >= 85
                                    ? colorScheme.primary
                                    : colorScheme.tertiary,
                              )),
                              DataCell(Text(
                                  '${m.weightTons.toStringAsFixed(1)} طن')),
                              DataCell(Text(
                                CurrencyFormatter.formatEGP(m.expectedValueEgp),
                                style: TextStyle(
                                  fontWeight: isOct
                                      ? FontWeight.w800
                                      : FontWeight.normal,
                                  color: isOct ? colorScheme.primary : null,
                                ),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: ESTIMATED INVENTORY & SMART REPLENISHMENT PO GENERATOR
  // ===========================================================================
  Widget _buildInventoryAndPOTab(
    ThemeData theme,
    ColorScheme colorScheme,
    CPFRDashboardModel d,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Interactive Replenishment Parameters Bar (Lead Time & Safety Stock)
        Container(
          padding: const EdgeInsets.all(M3Spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.35),
            borderRadius: M3Shape.radiusLg,
            border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
          ),
          child: Wrap(
            spacing: M3Spacing.lg,
            runSpacing: M3Spacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'خيارات بيع الأرصدة ومعاملات أوامر التوريد التلقائية:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('مهلة التوريد (Lead Time): '),
                  M3Dropdown<int>(
                    value: _leadTimeDays,
                    options: m3OptionsFromMenuItems<int>([
                      const DropdownMenuItem(value: 2, child: Text('يومان (2 Days)')),
                      const DropdownMenuItem(value: 4, child: Text('4 أيام (قياسي)')),
                      const DropdownMenuItem(value: 7, child: Text('7 أيام')),
                      const DropdownMenuItem(value: 10, child: Text('10 أيام')),
                    ]),
                    onChanged: m3Legacy<int>((v) {
                      if (v == null) return;
                      setState(() => _leadTimeDays = v);
                      _loadDashboard();
                    }),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('حد الأمان (Safety Stock): '),
                  M3Dropdown<int>(
                    value: _safetyStockDays,
                    options: m3OptionsFromMenuItems<int>([
                      const DropdownMenuItem(value: 5, child: Text('5 أيام')),
                      const DropdownMenuItem(
                          value: 7, child: Text('7 أيام (موصى به)')),
                      const DropdownMenuItem(value: 10, child: Text('10 أيام')),
                      const DropdownMenuItem(value: 14, child: Text('14 يوماً')),
                    ]),
                    onChanged: m3Legacy<int>((v) {
                      if (v == null) return;
                      setState(() => _safetyStockDays = v);
                      _loadDashboard();
                    }),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تصفية الحالة: '),
                  M3Dropdown<String>(
                    value: _selectedStockStatus,
                    options: m3OptionsFromMenuItems<String>([
                      const DropdownMenuItem(
                          value: 'all', child: Text('جميع الأصناف')),
                      const DropdownMenuItem(
                        value: 'urgent_replenishment',
                        child: Text('خطر نفاد عاجل (يحتاج توريد فوري)'),
                      ),
                      const DropdownMenuItem(
                          value: 'optimal', child: Text('رصيد آمن ومثالي')),
                      const DropdownMenuItem(
                          value: 'overstock', child: Text('تكدس مخزني')),
                    ]),
                    onChanged: m3Legacy<String>((v) {
                      if (v == null) return;
                      setState(() => _selectedStockStatus = v);
                      _loadDashboard();
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: M3Spacing.md),

        // KPI Summary Cards for Estimated Stock & Suggested PO
        _buildResponsiveCardGrid([
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'إجمالي الرصيد التقديري الحالي بالفروع',
            value:
                '${CurrencyFormatter.formatUnits(d.totalEstimatedStockCases.round())} كرتونة',
            subtitle:
                'بقيمة تقديرية: ${CurrencyFormatter.formatCompactEGP(d.totalEstimatedStockEgp)}',
            icon: Icons.inventory_rounded,
            accentColor: colorScheme.primary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'إجمالي أوامر التوريد المقترحة \u200E(Suggested PO)\u200E',
            value:
                '${CurrencyFormatter.formatUnits(d.totalSuggestedPoCases)} كرتونة',
            subtitle:
                'بقيمة: ${CurrencyFormatter.formatCompactEGP(d.totalSuggestedPoEgp)} (${d.totalSuggestedPoTons.toStringAsFixed(1)} طن)',
            icon: Icons.add_shopping_cart_rounded,
            accentColor: colorScheme.secondary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'أصناف تحتاج أمر توريد عاجل',
            value: '${d.urgentReplenishmentCount} صنف/إقليم',
            subtitle: 'رصيدها يغطي أقل من مهلة التوريد + حد الأمان',
            icon: Icons.notification_important_rounded,
            accentColor: colorScheme.error,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'خيارات تصريف التكدس المخزني \u200E(Overstock)\u200E',
            value: '${d.overstockAlertCount} صنف/إقليم',
            subtitle:
                'تغطيتها تتجاوز 28 يوماً (يوصى بعمل عرض ترويجي لتصريف الرصيد)',
            icon: Icons.hourglass_bottom_rounded,
            accentColor: colorScheme.tertiary,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // SKU x Region Inventory & Suggested PO Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side:
                BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600.0
                  ? M3Spacing.md
                  : M3Spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12.0,
                  runSpacing: 10.0,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خيارات بيع الأرصدة وأوامر التوريد المقترحة لكل صنف وإقليم (Suggested Replenishment Orders)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'المعادلة: الرصيد التقديري = التوريد الفعلي - المبيعات الفعلية - المرتجعات | أمر التوريد = (مهلة التوريد $_leadTimeDays أيام + حد الأمان $_safetyStockDays أيام) × السحب اليومي - الرصيد التقديري',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    M3Button.primary(
                      label: 'تصدير PO',
                      icon: Icons.download_rounded,
                      onPressed: () => _exportReplenishmentPOExcel(d),
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  showSwipeHint: true,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: const [
                      DataColumn(label: Text('الصنف (SKU)')),
                      DataColumn(label: Text('العلامة / القطاع')),
                      DataColumn(label: Text('الإقليم')),
                      DataColumn(label: Text('المندوب المسند')),
                      DataColumn(
                          label: Text('التوريد (كرتونة)'), numeric: true),
                      DataColumn(
                          label: Text('المبيعات (كرتونة)'), numeric: true),
                      DataColumn(label: Text('الرصيد التقديري'), numeric: true),
                      DataColumn(
                          label: Text('السحب اليومي (ADR)'), numeric: true),
                      DataColumn(
                          label: Text('أيام التغطية (DOI)'), numeric: true),
                      DataColumn(label: Text('حالة المخزون')),
                      DataColumn(
                          label: Text('أمر التوريد المقترح (PO)'),
                          numeric: true),
                      DataColumn(
                          label: Text('قيمة أمر التوريد'), numeric: true),
                    ],
                    rows: d.inventoryAndPoItems.take(60).map((item) {
                      final isUrgent =
                          item.stockStatus == 'urgent_replenishment';
                      return DataRow(
                        cells: [
                          DataCell(SizedBox(
                            width: 210,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.skuName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.itemCode.isNotEmpty ||
                                    item.barcode.isNotEmpty)
                                  Text(
                                    '${item.itemCode.isNotEmpty ? item.itemCode : ""}${item.itemCode.isNotEmpty && item.barcode.isNotEmpty ? " • " : ""}${item.barcode}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: M3FontSize.tiny,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          )),
                          DataCell(Text('${item.brand} (${item.sector})')),
                          DataCell(
                              Text('${item.governorate} (${item.regionCode})')),
                          DataCell(Text(item.salesRep)),
                          DataCell(Text(item.sellInCases.toStringAsFixed(1))),
                          DataCell(
                              Text(item.sellOutEstCases.toStringAsFixed(1))),
                          DataCell(Text(
                            '${item.estimatedStockCases.toStringAsFixed(1)} ك',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )),
                          DataCell(Text(
                              '${item.dailyRunRateCases.toStringAsFixed(2)} ك/يوم')),
                          DataCell(Text(
                              '${item.daysOfInventory.toStringAsFixed(1)} يوم')),
                          DataCell(_buildBadge(
                            item.stockStatusAr,
                            isUrgent
                                ? colorScheme.error
                                : (item.stockStatus == 'overstock'
                                    ? colorScheme.tertiary
                                    : colorScheme.primary),
                          )),
                          DataCell(Text(
                            '${item.suggestedPoCases} كرتونة',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: item.suggestedPoCases > 0
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          )),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(
                                item.suggestedPoValueEgp),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: W1+W2 -> EXP FORECASTING & PROMOTIONS / RETURNS ANALYTICS
  // ===========================================================================
  Widget _buildForecastAndPromosTab(
    ThemeData theme,
    ColorScheme colorScheme,
    CPFRDashboardModel d,
  ) {
    final pr = d.promoAndReturns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // W1 + W2 -> EXP Forecasting Cards
        _buildResponsiveCardGrid([
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'المسحوبات الفعلية للفترة الحالية \u200E(W1 + W2)\u200E',
            value: CurrencyFormatter.formatCompactEGP(d.octW1W2ActualEgp),
            subtitle:
                '${CurrencyFormatter.formatUnits(d.octW1W2ActualCases.round())} كرتونة محققة فعلياً',
            icon: Icons.calendar_today_rounded,
            accentColor: colorScheme.primary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'محرك التنبؤ بنهاية الشهر \u200E(Projected EXP)\u200E',
            value:
                CurrencyFormatter.formatCompactEGP(d.octProjectedMonthEndEgp),
            subtitle:
                'متوقع إغلاق ${CurrencyFormatter.formatUnits(d.octProjectedCases.round())} كرتونة (معادلة Run-Rate)',
            icon: Icons.auto_graph_rounded,
            accentColor: colorScheme.tertiary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'مساهمة العروض الترويجية \u200E(Promotions)\u200E',
            value: CurrencyFormatter.formatCompactEGP(pr.promoValueEgp),
            subtitle:
                '${pr.promoValueSharePct.toStringAsFixed(1)}% من القيمة (${pr.promoRecordsCount} حركة عرض • ${pr.promoTons.toStringAsFixed(1)} طن)',
            icon: Icons.local_offer_rounded,
            accentColor: colorScheme.secondary,
          ),
          _buildKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            title: 'تحليل المرتجعات السالبة \u200E(Returns Rate)\u200E',
            value: '${pr.overallReturnPct.toStringAsFixed(2)}%',
            subtitle:
                '${pr.returnRecordsCount} سجل مرتجع (${pr.totalReturnCases.toStringAsFixed(1)} كرتونة • ${CurrencyFormatter.formatCompactEGP(pr.totalReturnValueEgp)})',
            icon: Icons.assignment_return_rounded,
            accentColor: colorScheme.error,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // Brand-Level Forecast & Sector Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side:
                BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'محرك التنبؤ وتحليل العلامات التجارية (Brand Performance & EXP Forecast)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  showSwipeHint: true,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: const [
                      DataColumn(label: Text('القطاع')),
                      DataColumn(label: Text('العلامة التجارية (Brand)')),
                      DataColumn(label: Text('عدد الأصناف'), numeric: true),
                      DataColumn(
                          label: Text('الكمية الفعلية (كرتونة)'),
                          numeric: true),
                      DataColumn(
                          label: Text('القيمة الفعلية (ج.م)'), numeric: true),
                      DataColumn(
                          label: Text('الكمية المتوقعة (EXP)'), numeric: true),
                      DataColumn(
                          label: Text('القيمة المتوقعة (EXP ج.م)'),
                          numeric: true),
                      DataColumn(label: Text('الوزن (طن)'), numeric: true),
                      DataColumn(
                          label: Text('الحصة من الإجمالي %'), numeric: true),
                    ],
                    rows: d.brandForecasts.map((b) {
                      final isCC = b.sector.toUpperCase() == 'CC';
                      return DataRow(
                        cells: [
                          DataCell(_buildBadge(
                            b.sector,
                            isCC ? colorScheme.tertiary : colorScheme.primary,
                          )),
                          DataCell(Text(
                            b.brand,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )),
                          DataCell(Text('${b.activeSkusCount}')),
                          DataCell(Text(b.actualCases.toStringAsFixed(1))),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(b.actualValueEgp),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )),
                          DataCell(Text(b.expectedCases.toStringAsFixed(1))),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(b.expectedValueEgp),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          )),
                          DataCell(
                              Text('${b.weightTons.toStringAsFixed(1)} طن')),
                          DataCell(
                              Text('${b.shareOfTotalPct.toStringAsFixed(1)}%')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.lg),

        // Top Returned Items Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side:
                BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أعلى الأصناف المرتجعة (السجلات السالبة - Returns Diagnostics)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  showSwipeHint: true,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: const [
                      DataColumn(label: Text('اسم الصنف')),
                      DataColumn(label: Text('العلامة التجارية')),
                      DataColumn(label: Text('الإقليم والمحافظة')),
                      DataColumn(label: Text('المندوب')),
                      DataColumn(
                          label: Text('كمية المرتجع (كرتونة)'), numeric: true),
                      DataColumn(
                          label: Text('قيمة المرتجع (ج.م)'), numeric: true),
                      DataColumn(label: Text('نسبة المرتجع %'), numeric: true),
                    ],
                    rows: pr.topReturnItems.take(15).map((ret) {
                      return DataRow(
                        cells: [
                          DataCell(Text(
                            ret.itemName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )),
                          DataCell(Text('${ret.brand} (${ret.sector})')),
                          DataCell(
                              Text('${ret.governorate} (${ret.regionCode})')),
                          DataCell(Text(ret.salesRep)),
                          DataCell(Text(
                            ret.returnCases.toStringAsFixed(2),
                            style: TextStyle(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          )),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(ret.returnValueEgp),
                            style: TextStyle(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          )),
                          DataCell(_buildBadge(
                            '${ret.returnRatePct.toStringAsFixed(1)}%',
                            colorScheme.error,
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: SALES TEAM & KEY ACCOUNT HIERARCHY TRACKING
  // ===========================================================================
  Widget _buildSalesRepsTab(
    ThemeData theme,
    ColorScheme colorScheme,
    CPFRDashboardModel d,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Organizational Hierarchy Banner
        Container(
          padding: const EdgeInsets.all(M3Spacing.lg),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withOpacity(0.45),
            borderRadius: M3Shape.radiusLg,
            border:
                Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Wrap(
            spacing: M3Spacing.xl,
            runSpacing: M3Spacing.md,
            alignment: WrapAlignment.spaceAround,
            children: [
              _buildMiniStat(
                theme,
                'مدير المبيعات (Sales Manager)',
                d.salesManagerName,
              ),
              _buildMiniStat(
                theme,
                'مسؤول كبار العملاء (KA Officer)',
                d.kaOfficerName,
              ),
              _buildMiniStat(
                theme,
                'عدد مندوبي المبيعات النشطين',
                '${d.activeRepsCount} مندوب مبيعات نشط',
              ),
              _buildMiniStat(
                theme,
                'الأقاليم الجغرافية المخدومة',
                '${d.regionPerformances.length} أقاليم ومحافظات',
              ),
            ],
          ),
        ),
        const SizedBox(height: M3Spacing.lg),

        // Regional Summary Cards
        _buildResponsiveCardGrid(
          d.regionPerformances.map((reg) {
            return _buildKpiCard(
              theme: theme,
              colorScheme: colorScheme,
              title: 'إقليم ${reg.governorate} \u200E(${reg.regionCode})\u200E',
              value: CurrencyFormatter.formatCompactEGP(reg.actualValueEgp),
              subtitle:
                  '${CurrencyFormatter.formatUnits(reg.actualCases.round())} كرتونة • ${reg.weightTons.toStringAsFixed(1)} طن (${reg.sharePct}%)',
              icon: Icons.location_on_rounded,
              accentColor: colorScheme.secondary,
            );
          }).toList(),
        ),
        const SizedBox(height: M3Spacing.lg),

        // Field Sales Reps Scorecard Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side:
                BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لوحة تقييم أداء فريق المبيعات الميداني وهيكل الحسابات عبر السلاسل والأقاليم',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  showSwipeHint: true,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: const [
                      DataColumn(label: Text('مندوب المبيعات (Sales Rep)')),
                      DataColumn(label: Text('الإقليم / المحافظة')),
                      DataColumn(label: Text('الأصناف النشطة'), numeric: true),
                      DataColumn(
                          label: Text('الكمية الفعلية (كرتونة)'),
                          numeric: true),
                      DataColumn(
                          label: Text('القيمة الفعلية (ج.م)'), numeric: true),
                      DataColumn(
                          label: Text('المتوقع بنهاية الشهر (EXP)'),
                          numeric: true),
                      DataColumn(label: Text('الوزن (طن)'), numeric: true),
                      DataColumn(label: Text('نسبة العروض %'), numeric: true),
                      DataColumn(label: Text('نسبة المرتجع %'), numeric: true),
                    ],
                    rows: d.salesRepScorecards.map((rep) {
                      return DataRow(
                        cells: [
                          DataCell(Text(
                            rep.salesRep,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )),
                          DataCell(
                              Text('${rep.governorate} (${rep.regionCode})')),
                          DataCell(Text('${rep.activeSkusCount}')),
                          DataCell(Text(rep.actualCases.toStringAsFixed(1))),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(rep.actualValueEgp),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )),
                          DataCell(Text(
                            CurrencyFormatter.formatEGP(rep.expectedValueEgp),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          )),
                          DataCell(
                              Text('${rep.weightTons.toStringAsFixed(2)} طن')),
                          DataCell(
                              Text('${rep.promoSharePct.toStringAsFixed(1)}%')),
                          DataCell(_buildBadge(
                            '${rep.returnRatePct.toStringAsFixed(1)}%',
                            rep.returnRatePct > 5
                                ? colorScheme.error
                                : colorScheme.primary,
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    String? titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(M3Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.14),
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(icon, color: accentColor, size: 20.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (titleEn != null && titleEn.isNotEmpty) ...[
                      const SizedBox(height: 2.0),
                      Text(
                        titleEn,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
          const SizedBox(height: 4.0),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(ThemeData theme, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: M3FontSize.bodySmall,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(M3Spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.3),
        borderRadius: M3Shape.radiusLg,
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 36),
          const SizedBox(height: 8),
          Text(
            _error ?? 'حدث خطأ غير متوقع',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          M3Button.primary(
            label: 'إعادة المحاولة',
            icon: Icons.refresh_rounded,
            onPressed: _loadDashboard,
          ),
        ],
      ),
    );
  }
}
