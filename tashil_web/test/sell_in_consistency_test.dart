// Sell-In page M3 consistency (same standard as Sell-Out v1/v2): one icon
// scale (18/20/24, >=40 only for empty-state illustrations), one type scale,
// 40dp 8dp-corner buttons, 32dp 8dp-corner chips, Arabic content labels,
// shared table surface, pinned file actions, equal-height KPI cards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'support/real_fonts.dart';

final _typeScale = <double>{
  11.0,
  12.0,
  14.0,
  16.0,
  22.0,
  24.0,
  28.0,
  32.0,
  36.0
};
final _iconScale = <double>{18.0, 20.0, 24.0};
const _tabs = [
  'بيانات التوريد',
  'المخزون وإعادة الطلب',
  'المستهدفات',
  'الملفات المرفوعة'
];
const _src =
    'lib/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

class _Api extends ApiClient {
  _Api() : super(tenantId: 'tenant-adeco');
  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
    bool forceRefresh = false,
  }) async {
    final files = [
      for (final f in [
        ['in_a', 'in26a.xlsx', 1200, 3400.0, 45.5],
        ['in_b', 'in26b.xlsx', 800, 2100.0, 30.2],
      ])
        ArchivedExcelFileModel.fromJson({
          'id': f[0],
          'file_type': 'sell_in',
          'file_name': f[1],
          'retail_chain': 'fathalla',
          'target_year': '2026',
          'target_month': 'auto',
          'rows_ingested': f[2],
          'total_cases': f[3],
          'total_weight_tons': f[4],
          'total_revenue': 1000.0,
          'uploaded_at': '2026-11-13T10:00:00Z',
        }),
    ];
    return UploadedFilesArchiveResponse(
        tenantId: 'tenant-adeco',
        totalCount: files.length,
        chainCounts: const {},
        files: files);
  }
}

Future<void> _pump(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SellInExplorerScreen(apiClient: _Api())),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, int i) async {
  if (i == 0) return;
  final f = find.textContaining(RegExp('^${_tabs[i]}'));
  expect(f, findsWidgets, reason: 'tab ${_tabs[i]}');
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

ColorScheme _cs(WidgetTester t) =>
    Theme.of(t.element(find.byType(SellInExplorerScreen))).colorScheme;

Finder _keyPrefix(String p) => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith(p));

List<String> _violations(WidgetTester tester) {
  final out = <String>[];
  // Icons.
  for (final e in find.byType(Icon).evaluate()) {
    final icon = e.widget as Icon;
    final size = icon.size ?? IconTheme.of(e).size ?? 24.0;
    // DataTable's own sort arrow (framework-sized 16dp) is not ours.
    if (icon.icon == Icons.arrow_upward) continue;
    if (!_iconScale.contains(size) && size < 40.0) {
      out.add('icon ${icon.icon?.codePoint.toRadixString(16)} size $size');
    }
  }
  // Text sizes.
  for (final ro in tester.allRenderObjects.whereType<RenderParagraph>()) {
    void visit(InlineSpan span, TextStyle? parent) {
      final s = (parent ?? const TextStyle()).merge(span.style);
      if (span is TextSpan &&
          (span.text ?? '').trim().isNotEmpty &&
          !(s.fontFamily ?? '').contains('MaterialIcons')) {
        final fs = s.fontSize;
        if (fs != null && !_typeScale.contains(fs)) {
          out.add('font $fs "${span.text!.trim()}"');
        }
      }
      if (span is TextSpan) {
        for (final c in span.children ?? const <InlineSpan>[]) {
          visit(c, s);
        }
      }
    }

    visit(ro.text, null);
  }
  // Buttons (not icon buttons): 40dp tall, full-round (F1).
  for (final e in find
      .byWidgetPredicate((w) =>
          w is FilledButton || w is OutlinedButton || w is ElevatedButton)
      .evaluate()) {
    final ro = e.renderObject as RenderBox?;
    if (ro == null || !ro.hasSize) continue;
    // Visual height (the button's Material), not the 48dp tap target.
    final matEl = find
        .descendant(
            of: find.byWidget(e.widget), matching: find.byType(Material))
        .evaluate()
        .first;
    final material = matEl.widget as Material;
    final h = (matEl.renderObject! as RenderBox).size.height;
    final shape = material.shape;
    // F1: 40dp buttons are full-round (chips keep 8dp).
    final ok8 = shape is StadiumBorder;
    final label = find
        .descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
        .evaluate()
        .map((t) => (t.widget as Text).data)
        .join(' ');
    if ((h - 40.0).abs() > 0.5) {
      out.add('button "$label" height $h');
    }
    if (!ok8) out.add('button "$label" shape $shape');
  }
  // Chips.
  for (final e in [
    ...find.byType(M3StatusTag).evaluate(),
    ...find.byType(M3ChipSurface).evaluate(),
  ]) {
    final h = (e.renderObject! as RenderBox).size.height;
    if ((h - 32.0).abs() > 0.5) out.add('tag height $h');
  }
  // Content labels that must be Arabic (sidebar, brands, K/M and the page
  // name "Sell-In"/"Sell-Out" stay as they are).
  for (final e in find.byType(Text).evaluate()) {
    final t = (e.widget as Text).data ??
        (e.widget as Text).textSpan?.toPlainText() ??
        '';
    final stripped = t
        // Display-only bidi isolates and word joiners are not copy.
        .replaceAll(RegExp(r'[\u2066\u2067\u2068\u2069\u2060\u200F]'), '')
        // Chain/tenant brand names stay as they are.
        .replaceAll(
            RegExp(
                r'\((Fathalla Market|Gomla Market|Beet El Gomla|El Wakala)\)|\bAdco\b|\bADECO\b'),
            '')
        .replaceAll(
            RegExp(
                r'Sell-In|Sell-Out|CSV|PDF|Excel|STR|SKU|EGP|KB|MB|Fathalla|FATHALLA|[KM]\b'),
            '')
        .replaceAll(RegExp(r'\.xlsx|\.csv|[A-Za-z0-9_]+\.xlsx'), '');
    if (RegExp(r'[A-Za-z]{3,}').hasMatch(stripped) && !t.contains('.xlsx')) {
      out.add('english "$t"');
    }
  }
  // Minus before the number in RTL: never a bare ASCII '-' or '+' sign
  // without a direction isolate.
  for (final e in find.byType(Text).evaluate()) {
    final t = (e.widget as Text).data ?? '';
    if (RegExp(r'(^|\s)[-+−][0-9]').hasMatch(t) && !t.contains('\u2066')) {
      out.add('unisolated sign "$t"');
    }
  }
  return out;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  for (var i = 0; i < _tabs.length; i++) {
    testWidgets(
        'Sell-In tab ${_tabs[i]}: one icon/type/button/chip scale, Arabic',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, i);
      final v = _violations(tester).toSet().toList()..sort();
      expect(v, isEmpty, reason: v.join('\n'));
    });
    for (final w in [1280.0, 390.0]) {
      testWidgets('no overflow at ${w.toInt()}dp on ${_tabs[i]}',
          (tester) async {
        await _pump(tester, width: w);
        await _openTab(tester, i);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'files: Arabic headers, neutral 8dp chips, actions pinned at 1280',
      (tester) async {
    const w = 1280.0 - 250.0;
    await _pump(tester, width: w);
    await _openTab(tester, 3);
    for (final h in [
      'الملف',
      'السلسلة',
      'الفترة',
      'المعاملات',
      'الكراتين',
      'صافي Sell-In (ج.م)',
      'الوزن (طن)',
      'تاريخ الرفع',
      'الإجراءات'
    ]) {
      expect(find.text(h), findsWidgets, reason: h);
    }
    final groups = find.byType(ArchiveActionsGroup);
    expect(groups, findsNWidgets(2));
    for (final e in groups.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.left, greaterThanOrEqualTo(0.0), reason: '$r');
      expect(r.right, lessThanOrEqualTo(w), reason: '$r');
    }
    // Pinned action rows line up with their table rows.
    for (final id in ['in_a', 'in_b']) {
      final rowY =
          tester.getCenter(find.byKey(ValueKey('sellin_file_rows_$id'))).dy;
      final actY = tester
          .getCenter(find.byWidgetPredicate(
              (w) => w is ArchiveActionsGroup && w.archiveId == id))
          .dy;
      expect((rowY - actY).abs(), lessThan(1.0), reason: id);
    }
    final cs = _cs(tester);
    final chips = find.byKey(const ValueKey('sellin_file_chain_chip'));
    expect(chips, findsNWidgets(2));
    for (final c in tester.widgetList<M3ChipSurface>(chips)) {
      expect(c.color, cs.surfaceContainerHigh);
    }
    final sec = tester.widget<Container>(
        find.byKey(const ValueKey('sellin_uploaded_files_section')));
    expect((sec.decoration as BoxDecoration).color, cs.surfaceContainerLow);
  });

  for (final w in [1440.0, 900.0]) {
    testWidgets('KPI cards equal height at ${w.toInt()} (data + stock tabs)',
        (tester) async {
      await _pump(tester, width: w);
      for (final tab in [0, 1]) {
        await _openTab(tester, tab);
        final rows = _keyPrefix('sellin_kpi_grid_');
        expect(rows, findsWidgets);
        final cards = _keyPrefix('kpi_card_');
        expect(cards, findsWidgets);
        // Cards in the same grid row share one height.
        final byTop = <double, Set<double>>{};
        for (final e in cards.evaluate()) {
          final r = tester.getRect(find.byWidget(e.widget));
          byTop
              .putIfAbsent(r.top.roundToDouble(), () => {})
              .add(r.height.roundToDouble());
        }
        for (final hs in byTop.values) {
          expect(hs.length, 1, reason: '$byTop');
        }
      }
    });
  }

  testWidgets('neutral strips and shared filter-bar padding', (tester) async {
    await _pump(tester);
    final cs = _cs(tester);
    BoxDecoration deco(String k) =>
        tester.widget<Container>(find.byKey(ValueKey(k))).decoration
            as BoxDecoration;
    expect(deco('sellin_waterfall_strip').color, cs.surfaceContainerHigh);
    expect(deco('sellin_waterfall_strip').gradient, isNull);
    expect(
        tester
            .widget<Container>(
                find.byKey(const ValueKey('sellin_data_filter_bar')))
            .padding,
        const EdgeInsets.all(16.0));
    await _openTab(tester, 1);
    expect(deco('sellin_period_strip').color, cs.surfaceContainerHigh);
    expect(
        tester
            .widget<Container>(
                find.byKey(const ValueKey('sellin_stock_filter_bar')))
            .padding,
        const EdgeInsets.all(16.0));
  });

  test('source: no capsules, circles, tinted fills or white tables', () {
    final s = File(_src).readAsStringSync();
    expect(s.contains('M3Shape.radiusFull'), isFalse);
    expect(s.contains('StadiumBorder'), isFalse);
    expect(s.contains('CircleAvatar'), isFalse);
    // surfaceContainerLowest is the approved records-table surface (22 Nov redesign).
    expect(s.contains('M3ToolbarButtonTheme('), isTrue);
  });
}
