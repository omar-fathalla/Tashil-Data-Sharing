// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Stable DOM id for the shared hidden file input (Playwright `setInputFiles`).
const String kTashilFileInputDomId = 'tashil-file-input';

html.FileUploadInputElement? _persistentInput;
StreamSubscription<html.Event>? _changeSub;
StreamSubscription<html.Event>? _cancelSub;
Completer<Map<String, dynamic>?>? _armedCompleter;

html.FileUploadInputElement _resolvePersistentFileInput({
  String accept = '.csv,.xlsx,.xls',
}) {
  final existing = html.document.getElementById(kTashilFileInputDomId);
  if (existing is html.FileUploadInputElement) {
    _persistentInput = existing;
  } else {
    final input = html.FileUploadInputElement()
      ..id = kTashilFileInputDomId
      // Keep in layout (not display:none) so programmatic click() is honored.
      ..style.position = 'fixed'
      ..style.left = '0'
      ..style.top = '0'
      ..style.width = '1px'
      ..style.height = '1px'
      ..style.opacity = '0'
      ..style.overflow = 'hidden'
      ..style.padding = '0'
      ..style.border = '0'
      ..style.margin = '0'
      ..setAttribute('data-testid', kTashilFileInputDomId)
      ..setAttribute('aria-hidden', 'true')
      ..tabIndex = -1;
    html.document.body?.append(input);
    _persistentInput = input;
  }

  final input = _persistentInput!;
  input.accept = accept;
  return input;
}

/// Ensures a single hidden `<input type="file">` exists in `document.body`.
///
/// Must stay attached to the DOM: detached inputs often fail to open a chooser
/// under headless Chromium, and Playwright needs a stable node for
/// `setInputFiles` without relying on the `filechooser` event.
///
/// Signature is `void` to match the VM stub (conditional import).
void ensurePersistentFileInput({
  String accept = '.csv,.xlsx,.xls',
}) {
  _resolvePersistentFileInput(accept: accept);
}

void _disarm({Map<String, dynamic>? result, bool cancelled = false}) {
  final completer = _armedCompleter;
  _armedCompleter = null;
  _changeSub?.cancel();
  _cancelSub?.cancel();
  _changeSub = null;
  _cancelSub = null;
  _persistentInput?.removeAttribute('data-armed');
  _persistentInput?.value = '';
  if (completer != null && !completer.isCompleted) {
    completer.complete(cancelled ? null : result);
  }
}

void _armInput(html.FileUploadInputElement input) {
  _changeSub?.cancel();
  _cancelSub?.cancel();

  _changeSub = input.onChange.listen((_) async {
    final completer = _armedCompleter;
    if (completer == null || completer.isCompleted) return;

    final files = input.files;
    if (files == null || files.isEmpty) {
      _disarm(cancelled: true);
      return;
    }

    final file = files.first;
    final reader = html.FileReader();
    final loaded = Completer<Uint8List?>();

    reader.onLoadEnd.listen((_) {
      if (loaded.isCompleted) return;
      final result = reader.result;
      if (result is Uint8List) {
        loaded.complete(result);
      } else if (result is ByteBuffer) {
        loaded.complete(result.asUint8List());
      } else if (result is List<int>) {
        loaded.complete(Uint8List.fromList(result));
      } else {
        loaded.complete(null);
      }
    });
    reader.onError.listen((_) {
      if (!loaded.isCompleted) loaded.complete(null);
    });
    reader.readAsArrayBuffer(file);

    final bytes = await loaded.future;
    if (bytes == null) {
      _disarm(cancelled: true);
      return;
    }
    _disarm(result: <String, dynamic>{
      'name': file.name,
      'bytes': bytes,
    });
  });

  _cancelSub = input.on['cancel'].listen((_) {
    _disarm(cancelled: true);
  });

  input.setAttribute('data-armed', 'true');
}

/// Opens the browser file dialog via the persistent input (user-activation path).
///
/// Call from a button `onPressed` so the synchronous `input.click()` stays in the
/// same turn as the Flutter gesture when possible. Playwright may instead call
/// `setInputFiles` on `#tashil-file-input` while `data-armed="true"`.
Future<Map<String, dynamic>?> platformPickFile({
  String accept = '.csv,.xlsx,.xls',
}) {
  if (_armedCompleter != null && !(_armedCompleter!.isCompleted)) {
    _disarm(cancelled: true);
  }

  final input = _resolvePersistentFileInput(accept: accept);
  final completer = Completer<Map<String, dynamic>?>();
  _armedCompleter = completer;
  _armInput(input);

  // Programmatic click in the user-gesture turn. Headless may still suppress the
  // native chooser; automation should use setInputFiles on this same node.
  input.click();
  return completer.future;
}

void platformDownloadFile(
  String filename,
  List<int> bytes,
  String mimeType,
) {
  try {
    final blob = html.Blob(<dynamic>[Uint8List.fromList(bytes)], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}

void platformOpenInNewTab(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}

void Function() platformRegisterDropzone({
  required void Function(bool isDragging) onDragStateChanged,
  required bool Function() onBeforeDrop,
  required void Function(String name, Uint8List bytes) onFileDropped,
}) {
  final dragOverSub = html.document.onDragOver.listen((event) {
    event.preventDefault();
    onDragStateChanged(true);
  });

  final dragLeaveSub = html.document.onDragLeave.listen((event) {
    event.preventDefault();
    onDragStateChanged(false);
  });

  final dropSub = html.document.onDrop.listen((event) {
    event.preventDefault();
    onDragStateChanged(false);
    if (!onBeforeDrop()) {
      return;
    }
    final files = event.dataTransfer.files;
    if (files == null || files.isEmpty) return;
    final file = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      Uint8List? bytes;
      if (result is Uint8List) {
        bytes = result;
      } else if (result is ByteBuffer) {
        bytes = result.asUint8List();
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      }
      if (bytes != null) {
        onFileDropped(file.name, bytes);
      }
    });
    reader.readAsArrayBuffer(file);
  });

  return () {
    dragOverSub.cancel();
    dragLeaveSub.cancel();
    dropSub.cancel();
  };
}
