import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../utils/account_validators.dart';
import '../../utils/constants.dart';
import '../resident/submit_request_screen.dart';

class WalkInIntakeScreen extends StatefulWidget {
  const WalkInIntakeScreen({super.key});

  @override
  State<WalkInIntakeScreen> createState() => _WalkInIntakeScreenState();
}

class _WalkInIntakeScreenState extends State<WalkInIntakeScreen> {
  final _search = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  bool _working = false;
  UserModel? _resident;
  List<UserModel> _searchResults = const [];
  String? _error;
  String? _emailError;
  String? _mobileError;
  String? _temporaryPassword;
  Timer? _emailValidationTimer;
  Timer? _mobileValidationTimer;

  @override
  void dispose() {
    _emailValidationTimer?.cancel();
    _mobileValidationTimer?.cancel();
    _search.dispose();
    _email.dispose();
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  void _validateEmailWhileTyping(String value) {
    _emailValidationTimer?.cancel();
    final formatError = validateAccountEmail(value);
    setState(() => _emailError = formatError);
    if (formatError != null) return;
    _emailValidationTimer = Timer(const Duration(milliseconds: 400), () async {
      final checkedValue = value.trim().toLowerCase();
      final exists = await context.read<AuthService>().emailAddressExists(
        checkedValue,
      );
      if (!mounted || _email.text.trim().toLowerCase() != checkedValue) return;
      setState(
        () => _emailError = exists
            ? 'This email address is already in use.'
            : null,
      );
    });
  }

  void _validateMobileWhileTyping(String value) {
    _mobileValidationTimer?.cancel();
    final formatError = validatePhilippineMobile(value);
    setState(() => _mobileError = formatError);
    if (formatError != null) return;
    _mobileValidationTimer = Timer(const Duration(milliseconds: 400), () async {
      final checkedValue = value.trim();
      final exists = await context.read<AuthService>().mobileNumberExists(
        checkedValue,
      );
      if (!mounted || _mobile.text.trim() != checkedValue) return;
      setState(
        () => _mobileError = exists
            ? 'This mobile number is already in use.'
            : null,
      );
    });
  }

  String _generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _findResident() async {
    final term = _search.text.trim();
    if (term.length < 2) {
      setState(() => _error = 'Enter at least 2 characters to search.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _temporaryPassword = null;
      _searchResults = const [];
    });
    final residents = await context.read<AuthService>().searchResidents(term);
    if (!mounted) return;
    setState(() {
      _working = false;
      _searchResults = residents;
      if (residents.isEmpty) {
        _error =
            'No matching resident account was found. Enter the details below to create one.';
        if (validateAccountEmail(term) == null) {
          _email.text = term.toLowerCase();
        }
      }
    });
  }

  Future<void> _createResident() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Resident name is required.');
      return;
    }
    final emailFormatError = validateAccountEmail(_email.text);
    final mobileFormatError = validatePhilippineMobile(_mobile.text);
    if (emailFormatError != null || mobileFormatError != null) {
      setState(() {
        _emailError = emailFormatError;
        _mobileError = mobileFormatError;
      });
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final identifierChecks = await Future.wait([
      context.read<AuthService>().emailAddressExists(_email.text),
      context.read<AuthService>().mobileNumberExists(_mobile.text),
    ]);
    if (!mounted) return;
    final emailExists = identifierChecks[0];
    final mobileExists = identifierChecks[1];
    setState(() {
      _emailError = emailExists
          ? 'This email address is already in use.'
          : null;
      _mobileError = mobileExists
          ? 'This mobile number is already in use.'
          : null;
    });
    if (emailExists || mobileExists) {
      setState(() => _working = false);
      return;
    }
    final password = _generateTemporaryPassword();
    final result = await context.read<AuthService>().createWalkInResident(
      name: name,
      email: _email.text,
      mobile: _mobile.text,
      temporaryPassword: password,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _resident = result.resident;
      _error = result.error;
      _temporaryPassword = result.resident == null ? null : password;
    });
  }

  void _startOver() {
    setState(() {
      _resident = null;
      _error = null;
      _temporaryPassword = null;
      _emailError = null;
      _mobileError = null;
      _searchResults = const [];
      _search.clear();
      _email.clear();
      _name.clear();
      _mobile.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resident != null) {
      return Column(
        children: [
          _residentBanner(),
          Expanded(
            child: SubmitRequestScreen(
              residentOverride: _resident,
              onExit: _startOver,
            ),
          ),
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Walk-in Intake',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: kNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Find the resident’s account first. If none exists, create one and give the resident the temporary login details.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Find an existing resident',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            decoration: const InputDecoration(
                              labelText: 'Name, email, or mobile number *',
                              hintText: 'Juan Dela Cruz or 09XXXXXXXXX',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) =>
                                _working ? null : _findResident(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _working ? null : _findResident,
                          icon: const Icon(Icons.search),
                          label: const Text('Find account'),
                          style: FilledButton.styleFrom(
                            backgroundColor: kNavy,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${_searchResults.length} matching resident${_searchResults.length == 1 ? '' : 's'} found. Select the correct account:',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ..._searchResults.map(
                        (resident) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(resident.name),
                            subtitle: Text(
                              '${resident.email} · ${resident.mobile}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() {
                              _resident = resident;
                              _error = null;
                              _temporaryPassword = null;
                            }),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    const Divider(),
                    const SizedBox(height: 18),
                    const Text(
                      '2. Or create a resident account',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A secure 10-character temporary password will be generated. It is shown only once and is not saved in Firestore.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Login email *',
                        helperText:
                            'The resident uses this email with the temporary password.',
                        errorText: _emailError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _validateEmailWhileTyping,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Full name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Mobile number *',
                        hintText: '09XXXXXXXXX',
                        errorText: _mobileError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _validateMobileWhileTyping,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _working ? null : _createResident,
                        icon: _working
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: const Text('Create resident & continue'),
                        style: FilledButton.styleFrom(backgroundColor: kNavy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _residentBanner() {
    return Material(
      color: _temporaryPassword == null
          ? Colors.green.shade50
          : Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(
              _temporaryPassword == null
                  ? Icons.verified_user_outlined
                  : Icons.key,
              color: kNavy,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_resident!.name} · ${_resident!.email}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_temporaryPassword == null)
                    const Text(
                      'Existing resident account selected.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    Text(
                      'Temporary password: $_temporaryPassword — give this to the resident now. A password change is required at first login.',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            if (_temporaryPassword != null)
              IconButton(
                tooltip: 'Copy temporary password',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _temporaryPassword!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Temporary password copied.')),
                  );
                },
                icon: const Icon(Icons.copy),
              ),
            TextButton.icon(
              onPressed: _startOver,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Change resident'),
            ),
          ],
        ),
      ),
    );
  }
}
