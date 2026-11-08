import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/captain_delegation_service.dart';
import '../../utils/account_validators.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _DelegationReasonOption {
  final String code;
  final String label;
  final bool requiresDetails;
  final bool isSensitive;

  const _DelegationReasonOption({
    required this.code,
    required this.label,
    this.requiresDetails = false,
    this.isSensitive = false,
  });
}

const _delegationAssignmentReasons = <_DelegationReasonOption>[
  _DelegationReasonOption(
    code: 'official_leave',
    label: 'Official leave or vacation',
  ),
  _DelegationReasonOption(
    code: 'medical_leave',
    label: 'Medical leave or illness',
  ),
  _DelegationReasonOption(
    code: 'official_travel',
    label: 'Official travel, meeting, or training',
  ),
  _DelegationReasonOption(
    code: 'emergency_absence',
    label: 'Emergency or unexpected absence',
    requiresDetails: true,
  ),
  _DelegationReasonOption(
    code: 'temporary_unavailability',
    label: 'Temporary unavailability',
  ),
  _DelegationReasonOption(
    code: 'conflict_of_interest',
    label: 'Conflict of interest for specific duties',
    requiresDetails: true,
  ),
  _DelegationReasonOption(
    code: 'operational_continuity',
    label: 'Operational continuity or urgent workload',
  ),
  _DelegationReasonOption(code: 'other', label: 'Other', requiresDetails: true),
];

const _delegationRevocationReasons = <_DelegationReasonOption>[
  _DelegationReasonOption(
    code: 'captain_returned_early',
    label: 'Captain resumed duty early',
  ),
  _DelegationReasonOption(
    code: 'no_longer_required',
    label: 'Delegation no longer required',
  ),
  _DelegationReasonOption(
    code: 'schedule_changed',
    label: 'Schedule or availability changed',
  ),
  _DelegationReasonOption(
    code: 'delegate_requested',
    label: 'Acting captain requested revocation',
  ),
  _DelegationReasonOption(
    code: 'operational_reassignment',
    label: 'Operational reassignment',
  ),
  _DelegationReasonOption(
    code: 'policy_concern',
    label: 'Policy or procedural concern',
  ),
  _DelegationReasonOption(
    code: 'suspected_misuse',
    label: 'Suspected misuse of authority',
    requiresDetails: true,
    isSensitive: true,
  ),
  _DelegationReasonOption(
    code: 'security_concern',
    label: 'Security concern',
    requiresDetails: true,
    isSensitive: true,
  ),
  _DelegationReasonOption(code: 'other', label: 'Other', requiresDetails: true),
];

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _delegationService = CaptainDelegationService();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCreateAccountDialog() async {
    Set<String> existingEmails;
    Set<String> existingMobileNumbers;
    final authService = context.read<AuthService>();
    try {
      existingEmails = await authService.getExistingAccountEmails();
      existingMobileNumbers = await authService.getExistingMobileNumbers();
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

    final firstNameCtrl = TextEditingController();
    final middleNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
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
                    controller: firstNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: middleNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Middle Initial (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    maxLength: 1,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Last Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    decoration: InputDecoration(
                      labelText: 'Email *',
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
                      labelText: 'Mobile (09XXXXXXXXX) *',
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
                      () => mobileError = validateUniqueMobileNumber(
                        value,
                        existingMobileNumbers,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password *',
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
                      DropdownMenuItem(
                        value: 'treasurer',
                        child: Text('Barangay Treasurer'),
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
                final nextMobileError = validateUniqueMobileNumber(
                  mobileCtrl.text,
                  existingMobileNumbers,
                );
                final nextPasswordError = validateStaffPassword(passCtrl.text);
                setDialogState(() {
                  emailError = nextEmailError;
                  mobileError = nextMobileError;
                  passwordError = nextPasswordError;
                });
                if (firstNameCtrl.text.trim().isEmpty ||
                    lastNameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('First name and last name are required.'),
                    ),
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
        firstName: firstNameCtrl.text.trim(),
        middleName: middleNameCtrl.text.trim(),
        lastName: lastNameCtrl.text.trim(),
        email: emailCtrl.text.trim().toLowerCase(),
        mobile: mobileCtrl.text.trim(),
        password: passCtrl.text,
        role: selectedRole,
      );
    }
    firstNameCtrl.dispose();
    middleNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    mobileCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showConfirmPasswordDialog({
    required String firstName,
    required String middleName,
    required String lastName,
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
                        firstName: firstName,
                        middleName: middleName,
                        lastName: lastName,
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
              DropdownMenuItem(
                value: 'treasurer',
                child: Text('Barangay Treasurer'),
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

  Widget _delegationPanel(UserModel captain) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _delegationService.watchCurrent(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final expiry = (data?['expiresAt'] as Timestamp?)?.toDate();
        final active =
            data?['active'] == true &&
            expiry != null &&
            expiry.isAfter(DateTime.now());
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? Colors.orange.shade50 : Colors.blueGrey.shade50,
            border: Border.all(
              color: active ? Colors.orange.shade200 : Colors.blueGrey.shade100,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                active ? Icons.admin_panel_settings : Icons.shield_outlined,
                color: active ? Colors.orange.shade800 : kNavy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active
                          ? '${data?['delegateName']} is Acting Barangay Captain'
                          : 'Temporary Acting Captain',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? 'Access expires ${MaterialLocalizations.of(context).formatFullDate(expiry)} at ${TimeOfDay.fromDateTime(expiry).format(context)}. ${data?['reason'] ?? ''}'
                          : 'Temporarily grant captain-level system access to one active staff member or officer.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (active)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showChangeDurationDialog(captain, expiry),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('Change duration'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _revokeDelegation(captain),
                      icon: const Icon(Icons.block),
                      label: const Text('Revoke'),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: () => _showDelegationDialog(captain),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Assign acting captain'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDelegationDialog(UserModel captain) async {
    final snapshot = await context.read<AuthService>().getStaffAccounts().first;
    final candidates = snapshot.docs.where((document) {
      final data = document.data() as Map<String, dynamic>;
      return data['isActive'] != false &&
          ['staff', 'officer'].contains(data['role']);
    }).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active staff or officer is available.'),
        ),
      );
      return;
    }
    String selectedUid = candidates.first.id;
    var selectedExpiry = DateTime.now().add(const Duration(days: 1));
    String? selectedReasonCode;
    final reasonDetails = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedReason = selectedReasonCode == null
              ? null
              : _delegationAssignmentReasons.firstWhere(
                  (reason) => reason.code == selectedReasonCode,
                );
          final detailsRequired = selectedReason?.requiresDetails ?? false;
          final canSubmit =
              selectedExpiry.isAfter(DateTime.now()) &&
              selectedReason != null &&
              (!detailsRequired || reasonDetails.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Assign Acting Barangay Captain'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This grants the selected person captain-level system access until the stated expiry. Their permanent role will not change.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUid,
                    decoration: const InputDecoration(
                      labelText: 'Staff member or officer',
                      border: OutlineInputBorder(),
                    ),
                    items: candidates.map((document) {
                      final data = document.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: document.id,
                        child: Text('${data['name']} (${data['role']})'),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedUid = value!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(selectedExpiry),
                          ),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedExpiry,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              helpText: 'Select access expiry date',
                            );
                            if (date != null) {
                              final candidate = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                selectedExpiry.hour,
                                selectedExpiry.minute,
                              );
                              if (!candidate.isAfter(DateTime.now())) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'That date and time has already passed. Select a future expiry.',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              setDialogState(() {
                                selectedExpiry = candidate;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            TimeOfDay.fromDateTime(
                              selectedExpiry,
                            ).format(context),
                          ),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.fromDateTime(
                                selectedExpiry,
                              ),
                              initialEntryMode: TimePickerEntryMode.inputOnly,
                              helpText: 'Select access expiry time',
                              hourLabelText: 'Hour',
                              minuteLabelText: 'Minute',
                              errorInvalidText: 'Enter a valid time.',
                            );
                            if (time != null) {
                              final candidate = DateTime(
                                selectedExpiry.year,
                                selectedExpiry.month,
                                selectedExpiry.day,
                                time.hour,
                                time.minute,
                              );
                              if (!candidate.isAfter(DateTime.now())) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'That ending time has already passed. Select a future time.',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              setDialogState(() {
                                selectedExpiry = candidate;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Access starts immediately and automatically expires at the selected date and time.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReasonCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason for temporary assignment *',
                      border: OutlineInputBorder(),
                    ),
                    items: _delegationAssignmentReasons
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason.code,
                            child: Text(reason.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedReasonCode = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonDetails,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: detailsRequired
                          ? 'Supporting details *'
                          : 'Additional details (optional)',
                      hintText: detailsRequired
                          ? 'Briefly explain why temporary authority is needed.'
                          : 'Add dates, duties, or other useful context.',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
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
                onPressed: canSubmit
                    ? () {
                        if (!selectedExpiry.isAfter(DateTime.now())) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Select an expiry date and time in the future.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(dialogContext, true);
                      }
                    : null,
                child: const Text('Grant temporary access'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) {
      reasonDetails.dispose();
      return;
    }
    final selectedReason = _delegationAssignmentReasons.firstWhere(
      (reason) => reason.code == selectedReasonCode,
    );
    final selected = candidates.firstWhere((doc) => doc.id == selectedUid);
    final data = selected.data() as Map<String, dynamic>;
    try {
      await _delegationService.grant(
        captain: captain,
        delegateUid: selectedUid,
        delegateName: (data['name'] ?? '').toString(),
        delegateRole: (data['role'] ?? '').toString(),
        expiresAt: selectedExpiry,
        reasonCode: selectedReason.code,
        reasonLabel: selectedReason.label,
        reasonDetails: reasonDetails.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${data['name']} now has temporary captain access.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      reasonDetails.dispose();
    }
  }

  Future<void> _revokeDelegation(UserModel captain) async {
    String? selectedReasonCode;
    final detailsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedReason = selectedReasonCode == null
              ? null
              : _delegationRevocationReasons.firstWhere(
                  (reason) => reason.code == selectedReasonCode,
                );
          final detailsRequired = selectedReason?.requiresDetails ?? false;
          final canSubmit =
              selectedReason != null &&
              (!detailsRequired || detailsController.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Revoke temporary captain access?'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Access ends immediately. Select the operational reason so the revocation is clear in Delegation History.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReasonCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason for revocation *',
                      border: OutlineInputBorder(),
                    ),
                    items: _delegationRevocationReasons
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason.code,
                            child: Text(reason.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedReasonCode = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: detailsRequired
                          ? 'Supporting details *'
                          : 'Additional details (optional)',
                      hintText: detailsRequired
                          ? 'Provide a factual explanation for this revocation.'
                          : 'Add context for the delegation record.',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (selectedReason?.isSensitive ?? false) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'This records why access was removed; it does not replace a separate investigation or disciplinary process.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: canSubmit
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                icon: const Icon(Icons.block),
                label: const Text('Revoke access'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || selectedReasonCode == null) {
      detailsController.dispose();
      return;
    }
    final selectedReason = _delegationRevocationReasons.firstWhere(
      (reason) => reason.code == selectedReasonCode,
    );
    try {
      await _delegationService.revoke(
        captain: captain,
        reasonCode: selectedReason.code,
        reasonLabel: selectedReason.label,
        reasonDetails: detailsController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary captain access revoked.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      detailsController.dispose();
    }
  }

  Future<void> _showChangeDurationDialog(
    UserModel captain,
    DateTime currentExpiry,
  ) async {
    var selectedExpiry = currentExpiry;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change temporary access duration'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose a new exact expiry. Access remains active only until this date and time.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(selectedExpiry),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedExpiry.isAfter(DateTime.now())
                                ? selectedExpiry
                                : DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            helpText: 'Select new expiry date',
                          );
                          if (date == null) return;
                          final candidate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            selectedExpiry.hour,
                            selectedExpiry.minute,
                          );
                          if (!candidate.isAfter(DateTime.now())) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'That date and time has already passed.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          setDialogState(() => selectedExpiry = candidate);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          TimeOfDay.fromDateTime(
                            selectedExpiry,
                          ).format(context),
                        ),
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.fromDateTime(selectedExpiry),
                            initialEntryMode: TimePickerEntryMode.inputOnly,
                            helpText: 'Enter new expiry time',
                            hourLabelText: 'Hour',
                            minuteLabelText: 'Minute',
                            errorInvalidText: 'Enter a valid time.',
                          );
                          if (time == null) return;
                          final candidate = DateTime(
                            selectedExpiry.year,
                            selectedExpiry.month,
                            selectedExpiry.day,
                            time.hour,
                            time.minute,
                          );
                          if (!candidate.isAfter(DateTime.now())) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'That ending time has already passed.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          setDialogState(() => selectedExpiry = candidate);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason for changing duration',
                    border: OutlineInputBorder(),
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
              onPressed:
                  selectedExpiry.isAfter(DateTime.now()) &&
                      reason.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Save new duration'),
            ),
          ],
        ),
      ),
    );
    final changeReason = reason.text;
    reason.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _delegationService.changeExpiry(
        captain: captain,
        expiresAt: selectedExpiry,
        reason: changeReason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary access duration updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final currentUser = auth.currentUserModel;

    if (currentUser == null || !currentUser.isPermanentCaptain) {
      return const Center(
        child: Text(
          'Account Management is available only to the permanent Barangay Captain.',
        ),
      );
    }

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
            if (currentUser.isPermanentCaptain) ...[
              _delegationPanel(currentUser),
              const SizedBox(height: 16),
            ],
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
                      final isSelf = u['uid'] == currentUser.uid;
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
