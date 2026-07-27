import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../utils/account_validators.dart';
import '../utils/constants.dart';

class UserManagementPanel extends StatefulWidget {
  final bool showHeading;

  const UserManagementPanel({super.key, this.showHeading = true});

  @override
  State<UserManagementPanel> createState() => _UserManagementPanelState();
}

class _UserManagementPanelState extends State<UserManagementPanel> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeading) ...[
          const Text(
            'User Management',
            style: TextStyle(
              color: kNavy,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Manage your signed-in account and security.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 20),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
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
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: kNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ProfileRow(label: 'Name', value: user.name),
              _ProfileRow(label: 'Email', value: user.email),
              _ProfileRow(label: 'Mobile', value: user.mobile),
              _ProfileRow(label: 'Role', value: caseStatusLabel(user.role)),
              const Divider(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _showChangePasswordDialog,
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Change Password'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _showDeleteAccountDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? currentError;
    String? newError;
    String? confirmError;
    var obscureCurrent = true;
    var obscureNew = true;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: obscureCurrent,
                  onChanged: (value) {
                    setDialogState(() {
                      currentError = value.isEmpty
                          ? 'Enter your current password.'
                          : null;
                      if (newController.text.isNotEmpty) {
                        newError = newController.text == value
                            ? 'New password must be different from your current password.'
                            : validateStaffPassword(newController.text);
                      }
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    border: const OutlineInputBorder(),
                    errorText: currentError,
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(
                        () => obscureCurrent = !obscureCurrent,
                      ),
                      icon: Icon(
                        obscureCurrent
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: obscureNew,
                  onChanged: (value) {
                    setDialogState(() {
                      newError = validateStaffPassword(value);
                      if (newError == null && value == currentController.text) {
                        newError =
                            'New password must be different from your current password.';
                      }
                      if (confirmController.text.isNotEmpty) {
                        confirmError = confirmController.text == value
                            ? null
                            : 'New passwords do not match.';
                      }
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 6 characters',
                    border: const OutlineInputBorder(),
                    errorText: newError,
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => obscureNew = !obscureNew),
                      icon: Icon(
                        obscureNew ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: obscureNew,
                  onChanged: (value) => setDialogState(
                    () => confirmError = value == newController.text
                        ? null
                        : 'New passwords do not match.',
                  ),
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    border: const OutlineInputBorder(),
                    errorText: confirmError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final validationError = validatePasswordChange(
                  currentPassword: currentController.text,
                  newPassword: newController.text,
                );
                final passwordsMatch =
                    newController.text == confirmController.text;
                if (validationError != null || !passwordsMatch) {
                  setDialogState(() {
                    currentError = currentController.text.isEmpty
                        ? 'Enter your current password.'
                        : null;
                    newError = validationError != 'Enter your current password.'
                        ? validationError
                        : null;
                    confirmError = passwordsMatch
                        ? null
                        : 'New passwords do not match.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(backgroundColor: kNavy),
              child: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
    final currentPassword = currentController.text;
    final newPassword = newController.text;
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    if (submitted != true || !mounted) return;

    setState(() => _busy = true);
    final result = await context.read<AuthService>().changeOwnPassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(
      result ?? 'Password changed successfully.',
      isError: result != null,
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final passwordController = TextEditingController();
    String? error;
    var obscurePassword = true;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permanently Delete Account?'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This removes your login and user profile permanently. '
                  'Official case and audit records are retained.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    border: const OutlineInputBorder(),
                    errorText: error,
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  setDialogState(() => error = 'Enter your current password.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete My Account'),
            ),
          ],
        ),
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    if (submitted != true || !mounted) return;

    setState(() => _busy = true);
    final result = await context.read<AuthService>().deleteOwnAccount(
      currentPassword: password,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _busy = false);
      _showResult(result, isError: true);
      return;
    }
    context.go('/login');
  }

  void _showResult(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
