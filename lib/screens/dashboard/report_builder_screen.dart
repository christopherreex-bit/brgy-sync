import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  bool _isGenerating = false;

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
              onPressed: _isGenerating ? null : _generateReport,
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
              child: _isGenerating
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

  List<String> get _reportCategories {
    if (_reportType.startsWith('DSWD')) {
      return ['bass', 'documents', 'community', 'beneficiary', 'education', 'adhoc'];
    }
    if (_reportType.startsWith('DILG')) {
      return ['documents', 'bass', 'vaw', 'community'];
    }
    // Charter: all categories
    return ['bass', 'documents', 'community', 'beneficiary', 'vaw', 'education', 'adhoc'];
  }

  Future<void> _generateReport() async {
    setState(() => _isGenerating = true);
    try {
      Query query = FirebaseFirestore.instance.collection('cases');
      if (_periodFrom != null) {
        query = query.where('submissionTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_periodFrom!));
      }
      if (_periodTo != null) {
        query = query.where('submissionTimestamp', isLessThanOrEqualTo: Timestamp.fromDate(_periodTo!.add(const Duration(days: 1))));
      }
      final snapshot = await query.get();
      final allCases = snapshot.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      // Filter cases by report type categories
      final cases = allCases.where((c) {
        final cat = (c['serviceCategory'] ?? '').toString();
        return _reportCategories.contains(cat);
      }).toList();

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

      // Generate file bytes based on selected format
      List<int> fileBytes;
      String fileName;
      if (_outputFormat == 'Excel') {
        final csv = _buildCsvContent(
          totalCases: totalCases,
          resolved: resolved,
          pending: pending,
          categoryCounts: categoryCounts,
          categoryResolved: categoryResolved,
          categoryOnTime: categoryOnTime,
          categoryOverdue: categoryOverdue,
        );
        fileBytes = utf8.encode(csv);
        fileName = '${_reportTypeKey}_${DateTime.now().millisecondsSinceEpoch}.csv';
      } else {
        fileBytes = await _buildPdfBytes(
          totalCases: totalCases,
          resolved: resolved,
          pending: pending,
          categoryCounts: categoryCounts,
          categoryResolved: categoryResolved,
          categoryOnTime: categoryOnTime,
          categoryOverdue: categoryOverdue,
        );
        fileName = '${_reportTypeKey}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      }

      // Build CSV content for storage (works for both PDF and Excel reports)
      final csvContent = _buildCsvContent(
        totalCases: totalCases,
        resolved: resolved,
        pending: pending,
        categoryCounts: categoryCounts,
        categoryResolved: categoryResolved,
        categoryOnTime: categoryOnTime,
        categoryOverdue: categoryOverdue,
      );

      // Save report record to Firestore archive
      // Store both PDF bytes (for download) and CSV content (for viewing)
      await FirebaseFirestore.instance.collection('reports').add({
        'type': _reportTypeKey,
        'typeName': _reportTypeLabel,
        'period': '${_periodFrom?.toIso8601String() ?? 'all'} - ${_periodTo?.toIso8601String() ?? 'present'}',
        'format': _outputFormat.toLowerCase(),
        'fileName': fileName,
        'fileBytes': fileBytes,
        'csvContent': csvContent,
        'generatedAt': FieldValue.serverTimestamp(),
        'generatedBy': 'system',
        'totalCases': totalCases,
        'resolved': resolved,
        'pending': pending,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_reportTypeLabel generated. View in Report Archive.'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View Archive',
              onPressed: () => context.go('/dashboard/report-archive'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<List<int>> _buildPdfBytes({
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
        build: (pw.Context ctx) {
          final w = <pw.Widget>[
            pw.Text(
              'BrgySync - $_reportTypeLabel',
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
            pw.Text(
              'Period: $periodStr',
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
                  _pdfCell('Total Cases', bold: true),
                  _pdfCell('Resolved', bold: true),
                  _pdfCell('Pending', bold: true),
                  _pdfCell('Resolution Rate', bold: true),
                ]),
                pw.TableRow(children: [
                  _pdfCell('$totalCases'),
                  _pdfCell('$resolved'),
                  _pdfCell('$pending'),
                  _pdfCell(
                    totalCases > 0 ? '${(resolved / totalCases * 100).toStringAsFixed(1)}%' : 'N/A',
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
          ];
          return w;
        },
      ),
    );

    return await pdf.save();
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null),
      ),
    );
  }

  String _buildCsvContent({
    required int totalCases,
    required int resolved,
    required int pending,
    required Map<String, int> categoryCounts,
    required Map<String, int> categoryResolved,
    required Map<String, int> categoryOnTime,
    required Map<String, int> categoryOverdue,
  }) {
    final buffer = StringBuffer();
    final periodLabel = '${_periodFrom != null ? '${_periodFrom!.month}/${_periodFrom!.day}/${_periodFrom!.year}' : 'All'} - ${_periodTo != null ? '${_periodTo!.month}/${_periodTo!.day}/${_periodTo!.year}' : 'Present'}';

    buffer.writeln('BrgySync - $_reportTypeLabel');
    buffer.writeln('Barangay Calzada-Tipas, Taguig City');
    buffer.writeln('Period: $periodLabel');
    buffer.writeln();
    buffer.writeln('Summary');
    buffer.writeln('Total Cases,$totalCases');
    buffer.writeln('Resolved,$resolved');
    buffer.writeln('Pending,$pending');
    buffer.writeln('Resolution Rate,${totalCases > 0 ? '${(resolved / totalCases * 100).toStringAsFixed(1)}%' : 'N/A'}');
    buffer.writeln();
    buffer.writeln('Breakdown by Category');
    buffer.writeln('Category,Total,Resolved,On Time,Overdue');

    for (final entry in categoryCounts.entries) {
      final cat = entry.key;
      final total = entry.value;
      final onTime = categoryOnTime[cat] ?? 0;
      final overdue = categoryOverdue[cat] ?? 0;
      buffer.writeln('${cat.toUpperCase()},$total,${categoryResolved[cat] ?? 0},$onTime,$overdue');
    }

    return buffer.toString();
  }
}
