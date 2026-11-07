class UserModel {
  final String uid;
  final String name;
  final String firstName;
  final String middleName;
  final String lastName;
  final String mobile;
  final String email;
  final String role;
  final bool isSeedData;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime createdAt;
  final bool hasActingCaptainAuthority;
  final DateTime? actingCaptainUntil;

  UserModel({
    required this.uid,
    required this.name,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    required this.mobile,
    required this.email,
    required this.role,
    this.isSeedData = false,
    this.isActive = true,
    this.mustChangePassword = false,
    required this.createdAt,
    this.hasActingCaptainAuthority = false,
    this.actingCaptainUntil,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    final storedName = (map['name'] ?? map['legalName'] ?? '')
        .toString()
        .trim();
    final parsed = splitLegacyName(storedName);
    return UserModel(
      uid: uid,
      name: composeName(
        firstName: (map['firstName'] ?? parsed.firstName).toString(),
        middleName: (map['middleName'] ?? parsed.middleName).toString(),
        lastName: (map['lastName'] ?? parsed.lastName).toString(),
        fallback: storedName,
      ),
      firstName: (map['firstName'] ?? parsed.firstName).toString(),
      middleName: (map['middleName'] ?? parsed.middleName).toString(),
      lastName: (map['lastName'] ?? parsed.lastName).toString(),
      mobile: map['mobile'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'resident',
      isSeedData: map['isSeedData'] == true,
      isActive: map['isActive'] != false,
      mustChangePassword: map['mustChangePassword'] == true,
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt']
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'mobile': mobile,
      'email': email,
      'role': role,
      'isSeedData': isSeedData,
      'isActive': isActive,
      'mustChangePassword': mustChangePassword,
      'createdAt': createdAt,
    };
  }

  bool get isResident => role == 'resident';

  static String composeName({
    required String firstName,
    String middleName = '',
    required String lastName,
    String fallback = '',
  }) {
    final result = [
      firstName,
      middleName,
      lastName,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' ');
    return result.isEmpty ? fallback.trim() : result;
  }

  static ({String firstName, String middleName, String lastName})
  splitLegacyName(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (firstName: '', middleName: '', lastName: '');
    if (parts.length == 1) {
      return (firstName: parts.first, middleName: '', lastName: '');
    }
    return (
      firstName: parts.first,
      middleName: parts.length > 2
          ? parts.sublist(1, parts.length - 1).join(' ')
          : '',
      lastName: parts.last,
    );
  }

  bool get isStaff => role == 'staff';
  bool get isOfficer => role == 'officer';
  bool get isPermanentCaptain => role == 'captain';
  bool get isCaptain => isPermanentCaptain || hasActingCaptainAuthority;
  bool get isTreasurer => role == 'treasurer';
  String get effectiveRole => isCaptain ? 'captain' : role;
  bool get canAccessDashboard =>
      isStaff || isOfficer || isCaptain || isTreasurer;

  UserModel withActingCaptainAuthority({
    required bool enabled,
    DateTime? until,
  }) => UserModel(
    uid: uid,
    name: name,
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
    mobile: mobile,
    email: email,
    role: role,
    isSeedData: isSeedData,
    isActive: isActive,
    mustChangePassword: mustChangePassword,
    createdAt: createdAt,
    hasActingCaptainAuthority: enabled,
    actingCaptainUntil: enabled ? until : null,
  );
}
