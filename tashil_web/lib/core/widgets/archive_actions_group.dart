import 'package:flutter/material.dart';

import '../testing/test_semantics.dart';
import '../theme/m3_shape.dart';
import 'app_icons.dart';

/// Connected Material 3 button group for archived sheet rows:
/// Edit (replace) | Download | Delete.
class ArchiveActionsGroup extends StatelessWidget {
  const ArchiveActionsGroup({
    super.key,
    required this.onEdit,
    required this.onDownload,
    required this.onDelete,
    this.isEditing = false,
    this.isDeleting = false,
    this.showEdit = true,
    this.archiveId,
    this.fileName,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final bool isEditing;
  final bool isDeleting;

  /// Hides the Edit (replace) segment, e.g. for users the backend would refuse a replace.
  final bool showEdit;

  /// Archive id + file name wire `file-delete-<archiveId>-<name>` for automation.
  final String? archiveId;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final divider = VerticalDivider(
      width: 1.0,
      thickness: 1.0,
      color: colorScheme.outline,
    );

    final deleteId = (archiveId != null &&
            archiveId!.isNotEmpty &&
            fileName != null &&
            fileName!.isNotEmpty)
        ? TestIds.fileDelete(archiveId: archiveId!, fileName: fileName!)
        : null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline),
        borderRadius: M3Shape.radiusFull,
      ),
      child: ClipRRect(
        borderRadius: M3Shape.radiusFull,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showEdit) ...[
                _segment(
                  context,
                  label: 'Edit',
                  icon: AppIcons.edit,
                  busy: isEditing,
                  onPressed: onEdit,
                  color: colorScheme.primary,
                ),
                divider,
              ],
              _segment(
                context,
                label: 'Download',
                icon: AppIcons.download,
                busy: false,
                onPressed: onDownload,
                color: colorScheme.primary,
              ),
              divider,
              _segment(
                context,
                label: 'Delete',
                icon: AppIcons.delete,
                busy: isDeleting,
                onPressed: onDelete,
                color: colorScheme.error,
                semanticsIdentifier: deleteId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback? onPressed,
    required Color color,
    String? semanticsIdentifier,
  }) {
    Widget button = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        shape: const RoundedRectangleBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 14.0,
              height: 14.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            )
          : Icon(icon, size: 16.0),
      label: Text(label),
    );

    if (semanticsIdentifier != null) {
      // Own the tap on the Semantics node so Flutter web exposes role=button
      // (not DataTable role=cell) and Playwright clicks don't fall through to
      // flutter-view when the semantics box is offset.
      button = TestSemantics.button(
        identifier: semanticsIdentifier,
        label: label,
        onPressed: onPressed,
        child: button,
      );
    }

    return button;
  }
}
