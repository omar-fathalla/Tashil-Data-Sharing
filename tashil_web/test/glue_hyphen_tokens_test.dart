import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/glue_hyphen_tokens.dart';

void main() {
  test('glueHyphenTokens keeps hyphens and is display-only reversible', () {
    const raw = 'QA-NOT-IN-MASTER-999';
    final glued = glueHyphenTokens(raw);
    expect(glued, isNot(raw));
    expect(glued.contains(kWordJoiner), isTrue);
    expect(glued.contains('-'), isTrue);
    expect(stripWordJoiners(glued), raw);
    expect(glueHyphenTokens('6221133011903'), '6221133011903');
  });
}
