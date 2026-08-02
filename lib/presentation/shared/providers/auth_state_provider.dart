// lib/presentation/shared/providers/auth_state_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/security/secure_storage.dart';
import '../../../data/models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  String? get role => user?.role;
  bool get forcePasswordChange => user?.forcePasswordChange ?? false;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        user: user ?? this.user,
        error: error,
      );
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(const AuthState());

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      final hasSession = await SecureStorage.hasValidSession();
      if (hasSession) {
        final userId = await SecureStorage.getUserId();
        final role = await SecureStorage.getUserRole();
        if (userId != null &&
            role != null &&
            RoleConstants.allRoles.contains(role)) {
          state = AuthState(
            isAuthenticated: true,
            user: UserModel(
              id: userId,
              role: role,
              firstName: '',
              lastName: '',
              accountStatus: 'active',
              forcePasswordChange: false,
              createdAt: DateTime.now(),
            ),
          );
          return;
        }
      }
      state = const AuthState(isAuthenticated: false);
    } catch (_) {
      state = const AuthState(isAuthenticated: false);
    }
  }

  void setAuthenticated(UserModel user) {
    state = AuthState(isAuthenticated: true, user: user);
  }

  void setForcePasswordChangeDone() {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(forcePasswordChange: false),
      );
    }
  }

  Future<void> logout() async {
    await SecureStorage.clearAll();
    state = const AuthState(isAuthenticated: false);
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier()..initialize();
});
