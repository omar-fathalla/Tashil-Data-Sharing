import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_feedback.dart';

/// What the admin typed in «تسجيل سلسلة».
class RegisterChainInput {
  final String displayName;
  final String code;
  final String chainType;
  const RegisterChainInput(
      {required this.displayName,
      required this.code,
      this.chainType = 'supermarket'});
}

const _chainTypes = [
  M3DropdownOption<String>('supermarket', 'سوبر ماركت'),
  M3DropdownOption<String>('hypermarket', 'هايبر ماركت'),
  M3DropdownOption<String>('wholesale', 'جملة'),
  M3DropdownOption<String>('pharmacy', 'صيدلية'),
];

/// A chain code: lowercase latin letters, digits, "_" or "-".
bool isValidChainCode(String code) =>
    RegExp(r'^[a-z0-9][a-z0-9_-]{1,39}$').hasMatch(code.trim());

/// Admin-only button that opens the «تسجيل سلسلة» dialog. Hidden for any other role.
/// Registering a chain only adds the chain document; it never touches Sell-In rows, StoreIDs or
/// prefixes. [onRegistered] runs after the server created it.
class RegisterChainButton extends StatelessWidget {
  final ApiClient apiClient;
  final String? targetTenant;
  final ValueChanged<RetailChainModel>? onRegistered;
  const RegisterChainButton(
      {super.key,
      required this.apiClient,
      this.targetTenant,
      this.onRegistered});

  @override
  Widget build(BuildContext context) {
    if (apiClient.currentUser?.canManageChains != true) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: const ValueKey('register_chain_button'),
      onPressed: () => _register(context),
      icon: const Icon(AppIcons.add),
      label: const Text('تسجيل سلسلة'),
    );
  }

  Future<void> _register(BuildContext context) async {
    final input = await showDialog<RegisterChainInput>(
      context: context,
      builder: (_) => const RegisterChainDialog(),
    );
    if (input == null || !context.mounted) return;
    try {
      final created = await apiClient.registerRetailChain(
        displayName: input.displayName,
        code: input.code,
        chainType: input.chainType,
        targetTenant: targetTenant,
      );
      if (!context.mounted) return;
      M3Feedback.showSuccess(
          context, 'اتسجلت سلسلة «${created.displayName}» (${created.code})');
      onRegistered?.call(created);
    } on ChainAlreadyRegisteredException catch (e) {
      if (context.mounted) M3Feedback.showWarning(context, e.message);
    } catch (e) {
      if (context.mounted) {
        M3Feedback.showError(context, '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }
}

/// M3 dialog: display name, code and type (default supermarket). Returns null on cancel.
class RegisterChainDialog extends StatefulWidget {
  const RegisterChainDialog({super.key});

  @override
  State<RegisterChainDialog> createState() => _RegisterChainDialogState();
}

class _RegisterChainDialogState extends State<RegisterChainDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String _type = 'supermarket';

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && isValidChainCode(_code.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('register_chain_dialog'),
      icon: const Icon(AppIcons.store),
      title: const Text('تسجيل سلسلة'),
      content: SizedBox(
        width: 360.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('بيضيف السلسلة للقوايم بس. مفيش أي صف بيانات بيتغير.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: M3Spacing.sm),
              TextField(
                key: const ValueKey('register_chain_name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'اسم السلسلة', hintText: 'مثال: زهران'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: M3Spacing.sm),
              TextField(
                key: const ValueKey('register_chain_code'),
                controller: _code,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الكود',
                  hintText: 'zahran',
                  helperText: rtlEnd('حروف إنجليزي صغيرة وأرقام و ${ltrIsolate('_')} أو ${ltrIsolate('-')}'),
                  errorText: _code.text.isEmpty || isValidChainCode(_code.text)
                      ? null
                      : 'كود مش صالح',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: M3Spacing.sm),
              M3Dropdown<String>(
                fitOptions: true,
                key: const ValueKey('register_chain_type'),
                value: _type,
                label: 'النوع',
                expand: true,
                options: _chainTypes,
                onChanged: (v) => setState(() => _type = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(
          key: const ValueKey('register_chain_confirm'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(RegisterChainInput(
                    displayName: _name.text.trim(),
                    code: _code.text.trim(),
                    chainType: _type,
                  ))
              : null,
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}
