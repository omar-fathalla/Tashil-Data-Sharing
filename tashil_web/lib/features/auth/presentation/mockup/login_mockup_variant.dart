/// Owner-review layouts for the desktop login mockup.
///
/// Selected from the scratch entrypoint with `?variant=a|b|c`.
enum LoginMockupVariant {
  /// Split screen: brand panel and login card.
  a,

  /// Centered elevated card on a tonal background.
  b,

  /// Hero headline with feature highlights and an outlined form.
  c;

  static LoginMockupVariant parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'b':
      case '2':
        return LoginMockupVariant.b;
      case 'c':
      case '3':
        return LoginMockupVariant.c;
      case 'a':
      case '1':
      default:
        return LoginMockupVariant.a;
    }
  }
}

/// Desktop layouts collapse to one column below this width.
const double kLoginMockupWideBreakpoint = 960;
