import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/financial_slip_ocr_service.dart';

class FinancialSlipSection extends StatefulWidget {
  final String slipLabel;
  final TextEditingController amountController;
  final TextEditingController referenceController;
  final TextEditingController transactionDateController;
  final TextEditingController institutionController;
  final void Function(FinancialEvidenceDraft? evidence, bool confirmed)
  onChanged;

  const FinancialSlipSection({
    super.key,
    required this.slipLabel,
    required this.amountController,
    required this.referenceController,
    required this.transactionDateController,
    required this.institutionController,
    required this.onChanged,
  });

  @override
  State<FinancialSlipSection> createState() => _FinancialSlipSectionState();
}

class _FinancialSlipSectionState extends State<FinancialSlipSection> {
  final _ocr = FinancialSlipOcrService();
  FinancialEvidenceDraft? _evidence;
  bool _extracting = false;
  bool _confirmed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_detailsEdited);
    }
  }

  List<TextEditingController> get _controllers => [
    widget.amountController,
    widget.referenceController,
    widget.transactionDateController,
    widget.institutionController,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_detailsEdited);
    }
    super.dispose();
  }

  void _detailsEdited() {
    if (!_confirmed || !mounted) return;
    setState(() => _confirmed = false);
    widget.onChanged(_evidence, false);
  }

  Future<void> _chooseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _message = 'The selected file could not be read.');
      return;
    }
    if (bytes.length > 2 * 1024 * 1024) {
      setState(() => _message = 'The slip must be 2 MB or smaller.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => '',
    };
    if (contentType.isEmpty) {
      setState(() => _message = 'Upload a JPG, PNG, or PDF slip.');
      return;
    }

    setState(() {
      _extracting = contentType != 'application/pdf';
      _confirmed = false;
      _message = contentType == 'application/pdf'
          ? 'PDF attached. Enter the printed details manually, then confirm.'
          : 'Reading the slip…';
      _evidence = FinancialEvidenceDraft(
        bytes: bytes,
        fileName: file.name,
        contentType: contentType,
      );
    });
    widget.onChanged(_evidence, false);
    if (contentType == 'application/pdf') return;

    try {
      final extracted = await _ocr.extract(
        bytes: bytes,
        contentType: contentType,
      );
      if (!mounted) return;
      if (extracted.amount != null) {
        widget.amountController.text = _amountText(extracted.amount!);
      }
      if (extracted.transactionNumber.isNotEmpty) {
        widget.referenceController.text = extracted.transactionNumber;
      }
      if (extracted.transactionDate.isNotEmpty) {
        final parsedDate = _parseTransactionDate(extracted.transactionDate);
        if (parsedDate != null) {
          widget.transactionDateController.text = _dateText(parsedDate);
        }
      }
      if (extracted.financialInstitution.isNotEmpty) {
        widget.institutionController.text = extracted.financialInstitution;
      }
      setState(() {
        _extracting = false;
        _message = extracted.confidence > 0
            ? 'OCR suggestions added (${(extracted.confidence * 100).round()}% confidence). Review every field.'
            : 'OCR finished. Review the fields and complete anything missing.';
        _evidence = FinancialEvidenceDraft(
          bytes: bytes,
          fileName: file.name,
          contentType: contentType,
          ocrResult: extracted,
        );
      });
      widget.onChanged(_evidence, false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _message =
            'Automatic reading was unavailable. Enter the slip details manually. ($error)';
      });
    }
  }

  String _amountText(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  String _dateText(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  DateTime? _parseTransactionDate(String value) {
    final text = value.trim();
    final isoDate = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b').firstMatch(text);
    if (isoDate != null) return DateTime.tryParse(isoDate.group(1)!);

    const patterns = [
      'MMMM d, yyyy, h:mm a',
      'MMMM d, yyyy h:mm a',
      'MMMM d, yyyy',
      'MMM d, yyyy, h:mm a',
      'MMM d, yyyy',
      'MM/dd/yyyy',
      'M/d/yyyy',
    ];
    for (final pattern in patterns) {
      try {
        return DateFormat(pattern, 'en_US').parseStrict(text);
      } catch (_) {
        // Try the next supported printed-date format.
      }
    }
    return null;
  }

  Future<void> _selectTransactionDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    var initialDate =
        _parseTransactionDate(widget.transactionDateController.text) ?? today;
    if (initialDate.isAfter(today)) initialDate = today;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Select transaction date',
    );
    if (selected != null) {
      widget.transactionDateController.text = _dateText(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.slipLabel} *',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _extracting ? null : _chooseFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_evidence == null ? 'Upload slip' : 'Replace slip'),
            ),
          ],
        ),
        if (_evidence != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(_evidence!.fileName),
            subtitle: Text(
              '${(_evidence!.bytes.length / 1024).toStringAsFixed(0)} KB · Encrypted when confirmed',
            ),
          ),
        if (_extracting) const LinearProgressIndicator(),
        if (_message != null) ...[
          const SizedBox(height: 6),
          Text(
            _message!,
            style: TextStyle(
              color: _extracting ? Colors.blue.shade700 : Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: widget.amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount shown on slip *',
            prefixText: '₱ ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.referenceController,
          decoration: const InputDecoration(
            labelText: 'Transaction / slip number *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.transactionDateController,
                readOnly: true,
                onTap: _selectTransactionDate,
                decoration: const InputDecoration(
                  labelText: 'Transaction date *',
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.institutionController,
                decoration: const InputDecoration(
                  labelText: 'Bank / institution *',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirmed,
          onChanged: _evidence == null || _extracting
              ? null
              : (value) {
                  setState(() => _confirmed = value == true);
                  widget.onChanged(_evidence, _confirmed);
                },
          title: const Text('I reviewed the slip and confirm these details.'),
          subtitle: const Text(
            'OCR suggestions can be incorrect. The confirmed values are used in the cash ledger.',
          ),
        ),
      ],
    );
  }
}
