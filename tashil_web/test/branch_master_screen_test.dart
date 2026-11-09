import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/branch_master/data/branch_master_repository.dart';
import 'package:tashil_web/features/branch_master/presentation/screens/branch_master_screen.dart';

class _FakeBranchMasterDS implements BranchMasterDataSource {
  @override
  Future<BranchMasterState> load() async => const BranchMasterState(
        bootstrapDone: true,
        branches: [
          BranchMasterBranch(code: 'FTH-001', chainCode: 'FTH', displayName: 'سموحة'),
          BranchMasterBranch(
            code: 'FTH-UNALLOC',
            chainCode: 'FTH',
            displayName: 'غير موزع على فرع',
            unallocated: true,
          ),
        ],
        aliases: [
          BranchMasterAlias(rawName: 'عائلة فتح الله ماركت - سموحة', branchCode: 'FTH-001', source: 'bootstrap'),
        ],
        pending: [
          BranchMasterPending(
            id: 'p1',
            rawName: 'دمنهور ستاد',
            suggestedCode: 'FTH-002',
            suggestedName: 'دمنهور',
            altSuggestedCode: 'FTH-003',
            altSuggestedName: 'دمنهور الاستاد',
            reasonAr: 'التباس — بانتظار تأكيد',
            kind: 'ambiguous',
          ),
        ],
      );

  @override
  Future<void> updateDisplayName(String branchCode, String displayName) async {}

  @override
  Future<void> confirmPending(String pendingId, {String branchCode = '', String newDisplayName = ''}) async {}

  @override
  Future<void> rejectPending(String pendingId) async {}
}

void main() {
  testWidgets('BranchMasterScreen lists branches, aliases, pending (RTL)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BranchMasterScreen(dataSource: _FakeBranchMasterDS()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('إدارة الفروع'), findsOneWidget);
    expect(find.byKey(const Key('branch_row_FTH-001')), findsOneWidget);
    expect(find.textContaining('سموحة'), findsWidgets);

    await tester.tap(find.textContaining('المستعارة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('alias_row_عائلة فتح الله ماركت - سموحة')), findsOneWidget);

    await tester.tap(find.textContaining('معلّق'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pending_branch_p1')), findsOneWidget);
    expect(find.byKey(const Key('pending_confirm_p1')), findsOneWidget);
  });
}
