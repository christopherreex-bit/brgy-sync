String? validateAccountEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'Email is required.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateUniqueAccountEmail(
  String value,
  Iterable<String> existingEmails,
) {
  final formatError = validateAccountEmail(value);
  if (formatError != null) return formatError;
  final normalized = value.trim().toLowerCase();
  final alreadyExists = existingEmails.any(
    (email) => email.trim().toLowerCase() == normalized,
  );
  return alreadyExists ? 'This email is already in use.' : null;
}

String? validatePhilippineMobile(String value) {
  final mobile = value.trim();
  if (mobile.isEmpty) return 'Mobile number is required.';
  if (!RegExp(r'^09\d{9}$').hasMatch(mobile)) {
    return 'Use 09XXXXXXXXX (11 digits).';
  }
  return null;
}

String? validateStaffPassword(String value) {
  if (value.isEmpty) return 'Password is required.';
  if (value.length < 6) return 'Use at least 6 characters.';
  return null;
}

String? validatePasswordChange({
  required String currentPassword,
  required String newPassword,
}) {
  if (currentPassword.isEmpty) return 'Enter your current password.';
  final passwordError = validateStaffPassword(newPassword);
  if (passwordError != null) return passwordError;
  if (newPassword == currentPassword) {
    return 'New password must be different from your current password.';
  }
  return null;
}
