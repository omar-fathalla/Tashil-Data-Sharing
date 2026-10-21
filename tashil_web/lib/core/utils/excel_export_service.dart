import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'web_file_helper.dart';

/// ExcelExportService generates CSV / Excel compatible data files
/// and formatted printable HTML/PDF reports, facilitating browser downloading on Flutter Web.
class ExcelExportService {
  ExcelExportService._();

  /// Tracks the most recently downloaded filename for deterministic verification.
  static String? lastDownloadedFilename;

  /// Tracks the most recently downloaded file content for deterministic verification.
  static String? lastDownloadedContent;

  /// Tracks the MIME type of the most recently downloaded file.
  static String? lastDownloadedMimeType;

  /// Resets recorded download tracking state.
  static void resetDownloadHistory() {
    lastDownloadedFilename = null;
    lastDownloadedContent = null;
    lastDownloadedMimeType = null;
  }

  /// Alias for resetDownloadHistory.
  static void resetLastDownloaded() => resetDownloadHistory();

  /// Converts tabular data into CSV format with UTF-8 BOM for Arabic character compatibility.
  static String generateCsv({
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) {
    final buffer = StringBuffer();
    // UTF-8 BOM for Microsoft Excel Arabic support
    buffer.write('\uFEFF');

    // Write Header Row
    buffer.writeln(headers.map(_escapeCsvCell).join(','));

    // Write Data Rows
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCsvCell).join(','));
    }

    return buffer.toString();
  }

  static String _escapeCsvCell(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return '"$str"';
  }

  /// Triggers a browser download of CSV or HTML content.
  static void downloadCsv(String filename, String csvContent) {
    final lower = filename.toLowerCase();
    final mimeType = (lower.endsWith('.html') || lower.endsWith('.htm'))
        ? 'text/html;charset=utf-8'
        : 'text/csv;charset=utf-8';
    downloadFile(
      filename: filename,
      content: csvContent,
      mimeType: mimeType,
    );
  }

  /// Triggers a browser download of printable HTML report content.
  static void downloadHtml(String filename, String htmlContent) {
    downloadFile(
      filename: filename,
      content: htmlContent,
      mimeType: 'text/html;charset=utf-8',
    );
  }

  /// Triggers a real browser download using UTF-8 Blob URL on Web and records download state.
  static void downloadFile({
    required String filename,
    required String content,
    required String mimeType,
  }) {
    lastDownloadedFilename = filename;
    lastDownloadedContent = content;
    lastDownloadedMimeType = mimeType;

    final bytes = utf8.encode(content);
    WebFileHelper.downloadFile(
      filename: filename,
      bytes: bytes,
      mimeType: mimeType,
    );
    if (kIsWeb) {
      debugPrint('[ExcelExportService] Triggered browser download for $filename (${bytes.length} bytes)');
    }
  }

  /// Generates a styled, RTL-ready printable HTML report suitable for saving to PDF or printing.
  static String generatePrintableReport({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
    Map<String, String>? metadata,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="ar" dir="rtl">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<title>$title</title>');
    buffer.writeln('<style>');
    buffer.writeln('''
      @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap');
      body {
        font-family: 'Cairo', sans-serif;
        margin: 24px;
        color: #1F2937;
        direction: rtl;
        background-color: #FAFAFA;
      }
      .header {
        border-bottom: 2px solid #1E3A8A;
        padding-bottom: 12px;
        margin-bottom: 20px;
      }
      h1 {
        margin: 0 0 8px 0;
        color: #1E3A8A;
        font-size: 22px;
      }
      .meta {
        font-size: 13px;
        color: #4B5563;
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 16px;
        background-color: #FFFFFF;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      }
      th {
        background-color: #1E3A8A;
        color: #FFFFFF;
        padding: 10px 12px;
        text-align: right;
        font-size: 13px;
      }
      td {
        padding: 8px 12px;
        border-bottom: 1px solid #E5E7EB;
        font-size: 12px;
        text-align: right;
      }
      tr:nth-child(even) {
        background-color: #F9FAFB;
      }
      @media print {
        body { background-color: #FFFFFF; margin: 0; }
        table { box-shadow: none; }
        th { background-color: #1E3A8A !important; -webkit-print-color-adjust: exact; }
      }
    ''');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<div class="header">');
    buffer.writeln('<h1>$title</h1>');
    if (metadata != null && metadata.isNotEmpty) {
      buffer.writeln('<div class="meta">');
      metadata.forEach((k, v) {
        buffer.writeln('<span><strong>$k:</strong> $v</span>');
      });
      buffer.writeln('</div>');
    }
    buffer.writeln('</div>');

    buffer.writeln('<table>');
    buffer.writeln('<thead><tr>');
    for (final h in headers) {
      buffer.writeln('<th>$h</th>');
    }
    buffer.writeln('</tr></thead>');
    buffer.writeln('<tbody>');
    for (final row in rows) {
      buffer.writeln('<tr>');
      for (final cell in row) {
        buffer.writeln('<td>${cell?.toString() ?? ''}</td>');
      }
      buffer.writeln('</tr>');
    }
    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }
}
