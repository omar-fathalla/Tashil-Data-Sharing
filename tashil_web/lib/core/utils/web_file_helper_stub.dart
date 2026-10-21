import 'dart:convert';
import 'dart:typed_data';

const String defaultSampleCarrefourCsv =
    'Store_Code_Branch,Barcode,Item_Description,Category,Sales_Units,Net_Val_EGP,Transaction_Date\n'
    'Carrefour Maadi City Center,6221155001234,Adeco Extra Virgin Olive Oil 500ml,زيوت طعام,142,35500.0,2026-03-07\n'
    'Carrefour Dandy Mall,6221155001241,Adeco Pure Sunflower Oil 1L,زيوت طعام,210,23100.0,2026-03-07\n'
    'Carrefour City Stars,6221155001258,Adeco Pure Corn Oil 800ml,زيوت طعام,88,10560.0,2026-03-06\n'
    'Carrefour Maadi City Center,1234,Short Barcode Defect Sample,زيوت طعام,15,1500.0,2026-03-06\n';

Future<Map<String, dynamic>?> platformPickFile({
  String accept = '.csv,.xlsx,.xls',
}) async {
  return <String, dynamic>{
    'name': 'carrefour_daily_sellout_2026.csv',
    'bytes': Uint8List.fromList(utf8.encode(defaultSampleCarrefourCsv)),
  };
}

void platformDownloadFile(
  String filename,
  List<int> bytes,
  String mimeType,
) {
  // No-op in non-browser VM test environment; tracked via ExcelExportService.
}

void platformOpenInNewTab(String url) {
  // No-op in non-browser VM test environment.
}

void Function() platformRegisterDropzone({
  required void Function(bool isDragging) onDragStateChanged,
  required bool Function() onBeforeDrop,
  required void Function(String name, Uint8List bytes) onFileDropped,
}) {
  return () {};
}
