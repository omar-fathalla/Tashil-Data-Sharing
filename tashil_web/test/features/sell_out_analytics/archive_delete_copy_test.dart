import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/archive_delete_copy.dart';

void main() {
  test('auto or empty month covers all months', () {
    expect(archiveFileCoversAllMonths('auto', isLastFile: false), isTrue);
    expect(archiveFileCoversAllMonths('', isLastFile: false), isTrue);
    expect(archiveFileCoversAllMonths('all', isLastFile: false), isTrue);
  });

  test('a specific month covers all months only when it is the last file', () {
    expect(archiveFileCoversAllMonths('01', isLastFile: false), isFalse);
    expect(archiveFileCoversAllMonths('10', isLastFile: false), isFalse);
    expect(archiveFileCoversAllMonths('10', isLastFile: true), isTrue);
  });

  test(
      'Sell-Out dialog omits the other-months claim when the file covers all months',
      () {
    final all = sellOutDeleteConsequenceText(coversAllMonths: true);
    expect(all.contains('لن تتأثر باقي الشهور'), isFalse);
    expect(all.contains('Sell-In'), isTrue);
    final some = sellOutDeleteConsequenceText(coversAllMonths: false);
    expect(some.contains('لن تتأثر باقي الشهور'), isTrue);
  });

  test(
      'Sell-In dialog omits the other-months claim when the file covers all months',
      () {
    final all = sellInDeleteConsequenceText(coversAllMonths: true);
    expect(all.contains('لن تتأثر باقي الشهور'), isFalse);
    expect(all.contains('Sell-Out'), isTrue);
  });
}
