import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';

void main() {
  group('TestIds', () {
    test('fileToken sanitizes names for file-row / file-delete ids', () {
      expect(TestIds.fileToken('Sales Jan.xlsx'), 'sales-jan.xlsx');
      expect(TestIds.fileToken('  A__B  '), 'a__b');
      expect(TestIds.fileToken('!!!'), 'unnamed');
      expect(TestIds.fileRow('Report Q1.csv'), 'file-row-report-q1.csv');
      expect(TestIds.fileDelete('Report Q1.csv'), 'file-delete-report-q1.csv');
    });

    test('catalog constants use kebab-case login / nav ids', () {
      expect(TestIds.loginEmail, 'login-email');
      expect(TestIds.loginPassword, 'login-password');
      expect(TestIds.loginSubmit, 'login-submit');
      expect(TestIds.logout, 'logout');
      expect(TestIds.navSellOut, 'nav-sell-out');
      expect(TestIds.navSellIn, 'nav-sell-in');
      expect(TestIds.selloutUploadButton, 'sellout-upload-button');
      expect(TestIds.deleteConfirm, 'delete-confirm');
      expect(TestIds.snackbarError, 'snackbar-error');
    });
  });
}
