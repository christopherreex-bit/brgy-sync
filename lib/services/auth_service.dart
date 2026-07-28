import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../utils/account_validators.dart';

class AuthService extends ChangeNotifier {
  static const String _accountAdminUrl = String.fromEnvironment(
    'ACCOUNT_ADMIN_URL',
    defaultValue: 'https://brgy-sync-create-user.jasonleyva723.workers.dev',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get firebaseUser => _auth.currentUser;
  bool get isLoggedIn => _currentUserModel != null || _auth.currentUser != null;

  UserModel? _currentUserModel;
  UserModel? get currentUserModel => _currentUserModel;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user != null) {
      await _loadUserData(user.uid);
    } else {
      _currentUserModel = null;
    }
    notifyListeners();
  }

  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUserModel = UserModel.fromMap(doc.data()!, uid);
      }
    } catch (e) {
      // Firestore read failed (e.g. permission-denied, network error).
      // Don't crash — the auth state is still valid, just without role data.
      debugPrint('AuthService: failed to load user data for $uid: $e');
    }
  }

  Future<String?> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null) {
        final user = UserModel(
          uid: cred.user!.uid,
          name: name,
          mobile: mobile,
          email: email,
          role: 'resident',
          createdAt: DateTime.now(),
        );
        await _firestore
            .collection('users')
            .doc(cred.user!.uid)
            .set(user.toMap());
        _currentUserModel = user;
        notifyListeners();
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Completes when the current user's Firestore data has been loaded.
  /// Useful for waiting after login before routing by role.
  Future<void>? _userDataFuture;

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null) {
        _userDataFuture = _loadUserData(cred.user!.uid);
        await _userDataFuture;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Returns a Future that completes when user data is loaded for the
  /// currently authenticated user. Returns null if no user is logged in.
  Future<void>? get userDataLoaded => _userDataFuture;

  Future<void> logout() async {
    await _auth.signOut();
    _currentUserModel = null;
    notifyListeners();
  }

  // ─── Staff Account Management (Phase 12) ───────────────────────

  /// Reauthenticates the currently signed-in manager before a sensitive
  /// account-management action. No account is created if this fails.
  Future<String?> confirmCurrentUserPassword(String password) async {
    final currentUser = _auth.currentUser;
    final email = currentUser?.email;
    if (currentUser == null || email == null || email.isEmpty) {
      return 'Your session has expired. Please log in again.';
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-login-credentials') {
        return 'Incorrect password. No account was created.';
      }
      return e.message ?? 'Could not confirm your identity.';
    } catch (e) {
      return e.toString();
    }
  }

  /// Creates a new staff/officer/captain account (NOT resident).
  /// Uses an isolated Firebase Auth instance so the manager's primary browser
  /// session is never replaced by the newly created account.
  Future<String?> createStaffAccount({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String role,
  }) async {
    final emailError = validateAccountEmail(email);
    if (emailError != null) return emailError;
    final mobileError = validatePhilippineMobile(mobile);
    if (mobileError != null) return mobileError;
    final passwordError = validateStaffPassword(password);
    if (passwordError != null) return passwordError;

    FirebaseAuth? secondaryAuth;
    User? createdUser;
    try {
      const secondaryAppName = 'staff-account-creation';
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app(secondaryAppName);
      } on FirebaseException {
        secondaryApp = await Firebase.initializeApp(
          name: secondaryAppName,
          options: Firebase.app().options,
        );
      }
      secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      await secondaryAuth.signOut();

      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      createdUser = cred.user;
      if (createdUser == null) {
        return 'Failed to create user.';
      }

      final user = UserModel(
        uid: createdUser.uid,
        name: name,
        mobile: mobile,
        email: email,
        role: role,
        isActive: true,
        createdAt: DateTime.now(),
      );
      await _firestore
          .collection('users')
          .doc(createdUser.uid)
          .set(user.toMap());
      return null;
    } on FirebaseAuthException catch (e) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }
      return e.message;
    } catch (e) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }
      return e.toString();
    } finally {
      try {
        await secondaryAuth?.signOut();
      } catch (_) {}
    }
  }

  /// Updates a user's role in Firestore.
  Future<String?> updateUserRole(String userId, String newRole) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'role': newRole,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Deactivates a user account (soft delete).
  Future<String?> deactivateAccount(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isActive': false,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteManagedAccount(String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return 'Your session has expired. Please log in again.';
    }
    if (_currentUserModel?.isCaptain != true) {
      return 'Only the Barangay Captain can delete managed accounts.';
    }
    if (currentUser.uid == userId) {
      return 'Use User Management to delete your own account.';
    }
    if (_accountAdminUrl.isEmpty) {
      return 'Account deletion backend is not configured. '
          'Build with ACCOUNT_ADMIN_URL.';
    }

    Object? lastConnectionError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final token = await currentUser.getIdToken(attempt == 1);
        final response = await http
            .delete(
              Uri.parse(_accountAdminUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'uid': userId}),
            )
            .timeout(const Duration(seconds: 20));
        Map<String, dynamic> body = {};
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) body = decoded;
          } catch (_) {
            body = {
              'error':
                  'Account service returned an invalid response '
                  '(HTTP ${response.statusCode}).',
            };
          }
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return null;
        }

        // A previous request may have completed on the server even if its
        // response was lost. In that case, the missing profile confirms the
        // requested deletion completed and makes retries idempotent.
        if (!await _managedAccountProfileExists(userId)) return null;

        return (body['error'] ?? 'Could not delete the account.').toString();
      } catch (error) {
        lastConnectionError = error;
        if (!await _managedAccountProfileExists(userId)) return null;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    return 'The account service could not be reached after 3 attempts. '
        'Please check your connection and try again. ($lastConnectionError)';
  }

  Future<bool> _managedAccountProfileExists(String userId) async {
    try {
      return (await _firestore.collection('users').doc(userId).get()).exists;
    } catch (_) {
      // If Firestore itself is temporarily unavailable, do not assume that
      // deletion succeeded.
      return true;
    }
  }

  /// Reactivates a user account.
  Future<String?> activateAccount(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isActive': true,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Sends a password reset email.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final passwordError = validatePasswordChange(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (passwordError != null) return passwordError;

    final reauthenticationError = await confirmCurrentUserPassword(
      currentPassword,
    );
    if (reauthenticationError != null) {
      return reauthenticationError.replaceAll(
        'No account was created.',
        'Your password was not changed.',
      );
    }

    try {
      await _auth.currentUser!.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Could not change your password.';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteOwnAccount({required String currentPassword}) async {
    final user = _auth.currentUser;
    final profile = _currentUserModel;
    if (user == null || profile == null) {
      return 'Your session has expired. Please log in again.';
    }

    final reauthenticationError = await confirmCurrentUserPassword(
      currentPassword,
    );
    if (reauthenticationError != null) {
      return reauthenticationError.replaceAll(
        'No account was created.',
        'Your account was not deleted.',
      );
    }

    final profileRef = _firestore.collection('users').doc(user.uid);
    final profileData = profile.toMap();
    try {
      await profileRef.delete();
      try {
        await user.delete();
      } catch (error) {
        // Restore the profile if Firebase Authentication deletion fails so the
        // account is never left authenticated without its role record.
        await profileRef.set(profileData);
        rethrow;
      }
      _currentUserModel = null;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Could not delete your account.';
    } catch (e) {
      return e.toString();
    }
  }

  /// Queries all staff/officer/captain accounts.
  Stream<QuerySnapshot> getStaffAccounts() {
    return _firestore
        .collection('users')
        .where('role', whereIn: ['staff', 'officer', 'captain'])
        .snapshots();
  }

  Future<Set<String>> getExistingAccountEmails() async {
    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs
        .map(
          (doc) => (doc.data()['email'] ?? '').toString().trim().toLowerCase(),
        )
        .where((email) => email.isNotEmpty)
        .toSet();
  }
}
