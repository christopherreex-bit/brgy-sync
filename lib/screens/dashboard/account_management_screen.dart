import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/account_validators.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCreateAccountDialog() async {
    Set<String> existingEmails;
    try {
      existingEmails = await context
          .read<AuthService>()
          .getExistingAccountEmails();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not check existing emails: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'staff';
    String? emailError;
    String? mobileError;
    String? passwordError;

    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create New Account'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                      errorText: emailError,
                      suffixIcon:
                          emailCtrl.text.isNotEmpty && emailError == null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) => setDialogState(
                      () => emailError = validateUniqueAccountEmail(
                        value,
                        existingEmails,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mobileCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mobile (09XXXXXXXXX)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone),
                      errorText: mobileError,
                      suffixIcon:
                          mobileCtrl.text.isNotEmpty && mobileError == null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (value) => setDialogState(
                      () => mobileError = validatePhilippineMobile(value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      errorText: passwordError,
                      helperText: 'At least 6 characters',
                      suffixIcon:
                          passCtrl.text.isNotEmpty && passwordError == null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                    obscureText: true,
                    onChanged: (value) => setDialogState(
                      () => passwordError = validateStaffPassword(value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text('Barangay Staff'),
                      ),
                      DropdownMenuItem(
                        value: 'officer',
                        child: Text('Committee Officer'),
                      ),
                      DropdownMenuItem(
                        value: 'captain',
                        child: Text('Barangay Captain'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => selectedRole = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final nextEmailError = validateUniqueAccountEmail(
                  emailCtrl.text,
                  existingEmails,
                );
                final nextMobileError = validatePhilippineMobile(
                  mobileCtrl.text,
                );
                final nextPasswordError = validateStaffPassword(passCtrl.text);
                setDialogState(() {
                  emailError = nextEmailError;
                  mobileError = nextMobileError;
                  passwordError = nextPasswordError;
                });
                if (nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Full name is required.')),
                  );
                  return;
                }
                if (nextEmailError != null ||
                    nextMobileError != null ||
                    nextPasswordError != null) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
    if (shouldConfirm == true && mounted) {
      await _showConfirmPasswordDialog(
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim().toLowerCase(),
        mobile: mobileCtrl.text.trim(),
        password: passCtrl.text,
        role: selectedRole,
      );
    }
    nameCtrl.dispose();
    emailCtrl.dispose();
    mobileCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showConfirmPasswordDialog({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String role,
  }) async {
    final confirmPassCtrl = TextEditingController();
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Confirm Your Identity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your password to confirm account creation',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPassCtrl,
                decoration: const InputDecoration(
                  labelText: 'Captain Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (confirmPassCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter your password'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => loading = true);
                      final auth = context.read<AuthService>();
                      final captainPassword = confirmPassCtrl.text;
                      final confirmationError = await auth
                          .confirmCurrentUserPassword(captainPassword);
                      if (confirmationError != null) {
                        if (ctx.mounted) {
                          setDialogState(() => loading = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(confirmationError),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }

                      final err = await auth.createStaffAccount(
                        name: name,
                        email: email,
                        mobile: mobile,
                        password: password,
                        role: role,
                      );
                      if (ctx.mounted && err == null) Navigator.pop(ctx);
                      if (ctx.mounted && err != null) {
                        setDialogState(() => loading = false);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              err ?? 'Account created successfully',
                            ),
                            backgroundColor: err != null
                                ? Colors.red
                                : Colors.green,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Confirm & Create'),
            ),
          ],
        ),
      ),
    );
    confirmPassCtrl.dispose();
  }

  void _showChangeRoleDialog(
    String userId,
    String currentRole,
    String userName,
  ) {
    String selectedRole = currentRole;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Change Role — $userName'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: const InputDecoration(
              labelText: 'New Role',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'staff', child: Text('Barangay Staff')),
              DropdownMenuItem(
                value: 'officer',
                child: Text('Committee Officer'),
              ),
              DropdownMenuItem(
                value: 'captain',
                child: Text('Barangay Captain'),
              ),
            ],
            onChanged: (v) => setDialogState(() => selectedRole = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedRole == currentRole
                  ? null
                  : () async {
                      final auth = context.read<AuthService>();
                      final err = await auth.updateUserRole(
                        userId,
                        selectedRole,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              err ?? 'Role updated to $selectedRole',
                            ),
                            backgroundColor: err != null
                                ? Colors.red
                                : Colors.green,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update Role'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(
    String userId,
    String userName,
    String email,
  ) async {
    final passwordController = TextEditingController();
    String? passwordError;
    var deleting = false;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permanently Delete Account?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete $userName ($email) from Firebase Authentication '
                  'and the user database? This cannot be undone.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  enabled: !deleting,
                  decoration: InputDecoration(
                    labelText: 'Your captain password',
                    border: const OutlineInputBorder(),
                    errorText: passwordError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: deleting
                  ? null
                  : () async {
                      final password = passwordController.text;
                      if (password.isEmpty) {
                        setDialogState(
                          () => passwordError = 'Enter your password.',
                        );
                        return;
                      }
                      setDialogState(() {
                        deleting = true;
                        passwordError = null;
                      });
                      final auth = context.read<AuthService>();
                      final confirmationError = await auth
                          .confirmCurrentUserPassword(password);
                      if (confirmationError != null) {
                        setDialogState(() {
                          deleting = false;
                          passwordError = confirmationError.replaceAll(
                            'No account was created.',
                            'The account was not deleted.',
                          );
                        });
                        return;
                      }
                      final deletionError = await auth.deleteManagedAccount(
                        userId,
                      );
                      if (deletionError != null) {
                        setDialogState(() {
                          deleting = false;
                          passwordError = deletionError;
                        });
                        return;
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Delete Account'),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();
    if (deleted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$userName was permanently deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _sendReset(String email, String userName) async {
    final auth = context.read<AuthService>();
    final err = await auth.sendPasswordReset(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'Password reset sent to $userName'),
          backgroundColor: err != null ? Colors.red : Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final currentUser = auth.currentUserModel;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create and manage barangay staff accounts',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search by name or email',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showCreateAccountDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: context.read<AuthService>().getStaffAccounts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  var users = docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return {
                      'uid': doc.id,
                      'name': data['name'] ?? '',
                      'email': data['email'] ?? '',
                      'mobile': data['mobile'] ?? '',
                      'role': data['role'] ?? 'staff',
                      'isActive': data['isActive'] != false,
                    };
                  }).toList();

                  if (_searchQuery.isNotEmpty) {
                    users = users
                        .where(
                          (u) =>
                              u['name'].toString().toLowerCase().contains(
                                _searchQuery,
                              ) ||
                              u['email'].toString().toLowerCase().contains(
                                _searchQuery,
                              ),
                        )
                        .toList();
                  }

                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        'No staff accounts found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = users[index];
                      final isSelf = u['uid'] == currentUser?.uid;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kNavyLight,
                          child: Text(
                            u['name'].toString().isNotEmpty
                                ? u['name']
                                      .toString()
                                      .split(' ')
                                      .map((w) => w[0])
                                      .take(2)
                                      .join()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          u['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u['email'].toString()),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                StatusBadge(status: u['role'].toString()),
                                const SizedBox(width: 8),
                                StatusBadge(
                                  status: u['isActive'] == true
                                      ? 'active'
                                      : 'inactive',
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: isSelf
                            ? const Chip(
                                label: Text(
                                  'You',
                                  style: TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Colors.blueGrey,
                                labelStyle: TextStyle(color: Colors.white),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'role':
                                          _showChangeRoleDialog(
                                            u['uid'],
                                            u['role'],
                                            u['name'],
                                          );
                                          break;
                                        case 'delete':
                                          _showDeleteAccountDialog(
                                            u['uid'],
                                            u['name'],
                                            u['email'],
                                          );
                                          break;
                                        case 'reset':
                                          _sendReset(u['email'], u['name']);
                                          break;
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'role',
                                        child: Text('Change Role'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete Account',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'reset',
                                        child: Text('Send Password Reset'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
