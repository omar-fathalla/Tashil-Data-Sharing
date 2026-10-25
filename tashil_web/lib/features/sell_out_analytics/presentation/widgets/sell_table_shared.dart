import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/app_icons.dart';

/// Shared action buttons (Upload / Print PDF / Export Excel) used by both the
/// Sell-Out and Sell-In filter cards so the two pages stay visually identical.
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      key: key,
      borderRadius: M3Shape.radiusLg,
      onTap: isUploading ? null : onTap,
      child: Container(
        height: 38.0,
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        decoration: BoxDecoration(
          color: cs.secondary,
          borderRadius: M3Shape.radiusLg,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isUploading)
              const SizedBox(
                width: 14.0,
                height: 14.0,
                child: CircularProgressIndicator(
                    strokeWidth: 2.0, color: Colors.white),
              )
            else
              Icon(AppIcons.uploadFile, size: 16.0, color: cs.onSecondary),
            const SizedBox(width: 6.0),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: M3FontSize.labelSmallPlus,
                  color: cs.onSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget printPdf(
    BuildContext context, {
    required VoidCallback? onTap,
    bool expand = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      key: const ValueKey('export_pdf_button'),
      borderRadius: M3Shape.radiusLg,
      onTap: onTap,
      child: Container(
        height: 38.0,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        decoration:
            BoxDecoration(color: cs.primary, borderRadius: M3Shape.radiusLg),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.print, size: 15.0, color: cs.onPrimary),
            const SizedBox(width: 5.0),
            Flexible(
              child: Text(
                'Print PDF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: M3FontSize.labelSmall,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget exportExcel(
    BuildContext context, {
    required VoidCallback? onTap,
    bool expand = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      key: const ValueKey('export_excel_button'),
      borderRadius: M3Shape.radiusLg,
      onTap: onTap,
      child: Container(
        height: 38.0,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: M3Shape.radiusLg,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.fileDownload, size: 15.0, color: cs.onSurface),
            const SizedBox(width: 5.0),
            Flexible(
              child: Text(
                'Export Excel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: M3FontSize.labelSmall,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Upload, Print PDF, Export Excel in one row (Excel ends up at the far
  /// left in RTL, matching the Sell-Out filter card).
  static Widget row(
    BuildContext context, {
    required String uploadLabel,
    VoidCallback? onUpload,
    bool isUploading = false,
    VoidCallback? onExportPdf,
    required VoidCallback onExportExcel,
  }) {
    return Row(
      key: const ValueKey('sell_action_buttons_row'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onUpload != null) ...[
          upload(context,
              label: uploadLabel, onTap: onUpload, isUploading: isUploading),
          const SizedBox(width: 8.0),
        ],
        if (onExportPdf != null) ...[
          printPdf(context, onTap: onExportPdf),
          const SizedBox(width: 8.0),
        ],
        exportExcel(context, onTap: onExportExcel),
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
            label: 'هامش صحي',
            count: healthy,
            icon: AppIcons.trendingUp),
        SellTableFilterOption(
            value: 'low_margin',
            label: 'هامش منخفض',
            count: lowMargin,
            icon: AppIcons.warning),
        SellTableFilterOption(
            value: 'negative_margin',
            label: 'بيع بأقل من التكلفة / حرق سعر',
            count: negativeMargin,
            icon: AppIcons.error),
        SellTableFilterOption(
            value: 'promo',
            label: 'عروض ترويجية',
            count: promo,
            icon: AppIcons.promo),
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
