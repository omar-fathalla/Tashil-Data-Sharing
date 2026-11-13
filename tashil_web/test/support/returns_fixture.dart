import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/features/sell_in_returns/data/sell_in_returns_repository.dart';
import 'package:tashil_web/features/sell_in_returns/domain/sell_in_returns_models.dart';

/// Fictional prefix shared by every fixture branch (display-only stripping).
const kReturnsFixturePrefix = 'سلسلة تجريبية XYZ - ';

const kReturnsFixtureBranches = [
  'سلسلة تجريبية XYZ - مخزن ألفا',
  'سلسلة تجريبية XYZ - فرع بيتا',
  'سلسلة تجريبية XYZ - المستودع المركزي',
  'سلسلة تجريبية XYZ - فرع النيل الجديد ذو الاسم الطويل للتحقق من اللف',
];

const kReturnsLongProductName =
    'صنف تجريبي طويل الاسم جداً للتحقق من لف الكلام لثلاثة سطور في جدول أعلى الأصناف المرتجعة';

SellInReturnsCell _cell({
  required double gross,
  required double returnsValue,
  required double qty,
}) {
  final net = gross - returnsValue;
  final pct = gross == 0 ? 0.0 : (returnsValue / gross) * 100;
  return SellInReturnsCell(
    grossValueEgp: gross,
    returnsValueEgp: returnsValue,
    returnsQty: qty,
    netValueEgp: net,
    returnPctOfGross: pct,
  );
}

/// Made-up returns report used at 1280 and 1024. No customer rows.
class ReturnsFakeRepo implements SellInReturnsRepository {
  ReturnsFakeRepo({this.momChangePct = 8.5});

  final double? momChangePct;

  @override
  Future<Result<SellInReturnsReport>> load(
    SellInReturnsQuery q, {
    bool forceRefresh = false,
  }) async {
    const months = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final values = <String, List<double>>{
      kReturnsFixtureBranches[0]: [
        11.1,
        17,
        7.6,
        43,
        0,
        99.3,
        57.5,
        3.6,
        67,
        9.0
      ],
      kReturnsFixtureBranches[1]: [
        26.1,
        15.4,
        5.1,
        7.4,
        8.7,
        23.3,
        101.3,
        29,
        65.9,
        12.5
      ],
      kReturnsFixtureBranches[2]: [
        5.8,
        14.5,
        6.5,
        6.8,
        9.5,
        12.4,
        18.4,
        13.7,
        20.1,
        19.5
      ],
      kReturnsFixtureBranches[3]: [
        8.1,
        7.5,
        6.2,
        1.4,
        3.1,
        6.9,
        4.2,
        16.8,
        10.1,
        45.3
      ],
    };
    final qtys = <String, List<double>>{
      kReturnsFixtureBranches[0]: [2, 3, 1, 5, 0, 8, 6, 1, 7, 2],
      kReturnsFixtureBranches[1]: [4, 3, 1, 2, 2, 4, 9, 3, 6, 2],
      kReturnsFixtureBranches[2]: [1, 3, 1, 1, 2, 2, 3, 2, 3, 3],
      kReturnsFixtureBranches[3]: [1, 1, 1, 1, 1, 1, 1, 2, 2, 5],
    };

    SellInReturnsBranchRow branch(String name) {
      final byMonth = <int, SellInReturnsCell>{};
      var totRet = 0.0, totGross = 0.0, totQty = 0.0;
      for (var i = 0; i < months.length; i++) {
        final ret = values[name]![i] * 1000;
        final qty = qtys[name]![i];
        final gross = ret * 5;
        byMonth[months[i]] = _cell(gross: gross, returnsValue: ret, qty: qty);
        totRet += ret;
        totGross += gross;
        totQty += qty;
      }
      return SellInReturnsBranchRow(
        branchKey: 'qa-$name',
        branchName: name,
        byMonth: byMonth,
        total: _cell(gross: totGross, returnsValue: totRet, qty: totQty),
      );
    }

    final branches = [for (final n in kReturnsFixtureBranches) branch(n)];
    final columnTotals = <int, SellInReturnsCell>{};
    for (final m in months) {
      var ret = 0.0, gross = 0.0, qty = 0.0;
      for (final b in branches) {
        final c = b.byMonth[m]!;
        ret += c.returnsValueEgp;
        gross += c.grossValueEgp;
        qty += c.returnsQty;
      }
      columnTotals[m] = _cell(gross: gross, returnsValue: ret, qty: qty);
    }
    var gRet = 0.0, gGross = 0.0, gQty = 0.0;
    for (final c in columnTotals.values) {
      gRet += c.returnsValueEgp;
      gGross += c.grossValueEgp;
      gQty += c.returnsQty;
    }

    return Success(
      SellInReturnsReport(
        year: 2026,
        months: months,
        kpis: SellInReturnsKpis(
          returnsValueEgp: gRet,
          returnsQty: gQty,
          grossValueEgp: gGross,
          netValueEgp: gGross - gRet,
          returnPctOfGross: gGross == 0 ? 0 : (gRet / gGross) * 100,
          momChangePct: momChangePct,
          momDirection: momChangePct == null
              ? 'n/a'
              : (momChangePct! >= 0 ? 'up' : 'down'),
          focusMonth: momChangePct == null ? 0 : 10,
        ),
        monthly: [
          for (final m in months)
            SellInReturnsMonthPoint(
              monthNum: m,
              monthAr: const [
                '',
                'يناير',
                'فبراير',
                'مارس',
                'أبريل',
                'مايو',
                'يونيو',
                'يوليو',
                'أغسطس',
                'سبتمبر',
                'أكتوبر',
              ][m],
              returnsValueEgp: columnTotals[m]!.returnsValueEgp,
              grossValueEgp: columnTotals[m]!.grossValueEgp,
              netValueEgp: columnTotals[m]!.netValueEgp,
            ),
        ],
        branches: branches,
        columnTotals: columnTotals,
        grandTotal: _cell(gross: gGross, returnsValue: gRet, qty: gQty),
        filterOptions: const SellInReturnsFilterOptions(
          years: [2026],
          branches: kReturnsFixtureBranches,
          products: [kReturnsLongProductName, 'صنف تجريبي قصير'],
          productGroups: ['مجموعة تجريبية'],
        ),
        topReturnedProducts: const [
          SellInReturnsTopProduct(
            rank: 1,
            productCode: 'QA-100',
            productName: kReturnsLongProductName,
            productGroup: 'مجموعة تجريبية',
            returnsValueEgp: 184000,
            returnsQty: 22,
            grossValueEgp: 920000,
            netValueEgp: 736000,
            returnPctOfGross: 20,
            shareOfReturns: 55.2,
          ),
          SellInReturnsTopProduct(
            rank: 2,
            productCode: 'QA-200',
            productName: 'صنف تجريبي قصير',
            productGroup: 'مجموعة تجريبية',
            returnsValueEgp: 74000,
            returnsQty: 9,
            grossValueEgp: 370000,
            netValueEgp: 296000,
            returnPctOfGross: 20,
            shareOfReturns: 22.1,
          ),
        ],
      ),
    );
  }
}
