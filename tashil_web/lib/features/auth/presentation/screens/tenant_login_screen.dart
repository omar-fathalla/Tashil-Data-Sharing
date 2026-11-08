import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../main.dart';
import '../widgets/forgot_password_dialog.dart';

/// TenantLoginScreen provides unified Material Design 3 login experience
/// matching the Tashil ecosystem design system (Tashil / Data Sharing).
class TenantLoginScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String tenantSlug;
  final ValueChanged<LoginResultModel> onLoginSuccess;
  final VoidCallback? onNavigateToAdmin;
  final bool isGenericCompanyPortal;

  const TenantLoginScreen({
    super.key,
    required this.apiClient,
    required this.tenantSlug,
    required this.onLoginSuccess,
    this.onNavigateToAdmin,
    this.isGenericCompanyPortal = false,
  });

  @override
  State<TenantLoginScreen> createState() => _TenantLoginScreenState();
}

class _TenantLoginScreenState extends State<TenantLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fillDefaultCredentials();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.decelerate),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  @override
  void didUpdateWidget(covariant TenantLoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantSlug != widget.tenantSlug ||
        oldWidget.isGenericCompanyPortal != widget.isGenericCompanyPortal) {
      _fillDefaultCredentials();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillDefaultCredentials() {
    _emailController.text = '';
    _passwordController.text = '';
  }

  bool get _isArabic => appLocaleNotifier.value.languageCode == 'ar';

  void _toggleLanguage() {
    toggleAppLocale();
    setState(() {});
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      M3Feedback.showError(
        context,
        _isArabic
            ? 'يرجى إدخال البريد الإلكتروني وكلمة المرور'
            : 'Please enter email and password',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isGeneric = widget.isGenericCompanyPortal ||
          widget.tenantSlug == 'company' ||
          widget.tenantSlug == 'portal';

      final resolvedTenant = isGeneric
          ? ApiClient.findTenantSlugForEmail(email)
          : widget.tenantSlug;

      final res = await widget.apiClient.login(
        tenantId: resolvedTenant,
        email: email,
        password: password,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        M3Feedback.showSuccess(
          context,
          _isArabic ? 'مرحباً بك! تم تسجيل الدخول بنجاح' : 'Login Successful!',
        );
        widget.onLoginSuccess(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        M3Feedback.showError(
          context,
          _isArabic
              ? 'فشل تسجيل الدخول: يرجى التأكد من صحة البيانات'
              : 'Login failed: Please verify your credentials',
        );
      }
    }
  }

  void _openForgotPassword() {
    showDialog(
      context: context,
      builder: (ctx) => ForgotPasswordDialog(
        apiClient: widget.apiClient,
        tenantSlug: widget.tenantSlug,
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    required ColorScheme colorScheme,
    Widget? suffixIcon,
  }) {
    const topRoundedRadius = BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(4),
    );
    return InputDecoration(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      hintText: hintText,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      prefixIcon: Icon(
        prefixIcon,
        color: colorScheme.onSurfaceVariant,
        size: 22,
      ),
      suffixIcon: suffixIcon,
      border: UnderlineInputBorder(
        borderRadius: topRoundedRadius,
        borderSide: BorderSide(color: colorScheme.onSurfaceVariant),
      ),
      enabledBorder: UnderlineInputBorder(
        borderRadius: topRoundedRadius,
        borderSide: BorderSide(color: colorScheme.onSurfaceVariant),
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: topRoundedRadius,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: UnderlineInputBorder(
        borderRadius: topRoundedRadius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderRadius: topRoundedRadius,
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = _isArabic;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 28.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                      maxWidth: 480.0,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 24),

                          // ---- Top Bar: Tashil Title (Left) & Language Toggle (Right) ----
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    isArabic ? 'تسهيل' : 'Tashil',
                                    style: TextStyle(
                                      fontSize: M3FontSize.headlineMedium,
                                      fontWeight: FontWeight.w900,
                                      color: colorScheme.primary,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Material(
                                    color: colorScheme.surface.withValues(
                                      alpha: 0,
                                    ),
                                    child: InkWell(
                                      borderRadius: M3Shape.radiusLg,
                                      onTap: _toggleLanguage,
                                      child: Container(
                                        padding:
                                            const EdgeInsetsDirectional.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: M3Shape.radiusLg,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.language_rounded,
                                              size: 18,
                                              color: colorScheme.onSurface,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isArabic ? 'English' : 'العربية',
                                              style: TextStyle(
                                                fontSize: M3FontSize.bodyMedium,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const Spacer(flex: 1),
                          const SizedBox(height: 24),

                          // ---- Center Hero Logo (D) ----
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Material(
                              color: colorScheme.primary,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: M3Shape.radiusXl,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                width: 120,
                                height: 120,
                                child: Center(
                                  child: Text(
                                    'D',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: M3FontSize.displayHero,
                                      fontWeight: FontWeight.w900,
                                      height: 1.0,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ---- Subtitle ----
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Text(
                              isArabic ? 'مشاركة البيانات' : 'Data Sharing',
                              style: TextStyle(
                                fontSize: M3FontSize.bodyLarge,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),

                          const SizedBox(height: 52),

                          // ---- Login Text ----
                          SlideTransition(
                            position: _slideAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isArabic ? 'تسجيل الدخول' : 'Login',
                                      style: TextStyle(
                                        fontSize: M3FontSize.headlineSmall,
                                        fontWeight: FontWeight.w400,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isArabic
                                          ? 'مرحباً بعودتك، يرجى إدخال بياناتك'
                                          : 'Welcome back, please enter your details',
                                      style: TextStyle(
                                        fontSize: M3FontSize.bodyMedium,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ---- Login Form ----
                          SlideTransition(
                            position: _slideAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Form(
                                key: _formKey,
                                child: AutofillGroup(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Email field — keep child TextField semantics
                                      // (excludeSemantics/onTap wrappers make web
                                      // flt-semantics pointer-events:none → flutter-view intercepts).
                                      TestSemantics(
                                        identifier: TestIds.loginEmail,
                                        label: isArabic
                                            ? 'البريد الإلكتروني'
                                            : 'Email',
                                        textField: true,
                                        child: TextFormField(
                                          controller: _emailController,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction: TextInputAction.next,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          autofillHints: const [
                                            AutofillHints.email,
                                          ],
                                          textDirection: TextDirection.ltr,
                                          style: TextStyle(
                                            fontSize: M3FontSize.bodyLarge,
                                            color: colorScheme.onSurface,
                                          ),
                                          decoration: _inputDecoration(
                                            hintText: isArabic
                                                ? 'البريد الإلكتروني'
                                                : 'Email',
                                            prefixIcon: Icons.email_rounded,
                                            colorScheme: colorScheme,
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return isArabic
                                                  ? 'يرجى إدخال البريد الإلكتروني'
                                                  : 'Please enter email';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      // Password field — same as email: do not
                                      // exclude child semantics on web.
                                      TestSemantics(
                                        identifier: TestIds.loginPassword,
                                        label: isArabic
                                            ? 'كلمة المرور'
                                            : 'Password',
                                        textField: true,
                                        child: TextFormField(
                                          controller: _passwordController,
                                          keyboardType:
                                              TextInputType.visiblePassword,
                                          textInputAction: TextInputAction.done,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          autofillHints: const [
                                            AutofillHints.password,
                                          ],
                                          onFieldSubmitted: (_) =>
                                              _handleLogin(),
                                          textDirection: TextDirection.ltr,
                                          obscureText: _obscurePassword,
                                          style: TextStyle(
                                            fontSize: M3FontSize.bodyLarge,
                                            color: colorScheme.onSurface,
                                          ),
                                          decoration: _inputDecoration(
                                            hintText: isArabic
                                                ? 'كلمة المرور'
                                                : 'Password',
                                            prefixIcon: Icons.lock_rounded,
                                            colorScheme: colorScheme,
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons
                                                        .visibility_off_outlined
                                                    : Icons.visibility_rounded,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                size: 22,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _obscurePassword =
                                                      !_obscurePassword;
                                                });
                                              },
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return isArabic
                                                  ? 'يرجى إدخال كلمة المرور'
                                                  : 'Please enter password';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      // Remember Me & Forgot Password Row
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                height: 24,
                                                width: 24,
                                                child: Checkbox(
                                                  value: _rememberMe,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      _rememberMe =
                                                          value ?? false;
                                                    });
                                                  },
                                                  activeColor:
                                                      colorScheme.primary,
                                                  shape: const RoundedRectangleBorder(
                                                    borderRadius:
                                                        M3Shape.radiusXs,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _rememberMe = !_rememberMe;
                                                  });
                                                },
                                                child: Text(
                                                  isArabic
                                                      ? 'تذكرني'
                                                      : 'Remember Me',
                                                  style: TextStyle(
                                                    fontSize: M3FontSize.bodyMedium,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TextButton(
                                            onPressed: _openForgotPassword,
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            child: Text(
                                              isArabic
                                                  ? 'نسيت كلمة المرور؟'
                                                  : 'Forgot Password?',
                                              style: TextStyle(
                                                fontSize: M3FontSize.bodyMedium,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 28),

                                      // Login Button
                                      SizedBox(
                                        width: double.infinity,
                                        child: TestSemantics(
                                          identifier: TestIds.loginSubmit,
                                          label: isArabic
                                              ? 'تسجيل الدخول'
                                              : 'Login',
                                          button: true,
                                          child: FilledButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _handleLogin,
                                            style: FilledButton.styleFrom(
                                              minimumSize:
                                                  const Size.fromHeight(
                                                60,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 12,
                                              ),
                                              backgroundColor:
                                                  colorScheme.primary,
                                              foregroundColor:
                                                  colorScheme.onPrimary,
                                              disabledBackgroundColor:
                                                  colorScheme.primary
                                                      .withValues(alpha: 0.6),
                                              shape: const StadiumBorder(),
                                              textStyle: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            child: _isLoading
                                                ? SizedBox(
                                                    height: 22,
                                                    width: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                      color: colorScheme
                                                          .onPrimary,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Text(
                                                    isArabic
                                                        ? 'تسجيل الدخول'
                                                        : 'Login',
                                                    style: TextStyle(
                                                      fontSize: M3FontSize
                                                          .titleMediumPlus,
                                                      color: colorScheme
                                                          .onPrimary,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          const Spacer(flex: 1),

                          // ---- Contact Section ----
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              children: [
                                Text(
                                  isArabic
                                      ? 'ليس لديك حساب؟'
                                      : "Don't have an account?",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: M3FontSize.bodyMediumLarge,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isArabic
                                      ? 'تواصل على الرقم التالي'
                                      : 'Contact the following number',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: M3FontSize.labelMediumPlus,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: M3Shape.radiusLg,
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.support_agent_rounded,
                                        color: colorScheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '01211857725',
                                        style: TextStyle(
                                          fontSize: M3FontSize.bodyMediumLarge,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                          color: colorScheme.primary,
                                        ),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onNavigateToAdmin != null) ...[
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.admin_panel_settings_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isArabic
                                          ? 'التبديل إلى بوابة مدير المنصة (Super Admin)'
                                          : 'Switch to Super Admin Portal',
                                      style: const TextStyle(fontSize: M3FontSize.bodySmall),
                                    ),
                                    onPressed: widget.onNavigateToAdmin,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
