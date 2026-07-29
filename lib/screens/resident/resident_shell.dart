import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import 'home_screen.dart';
import 'submit_request_screen.dart';
import 'track_request_screen.dart';
import 'notifications_screen.dart';

class ResidentShell extends StatefulWidget {
  const ResidentShell({super.key});

  @override
  State<ResidentShell> createState() => ResidentShellState();
}

class ResidentShellState extends State<ResidentShell> {
  int _currentIndex = 0;
  String? _pendingCategoryId;
  String? _pendingSubType;
  int _submitSession = 0;

  void switchToSubmitTab({String? categoryId, String? subType}) {
    setState(() {
      _currentIndex = 1;
      _pendingCategoryId = categoryId;
      _pendingSubType = subType;
      _submitSession++;
    });
  }

  void _selectTab(int index) {
    setState(() {
      if (_currentIndex == 1 && index != 1) {
        _pendingCategoryId = null;
        _pendingSubType = null;
        _submitSession++;
      }
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUserModel;

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
                Text(
                  'BrgySync',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Barangay Calzada-Tipas, Taguig City',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Resident Portal',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () async {
                  await auth.logout();
                  if (context.mounted) context.go('/login');
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, color: Colors.white70, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'Log Out',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
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
                _tabButton('My Cases', 2),
                _tabButton('Notifications', 3),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _currentIndex == 0
                ? HomeScreen(
                    onCategorySelected: (catId, subType) {
                      switchToSubmitTab(categoryId: catId, subType: subType);
                    },
                  )
                : _currentIndex == 1
                ? SubmitRequestScreen(
                    key: ValueKey(
                      'submit_$_submitSession'
                      '_$_pendingCategoryId'
                      '_$_pendingSubType',
                    ),
                    initialCategoryId: _pendingCategoryId,
                    initialSubType: _pendingSubType,
                  )
                : _currentIndex == 2
                ? const TrackRequestScreen()
                : const NotificationsScreen(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTab(index),
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
