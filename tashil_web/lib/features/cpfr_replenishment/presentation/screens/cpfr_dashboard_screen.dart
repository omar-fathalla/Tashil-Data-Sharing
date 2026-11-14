import 'package:flutter/material.dart';
import '../../../data_ingestion/presentation/widgets/upload_checks.dart';
import '../../../data_ingestion/presentation/widgets/sell_in_upload_target.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/utils/export_columns.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_button_group.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../sell_out_analytics/presentation/utils/monthly_status_text.dart';
import '../../domain/cpfr_models.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// Missing-metric honesty (Sell-Out / TM): never paint fake +0.0% / 0.00.
const String _kMissingDash = '—';
const String _kNoLastYearAr = 'لا توجد بيانات للعام السابق';
const String _kNoPeriodDataAr = 'لا توجد بيانات للفترة';
const String _kNoPromoDataAr = 'لا توجد عروض في الفترة';
const String _kNoReturnDataAr = 'لا توجد مرتجعات في الفترة';

/// CPFRDashboardScreen implements the multi-company, multi-chain
/// Collaborative Planning, Forecasting & Replenishment (CPFR) system:
/// 1. Sell-In vs. Sell-Out Reconciliation (مطابقة التوريد مع البيع الفعلي والفجوة المخزنية)
/// 2. Stock Disposition Options & Smart Replenishment PO Generator (خيارات بيع الأرصدة وأوامر التوريد)
/// 3. Run-Rate Month-End Forecasting Engine (محرك التنبؤ EXP) & Promotions/Returns Analytics
/// 4. Field Sales Team & Key Account Hierarchy Tracking across all Retail Chains
class CPFRDashboardScreen extends StatefulWidget {
  final ApiClient apiClient;

  const CPFRDashboardScreen({super.key, required this.apiClient});

  @override
  State<CPFRDashboardScreen> createState() => _CPFRDashboardScreenState();
}

class _CPFRDashboardScreenState extends State<CPFRDashboardScreen>
    with DataRefreshMixin<CPFRDashboardScreen> {
  // Headers and cells share one centred axis (owner table rule).
  // Eight compact columns: secondary metrics stack under a related
  // primary so the table fits 1280 with no horizontal scroll.
  static List<DataColumn> _reconciliationColumns() {
    DataColumn col(String line1, [String? line2, bool numeric = true]) {
      return DataColumn(
        headingRowAlignment: MainAxisAlignment.center,
        numeric: numeric,
        label: _headerLabel(line1, line2),
      );
    }

    return [
      col('الشهر', null, false),
      col('حالة', 'الفترة', false),
      col('الأصناف النشطة'),
      col('رصيد أول', 'الشهر'),
      col('التوريد', 'Sell-In'),
      col('المبيعات', 'Sell-Out'),
      col('الرصيد آخر', 'الشهر'),
      col('الدوران', 'والمتوقع'),
    ];
  }

  static Widget _headerLabel(String line1,
      [String? line2, double maxWidth = 140]) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        line2 == null ? line1 : '$line1\n$line2',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  void onBackendDataChanged() {
    _initChainsAndLoadDashboard();
  }

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
  // TOP RULE: no default upload chain; '' until the user picks one.
  String _uploadTargetChain = '';
  String? _lastUploadedSellInFilename;

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

  Future<void> _initChainsAndLoadDashboard() async {
    try {
      final chains = await widget.apiClient.getRetailChains();
      if (mounted) {
        setState(() {
          _companyChains = chains;
          if (!_companyChains.any((c) => c.code == _uploadTargetChain)) {
            _uploadTargetChain = '';
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
        'تم تحديث بيانات التوريد والمخزون (${CurrencyFormatter.formatUnits(res.validRows)} سجل - ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)})',
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
    // TOP RULE: the chain is always explicit; ask when the selector is empty.
    var targetChain = _uploadTargetChain;
    int? targetYear;
    int? targetMonth;
    if (!isExplicitChain(targetChain)) {
      final target = await askSellInUploadTarget(
        context,
        chains: _companyChains,
        initialChain: _selectedChain,
      );
      if (target == null || !mounted) return;
      targetChain = target.chain;
      targetYear = target.year;
      targetMonth = target.month;
    }
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() => _isUploadingSellIn = true);
    try {
      if (!mounted) return;
      final res = await runUploadWithQuestions(
        context,
        (replaceConfirmed, periodChoice) => widget.apiClient
            .uploadSellInFile(
              filename: picked.name,
              fileBytes: picked.bytes,
              chain: targetChain,
              year: targetYear,
              month: targetMonth,
              replaceConfirmed: replaceConfirmed,
              periodChoice: periodChoice,
            )
            .timeout(sellInUploadTimeout),
      );
      if (!mounted) return;
      if (res == null) {
        M3Feedback.showInfo(context, 'اتلغى الرفع ومفيش حاجة اتحفظت');
        return;
      }
      final notes = uploadWarningsSummary(
        IngestionWarningsView(
          res.quarantinedCustomers.length,
          res.unknownBarcodes.length,
        ),
      );
      if (notes.isNotEmpty) M3Feedback.showWarning(context, notes);
      setState(() {
        _lastUploadedSellInFilename = picked.name;
      });
      M3Feedback.showSuccess(
        context,
        rtlEnd('تم رفع ومعالجة ملف التوريد (${ltrIsolate('Sell-\u2060In')}): ${ltrIsolate(picked.name)} (${CurrencyFormatter.formatUnits(res.validRows)} سجل بإجمالي ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)})'),
      );
      await _loadDashboard();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingSellIn = false);
      if (isUploadWaitTimeout(e)) {
        try {
          await _loadDashboard();
        } catch (_) {}
        if (!mounted) return;
      }
      await showUploadFailureDialog(context, picked.name, e);
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
            Expanded(
              child: Text(
                rtlEnd(
                  'دليل البيانات المطلوبة لمحرك ${ltrIsolate('CPFR')} (${ltrIsolate('Sell-\u2060In')} & ${ltrIsolate('Sell-\u2060Out')})',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: M3FontSize.titleMediumPlus,
                ),
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
        .map(
          (item) => [
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
          ],
        )
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
              _buildTabSelector(),
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
          rtlEnd('منظومة التخطيط المشترك ومطابقة التوريد (${ltrIsolate('Sell-\u2060In')}) مع مبيعات الكاشير (${ltrIsolate('Sell-\u2060Out')}) وحساب دوران المخزون وأوامر التوريد لجميع السلاسل'),
      actions: M3ButtonGroup(
        maxVisibleCompact: 2,
        items: [
          M3GroupItem(
            label: 'نموذج التوريد الإرشادي',
            icon: Icons.download_for_offline_rounded,
            kind: M3GroupItemKind.tonal,
            onPressed: _downloadSellInGuidedDemoTemplate,
          ),
          M3GroupItem(
            label: 'رفع ملف Sell-In',
            icon: Icons.upload_file_rounded,
            kind: M3GroupItemKind.tonal,
            isLoading: _isUploadingSellIn,
            onPressed: _isUploadingSellIn ? null : _pickAndUploadSellInFile,
          ),
          M3GroupItem(
            label: 'تحديث التوريد',
            icon: Icons.sync_rounded,
            kind: M3GroupItemKind.tonal,
            isLoading: _isReloadingWorkbook,
            onPressed: _isReloadingWorkbook ? null : _reloadSellInWorkbook,
          ),
          if (_data != null)
            M3GroupItem(
              label: 'تصدير PO',
              icon: Icons.shopping_cart_checkout_rounded,
              kind: M3GroupItemKind.tonal,
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
                    fitOptions: true,
                    value:
                        _companyChains.any((c) => c.code == _uploadTargetChain)
                            ? _uploadTargetChain
                            : null,
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
                        () => _showDataGuideBanner = !_showDataGuideBanner,
                      );
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
              M3Button.tonal(
                label: 'رفع ملف Sell-In هنا',
                icon: Icons.upload_file_rounded,
                isLoading: _isUploadingSellIn,
                onPressed:
                    _isUploadingSellIn ? null : _pickAndUploadSellInFile,
              ),
              const SizedBox(width: 12.0),
              Flexible(
                child: Text(
                  'اختر ملف التوريد الخاص بالسلسلة المحددة لمطابقته الفورية مع مبيعات الكاشير وحساب الفجوة المخزنية',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
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
                    'مصدر بيانات التوريد النشط: ${ltrIsolate(activeFile)} (${CurrencyFormatter.formatUnits(_data?.totalRecords ?? 0)} سجل)',
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
              Icon(
                Icons.storefront_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'سلسلة التجزئة:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          M3Dropdown<String>(
            fitOptions: true,
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

          // 2. Product Sector Filter (القطاع السلعي) — M3Dropdown like Sell-Out / TM
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'القطاع السلعي:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          M3Dropdown<String>(
            fitOptions: true,
            value: _selectedSector,
            options: m3OptionsFromMenuItems<String>([
              const DropdownMenuItem(
                value: 'all',
                child: Text('كل القطاعات'),
              ),
              const DropdownMenuItem(
                value: 'MT',
                child: Text('المنظفات والعناية المنزلية'),
              ),
              const DropdownMenuItem(
                value: 'CC',
                child: Text('العناية المتخصصة'),
              ),
            ]),
            onChanged: m3Legacy<String>((sector) {
              if (sector == null || _selectedSector == sector) return;
              setState(() => _selectedSector = sector);
              _loadDashboard();
            }),
          ),

          const SizedBox(width: M3Spacing.sm),

          // 3. Region Filter (الإقليم)
          Text(
            'الإقليم:',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          M3Dropdown<String>(
            fitOptions: true,
            value: _selectedRegion,
            options: m3OptionsFromMenuItems<String>([
              const DropdownMenuItem(
                value: 'all',
                child: Text('جميع الأقاليم'),
              ),
              const DropdownMenuItem(
                value: 'ALX',
                child: Text('ALX - الإسكندرية ومطروح'),
              ),
              const DropdownMenuItem(
                value: 'CIR',
                child: Text('CIR - القاهرة الكبرى'),
              ),
              const DropdownMenuItem(
                value: 'TNT',
                child: Text('TNT - الغربية (طنطا)'),
              ),
              const DropdownMenuItem(
                value: 'BHR',
                child: Text('BHR - البحيرة'),
              ),
              const DropdownMenuItem(
                value: 'MNS',
                child: Text('MNS - المنصورة والدلتا'),
              ),
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

  /// Full-width M3 tab bar — same geometry as Sell-Out / Trade Marketing.
  Widget _buildTabSelector() {
    return M3ResponsiveTabBar<int>(
      key: const ValueKey('cpfr_tab_bar'),
      textDirection: TextDirection.ltr,
      selectedValue: _activeTab,
      // labelKey uses 1-based indices (cpfr_tab_label_N) for Mac/web tests.
      items: const [
        M3ResponsiveTabItem<int>(
          value: 0,
          icon: Icons.compare_arrows_rounded,
          selectedIcon: Icons.compare_arrows_rounded,
          label: 'Sell-In vs Sell-Out',
          labelKey: ValueKey('cpfr_tab_label_1'),
        ),
        M3ResponsiveTabItem<int>(
          value: 1,
          icon: Icons.calculate_rounded,
          selectedIcon: Icons.calculate_rounded,
          label: 'Suggested PO & Replenishment',
          labelKey: ValueKey('cpfr_tab_label_2'),
        ),
        M3ResponsiveTabItem<int>(
          value: 2,
          icon: Icons.trending_up_rounded,
          selectedIcon: Icons.trending_up_rounded,
          label: 'Demand Forecasting & Promos (EXP)',
          labelKey: ValueKey('cpfr_tab_label_3'),
        ),
        M3ResponsiveTabItem<int>(
          value: 3,
          icon: Icons.badge_rounded,
          selectedIcon: Icons.badge_rounded,
          label: 'أداء فريق المبيعات وهيكل الحسابات',
          labelKey: ValueKey('cpfr_tab_label_4'),
        ),
      ],
      onChanged: (next) => setState(() => _activeTab = next),
    );
  }

  Widget _buildResponsiveCardGrid(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();

    // Same breakpoints, gutters and equal-height behavior as Sell-Out / Sell-In.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 960
            ? (cards.length >= 4 ? 4 : cards.length)
            : (maxWidth >= 580 ? (cards.length >= 2 ? 2 : 1) : 1);
        return M3EqualHeightGrid(
          key: const ValueKey('kpi_cards_row'),
          columns: columns,
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: cards,
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
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Sell-In'),
            valueKey: const ValueKey('kpi_value_Sell-In'),
            subtitleKey: const ValueKey('kpi_subtitle_Sell-In'),
            title: 'إجمالي التوريد للسلاسل',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026SellInEgp),
            subtitle: CurrencyFormatter.formatEGP(d.jan2026SellInEgp),
            icon: Icons.local_shipping_rounded,
            color: colorScheme.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Sell-Out'),
            valueKey: const ValueKey('kpi_value_Sell-Out'),
            subtitleKey: const ValueKey('kpi_subtitle_Sell-Out'),
            title: 'مبيعات الكاشير الفعلية',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026SellOutEgp),
            subtitle: CurrencyFormatter.formatEGP(d.jan2026SellOutEgp),
            icon: Icons.point_of_sale_rounded,
            color: colorScheme.secondary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Sell-Through Rate'),
            valueKey: const ValueKey('kpi_value_Sell-Through Rate'),
            subtitleKey: const ValueKey('kpi_subtitle_Sell-Through Rate'),
            title: 'معدل دوران المخزون',
            value: '${d.jan2026SellThroughPct.toStringAsFixed(1)}%',
            subtitle: 'تصريف مقابل التوريد · معيار 85%',
            icon: Icons.autorenew_rounded,
            color: colorScheme.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Inventory Gap'),
            valueKey: const ValueKey('kpi_value_Inventory Gap'),
            subtitleKey: const ValueKey('kpi_subtitle_Inventory Gap'),
            title: 'الفجوة المخزنية',
            value: CurrencyFormatter.formatCompactEGP(d.jan2026GapEgp),
            subtitle: CurrencyFormatter.formatEGP(d.jan2026GapEgp),
            icon: Icons.warehouse_rounded,
            color: colorScheme.tertiary,
          ),
        ]),
        const SizedBox(height: M3Spacing.sm),

        // Sell-In symmetry: chain margin + YoY — «—» when cost / last-year missing.
        _buildResponsiveCardGrid([
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Chain Margin'),
            valueKey: const ValueKey('kpi_value_Chain Margin'),
            subtitleKey: const ValueKey('kpi_subtitle_Chain Margin'),
            title: 'هامش السلسلة',
            value: d.matchedSellOutPosValueEgp <= 0
                ? _kMissingDash
                : (d.matchedSellOutValueWithCostEgp <= 0
                    ? _kMissingDash
                    : CurrencyFormatter.formatMarginSummary(
                        d.matchedChainGrossMarginEgp,
                        d.matchedChainGrossMarginPct,
                      )),
            subtitle: d.matchedSellOutPosValueEgp <= 0
                ? 'لا توجد مبيعات مطابقة لحساب الهامش'
                : (d.matchedSellOutValueWithCostEgp <= 0
                    ? 'تكلفة المصنع غير متوفرة للأصناف المباعة'
                    : (d.matchedMissingCostSellOutEgp > 0
                        ? 'محسوب على الأصناف المعروفة تكلفتها فقط · مستبعد ${CurrencyFormatter.formatCompactEGP(d.matchedMissingCostSellOutEgp)}'
                        : 'سعر البيع للمستهلك ناقص صافي تكلفة التوريد')),
            icon: Icons.paid_rounded,
            color: d.matchedChainGrossMarginEgp < 0
                ? colorScheme.error
                : colorScheme.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Sell-Out Growth YoY'),
            valueKey: const ValueKey('kpi_value_Sell-Out Growth YoY'),
            subtitleKey: const ValueKey('kpi_subtitle_Sell-Out Growth YoY'),
            title: 'النمو عن العام السابق',
            value: d.matchedYoyAvailable
                ? '${CurrencyFormatter.formatSignedPct(d.matchedYoyValueGrowthPct)} بالقيمة'
                : _kMissingDash,
            subtitle: d.matchedYoyAvailable
                ? 'بالكمية: ${CurrencyFormatter.formatSignedPct(d.matchedYoyUnitsGrowthPct)} عن نفس الفترة من العام السابق'
                : _kNoLastYearAr,
            icon: Icons.trending_up_rounded,
            color: colorScheme.secondary,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // YTD Multi-Chain Summary Strip
        Container(
          padding: const EdgeInsets.all(M3Spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
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
                countSku(d.activeSkusCount),
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
            side: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  key: const ValueKey('cpfr_reconciliation_table'),
                  showSwipeHint: true,
                  columnFlex: const [2.0, 1.1, 0.7, 0.9, 1.2, 1.2, 1.2, 1.2],
                  child: DataTable(
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: double.infinity,
                    horizontalMargin: 8.0,
                    columnSpacing: 10.0,
                    headingRowHeight: 52.0,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: _reconciliationColumns(),
                    rows: d.monthlyReconciliation.map((m) {
                      final isJan = m.monthNum == 1;
                      final isOct = m.monthNum == 10;
                      return DataRow(
                        color: isJan
                            ? WidgetStateProperty.all(
                                colorScheme.primaryContainer.withOpacity(0.22),
                              )
                            : (isOct
                                ? WidgetStateProperty.all(
                                    colorScheme.tertiaryContainer.withOpacity(
                                      0.22,
                                    ),
                                  )
                                : null),
                        cells: [
                          DataCell(
                            _bounded(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _cellText(
                                    '${m.monthNum} - ${m.monthAr} ${m.year}',
                                    key: ValueKey(
                                      'cpfr_recon_month_name_${m.monthNum}',
                                    ),
                                    weight: FontWeight.w700,
                                  ),
                                  if (m.monthEn.isNotEmpty)
                                    _cellText(
                                      '(${m.monthEn})',
                                      fontSize: M3FontSize.labelSmall,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                ],
                              ),
                              150,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _statusChip(
                                status: m.periodStatus,
                                label: m.periodStatus,
                                color: isOct
                                    ? colorScheme.tertiary
                                    : colorScheme.secondary,
                              ),
                              96,
                            ),
                          ),
                          DataCell(
                              _bounded(_cellText('${m.activeSkusCount}'), 44)),
                          DataCell(
                            _bounded(
                              _cellText(
                                '${CurrencyFormatter.formatNumber(m.openingStockCases.round())} كرتونة',
                                fontSize: M3FontSize.bodySmall,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              80,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  m.sellInValueEgp,
                                ),
                                secondary:
                                    '${m.sellInCases.toStringAsFixed(1)} كرتونة',
                                primaryWeight: FontWeight.w700,
                              ),
                              110,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  m.sellOutValueEgp,
                                ),
                                secondary:
                                    'صافي ${CurrencyFormatter.formatEGP(m.monthlyNetValueEgp)}',
                                primaryWeight: FontWeight.w700,
                                primaryColor: colorScheme.secondary,
                                secondaryColor: colorScheme.tertiary,
                              ),
                              110,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  m.closingStockValueEgp,
                                ),
                                secondary:
                                    '${CurrencyFormatter.formatNumber(m.closingStockCases.round())} كرتونة',
                                primaryWeight: FontWeight.w800,
                                primaryColor: colorScheme.primary,
                              ),
                              110,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              Column(
                                key: ValueKey(
                                  'cpfr_recon_str_exp_${m.monthNum}',
                                ),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _metricChip(
                                    '${m.sellThroughRatePct.toStringAsFixed(1)}%',
                                    m.sellThroughRatePct >= 85
                                        ? colorScheme.primary
                                        : colorScheme.tertiary,
                                  ),
                                  _cellText(
                                    '${m.weightTons.toStringAsFixed(1)} طن',
                                    fontSize: M3FontSize.labelSmall,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  _cellText(
                                    CurrencyFormatter.formatEGP(
                                      m.expectedValueEgp,
                                    ),
                                    fontSize: M3FontSize.labelSmall,
                                    weight: isOct
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isOct
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                              110,
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
                    fitOptions: true,
                    value: _leadTimeDays,
                    options: m3OptionsFromMenuItems<int>([
                      const DropdownMenuItem(
                        value: 2,
                        child: Text('يومان (2 Days)'),
                      ),
                      const DropdownMenuItem(
                        value: 4,
                        child: Text('4 أيام (قياسي)'),
                      ),
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
                    fitOptions: true,
                    value: _safetyStockDays,
                    options: m3OptionsFromMenuItems<int>([
                      const DropdownMenuItem(value: 5, child: Text('5 أيام')),
                      const DropdownMenuItem(
                        value: 7,
                        child: Text('7 أيام (موصى به)'),
                      ),
                      const DropdownMenuItem(value: 10, child: Text('10 أيام')),
                      const DropdownMenuItem(
                        value: 14,
                        child: Text('14 يوماً'),
                      ),
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
                    fitOptions: true,
                    value: _selectedStockStatus,
                    options: m3OptionsFromMenuItems<String>([
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('جميع الأصناف'),
                      ),
                      const DropdownMenuItem(
                        value: 'urgent_replenishment',
                        child: Text('خطر نفاد عاجل (يحتاج توريد فوري)'),
                      ),
                      const DropdownMenuItem(
                        value: 'optimal',
                        child: Text('رصيد آمن ومثالي'),
                      ),
                      const DropdownMenuItem(
                        value: 'overstock',
                        child: Text('تكدس مخزني'),
                      ),
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
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Estimated stock'),
            valueKey: const ValueKey('kpi_value_Estimated stock'),
            subtitleKey: const ValueKey('kpi_subtitle_Estimated stock'),
            title: 'الرصيد التقديري',
            value:
                '${CurrencyFormatter.formatUnits(d.totalEstimatedStockCases.round())} كرتونة',
            subtitle:
                CurrencyFormatter.formatCompactEGP(d.totalEstimatedStockEgp),
            icon: Icons.inventory_rounded,
            color: colorScheme.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Suggested PO'),
            valueKey: const ValueKey('kpi_value_Suggested PO'),
            subtitleKey: const ValueKey('kpi_subtitle_Suggested PO'),
            title: 'أوامر التوريد المقترحة',
            value:
                '${CurrencyFormatter.formatUnits(d.totalSuggestedPoCases)} كرتونة',
            subtitle:
                '${CurrencyFormatter.formatCompactEGP(d.totalSuggestedPoEgp)} · ${d.totalSuggestedPoTons.toStringAsFixed(1)} طن',
            icon: Icons.add_shopping_cart_rounded,
            color: colorScheme.secondary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Urgent replenishment'),
            valueKey: const ValueKey('kpi_value_Urgent replenishment'),
            subtitleKey: const ValueKey('kpi_subtitle_Urgent replenishment'),
            title: 'توريد عاجل',
            value: countSku(d.urgentReplenishmentCount),
            subtitle: 'أقل من المهلة + حد الأمان',
            icon: Icons.notification_important_rounded,
            color: colorScheme.error,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Overstock'),
            valueKey: const ValueKey('kpi_value_Overstock'),
            subtitleKey: const ValueKey('kpi_subtitle_Overstock'),
            title: 'تكدس مخزني',
            value: countSku(d.overstockAlertCount),
            subtitle: 'تغطية أكثر من 28 يوماً',
            icon: Icons.hourglass_bottom_rounded,
            color: colorScheme.tertiary,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // SKU x Region Inventory & Suggested PO Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
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
                    M3Button.tonal(
                      label: 'تصدير PO',
                      icon: Icons.download_rounded,
                      onPressed: () => _exportReplenishmentPOExcel(d),
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.md),
                TableScrollContainer(
                  key: const ValueKey('cpfr_po_table'),
                  showSwipeHint: true,
                  columnFlex: const [2.2, 1.3, 1.2, 1.2, 1.2, 1.3],
                  child: DataTable(
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: double.infinity,
                    horizontalMargin: 8.0,
                    columnSpacing: 10.0,
                    headingRowHeight: 52.0,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('الصنف', 'SKU', 260),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('العلامة', 'والإقليم'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('المندوب'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('الرصيد', 'والسحب'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('حالة', 'المخزون'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('أمر التوريد', 'المقترح'),
                      ),
                    ],
                    rows: d.inventoryAndPoItems.take(60).map((item) {
                      final isUrgent =
                          item.stockStatus == 'urgent_replenishment';
                      return DataRow(
                        cells: [
                          DataCell(
                            _bounded(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    item.skuName,
                                    key: const ValueKey('cpfr_po_sku_name'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.itemCode.isNotEmpty ||
                                      item.barcode.isNotEmpty)
                                    Text(
                                      '${item.itemCode.isNotEmpty ? item.itemCode : ""}${item.itemCode.isNotEmpty && item.barcode.isNotEmpty ? " • " : ""}${item.barcode}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: M3FontSize.tiny,
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              260,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: '${item.brand} (${item.sector})',
                                secondary:
                                    '${item.governorate} (${item.regionCode})',
                              ),
                              120,
                            ),
                          ),
                          DataCell(_bounded(_cellText(item.salesRep), 100)),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary:
                                    '${item.estimatedStockCases.toStringAsFixed(1)} ك',
                                secondary:
                                    '${item.dailyRunRateCases.toStringAsFixed(1)} ك/يوم · ${item.daysOfInventory.toStringAsFixed(0)} يوم',
                                tertiary:
                                    'توريد ${item.sellInCases.toStringAsFixed(0)} · بيع ${item.sellOutEstCases.toStringAsFixed(0)}',
                                primaryWeight: FontWeight.w800,
                              ),
                              130,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _statusChip(
                                status: item.stockStatus,
                                label: item.stockStatusAr,
                                color: isUrgent
                                    ? colorScheme.error
                                    : (item.stockStatus == 'overstock'
                                        ? colorScheme.tertiary
                                        : colorScheme.primary),
                              ),
                              110,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: '${item.suggestedPoCases} كرتونة',
                                secondary: CurrencyFormatter.formatEGP(
                                  item.suggestedPoValueEgp,
                                ),
                                primaryWeight: FontWeight.w800,
                                primaryColor: item.suggestedPoCases > 0
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              120,
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
        // W1 + W2 -> EXP Forecasting Cards (— when the period has no data)
        _buildResponsiveCardGrid([
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_W1+W2 actual'),
            valueKey: const ValueKey('kpi_value_W1+W2 actual'),
            subtitleKey: const ValueKey('kpi_subtitle_W1+W2 actual'),
            title: 'المسحوبات الفعلية',
            value: (d.octW1W2ActualEgp <= 0 && d.octW1W2ActualCases <= 0)
                ? _kMissingDash
                : CurrencyFormatter.formatCompactEGP(d.octW1W2ActualEgp),
            subtitle: (d.octW1W2ActualEgp <= 0 && d.octW1W2ActualCases <= 0)
                ? _kNoPeriodDataAr
                : 'W1 + W2 · ${CurrencyFormatter.formatUnits(d.octW1W2ActualCases.round())} كرتونة',
            icon: Icons.calendar_today_rounded,
            color: colorScheme.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Projected EXP'),
            valueKey: const ValueKey('kpi_value_Projected EXP'),
            subtitleKey: const ValueKey('kpi_subtitle_Projected EXP'),
            title: 'المتوقع بنهاية الشهر',
            value: d.octProjectedMonthEndEgp <= 0
                ? _kMissingDash
                : CurrencyFormatter.formatCompactEGP(
                    d.octProjectedMonthEndEgp,
                  ),
            subtitle: d.octProjectedMonthEndEgp <= 0
                ? _kNoPeriodDataAr
                : '${CurrencyFormatter.formatUnits(d.octProjectedCases.round())} كرتونة · Run-Rate',
            icon: Icons.auto_graph_rounded,
            color: colorScheme.tertiary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Promotions'),
            valueKey: const ValueKey('kpi_value_Promotions'),
            subtitleKey: const ValueKey('kpi_subtitle_Promotions'),
            title: 'مساهمة العروض',
            value: (pr.promoValueEgp <= 0 && pr.promoRecordsCount <= 0)
                ? _kMissingDash
                : CurrencyFormatter.formatCompactEGP(pr.promoValueEgp),
            subtitle: (pr.promoValueEgp <= 0 && pr.promoRecordsCount <= 0)
                ? _kNoPromoDataAr
                : '${pr.promoValueSharePct.toStringAsFixed(1)}% · ${pr.promoRecordsCount} حركة',
            icon: Icons.local_offer_rounded,
            color: colorScheme.secondary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('kpi_card_Returns Rate'),
            valueKey: const ValueKey('kpi_value_Returns Rate'),
            subtitleKey: const ValueKey('kpi_subtitle_Returns Rate'),
            title: 'معدل المرتجعات',
            value: pr.returnRecordsCount <= 0
                ? _kMissingDash
                : '${pr.overallReturnPct.toStringAsFixed(2)}%',
            subtitle: pr.returnRecordsCount <= 0
                ? _kNoReturnDataAr
                : '${pr.returnRecordsCount} مرتجع · ${CurrencyFormatter.formatCompactEGP(pr.totalReturnValueEgp)}',
            icon: Icons.assignment_return_rounded,
            color: colorScheme.error,
          ),
        ]),
        const SizedBox(height: M3Spacing.lg),

        // Brand-Level Forecast & Sector Table
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
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
                  key: const ValueKey('cpfr_forecast_table'),
                  showSwipeHint: true,
                  columnFlex: const [0.7, 2.0, 0.7, 1.3, 1.5],
                  child: DataTable(
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: double.infinity,
                    horizontalMargin: 8.0,
                    columnSpacing: 10.0,
                    headingRowHeight: 52.0,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('القطاع'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('العلامة', 'التجارية'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('الأصناف'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('الفعلي', 'قيمة / كمية'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('المتوقع EXP', 'وحصة'),
                      ),
                    ],
                    rows: d.brandForecasts.map((b) {
                      final isCC = b.sector.toUpperCase() == 'CC';
                      return DataRow(
                        cells: [
                          DataCell(
                            _metricChip(
                              b.sector,
                              isCC ? colorScheme.tertiary : colorScheme.primary,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _cellText(
                                b.brand,
                                key: const ValueKey('cpfr_forecast_brand'),
                                weight: FontWeight.w800,
                              ),
                              240,
                            ),
                          ),
                          DataCell(
                              _bounded(_cellText('${b.activeSkusCount}'), 44)),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  b.actualValueEgp,
                                ),
                                secondary:
                                    '${b.actualCases.toStringAsFixed(1)} كرتونة',
                                primaryWeight: FontWeight.w700,
                              ),
                              140,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  b.expectedValueEgp,
                                ),
                                secondary:
                                    '${b.expectedCases.toStringAsFixed(1)} ك · ${b.weightTons.toStringAsFixed(1)} طن',
                                tertiary:
                                    '${b.shareOfTotalPct.toStringAsFixed(1)}%',
                                primaryWeight: FontWeight.w700,
                              ),
                              140,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                TableScrollContainer(
                  key: const ValueKey('cpfr_returns_table'),
                  showSwipeHint: true,
                  columnFlex: const [2.0, 1.3, 1.2, 1.2, 0.9],
                  child: DataTable(
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: double.infinity,
                    horizontalMargin: 8.0,
                    columnSpacing: 10.0,
                    headingRowHeight: 52.0,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('اسم الصنف', null, 260),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('العلامة', 'والإقليم'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('المندوب'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('المرتجع', 'كمية / قيمة'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('النسبة'),
                      ),
                    ],
                    rows: pr.topReturnItems.take(15).map((ret) {
                      return DataRow(
                        cells: [
                          DataCell(
                            _bounded(
                              _cellText(
                                ret.itemName,
                                key: const ValueKey('cpfr_returns_sku_name'),
                                weight: FontWeight.w700,
                              ),
                              260,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: '${ret.brand} (${ret.sector})',
                                secondary:
                                    '${ret.governorate} (${ret.regionCode})',
                              ),
                              140,
                            ),
                          ),
                          DataCell(_bounded(_cellText(ret.salesRep), 120)),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: ret.returnCases.toStringAsFixed(2),
                                secondary: CurrencyFormatter.formatEGP(
                                  ret.returnValueEgp,
                                ),
                                primaryWeight: FontWeight.w700,
                                primaryColor: colorScheme.error,
                                secondaryColor: colorScheme.error,
                              ),
                              120,
                            ),
                          ),
                          DataCell(
                            _metricChip(
                              '${ret.returnRatePct.toStringAsFixed(1)}%',
                              colorScheme.error,
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
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
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
            return M3SummaryKpiCard(
              key: ValueKey('kpi_card_Region ${reg.regionCode}'),
              valueKey: ValueKey('kpi_value_Region ${reg.regionCode}'),
              subtitleKey: ValueKey('kpi_subtitle_Region ${reg.regionCode}'),
              title: reg.governorate,
              value: CurrencyFormatter.formatCompactEGP(reg.actualValueEgp),
              subtitle:
                  '${CurrencyFormatter.formatUnits(reg.actualCases.round())} كرتونة · ${reg.sharePct}%',
              icon: Icons.location_on_rounded,
              color: colorScheme.secondary,
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
            side: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
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
                  key: const ValueKey('cpfr_rep_table'),
                  showSwipeHint: true,
                  columnFlex: const [2.0, 1.3, 0.7, 1.3, 1.4],
                  child: DataTable(
                    dataRowMinHeight: 56.0,
                    dataRowMaxHeight: double.infinity,
                    horizontalMargin: 8.0,
                    columnSpacing: 10.0,
                    headingRowHeight: 52.0,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    columns: [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('المندوب'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: _headerLabel('الإقليم'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('الأصناف'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('الفعلي', 'قيمة / كمية'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        numeric: true,
                        label: _headerLabel('المتوقع', 'وعروض / مرتجع'),
                      ),
                    ],
                    rows: d.salesRepScorecards.map((rep) {
                      return DataRow(
                        cells: [
                          DataCell(
                            _bounded(
                              _cellText(
                                rep.salesRep,
                                key: const ValueKey('cpfr_rep_name'),
                                weight: FontWeight.w800,
                              ),
                              240,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _cellText(
                                  '${rep.governorate} (${rep.regionCode})'),
                              140,
                            ),
                          ),
                          DataCell(_cellText('${rep.activeSkusCount}')),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  rep.actualValueEgp,
                                ),
                                secondary:
                                    '${rep.actualCases.toStringAsFixed(1)} كرتونة',
                                primaryWeight: FontWeight.w700,
                              ),
                              140,
                            ),
                          ),
                          DataCell(
                            _bounded(
                              _stackedMetric(
                                primary: CurrencyFormatter.formatEGP(
                                  rep.expectedValueEgp,
                                ),
                                secondary:
                                    '${rep.weightTons.toStringAsFixed(1)} طن · عروض ${rep.promoSharePct.toStringAsFixed(1)}%',
                                tertiary:
                                    'مرتجع ${rep.returnRatePct.toStringAsFixed(1)}%',
                                primaryWeight: FontWeight.w700,
                                primaryColor: colorScheme.primary,
                              ),
                              140,
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
        ),
      ],
    );
  }

  Widget _bounded(Widget child, double maxWidth) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
  }

  Widget _stackedMetric({
    required String primary,
    String? secondary,
    String? tertiary,
    FontWeight primaryWeight = FontWeight.w700,
    Color? primaryColor,
    Color? secondaryColor,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cellText(primary, weight: primaryWeight, color: primaryColor),
        if (secondary != null)
          _cellText(
            secondary,
            fontSize: M3FontSize.labelSmall,
            weight: FontWeight.w600,
            color: secondaryColor ??
                Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        if (tertiary != null)
          _cellText(
            tertiary,
            fontSize: M3FontSize.labelSmall,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _cellText(
    String text, {
    Key? key,
    FontWeight? weight,
    Color? color,
    double? fontSize,
    String? fontFamily,
  }) {
    return Text(
      text,
      key: key,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: weight,
        color: color,
        fontSize: fontSize,
        fontFamily: fontFamily,
      ),
    );
  }

  /// CPFR Suggested-PO stock statuses. Kept local so Sell-In's monthly
  /// health map (and its text-style snapshot) stays unchanged.
  static const Map<String, MonthlyStatusText> _stockStatusText = {
    'urgent_replenishment': MonthlyStatusText('نفاد عاجل', 'يحتاج توريد فوري'),
    'optimal': MonthlyStatusText('رصيد آمن', 'رصيد آمن ومثالي'),
    'overstock': MonthlyStatusText(
      'تكدس مخزني',
      'التغطية تتجاوز حد الأمان الموصى به',
    ),
  };

  /// Short status chip + grey description underneath (Sell-In monthly status).
  Widget _statusChip({
    required String status,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t =
        _stockStatusText[status] ?? MonthlyStatusText.resolve(status, label);
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          M3ChipSurface(
            color: color.withValues(alpha: 0.12),
            borderColor: color.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: M3Spacing.xxs),
              child: Text(
                t.short,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (t.description.isNotEmpty) ...[
            const SizedBox(height: M3Spacing.xxs),
            Text(
              t.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact 8dp metric/category chip (percentages, sector codes).
  Widget _metricChip(String label, Color color) {
    return M3ChipSurface(
      color: color.withValues(alpha: 0.12),
      borderColor: color.withValues(alpha: 0.35),
      child: Text(
        label,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: M3FontSize.bodySmall,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMiniStat(ThemeData theme, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
