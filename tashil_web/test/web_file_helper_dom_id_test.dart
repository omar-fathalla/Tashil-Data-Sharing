import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';

void main() {
  test('persistent file input DOM id is stable for Playwright setInputFiles', () {
    expect(kTashilFileInputDomId, 'tashil-file-input');
    expect(TestIds.fileInput, kTashilFileInputDomId);
  });

  test('ensureMounted is safe on VM stub', () {
    expect(() => WebFileHelper.ensureMounted(), returnsNormally);
  });
}
