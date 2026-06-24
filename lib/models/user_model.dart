class UserModel {
  final String uid;
  final String name;
  final String mobile;
  final String email;
  final String role;
  final bool isSeedData;
  final bool isActive;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.mobile,
    required this.email,
    required this.role,
    this.isSeedData = false,
    this.isActive = true,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      mobile: map['mobile'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'resident',
      isSeedData: map['isSeedData'] == true,
      isActive: map['isActive'] != false,
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt']
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'mobile': mobile,
      'email': email,
      'role': role,
      'isSeedData': isSeedData,
      'isActive': isActive,
      'createdAt': createdAt,
    };
  }

  bool get isResident => role == 'resident';
  bool get isStaff => role == 'staff';
  bool get isOfficer => role == 'officer';
  bool get isCaptain => role == 'captain';
  bool get canAccessDashboard => isStaff || isOfficer || isCaptain;
}
