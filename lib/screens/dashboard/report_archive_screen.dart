import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../services/export_service.dart';

class ReportArchiveScreen extends StatefulWidget {
  const ReportArchiveScreen({super.key});

  @override
  State<ReportArchiveScreen> createState() => _ReportArchiveScreenState();
}

class _ReportArchiveScreenState extends State<ReportArchiveScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Report Archive',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Previously generated reports.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // Filter tabs
          Row(
            children: [
              _filterBtn('All Reports', 'all'),
              const SizedBox(width: 8),
              _filterBtn('DSWD', 'dswd_summary'),
              const SizedBox(width: 8),
              _filterBtn('DILG', 'dilg_compliance'),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _filter == 'all'
                  ? FirebaseFirestore.instance.collection('reports').orderBy('generatedAt', descending: true).snapshots()
                  : FirebaseFirestore.instance
                      .collection('reports')
                      .where('type', isEqualTo: _filter)
                      .orderBy('generatedAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.archive_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No reports generated yet.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Use the Report Builder to generate reports.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final name = data['type'] ?? 'Report';
                    final format = data['format'] ?? 'pdf';
                    final period = data['period'] ?? '';
                    final ts = data['generatedAt'];
                    final dateStr = ts is Timestamp ? '${ts.toDate().month}/${ts.toDate().day}/${ts.toDate().year}' : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.description, color: kNavy, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('$period · $dateStr',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: format == 'pdf' ? Colors.red.shade50 : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(format.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: format == 'pdf' ? Colors.red : Colors.green,
                                )),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.download, size: 20),
                            onPressed: () => _downloadReport(data),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _downloadReport(Map<String, dynamic> data) {
    final name = (data['typeName'] ?? data['type'] ?? 'Report').toString();
    final type = (data['type'] ?? '').toString();
    final format = (data['format'] ?? 'pdf').toString();
    final fileName = (data['fileName'] ?? '${type}_report').toString();
    final csvContent = (data['csvContent'] ?? '').toString();
    final storedBytes = data['fileBytes'];
    final totalCases = data['totalCases'] ?? 0;
    final resolved = data['resolved'] ?? 0;
    final pending = data['pending'] ?? 0;
    final period = (data['period'] ?? '').toString();

    // For PDF reports: download stored PDF bytes
    if (format == 'pdf' && storedBytes != null && storedBytes is List && storedBytes.isNotEmpty) {
      ExportService.downloadBytes(
        bytes: List<int>.from(storedBytes),
        filename: fileName.endsWith('.pdf') ? fileName : '$fileName.pdf',
      );
    } else if (csvContent.isNotEmpty) {
      // For Excel reports or fallback: download CSV content
      final csvFileName = fileName.endsWith('.csv') ? fileName : '$fileName.csv';
      ExportService.downloadCsv(
        headers: <String>[],
        rows: <List<String>>[],
        filename: csvFileName,
        rawContent: csvContent,
      );
    } else {
      // Final fallback: generate minimal CSV from metadata
      final buffer = StringBuffer();
      buffer.writeln('BrgySync - $name');
      buffer.writeln('Barangay Calzada-Tipas, Taguig City');
      buffer.writeln('Period: $period');
      buffer.writeln();
      buffer.writeln('Summary');
      buffer.writeln('Total Cases,$totalCases');
      buffer.writeln('Resolved,$resolved');
      buffer.writeln('Pending,$pending');
      buffer.writeln('Resolution Rate,${totalCases > 0 ? '${(resolved / totalCases * 100).toStringAsFixed(1)}%' : 'N/A'}');

      ExportService.downloadCsv(
        headers: <String>[],
        rows: <List<String>>[],
        filename: '${type}_report.csv',
        rawContent: buffer.toString(),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded: $name ($format)'), backgroundColor: Colors.green),
    );
  }

  Widget _filterBtn(String label, String key) {
    final isActive = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? kNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? kNavy : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: isActive ? Colors.white : Colors.grey.shade700,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}
