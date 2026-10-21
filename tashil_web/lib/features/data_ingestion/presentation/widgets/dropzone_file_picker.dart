import 'package:flutter/material.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_button.dart';

/// DropzoneFilePicker allows uploading Excel/CSV retail files via drag-and-drop or file picker
/// and validates that a target retail chain is selected before accepting any file.
class DropzoneFilePicker extends StatefulWidget {
  final bool isProcessing;
  final Function(String filename, List<int> bytes) onFileSelected;
  final bool Function()? onBeforePickFile;
  final bool hasError;

  const DropzoneFilePicker({
    super.key,
    required this.isProcessing,
    required this.onFileSelected,
    this.onBeforePickFile,
    this.hasError = false,
  });

  @override
  State<DropzoneFilePicker> createState() => _DropzoneFilePickerState();
}

class _DropzoneFilePickerState extends State<DropzoneFilePicker> {
  bool _isDraggingOver = false;
  void Function()? _disposeDropzone;

  @override
  void initState() {
    super.initState();
    _disposeDropzone = WebFileHelper.registerDropzoneListener(
      onDragStateChanged: (isDragging) {
        if (mounted && _isDraggingOver != isDragging) {
          setState(() => _isDraggingOver = isDragging);
        }
      },
      onBeforeDrop: () {
        if (widget.isProcessing) return false;
        if (widget.onBeforePickFile != null && !widget.onBeforePickFile!()) {
          return false;
        }
        return true;
      },
      onFileDropped: (name, bytes) {
        if (!mounted || widget.isProcessing) return;
        widget.onFileSelected(name, bytes);
      },
    );
  }

  @override
  void dispose() {
    _disposeDropzone?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: M3Spacing.pLg,
        child: Column(
          children: [
            // Upload Drag & Drop Container
            Container(
              key: const ValueKey('upload_dropzone_container'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
              decoration: BoxDecoration(
                color: widget.hasError
                    ? colorScheme.errorContainer.withOpacity(0.18)
                    : _isDraggingOver
                        ? colorScheme.primaryContainer.withOpacity(0.35)
                        : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: widget.hasError
                      ? colorScheme.error
                      : _isDraggingOver
                          ? colorScheme.primary
                          : colorScheme.primary.withOpacity(0.4),
                  width: _isDraggingOver || widget.hasError ? 2.5 : 2.0,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: widget.hasError
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.hasError
                          ? Icons.warning_amber_rounded
                          : Icons.cloud_upload_rounded,
                      size: 36.0,
                      color: widget.hasError ? colorScheme.onErrorContainer : colorScheme.primary,
                    ),
                  ),
                  M3Spacing.gapMD,
                  Text(
                    'اسحب وأفلت ملف إكسيل أو CSV هنا',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'يدعم ملفات الإكسيل متعددة التابات (Multi-Tab .xlsx / .xls) وملفات CSV لأي سلسلة تجزئة',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  M3Spacing.gapMD,
                  M3Button.primary(
                    label: 'اختيار ملف',
                    icon: Icons.folder_open_rounded,
                    isLoading: widget.isProcessing,
                    onPressed: widget.isProcessing
                        ? null
                        : () async {
                            if (widget.onBeforePickFile != null &&
                                !widget.onBeforePickFile!()) {
                              return;
                            }
                            final picked = await WebFileHelper.pickFile();
                            if (picked != null) {
                              widget.onFileSelected(picked.name, picked.bytes);
                            }
                          },
                  ),
                  const SizedBox(height: 12.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 14.0, color: colorScheme.secondary),
                        const SizedBox(width: 6.0),
                        Flexible(
                          child: Text(
                            'يقوم الذكاء الاصطناعي باستكشاف كافة التابات (Worksheets) واستنتاج الفروع والأصناف والأسعار تلقائياً',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
