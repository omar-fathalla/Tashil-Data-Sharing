import 'package:flutter/material.dart';

import '../../../../core/network/preupload_check.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/app_icons.dart';

export '../../../../core/network/preupload_check.dart';

/// Arabic fix-list panel shown when precheck blocks upload.
class PreuploadFixListPanel extends StatelessWidget {
  final PreuploadCheckReport report;
  final VoidCallback? onDismiss;

  const PreuploadFixListPanel({
    super.key,
    required this.report,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card.outlined(
      key: const Key('preupload_fix_list_panel'),
      color: cs.errorContainer.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(AppIcons.warning, color: cs.error),
                const SizedBox(width: M3Spacing.xs),
                Expanded(
                  child: Text(
                    'صلّح الملف قبل الرفع — مفيش حاجة اتحفظت',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    key: const Key('preupload_fix_list_dismiss'),
                    tooltip: 'إخفاء',
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Text(
              'فحص أولي لـ «${report.filename}»: ${report.blockingCount} مشكلة لازم تتصلح. الرفع متوقف لحد ما الملف يتصلح.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: M3Spacing.xs),
            for (final fix in report.fixes)
              ListTile(
                key: Key('preupload_fix_${fix.code}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  fix.code == 'unreadable_cell' ? Icons.grid_off_rounded : AppIcons.warning,
                  color: fix.isBlocking ? cs.error : cs.tertiary,
                ),
                title: Text('${fix.codeLabelAr}${fix.column.isNotEmpty ? ' — ${fix.column}' : ''}'),
                subtitle: Text([
                  fix.messageAr,
                  if (fix.howToFixAr.isNotEmpty) 'الحل: ${fix.howToFixAr}',
                  if (fix.samples.isNotEmpty) 'أمثلة: ${fix.samples.join('، ')}',
                ].where((s) => s.trim().isNotEmpty).join('\n')),
                isThreeLine: true,
              ),
          ],
        ),
      ),
    );
  }
}
