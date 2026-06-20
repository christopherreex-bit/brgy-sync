import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class TrackRequestScreen extends StatefulWidget {
  const TrackRequestScreen({super.key});

  @override
  State<TrackRequestScreen> createState() => _TrackRequestScreenState();
}

class _TrackRequestScreenState extends State<TrackRequestScreen> {
  final _searchCtrl = TextEditingController();

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
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by reference number or mobile',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_searchCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a reference number or mobile number')),
                  );
                  return;
                }
                // Search logic coming in Phase 3
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Searching for: ${_searchCtrl.text.trim()}... (Phase 3)')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Search', style: TextStyle(fontSize: 16)),
            ),
          ),
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
