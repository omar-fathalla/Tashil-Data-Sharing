import 'package:flutter/material.dart';

/// Categories of FMCG Trade Marketing & Promotional activities
enum MarketingExpenseCategory {
  floorRental(
    id: 'floor_rental',
    labelAr: 'تأجير فلورات ومساحات عرض',
    labelEn: 'Floor Display & Gondola Rentals',
    icon: Icons.storefront_rounded,
    color: Color(0xFF0284C7),
  ),
  advertising(
    id: 'advertising',
    labelAr: 'دعاية وإعلانات ومجلات عروض',
    labelEn: 'Advertising, Flyers & Branding',
    icon: Icons.campaign_rounded,
    color: Color(0xFF7C3AED),
  ),
  giftsAndSamples(
    id: 'gifts_samples',
    labelAr: 'هدايا وعينات مجانية وبوندل',
    labelEn: 'Free Gifts, Samples & Promo Bundles',
    icon: Icons.card_giftcard_rounded,
    color: Color(0xFFD97706),
  ),
  eventsAndAgencies(
    id: 'events_agencies',
    labelAr: 'شركات دعاية وإيفنتات وتذوق',
    labelEn: 'Events, Agencies & Activations',
    icon: Icons.celebration_rounded,
    color: Color(0xFFDB2777),
  ),
  promoterIncentives(
    id: 'promoter_incentives',
    labelAr: 'حوافز مروجي ومنسقي المبيعات',
    labelEn: 'Promoter & Merchandiser Incentives',
    icon: Icons.badge_rounded,
    color: Color(0xFF059669),
  ),
  equipmentRental(
    id: 'equipment_rental',
    labelAr: 'تأجير ثلاجات ومعدات عرض',
    labelEn: 'Chillers & Display Equipment Rentals',
    icon: Icons.kitchen_rounded,
    color: Color(0xFF2563EB),
  );

  final String id;
  final String labelAr;
  final String labelEn;
  final IconData icon;
  final Color color;

  const MarketingExpenseCategory({
    required this.id,
    required this.labelAr,
    required this.labelEn,
    required this.icon,
    required this.color,
  });

  static MarketingExpenseCategory fromId(String id) {
    return MarketingExpenseCategory.values.firstWhere(
      (e) => e.id == id,
      orElse: () => MarketingExpenseCategory.floorRental,
    );
  }
}

/// Represents a single promotional or marketing expense line item
class MarketingExpenseItem {
  final String id;
  final int year;
  final int month; // 1 = Jan .. 12 = Dec
  final String chainName;
  final MarketingExpenseCategory category;
  final String brandName;
  final String campaignTitle;
  final String vendorOrAgency;
  final double amountEgp;
  final String notes;
  final DateTime createdAt;

  const MarketingExpenseItem({
    required this.id,
    required this.year,
    required this.month,
    required this.chainName,
    required this.category,
    required this.brandName,
    required this.campaignTitle,
    required this.vendorOrAgency,
    required this.amountEgp,
    required this.notes,
    required this.createdAt,
  });

  String get monthNameEn => monthNamesEn[month] ?? 'Month $month';
  String get monthNameAr => monthNamesAr[month] ?? 'شهر $month';

  static const Map<int, String> monthNamesEn = {
    1: 'January',
    2: 'February',
    3: 'March',
    4: 'April',
    5: 'May',
    6: 'June',
    7: 'July',
    8: 'August',
    9: 'September',
    10: 'October',
    11: 'November',
    12: 'December',
  };

  static const Map<int, String> monthNamesAr = {
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
}

/// Aggregated Monthly + Chain ROI & Growth comparison row
class MonthlyChainRoiSummary {
  final int year;
  final int month;
  final String chainName;
  final double marketingSpendEgp;
  final int activitiesCount;
  final List<MarketingExpenseItem> expenses;

  /// Actual Sell-Out Sales in the selected campaign month (EGP)
  final double currentMonthSalesEgp;

  /// Sell-Out Sales in the immediately preceding month (MoM baseline)
  final double previousMonthSalesEgp;

  /// Sell-Out Sales in the exact same month of the previous year (YoY baseline)
  final double lastYearSameMonthSalesEgp;

  /// Actual Sell-In (Supply) in the selected month (EGP)
  final double currentMonthSellInEgp;

  const MonthlyChainRoiSummary({
    required this.year,
    required this.month,
    required this.chainName,
    required this.marketingSpendEgp,
    required this.activitiesCount,
    required this.expenses,
    required this.currentMonthSalesEgp,
    required this.previousMonthSalesEgp,
    required this.lastYearSameMonthSalesEgp,
    required this.currentMonthSellInEgp,
  });

  String get monthNameEn => MarketingExpenseItem.monthNamesEn[month] ?? 'M$month';
  String get monthNameAr => MarketingExpenseItem.monthNamesAr[month] ?? 'شهر $month';

  /// MoM incremental sales lift in EGP (Current Month - Previous Month)
  double get momLiftEgp => currentMonthSalesEgp - previousMonthSalesEgp;

  /// MoM growth percentage
  double get momGrowthPct => previousMonthSalesEgp > 0
      ? ((currentMonthSalesEgp - previousMonthSalesEgp) / previousMonthSalesEgp) * 100.0
      : 0.0;

  /// YoY incremental sales lift in EGP (Current Month - Same Month Last Year)
  double get yoyLiftEgp => currentMonthSalesEgp - lastYearSameMonthSalesEgp;

  /// YoY growth percentage
  double get yoyGrowthPct => lastYearSameMonthSalesEgp > 0
      ? ((currentMonthSalesEgp - lastYearSameMonthSalesEgp) / lastYearSameMonthSalesEgp) * 100.0
      : 0.0;

  /// Marketing Cost-to-Sales Ratio (%) = Marketing Spend / Current Month Sales
  double get spendToSalesRatioPct => currentMonthSalesEgp > 0
      ? (marketingSpendEgp / currentMonthSalesEgp) * 100.0
      : 0.0;

  /// Return on Marketing Investment Multiple (Incremental MoM Sales Lift / Marketing Spend)
  /// If MoM lift is negative or seasonal, falls back to YoY lift for evaluation if positive.
  double get romiMultiple {
    if (marketingSpendEgp <= 0) return 0.0;
    final effectiveLift = momLiftEgp >= 0 ? momLiftEgp : (yoyLiftEgp > 0 ? yoyLiftEgp : momLiftEgp);
    return effectiveLift / marketingSpendEgp;
  }

  /// Net ROI % = ((Incremental Lift - Marketing Spend) / Marketing Spend) * 100
  double get netRoiPct {
    if (marketingSpendEgp <= 0) return 0.0;
    final effectiveLift = momLiftEgp >= 0 ? momLiftEgp : (yoyLiftEgp > 0 ? yoyLiftEgp : momLiftEgp);
    return ((effectiveLift - marketingSpendEgp) / marketingSpendEgp) * 100.0;
  }

  /// Executive AI Verdict on whether the marketing spend drove profitable growth
  String get verdictAr {
    if (marketingSpendEgp <= 0) return 'بدون إنفاق ترويجي';
    if (romiMultiple >= 3.5 && momGrowthPct >= 10.0) {
      return 'عائد ممتاز ونمو قياسي';
    } else if (romiMultiple >= 1.5 || (momGrowthPct >= 5.0 && yoyGrowthPct >= 10.0)) {
      return 'حملة ناجحة ونمو إيجابي';
    } else if (momGrowthPct > 0 || yoyGrowthPct > 5.0) {
      return 'نمو متوسط - يحتاج تحسين';
    } else {
      return 'عائد ضعيف / مراجعة التكلفة';
    }
  }

  String get verdictEn {
    if (marketingSpendEgp <= 0) return 'No Promo Spend';
    if (romiMultiple >= 3.5 && momGrowthPct >= 10.0) {
      return 'High ROI & Strong Lift';
    } else if (romiMultiple >= 1.5 || (momGrowthPct >= 5.0 && yoyGrowthPct >= 10.0)) {
      return 'Positive Growth Impact';
    } else if (momGrowthPct > 0 || yoyGrowthPct > 5.0) {
      return 'Moderate Lift';
    } else {
      return 'Low Impact - Audit Spend';
    }
  }

  Color get verdictColor {
    if (marketingSpendEgp <= 0) return const Color(0xFF64748B);
    if (romiMultiple >= 3.5 && momGrowthPct >= 10.0) {
      return const Color(0xFF15803D);
    } else if (romiMultiple >= 1.5 || (momGrowthPct >= 5.0 && yoyGrowthPct >= 10.0)) {
      return const Color(0xFF0284C7);
    } else if (momGrowthPct > 0 || yoyGrowthPct > 5.0) {
      return const Color(0xFFD97706);
    } else {
      return const Color(0xFFDC2626);
    }
  }
}

/// Provides initial realistic FMCG trade marketing campaigns and monthly sales baselines
class TradeMarketingSeedData {
  static List<MarketingExpenseItem> getInitialExpenses(String tenantSlug) {
    final isAdeco = tenantSlug.toLowerCase().contains('adeco') || tenantSlug.isEmpty;
    final primaryBrand = isAdeco ? 'Diva' : 'Nivea';
    final secondaryBrand = isAdeco ? 'Maxell' : 'Dove';
    final thirdBrand = isAdeco ? 'Fiesta' : 'Rexona';

    return [
      // JANUARY 2026 - Fathalla (Total = 100,000 EGP as in user's exact example!)
      MarketingExpenseItem(
        id: 'EXP-2026-01-FATH-01',
        year: 2026,
        month: 1,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.floorRental,
        brandName: primaryBrand,
        campaignTitle: 'تأجير 8 فلورات عرض رئيسية وجوندولات مدخل الفروع - يناير',
        vendorOrAgency: 'إدارة التعاقدات - أسواق فتح الله',
        amountEgp: 45000,
        notes: 'فلورات مميزة في فروع سموحة، سان ستيفانو، المنتزه، والغردقة',
        createdAt: DateTime(2026, 1, 5),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-01-FATH-02',
        year: 2026,
        month: 1,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.eventsAndAgencies,
        brandName: primaryBrand,
        campaignTitle: 'إيفنت تذوق وترويج ويك إند مع شركة دعاية متخصصة',
        vendorOrAgency: 'وكالة سبارك للدعاية والإيفنتات (Spark Activation)',
        amountEgp: 35000,
        notes: 'توفير 12 بروموتر واستندات تذوق تفاعلية لمدة 3 أسابيع',
        createdAt: DateTime(2026, 1, 10),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-01-FATH-03',
        year: 2026,
        month: 1,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.giftsAndSamples,
        brandName: secondaryBrand,
        campaignTitle: 'هدايا فورية وعينات مجانية على عبوات العائلة (Bundle Promo)',
        vendorOrAgency: 'مخازن الهدايا الترويجية',
        amountEgp: 20000,
        notes: 'توزيع 4,000 هدية ترويجية عند شراء قطعتين',
        createdAt: DateTime(2026, 1, 14),
      ),

      // FEBRUARY 2026 - Fathalla (Ramadan Early Prep Campaign - 135,000 EGP)
      MarketingExpenseItem(
        id: 'EXP-2026-02-FATH-01',
        year: 2026,
        month: 2,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.floorRental,
        brandName: primaryBrand,
        campaignTitle: 'حجز مساحات وفلورات جناح أهلاً رمضان في 14 فرع',
        vendorOrAgency: 'إدارة التعاقدات - أسواق فتح الله',
        amountEgp: 65000,
        notes: 'مساحات عرض كبيرة (Pallets & Islands) قبل ذروة الموسم',
        createdAt: DateTime(2026, 2, 3),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-02-FATH-02',
        year: 2026,
        month: 2,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.advertising,
        brandName: primaryBrand,
        campaignTitle: 'إعلان غلاف مجلة العروض الشهرية + لافتات الممرات (Aisle Fins)',
        vendorOrAgency: 'قسم التسويق والإعلان - فتح الله',
        amountEgp: 42000,
        notes: 'الصفحة الأولى في مجلة العروض المطبوعة والديجيتال',
        createdAt: DateTime(2026, 2, 7),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-02-FATH-03',
        year: 2026,
        month: 2,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.promoterIncentives,
        brandName: secondaryBrand,
        campaignTitle: 'حوافز ومكافآت فريق المنسقين والـ Merchandisers لتحقيق التارجت',
        vendorOrAgency: 'فريق المبيعات المباشر',
        amountEgp: 28000,
        notes: 'مكافآت رص وتواجد على الرف ومنع النواقص خلال الحملة',
        createdAt: DateTime(2026, 2, 18),
      ),

      // JANUARY 2026 - Gomla Market (85,000 EGP)
      MarketingExpenseItem(
        id: 'EXP-2026-01-GOM-01',
        year: 2026,
        month: 1,
        chainName: 'Gomla',
        category: MarketingExpenseCategory.floorRental,
        brandName: secondaryBrand,
        campaignTitle: 'تأجير جوندولات طرفية (End-Caps) في فروع جملة ماركت',
        vendorOrAgency: 'إدارة جملة ماركت',
        amountEgp: 50000,
        notes: '10 فروع رئيسية في الإسكندرية والقاهرة',
        createdAt: DateTime(2026, 1, 6),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-01-GOM-02',
        year: 2026,
        month: 1,
        chainName: 'Gomla',
        category: MarketingExpenseCategory.advertising,
        brandName: thirdBrand,
        campaignTitle: 'حملة فلايرز وبانرات دعائية داخل الفروع',
        vendorOrAgency: 'وكالة ميديا لاين للدعاية',
        amountEgp: 35000,
        notes: 'تصميم وطباعة ستاندات رول أب وبانرات معلقة',
        createdAt: DateTime(2026, 1, 12),
      ),

      // MARCH 2026 - Fathalla (150,000 EGP - Peak Season Campaign)
      MarketingExpenseItem(
        id: 'EXP-2026-03-FATH-01',
        year: 2026,
        month: 3,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.eventsAndAgencies,
        brandName: primaryBrand,
        campaignTitle: 'حملة إيفنت الخيمة الرمضانية ومسابقات العملاء المباشرة',
        vendorOrAgency: 'وكالة بريميير للإيفنتات (Premier Events)',
        amountEgp: 75000,
        notes: 'تفاعل مباشر مع المتسوقين وتوزيع قسائم وهدايا فورية',
        createdAt: DateTime(2026, 3, 2),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-03-FATH-02',
        year: 2026,
        month: 3,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.equipmentRental,
        brandName: primaryBrand,
        campaignTitle: 'تأجير وتركيب 15 استند وثلاجة عرض إضافية بعلامة البراند',
        vendorOrAgency: 'شركة كول تك لتجهيزات العرض',
        amountEgp: 45000,
        notes: 'زيادة مساحة التبريد والعرض في الفروع الأعلى كثافة',
        createdAt: DateTime(2026, 3, 5),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-03-FATH-03',
        year: 2026,
        month: 3,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.giftsAndSamples,
        brandName: thirdBrand,
        campaignTitle: 'بوندل شنط وهدايا ترويجية للعائلات',
        vendorOrAgency: 'مخازن الهدايا الترويجية',
        amountEgp: 30000,
        notes: 'عروض القيمة المضافة لرفع متوسط سلة الشراء',
        createdAt: DateTime(2026, 3, 10),
      ),

      // APRIL 2026 - Beet El Gomla (70,000 EGP)
      MarketingExpenseItem(
        id: 'EXP-2026-04-BEET-01',
        year: 2026,
        month: 4,
        chainName: 'Beet El Gomla',
        category: MarketingExpenseCategory.floorRental,
        brandName: primaryBrand,
        campaignTitle: 'تأجير فلورات عرض الأعياد والربيع - بيت الجملة',
        vendorOrAgency: 'إدارة بيت الجملة',
        amountEgp: 42000,
        notes: 'تواجد مميز أمام الكاشير وفي الممرات الرئيسية',
        createdAt: DateTime(2026, 4, 4),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-04-BEET-02',
        year: 2026,
        month: 4,
        chainName: 'Beet El Gomla',
        category: MarketingExpenseCategory.giftsAndSamples,
        brandName: secondaryBrand,
        campaignTitle: 'حملة عينات مجانية وهدايا فورية للمستهلكين',
        vendorOrAgency: 'وكالة سبارك للدعاية',
        amountEgp: 28000,
        notes: 'تنشيط المبيعات بعد شهر رمضان',
        createdAt: DateTime(2026, 4, 9),
      ),

      // MAY 2026 - El Wakala (60,000 EGP - Test Case with Moderate/Low Lift for comparison)
      MarketingExpenseItem(
        id: 'EXP-2026-05-WAK-01',
        year: 2026,
        month: 5,
        chainName: 'El Wakala',
        category: MarketingExpenseCategory.advertising,
        brandName: thirdBrand,
        campaignTitle: 'إعلانات مطبوعة وبانرات خارجية لفروع الوكالة',
        vendorOrAgency: 'وكالة النور للإعلان',
        amountEgp: 60000,
        notes: 'حملة إعلانية بدون خصومات سعرية أو فلورات إضافية',
        createdAt: DateTime(2026, 5, 5),
      ),

      // JUNE 2026 - Fathalla Summer Kickoff (115,000 EGP)
      MarketingExpenseItem(
        id: 'EXP-2026-06-FATH-01',
        year: 2026,
        month: 6,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.floorRental,
        brandName: primaryBrand,
        campaignTitle: 'تأجير فلورات الساحل الشمالي ومطروح والإسكندرية لموسم الصيف',
        vendorOrAgency: 'إدارة التعاقدات - أسواق فتح الله',
        amountEgp: 65000,
        notes: 'تركيز على الفروع الساحلية والمصيفية عالية الدوران',
        createdAt: DateTime(2026, 6, 2),
      ),
      MarketingExpenseItem(
        id: 'EXP-2026-06-FATH-02',
        year: 2026,
        month: 6,
        chainName: 'Fathalla',
        category: MarketingExpenseCategory.eventsAndAgencies,
        brandName: secondaryBrand,
        campaignTitle: 'إيفنت تنشيطي وتذوق في فروع الساحل ومارينا',
        vendorOrAgency: 'وكالة سبارك للدعاية والإيفنتات',
        amountEgp: 50000,
        notes: 'حملة ترويجية شاملة مع هدايا الشاطئ',
        createdAt: DateTime(2026, 6, 12),
      ),
    ];
  }

  /// Baseline monthly Sell-Out & Sell-In sales per chain (in EGP) so that every month
  /// has realistic Current Month, Previous Month (MoM), and Last Year Same Month (YoY) figures.
  static Map<String, double> getMonthlySalesSnapshot({
    required String chainName,
    required int year,
    required int month,
    required double totalMarketingSpendInMonth,
  }) {
    final chainMultiplier = switch (chainName) {
      'Fathalla' => 1.0,
      'Gomla' => 0.72,
      'Beet El Gomla' => 0.58,
      'El Wakala' => 0.42,
      'Zahran' => 0.38,
      'Metro' => 0.50,
      _ => 0.55,
    };

    // Base monthly organic sales for Fathalla ~ 1.45M - 1.95M EGP
    final baseSeasonalByMonth = <int, double>{
      1: 1420000.0,
      2: 1680000.0,
      3: 2150000.0,
      4: 1560000.0,
      5: 1490000.0,
      6: 1840000.0,
      7: 1920000.0,
      8: 1980000.0,
      9: 1650000.0,
      10: 1720000.0,
      11: 1600000.0,
      12: 1750000.0,
    };

    final prevMonthIndex = month == 1 ? 12 : month - 1;
    final prevMonthOrganic = (baseSeasonalByMonth[prevMonthIndex] ?? 1400000.0) * chainMultiplier;

    // For January 2026 Fathalla (where spend = 100,000 EGP):
    // Previous month (Dec 2025) = 1,450,000 EGP
    // Current month (Jan 2026) with 100k campaign = 1,920,000 EGP (+470,000 EGP MoM lift = +32.4% growth, 4.7x ROI!)
    // Last year Jan 2025 = 1,360,000 EGP (+560,000 EGP YoY lift = +41.2% growth!)
    if (chainName == 'Fathalla' && year == 2026 && month == 1) {
      final extraUserSpend = (totalMarketingSpendInMonth - 100000.0).clamp(0.0, double.infinity);
      return {
        'currentSales': 1920000.0 + (extraUserSpend * 3.8),
        'previousMonthSales': 1450000.0,
        'lastYearSales': 1360000.0,
        'currentSellIn': 2180000.0 + (extraUserSpend * 4.0),
      };
    }

    if (chainName == 'Fathalla' && year == 2026 && month == 2) {
      return {
        'currentSales': 2480000.0,
        'previousMonthSales': 1920000.0,
        'lastYearSales': 1790000.0,
        'currentSellIn': 2750000.0,
      };
    }

    if (chainName == 'Fathalla' && year == 2026 && month == 3) {
      return {
        'currentSales': 3190000.0,
        'previousMonthSales': 2480000.0,
        'lastYearSales': 2240000.0,
        'currentSellIn': 3450000.0,
      };
    }

    if (chainName == 'Gomla' && year == 2026 && month == 1) {
      return {
        'currentSales': 1340000.0,
        'previousMonthSales': 1050000.0,
        'lastYearSales': 980000.0,
        'currentSellIn': 1490000.0,
      };
    }

    if (chainName == 'Beet El Gomla' && year == 2026 && month == 4) {
      return {
        'currentSales': 1120000.0,
        'previousMonthSales': 910000.0,
        'lastYearSales': 860000.0,
        'currentSellIn': 1250000.0,
      };
    }

    if (chainName == 'El Wakala' && year == 2026 && month == 5) {
      // Example of a campaign with weak lift so the user can see how the system flags inefficient spend!
      return {
        'currentSales': 685000.0,
        'previousMonthSales': 640000.0,
        'lastYearSales': 650000.0,
        'currentSellIn': 790000.0,
      };
    }

    if (chainName == 'Fathalla' && year == 2026 && month == 6) {
      return {
        'currentSales': 2360000.0,
        'previousMonthSales': 1810000.0,
        'lastYearSales': 1740000.0,
        'currentSellIn': 2620000.0,
      };
    }

    // Dynamic calculation for any new month/chain the user adds!
    final organicCurrent = (baseSeasonalByMonth[month] ?? 1500000.0) * chainMultiplier;
    final campaignLift = totalMarketingSpendInMonth * 3.45; // 3.45x average lift
    final currentSales = organicCurrent + campaignLift;
    final prevSales = prevMonthOrganic;
    final lastYearSales = organicCurrent * 0.86;

    return {
      'currentSales': currentSales,
      'previousMonthSales': prevSales,
      'lastYearSales': lastYearSales,
      'currentSellIn': currentSales * 1.12,
    };
  }
}
