import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';

void main() {
  test('countSku uses the Arabic counted-noun rules', () {
    expect(countSku(0), '0 أصناف');
    expect(countSku(1), 'صنف واحد');
    expect(countSku(2), 'صنفان');
    expect(countSku(3), '3 أصناف');
    expect(countSku(10), '10 أصناف');
    expect(countSku(11), '11 صنفًا');
    expect(countSku(86), '86 صنفًا');
    expect(countSku(99), '99 صنفًا');
    expect(countSku(100), '100 صنف');
    expect(countSku(102), '102 صنف');
    expect(countSku(103), '103 أصناف');
    expect(countSku(111), '111 صنفًا');
  });

  test('countBranches uses the Arabic counted-noun rules', () {
    expect(countBranches(0), '0 فروع');
    expect(countBranches(1), 'فرع واحد');
    expect(countBranches(2), 'فرعان');
    expect(countBranches(4), '4 فروع');
    expect(countBranches(12), '12 فرعًا');
    expect(countBranches(100), '100 فرع');
  });

  test('countDay uses the Arabic counted-noun rules', () {
    expect(countDay(0), '0 أيام');
    expect(countDay(1), 'يوم واحد');
    expect(countDay(2), 'يومان');
    expect(countDay(5), '5 أيام');
    expect(countDay(12), '12 يومًا');
    expect(countDay(100), '100 يوم');
  });

  test('countMissingInBranch agrees the adjective with the counted noun', () {
    expect(countMissingInBranch(0), '0 أصناف منعدمة بالفرع');
    expect(countMissingInBranch(1), 'صنف واحد منعدم بالفرع');
    expect(countMissingInBranch(2), 'صنفان منعدمان بالفرع');
    expect(countMissingInBranch(3), '3 أصناف منعدمة بالفرع');
    expect(countMissingInBranch(18), '18 صنفًا منعدمًا بالفرع');
    expect(countMissingInBranch(100), '100 صنف منعدم بالفرع');
  });

  test('countRows uses the Arabic counted-noun rules', () {
    expect(countRows(0), '0 صفوف');
    expect(countRows(1), 'صف واحد');
    expect(countRows(2), 'صفان');
    expect(countRows(5), '5 صفوف');
    expect(countRows(12), '12 صفًا');
    expect(countRows(100), '100 صف');
    expect(countRows(389), '389 صفًا');
  });

  test('countError uses the Arabic counted-noun rules', () {
    expect(countError(0), '0 أخطاء');
    expect(countError(1), 'خطأ واحد');
    expect(countError(2), 'خطآن');
    expect(countError(5), '5 أخطاء');
    expect(countError(12), '12 خطأً');
    expect(countError(100), '100 خطأ');
    expect(countError(2004), '2004 أخطاء');
  });
}
