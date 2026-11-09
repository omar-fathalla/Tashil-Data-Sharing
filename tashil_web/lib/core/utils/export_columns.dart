/// Excel/CSV export column orders, kept in one place so UI table changes
/// (M3 migration, RTL, re-ordering visible columns) can never silently
/// reorder exported files. `test/export_columns_test.dart` pins these.
class ExportColumns {
  ExportColumns._();

  /// Used by cpfr_dashboard_screen.dart.
  static const List<String> cpfrReplenishment = [
    'اسم الصنف (SKU)',
    'العلامة التجارية (Brand)',
    'القطاع (Sector)',
    'الإقليم (Region)',
    'المحافظة (Governorate)',
    'مندوب المبيعات (Sales Rep)',
    'إجمالي التوريد بالكرتونة (Sell-In Cases)',
    'البيع الفعلي التقديري بالكرتونة (Sell-Out Cases)',
    'المرتجعات بالكرتونة (Returns)',
    'الرصيد التقديري الحالي بالكرتونة (Est. Stock Cases)',
    'قيمة الرصيد التقديري (Est. Stock EGP)',
    'معدل السحب اليومي (Daily Run-Rate Cases)',
    'أيام تغطية المخزون (DOI Days)',
    'حالة الرصيد (Stock Status)',
    'أمر التوريد المقترح بالكرتونة (Suggested PO Cases)',
    'قيمة أمر التوريد المقترح (Suggested PO EGP)',
    'وزن أمر التوريد بالطن (Suggested PO Tons)',
  ];

  /// Used by sell_in_explorer_screen.dart.
  static const List<String> sellInReconciliation = [
    'السنة (Year)',
    'الشهر (Month)',
    'حالة الفترة',
    'رصيد أول الشهر بالكرتونة (Opening Cases)',
    'رصيد أول الشهر بالجنيه (Opening EGP)',
    'التوريد الشهري بالكرتونة (Sell-In Cases)',
    'قيمة التوريد الشهري (Sell-In EGP)',
    'المبيعات الفعلية بالكرتونة التقديرية (Sell-Out Cases)',
    'قيمة المبيعات الفعلية (Sell-Out EGP)',
    'صافي حركة الشهر بالكرتونة (Monthly Net Cases)',
    'صافي حركة الشهر بالجنيه (Monthly Net EGP)',
    'الرصيد المتبقي آخر الشهر بالكرتونة (Closing Stock Cases)',
    'الرصيد المتبقي آخر الشهر بالجنيه (Closing Stock EGP)',
    'نسبة التصريف (Sell-Through %)',
    'تشخيص حالة الرصيد (Stock Health)',
  ];

  /// Used by sell_in_explorer_screen.dart.
  static const List<String> sellInRecords = [
    'السنة',
    'الشهر',
    'السلسلة',
    'المحافظة / الإقليم',
    'العميل / الفرع',
    'القطاع',
    'العلامة التجارية',
    'الفئة الفرعية',
    'كود الصنف (Item Code)',
    'الباركود (Barcode)',
    'اسم الصنف',
    'مندوب المبيعات',
    'شد الكرتونة (Units/Carton)',
    'الكمية بالكرتونة (Cases)',
    'إجمالي الكمية بالقطعة (Units)',
    'سعر الكرتونة الرسمي (Official Carton Excl VAT)',
    'سعر الكرتونة الفعلي (Actual Case Price Excl VAT)',
    'نسبة الخصم الفعلي %',
    'صافي قيمة التوريد غير شامل الضريبة (Net EGP)',
    'ضريبة القيمة المضافة 14% (VAT EGP)',
    'إجمالي قيمة الفاتورة شامل الضريبة (Gross Incl VAT EGP)',
    'الوزن بالطن (Tons)',
    'حالة التسعير (Pricing Wave)',
    'الشيت المصدري (Source Sheet)',
  ];

  /// Used by sell_out_explorer_screen.dart.
  static const List<String> sellOutRecords = [
    'الباركود الدولي',
    'اسم الصنف',
    'السلسلة',
    'الفرع',
    'الفئة',
    'الكمية المباعة',
    'سعر الوحدة',
    'صافي المبيعات (ج.م)',
    'تاريخ البيع',
  ];

  /// Used by sell_in_returns_screen.dart (Phase-2 Excel export — branch×month matrix).
  static const List<String> sellInReturnsMatrix = [
    'الفرع (Branch)',
    'الشهر (Month)',
    'إجمالي التوريد (Gross EGP)',
    'قيمة المرتجع (Returns EGP)',
    'كمية المرتجع (Returns Qty)',
    'صافي التوريد بعد المرتجعات (Net EGP)',
    'نسبة المرتجع من الإجمالي %',
  ];

  /// Used by sell_in_returns_screen.dart (Phase-2 Excel export — top returned products).
  static const List<String> sellInReturnsTopProducts = [
    'الترتيب (Rank)',
    'كود الصنف (Item Code)',
    'اسم الصنف (Product)',
    'مجموعة الصنف (Group)',
    'قيمة المرتجع (Returns EGP)',
    'كمية المرتجع (Returns Qty)',
    'إجمالي التوريد (Gross EGP)',
    'صافي بعد المرتجعات (Net EGP)',
    'نسبة المرتجع من الإجمالي %',
    'حصة من إجمالي المرتجعات %',
  ];

}
