import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Shared export utilities for CSV downloads and PDF generation.
class ExportService {
  // CSV Download

  static void downloadCsv({
    required List<String> headers,
    required List<List<String>> rows,
    required String filename,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_escapeCsv).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCsv).join(','));
    }
    final bytes = utf8.encode(buffer.toString());
    Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
  }

  /// Downloads raw bytes as a file.
  static void downloadBytes({
    required List<int> bytes,
    required String filename,
  }) {
    Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // Compliance Report PDF

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
    await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'report.pdf');
  }

  // Expenditure Summary PDF

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
                  _pdfCell('PHP ${totalAllocated.toStringAsFixed(0)}'),
                  _pdfCell('PHP ${totalUtilized.toStringAsFixed(0)}'),
                  _pdfCell('PHP ${totalRemaining.toStringAsFixed(0)}'),
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
                  _pdfCell('PHP ${(p['allocated'] as double).toStringAsFixed(0)}'),
                  _pdfCell('PHP ${(p['utilized'] as double).toStringAsFixed(0)}'),
                  _pdfCell('PHP ${(p['remaining'] as double).toStringAsFixed(0)}'),
                ])),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfCell('TOTAL', bold: true),
                    _pdfCell('PHP ${totalAllocated.toStringAsFixed(0)}', bold: true),
                    _pdfCell('PHP ${totalUtilized.toStringAsFixed(0)}', bold: true),
                    _pdfCell('PHP ${totalRemaining.toStringAsFixed(0)}', bold: true),
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
    await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'report.pdf');
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
