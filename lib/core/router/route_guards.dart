// lib/core/router/route_guards.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/shared/providers/auth_state_provider.dart';
import '../constants/role_constants.dart';
import '../constants/route_constants.dart';

class RouteGuards {
  RouteGuards._();

  static String? authGuard(BuildContext context, GoRouterState state, WidgetRef ref) {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated) {
      const isWeb = kIsWeb;
      return isWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin;
    }
    return null;
  }

  static String? roleGuard(
    BuildContext context,
    GoRouterState state,
    WidgetRef ref,
    List<String> allowedRoles,
  ) {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated) {
      return kIsWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin;
    }
    final role = authState.role ?? '';
    if (!allowedRoles.contains(role)) {
      return _defaultRouteForRole(role);
    }
    return null;
  }

  static String? forcePasswordGuard(
    BuildContext context,
    GoRouterState state,
    WidgetRef ref,
  ) {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated &&
        authState.forcePasswordChange == true &&
        state.matchedLocation != RouteConstants.forceChangePassword) {
      return RouteConstants.forceChangePassword;
    }
    return null;
  }

  static String _defaultRouteForRole(String role) {
    switch (role) {
      case RoleConstants.headManager:
        return RouteConstants.hmDashboard;
      case RoleConstants.employee:
        return RouteConstants.empDashboard;
      case RoleConstants.rider:
        return RouteConstants.riderDashboard;
      case RoleConstants.lender:
        return RouteConstants.lenderDashboard;
      default:
        return kIsWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin;
    }
  }
}
