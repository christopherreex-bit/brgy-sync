import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Maps raw Firebase/auth error strings to friendly, user-facing messages.
  /// Falls back to the original string when nothing specific matches.
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('user-not-found') ||
        lower.contains('wrong-password') ||
        lower.contains('invalid-credential') ||
        lower.contains('invalid login')) {
      return 'Wrong email or password. Please try again.';
    }
    if (lower.contains('email is badly formatted') ||
        lower.contains('invalid email') ||
        lower.contains('badly formatted')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') || lower.contains('request-failed')) {
      return 'Network error. Check your connection and try again.';
    }
    if (lower.contains('user-disabled')) {
      return 'This account has been disabled. Contact the barangay office.';
    }
    return raw;
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    // Client-side validation before hitting Firebase.
    if (email.isEmpty && password.isEmpty) {
      setState(() { _error = 'Please enter your email and password.'; });
      return;
    }
    if (email.isEmpty) {
      setState(() { _error = 'Please enter your email.'; });
      return;
    }
    if (password.isEmpty) {
      setState(() { _error = 'Please enter your password.'; });
      return;
    }

    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthService>();
    final result = await auth.login(email: email, password: password);
    if (mounted) {
      setState(() { _loading = false; _error = result == null ? null : _friendlyError(result); });
      if (result == null) {
        // Wait for Firestore user data to load, then route by role
        await auth.userDataLoaded;
        if (!mounted) return;
        final user = auth.currentUserModel;
        if (user != null && user.role == 'resident') {
          context.go('/resident');
        } else {
          context.go('/dashboard');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_city, size: 48, color: kNavy),
                const SizedBox(height: 12),
                const Text('BrgySync',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: kNavy)),
                const SizedBox(height: 4),
                const Text('Brgy. Calzada-Tipas, Taguig City',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),

                // ─── Login Form ─────────────────────────────────
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNavy,
                      foregroundColor: Colors.white,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Log In', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
