// MOCKUP ONLY. Shared pieces for the three login page mockups.
// Not wired into the production router or TenantLoginScreen.

import 'package:flutter/material.dart';

import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/app_icons.dart';

/// Arabic or English copy for the ambient locale.
String loginTr(BuildContext context, String ar, String en) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

/// Support line shown on the current login screen.
const String loginSupportPhone = '01211857725';

/// One platform capability, described from the shipped screen it names.
class LoginFeature {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;

  const LoginFeature({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
  });
}

/// The seven features reviewed for the login page, in the reviewer's order.
const List<LoginFeature> loginFeatures = [
  LoginFeature(
    icon: AppIcons.analytics,
    titleAr: 'تحليل المبيعات والتوريد',
    titleEn: 'Sell-In & Sell-Out analytics',
    bodyAr: 'المبيعات والتوريد حسب السلسلة والفرع والصنف مقابل المستهدف.',
    bodyEn: 'Sales and supply by chain, branch and SKU against targets.',
  ),
  LoginFeature(
    icon: AppIcons.oos,
    titleAr: 'مراقب النواقص',
    titleEn: 'OOS monitor',
    bodyAr: 'الأصناف الناقصة في كل فرع مع تقدير المبيعات المفقودة.',
    bodyEn: 'Out-of-stock items per branch with estimated lost sales.',
  ),
  LoginFeature(
    icon: AppIcons.storeMatrix,
    titleAr: 'مصفوفة الفروع',
    titleEn: 'Store matrix',
    bodyAr: 'قارن أداء الفروع جنبًا إلى جنب عبر السلاسل.',
    bodyEn: 'Benchmark branches side by side across chains.',
  ),
  LoginFeature(
    icon: AppIcons.pricing,
    titleAr: 'التسعير ومقارنة المنافسين',
    titleEn: 'Pricing & competitor compare',
    bodyAr: 'التزام الأسعار بالسعر المقترح ومقارنة أصنافك بالمنافسين.',
    bodyEn: 'Price compliance against RRP and SKU-level competitor compare.',
  ),
  LoginFeature(
    icon: AppIcons.tradeMarketing,
    titleAr: 'عائد التسويق التجاري',
    titleEn: 'Trade marketing ROI',
    bodyAr: 'سجّل المصروفات الترويجية وقِس عائدها على المبيعات.',
    bodyEn: 'Log promotional spend and measure its return on sales.',
  ),
  LoginFeature(
    icon: AppIcons.cpfr,
    titleAr: 'التجديد وأوامر الشراء (CPFR)',
    titleEn: 'CPFR replenishment',
    bodyAr: 'اقتراح كميات التجديد وأوامر الشراء من مبيعات ومخزون الفروع.',
    bodyEn: 'Replenishment quantities and POs from branch sales and stock.',
  ),
  LoginFeature(
    icon: AppIcons.ai,
    titleAr: 'رفع Excel الذكي',
    titleEn: 'Smart Excel ingestion',
    bodyAr: 'ارفع ملفات السلاسل ويتم تعريف الأعمدة والباركود تلقائيًا.',
    bodyEn: 'Upload chain files; columns and barcodes are mapped for you.',
  ),
];

/// Tenant-neutral English wordmark. Always LTR, in both locales.
class TashilWordmark extends StatelessWidget {
  final Color? color;

  const TashilWordmark({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = color ?? cs.onSurface;
    return Semantics(
      label: 'Tashil Data Sharing',
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Tashil',
              style: theme.textTheme.titleLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            const SizedBox(width: M3Spacing.s12),
            SizedBox(
              width: 1.0,
              height: 20.0,
              child: ColoredBox(color: fg.withValues(alpha: 0.4)),
            ),
            const SizedBox(width: M3Spacing.s12),
            Text(
              'Data Sharing',
              style: theme.textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Outlined language switch: flips locale and, with it, text direction.
class LoginLanguageButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LoginLanguageButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Tooltip(
      message: isAr ? 'Switch to English' : 'التبديل إلى العربية',
      child: OutlinedButton.icon(
        key: const ValueKey('login_language_button'),
        onPressed: onPressed,
        icon: const Icon(Icons.language_rounded),
        label: Text(
          isAr ? 'English' : 'العربية',
          textDirection: isAr ? TextDirection.ltr : TextDirection.rtl,
        ),
      ),
    );
  }
}

/// Wordmark at the start, language switch at the end.
class LoginTopBar extends StatelessWidget {
  final VoidCallback onToggleLocale;
  final Color? wordmarkColor;
  final bool showWordmark;

  const LoginTopBar({
    super.key,
    required this.onToggleLocale,
    this.wordmarkColor,
    this.showWordmark = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64.0,
      child: Row(
        children: [
          if (showWordmark) TashilWordmark(color: wordmarkColor),
          const Spacer(),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: LoginLanguageButton(onPressed: onToggleLocale),
          ),
        ],
      ),
    );
  }
}

/// Places the form first in keyboard focus order, ahead of the top bar.
class LoginFocusOrder extends StatelessWidget {
  final Widget child;

  const LoginFocusOrder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: child,
    );
  }
}

/// Signature of the submit handler. Throw to show the inline error banner.
typedef LoginSubmit = Future<void> Function(
  String email,
  String password,
  bool rememberMe,
);

/// The login form shared by all three mockups. Width is set by the caller
/// (400–440dp); the form never stretches beyond its parent.
class LoginMockupForm extends StatefulWidget {
  final LoginSubmit onSubmit;
  final VoidCallback onForgotPassword;
  final bool autofocusEmail;

  /// Pre-filled failure, used only to render the error state for review.
  final String? initialError;

  const LoginMockupForm({
    super.key,
    required this.onSubmit,
    required this.onForgotPassword,
    this.autofocusEmail = false,
    this.initialError,
  });

  @override
  State<LoginMockupForm> createState() => _LoginMockupFormState();
}

class _LoginMockupFormState extends State<LoginMockupForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await widget.onSubmit(
        _emailController.text.trim(),
        _passwordController.text,
        _rememberMe,
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _isLoading = false;
        _error = msg.trim().isEmpty
            ? loginTr(
                context,
                'تعذّر تسجيل الدخول. تحقّق من البيانات وحاول مرة أخرى.',
                'Sign-in failed. Check your details and try again.',
              )
            : msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String tr(String ar, String en) => loginTr(context, ar, en);
    final signInLabel = tr('تسجيل الدخول', 'Sign in');

    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(signInLabel, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: M3Spacing.xs),
            Text(
              tr('مرحبًا بعودتك، أدخل بيانات حسابك للمتابعة.',
                  'Welcome back. Enter your account details to continue.'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: M3Spacing.md),
            Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TestSemantics(
                      identifier: TestIds.loginEmail,
                      label: tr('البريد الإلكتروني', 'Email'),
                      textField: true,
                      child: TextFormField(
                        key: const ValueKey('login_email'),
                        controller: _emailController,
                        autofocus: widget.autofocusEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [
                          AutofillHints.email,
                          AutofillHints.username,
                        ],
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: tr('البريد الإلكتروني', 'Email'),
                          prefixIcon: const Icon(Icons.mail_rounded),
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) {
                            return tr('أدخل البريد الإلكتروني',
                                'Enter your email');
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return tr('صيغة البريد الإلكتروني غير صحيحة',
                                'Enter a valid email address');
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: M3Spacing.sm),
                    TestSemantics(
                      identifier: TestIds.loginPassword,
                      label: tr('كلمة المرور', 'Password'),
                      textField: true,
                      child: TextFormField(
                        key: const ValueKey('login_password'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textDirection: TextDirection.ltr,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: tr('كلمة المرور', 'Password'),
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            key: const ValueKey('login_password_visibility'),
                            tooltip: _obscurePassword
                                ? tr('إظهار كلمة المرور', 'Show password')
                                : tr('إخفاء كلمة المرور', 'Hide password'),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? tr('أدخل كلمة المرور', 'Enter your password')
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: M3Spacing.xs),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _RememberMe(
                  value: _rememberMe,
                  label: tr('تذكرني', 'Remember me'),
                  onChanged: (v) => setState(() => _rememberMe = v),
                ),
                TextButton(
                  key: const ValueKey('login_forgot_password'),
                  onPressed: widget.onForgotPassword,
                  child: Text(tr('نسيت كلمة المرور؟', 'Forgot password?')),
                ),
              ],
            ),
            const SizedBox(height: M3Spacing.md),
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: M3Spacing.sm),
            ],
            TestSemantics(
              identifier: TestIds.loginSubmit,
              label: signInLabel,
              button: true,
              child: FilledButton(
                key: const ValueKey('login_submit'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40.0),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLoading) ...[
                      SizedBox.square(
                        dimension: 18.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: cs.onPrimary,
                        ),
                      ),
                      const SizedBox(width: M3Spacing.xs),
                    ],
                    Text(signInLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: M3Spacing.md),
            _ContactLine(),
          ],
        ),
      ),
    );
  }
}

class _RememberMe extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _RememberMe({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        key: const ValueKey('login_remember_me'),
        borderRadius: M3Shape.radiusFull,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48.0),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: M3Spacing.s12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        key: const ValueKey('login_error_banner'),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: M3Shape.radiusMd,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: M3Spacing.sm,
            vertical: M3Spacing.s12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_rounded, size: 20.0, color: cs.onErrorContainer),
              const SizedBox(width: M3Spacing.s12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          loginTr(context, 'ليس لديك حساب؟ تواصل معنا على',
              "Don't have an account? Call us at"),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        Semantics(
          link: true,
          child: TextButton.icon(
            key: const ValueKey('login_support_phone'),
            onPressed: () =>
                WebFileHelper.openUrlInNewTab('tel:$loginSupportPhone'),
            icon: const Icon(Icons.call_rounded, size: 18.0),
            label: Text(
              ltrIsolate(loginSupportPhone),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ],
    );
  }
}

/// 40dp secondaryContainer circle with a 24dp rounded symbol.
class LoginFeatureIcon extends StatelessWidget {
  final IconData icon;

  const LoginFeatureIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 40.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 24.0, color: cs.onSecondaryContainer),
      ),
    );
  }
}

/// List-row presentation: icon circle, then name and one line.
class LoginFeatureTile extends StatelessWidget {
  final LoginFeature feature;
  final Color? titleColor;
  final Color? bodyColor;

  const LoginFeatureTile({
    super.key,
    required this.feature,
    this.titleColor,
    this.bodyColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoginFeatureIcon(icon: feature.icon),
        const SizedBox(width: M3Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loginTr(context, feature.titleAr, feature.titleEn),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: titleColor ?? cs.onSurface),
              ),
              Text(
                loginTr(context, feature.bodyAr, feature.bodyEn),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: bodyColor ?? cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Outlined card presentation (outlineVariant, 12dp radius, 16dp padding).
class LoginFeatureCard extends StatelessWidget {
  final LoginFeature feature;
  final Color? background;

  const LoginFeatureCard({super.key, required this.feature, this.background});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? cs.surface,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: M3Spacing.pSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoginFeatureIcon(icon: feature.icon),
            const SizedBox(height: M3Spacing.s12),
            Text(
              loginTr(context, feature.titleAr, feature.titleEn),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: M3Spacing.xxs),
            Text(
              loginTr(context, feature.bodyAr, feature.bodyEn),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Equal-height rows of [columns]; a short last row is centred (4 + 3).
class LoginFeatureGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  /// False keeps a short last row at the start, for list-style tiles.
  final bool centerLastRow;

  const LoginFeatureGrid({
    super.key,
    required this.columns,
    required this.children,
    this.centerLastRow = true,
    this.spacing = M3Spacing.sm,
    this.runSpacing = M3Spacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (columns == 1) {
      for (final child in children) {
        if (rows.isNotEmpty) rows.add(SizedBox(height: runSpacing));
        rows.add(child);
      }
    }
    for (var i = 0; columns > 1 && i < children.length; i += columns) {
      final chunk = children.sublist(
        i,
        (i + columns).clamp(0, children.length),
      );
      final missing = columns - chunk.length;
      // Each side of a short row absorbs half of the missing cells and gaps,
      // so its cards keep the full-row width.
      final edgeGap = missing * spacing / 2;
      final cells = <Widget>[];
      if (missing > 0 && centerLastRow) {
        cells.add(Spacer(flex: missing));
        cells.add(SizedBox(width: edgeGap));
      }
      for (var j = 0; j < chunk.length; j++) {
        if (j > 0) cells.add(SizedBox(width: spacing));
        cells.add(Expanded(flex: 2, child: chunk[j]));
      }
      if (missing > 0) {
        cells.add(SizedBox(width: centerLastRow ? edgeGap : missing * spacing));
        cells.add(Spacer(flex: centerLastRow ? missing : missing * 2));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: runSpacing));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Optional section header above the feature grids.
class LoginFeaturesHeader extends StatelessWidget {
  const LoginFeaturesHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        loginTr(context, 'ماذا تقدم المنصة', 'What the platform does'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
