import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
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

  /// Queries all staff/officer/captain accounts.
  Stream<QuerySnapshot> getStaffAccounts() {
    return _firestore
        .collection('users')
        .where('role', whereIn: ['staff', 'officer', 'captain'])
        .snapshots();
  }
}
