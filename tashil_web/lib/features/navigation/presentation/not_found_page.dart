import 'package:flutter/material.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/widgets/m3_button.dart';
import '../../../core/widgets/m3_states.dart';

/// In-shell page for an unknown `/{tenant}/{slug}` path. The sidebar
/// stays visible; [onBackToDashboard] returns to the Dashboard route.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({
    super.key,
    this.attemptedSlug,
    required this.onBackToDashboard,
  });

  final String? attemptedSlug;
  final VoidCallback onBackToDashboard;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: M3EmptyState(
          key: const ValueKey('not_found_page'),
          icon: Icons.search_off_rounded,
          title: 'الصفحة دي مش موجودة',
          message:
              'الرابط اللي فتحته مش موجود في النظام. تقدر ترجع للوحة القيادة وتختار الصفحة من القائمة.',
          action: Padding(
            padding: const EdgeInsets.only(top: M3Spacing.xs),
            child: M3Button(
              key: const ValueKey('not_found_back_to_dashboard'),
              label: 'الرجوع للوحة القيادة',
              icon: Icons.dashboard_rounded,
              onPressed: onBackToDashboard,
              isPrimary: false,
              isTonal: true,
            ),
          ),
        ),
      ),
    );
  }
}
