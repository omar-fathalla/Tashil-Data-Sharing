import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/security/zero_trust_digest.dart';
import '../../../../core/widgets/m3_button.dart';

class SuperAdminLoginScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ValueChanged<LoginResultModel> onLoginSuccess;
  final VoidCallback onCancel;

  const SuperAdminLoginScreen({
    super.key,
    required this.apiClient,
    required this.onLoginSuccess,
    required this.onCancel,
  });

  @override
  State<SuperAdminLoginScreen> createState() => _SuperAdminLoginScreenState();
}

class _SuperAdminLoginScreenState extends State<SuperAdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMsg;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    return DateTime.now().isBefore(_lockoutUntil!);
  }

  int get _remainingLockoutSeconds {
    if (!_isLockedOut) return 0;
    return _lockoutUntil!.difference(DateTime.now()).inSeconds.clamp(1, 300);
  }

  void _triggerLockout() {
    _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isLockedOut) {
        timer.cancel();
        setState(() {
          _failedAttempts = 0;
          _errorMsg = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submitLogin() async {
    if (_isLockedOut) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      // Client-side Zero-Trust SHA-256 cryptographic digest pre-verification
      final isDigestValid = ZeroTrustDigest.verifySuperAdminCredentials(
        email: email,
        password: password,
      );
      if (!isDigestValid) {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _triggerLockout();
          throw Exception(
            'تم إيقاف المحاولات مؤقتاً لمدة 30 ثانية لحماية البوابة من الاختراق (Brute-Force Protection)',
          );
        }
        throw Exception(
          'رفض الوصول الأمني: البريد الإلكتروني أو كلمة المرور غير مصرح لها بدخول بوابة الإدارة المركزية',
        );
      }

      final res = await widget.apiClient.login(
        tenantId: 'system',
        email: email,
        password: password,
      );

      if (!res.user.isSuperAdmin) {
        throw Exception('رفض الوصول: هذا الحساب لا يمتلك صلاحيات Super Admin');
      }

      if (!mounted) return;
      _failedAttempts = 0;
      widget.onLoginSuccess(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.35),
              cs.surface,
              cs.surfaceContainerLow,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                color: cs.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Security Header Row (Unified M3 Left English + Right Arabic)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer.withValues(
                                    alpha: 0.7,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified_user_rounded,
                                      size: 15,
                                      color: cs.onSecondaryContainer,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Zero-Trust Gate',
                                        style: tt.labelSmall?.copyWith(
                                          color: cs.onSecondaryContainer,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 26,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Unified M3 Header Rule: Left Bold English Title + Right Arabic Subtitle
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Super Admin Security Gate',
                              style: tt.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'بوابة التحكم المركزي المشفرة لإدارة الشركات وسلاسل التجزئة وسجلات التدقيق',
                              style: tt.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (_errorMsg != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cs.error.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.gpp_bad_rounded,
                                  color: cs.onErrorContainer,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onErrorContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Email Input (LTR)
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextFormField(
                            key: const ValueKey('super_admin_email_field'),
                            controller: _emailCtrl,
                            enabled: !_isLockedOut && !_isLoading,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Super Admin Email',
                              hintText: 'name@domain.com',
                              prefixIcon: const Icon(
                                Icons.alternate_email_rounded,
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'يرجى إدخال البريد الإلكتروني للمسؤول';
                              }
                              if (!v.contains('@') || !v.contains('.')) {
                                return 'صيغة البريد الإلكتروني غير صحيحة';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Input (LTR)
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextFormField(
                            key: const ValueKey('super_admin_password_field'),
                            controller: _passwordCtrl,
                            enabled: !_isLockedOut && !_isLoading,
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) => _submitLogin(),
                            decoration: InputDecoration(
                              labelText: 'Master Security Password',
                              hintText: '••••••••••••',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'يرجى إدخال كلمة المرور السرية';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Connected M3 Action Button Group
                        SizedBox(
                          width: double.infinity,
                          child: M3ActionButtonGroup(
                            actions: [
                              M3ActionItem(
                                label: _isLockedOut
                                    ? 'Locked (${_remainingLockoutSeconds}s)'
                                    : (_isLoading ? 'Verifying...' : 'Sign In'),
                                icon: _isLockedOut
                                    ? Icons.timer_outlined
                                    : Icons.login_rounded,
                                isPrimary: true,
                                onPressed:
                                    (_isLoading || _isLockedOut) ? null : _submitLogin,
                              ),
                              M3ActionItem(
                                label: 'Portal',
                                icon: Icons.storefront_outlined,
                                onPressed: _isLoading ? null : widget.onCancel,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Security Protection Notice Chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildSecurityBadgeChip(
                              cs,
                              tt,
                              Icons.enhanced_encryption_outlined,
                              'Zero Plaintext Secrets',
                            ),
                            _buildSecurityBadgeChip(
                              cs,
                              tt,
                              Icons.shield_outlined,
                              'RLS Multi-Tenant Guard',
                            ),
                            _buildSecurityBadgeChip(
                              cs,
                              tt,
                              Icons.policy_outlined,
                              'Brute-Force Lockout',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBadgeChip(
    ColorScheme cs,
    TextTheme tt,
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
