import 'dart:convert';
import 'dart:typed_data';

import 'web_file_helper_stub.dart'
    if (dart.library.html) 'web_file_helper_web.dart';

/// Stable DOM id of the hidden web file input (`#tashil-file-input`).
/// Playwright should prefer `setInputFiles` on this node over `filechooser`.
const String kTashilFileInputDomId = 'tashil-file-input';

/// Represents a file selected via the browser file picker or test hook.
class PickedFileData {
  final String name;
  final Uint8List bytes;

  const PickedFileData({
    required this.name,
    required this.bytes,
  });
}

/// WebFileHelper provides platform-safe browser file picking (`<input type="file">`)
/// and Blob object URL file downloading (`<a download="...">`), with deterministic
/// hooks for Flutter VM widget tests.
class WebFileHelper {
  WebFileHelper._();

  /// Optional test override allowing widget/unit tests to inject custom picked files.
  static Future<PickedFileData?> Function()? testFilePickerOverride;

  /// Optional one-shot mock picked file for tests.
  static PickedFileData? nextMockPickedFile;

  static bool Function()? _activeBeforeDrop;
  static void Function(String name, Uint8List bytes)? _activeOnFileDropped;

  /// Resets any test overrides.
  static void resetTestOverrides() {
    testFilePickerOverride = null;
    nextMockPickedFile = null;
  }

  /// Mounts the persistent hidden `<input type="file">` early on web so
  /// Playwright can discover `#tashil-file-input` before the first click.
  static void ensureMounted({String accept = '.csv,.xlsx,.xls'}) {
    ensurePersistentFileInput(accept: accept);
  }

  /// Registers a browser drag-and-drop file listener (and test drop hook).
  static void Function() registerDropzoneListener({
    required void Function(bool isDragging) onDragStateChanged,
    required bool Function() onBeforeDrop,
    required void Function(String name, Uint8List bytes) onFileDropped,
  }) {
    _activeBeforeDrop = onBeforeDrop;
    _activeOnFileDropped = onFileDropped;
    final disposePlatform = platformRegisterDropzone(
      onDragStateChanged: onDragStateChanged,
      onBeforeDrop: onBeforeDrop,
      onFileDropped: onFileDropped,
    );
    return () {
      if (_activeBeforeDrop == onBeforeDrop) {
        _activeBeforeDrop = null;
      }
      if (_activeOnFileDropped == onFileDropped) {
        _activeOnFileDropped = null;
      }
      disposePlatform();
    };
  }

  /// Simulates dropping a file onto the active DropzoneFilePicker in widget tests.
  static bool simulateFileDrop(String filename, List<int> bytes) {
    if (_activeBeforeDrop != null && !_activeBeforeDrop!()) {
      return false;
    }
    if (_activeOnFileDropped != null) {
      _activeOnFileDropped!(filename, Uint8List.fromList(bytes));
      return true;
    }
    return false;
  }

  /// Opens the browser file upload dialog (or returns test fallback in VM tests).
  static Future<PickedFileData?> pickFile({
    String accept = '.csv,.xlsx,.xls',
  }) async {
    if (testFilePickerOverride != null) {
      return testFilePickerOverride!();
    }
    if (nextMockPickedFile != null) {
      final picked = nextMockPickedFile;
      nextMockPickedFile = null;
      return picked;
    }
    final raw = await platformPickFile(accept: accept);
    if (raw == null) return null;
    final name = raw['name'] as String? ?? 'uploaded_file.csv';
    final rawBytes = raw['bytes'];
    final bytes = rawBytes is Uint8List
        ? rawBytes
        : Uint8List.fromList((rawBytes as List<int>?) ?? const <int>[]);
    return PickedFileData(name: name, bytes: bytes);
  }

  /// Triggers a real browser file download using Blob & createObjectUrlFromBlob on Web.
  static void downloadFile({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) {
    platformDownloadFile(filename, bytes, mimeType);
  }

  /// Opens the given URL in a new browser tab/window safely on Web.
  static void openUrlInNewTab(String url) {
    platformOpenInNewTab(url);
  }

  /// Realistic multi-row Carrefour CSV payload (valid rows + 1 short barcode anomaly row).
  static Uint8List sampleCarrefourCsvBytes() {
    const csv =
        'Store_Code_Branch,Barcode,Item_Description,Category,Sales_Units,Net_Val_EGP,Transaction_Date\n'
        'Carrefour Maadi City Center,6221155001234,Adeco Extra Virgin Olive Oil 500ml,زيوت طعام,142,35500.0,2026-03-07\n'
        'Carrefour Dandy Mall,6221155001241,Adeco Pure Sunflower Oil 1L,زيوت طعام,210,23100.0,2026-03-07\n'
        'Carrefour City Stars,6221155001258,Adeco Pure Corn Oil 800ml,زيوت طعام,88,10560.0,2026-03-06\n'
        'Carrefour Maadi City Center,1234,Short Barcode Defect Item,زيوت طعام,15,1500.0,2026-03-06\n';
    return Uint8List.fromList(utf8.encode(csv));
  }

  /// Realistic multi-row Fathalla Arabic CSV payload (valid rows + 1 negative quantity anomaly row).
  static Uint8List sampleFathallaCsvBytes() {
    const csv =
        'فرع فتح الله,الباركود الدولي,اسم الصنف,الفئة,الكمية المباعة,صافي المبيعات,تاريخ البيع\n'
        'فتح الله جملة ماركت - فرع سموحة,6221155001234,زيت زيتون بكر ممتاز ادكو 500 مل,زيوت طعام,185,46250.0,2026-03-07\n'
        'فتح الله - فرع ستانلي الإسكندرية,6221155001241,زيت عباد الشمس نقي ادكو 1 لتر,زيوت طعام,164,18040.0,2026-03-07\n'
        'فتح الله - فرع المنشية,6221155001265,زيت كانولا ادكو 750 مل,زيوت طعام,95,11400.0,2026-03-06\n'
        'فتح الله - فرع سموحة,6221155002019,مرتجع صلصة طماطم ادكو,صلصة ومعلبات,-12,-456.0,2026-03-06\n';
    return Uint8List.fromList(utf8.encode(csv));
  }

  /// Realistic multi-row Gomla Market CSV payload (valid rows + 1 short barcode anomaly row).
  static Uint8List sampleGomlaCsvBytes() {
    const csv =
        'Store_Name,Barcode,Item_Description,Category,Qty_Sold,Net_Amount,Transaction_Date\n'
        'Gomla Market Nasr City,6221155001234,Adeco Extra Virgin Olive Oil 500ml,زيوت طعام,98,24500.0,2026-03-07\n'
        'Gomla Market Dokki,6221155001241,Adeco Pure Sunflower Oil 1L,زيوت طعام,130,14300.0,2026-03-07\n'
        'Gomla Market Heliopolis,6221155003016,Adeco Traditional Fava Beans 400g,بقوليات ومعلبات,150,4200.0,2026-03-06\n'
        'Gomla Market Nasr City,9988,Invalid Short Barcode Item,بقوليات ومعلبات,10,280.0,2026-03-06\n';
    return Uint8List.fromList(utf8.encode(csv));
  }
}
