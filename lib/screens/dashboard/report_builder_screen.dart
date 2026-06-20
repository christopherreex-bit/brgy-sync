import 'package:flutter/material.dart';
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
              onPressed: _generateReport,
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
              child: const Text('Generate Report', style: TextStyle(fontSize: 16)),
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
                Text(_reportType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

  void _generateReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generating $_reportType... (demo mode)')),
    );
  }
}
