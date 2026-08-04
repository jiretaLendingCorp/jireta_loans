// lib/core/network/api_endpoints.dart
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String authLogin = 'auth-login';
  static const String authSendOtp = 'auth-send-otp';
  static const String authVerifyOtp = 'auth-verify-otp';
  static const String authForceChangePassword = 'auth-force-change-password';
  static const String authForgotPassword = 'auth-forgot-password';
  static const String authResetPassword = 'auth-reset-password';
  static const String authLogout = 'auth-logout';
  static const String authRefreshSession = 'auth-refresh-session';
  static const String authTermsAccept = 'auth-terms-accept';

  // Users
  static const String usersCreateEmployee = 'users-create-employee';
  static const String usersCreateRider = 'users-create-rider';
  static const String usersCreateLender = 'users-create-lender';
  static const String usersUpdateProfile = 'users-update-profile';
  static const String usersGetProfile = 'users-get-profile';
  static const String usersGetList = 'users-get-list';
  static const String usersSuspendActivate = 'users-suspend-activate';
  static const String usersArchive = 'users-archive';

  // KYC
  static const String kycSubmit = 'kyc-submit';
  static const String kycVerify = 'kyc-verify';
  static const String kycGetList = 'kyc-get-list';
  static const String kycGetStatus = 'kyc-get-status';
  static const String kycGetDetails = 'kyc-get-details';

  // Loans
  static const String loansApply = 'loans-apply';
  static const String loansApprove = 'loans-approve';
  static const String loansReject = 'loans-reject';
  static const String loansCancel = 'loans-cancel';
  static const String loansGetList = 'loans-get-list';
  static const String loansGetDetails = 'loans-get-details';
  static const String loansGetSchedulePreview = 'loans-get-schedule-preview';
  static const String loansApplyPenalty = 'loans-apply-penalty';
  static const String loansRequestCi = 'loans-request-ci';

  // Credit Investigation
  static const String ciAssign = 'ci-assign';
  static const String ciAccept = 'ci-accept';
  static const String ciDecline = 'ci-decline';
  static const String ciUploadDocuments = 'ci-upload-documents';
  static const String ciSubmitReport = 'ci-submit-report';
  static const String ciGetList = 'ci-get-list';

  // Collections
  static const String collectionsAssign = 'collections-assign';
  static const String collectionsAccept = 'collections-accept';
  static const String collectionsDecline = 'collections-decline';
  static const String collectionsRecord = 'collections-record';
  static const String collectionsUploadProof = 'collections-upload-proof';
  static const String collectionsGetList = 'collections-get-list';

  // Payments
  static const String paymentsRecordOffice = 'payments-record-office';
  static const String paymentsGenerateXenditLink =
      'payments-generate-xendit-link';
  static const String paymentsXenditWebhook = 'payments-xendit-webhook';
  static const String paymentsReverse = 'payments-reverse';
  static const String paymentsGetReceipt = 'payments-get-receipt';
  static const String paymentsGetList = 'payments-get-list';

  // Disbursements
  static const String disbursementsGcash = 'disbursements-gcash';
  static const String disbursementsOfficeCash = 'disbursements-office-cash';
  static const String disbursementsRiderDelivery =
      'disbursements-rider-delivery';
  static const String disbursementsXenditWebhook =
      'disbursements-xendit-webhook';

  // Blacklist
  static const String blacklistAdd = 'blacklist-add';
  static const String blacklistRemove = 'blacklist-remove';
  static const String blacklistGetList = 'blacklist-get-list';

  // Location
  static const String locationUpdateRider = 'location-update-rider';
  static const String locationGetRider = 'location-get-rider';

  // Notifications
  static const String notificationsSend = 'notifications-send';
  static const String notificationsGetList = 'notifications-get-list';
  static const String notificationsMarkRead = 'notifications-mark-read';

  // Reports
  static const String reportsGenerate = 'reports-generate';
  static const String reportsGetList = 'reports-get-list';
  static const String reportsGetHistory = 'reports-get-history';

  // In-Office
  static const String inOfficeCreateDraft = 'in-office-create-draft';
  static const String inOfficeSaveStep = 'in-office-save-step';
  static const String inOfficeSubmit = 'in-office-submit';
  static const String inOfficeGetList = 'in-office-get-list';

  // KPIs
  static const String kpiHeadManager = 'kpi-head-manager';
  static const String kpiEmployee = 'kpi-employee';
  static const String kpiRider = 'kpi-rider';
  static const String kpiLender = 'kpi-lender';

  // Audit
  static const String auditGetLogs = 'audit-get-logs';
}
