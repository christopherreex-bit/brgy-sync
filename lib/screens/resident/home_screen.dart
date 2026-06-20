import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _categories = [
    _CatItem('BASS Assistance', 'Medical, burial, rehab, fire relief', Icons.work, catBass),
    _CatItem('Barangay Documents', 'Clearance, indigency cert, brgy ID', Icons.description, catDocuments),
    _CatItem('Community Services', 'Infrastructure, equipment loan', Icons.build, catCommunity),
    _CatItem('Beneficiary Registration', 'Senior citizen & PWD programs', Icons.groups, catBeneficiary),
    _CatItem('VAW / BCPC Report', 'Case report, child protection', Icons.shield, catVaw),
    _CatItem('Education Incentive', 'Honor student application', Icons.school, catEducation),
    _CatItem('Ad Hoc / Special Program', 'One-time distributions or irregular community initiatives', Icons.calendar_month, catAdhoc),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What do you need help with?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Select a service to begin your request.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          // 6 cards in 2x3 grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => _buildCard(context, _categories[index]),
          ),
          const SizedBox(height: 12),
          // 7th card centered, wider
          SizedBox(
            width: double.infinity,
            child: _buildCard(context, _categories[6], isWide: true),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, _CatItem cat, {bool isWide = false}) {
    return InkWell(
      onTap: () {
        // Navigate to submit request for this category
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected: ${cat.name} - form coming in Phase 3')),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(cat.icon, color: kNavy, size: isWide ? 28 : 24),
            const SizedBox(height: 8),
            Text(cat.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(cat.description,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _CatItem {
  final String name;
  final String description;
  final IconData icon;
  final String id;
  const _CatItem(this.name, this.description, this.icon, this.id);
}
