import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';

/// ForgotPasswordDialog facilitates password recovery using a secure reset token.
class ForgotPasswordDialog extends StatefulWidget {
  final ApiClient apiClient;
  final String tenantSlug;
  final String? initialEmail;

  const ForgotPasswordDialog({
    super.key,
    required this.apiClient,
    required this.tenantSlug,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _newPasswordController = TextEditingController();

  int _step = 1; // 1 = Request Token, 2 = Reset Password
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  Future<void> _requestToken() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      M3Feedback.showError(context, 'يرجى إدخال بريد إلكتروني صالح');
      return;
    }

    setState(() => _isLoading = true);
    final msg = await widget.apiClient.forgotPassword(
      tenantId: widget.tenantSlug,
      email: email,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _step = 2;
        if (widget.apiClient.lastResetToken != null && widget.apiClient.lastResetToken!.isNotEmpty) {
          _tokenController.text = widget.apiClient.lastResetToken!;
        }
      });
      M3Feedback.showSuccess(context, msg);
    }
  }

  Future<void> _resetPassword() async {
    final token = _tokenController.text.trim();
    final newPass = _newPasswordController.text.trim();

    if (token.isEmpty) {
      M3Feedback.showError(context, 'يرجى إدخال رمز التحقق');
      return;
    }
    if (newPass.length < 8) {
      M3Feedback.showError(context, 'كلمة المرور يجب ألا تقل عن 8 خانات');
      return;
    }

    setState(() => _isLoading = true);
    final msg = await widget.apiClient.resetPassword(
      token: token,
      newPassword: newPass,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      M3Feedback.showSuccess(context, msg);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: colorScheme.primary),
          M3Spacing.gapSM,
          Text(
            _step == 1 ? 'استعادة كلمة المرور' : 'تعيين كلمة المرور الجديدة',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 440.0,
        child: _step == 1
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'أدخل البريد الإلكتروني لمسؤول حساب شركة (${widget.tenantSlug.toUpperCase()}) لإرسال رمز استعادة الحساب:',
                    style: theme.textTheme.bodyMedium,
                  ),
                  M3Spacing.gapMD,
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'أدخل رمز الاستعادة وكلمة المرور الجديدة لحسابك:',
                    style: theme.textTheme.bodyMedium,
                  ),
                  M3Spacing.gapMD,
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'رمز التحقق (Reset Token)',
                      hintText: 'أدخل رمز الاستعادة المكون من 48 حرفاً',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  M3Spacing.gapSM,
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        M3Button.text(
          label: 'إلغاء',
          onPressed: () => Navigator.pop(context),
        ),
        if (_step == 1)
          M3Button.primary(
            label: _isLoading ? 'جارٍ الإرسال...' : 'إرسال الرمز',
            icon: Icons.send_rounded,
            onPressed: _isLoading ? null : _requestToken,
          )
        else
          M3Button.primary(
            label: _isLoading ? 'جارٍ التحديث...' : 'تحديث كلمة المرور',
            icon: Icons.check_circle_rounded,
            onPressed: _isLoading ? null : _resetPassword,
          ),
      ],
    );
  }
}
