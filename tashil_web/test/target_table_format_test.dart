import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_table_format.dart';

/// Drop bidi isolates and the word joiner so assertions read like the screen.
String _visible(String value) => value.replaceAll(
      RegExp('[\u2060\u2066\u2067\u2068\u2069]'),
      '',
    );

void main() {
  group('period', () {
    test('full year is just the year', () {
      expect(
        TargetTableFormat.period(
          year: 2027,
          month: 0,
          monthLabel: 'إجمالي سنة 2027 (كل الشهور)',
        ),
        '2027',
      );
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 0,
          monthLabel: 'سنة 2026',
        ),
        '2026',
      );
    });

    test('a month stays a short label', () {
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 3,
          monthLabel: 'مارس 2026',
        ),
        'مارس 2026',
      );
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 9,
          monthLabel: 'إجمالي سبتمبر 2026 (تفصيل طويل)',
        ),
        'سبتمبر 2026',
      );
    });

    test('a quarter stays Qn year', () {
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 0,
          monthLabel: 'Q1 2026',
        ),
        'Q1 2026',
      );
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 0,
          monthLabel: 'الربع الأول 2026',
        ),
        'Q1 2026',
      );
      expect(
        TargetTableFormat.period(
          year: 2026,
          month: 0,
          monthLabel: 'الربع الرابع',
        ),
        'Q4 2026',
      );
    });
  });

  group('scope', () {
    test('all branches and categories is just كل الفروع', () {
      expect(
        TargetTableFormat.scope(branch: 'كل الفروع', category: 'كل الفئات'),
        'كل الفروع',
      );
      expect(
        TargetTableFormat.scope(branch: '', category: ''),
        'كل الفروع',
      );
    });

    test('a specific scope keeps a short label', () {
      expect(
        TargetTableFormat.scope(branch: 'فرع المعادي', category: 'كل الفئات'),
        'فرع المعادي',
      );
      expect(
        TargetTableFormat.scope(branch: 'كل الفروع', category: 'عصائر'),
        'عصائر',
      );
      expect(
        TargetTableFormat.scope(branch: 'فرع المعادي', category: 'عصائر'),
        'فرع المعادي • عصائر',
      );
      expect(
        TargetTableFormat.scope(branch: '—', category: 'كل الفئات'),
        '—',
      );
    });
  });

  group('achievement', () {
    test('percentage only, dash when there are no sales', () {
      expect(
        TargetTableFormat.achievement(pct: 84.756, hasActuals: true),
        '84.8%',
      );
      expect(
        TargetTableFormat.achievement(pct: 0, hasActuals: false),
        '—',
      );
      expect(
        TargetTableFormat.achievement(pct: 84.8, hasActuals: true),
        isNot(contains('مستهدف')),
      );
    });
  });

  group('money and quantity', () {
    test('large values compact in millions and thousands', () {
      expect(_visible(TargetTableFormat.money(180000000)), '180M ج.م');
      expect(_visible(TargetTableFormat.money(127135120)), '127.1M ج.م');
      expect(_visible(TargetTableFormat.money(-22864880)), '−22.9M ج.م');
      expect(
        TargetTableFormat.money(-22864880).contains('-'),
        isFalse,
      );
      expect(
        _visible(TargetTableFormat.quantity(
          actual: 1532854,
          target: 250000,
          unit: 'وحدة',
        )),
        '1.53M / 250K وحدة',
      );
      expect(
        _visible(TargetTableFormat.quantity(
          actual: null,
          target: 2273513,
          unit: 'وحدة',
        )),
        '— / 2.27M وحدة',
      );
    });

    test('tooltips keep the exact value', () {
      expect(
        _visible(TargetTableFormat.moneyExact(180000000)),
        '180,000,000 ج.م',
      );
      expect(
        _visible(TargetTableFormat.moneyExact(127135120)),
        '127,135,120 ج.م',
      );
      expect(
        _visible(TargetTableFormat.moneyExact(-22864880)),
        '−22,864,880 ج.م',
      );
      expect(
        _visible(TargetTableFormat.quantityExact(
          actual: 1532854,
          target: 250000,
          unit: 'وحدة',
        )),
        '1,532,854 / 250,000 وحدة',
      );
      expect(
        _visible(TargetTableFormat.quantityExact(
          actual: null,
          target: 250000,
          unit: 'وحدة',
        )),
        '— / 250,000 وحدة',
      );
    });

    test('small amounts stay exact and missing stays a dash', () {
      expect(_visible(TargetTableFormat.money(850)), '850 ج.م');
      expect(_visible(TargetTableFormat.money(0)), '0 ج.م');
      expect(
        _visible(TargetTableFormat.quantity(
          actual: 12,
          target: 40,
          unit: 'وحدة',
        )),
        '12 / 40 وحدة',
      );
    });
  });
}
