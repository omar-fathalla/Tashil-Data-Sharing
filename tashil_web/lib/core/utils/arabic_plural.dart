/// Arabic counted nouns (تمييز العدد) for UI counts.
///
/// 1 → "صنف واحد", 2 → "صنفان", 3–10 → "n أصناف" (plural),
/// 11–99 → "n صنفًا" (singular, accusative), 100, 101, 102, 200… →
/// "n صنف" (singular, genitive), 0 → "0 أصناف".
String arabicCount(
  int n, {
  required String one,
  required String two,
  required String few,
  required String many,
  required String hundred,
}) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n == 0) return '$n $few';
  final r = n % 100;
  if (r >= 3 && r <= 10) return '$n $few';
  if (r >= 11) return '$n $many';
  return '$n $hundred';
}

/// "صنف واحد" / "صنفان" / "5 أصناف" / "86 صنفًا" / "100 صنف".
String countSku(int n) => arabicCount(n,
    one: 'صنف واحد', two: 'صنفان', few: 'أصناف', many: 'صنفًا', hundred: 'صنف');

/// "منافس واحد" / "منافسان" / "5 منافسين" / "86 منافسًا" / "105 منافسين".
///
/// 101–110 take the plural like 3–10 (handled by [arabicCount]).
String countCompetitors(int n) => arabicCount(n,
    one: 'منافس واحد',
    two: 'منافسان',
    few: 'منافسين',
    many: 'منافسًا',
    hundred: 'منافس');

/// "سلسلة نشطة واحدة" / "سلسلتان نشطتان" / "5 سلاسل نشطة" / "12 سلسلة نشطة".
String countActiveChains(int n) => arabicCount(n,
    one: 'سلسلة نشطة واحدة',
    two: 'سلسلتان نشطتان',
    few: 'سلاسل نشطة',
    many: 'سلسلة نشطة',
    hundred: 'سلسلة نشطة');
