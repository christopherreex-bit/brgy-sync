import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../widgets/user_management_panel.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user == null || (!user.isStaff && !user.isOfficer)) {
      return const Center(
        child: Text('User Management is available to staff and officers.'),
      );
    }

    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: UserManagementPanel(),
    );
  }
}
