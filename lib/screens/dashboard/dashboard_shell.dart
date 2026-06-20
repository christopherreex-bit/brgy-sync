import 'package:flutter/material.dart';
import '../../widgets/sidebar.dart';
import 'case_queue_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),
          const Expanded(
            child: CaseQueueScreen(), // Default landing page
          ),
        ],
      ),
    );
  }
}
