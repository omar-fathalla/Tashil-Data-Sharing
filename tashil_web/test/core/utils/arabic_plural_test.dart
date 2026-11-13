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
}
