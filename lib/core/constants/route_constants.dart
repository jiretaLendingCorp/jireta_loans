// lib/core/constants/route_constants.dart
class RouteConstants {
  RouteConstants._();

  static const String splash = '/';
  static const String terms = '/terms';
  static const String webLogin = '/login';
  static const String mobileLogin = '/mobile-login';
  static const String otpVerify = '/otp-verify';
  static const String forceChangePassword = '/force-change-password';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Head Manager
  static const String hmDashboard = '/hm/dashboard';
  static const String hmEmployees = '/hm/employees';
  static const String hmEmployeeDetails = '/hm/employees/:id';
  static const String hmRiders = '/hm/riders';
  static const String hmRiderDetails = '/hm/riders/:id';
  static const String hmLenders = '/hm/lenders';
  static const String hmLenderDetails = '/hm/lenders/:id';
  static const String hmLoanApplications = '/hm/loan-applications';
  static const String hmLoanApplicationDetails = '/hm/loan-applications/:id';
  static const String hmLoans = '/hm/loans';
  static const String hmLoanDetails = '/hm/loans/:id';
  static const String hmAccountUpgrade = '/hm/account-upgrade';
  static const String hmAccountUpgradeDetails = '/hm/account-upgrade/:id';
  static const String hmCi = '/hm/ci';
  static const String hmCiDetails = '/hm/ci/:id';
  static const String hmCollections = '/hm/collections';
  static const String hmCollectionDetails = '/hm/collections/:id';
  static const String hmDisbursements = '/hm/disbursements';
  static const String hmDisbursementDetails = '/hm/disbursements/:id';
  static const String hmPayments = '/hm/payments';
  static const String hmPaymentDetails = '/hm/payments/:id';
  static const String hmPenalties = '/hm/penalties';
  static const String hmReports = '/hm/reports';
  static const String hmReportHistory = '/hm/report-history';
  static const String hmAudit = '/hm/audit';
  static const String hmNotifications = '/hm/notifications';
  static const String hmInOffice = '/hm/in-office';
  static const String hmSettings = '/hm/settings';
  static const String hmProfile = '/hm/profile';

  // Employee
  static const String empDashboard = '/employee/dashboard';
  static const String empLenders = '/employee/lenders';
  static const String empLenderDetails = '/employee/lenders/:id';
  static const String empRiders = '/employee/riders';
  static const String empRiderDetails = '/employee/riders/:id';
  static const String empLoans = '/employee/loans';
  static const String empLoanApplicationDetails = '/employee/loans/:id';
  static const String empLoanDetails = '/employee/loan-details/:id';
  static const String empAccountUpgrade = '/employee/account-upgrade';
  static const String empAccountUpgradeDetails =
      '/employee/account-upgrade/:id';
  static const String empCi = '/employee/ci';
  static const String empCiDetails = '/employee/ci/:id';
  static const String empCollections = '/employee/collections';
  static const String empCollectionDetails = '/employee/collections/:id';
  static const String empPayments = '/employee/payments';
  static const String empPaymentDetails = '/employee/payments/:id';
  static const String empInOffice = '/employee/in-office';
  static const String empNotifications = '/employee/notifications';
  static const String empProfile = '/employee/profile';

  // Rider
  static const String riderDashboard = '/rider/dashboard';
  static const String riderDisbursements = '/rider/disbursements';
  static const String riderDisbursementUploadProof = '/rider/disbursements/:id/proof';
  static const String riderCollections = '/rider/collections';
  static const String riderCollectionDetails = '/rider/collections/:id';
  static const String riderRecordCollection = '/rider/collections/:id/record';
  static const String riderUploadProof = '/rider/collections/:id/proof';
  static const String riderBorrowerInfo = '/rider/collections/:id/borrower';
  static const String riderNavigateToBorrower =
      '/rider/collections/:id/navigate';
  static const String riderCi = '/rider/ci';
  static const String riderCiDetails = '/rider/ci/:id';
  static const String riderCiBorrowerInfo = '/rider/ci/:id/borrower';
  static const String riderNavigateToBorrowerCi = '/rider/ci/:id/navigate';
  static const String riderUploadCiDocuments = '/rider/ci/:id/upload';
  static const String riderSubmitCiReport = '/rider/ci/:id/submit';
  static const String riderNotifications = '/rider/notifications';
  static const String riderProfile = '/rider/profile';
  static const String riderEditProfile = '/rider/profile/edit';

  // Lender
  static const String lenderDashboard = '/lender/dashboard';
  static const String lenderAccountUpgrade = '/lender/account-upgrade';
  static const String lenderAccountUpgradeStatus =
      '/lender/account-upgrade-status';
  static const String lenderLoans = '/lender/loans';
  static const String lenderLoanDetails = '/lender/loans/:id';
  static const String lenderLoanApplicationStatus = '/lender/loan-status/:id';
  static const String lenderLoanHistory = '/lender/loan-history';
  static const String lenderPayments = '/lender/payments';
  static const String lenderPaymentHistory = '/lender/payment-history';
  static const String lenderPayViaGcash = '/lender/pay-gcash';
  static const String lenderPaymentReceipt = '/lender/receipt/:id';
  static const String lenderCollections = '/lender/collections';
  static const String lenderCollectionDetails = '/lender/collections/:id';
  static const String lenderTrackRider = '/lender/track-rider/:id';
  static const String lenderDocuments = '/lender/documents';
  static const String lenderUploadDocument = '/lender/documents/upload';
  static const String lenderNotifications = '/lender/notifications';
  static const String lenderProfile = '/lender/profile';
  static const String lenderEditProfile = '/lender/profile/edit';
}
