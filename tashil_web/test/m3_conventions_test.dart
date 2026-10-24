import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guard rails for the M3 migration. Widget tests that look up
/// icons or widget types stay valid only while these conventions hold, so a
/// regression fails here with a clear file:line instead of in a random test.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  List<String> offenders(RegExp re) => [
        for (final f in files)
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (re.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
      ];

  test('only Rounded Material icons are used', () {
    final bad = offenders(RegExp(r'(?<![A-Za-z])Icons\.(?![a-z0-9_]+_rounded\b)[a-z0-9_]+'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no legacy DropdownButton (use M3Dropdown)', () {
    final bad = offenders(RegExp(r'\bDropdownButton<'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no legacy DropdownButtonFormField (use M3Dropdown)', () {
    final bad = offenders(RegExp(r'\bDropdownButtonFormField\b'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no raw BorderRadius.circular outside the shape tokens', () {
    final bad = offenders(RegExp(r'BorderRadius\.circular\('))
        .where((l) => !l.startsWith('lib/core/theme/'))
        // The logo's corner scales with its size, so it can't be a fixed token.
        .where((l) => !l.contains('size * 0.24'))
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no raw numeric fontSize outside the theme (use M3FontSize / textTheme)', () {
    final bad = offenders(RegExp(r'fontSize:\s*[\d.]+'))
        .where((l) => !l.startsWith('lib/core/theme/'))
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('raw Color(0x..) only in theme files or allowlisted identity palettes', () {
    const allow = [
      'lib/core/theme/',
      'lib/core/widgets/data_sharing_logo.dart',
      'lib/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart',
      'lib/features/sell_out_analytics/presentation/widgets/barcode_scanner_dialog.dart',
      'lib/features/trade_marketing/domain/trade_marketing_models.dart',
    ];
    final bad = offenders(RegExp(r'Color\(0x'))
        .where((l) => !allow.any(l.startsWith))
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no inline TextStyle(fontSize:) outside lib/core/theme (legacy allowlist)', () {
    // Files not yet migrated to M3TextVariants / textTheme. Shrink this list;
    // never add to it. Sell-In / Sell-Out / Targets are already clean.
    const legacy = <String>[
      'lib/core/widgets/m3_responsive_tab_bar.dart',
      'lib/features/auth/presentation/screens/tenant_login_screen.dart',
      'lib/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart',
      'lib/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart',
      'lib/features/data_ingestion/presentation/screens/upload_portal_screen.dart',
      'lib/features/data_ingestion/presentation/widgets/ai_analysis_progress_card.dart',
      'lib/features/data_ingestion/presentation/widgets/anomaly_resolution_table.dart',
      'lib/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart',
      'lib/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart',
      'lib/features/product_master/presentation/screens/product_master_screen.dart',
      'lib/features/sell_out_analytics/presentation/widgets/barcode_scanner_dialog.dart',
      'lib/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart',
      'lib/features/store_benchmark/presentation/screens/store_matrix_screen.dart',
      'lib/features/super_admin/presentation/screens/super_admin_screen.dart',
      'lib/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart',
    ];
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart') || p.startsWith('lib/core/theme/') || legacy.contains(p)) continue;
      final s = f.readAsStringSync();
      for (final m in RegExp(r'TextStyle\(').allMatches(s)) {
        // Styles merged onto a textTheme role are bound to the theme.
        if (RegExp(r'merge\(\s*(const\s+)?$').hasMatch(s.substring(m.start < 20 ? 0 : m.start - 20, m.start))) continue;
        var i = m.end, d = 1;
        while (d > 0 && i < s.length) {
          final ch = s[i];
          if (ch == '(') d++;
          if (ch == ')') d--;
          i++;
        }
        if (RegExp(r'\bfontSize:').hasMatch(s.substring(m.end, i - 1))) {
          bad.add('$p:${s.substring(0, m.start).split('\n').length}');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('Sell-In / Sell-Out / Targets use theme colour roles, not Material swatches', () {
    const files = [
      'lib/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart',
      'lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart',
      'lib/features/sell_out_analytics/presentation/widgets/target_management_panel.dart',
    ];
    // Any Colors.<swatch> (teal, red, orange, …) incl. .shadeNNN; only
    // transparent/white/black are allowed. Use M3StatusColors.of(context).
    final swatch = RegExp(r'(?<![A-Za-z0-9_])Colors\.(?!transparent\b|white\b|black\b)[a-z][A-Za-z]*');
    final bad = <String>[];
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (swatch.hasMatch(lines[i])) bad.add('$f:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
