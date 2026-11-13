// v141 live-test follow-up: tests must use the real content width
// (1280 viewport minus the 250dp sidebar = 1030) with real Cairo and
// the longest live-like labels. The previous 1280-only harness missed
// category clipping, the clipped RRP header, and the OOS branch-matrix
// horizontal scroll.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';

import 'oos_m3_support.dart' hide ignoreGoogleFontLoadErrors, disableGoogleFontsFetch;
import 'pricing_m3_support.dart';
import 'support/live_viewport.dart';

const kLiveCarpetCategory = 'منظفات سجاد ومفروشات';
const kLiveRrpHeader = 'السعر الموصى به (RRP)';
const kLiveNisBranch = 'فرع فتح الله - نيس';
const kLiveNisSku = 'عرض شركه فيبا بلس + 3 كجم & فيبا 3 كجم - 3 مجموعه';

class _LiveOosClient extends OosShotApiClient {
  @override
  Future<OOSMonitorResponseModel> getOOSMonitorReport() async {
    final base = await super.getOOSMonitorReport();
    final nis = [
      kLiveNisSku,
      'فيبا 4 كجم منظف متعدد الاغراض للممول',
      'ديفا هند سوب (1 مضخة +1 غيار)',
      'فلفيتا 3 لتر منعم ومعطر منسوجات رائحة الإنعاش',
      'كلوريل 2 كجم الوان روز',
      'عرض شركه جلسي 600 مل ( 1 عبوة بشاش & 1 عبوة اقتصادى ) - 6 مجموعة',
      'ميبا بلس + 3 كجم منظف اطباق تليم - 6 عبوه',
      'فلفيتا 3 لتر جل غسيل اوتوماتيك للملابس الملونة و البيضاء برائحة اللافندر',
    ];
    final extra = <OOSAlertModel>[
      for (var i = 0; i < nis.length; i++)
        OOSAlertModel(
          alertId: 'nis_$i',
          retailerChain: 'fathalla',
          storeId: 'fat_nice',
          storeName: kLiveNisBranch,
          itemCode: 'FG-NIS-${i.toString().padLeft(4, '0')}',
          barcode: '6221133099${i.toString().padLeft(2, '0')}',
          skuName: nis[i],
          brand: i.isEven ? 'فيبا (Feba)' : 'فلفيتا (Velvetta)',
          category: 'منظفات منزلية',
          estimatedLostDailyCost: 430.0 - i * 12,
          consecutiveDaysOOS: 5,
          severity: 'critical',
        ),
      // Singular branch: grammar must be «منعدم», not «منعدمة».
      OOSAlertModel(
        alertId: 'one_1',
        retailerChain: 'fathalla',
        storeId: 'fat_one',
        storeName: 'فرع فتح الله - الواحد',
        itemCode: 'FG-ONE-0001',
        barcode: '6221133000001',
        skuName: kLiveNisSku,
        brand: 'فيبا (Feba)',
        category: 'منظفات منزلية',
        estimatedLostDailyCost: 120.0,
        consecutiveDaysOOS: 3,
        severity: 'high',
      ),
    ];
    final alerts = [...base.alerts, ...extra];
    final lost = alerts.fold<double>(0, (s, a) => s + a.estimatedLostDailyCost);
    return OOSMonitorResponseModel(
      totalIncidents: alerts.length,
      totalLostDailyCost: lost,
      alerts: alerts,
      brandSummaries: base.brandSummaries,
      branchSummaries: base.branchSummaries,
      aiAnalysis: base.aiAnalysis,
    );
  }
}

Future<void> _pumpAtLiveContent(
  WidgetTester tester,
  Widget page, {
  double height = 3600,
}) async {
  tester.view.physicalSize = Size(kLiveContentWidth, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: page),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpAtLiveViewportWithSidebar(
  WidgetTester tester,
  Widget page, {
  double height = 3600,
}) async {
  tester.view.physicalSize = Size(kLiveViewportWidth, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          const SizedBox(
            width: kLiveSidebarWidth,
            child: ColoredBox(color: Color(0xFFECEEE6)),
          ),
          Expanded(child: Scaffold(body: page)),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

bool _inContent(WidgetTester tester, Finder f, {required double contentWidth}) {
  expect(f, findsWidgets);
  final box = tester.getRect(f.first);
  return box.left < contentWidth - 1 &&
      box.right > 1 &&
      box.top < 8000 &&
      box.bottom > 0;
}

/// True when [expected] is fully laid out inside [scope] in at most 3 lines
/// and the text's paint rect sits inside the scope's rect (no parent clip).
bool _labelFullyVisible(WidgetTester tester, Finder scope, String expected) {
  final texts = find.descendant(of: scope, matching: find.text(expected));
  if (texts.evaluate().isEmpty) return false;
  final textEl = texts.evaluate().first;
  final text = textEl.widget as Text;
  if ((text.maxLines ?? 99) < 3) return false;
  final para = tester.renderObject<RenderParagraph>(
      find.byElementPredicate((x) => x == textEl));
  final tp = TextPainter(
    text: TextSpan(text: expected, style: text.style ?? para.text.style),
    textDirection: Directionality.of(textEl),
    textScaler: MediaQuery.textScalerOf(textEl),
    maxLines: 3,
  )..layout(maxWidth: para.size.width);
  if (tp.didExceedMaxLines) return false;
  final scopeBox = tester.getRect(scope);
  final textBox = tester.getRect(texts.first);
  const slop = 1.5;
  return textBox.left >= scopeBox.left - slop &&
      textBox.right <= scopeBox.right + slop &&
      textBox.top >= scopeBox.top - slop &&
      textBox.bottom <= scopeBox.bottom + slop;
}

double _hScrollExtent(WidgetTester tester, Finder scope) {
  final scrollable =
      find.descendant(of: scope, matching: find.byType(Scrollable));
  if (scrollable.evaluate().isEmpty) return 0;
  for (final el in scrollable.evaluate()) {
    final s = el.widget as Scrollable;
    if (s.axisDirection == AxisDirection.right ||
        s.axisDirection == AxisDirection.left) {
      final state = tester.state<ScrollableState>(find.byWidget(s));
      if (state.position.hasContentDimensions) {
        return state.position.maxScrollExtent;
      }
    }
  }
  return 0;
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadPricingFonts();
  });

  testWidgets(
      'Pricing long categories and RRP header fit at live 1030 content width',
      (tester) async {
    await _pumpAtLiveContent(
      tester,
      PricingComplianceScreen(apiClient: PricingShotApiClient()),
      height: 3600,
    );
    await tester.tap(find.text('عروض نشطة'));
    await tester.pumpAndSettle();

    for (final name in [
      kLiveCarpetCategory,
      'مسحوق غسالات اطباق',
      kLongCategory,
    ]) {
      final chip = find.widgetWithText(FilterChip, name);
      expect(chip, findsOneWidget, reason: name);
      expect(_inContent(tester, chip, contentWidth: kLiveContentWidth), isTrue,
          reason: name);
      expect(_labelFullyVisible(tester, chip, name), isTrue,
          reason: 'category "$name" must wrap inside the chip, not clip');
    }

    final rrp = find.text(kLiveRrpHeader);
    expect(rrp, findsOneWidget);
    expect(_inContent(tester, rrp, contentWidth: kLiveContentWidth), isTrue);
    final rrpText = tester.widget<Text>(rrp);
    expect(rrpText.maxLines, greaterThanOrEqualTo(2));
    expect(rrpText.overflow, isNot(TextOverflow.ellipsis));
    expect(rrpText.overflow, isNot(TextOverflow.fade));
    final table = find.byKey(const ValueKey('pricing_compliance_table'));
    expect(table, findsOneWidget);
    expect(_labelFullyVisible(tester, table, kLiveRrpHeader), isTrue,
        reason: 'RRP header must wrap inside its column');
    expect(
        _hScrollExtent(
            tester, find.byKey(const ValueKey('pricing_table_scroll'))),
        lessThanOrEqualTo(2.0));
  });

  testWidgets(
      'Pricing long categories still wrap when the 250dp sidebar is present at 1280',
      (tester) async {
    await _pumpAtLiveViewportWithSidebar(
      tester,
      PricingComplianceScreen(apiClient: PricingShotApiClient()),
    );
    await tester.tap(find.text('عروض نشطة'));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(FilterChip, kLiveCarpetCategory);
    expect(chip, findsOneWidget);
    expect(_inContent(tester, chip, contentWidth: kLiveContentWidth), isTrue);
    expect(_labelFullyVisible(tester, chip, kLiveCarpetCategory), isTrue);
    expect(_labelFullyVisible(
        tester,
        find.byKey(const ValueKey('pricing_compliance_table')),
        kLiveRrpHeader), isTrue);
  });

  testWidgets(
      'OOS نيس branch matrix fits at live 1030; daily loss visible; singular grammar',
      (tester) async {
    await _pumpAtLiveContent(
      tester,
      OOSDashboardScreen(apiClient: _LiveOosClient()),
      height: 4200,
    );
    final matrix = find.text('مصفوفة الفروع والنواقص');
    expect(matrix, findsOneWidget);
    await tester.ensureVisible(matrix);
    await tester.pumpAndSettle();
    await tester.tap(matrix);
    await tester.pumpAndSettle();

    expect(find.text(kLiveNisBranch), findsOneWidget);
    await tester.ensureVisible(find.text(kLiveNisBranch));
    await tester.pumpAndSettle();

    final scroller =
        find.byKey(const ValueKey('oos_matrix_table_$kLiveNisBranch'));
    expect(scroller, findsOneWidget);
    expect(_hScrollExtent(tester, scroller), lessThanOrEqualTo(2.0),
        reason: 'نيس table must not scroll horizontally at 1030');

    expect(find.text('الفاقد اليومي'), findsWidgets);
    expect(_inContent(tester, find.text('الفاقد اليومي'),
        contentWidth: kLiveContentWidth), isTrue);
    expect(find.text(kLiveNisSku), findsWidgets);
    expect(_inContent(tester, find.text(kLiveNisSku),
        contentWidth: kLiveContentWidth), isTrue);
    expect(_labelFullyVisible(tester, scroller, kLiveNisSku), isTrue,
        reason: 'long نيس item name must wrap inside the table');

    expect(find.text('صنف واحد منعدم بالفرع'), findsOneWidget);
    expect(find.text('صنف واحد منعدمة بالفرع'), findsNothing);
  });
}
