// Test-only Trade Marketing fixture: made-up campaigns, vendors and EGP
// amounts at live-like magnitudes (millions, long Arabic titles). No
// customer data. Shared by Trade Marketing widget tests and shots.
import 'package:tashil_web/features/trade_marketing/data/trade_marketing_repository.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';

const tmLongCampaignTitle =
    'تأجير فلورات عرض رئيسية وجوندولات مدخل الفروع مع ستاندات ترويجية مضيئة لموسم رمضان والعيد';
const tmLongVendor = 'وكالة الدعاية والإعلان التجريبية المتكاملة للتسويق الميداني';
const tmLongBrand = 'علامة تجريبية بريميوم للعناية المنزلية';

class TmLiveScaleRepo implements TradeMarketingRepository {
  TmLiveScaleRepo({
    this.withLastYear = true,
    this.withExpenses = true,
    this.withPreviousMonth = true,
  });

  /// false: last-year same-month sales are missing (YoY must show «—»).
  final bool withLastYear;

  /// false: no campaigns/expenses (MoM/ROMI must show «—», not fake +0).
  final bool withExpenses;

  /// false: previous-month Sell-Out missing (MoM must show «—»).
  final bool withPreviousMonth;

  static const chains = ['Fathalla', 'Kazyon', 'Seoudi'];

  late final List<MarketingExpenseItem> items = [
    if (withExpenses)
      for (var m = 1; m <= 10; m++)
        for (var c = 0; c < chains.length; c++)
          for (var k = 0; k < MarketingExpenseCategory.values.length; k++)
            MarketingExpenseItem(
              id: 'tm_${m}_${c}_$k',
              year: 2026,
              month: m,
              chainName: chains[c],
              category: MarketingExpenseCategory.values[k],
              brandName: k.isEven ? tmLongBrand : 'علامة تجريبية',
              campaignTitle:
                  k == 0 ? tmLongCampaignTitle : 'حملة تجريبية رقم $m-$c-$k',
              vendorOrAgency: k == 1 ? tmLongVendor : 'مورد تجريبي $k',
              amountEgp: 185000.0 + 12500.0 * m + 7300.0 * k + 3100.0 * c,
              notes: 'ملاحظة تجريبية',
              createdAt: DateTime(2026, m, 3),
            ),
  ];

  @override
  Future<List<MarketingExpenseItem>> listExpenses(
          {int? year, int? month, String? chain}) async =>
      items
          .where((e) =>
              (year == null || e.year == year) &&
              (month == null || month == 0 || e.month == month) &&
              (chain == null || chain.isEmpty || e.chainName == chain))
          .toList();

  @override
  Future<List<TradeMarketingSalesBaseline>> getRoi(
      {int? year, int? month, String? chain}) async {
    final out = <TradeMarketingSalesBaseline>[];
    if (!withExpenses) return out;
    for (var m = 1; m <= 10; m++) {
      if (month != null && month != 0 && month != m) continue;
      for (var c = 0; c < chains.length; c++) {
        if (chain != null && chain.isNotEmpty && chain != chains[c]) continue;
        final spend = items
            .where((e) => e.month == m && e.chainName == chains[c])
            .fold<double>(0, (a, e) => a + e.amountEgp);
        final cur = 48750000.0 + 1250000.0 * m + 2300000.0 * c;
        out.add(TradeMarketingSalesBaseline(
          year: 2026,
          month: m,
          chainName: chains[c],
          currentMonthSalesEgp: cur,
          previousMonthSalesEgp:
              withPreviousMonth ? cur - 1850000.0 : 0,
          lastYearSameMonthSalesEgp: withLastYear ? cur * 0.82 : 0,
          currentMonthSellInEgp: cur * 0.9,
          marketingSpendEgp: spend,
        ));
      }
    }
    return out;
  }

  @override
  Future<MarketingExpenseItem> saveExpense(MarketingExpenseItem item,
      {required bool isNew}) async {
    items.removeWhere((e) => e.id == item.id);
    items.add(item);
    return item;
  }

  @override
  Future<void> deleteExpense(String id) async =>
      items.removeWhere((e) => e.id == id);

  @override
  Future<ExpenseUploadResult> uploadExpenses(
          List<int> bytes, String filename) async =>
      const ExpenseUploadResult(0, 0, []);
}
