import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';

/// ChainSharePie renders market share distribution across retailer chains.
class ChainSharePie extends StatelessWidget {
  final List<ChainShareItem> chainShares;

  const ChainSharePie({
    super.key,
    required this.chainShares,
  });

  static const List<Color> _chainColors = [
    Color(0xFF10B981), // Fathalla: Emerald Green
    Color(0xFFF59E0B), // Gomla: Amber Orange
    Color(0xFF7C3AED), // Beet El Gomla: Royal Violet / Purple
    Color(0xFF2563EB), // Carrefour: Royal Blue
    Color(0xFFE11D48), // Spinneys: Crimson / Coral
    Color(0xFF0891B2), // Seoudi: Deep Cyan
    Color(0xFFD946EF), // Metro: Magenta Pink
    Color(0xFFDC2626), // Kazyon: Fire Red
  ];

  static Color colorForChain(String chainCode, [int fallbackIndex = -1]) {
    final clean = chainCode.trim().toLowerCase();
    switch (clean) {
      case 'fathalla':
        return const Color(0xFF10B981); // Emerald Green
      case 'gomla':
        return const Color(0xFFF59E0B); // Amber Orange
      case 'beet-elgomla':
      case 'beet_elgomla':
      case 'beet elgomla':
        return const Color(0xFF7C3AED); // Royal Violet / Purple (Distinguishable from Fathalla Green)
      case 'carrefour':
        return const Color(0xFF2563EB); // Royal Blue
      case 'spinneys':
        return const Color(0xFFE11D48); // Crimson / Coral
      case 'metro':
        return const Color(0xFFD946EF); // Magenta / Pink
      case 'seoudi':
      case 'chain-1080314':
      case 'el-wakala':
      case 'wakala':
      case 'الوكالة':
        return const Color(0xFF0891B2); // Deep Cyan
      case 'kazyon':
        return const Color(0xFFDC2626); // Fire Red
      default:
        if (fallbackIndex >= 0) {
          return _chainColors[fallbackIndex % _chainColors.length];
        }
        final hash = clean.codeUnits.fold<int>(0, (acc, c) => acc + c);
        // Offset by 3 so custom chains don't collide with Fathalla/Gomla/Beet El Gomla
        return _chainColors[3 + (hash % (_chainColors.length - 3))];
    }
  }

  static String labelForChain(String chainCode) {
    final clean = chainCode.trim().toLowerCase();
    switch (clean) {
      case 'fathalla':
        return 'أسواق فتح الله (Fathalla Market)';
      case 'gomla':
        return 'جملة ماركت (Gomla Market)';
      case 'beet-elgomla':
      case 'beet_elgomla':
      case 'beet elgomla':
        return 'بيت الجملة (Beet El Gomla)';
      case 'carrefour':
        return 'كارفور (Carrefour)';
      case 'spinneys':
        return 'سبينيس (Spinneys)';
      case 'metro':
        return 'مترو ماركت (Metro)';
      case 'seoudi':
        return 'سعودي ماركت (Seoudi)';
      case 'chain-1080314':
      case 'el-wakala':
      case 'wakala':
      case 'الوكالة':
      case 'الوكاله':
        return 'الوكالة (El Wakala)';
      default:
        return ApiClient.getRetailChainDisplayName(chainCode);
    }
  }

  /// Splits a combined bilingual string like `'أسواق فتح الله (Fathalla Market)'`
  /// or `'Fathalla (أسواق فتح الله)'` or `'بروكتر آند جامبل (حساب 2) (P&G)'`
  /// into an Arabic line (`ar`) and an English line (`en`).
  static ({String ar, String? en}) splitBilingualLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith(')')) {
      final lastOpen = trimmed.lastIndexOf('(');
      if (lastOpen > 0) {
        final first = trimmed.substring(0, lastOpen).trim();
        final second = trimmed.substring(lastOpen + 1, trimmed.length - 1).trim();
        final arabicRegex = RegExp(r'[\u0600-\u06FF]');
        final latinRegex = RegExp(r'[A-Za-z]');
        final firstHasAr = arabicRegex.hasMatch(first);
        final secondHasAr = arabicRegex.hasMatch(second);
        final firstHasEn = latinRegex.hasMatch(first);
        final secondHasEn = latinRegex.hasMatch(second);

        if (firstHasAr && !secondHasAr && secondHasEn) {
          return (ar: first, en: second);
        }
        if (secondHasAr && !firstHasAr && firstHasEn) {
          return (ar: second, en: first);
        }
      }
    }
    return (ar: trimmed, en: null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الحصص البيعية للسلاسل',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'Chain Market Share',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${chainShares.length} ${chainShares.length == 1 ? "سلسلة نشطة" : "سلاسل نشطة"}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${chainShares.length} Active ${chainShares.length == 1 ? "Chain" : "Chains"}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6.0),
                Icon(Icons.pie_chart_rounded, size: 20.0, color: colorScheme.primary),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'توزيع إيرادات مبيعات التجزئة وحجم الاستهلاك للسلاسل التي تحتوي على بيانات في الفترة المحددة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            M3Spacing.gapMD,
            // Stacked Bar Representation
            if (chainShares.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: SizedBox(
                  height: 14.0,
                  child: Row(
                    children: chainShares.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final color = colorForChain(item.retailerChain, idx);

                      return Expanded(
                        flex: (item.marketShare * 10).round().clamp(1, 1000),
                        child: Tooltip(
                          message: '${item.displayName}: ${item.marketShare.toStringAsFixed(1)}%',
                          child: Container(color: color),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            M3Spacing.gapMD,
            // Detailed Chain Breakdown List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chainShares.length,
              separatorBuilder: (_, __) => const Divider(height: 16.0),
              itemBuilder: (context, index) {
                final item = chainShares[index];
                final color = colorForChain(item.retailerChain, index);
                final rawLabel = (item.displayName.trim().isNotEmpty &&
                        item.displayName.trim().toLowerCase() !=
                            item.retailerChain.trim().toLowerCase())
                    ? item.displayName
                    : labelForChain(item.retailerChain);
                final parts = splitBilingualLabel(rawLabel);

                return Row(
                  children: [
                    Container(
                      width: 12.0,
                      height: 12.0,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    M3Spacing.gapSM,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parts.ar,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (parts.en != null) ...[
                            const SizedBox(height: 1.0),
                            Text(
                              parts.en!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.0,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2.0),
                          Text(
                            '${CurrencyFormatter.formatUnits(item.totalUnits)} عبوة مباعة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.formatCompactEGP(item.totalRevenue),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            '${item.marketShare.toStringAsFixed(1)}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
