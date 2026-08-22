// lib/core/router/app_router.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/presentation/features/lender/profile/screens/lender_edit_profile_screen.dart'
    as lender_edit_profile;

import '../../presentation/features/auth/screens/force_change_password_screen.dart';
import '../../presentation/features/auth/screens/forgot_password_screen.dart';
import '../../presentation/features/auth/screens/mobile_login_screen.dart';
import '../../presentation/features/auth/screens/otp_verify_screen.dart';
import '../../presentation/features/auth/screens/reset_password_screen.dart';
import '../../presentation/features/auth/screens/splash_screen.dart';
import '../../presentation/features/auth/screens/terms_conditions_screen.dart';
import '../../presentation/features/auth/screens/web_login_screen.dart';
import '../../presentation/features/auth/screens/web_register_screen.dart';
import '../../presentation/features/employee/ci/screens/emp_ci_details_screen.dart';
import '../../presentation/features/employee/ci/screens/emp_ci_list_screen.dart';
import '../../presentation/features/employee/collections/screens/emp_collection_details_screen.dart';
import '../../presentation/features/employee/collections/screens/emp_collection_list_screen.dart';
import '../../presentation/features/employee/dashboard/screens/emp_dashboard_screen.dart';
import '../../presentation/features/employee/in_office/screens/emp_in_office_list_screen.dart';
import '../../presentation/features/employee/account_upgrade/screens/emp_account_upgrade_details_screen.dart';
import '../../presentation/features/employee/account_upgrade/screens/emp_account_upgrade_list_screen.dart';
import '../../presentation/features/employee/lenders/screens/emp_lender_details_screen.dart';
import '../../presentation/features/employee/lenders/screens/emp_lender_list_screen.dart';
import '../../presentation/features/employee/loans/screens/emp_loan_application_details_screen.dart';
import '../../presentation/features/employee/loans/screens/emp_loan_applications_screen.dart';
import '../../presentation/features/employee/loans/screens/emp_loan_details_screen.dart';
import '../../presentation/features/employee/loans/screens/emp_loan_list_screen.dart';
import '../../presentation/features/employee/notifications/screens/emp_notifications_screen.dart';
import '../../presentation/features/employee/payments/screens/emp_payment_details_screen.dart';
import '../../presentation/features/employee/payments/screens/emp_payment_list_screen.dart';
import '../../presentation/features/employee/profile/screens/emp_profile_screen.dart';
import '../../presentation/features/employee/riders/screens/emp_rider_details_screen.dart';
import '../../presentation/features/employee/riders/screens/emp_rider_list_screen.dart';
import '../../presentation/features/head_manager/all_users/screens/hm_all_users_screen.dart';
import '../../presentation/features/head_manager/audit/screens/hm_audit_logs_screen.dart';
import '../../presentation/features/head_manager/ci/screens/hm_ci_details_screen.dart';
import '../../presentation/features/head_manager/ci/screens/hm_ci_list_screen.dart';
import '../../presentation/features/head_manager/collections/screens/hm_collection_details_screen.dart';
import '../../presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart';
import '../../presentation/features/head_manager/dashboard/screens/hm_dashboard_screen.dart';
import '../../presentation/features/head_manager/disbursements/screens/hm_disbursement_details_screen.dart';
import '../../presentation/features/head_manager/disbursements/screens/hm_disbursement_list_screen.dart';
import '../../presentation/features/head_manager/employees/screens/hm_employee_details_screen.dart';
import '../../presentation/features/head_manager/employees/screens/hm_employee_list_screen.dart';
import '../../presentation/features/head_manager/in_office/screens/hm_in_office_list_screen.dart';
import '../../presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_details_screen.dart';
import '../../presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart';
import '../../presentation/features/head_manager/lenders/screens/hm_lender_details_screen.dart';
import '../../presentation/features/head_manager/lenders/screens/hm_lender_list_screen.dart';
import '../../presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart';
import '../../presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart';
import '../../presentation/features/head_manager/loans/screens/hm_loan_details_screen.dart';
import '../../presentation/features/head_manager/loans/screens/hm_loan_list_screen.dart';
import '../../presentation/features/head_manager/notifications/screens/hm_notification_center_screen.dart';
import '../../presentation/features/head_manager/payments/screens/hm_payment_details_screen.dart';
import '../../presentation/features/head_manager/payments/screens/hm_payment_list_screen.dart';
import '../../presentation/features/head_manager/payments/screens/hm_penalty_list_screen.dart';
import '../../presentation/features/head_manager/profile/screens/hm_profile_screen.dart';
import '../../presentation/features/head_manager/reports/screens/hm_report_history_screen.dart';
import '../../presentation/features/head_manager/reports/screens/hm_report_library_screen.dart';
import '../../presentation/features/head_manager/riders/screens/hm_rider_details_screen.dart';
import '../../presentation/features/head_manager/riders/screens/hm_rider_list_screen.dart';
import '../../presentation/features/head_manager/settings/screens/hm_settings_screen.dart';
import '../../presentation/features/lender/collections/screens/lender_collection_details_screen.dart';
import '../../presentation/features/lender/collections/screens/lender_collection_history_screen.dart';
import '../../presentation/features/lender/collections/screens/lender_track_rider_screen.dart';
import '../../presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart';
import '../../presentation/features/lender/documents/screens/lender_documents_screen.dart';
import '../../presentation/features/lender/documents/screens/lender_upload_document_screen.dart';
import '../../presentation/features/lender/account_upgrade/screens/lender_account_upgrade_status_screen.dart';
import '../../presentation/features/lender/account_upgrade/screens/lender_account_upgrade_submit_screen.dart';
import '../../presentation/features/lender/loans/screens/lender_apply_loan_screen.dart';
import '../../presentation/features/lender/loans/screens/lender_loan_application_status_screen.dart';
import '../../presentation/features/lender/loans/screens/lender_loan_details_screen.dart';
import '../../presentation/features/lender/loans/screens/lender_loan_history_screen.dart';
import '../../presentation/features/lender/notifications/screens/lender_notifications_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_pay_via_gcash_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_payment_history_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_payment_method_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_payment_receipt_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_payment_schedule_screen.dart';
import '../../presentation/features/lender/payments/screens/lender_office_payment_screen.dart';
import '../../presentation/features/lender/profile/screens/lender_profile_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_ci_borrower_info_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_ci_details_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_ci_list_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_navigate_to_borrower_ci_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_submit_ci_report_screen.dart';
import '../../presentation/features/rider/ci/screens/rider_upload_ci_documents_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_borrower_info_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_collection_details_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_collection_list_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_navigate_to_borrower_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_record_collection_screen.dart';
import '../../presentation/features/rider/collections/screens/rider_upload_proof_screen.dart';
import '../../presentation/features/rider/dashboard/screens/rider_dashboard_screen.dart';
import '../../presentation/features/rider/disbursements/screens/rider_disbursement_list_screen.dart';
import '../../presentation/features/rider/disbursements/screens/rider_disbursement_upload_proof_screen.dart';
import '../../presentation/features/rider/notifications/screens/rider_notifications_screen.dart';
import '../../presentation/features/rider/profile/screens/rider_profile_screen.dart';
import '../../presentation/features/rider/profile/screens/rider_edit_profile_screen.dart'
    as rider_edit_profile;
import '../../presentation/shared/providers/auth_state_provider.dart';
import '../../presentation/shared/providers/connectivity_provider.dart';
import '../constants/app_constants.dart';
import '../constants/route_constants.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // NOTE: The GoRouter instance is created ONCE and kept stable. Auth state is
  // read LIVE inside `redirect` (never captured — a captured value goes stale
  // after login/logout), and `ref.listen` below re-runs redirects whenever the
  // auth state changes. Recreating the whole router on every auth change used
  // to leave users stranded on the login screen.

  // Platform-aware login route (local variable — getters are class-only in Dart)
  const loginRoute =
      kIsWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin;

  String? redirectForRole(String path, String? role) {
    if (role == null) {
      return loginRoute;
    }

    if (role == AppConstants.roleHeadManager) {
      return path.startsWith('/hm/') ? null : RouteConstants.hmDashboard;
    }

    if (role == AppConstants.roleEmployee) {
      return path.startsWith('/employee/') ? null : RouteConstants.empDashboard;
    }

    if (role == AppConstants.roleRider) {
      return path.startsWith('/rider/') ? null : RouteConstants.riderDashboard;
    }

    if (role == AppConstants.roleLender) {
      return path.startsWith('/lender/')
          ? null
          : RouteConstants.lenderDashboard;
    }

    return RouteConstants.webLogin;
  }

  final router = GoRouter(
    // Mobile has no splash screen — open straight on the login screen and let
    // the redirect below send already-authenticated users to their dashboard.
    initialLocation: kIsWeb ? RouteConstants.splash : RouteConstants.mobileLogin,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // Always evaluate against the LATEST auth state.
      final authState = ref.read(authStateProvider);
      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final path = state.uri.path;

      // While offline (or still probing for connectivity) the web app stays on
      // the splash screen — it cannot be opened without internet access. The
      // mobile app has no splash: unauthenticated users land on the login
      // screen (which shows an offline banner and disables actions) while
      // authenticated users keep their session and get the global offline
      // overlay instead.
      final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
      if (!isOnline) {
        if (kIsWeb) {
          return path == RouteConstants.splash ? null : RouteConstants.splash;
        }
        if (authState.isAuthenticated) {
          return redirectForRole(path, authState.role);
        }
        return path == RouteConstants.mobileLogin
            ? null
            : RouteConstants.mobileLogin;
      }

      final isAuthenticated = authState.isAuthenticated;

      final publicRoutes = [
        RouteConstants.splash,
        RouteConstants.terms,
        RouteConstants.webLogin,
        RouteConstants.webRegister,
        RouteConstants.mobileLogin,
        RouteConstants.otpVerify,
        RouteConstants.forgotPassword,
        RouteConstants.resetPassword,
      ];

      if (!isAuthenticated && !publicRoutes.contains(path)) {
        return loginRoute;
      }

      // Prevent web users from reaching /mobile-login and mobile from /login
      if (!isAuthenticated) {
        if (kIsWeb && path == RouteConstants.mobileLogin) {
          return RouteConstants.webLogin;
        }
        if (!kIsWeb && path == RouteConstants.webLogin) {
          return RouteConstants.mobileLogin;
        }
      }

      if (isAuthenticated) {
        if (authState.forcePasswordChange &&
            path != RouteConstants.forceChangePassword) {
          final role = authState.role;
          if (role != AppConstants.roleRider &&
              role != AppConstants.roleLender) {
            return RouteConstants.forceChangePassword;
          }
        }

        if (path != RouteConstants.forceChangePassword &&
            !publicRoutes.contains(path)) {
          return redirectForRole(path, authState.role);
        }

        if (publicRoutes.contains(path) && !authState.forcePasswordChange) {
          final role = authState.role;
          switch (role) {
            case AppConstants.roleHeadManager:
              return RouteConstants.hmDashboard;
            case AppConstants.roleEmployee:
              return RouteConstants.empDashboard;
            case AppConstants.roleRider:
              return RouteConstants.riderDashboard;
            case AppConstants.roleLender:
              return RouteConstants.lenderDashboard;
            default:
              return loginRoute;
          }
        }
      }
      return null;
    },
    routes: [
      GoRoute(
          path: RouteConstants.splash,
          builder: (ctx, s) => const SplashScreen()),
      GoRoute(
          path: RouteConstants.terms,
          builder: (ctx, s) => const TermsConditionsScreen()),
      GoRoute(
          path: RouteConstants.webLogin,
          builder: (ctx, s) => const WebLoginScreen()),
      GoRoute(
          path: RouteConstants.webRegister,
          builder: (ctx, s) => const WebRegisterScreen()),
      GoRoute(
          path: RouteConstants.mobileLogin,
          builder: (ctx, s) => const MobileLoginScreen()),
      GoRoute(
          path: RouteConstants.otpVerify,
          builder: (ctx, s) =>
              OtpVerifyScreen(phone: s.extra as String? ?? '')),
      GoRoute(
          path: RouteConstants.forceChangePassword,
          builder: (ctx, s) => const ForceChangePasswordScreen()),
      GoRoute(
          path: RouteConstants.forgotPassword,
          builder: (ctx, s) => const ForgotPasswordScreen()),
      GoRoute(
          path: RouteConstants.resetPassword,
          builder: (ctx, s) => const ResetPasswordScreen()),

      // ── Head Manager ──
      GoRoute(
          path: RouteConstants.hmDashboard,
          builder: (ctx, s) => const HmDashboardScreen()),
      GoRoute(
          path: RouteConstants.hmAllUsers,
          builder: (ctx, s) => const HmAllUsersScreen()),
      GoRoute(
          path: RouteConstants.hmEmployees,
          builder: (ctx, s) => const HmEmployeeListScreen()),
      GoRoute(
          path: RouteConstants.hmEmployeeDetails,
          builder: (ctx, s) =>
              HmEmployeeDetailsScreen(userId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmRiders,
          builder: (ctx, s) => const HmRiderListScreen()),
      GoRoute(
          path: RouteConstants.hmRiderDetails,
          builder: (ctx, s) =>
              HmRiderDetailsScreen(userId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmLenders,
          builder: (ctx, s) => const HmLenderListScreen()),
      GoRoute(
          path: RouteConstants.hmLenderDetails,
          builder: (ctx, s) =>
              HmLenderDetailsScreen(userId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmLoanApplications,
          builder: (ctx, s) => const HmLoanApplicationsListScreen()),
      GoRoute(
          path: RouteConstants.hmLoanApplicationDetails,
          builder: (ctx, s) =>
              HmLoanApplicationDetailsScreen(loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmLoans,
          builder: (ctx, s) => const HmLoanListScreen()),
      GoRoute(
          path: RouteConstants.hmLoanDetails,
          builder: (ctx, s) =>
              HmLoanDetailsScreen(loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmAccountUpgrade,
          builder: (ctx, s) => const HmAccountUpgradeListScreen()),
      GoRoute(
          path: RouteConstants.hmAccountUpgradeDetails,
          builder: (ctx, s) =>
              HmAccountUpgradeDetailsScreen(lenderId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmCi,
          builder: (ctx, s) => const HmCiListScreen()),
      GoRoute(
          path: RouteConstants.hmCiDetails,
          builder: (ctx, s) =>
              HmCiDetailsScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmCollections,
          builder: (ctx, s) => const HmCollectionListScreen()),
      GoRoute(
          path: RouteConstants.hmCollectionDetails,
          builder: (ctx, s) =>
              HmCollectionDetailsScreen(collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmDisbursements,
          builder: (ctx, s) => const HmDisbursementListScreen()),
      GoRoute(
          path: RouteConstants.hmDisbursementDetails,
          builder: (ctx, s) => HmDisbursementDetailsScreen(
              disbursementId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmPayments,
          builder: (ctx, s) => const HmPaymentListScreen()),
      GoRoute(
          path: RouteConstants.hmPaymentDetails,
          builder: (ctx, s) =>
              HmPaymentDetailsScreen(paymentId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.hmPenalties,
          builder: (ctx, s) => const HmPenaltyListScreen()),
      GoRoute(
          path: RouteConstants.hmReports,
          builder: (ctx, s) => const HmReportLibraryScreen()),
      GoRoute(
          path: RouteConstants.hmReportHistory,
          builder: (ctx, s) => const HmReportHistoryScreen()),
      GoRoute(
          path: RouteConstants.hmAudit,
          builder: (ctx, s) => const HmAuditLogsScreen()),
      GoRoute(
          path: RouteConstants.hmNotifications,
          builder: (ctx, s) => const HmNotificationCenterScreen()),
      GoRoute(
          path: RouteConstants.hmInOffice,
          builder: (ctx, s) => const HmInOfficeListScreen()),
      GoRoute(
          path: RouteConstants.hmSettings,
          builder: (ctx, s) => const HmSettingsScreen()),
      GoRoute(
          path: RouteConstants.hmProfile,
          builder: (ctx, s) => const HmProfileScreen()),

      // ── Employee ──
      GoRoute(
          path: RouteConstants.empDashboard,
          builder: (ctx, s) => const EmpDashboardScreen()),
      GoRoute(
          path: RouteConstants.empLenders,
          builder: (ctx, s) => const EmpLenderListScreen()),
      GoRoute(
          path: RouteConstants.empLenderDetails,
          builder: (ctx, s) =>
              EmpLenderDetailsScreen(lenderId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empRiders,
          builder: (ctx, s) => const EmpRiderListScreen()),
      GoRoute(
          path: RouteConstants.empRiderDetails,
          builder: (ctx, s) =>
              EmpRiderDetailsScreen(riderId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empLoans,
          builder: (ctx, s) => const EmpLoanApplicationsScreen()),
      GoRoute(
          path: RouteConstants.empActiveLoans,
          builder: (ctx, s) => const EmpLoanListScreen()),
      GoRoute(
          path: RouteConstants.empLoanApplicationDetails,
          builder: (ctx, s) =>
              EmpLoanApplicationDetailsScreen(loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empLoanDetails,
          builder: (ctx, s) =>
              EmpLoanDetailsScreen(loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empAccountUpgrade,
          builder: (ctx, s) => const EmpAccountUpgradeListScreen()),
      GoRoute(
          path: RouteConstants.empAccountUpgradeDetails,
          builder: (ctx, s) => EmpAccountUpgradeDetailsScreen(
              lenderId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empCi,
          builder: (ctx, s) => const EmpCiListScreen()),
      GoRoute(
          path: RouteConstants.empCiDetails,
          builder: (ctx, s) =>
              EmpCiDetailsScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empCollections,
          builder: (ctx, s) => const EmpCollectionListScreen()),
      GoRoute(
          path: RouteConstants.empCollectionDetails,
          builder: (ctx, s) => EmpCollectionDetailsScreen(
              collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empPayments,
          builder: (ctx, s) => const EmpPaymentListScreen()),
      GoRoute(
          path: RouteConstants.empPaymentDetails,
          builder: (ctx, s) =>
              EmpPaymentDetailsScreen(paymentId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.empInOffice,
          builder: (ctx, s) => const EmpInOfficeListScreen()),
      GoRoute(
          path: RouteConstants.empNotifications,
          builder: (ctx, s) => const EmpNotificationsScreen()),
      GoRoute(
          path: RouteConstants.empProfile,
          builder: (ctx, s) => const EmpProfileScreen()),

      // ── Rider ──
      GoRoute(
          path: RouteConstants.riderDashboard,
          builder: (ctx, s) => const RiderDashboardScreen()),
      GoRoute(
          path: RouteConstants.riderDisbursements,
          builder: (ctx, s) => const RiderDisbursementListScreen()),
      GoRoute(
          path: RouteConstants.riderDisbursementUploadProof,
          builder: (ctx, s) => RiderDisbursementUploadProofScreen(
              disbursementId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderCollections,
          builder: (ctx, s) => const RiderCollectionListScreen()),
      GoRoute(
          path: RouteConstants.riderCollectionDetails,
          builder: (ctx, s) => RiderCollectionDetailsScreen(
              collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderBorrowerInfo,
          builder: (ctx, s) =>
              RiderBorrowerInfoScreen(collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderNavigateToBorrower,
          builder: (ctx, s) => RiderNavigateToBorrowerScreen(
              collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderRecordCollection,
          builder: (ctx, s) => RiderRecordCollectionScreen(
              collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderUploadProof,
          builder: (ctx, s) =>
              RiderUploadProofScreen(assignmentId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderCi,
          builder: (ctx, s) => const RiderCiListScreen()),
      GoRoute(
          path: RouteConstants.riderCiDetails,
          builder: (ctx, s) =>
              RiderCiDetailsScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderCiBorrowerInfo,
          builder: (ctx, s) =>
              RiderCiBorrowerInfoScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderNavigateToBorrowerCi,
          builder: (ctx, s) =>
              RiderNavigateToBorrowerCiScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderUploadCiDocuments,
          builder: (ctx, s) =>
              RiderUploadCiDocumentsScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderSubmitCiReport,
          builder: (ctx, s) =>
              RiderSubmitCiReportScreen(ciId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.riderNotifications,
          builder: (ctx, s) => const RiderNotificationsScreen()),
      GoRoute(
          path: RouteConstants.riderProfile,
          builder: (ctx, s) => const RiderProfileScreen()),
      GoRoute(
          path: RouteConstants.riderEditProfile,
          builder: (ctx, s) =>
              const rider_edit_profile.RiderProfileEditScreen()),

      // ── Lender ──
      GoRoute(
          path: RouteConstants.lenderDashboard,
          builder: (ctx, s) => const LenderDashboardScreen()),
      GoRoute(
          path: RouteConstants.lenderAccountUpgrade,
          builder: (ctx, s) => const LenderAccountUpgradeSubmitScreen()),
      GoRoute(
          path: RouteConstants.lenderAccountUpgradeStatus,
          builder: (ctx, s) => const LenderAccountUpgradeStatusScreen()),
      GoRoute(
          path: RouteConstants.lenderLoans,
          builder: (ctx, s) => const LenderApplyLoanScreen()),
      GoRoute(
          path: RouteConstants.lenderLoanDetails,
          builder: (ctx, s) =>
              LenderLoanDetailsScreen(loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.lenderLoanApplicationStatus,
          builder: (ctx, s) => LenderLoanApplicationStatusScreen(
              loanId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.lenderLoanHistory,
          builder: (ctx, s) => const LenderLoanHistoryScreen()),
      GoRoute(
          path: RouteConstants.lenderPayments,
          builder: (ctx, s) => const LenderPaymentScheduleScreen()),
      GoRoute(
          path: RouteConstants.lenderPaymentHistory,
          builder: (ctx, s) => const LenderPaymentHistoryScreen()),
      GoRoute(
          path: RouteConstants.lenderPayViaGcash,
          builder: (ctx, s) => LenderPayViaGcashScreen(
              extra: s.extra as Map<String, dynamic>? ?? {})),
      GoRoute(
          path: RouteConstants.lenderPaymentMethod,
          builder: (ctx, s) => LenderPaymentMethodScreen(
              extra: s.extra as Map<String, dynamic>? ?? {})),
      GoRoute(
          path: RouteConstants.lenderOfficePayment,
          builder: (ctx, s) => LenderOfficePaymentScreen(
              extra: s.extra as Map<String, dynamic>? ?? {})),
      GoRoute(
          path: RouteConstants.lenderPaymentReceipt,
          builder: (ctx, s) =>
              LenderPaymentReceiptScreen(paymentId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.lenderCollections,
          builder: (ctx, s) => const LenderCollectionHistoryScreen()),
      GoRoute(
          path: RouteConstants.lenderCollectionDetails,
          builder: (ctx, s) => LenderCollectionDetailsScreen(
              collectionId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.lenderTrackRider,
          builder: (ctx, s) =>
              LenderTrackRiderScreen(riderId: s.pathParameters['id']!)),
      GoRoute(
          path: RouteConstants.lenderDocuments,
          builder: (ctx, s) => const LenderDocumentsScreen()),
      GoRoute(
          path: RouteConstants.lenderUploadDocument,
          builder: (ctx, s) => const LenderUploadDocumentScreen()),
      GoRoute(
          path: RouteConstants.lenderNotifications,
          builder: (ctx, s) => const LenderNotificationsScreen()),
      GoRoute(
          path: RouteConstants.lenderProfile,
          builder: (ctx, s) => const LenderProfileScreen()),
      GoRoute(
          path: RouteConstants.lenderEditProfile,
          builder: (ctx, s) =>
              const lender_edit_profile.LenderProfileEditScreen()),
    ],
    errorBuilder: (ctx, s) =>
        Scaffold(body: Center(child: Text('Page not found: ${s.uri.path}'))),
  );

  // Re-evaluate redirects whenever auth state changes (login success, logout,
  // session expiry, force-password-change flag flips). Without this the router
  // would keep showing the login screen after a successful login.
  ref.listen(authStateProvider, (_, __) => router.refresh());
  ref.onDispose(router.dispose);

  return router;
});

/// Exposes the current go_router path so widgets rendered ABOVE the router
/// (e.g. the global [ConnectivityOverlay]) can tell which screen is showing.
final currentRoutePathProvider = StreamProvider<String>((ref) {
  final router = ref.watch(appRouterProvider);
  final controller = StreamController<String>();

  void emit() {
    final path = router.routeInformationProvider.value.uri.path;
    if (!controller.isClosed) controller.add(path);
  }

  router.routeInformationProvider.addListener(emit);
  emit();
  ref.onDispose(() {
    router.routeInformationProvider.removeListener(emit);
    controller.close();
  });
  return controller.stream;
});
