import 'package:flutter/widgets.dart';

/// Copy shared by the three login mockups.
///
/// Form strings match the production login screen. Brand lines use the
/// product name (Tashil Data Sharing Platform), not tenant branding.
abstract final class LoginMockupCopy {
  static bool isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar';

  static String tashil(bool ar) => ar ? 'تسهيل' : 'Tashil';

  static String platform(bool ar) =>
      ar ? 'منصة مشاركة البيانات' : 'Data Sharing Platform';

  static String tagline(bool ar) => ar
      ? 'مكان واحد لسلاسل الشركاء لمشاركة بيانات البيع والتسعير.'
      : 'One place for partner chains to share sell-in, sell-out, and price data.';

  static String login(bool ar) => ar ? 'تسجيل الدخول' : 'Login';

  static String welcome(bool ar) => ar
      ? 'مرحباً بعودتك، يرجى إدخال بياناتك'
      : 'Welcome back, please enter your details';

  static String email(bool ar) => ar ? 'البريد الإلكتروني' : 'Email';

  static String emailRequired(bool ar) =>
      ar ? 'يرجى إدخال البريد الإلكتروني' : 'Please enter email';

  static String password(bool ar) => ar ? 'كلمة المرور' : 'Password';

  static String passwordRequired(bool ar) =>
      ar ? 'يرجى إدخال كلمة المرور' : 'Please enter password';

  static String credentialsRequired(bool ar) => ar
      ? 'يرجى إدخال البريد الإلكتروني وكلمة المرور'
      : 'Please enter email and password';

  static String loginSuccess(bool ar) =>
      ar ? 'مرحباً بك! تم تسجيل الدخول بنجاح' : 'Login Successful!';

  static String loginFailed(bool ar) => ar
      ? 'فشل تسجيل الدخول: يرجى التأكد من صحة البيانات'
      : 'Login failed: Please verify your credentials';

  static String remember(bool ar) => ar ? 'تذكرني' : 'Remember Me';

  static String forgot(bool ar) => ar ? 'نسيت كلمة المرور؟' : 'Forgot Password?';

  static String showPassword(bool ar) =>
      ar ? 'إظهار كلمة المرور' : 'Show password';

  static String hidePassword(bool ar) =>
      ar ? 'إخفاء كلمة المرور' : 'Hide password';

  static String noAccount(bool ar) =>
      ar ? 'ليس لديك حساب؟' : "Don't have an account?";

  static String contact(bool ar) =>
      ar ? 'تواصل على الرقم التالي' : 'Contact the following number';

  static String languageToggle(bool ar) => ar ? 'English' : 'العربية';

  static String languageToggleTooltip(bool ar) =>
      ar ? 'التبديل إلى الإنجليزية' : 'Switch to Arabic';

  static String heroHeadline(bool ar) => ar
      ? 'القرارات تبدأ ببيانات تجزئة مشتركة.'
      : 'Decisions start with shared retail data.';

  static String heroHeadlineCompact(bool ar) => ar
      ? 'بيانات التجزئة، جاهزة للقرار.'
      : 'Retail data, ready for the decision.';

  static String heroSupportCompact(bool ar) => ar
      ? 'البيع والتسعير في مكان واحد.'
      : 'Sell-in, sell-out, and pricing in one place.';

  static List<String> featureShortLabels(bool ar) => ar
      ? const ['تحليلات', 'إكسل', 'تسعير']
      : const ['Analytics', 'Excel', 'Pricing'];

  static String heroSupport(bool ar) => ar
      ? 'تجمع منصة تسهيل لمشاركة البيانات البيع الداخلي والخارجي والتسعير في مكان واحد لفريقك.'
      : 'Tashil Data Sharing Platform brings sell-in, sell-out, and pricing into one place for your team.';

  static List<LoginMockupFeature> features(bool ar) => [
        LoginMockupFeature(
          title: ar ? 'تحليلات البيع الداخلي والخارجي' : 'Sell-In / Sell-Out analytics',
          body: ar
              ? 'اقرأ الأداء عبر السلاسل دون تصدير ملف جديد.'
              : 'Read performance across chains without exporting another workbook.',
        ),
        LoginMockupFeature(
          title: ar ? 'استيراد إكسل ذكي' : 'Smart Excel ingestion',
          body: ar
              ? 'استورد ملفات الشركاء وعالج الاستثناءات في سياقها.'
              : 'Bring partner workbooks in, then resolve exceptions in context.',
        ),
        LoginMockupFeature(
          title: ar ? 'تسعير السلاسل' : 'Chain pricing',
          body: ar
              ? 'اجعل أسعار الأرفف والالتزام ظاهرة لكل سلسلة.'
              : 'Keep shelf prices and compliance visible for every chain.',
        ),
      ];

  static List<String> proofPoints(bool ar) => ar
      ? const ['بيع داخلي', 'بيع خارجي', 'تسعير السلاسل']
      : const ['Sell-in', 'Sell-out', 'Chain pricing'];

  static String motifCaption(bool ar) =>
      ar ? 'سلاسل الشركاء · هذا الشهر' : 'Partner chains · this month';
}

class LoginMockupFeature {
  const LoginMockupFeature({required this.title, required this.body});

  final String title;
  final String body;
}
