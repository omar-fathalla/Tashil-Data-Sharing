/// Phase-1 Sell-In returns (المرتجعات) report models.
class SellInReturnsCell {
  final double grossValueEgp;
  final double returnsValueEgp;
  final double returnsQty;
  final double netValueEgp;
  final double returnPctOfGross;

  const SellInReturnsCell({
    this.grossValueEgp = 0,
    this.returnsValueEgp = 0,
    this.returnsQty = 0,
    this.netValueEgp = 0,
    this.returnPctOfGross = 0,
  });

  factory SellInReturnsCell.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellInReturnsCell();
    return SellInReturnsCell(
      grossValueEgp: (json['gross_value_egp'] as num?)?.toDouble() ?? 0,
      returnsValueEgp: (json['returns_value_egp'] as num?)?.toDouble() ?? 0,
      returnsQty: (json['returns_qty'] as num?)?.toDouble() ?? 0,
      netValueEgp: (json['net_value_egp'] as num?)?.toDouble() ?? 0,
      returnPctOfGross: (json['return_pct_of_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SellInReturnsBranchRow {
  final String branchKey;
  final String branchName;
  final String retailerChain;
  final Map<int, SellInReturnsCell> byMonth;
  final SellInReturnsCell total;

  const SellInReturnsBranchRow({
    required this.branchKey,
    required this.branchName,
    this.retailerChain = '',
    this.byMonth = const {},
    this.total = const SellInReturnsCell(),
  });

  factory SellInReturnsBranchRow.fromJson(Map<String, dynamic> json) {
    final raw = json['by_month'];
    final map = <int, SellInReturnsCell>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final m = int.tryParse('$k');
        if (m != null && v is Map) {
          map[m] = SellInReturnsCell.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return SellInReturnsBranchRow(
      branchKey: '${json['branch_key'] ?? ''}',
      branchName: '${json['branch_name'] ?? ''}',
      retailerChain: '${json['retailer_chain'] ?? ''}',
      byMonth: map,
      total: SellInReturnsCell.fromJson(
        json['total'] is Map ? Map<String, dynamic>.from(json['total'] as Map) : null,
      ),
    );
  }
}

class SellInReturnsMonthPoint {
  final int monthNum;
  final String monthAr;
  final String monthEn;
  final double grossValueEgp;
  final double returnsValueEgp;
  final double returnsQty;
  final double netValueEgp;
  final double returnPctOfGross;

  const SellInReturnsMonthPoint({
    required this.monthNum,
    this.monthAr = '',
    this.monthEn = '',
    this.grossValueEgp = 0,
    this.returnsValueEgp = 0,
    this.returnsQty = 0,
    this.netValueEgp = 0,
    this.returnPctOfGross = 0,
  });

  factory SellInReturnsMonthPoint.fromJson(Map<String, dynamic> json) {
    return SellInReturnsMonthPoint(
      monthNum: (json['month_num'] as num?)?.toInt() ?? 0,
      monthAr: '${json['month_ar'] ?? ''}',
      monthEn: '${json['month_en'] ?? ''}',
      grossValueEgp: (json['gross_value_egp'] as num?)?.toDouble() ?? 0,
      returnsValueEgp: (json['returns_value_egp'] as num?)?.toDouble() ?? 0,
      returnsQty: (json['returns_qty'] as num?)?.toDouble() ?? 0,
      netValueEgp: (json['net_value_egp'] as num?)?.toDouble() ?? 0,
      returnPctOfGross: (json['return_pct_of_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SellInReturnsKpis {
  final double returnsValueEgp;
  final double returnsQty;
  final double grossValueEgp;
  final double netValueEgp;
  final double returnPctOfGross;
  final double? momChangePct;
  final String momDirection;
  final int focusMonth;

  const SellInReturnsKpis({
    this.returnsValueEgp = 0,
    this.returnsQty = 0,
    this.grossValueEgp = 0,
    this.netValueEgp = 0,
    this.returnPctOfGross = 0,
    this.momChangePct,
    this.momDirection = 'n/a',
    this.focusMonth = 0,
  });

  factory SellInReturnsKpis.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellInReturnsKpis();
    return SellInReturnsKpis(
      returnsValueEgp: (json['returns_value_egp'] as num?)?.toDouble() ?? 0,
      returnsQty: (json['returns_qty'] as num?)?.toDouble() ?? 0,
      grossValueEgp: (json['gross_value_egp'] as num?)?.toDouble() ?? 0,
      netValueEgp: (json['net_value_egp'] as num?)?.toDouble() ?? 0,
      returnPctOfGross: (json['return_pct_of_gross'] as num?)?.toDouble() ?? 0,
      momChangePct: (json['mom_change_pct'] as num?)?.toDouble(),
      momDirection: '${json['mom_direction'] ?? 'n/a'}',
      focusMonth: (json['focus_month'] as num?)?.toInt() ?? 0,
    );
  }
}

class SellInReturnsAdvisory {
  final int year;
  final int monthNum;
  final String branchName;
  final String productName;
  final double netValueEgp;
  final String messageAr;

  const SellInReturnsAdvisory({
    this.year = 0,
    this.monthNum = 0,
    this.branchName = '',
    this.productName = '',
    this.netValueEgp = 0,
    this.messageAr = '',
  });

  factory SellInReturnsAdvisory.fromJson(Map<String, dynamic> json) {
    return SellInReturnsAdvisory(
      year: (json['year'] as num?)?.toInt() ?? 0,
      monthNum: (json['month_num'] as num?)?.toInt() ?? 0,
      branchName: '${json['branch_name'] ?? ''}',
      productName: '${json['product_name'] ?? ''}',
      netValueEgp: (json['net_value_egp'] as num?)?.toDouble() ?? 0,
      messageAr: '${json['message_ar'] ?? ''}',
    );
  }
}

/// Phase-2 top returned product row.
class SellInReturnsTopProduct {
  final int rank;
  final String productCode;
  final String productName;
  final String productGroup;
  final double returnsValueEgp;
  final double returnsQty;
  final double grossValueEgp;
  final double netValueEgp;
  final double returnPctOfGross;
  final double shareOfReturns;

  const SellInReturnsTopProduct({
    this.rank = 0,
    this.productCode = '',
    this.productName = '',
    this.productGroup = '',
    this.returnsValueEgp = 0,
    this.returnsQty = 0,
    this.grossValueEgp = 0,
    this.netValueEgp = 0,
    this.returnPctOfGross = 0,
    this.shareOfReturns = 0,
  });

  factory SellInReturnsTopProduct.fromJson(Map<String, dynamic> json) {
    return SellInReturnsTopProduct(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      productCode: '${json['product_code'] ?? ''}',
      productName: '${json['product_name'] ?? ''}',
      productGroup: '${json['product_group'] ?? ''}',
      returnsValueEgp: (json['returns_value_egp'] as num?)?.toDouble() ?? 0,
      returnsQty: (json['returns_qty'] as num?)?.toDouble() ?? 0,
      grossValueEgp: (json['gross_value_egp'] as num?)?.toDouble() ?? 0,
      netValueEgp: (json['net_value_egp'] as num?)?.toDouble() ?? 0,
      returnPctOfGross: (json['return_pct_of_gross'] as num?)?.toDouble() ?? 0,
      shareOfReturns: (json['share_of_returns'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Phase-2 threshold alert when returns exceed normal levels.
class SellInReturnsAlert {
  final String severity; // warning | critical
  final String code;
  final String messageAr;
  final double value;
  final double threshold;
  final String context;

  const SellInReturnsAlert({
    this.severity = 'warning',
    this.code = '',
    this.messageAr = '',
    this.value = 0,
    this.threshold = 0,
    this.context = '',
  });

  bool get isCritical => severity == 'critical';

  factory SellInReturnsAlert.fromJson(Map<String, dynamic> json) {
    return SellInReturnsAlert(
      severity: '${json['severity'] ?? 'warning'}',
      code: '${json['code'] ?? ''}',
      messageAr: '${json['message_ar'] ?? ''}',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0,
      context: '${json['context'] ?? ''}',
    );
  }
}

class SellInReturnsFilterOptions {
  final List<int> years;
  final List<String> branches;
  final List<String> products;
  final List<String> productGroups;

  const SellInReturnsFilterOptions({
    this.years = const [],
    this.branches = const [],
    this.products = const [],
    this.productGroups = const [],
  });

  factory SellInReturnsFilterOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellInReturnsFilterOptions();
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return SellInReturnsFilterOptions(
      years: ((json['years'] as List?) ?? const []).map(asInt).where((y) => y > 0).toList(),
      branches: ((json['branches'] as List?) ?? const []).map((e) => '$e').toList(),
      products: ((json['products'] as List?) ?? const []).map((e) => '$e').toList(),
      productGroups: ((json['product_groups'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }
}

class SellInReturnsReport {
  final int year;
  final int month;
  final List<int> months;
  final SellInReturnsKpis kpis;
  final List<SellInReturnsMonthPoint> monthly;
  final List<SellInReturnsBranchRow> branches;
  final Map<int, SellInReturnsCell> columnTotals;
  final SellInReturnsCell grandTotal;
  final SellInReturnsFilterOptions filterOptions;
  final List<SellInReturnsAdvisory> advisories;
  final List<SellInReturnsTopProduct> topReturnedProducts;
  final List<SellInReturnsAlert> alerts;

  const SellInReturnsReport({
    this.year = 0,
    this.month = 0,
    this.months = const [],
    this.kpis = const SellInReturnsKpis(),
    this.monthly = const [],
    this.branches = const [],
    this.columnTotals = const {},
    this.grandTotal = const SellInReturnsCell(),
    this.filterOptions = const SellInReturnsFilterOptions(),
    this.advisories = const [],
    this.topReturnedProducts = const [],
    this.alerts = const [],
  });

  factory SellInReturnsReport.fromJson(Map<String, dynamic> json) {
    final col = <int, SellInReturnsCell>{};
    final rawCol = json['column_totals'];
    if (rawCol is Map) {
      rawCol.forEach((k, v) {
        final m = int.tryParse('$k');
        if (m != null && v is Map) {
          col[m] = SellInReturnsCell.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return SellInReturnsReport(
      year: (json['year'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      months: ((json['months'] as List?) ?? const [])
          .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
          .where((m) => m > 0)
          .toList(),
      kpis: SellInReturnsKpis.fromJson(
        json['kpis'] is Map ? Map<String, dynamic>.from(json['kpis'] as Map) : null,
      ),
      monthly: ((json['monthly'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SellInReturnsMonthPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      branches: ((json['branches'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SellInReturnsBranchRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      columnTotals: col,
      grandTotal: SellInReturnsCell.fromJson(
        json['grand_total'] is Map ? Map<String, dynamic>.from(json['grand_total'] as Map) : null,
      ),
      filterOptions: SellInReturnsFilterOptions.fromJson(
        json['filter_options'] is Map
            ? Map<String, dynamic>.from(json['filter_options'] as Map)
            : null,
      ),
      advisories: ((json['advisories'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SellInReturnsAdvisory.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      topReturnedProducts: ((json['top_returned_products'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SellInReturnsTopProduct.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      alerts: ((json['alerts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SellInReturnsAlert.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
