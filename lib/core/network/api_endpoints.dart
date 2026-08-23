// lib/core/network/api_endpoints.dart
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String authLogin = 'auth-login?fn=login';
  static const String authRegister = 'auth-register?fn=register';
  static const String authSendOtp = 'auth-otp?fn=send-otp';
  static const String authVerifyOtp = 'auth-otp?fn=verify-otp';
  static const String authForceChangePassword =
      'auth-password?fn=force-change-password';
  static const String authChangePassword = 'auth-password?fn=change-password';
  static const String authForgotPassword = 'auth-password?fn=forgot-password';
  static const String authVerifyResetOtp = 'auth-password?fn=verify-otp';
  static const String authResetPassword = 'auth-password?fn=reset-password';
  static const String authLogout = 'auth-logout?fn=logout';
  static const String authRefreshSession = 'auth-session?fn=refresh-session';
  static const String authTermsAccept = 'auth-session?fn=terms-accept';
  static const String authGoogle = 'auth-google?fn=exchange';

  // Users
  static const String usersCreateEmployee = 'users-create?fn=create-employee';
  static const String usersCreateRider = 'users-create?fn=create-rider';
  static const String usersCreateLender = 'users-create?fn=create-lender';
  static const String usersUpdateProfile = 'users-manage?fn=update-profile';
  static const String usersGetProfile = 'users-manage?fn=get-profile';
  static const String usersGetList = 'users-admin?fn=get-list';
  static const String usersArchive = 'users-admin?fn=archive';

  // Account Upgrade
  static const String accountUpgradeSubmit = 'kyc-submit?fn=submit';
  static const String accountUpgradeVerify = 'kyc-view?fn=verify';
  static const String accountUpgradeGetList = 'kyc-view?fn=get-list';
  static const String accountUpgradeGetStatus = 'kyc-view?fn=get-status';
  static const String accountUpgradeGetDetails = 'kyc-view?fn=get-details';

  // Loans
  static const String loansApply = 'loans-apply?fn=apply';
  static const String loansApprove = 'loans-manage?fn=approve';
  static const String loansReject = 'loans-manage?fn=reject';
  static const String loansCancel = 'loans-manage?fn=cancel';
  static const String loansGetList = 'loans-view?fn=get-list';
  static const String loansGetDetails = 'loans-view?fn=get-details';
  static const String loansGetSchedulePreview =
      'loans-view?fn=get-schedule-preview';
  static const String loansApplyPenalty = 'loans-manage?fn=apply-penalty';
  static const String loansRequestCi = 'loans-manage?fn=request-ci';

  // Credit Investigation
  static const String ciAssign = 'ci-manage?fn=assign';
  static const String ciAccept = 'ci-manage?fn=accept';
  static const String ciDecline = 'ci-manage?fn=decline';
  static const String ciUploadDocuments = 'ci-submit?fn=upload-documents';
  static const String ciSubmitReport = 'ci-submit?fn=submit-report';
  static const String ciGetList = 'ci-view?fn=get-list';

  // Collections
  static const String collectionsRequest = 'collections-manage?fn=request';
  static const String collectionsAssign = 'collections-manage?fn=assign';
  static const String collectionsAccept = 'collections-manage?fn=accept';
  static const String collectionsDecline = 'collections-manage?fn=decline';
  static const String collectionsRecord = 'collections-manage?fn=record';
  static const String collectionsUploadProof =
      'collections-manage?fn=upload-proof';
  static const String collectionsGetList = 'collections-view?fn=get-list';
  static const String collectionsGet = 'collections-view?fn=get';

  // Payments
  static const String paymentsRecordOffice = 'payments-manage?fn=record-office';
  static const String paymentsGenerateXenditLink =
      'payments-xendit-link?fn=generate';
  static const String paymentsXenditWebhook = 'payments-xendit-webhook';
  static const String paymentsReverse = 'payments-manage?fn=reverse';
  static const String paymentsGetReceipt = 'payments-view?fn=get-receipt';
  static const String paymentsGetList = 'payments-view?fn=get-list';

  // Disbursements
  static const String disbursementsSelect = 'disbursements-select?fn=select';
  static const String disbursementsGcash = 'disbursements-gcash?fn=gcash';
  static const String disbursementsOfficeCash =
      'disbursements-delivery?fn=office-cash';
  static const String disbursementsRiderDelivery =
      'disbursements-delivery?fn=rider-delivery';
  static const String disbursementsUploadProof =
      'disbursements-delivery?fn=upload-proof';
  static const String disbursementsXenditWebhook =
      'disbursements-xendit-webhook';
  static const String disbursementsGetList = 'disbursements-view?fn=get-list';

  // Location
  static const String locationUpdateRider = 'location-manage?fn=update-rider';
  static const String locationGetRider = 'location-manage?fn=get-rider';
  static const String locationListTracked = 'location-manage?fn=list-tracked';

  // Notifications
  static const String notificationsSend = 'notifications-send?fn=send';
  static const String notificationsGetList = 'notifications-view?fn=get-list';
  static const String notificationsMarkRead = 'notifications-view?fn=mark-read';

  // Reports
  static const String reportsGenerate = 'reports-generate?fn=generate';
  static const String reportsGetList = 'reports-view?fn=get-list';
  static const String reportsGetHistory = 'reports-view?fn=get-history';

  // In-Office
  static const String inOfficeCreateDraft = 'in-office-create?fn=create-draft';
  static const String inOfficeSaveStep = 'in-office-create?fn=save-step';
  static const String inOfficeSubmit = 'in-office-view?fn=submit';
  static const String inOfficeGetList = 'in-office-view?fn=get-list';

  // KPIs
  static const String kpiHeadManager = 'kpi-view?fn=head-manager';
  static const String kpiEmployee = 'kpi-view?fn=employee';
  static const String kpiRider = 'kpi-view?fn=rider';
  static const String kpiLender = 'kpi-view?fn=lender';

  // System
  static const String systemGetConfig = 'system-view?fn=get-config';
  static const String systemUpdateConfig = 'system-update-config';
  static const String systemGetSmsTemplates =
      'system-view?fn=get-sms-templates';
  static const String systemUpdateSmsTemplate =
      'system-view?fn=update-sms-template';

  // Audit
  static const String auditGetLogs = 'audit-get-logs?fn=get-logs';
}
