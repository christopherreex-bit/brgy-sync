import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../utils/account_validators.dart';
import '../utils/constants.dart';
import '../models/user_model.dart';
import '../services/staff_leave_service.dart';

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
        if (user.isStaff) ...[
          const SizedBox(height: 20),
          _StaffLeaveCard(user: user),
        ],
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
                  'Official service request and audit records are retained.',
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

class _LeaveReason {
  final String code;
  final String label;

  const _LeaveReason(this.code, this.label);
}

const _leaveReasons = <_LeaveReason>[
  _LeaveReason('sick_medical', 'Sick or medical leave'),
  _LeaveReason('vacation_personal', 'Vacation or personal leave'),
  _LeaveReason('family_emergency', 'Family emergency'),
  _LeaveReason('training_official', 'Training or official activity'),
  _LeaveReason('parental', 'Maternity or paternity leave'),
  _LeaveReason('other', 'Other'),
];

class _StaffLeaveCard extends StatefulWidget {
  final UserModel user;

  const _StaffLeaveCard({required this.user});

  @override
  State<_StaffLeaveCard> createState() => _StaffLeaveCardState();
}

class _StaffLeaveCardState extends State<_StaffLeaveCard> {
  bool _busy = false;
  final _service = StaffLeaveService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchOwnLeaves(widget.user.uid),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final leaves = snapshot.data?.docs.toList() ?? const [];
        leaves.sort((a, b) {
          final aDate = (a.data()['filedAt'] as Timestamp?)?.toDate();
          final bDate = (b.data()['filedAt'] as Timestamp?)?.toDate();
          return (bDate ?? DateTime(1970)).compareTo(
            aDate ?? DateTime(1970),
          );
        });
        QueryDocumentSnapshot<Map<String, dynamic>>? activeLeave;
        for (final leave in leaves) {
          final endsAt = (leave.data()['endsAt'] as Timestamp?)?.toDate();
          if (endsAt != null && endsAt.isAfter(now)) {
            activeLeave = leave;
            break;
          }
        }
        final activeData = activeLeave?.data();
        final activeUntil = (activeData?['endsAt'] as Timestamp?)?.toDate();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff Leave',
                          style: TextStyle(
                            color: kNavy,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Open assignments are redistributed fairly among available staff.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || activeUntil != null ? null : _fileLeave,
                    style: FilledButton.styleFrom(backgroundColor: kNavy),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: Text(activeUntil == null ? 'File Leave' : 'On Leave'),
                  ),
                ],
              ),
              if (activeUntil != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'On leave until ${_dateTimeLabel(activeUntil)} · '
                    '${activeData?['reasonLabel'] ?? 'Staff leave'} · '
                    '${activeData?['redistributedCaseCount'] ?? 0} open assignment(s) redistributed',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
              if (leaves.isNotEmpty) ...[
                const SizedBox(height: 14),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text(
                    'Leave history',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  children: leaves.take(5).map((leave) {
                    final data = leave.data();
                    final starts = (data['startsAt'] as Timestamp?)?.toDate();
                    final ends = (data['endsAt'] as Timestamp?)?.toDate();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_note_outlined),
                      title: Text((data['reasonLabel'] ?? 'Staff leave').toString()),
                      subtitle: Text(
                        '${starts == null ? 'Filed' : _dateTimeLabel(starts)} – '
                        '${ends == null ? 'No end recorded' : _dateTimeLabel(ends)}'
                        '${(data['note'] ?? '').toString().trim().isEmpty ? '' : '\n${data['note']}'}',
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _fileLeave() async {
    var selectedReason = _leaveReasons.first;
    var selectedDate = DateTime.now().add(const Duration(days: 1));
    final timeController = TextEditingController(text: '17:00');
    final noteController = TextEditingController();
    String? error;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('File Staff Leave'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Leave starts immediately. Open service requests assigned to you will be redistributed using the same SLA-balanced workload rules.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<_LeaveReason>(
                    initialValue: selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for leave *',
                      border: OutlineInputBorder(),
                    ),
                    items: _leaveReasons
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(reason.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => selectedReason = value ?? selectedReason,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(_dateLabel(selectedDate)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: timeController,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: 'End time (HH:MM)',
                            hintText: '17:00',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: selectedReason.code == 'other'
                          ? 'Supporting note *'
                          : 'Note (optional)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kNavy),
              onPressed: () {
                final match = RegExp(
                  r'^([01]?\d|2[0-3]):([0-5]\d)$',
                ).firstMatch(timeController.text.trim());
                if (match == null) {
                  setDialogState(
                    () => error = 'Enter time in 24-hour HH:MM format.',
                  );
                  return;
                }
                final endsAt = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  int.parse(match.group(1)!),
                  int.parse(match.group(2)!),
                );
                if (!endsAt.isAfter(DateTime.now())) {
                  setDialogState(
                    () => error = 'Leave must end in the future.',
                  );
                  return;
                }
                if (selectedReason.code == 'other' &&
                    noteController.text.trim().isEmpty) {
                  setDialogState(
                    () => error = 'Enter a note for the selected reason.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Confirm Leave'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      timeController.dispose();
      noteController.dispose();
      return;
    }
    final match = RegExp(
      r'^([01]?\d|2[0-3]):([0-5]\d)$',
    ).firstMatch(timeController.text.trim())!;
    final endsAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    final note = noteController.text.trim();
    timeController.dispose();
    noteController.dispose();
    setState(() => _busy = true);
    try {
      final redistributed = await _service.fileLeave(
        staff: widget.user,
        endsAt: endsAt,
        reasonCode: selectedReason.code,
        reasonLabel: selectedReason.label,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Leave filed. $redistributed open assignment(s) redistributed.',
          ),
        ),
      );
    } catch (caught) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(caught.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _dateLabel(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  static String _dateTimeLabel(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${_dateLabel(value)} $hour:${value.minute.toString().padLeft(2, '0')} $period';
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
