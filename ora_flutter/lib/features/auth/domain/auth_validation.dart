const maxNicknameLength = 8;

String? nikValidationError(String nik) =>
    nik.trim().isEmpty ? 'Enter your NIK.' : null;

String? pinValidationError(String pin) {
  if (pin.isEmpty) return 'Enter your PIN.';
  if (pin.length != 4) return 'PIN must be exactly 4 digits.';
  if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
    return 'PIN must contain numbers only.';
  }
  return null;
}

String normalizeNickname(String nickname) => nickname.trim();

String canonicalNickname(String nickname) =>
    normalizeNickname(nickname).toUpperCase();

String? nicknameValidationError(String nickname) {
  final normalized = normalizeNickname(nickname);
  if (normalized.isEmpty) return 'Enter a nickname.';
  if (normalized.length > maxNicknameLength) {
    return 'Nickname can have up to 8 characters.';
  }
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(normalized)) {
    return 'Use letters and numbers only.';
  }
  return null;
}
