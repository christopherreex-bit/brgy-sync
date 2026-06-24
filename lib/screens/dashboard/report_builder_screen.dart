import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel_plus/excel_plus.dart' hide Border, BorderStyle, BorderSide, TableBorder;
import '../../utils/constants.dart';

class ReportBuilderScreen extends StatefulWidget {
  const ReportBuilderScreen({super.key});

  @override
  State<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _ReportBuilderScreenState extends State<ReportBuilderScreen> {
  String _reportType = 'DSWD Social Services Summary';
  DateTime? _periodFrom;
  DateTime? _periodTo;
  String _outputFormat = 'PDF';
  bool _generating = false;

  String get _reportTypeKey {
    if (_reportType.startsWith('DSWD')) return 'dswd_summary';
    if (_reportType.startsWith('DILG')) return 'dilg_compliance';
    return 'charter_compliance';
  }

  String get _reportTypeLabel {
    if (_reportType.startsWith('DSWD')) return 'DSWD Social Services Summary';
    if (_reportType.startsWith('DILG')) return 'DILG Operational Compliance Report';
    return "Citizens' Charter Compliance Report";
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Report Builder',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Auto-generate operational reports for DSWD, DILG, and Charter compliance.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compiled automatically from validated records. No manual data entry required.',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Report Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _reportType,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'DSWD Social Services Summary', child: Text('DSWD Social Services Summary')),
              DropdownMenuItem(value: 'DILG Operational Compliance Report', child: Text('DILG Operational Compliance Report')),
              DropdownMenuItem(value: "Citizens' Charter Compliance Report", child: Text("Citizens' Charter Compliance Report")),
            ],
            onChanged: (v) => setState(() => _reportType = v!),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _periodFrom ?? DateTime.now(),
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _periodFrom = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Period From', border: OutlineInputBorder()),
                    child: Text(
                      _periodFrom != null
                          ? '${_periodFrom!.month}/${_periodFrom!.day}/${_periodFrom!.year}'
                          : 'Select date',
                      style: TextStyle(color: _periodFrom != null ? Colors.black : Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _periodTo ?? DateTime.now(),
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _periodTo = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Period To', border: OutlineInputBorder()),
                    child: Text(
                      _periodTo != null
                          ? '${_periodTo!.month}/${_periodTo!.day}/${_periodTo!.year}'
                          : 'Select date',
                      style: TextStyle(color: _periodTo != null ? Colors.black : Colors.grey),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text('Output Format', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _outputFormat,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'PDF', child: Text('PDF (formatted report)')),
              DropdownMenuItem(value: 'Excel', child: Text('Excel (.xlsx)')),
            ],
            onChanged: (v) => setState(() => _outputFormat = v!),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _genering ? null : _generateReport,
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
              child: _genering
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Generate Report', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 20),

          // Preview pane
          const Text('Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_reportTypeLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Reporting Period: ${_periodFrom != null ? '${_periodFrom!.month}/${_periodFrom!.day}/${_periodFrom!.year}' : 'All'} - ${_periodTo != null ? '${_periodTo!.month}/${_periodTo!.day}/${_periodTo!.year}' : 'Present'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text('Select parameters and click Generate to populate this report.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _genering => _generating;

  Future<void> _generateReport() async {
    setState(() => _generating = true);
    try {
      // Query cases within the date range
      Query query = FirebaseFirestore.instance.collection('cases');
      if (_periodFrom != null) {
        query = query.where('submissionTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_periodFrom!));
      }
      if (_periodTo != null) {
        query = query.where('submissionTimestamp', isLessThanOrEqualTo: Timestamp.fromDate(_periodTo!.add(const Duration(days: 1))));
      }
      final snapshot = await query.get();
      final cases = snapshot.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      // Aggregate data
      final totalCases = cases.length;
      final resolved = cases.where((c) => c['status'] == 'released' || c['status'] == 'rejected').length;
      final pending = cases.where((c) => c['status'] == 'pending_review' || c['status'] == 'processing').length;

      final categoryCounts = <String, int>{};
      final categoryResolved = <String, int>{};
      final categoryOnTime = <String, int>{};
      final categoryOverdue = <String, int>{};

      for (final c in cases) {
        final cat = (c['serviceCategory'] ?? 'unknown').toString();
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
        if (c['status'] == 'released' || c['status'] == 'rejected') {
          categoryResolved[cat] = (categoryResolved[cat] ?? 0) + 1;
        }
        final sla = (c['slaStatus'] ?? 'on_time').toString();
        if (sla == 'on_time') categoryOnTime[cat] = (categoryOnTime[cat] ?? 0) + 1;
        if (sla == 'overdue') categoryOverdue[cat] = (categoryOverdue[cat] ?? 0) + 1;
      }

      if (_outputFormat == 'PDF') {
        await _generatePdf(
          cases: cases,
          totalCases: totalCases,
          resolved: resolved,
          pending: pending,
          categoryCounts: categoryCounts,
          categoryResolved: categoryResolved,
          categoryOnTime: categoryOnTime,
          categoryOverdue: categoryOverdue,
        );
      } else {
        await _generateExcel(
          totalCases: totalCases,
          resolved: resolved,
          pending: pending,
          categoryCounts: categoryCounts,
          categoryResolved: categoryResolved,
          categoryOnTime: categoryOnTime,
          categoryOverdue: categoryOverdue,
        );
      }

      // Save report record to Firestore
      await FirebaseFirestore.instance.collection('reports').add({
        'type': _reportTypeKey,
        'typeName': _reportTypeLabel,
        'period': '${_periodFrom?.toIso8601String() ?? 'all'} - ${_periodTo?.toIso8601String() ?? 'present'}',
        'format': _outputFormat.toLowerCase(),
        'generatedAt': FieldValue.serverTimestamp(),
        'generatedBy': 'system',
        'totalCases': totalCases,
        'resolved': resolved,
        'pending': pending,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_reportTypeLabel generated successfully.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePdf({
    required List<Map<String, dynamic>> cases,
    required int totalCases,
    required int resolved,
    required int pending,
    required Map<String, int> categoryCounts,
    required Map<String, int> categoryResolved,
    required Map<String, int> categoryOnTime,
    required Map<String, int> categoryOverdue,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final periodStr = '${_periodFrom != null ? '${_periodFrom!.month}/${_periodFrom!.day}/${_periodFrom!.year}' : 'All'} - ${_periodTo != null ? '${_periodTo!.month}/${_periodTo!.day}/${_periodTo!.year}' : 'Present'}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) [
          // Header
          pw.Text('BrgySync — $_reportTypeLabel', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Barangay Calzada-Tipas, Taguig City', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text('Generated: ${now.month}/${now.day/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.Text('Period: $periodStr', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.Divider(),

          // Summary
          pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(children: [
                _pdfCell('Total Cases', bold: true),
                _pdfCell('Resolved', bold: true),
                _pdfCell('Pending', bold: true),
                _pdfCell('Resolution Rate', bold: true),
              ]),
              pw.TableRow(children: [
                _pdfCell('$totalCases'),
                _pdfCell('$resolved'),
                _pdfCell('$pending'),
                _pdfCell(totalCases > 0 ? '${(resolved / totalCases * 100).toStringAsFixed(1)}%' : 'N/A'),
              ]),
            ],
          ),
          pw.SizedBox(height: 16),

          // Category breakdown
          pw.Text('Breakdown by Category', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
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
                  _pdfCell('Total', bold: true),
                  _pdfCell('Resolved', bold: true),
                  _pdfCell('On Time', bold: true),
                  _pdfCell('Overdue', bold: true),
                ],
              ),
              ...categoryCounts.entries.map((entry) {
                final cat = entry.key;
                final total = entry.value;
                final onTime = categoryOnTime[cat] ?? 0;
                final overdue = categoryOverdue[cat] ?? 0;
                return pw.TableRow(children: [
                  _pdfCell(cat.toUpperCase()),
                  _pdfCell('$total'),
                  _pdfCell('${categoryResolved[cat] ?? 0}'),
                  _pdfCell('$onTime'),
                  _pdfCell('$overdue'),
                ]);
              }),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
    );
  }

  Future<void> _generateExcel({
    required int totalCases,
    required int resolved,
    required int pending,
    required Map<String, int> categoryCounts,
    required Map<String, int> categoryResolved,
    required Map<String, int> categoryOnTime,
    required Map<String, int> categoryOverdue,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    // Title
    sheet.updateCell(CellIndex.indexByString('A1'), TextCellValue('BrgySync - $_reportTypeLabel'));
    sheet.updateCell(CellIndex.indexByString('A2'), TextCellValue('Barangay Calzada-Tipas, Taguig City'));
    final periodLabel = '${_periodFrom != null ? '${_periodFrom!.month}/${_periodFrom!.day}/${_periodFrom!.year}' : 'All'} - ${_periodTo != null ? '${_periodTo!.month}/${_periodTo!.day}/${_periodTo!.year}' : 'Present'}';
    sheet.updateCell(CellIndex.indexByString('A3'), TextCellValue('Period: $periodLabel'));

    // Summary
    sheet.updateCell(CellIndex.indexByString('A5'), TextCellValue('Summary'));
    sheet.updateCell(CellIndex.indexByString('A6'), TextCellValue('Total Cases'));
    sheet.updateCell(CellIndex.indexByString('B6'), IntCellValue(totalCases));
    sheet.updateCell(CellIndex.indexByString('A7'), TextCellValue('Resolved'));
    sheet.updateCell(CellIndex.indexByString('B7'), IntCellValue(resolved));
    sheet.updateCell(CellIndex.indexByString('A8'), TextCellValue('Pending'));
    sheet.updateCell(CellIndex.indexByString('B8'), IntCellValue(pending));
    sheet.updateCell(CellIndex.indexByString('A9'), TextCellValue('Resolution Rate'));
    sheet.updateCell(CellIndex.indexByString('B9'), TextCellValue(totalCases > 0 ? '${(resolved / totalCases * 100).toStringAsFixed(1)}%' : 'N/A'));

    // Category breakdown
    sheet.updateCell(CellIndex.indexByString('A11'), TextCellValue('Breakdown by Category'));
    sheet.updateCell(CellIndex.indexByString('A12'), TextCellValue('Category'));
    sheet.updateCell(CellIndex.indexByString('B12'), TextCellValue('Total'));
    sheet.updateCell(CellIndex.indexByString('C12'), TextCellValue('Resolved'));
    sheet.updateCell(CellIndex.indexByString('D12'), TextCellValue('On Time'));
    sheet.updateCell(CellIndex.indexByString('E12'), TextCellValue('Overdue'));

    var row = 13;
    for (final entry in categoryCounts.entries) {
      final cat = entry.key;
      sheet.updateCell(CellIndex.indexByString('A$row'), TextCellValue(cat.toUpperCase()));
      sheet.updateCell(CellIndex.indexByString('B$row'), IntCellValue(entry.value));
      sheet.updateCell(CellIndex.indexByString('C$row'), IntCellValue(categoryResolved[cat] ?? 0));
      sheet.updateCell(CellIndex.indexByString('D$row'), IntCellValue(categoryOnTime[cat] ?? 0));
      sheet.updateCell(CellIndex.indexByString('E$row'), IntCellValue(categoryOverdue[cat] ?? 0));
      row++;
    }

    // Save and download
    final bytes = excel.save();
    if (bytes != null) {
      final fileName = '${_reportTypeKey}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }
}
