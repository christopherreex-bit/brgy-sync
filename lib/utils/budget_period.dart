class BudgetPeriod {
  final String label;
  final int? fiscalYear;
  final String type;
  final int? quarter;

  const BudgetPeriod({
    required this.label,
    required this.fiscalYear,
    required this.type,
    this.quarter,
  });

  factory BudgetPeriod.fromData(Map<String, dynamic> data) {
    final label = (data['fiscalPeriod'] ?? '').toString().trim();
    final storedYear = (data['fiscalYear'] as num?)?.toInt();
    final storedType = data['periodType'] as String?;
    final storedQuarter = (data['quarter'] as num?)?.toInt();

    if (storedYear != null &&
        (storedType == 'annual' ||
            storedType == 'quarterly' ||
            storedType == 'custom')) {
      return BudgetPeriod(
        label: label,
        fiscalYear: storedYear,
        type: storedType!,
        quarter: storedQuarter,
      );
    }

    return BudgetPeriod.parse(label);
  }

  factory BudgetPeriod.parse(String label) {
    final normalized = label.trim();
    final fiscalMatch = RegExp(
      r'^FY\s+(\d{4})(?:\s+Q([1-4]))?',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (fiscalMatch != null) {
      final year = int.parse(fiscalMatch.group(1)!);
      final quarterText = fiscalMatch.group(2);
      return BudgetPeriod(
        label: normalized,
        fiscalYear: year,
        type: quarterText == null ? 'annual' : 'quarterly',
        quarter: quarterText == null ? null : int.parse(quarterText),
      );
    }

    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(normalized);
    return BudgetPeriod(
      label: normalized,
      fiscalYear: yearMatch == null ? null : int.parse(yearMatch.group(1)!),
      type: 'custom',
    );
  }

  String get scopeLabel {
    if (type == 'annual') return 'Annual';
    if (type == 'quarterly' && quarter != null) return 'Q$quarter';
    return label.isEmpty ? 'Unspecified' : label;
  }

  Map<String, dynamic> get firestoreFields => {
    if (fiscalYear != null) 'fiscalYear': fiscalYear,
    'periodType': type,
    if (quarter != null) 'quarter': quarter,
  };
}

/// Returns true only after the selected fiscal quarter has ended.
///
/// The current quarter remains editable until its final day, while all
/// quarters in an earlier fiscal year are locked.
bool isPastBudgetQuarter(BudgetPeriod period, DateTime asOf) {
  final year = period.fiscalYear;
  final quarter = period.quarter;
  if (year == null || period.type != 'quarterly' || quarter == null) {
    return false;
  }
  final currentQuarter = ((asOf.month - 1) ~/ 3) + 1;
  return year < asOf.year || (year == asOf.year && quarter < currentQuarter);
}
