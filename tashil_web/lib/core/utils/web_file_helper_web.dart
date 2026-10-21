// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Map<String, dynamic>?> platformPickFile({
  String accept = '.csv,.xlsx,.xls',
}) {
  final completer = Completer<Map<String, dynamic>?>();
  final input = html.FileUploadInputElement()..accept = accept;

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return;
    }

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      if (completer.isCompleted) return;
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
        completer.complete(<String, dynamic>{
          'name': file.name,
          'bytes': bytes,
        });
      } else {
        completer.complete(null);
      }
    });

    reader.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    reader.readAsArrayBuffer(file);
  });

  input.on['cancel'].listen((_) {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  });

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
