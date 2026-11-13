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

/// "مخالفة واحدة" / "مخالفتان" / "5 مخالفات" / "12 مخالفةً" / "100 مخالفة".
String countViolation(int n) => arabicCount(n,
    one: 'مخالفة واحدة',
    two: 'مخالفتان',
    few: 'مخالفات',
    many: 'مخالفةً',
    hundred: 'مخالفة');

/// "عنصر واحد" / "عنصران" / "5 عناصر" / "12 عنصرًا" / "100 عنصر".
String countItem(int n) => arabicCount(n,
    one: 'عنصر واحد',
    two: 'عنصران',
    few: 'عناصر',
    many: 'عنصرًا',
    hundred: 'عنصر');

/// "ملف واحد" / "ملفان" / "5 ملفات" / "12 ملفًا" / "100 ملف".
String countFiles(int n) => arabicCount(n,
    one: 'ملف واحد', two: 'ملفان', few: 'ملفات', many: 'ملفًا', hundred: 'ملف');

/// "شيت واحد" / "شيتان" / "5 شيتات" / "12 شيتًا" / "100 شيت".
String countSheets(int n) => arabicCount(n,
    one: 'شيت واحد', two: 'شيتان', few: 'شيتات', many: 'شيتًا', hundred: 'شيت');

/// "فرع واحد" / "فرعان" / "5 فروع" / "12 فرعًا" / "100 فرع".
String countBranches(int n) => arabicCount(n,
    one: 'فرع واحد', two: 'فرعان', few: 'فروع', many: 'فرعًا', hundred: 'فرع');

/// "سجل واحد" / "سجلان" / "5 سجلات" / "12 سجلًا" / "100 سجل".
String countRecords(int n) => arabicCount(n,
    one: 'سجل واحد', two: 'سجلان', few: 'سجلات', many: 'سجلًا', hundred: 'سجل');

/// "سلسلة مسجلة واحدة" / "سلسلتان مسجلتان" / "5 سلاسل مسجلة" / "12 سلسلة مسجلة".
String countRegisteredChains(int n) => arabicCount(n,
    one: 'سلسلة مسجلة واحدة',
    two: 'سلسلتان مسجلتان',
    few: 'سلاسل مسجلة',
    many: 'سلسلة مسجلة',
    hundred: 'سلسلة مسجلة');

/// "يوم واحد" / "يومان" / "5 أيام" / "12 يومًا" / "100 يوم".
String countDay(int n) => arabicCount(n,
    one: 'يوم واحد',
    two: 'يومان',
    few: 'أيام',
    many: 'يومًا',
    hundred: 'يوم');

/// "صنف واحد منعدم بالفرع" / "صنفان منعدمان بالفرع" / "5 أصناف منعدمة بالفرع"
/// / "12 صنفًا منعدمًا بالفرع" / "100 صنف منعدم بالفرع".
String countMissingInBranch(int n) {
  if (n == 1) return 'صنف واحد منعدم بالفرع';
  if (n == 2) return 'صنفان منعدمان بالفرع';
  if (n == 0) return '0 أصناف منعدمة بالفرع';
  final r = n % 100;
  if (r >= 3 && r <= 10) return '$n أصناف منعدمة بالفرع';
  if (r >= 11) return '$n صنفًا منعدمًا بالفرع';
  return '$n صنف منعدم بالفرع';
}
