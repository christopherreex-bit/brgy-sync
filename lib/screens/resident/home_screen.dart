import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/service_category.dart';
import '../../widgets/user_management_panel.dart';

class HomeScreen extends StatelessWidget {
  final void Function(String categoryId, String subType)? onCategorySelected;

  const HomeScreen({super.key, this.onCategorySelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you need help with?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a service to begin your request.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
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
            itemBuilder: (context, index) =>
                _buildCard(context, kServiceCategories[index]),
          ),
          const SizedBox(height: 12),
          // 7th card centered, wider
          SizedBox(
            width: double.infinity,
            child: _buildCard(context, kServiceCategories[6], isWide: true),
          ),
          const SizedBox(height: 32),
          const UserManagementPanel(),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ServiceCategory cat, {
    bool isWide = false,
  }) {
    return InkWell(
      onTap: () => _onCategoryTap(context, cat),
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
        child: isWide
            ? Row(
                children: [
                  Icon(cat.icon, color: kNavy, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cat.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: kNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat.description,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cat.icon, color: kNavy, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    cat.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: kNavy,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cat.description,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }

  void _onCategoryTap(BuildContext context, ServiceCategory cat) {
    if (cat.subTypes.length == 1) {
      // Only one sub-type, go directly
      onCategorySelected?.call(cat.id, cat.subTypes.first);
      return;
    }
    // Show sub-type picker dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the specific service type:',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...cat.subTypes.map(
              (st) => ListTile(
                dense: true,
                leading: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: kNavy,
                ),
                title: Text(st, style: const TextStyle(fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  onCategorySelected?.call(cat.id, st);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
