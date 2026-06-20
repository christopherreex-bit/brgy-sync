import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import 'home_screen.dart';
import 'submit_request_screen.dart';
import 'track_request_screen.dart';

class ResidentShell extends StatefulWidget {
  const ResidentShell({super.key});

  @override
  State<ResidentShell> createState() => _ResidentShellState();
}

class _ResidentShellState extends State<ResidentShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    SubmitRequestScreen(),
    TrackRequestScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavy,
        title: Row(
          children: [
            const Icon(Icons.location_city, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BrgySync',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Barangay Calzada-Tipas, Taguig City',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Resident Portal',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.blue.shade50,
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You will receive SMS confirmation for your requests. Walk-in assistance is available at the barangay hall.',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                _tabButton('Home', 0),
                _tabButton('Submit a Request', 1),
                _tabButton('Track My Request', 2),
              ],
            ),
          ),
          // Content
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? kNavy : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? kNavy : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
