import 'package:flutter/material.dart';
import 'package:tashil_web/core/widgets/m3_button_group.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';

/// Shared Sell-Out / Sell-In toolbar actions as real M3 buttons (tonal group).
/// Replaces the old InkWell+Container fakes (G21). Prefer [M3ButtonGroup] directly
/// for new call sites; these helpers keep ValueKeys for existing tests.
class SellActionButtons {
  SellActionButtons._();

  static Widget upload(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
    bool isUploading = false,
    Key key = const ValueKey('upload_sellout_button'),
    bool expand = false,
  }) {
    return FilledButton.tonalIcon(
      key: key,
      style: M3ToolbarButton.style,
      onPressed: isUploading ? null : onTap,
      icon: isUploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(AppIcons.uploadFile),
      label: Text(label),
    );
  }

  static Widget printPdf(
    BuildContext context, {
    required VoidCallback? onTap,
    bool expand = false,
  }) {
    return FilledButton.tonalIcon(
      key: const ValueKey('export_pdf_button'),
      style: M3ToolbarButton.style,
      onPressed: onTap,
      icon: const Icon(AppIcons.print),
      label: const Text('طباعة'),
    );
  }

  static Widget exportExcel(
    BuildContext context, {
    required VoidCallback? onTap,
    bool expand = false,
  }) {
    return OutlinedButton.icon(
      key: const ValueKey('export_excel_button'),
      style: M3ToolbarButton.style,
      onPressed: onTap,
      icon: const Icon(AppIcons.fileDownload),
      label: const Text('تصدير'),
    );
  }

  /// Upload (tonal) + Print (tonal) + Export (outlined) as [M3ButtonGroup].
  static Widget row(
    BuildContext context, {
    required String uploadLabel,
    VoidCallback? onUpload,
    bool isUploading = false,
    VoidCallback? onExportPdf,
    required VoidCallback onExportExcel,
  }) {
    return M3ButtonGroup(
      key: const ValueKey('sell_action_buttons_row'),
      items: [
        if (onUpload != null)
          M3GroupItem(
            key: const ValueKey('upload_sellout_button'),
            label: uploadLabel,
            icon: AppIcons.uploadFile,
            onPressed: onUpload,
            isLoading: isUploading,
            kind: M3GroupItemKind.tonal,
          ),
        if (onExportPdf != null)
          M3GroupItem(
            key: const ValueKey('export_pdf_button'),
            label: 'طباعة',
            icon: AppIcons.print,
            onPressed: onExportPdf,
            kind: M3GroupItemKind.tonal,
          ),
        M3GroupItem(
          key: const ValueKey('export_excel_button'),
          label: 'تصدير',
          icon: AppIcons.fileDownload,
          onPressed: onExportExcel,
          kind: M3GroupItemKind.outlined,
        ),
      ],
    );
  }
}

/// One option of a [SellTableFilterChips] bar.
class SellTableFilterOption {
  final String value;
  final String label;
  final int count;
  final IconData? icon;
  const SellTableFilterOption({
    required this.value,
    required this.label,
    required this.count,
    this.icon,
  });
}

/// Shared table filter chip bar for the Sell-Out and Sell-In tables:
/// single-select ChoiceChips, AppIcons avatars, "label (count)" text.
class SellTableFilterChips extends StatelessWidget {
  final List<SellTableFilterOption> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const SellTableFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  /// Standard margin / promo filter set shared by both pages.
  static List<SellTableFilterOption> marginOptions({
    required int all,
    required int healthy,
    required int lowMargin,
    required int negativeMargin,
    required int promo,
  }) =>
      [
        SellTableFilterOption(value: 'all', label: 'الكل', count: all),
        SellTableFilterOption(
            value: 'healthy',
            label: 'هامش جيد',
            count: healthy,
            icon: AppIcons.trendingUp),
        SellTableFilterOption(
            value: 'low_margin',
            label: 'هامش منخفض',
            count: lowMargin,
            icon: AppIcons.warning),
        SellTableFilterOption(
            value: 'negative_margin',
            label: 'أقل من التكلفة',
            count: negativeMargin,
            icon: AppIcons.error),
        SellTableFilterOption(
            value: 'promo', label: 'عروض', count: promo, icon: AppIcons.promo),
      ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: [
        for (final o in options)
          ChoiceChip(
            key: ValueKey('sell_filter_chip_${o.value}'),
            avatar: o.icon == null ? null : Icon(o.icon, size: 18.0),
            label: Text('${o.label} (${o.count})'),
            selected: selected == o.value,
            onSelected: (_) => onSelected(o.value),
          ),
      ],
    );
  }
}
