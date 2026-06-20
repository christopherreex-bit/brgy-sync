import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class TrackRequestScreen extends StatefulWidget {
  const TrackRequestScreen({super.key});

  @override
  State<TrackRequestScreen> createState() => _TrackRequestScreenState();
}

class _TrackRequestScreenState extends State<TrackRequestScreen> {
  final _searchCtrl = TextEditingController();
  bool _searched = false;
  bool _loading = false;
  List<QueryDocumentSnapshot> _results = [];
  String? _error;

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reference number or mobile number')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
      _results = [];
    });

    try {
      final db = FirebaseFirestore.instance;
      List<QueryDocumentSnapshot> results;

      // Try reference number first (exact match)
      if (query.toUpperCase().startsWith('BRGY-')) {
        final snap = await db
            .collection('cases')
            .where('referenceNumber', isEqualTo: query.toUpperCase())
            .get();
        results = snap.docs;
      } else {
        // Search by mobile number
        final snap = await db
            .collection('cases')
            .where('residentMobile', isEqualTo: query)
            .orderBy('submissionTimestamp', descending: true)
            .limit(10)
            .get();
        results = snap.docs;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _results = results;
          if (results.isEmpty) {
            _error = 'No cases found for "$query". Please check the reference number or mobile number.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Search failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Track My Request',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Enter your reference number or mobile number to check your case status.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by reference number or mobile',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    foregroundColor: Colors.white,
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Search'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          if (_results.isNotEmpty) ...[
            const Text('Search Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
            const SizedBox(height: 12),
            ..._results.map((doc) => _buildCaseCard(doc.data() as Map<String, dynamic>)),
          ],
        ],
      ),
    );
  }

  Widget _buildCaseCard(Map<String, dynamic> data) {
    final ref = data['referenceNumber'] ?? '';
    final category = data['serviceCategory'] ?? '';
    final subType = data['serviceSubType'] ?? '';
    final status = data['status'] ?? 'pending_review';
    final isConfidential = data['isConfidential'] ?? false;
    final residentName = isConfidential ? 'Confidential' : (data['residentName'] ?? '');
    final ts = data['submissionTimestamp'];
    final dateStr = ts is Timestamp
        ? '${ts.toDate().month}/${ts.toDate().day}/${ts.toDate().year} ${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(category.toUpperCase(), style: const TextStyle(fontSize: 9, color: kNavy, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 8),
          Text('$residentName · $subType', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Submitted: $dateStr', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
