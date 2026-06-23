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

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthService>();
    final result = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (mounted) {
      setState(() { _loading = false; _error = result; });
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

  void _mockLogin(String role) {
    context.read<AuthService>().mockLogin(role);
    if (mounted) {
      final target = role == 'resident' ? '/resident' : '/dashboard';
      context.go(target);
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

                // ─── Demo Login Buttons ─────────────────────────
                const Text('Demo Login (No Firebase required)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kNavy)),
                const SizedBox(height: 12),
                _demoButton('Login as Barangay Captain', 'captain', Icons.admin_panel_settings),
                const SizedBox(height: 8),
                _demoButton('Login as Committee Officer', 'officer', Icons.person_outline),
                const SizedBox(height: 8),
                _demoButton('Login as Barangay Staff', 'staff', Icons.badge),
                const SizedBox(height: 8),
                _demoButton('Login as Resident', 'resident', Icons.home),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // ─── Real Login Form ───────────────────────────
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

  Widget _demoButton(String label, String role, IconData icon) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () => _mockLogin(role),
        icon: Icon(icon, size: 18, color: kNavy),
        label: Text(label, style: const TextStyle(color: kNavy, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kNavy),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
