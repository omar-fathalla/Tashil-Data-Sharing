import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';

int countSemanticsIdentifiers(WidgetTester tester, String id) {
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return 0;

  var count = 0;
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().identifier == id) {
      count += 1;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return count;
}

void main() {
  group('TestIds', () {
    test('fileToken sanitizes names for file-row / file-delete ids', () {
      expect(TestIds.fileToken('Sales Jan.xlsx'), 'sales-jan.xlsx');
      expect(TestIds.fileToken('  A__B  '), 'a__b');
      expect(TestIds.fileToken('!!!'), 'unnamed');
    });

    test('fileRow / fileDelete include archive id for uniqueness', () {
      expect(
        TestIds.fileRow(archiveId: 'arc-1', fileName: 'Report Q1.csv'),
        'file-row-arc-1-report-q1.csv',
      );
      expect(
        TestIds.fileDelete(archiveId: 'arc-1', fileName: 'Report Q1.csv'),
        'file-delete-arc-1-report-q1.csv',
      );
    });

    test('identical file names with different archive ids do not collide', () {
      final a = TestIds.fileRow(archiveId: 'id-aaa', fileName: 'same.xlsx');
      final b = TestIds.fileRow(archiveId: 'id-bbb', fileName: 'same.xlsx');
      expect(a, isNot(equals(b)));
      expect(
        TestIds.fileDelete(archiveId: 'id-aaa', fileName: 'same.xlsx'),
        isNot(
          equals(
            TestIds.fileDelete(archiveId: 'id-bbb', fileName: 'same.xlsx'),
          ),
        ),
      );
      expect(a, 'file-row-id-aaa-same.xlsx');
      expect(b, 'file-row-id-bbb-same.xlsx');
    });

    test('catalog constants use kebab-case login / nav ids', () {
      expect(TestIds.loginEmail, 'login-email');
      expect(TestIds.loginPassword, 'login-password');
      expect(TestIds.loginSubmit, 'login-submit');
      expect(TestIds.logout, 'logout');
      expect(TestIds.navSellOut, 'nav-sell-out');
      expect(TestIds.navSellIn, 'nav-sell-in');
      expect(TestIds.navPricing, 'nav-pricing');
      expect(TestIds.navCompare, 'nav-compare');
      expect(TestIds.selloutUploadButton, 'sellout-upload-button');
      expect(TestIds.selloutTargetsTab, 'sellout-targets-tab');
      expect(TestIds.selloutTargetsAdd, 'sellout-targets-add');
      expect(TestIds.selloutTargetsExport, 'sellout-targets-export');
      expect(TestIds.selloutTargetDetailBack, 'sellout-target-detail-back');
      expect(TestIds.fileInput, 'tashil-file-input');
      expect(TestIds.uploadCommitConfirm, 'upload-commit-confirm');
      expect(TestIds.uploadCommitCancel, 'upload-commit-cancel');
      expect(TestIds.deleteConfirm, 'delete-confirm');
      expect(TestIds.snackbarError, 'snackbar-error');
      expect(TestIds.navIdForIndex(1), TestIds.navSellOut);
      expect(TestIds.navIdForIndex(2), TestIds.navSellIn);
      expect(TestIds.navIdForIndex(3), TestIds.navReturns);
      expect(TestIds.navIdForIndex(6), TestIds.navPricing);
      expect(TestIds.navIdForIndex(7), TestIds.navCompare);
      expect(TestIds.navIdForIndex(0), isNull);
      // file-delete ids are archiveId + '-' + slugified filename
      expect(
        TestIds.fileDelete(
          archiveId: 'AbC_123',
          fileName: 'QA Sell Out.xlsx',
        ),
        'file-delete-abc_123-qa-sell-out.xlsx',
      );
    });
  });

  testWidgets('key catalog identifiers each appear exactly once in the tree',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                for (final id in TestIds.keyCatalogIds)
                  TestSemantics(
                    identifier: id,
                    label: id,
                    button: true,
                    child: Text(id),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in TestIds.keyCatalogIds) {
        expect(
          countSemanticsIdentifiers(tester, id),
          1,
          reason: 'expected exactly one Semantics node for "$id"',
        );
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('navTarget attaches identifier once (not duplicated on siblings)',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TestSemantics.navTarget(
                  identifier: TestIds.navSellOut,
                  label: 'Sell-Out',
                  child: Icon(Icons.analytics_rounded),
                ),
                Icon(Icons.analytics_rounded),
                Text('Sell-Out'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(countSemanticsIdentifiers(tester, TestIds.navSellOut), 1);
    } finally {
      handle.dispose();
    }
  });
}
