import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

/// Shared export utilities for CSV downloads and PDF generation.
class ExportService {
  // ─── CSV Download ────────────────────────────────────────────────

  static void downloadCsv({
    required List<String> headers,
    required List<List<String>> rows,
    required String filename,
    String? rawContent,
  }) {
    final content = rawContent ?? _buildCsv(headers, rows);
    // Prepend UTF-8 BOM so Excel recognizes encoding (fixes mojibake for —, ₱, etc.)
    const bom = [0xEF, 0xBB, 0xBF];
    final bytes = [...bom, ...utf8.encode(content)];
    _downloadBytes(bytes, filename, 'text/csv');
  }

  /// Downloads raw bytes as a file.
  static void downloadBytes({
    required List<int> bytes,
    required String filename,
  }) {
    _downloadBytes(bytes, filename, 'application/octet-stream');
  }

  /// Platform-aware download: uses blob URL on web, sharePdf on mobile/desktop.
  static void _downloadBytes(List<int> bytes, String filename, String mimeType) {
    // Create a blob and trigger download via anchor element
    final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _buildCsv(List<String> headers, List<List<String>> rows) {
    final buffer = StringBuffer();
    if (headers.isNotEmpty) {
      buffer.writeln(headers.map(_escapeCsv).join(','));
    }
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCsv).join(','));
    }
    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ─── Compliance Report PDF ───────────────────────────────────────

  static Future<void> generateCompliancePdf({
    required String month,
    required List<Map<String, dynamic>> breakdown,
    required int totalReceived,
    required int completedOnTime,
    required int overdueCases,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final widgets = <pw.Widget>[
            pw.Text(
              "Citizens' Charter Compliance Report",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Barangay Calzada-Tipas, Taguig City',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Period: $month  |  Generated: ${now.month}/${now.day}/${now.year}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Divider(),
            pw.Text(
              'Summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(children: [
                  _pdfCell('Total Received', bold: true),
                  _pdfCell('Completed On Time', bold: true),
                  _pdfCell('Overdue Cases', bold: true),
                  _pdfCell('Compliance Rate', bold: true),
                ]),
                pw.TableRow(children: [
                  _pdfCell('$totalReceived'),
                  _pdfCell('$completedOnTime'),
                  _pdfCell('$overdueCases'),
                  _pdfCell(
                    totalReceived > 0
                        ? '${(completedOnTime / totalReceived * 100).toStringAsFixed(1)}%'
                        : 'N/A',
                  ),
                ]),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Breakdown by Category',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Category', bold: true),
                    _pdfCell('Received', bold: true),
                    _pdfCell('On Time', bold: true),
                    _pdfCell('Overdue', bold: true),
                    _pdfCell('Rate %', bold: true),
                  ],
                ),
                ...breakdown.map((d) {
                  final total = d['total'] as int;
                  final onTime = d['onTime'] as int;
                  final rate = total > 0
                      ? (onTime / total * 100).toStringAsFixed(1)
                      : '0.0';
                  return pw.TableRow(children: [
                    _pdfCell((d['category'] as String).toUpperCase()),
                    _pdfCell('$total'),
                    _pdfCell('$onTime'),
                    _pdfCell('${d['overdue']}'),
                    _pdfCell('$rate%'),
                  ]);
                }),
              ],
            ),
          ];
          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    // For PDF: use layoutPdf (opens print dialog, user can save as PDF)
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  // ─── Expenditure Summary PDF ─────────────────────────────────────

  static Future<void> generateExpenditurePdf({
    required List<Map<String, dynamic>> programData,
    required double totalAllocated,
    required double totalUtilized,
    required double totalRemaining,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final widgets = <pw.Widget>[
            pw.Text(
              'Expenditure Summary Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Barangay Calzada-Tipas, Taguig City',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${now.month}/${now.day}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Divider(),
            pw.Text(
              'Budget Summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(children: [
                  _pdfCell('Total Allocated', bold: true),
                  _pdfCell('Total Utilized', bold: true),
                  _pdfCell('Total Remaining', bold: true),
                ]),
                pw.TableRow(children: [
                  _php(totalAllocated),
                  _php(totalUtilized),
                  _php(totalRemaining),
                ]),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Breakdown by Program',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Program', bold: true),
                    _pdfCell('Allocated', bold: true),
                    _pdfCell('Utilized', bold: true),
                    _pdfCell('Remaining', bold: true),
                  ],
                ),
                ...programData.map((p) => pw.TableRow(children: [
                  _pdfCell(p['name'] ?? ''),
                  _php(p['allocated'] as double),
                  _php(p['utilized'] as double),
                  _php(p['remaining'] as double),
                ])),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfCell('TOTAL', bold: true),
                    _php(totalAllocated, bold: true),
                    _php(totalUtilized, bold: true),
                    _php(totalRemaining, bold: true),
                  ],
                ),
              ],
            ),
          ];
          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  static pw.Widget _php(double value, {bool bold = false}) {
    return _pdfCell('PHP ${value.toStringAsFixed(0)}', bold: bold);
  }

  static pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : null,
        ),
      ),
    );
  }
}
