import 'package:flutter/material.dart';

class SubmitRequestScreen extends StatelessWidget {
  const SubmitRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Select a service from the Home tab to submit a request.\n(Intake forms coming in Phase 3)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }
}
