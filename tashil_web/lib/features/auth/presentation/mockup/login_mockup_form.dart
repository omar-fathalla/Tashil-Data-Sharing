import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../widgets/forgot_password_dialog.dart';
import 'login_mockup_copy.dart';

/// Login fields shared by every mockup variant.
///
/// Behavior matches [TenantLoginScreen]: email, password with show/hide,
/// remember me, forgot password, login, contact number, and validation.
class LoginMockupForm extends StatefulWidget {
  const LoginMockupForm({
    super.key,
    this.filledFields = false,
    this.fieldGap = M3Spacing.sm,
    this.initialEmail = 'user@example.com',
    this.tenantSlug = 'company',
    this.compact = false,
  });

  final bool filledFields;
  final double fieldGap;
  final String initialEmail;
  final String tenantSlug;

  /// Tighter gaps so a phone-height column can show the contact line.
  final bool compact;

  @override
  State<LoginMockupForm> createState() => _LoginMockupFormState();
}

class _LoginMockupFormState extends State<LoginMockupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  late final ApiClient _apiClient;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _apiClient = ApiClient();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    final ar = LoginMockupCopy.isArabic(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      M3Feedback.showError(context, LoginMockupCopy.credentialsRequired(ar));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final isGeneric = widget.tenantSlug == 'company' || widget.tenantSlug == 'portal';
      final resolvedTenant = isGeneric
          ? ApiClient.findTenantSlugForEmail(email)
          : widget.tenantSlug;
      await _apiClient.login(
        tenantId: resolvedTenant,
        email: email,
        password: password,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      M3Feedback.showSuccess(context, LoginMockupCopy.loginSuccess(ar));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
      if (msg.isEmpty) msg = LoginMockupCopy.loginFailed(ar);
      M3Feedback.showError(context, msg);
    }
  }

  void _openForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ForgotPasswordDialog(
        apiClient: _apiClient,
        tenantSlug: widget.tenantSlug,
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required ColorScheme cs,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: widget.filledFields,
      fillColor: widget.filledFields
          ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ar = LoginMockupCopy.isArabic(context);

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LoginMockupCopy.login(ar),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
                fontSize: M3FontSize.headlineSmall,
              ),
            ),
            const SizedBox(height: M3Spacing.xs),
            Text(
              LoginMockupCopy.welcome(ar),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: M3FontSize.bodyMedium,
              ),
            ),
            SizedBox(height: widget.fieldGap + M3Spacing.xs),
            TestSemantics(
              identifier: TestIds.loginEmail,
              label: LoginMockupCopy.email(ar),
              textField: true,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface,
                  fontSize: M3FontSize.bodyLarge,
                ),
                decoration: _decoration(
                  label: LoginMockupCopy.email(ar),
                  icon: Icons.email_rounded,
                  cs: cs,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return LoginMockupCopy.emailRequired(ar);
                  }
                  return null;
                },
              ),
            ),
            SizedBox(height: widget.fieldGap),
            TestSemantics(
              identifier: TestIds.loginPassword,
              label: LoginMockupCopy.password(ar),
              textField: true,
              child: TextFormField(
                controller: _passwordController,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _handleLogin(),
                textDirection: TextDirection.ltr,
                obscureText: _obscurePassword,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface,
                  fontSize: M3FontSize.bodyLarge,
                ),
                decoration: _decoration(
                  label: LoginMockupCopy.password(ar),
                  icon: Icons.lock_rounded,
                  cs: cs,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? LoginMockupCopy.showPassword(ar)
                        : LoginMockupCopy.hidePassword(ar),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return LoginMockupCopy.passwordRequired(ar);
                  }
                  return null;
                },
              ),
            ),
            SizedBox(height: widget.fieldGap),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: M3Spacing.xs,
              runSpacing: M3Spacing.xxs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: M3Spacing.md,
                      width: M3Spacing.md,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (value) =>
                            setState(() => _rememberMe = value ?? false),
                        shape: const RoundedRectangleBorder(
                          borderRadius: M3Shape.radiusXs,
                        ),
                      ),
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    GestureDetector(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      child: Text(
                        LoginMockupCopy.remember(ar),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontSize: M3FontSize.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _openForgotPassword,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.xs,
                      vertical: M3Spacing.xxs,
                    ),
                  ),
                  child: Text(
                    LoginMockupCopy.forgot(ar),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: M3FontSize.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: widget.compact ? M3Spacing.sm : M3Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: TestSemantics(
                identifier: TestIds.loginSubmit,
                label: LoginMockupCopy.login(ar),
                button: true,
                child: FilledButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(widget.compact ? 48 : 56),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: M3FontSize.bodyLarge,
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: cs.onPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(LoginMockupCopy.login(ar)),
                ),
              ),
            ),
            SizedBox(height: widget.compact ? M3Spacing.sm : M3Spacing.lg),
            _ContactBlock(ar: ar),
          ],
        ),
      ),
    );
  }
}

class _ContactBlock extends StatelessWidget {
  const _ContactBlock({required this.ar});

  final bool ar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            LoginMockupCopy.noAccount(ar),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: M3FontSize.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.xxs),
        SizedBox(
          width: double.infinity,
          child: Text(
            LoginMockupCopy.contact(ar),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: M3FontSize.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.s12),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: M3Shape.radiusFull,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: M3Spacing.sm,
                vertical: M3Spacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.support_agent_rounded,
                    color: cs.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: M3Spacing.xs),
                  Text(
                    '01211857725',
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: M3FontSize.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
