import 'package:flutter/foundation.dart';
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

  bool _mockMode = false;
  bool _ignoreNextAuthState = false;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (_ignoreNextAuthState) {
      _ignoreNextAuthState = false;
      notifyListeners();
      return;
    }
    if (user != null && !_mockMode) {
      await _loadUserData(user.uid);
    } else if (user == null && !_mockMode) {
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

  // ─── Mock login for demo (no Firebase needed) ─────────────────
  void mockLogin(String role) {
    _mockMode = true;
    _currentUserModel = UserModel(
      uid: 'mock_${role}_001',
      name: _mockName(role),
      mobile: '09123456789',
      email: '$role@brgysync.demo',
      role: role,
      createdAt: DateTime.now(),
    );
    notifyListeners();
  }

  String _mockName(String role) {
    switch (role) {
      case 'captain':
        return 'Juan Dela Cruz';
      case 'officer':
        return 'Maria Santos';
      case 'staff':
        return 'Pedro Reyes';
      default:
        return 'Ana Garcia';
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
    if (_mockMode) {
      _mockMode = false;
      _currentUserModel = null;
    } else {
      await _auth.signOut();
      _currentUserModel = null;
    }
    notifyListeners();
  }

  // ─── Staff Account Management (Phase 12) ───────────────────────

  /// Creates a new staff/officer/captain account (NOT resident).
  /// Returns the new user's UID on success, error message on failure.
  /// Note: createUserWithEmailAndPassword signs in as the new user.
  /// The caller is responsible for re-logging in as the captain after.
  Future<String?> createStaffAccount({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String role,
  }) async {
    try {
      // createUserWithEmailAndPassword signs in as the new user.
      // Ignore the auth state change so _currentUserModel stays as the captain.
      _ignoreNextAuthState = true;
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
          role: role,
          isActive: true,
          createdAt: DateTime.now(),
        );
        await _firestore
            .collection('users')
            .doc(cred.user!.uid)
            .set(user.toMap());
        return null;
      }
      return 'Failed to create user.';
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Updates a user's role in Firestore.
  Future<String?> updateUserRole(String userId, String newRole) async {
    try {
      await _firestore.collection('users').doc(userId).update({'role': newRole});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Deactivates a user account (soft delete).
  Future<String?> deactivateAccount(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({'isActive': false});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Reactivates a user account.
  Future<String?> activateAccount(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({'isActive': true});
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
