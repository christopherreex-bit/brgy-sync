import 'package:flutter/material.dart';
import '../../widgets/sidebar.dart';

class DashboardShell extends StatelessWidget {
  final Widget child;

  const DashboardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
