// lib/core/utils/validators.dart
class AppValidators {
  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static bool isValidEmail(String? value) => email(value) == null;

  static String? phone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';
    final clean = value.replaceAll(' ', '').replaceAll('-', '');
    final regex = RegExp(r'^(09|\+639)\d{9}$');
    if (!regex.hasMatch(clean)) {
      return 'Enter a valid PH phone number (e.g. 09xxxxxxxxx)';
    }
    return null;
  }

  static bool isValidPhone(String? value) => phone(value) == null;

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Must contain an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Must contain a number';
    return null;
  }

  static String? confirmPassword(String? value, String? original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? minLength(String? value, int min) {
    if (value == null || value.length < min) {
      return 'Must be at least $min characters';
    }
    return null;
  }

  static String? loanAmount(String? value) {
    if (value == null || value.isEmpty) return 'Amount is required';
    final amount = double.tryParse(value.replaceAll(',', ''));
    if (amount == null) return 'Enter a valid amount';
    if (amount < 3000) return 'Minimum loan amount is ₱3,000';
    if (amount > 500000) return 'Maximum loan amount is ₱500,000';
    return null;
  }

  static String? plateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Plate number is required';
    }
    return null;
  }

  static String? driversLicense(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Driver\'s license number is required';
    }
    return null;
  }
}
