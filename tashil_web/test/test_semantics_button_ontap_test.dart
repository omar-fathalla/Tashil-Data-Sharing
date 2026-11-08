import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';

SemanticsNode? findNodeById(WidgetTester tester, String id) {
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return null;
  SemanticsNode? found;
  void walk(SemanticsNode node) {
    if (found != null) return;
    if (node.getSemanticsData().identifier == id) {
      found = node;
      return;
    }
    node.visitChildren((child) {
      walk(child);
      return found == null;
    });
  }

  walk(root);
  return found;
}

Future<void> tapSemanticsId(WidgetTester tester, String id) async {
  final node = findNodeById(tester, id);
  expect(node, isNotNull, reason: 'expected semantics id $id');
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  expect(owner, isNotNull);
  owner!.performAction(node!.id, SemanticsAction.tap);
  await tester.pump();
}

void main() {
  testWidgets('TestSemantics.button owns tap and is flagged as button',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TestSemantics.button(
              identifier: TestIds.deleteConfirm,
              label: 'Confirm delete',
              onPressed: () => taps += 1,
              child: const Text('حذف'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = findNodeById(tester, TestIds.deleteConfirm);
      expect(node, isNotNull);
      final data = node!.getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tapSemanticsId(tester, TestIds.deleteConfirm);
      expect(taps, 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
      'file-delete inside DataTable stays a tappable button (not cell-only)',
      (tester) async {
    final handle = tester.ensureSemantics();
    var deletes = 0;
    const archiveId = 'arc-42';
    const fileName = 'QA Sell Out.xlsx';
    final deleteId = TestIds.fileDelete(
      archiveId: archiveId,
      fileName: fileName,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataTable(
              columns: const [
                DataColumn(label: Text('File')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                DataRow(
                  cells: [
                    const DataCell(Text(fileName)),
                    DataCell(
                      ArchiveActionsGroup(
                        archiveId: archiveId,
                        fileName: fileName,
                        onEdit: () {},
                        onDownload: () {},
                        onDelete: () => deletes += 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = findNodeById(tester, deleteId);
      expect(node, isNotNull, reason: 'expected $deleteId in semantics tree');
      final data = node!.getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tapSemanticsId(tester, deleteId);
      expect(deletes, 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('sellout upload button semantics exposes tap action',
      (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TestSemantics.button(
              identifier: TestIds.selloutUploadButton,
              label: 'Upload Sell-Out file',
              onPressed: () => pressed += 1,
              child: FilledButton(
                onPressed: () => pressed += 1,
                child: const Text('رفع'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = findNodeById(tester, TestIds.selloutUploadButton);
      expect(node, isNotNull);
      expect(node!.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tapSemanticsId(tester, TestIds.selloutUploadButton);
      // excludeSemantics on TestSemantics.button → only the outer onTap fires.
      expect(pressed, 1);
    } finally {
      handle.dispose();
    }
  });
}
