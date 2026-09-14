// lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/security/submission_guard.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../shared/widgets/legal_links.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/philippines_address_field.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../account_upgrade/screens/valid_id_scanner_screen.dart';
import '../../../../../data/models/loan_model.dart';
import '../../account_upgrade/providers/lender_account_upgrade_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_loan_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// Maliit na pagitan ng Back/Next row ng loan-apply wizard sa TAAS ng floating
/// bottom nav pill kapag fully scrolled na ang step — ipinapantay ang ilalim ng
/// mga button sa itaas na gilid ng bottom nav bar (8px lang ang gap, hindi na
/// dikit at hindi rin masyadong mataas).
const double kStepNavGapAbovePill = 8;

class LenderApplyLoanScreen extends ConsumerStatefulWidget {
  const LenderApplyLoanScreen({super.key});

  @override
  ConsumerState<LenderApplyLoanScreen> createState() =>
      _LenderApplyLoanScreenState();
}

class _LenderApplyLoanScreenState extends ConsumerState<LenderApplyLoanScreen> {
  static const double _minAmount = 3000;
  static const double _maxAmount = 500000;

  double _amount = 3000;
  String _frequency = 'daily';
  int? _termPeriods;
  final _purposeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _amountError;
  Timer? _previewDebounce;
  bool _previewLoading = false;
  Map<String, dynamic>? _coMaker;
  int _step = 0;
  final _coMakerFormKey = GlobalKey<_CoMakerFormState>();
  String? _coMakerSignature;
  String? _signatureError;
  // 00147: co-maker Valid ID captured with the signature (uploaded to
  // co_maker_documents so HM/employee reviewers can view it).
  // Gaya sa Account Upgrade: Front + Back scan.
  PlatformFile? _coMakerValidId;
  PlatformFile? _coMakerValidIdBack;
  String? _validIdError;

  bool get _hasCoMakerValidIdFront => _coMakerValidId != null;
  bool get _hasCoMakerValidIdBack => _coMakerValidIdBack != null;
  bool get _hasCoMakerValidIdComplete =>
      _hasCoMakerValidIdFront && _hasCoMakerValidIdBack;
  // Panandaliang "Signature confirmed" feedback para sa co-maker signature:
  // lumalabas kapag pinindot ang Confirm (3s bago mawala) at agad ding
  // nawawala kapag Clear.
  bool _showCoMakerSignatureConfirmed = false;
  Timer? _coMakerSignatureTimer;

  // 00128: financial + emergency are declared PER APPLICATION (this loan).
  final _employerNameCtrl = TextEditingController();
  final _monthlyIncomeCtrl = TextEditingController();
  final _ecNameCtrl = TextEditingController();
  final _ecPhoneCtrl = TextEditingController();
  final _monthlyIncomeFocus = FocusNode();
  // "Other" free-text blanks — lumalabas lang kapag pinili ang "Other" sa
  // katumbas na dropdown.
  final _employmentOtherCtrl = TextEditingController();
  final _sourceOtherCtrl = TextEditingController();
  final _ecRelationshipOtherCtrl = TextEditingController();
  String? _employmentType;
  String? _sourceOfFunds;
  String? _ecRelationship;
  // RPCMB emergency-contact address (required).
  final _ecAddressKey = GlobalKey<PhilippinesAddressFieldState>();
  String _ecAddress = '';

  // Scroll targets para diretso sa field na may red validation message.
  final _amountKey = GlobalKey();
  final _purposeKey = GlobalKey();
  final _employmentKey = GlobalKey();
  final _employerKey = GlobalKey();
  final _incomeKey = GlobalKey();
  final _sourceKey = GlobalKey();
  final _ecNameKey = GlobalKey();
  final _ecRelationshipKey = GlobalKey();
  final _ecPhoneKey = GlobalKey();
  final _coMakerSignatureKey = GlobalKey();
  final _coMakerValidIdKey = GlobalKey();
  final _termsKey = GlobalKey();

  /// Terms & Conditions checkbox sa Review step. Kung false, hindi
  /// makakapag-submit ng loan application.
  bool _termsAccepted = false;
  String? _termsError;

  /// Ang "Please accept the Terms and Conditions…" na validation message ay
  /// 2 segundo lang nakikita tapos awtomatikong nawawala.
  Timer? _termsErrorTimer;
  static const Duration _termsErrorVisibleFor = Duration(seconds: 2);

  /// False habang hindi pa pumipili ng loan purpose: ito ang unang full-screen
  /// na nakikita pagkapindot ng Apply Loan, bago ang Loan Details step.
  bool _purposeChosen = false;

  /// Set the first time the user taps Next on the Financial step so inline
  /// field errors become visible and stay until every field is fixed.
  bool _financialAttempted = false;

  /// True once the application was accepted — hides the skeleton/shimmer and
  /// the loan-state views that would otherwise rebuild behind the success
  /// modal while the list refreshes with the new application.
  bool _justSubmitted = false;

  /// True habang tumatakbo ang apply request — pinipigilan ang shimmer skeleton
  /// (galing sa `loadLoans`) na sumilip habang naka-loading ang Submit button.
  bool _submitting = false;

  /// True pagkatapos ma-submit ang piniling disbursement method: hindi na dapat
  /// sumilip ang "Awaiting Release"/status view sa screen na ito — deretso Home.
  bool _handedOff = false;

  static const _employmentOptions = [
    ('employed', 'Employed'),
    ('self_employed', 'Self-Employed'),
    ('business_owner', 'Business Owner'),
    ('ofw', 'OFW'),
    ('freelancer', 'Freelancer'),
    ('student', 'Student'),
    ('unemployed', 'Unemployed'),
    ('other', 'Other'),
  ];
  static const _sourceOfFundsOptions = [
    ('salary', 'Salary'),
    ('business_income', 'Business Income'),
    ('remittance', 'Remittance'),
    ('allowance', 'Allowance'),
    ('pension', 'Pension'),
    ('other', 'Other'),
  ];
  static const _relationshipOptions = [
    'Spouse',
    'Parent',
    'Sibling',
    'Child',
    'Relative',
    'Friend',
    'Colleague',
    'Employer',
    'Other',
  ];

  static const _navItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
    ),
    MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Transaction',
      route: RouteConstants.lenderPaymentHistory,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile,
    ),
  ];

  /// Mga madalas na dahilan ng loan — pinipili sa full-screen na purpose
  /// selection bago pa man makarating sa Loan Details step.
  static const List<(String, IconData)> _purposeSuggestions = [
    ('Business Capital', Icons.storefront_outlined),
    ('Emergency / Medical', Icons.local_hospital_outlined),
    ('Education', Icons.school_outlined),
    ('Home Improvement', Icons.home_work_outlined),
    ('Debt Consolidation', Icons.account_balance_outlined),
    ('Travel', Icons.flight_takeoff_outlined),
    ('Other', Icons.more_horiz),
  ];

  @override
  void initState() {
    super.initState();
    _purposeChosen = _purposeCtrl.text.trim().isNotEmpty;
    _purposeCtrl.addListener(_onPurposeChanged);
    _monthlyIncomeFocus.addListener(_normalizeIncomeOnBlur);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lenderAccountUpgradeProvider.notifier).loadStatus();
      ref.read(lenderLoanProvider.notifier).loadLoans();
      _refreshPreview();
    });
  }

  void _onPurposeChanged() {
    if (mounted) setState(() {});
  }

  /// Monthly income: kapag umalis ang focus, awtomatikong idagdag ang `.00`
  /// para laging peso-formatted ang halaga (e.g. "1,500" → "1,500.00").
  void _normalizeIncomeOnBlur() {
    if (_monthlyIncomeFocus.hasFocus) return;
    final raw =
        _monthlyIncomeCtrl.text.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (raw.isEmpty) return;
    final value = double.tryParse(raw);
    if (value == null) return;
    final formatted = NumberFormat('#,##0.00').format(value);
    if (formatted != _monthlyIncomeCtrl.text) {
      _monthlyIncomeCtrl.text = formatted;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _coMakerSignatureTimer?.cancel();
    _termsErrorTimer?.cancel();
    _purposeCtrl.removeListener(_onPurposeChanged);
    _purposeCtrl.dispose();
    _amountCtrl.dispose();
    _employerNameCtrl.dispose();
    _monthlyIncomeCtrl.dispose();
    _monthlyIncomeFocus.dispose();
    _ecNameCtrl.dispose();
    _ecPhoneCtrl.dispose();
    _employmentOtherCtrl.dispose();
    _sourceOtherCtrl.dispose();
    _ecRelationshipOtherCtrl.dispose();
    super.dispose();
  }

  // ── Validation for Next button ──
  bool get _isAmountValid =>
      _amountCtrl.text.trim().isNotEmpty &&
      _amountError == null &&
      _amount >= _minAmount &&
      _amount <= _maxAmount;

  // ── 00128: per-application financial + emergency declaration ──────────────
  double? _parseMonthlyIncome() {
    final raw =
        _monthlyIncomeCtrl.text.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  bool get _isFinancialValid {
    if (_employmentType == null) return false;
    if (_employmentType == 'other' &&
        _employmentOtherCtrl.text.trim().isEmpty) {
      return false;
    }
    if (_employerNameCtrl.text.trim().isEmpty) return false;
    final income = _parseMonthlyIncome();
    if (income == null || income <= 0) return false;
    if (_sourceOfFunds == null) return false;
    if (_sourceOfFunds == 'other' && _sourceOtherCtrl.text.trim().isEmpty) {
      return false;
    }
    if (_ecNameCtrl.text.trim().isEmpty) return false;
    final ecPhone = _ecPhoneCtrl.text.trim();
    if (ecPhone.length != 11 ||
        !ecPhone.startsWith('09') ||
        !RegExp(r'^\d{11}$').hasMatch(ecPhone)) {
      return false;
    }
    if (_ecRelationship == null) return false;
    if (_ecRelationship == 'Other' &&
        _ecRelationshipOtherCtrl.text.trim().isEmpty) {
      return false;
    }
    // Emergency contact address is required (RPCMB composite).
    if (_ecAddress.trim().isEmpty) return false;
    final addressState = _ecAddressKey.currentState;
    if (addressState != null && !addressState.isValid) return false;
    return true;
  }

  // ── Inline per-field errors (shown after the user tries to continue) ──────
  String? get _employmentTypeError =>
      _financialAttempted && _employmentType == null
          ? 'Select your employment type'
          : null;

  String? get _employerNameError =>
      _financialAttempted && _employerNameCtrl.text.trim().isEmpty
          ? 'Employer / business name is required'
          : null;

  String? get _monthlyIncomeError {
    if (!_financialAttempted) return null;
    final raw =
        _monthlyIncomeCtrl.text.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (raw.isEmpty) return 'Monthly income is required';
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return 'Enter a valid monthly income';
    if (value > 10000000) {
      return 'Monthly income cannot exceed ₱10,000,000';
    }
    return null;
  }

  String? get _sourceOfFundsError =>
      _financialAttempted && _sourceOfFunds == null
          ? 'Select your source of funds'
          : null;

  String? get _ecNameError =>
      _financialAttempted && _ecNameCtrl.text.trim().isEmpty
          ? 'Contact name is required'
          : null;

  String? get _ecRelationshipError =>
      _financialAttempted && _ecRelationship == null
          ? 'Select a relationship'
          : null;

  String? get _employmentOtherError =>
      _financialAttempted &&
              _employmentType == 'other' &&
              _employmentOtherCtrl.text.trim().isEmpty
          ? 'Please specify your employment type'
          : null;

  String? get _sourceOtherError =>
      _financialAttempted &&
              _sourceOfFunds == 'other' &&
              _sourceOtherCtrl.text.trim().isEmpty
          ? 'Please specify your source of funds'
          : null;

  String? get _ecRelationshipOtherError =>
      _financialAttempted &&
              _ecRelationship == 'Other' &&
              _ecRelationshipOtherCtrl.text.trim().isEmpty
          ? 'Please specify the relationship'
          : null;

  String? get _ecPhoneError {
    if (!_financialAttempted) return null;
    final p = _ecPhoneCtrl.text.trim();
    if (p.isEmpty) return 'Contact phone number is required';
    if (p.length != 11 ||
        !p.startsWith('09') ||
        !RegExp(r'^\d{11}$').hasMatch(p)) {
      return 'Must be an 11-digit number starting with 09';
    }
    return null;
  }

  String _formatAmountInput(int value) => NumberFormat('#,##0').format(value);

  /// Called while the user types in the amount field. Filters/validates the
  /// input, keeps the slider in sync, and refreshes the preview (debounced).
  void _onAmountTextChanged(String digits) {
    final parsed = int.tryParse(digits.replaceAll(RegExp(r'\D'), ''));
    setState(() {
      if (parsed == null || parsed == 0) {
        _amountError = 'Please enter a loan amount.';
      } else if (parsed < _minAmount || parsed > _maxAmount) {
        _amountError = 'Amount must be between ₱3,000 and ₱500,000.';
        _amount = parsed.clamp(_minAmount, _maxAmount).toDouble();
      } else {
        _amountError = null;
        _amount = parsed.toDouble();
      }
    });
    _schedulePreviewRefresh();
  }

  void _schedulePreviewRefresh() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _refreshPreview();
    });
  }

  Future<void> _refreshPreview() async {
    setState(() => _previewLoading = true);
    await ref.read(lenderLoanProvider.notifier).getSchedulePreview(
          amount: _amount,
          frequency: _frequency,
          termPeriods: _termPeriods,
        );
    // Clamp the chosen term to the new maximum so a stale selection (after the
    // amount or frequency changed) never exceeds what the server allows.
    final preview = ref.read(lenderLoanProvider).schedulePreview;
    final maxPeriods = (preview?['max_periods'] as num?)?.toInt();
    if (maxPeriods != null &&
        _termPeriods != null &&
        _termPeriods! > maxPeriods) {
      _termPeriods = null;
    }
    setState(() => _previewLoading = false);
  }

  /// Diretso sa field na may red validation message (scroll habang visible).
  void _focusOn(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  /// Unang field na may kulang sa Financial & Emergency step.
  GlobalKey _firstInvalidFinancialKey() {
    if (_employmentType == null ||
        (_employmentType == 'other' &&
            _employmentOtherCtrl.text.trim().isEmpty)) {
      return _employmentKey;
    }
    if (_employerNameCtrl.text.trim().isEmpty) return _employerKey;
    final income = _parseMonthlyIncome();
    if (income == null || income <= 0) return _incomeKey;
    if (_sourceOfFunds == null ||
        (_sourceOfFunds == 'other' && _sourceOtherCtrl.text.trim().isEmpty)) {
      return _sourceKey;
    }
    if (_ecNameCtrl.text.trim().isEmpty) return _ecNameKey;
    if (_ecRelationship == null ||
        (_ecRelationship == 'Other' &&
            _ecRelationshipOtherCtrl.text.trim().isEmpty)) {
      return _ecRelationshipKey;
    }
    if (_ecPhoneError != null) return _ecPhoneKey;
    return _ecAddressKey;
  }

  Future<void> _submit() async {
    _normalizeIncomeOnBlur();
    // ── Step 0: Loan Details ─────────────────────────────────────────────
    if (!_isAmountValid || _purposeCtrl.text.trim().isEmpty) {
      setState(() {
        _step = 0;
        if (_amountCtrl.text.trim().isEmpty) {
          _amountError = 'Please enter a loan amount.';
        }
      });
      _focusOn(!_isAmountValid ? _amountKey : _purposeKey);
      return;
    }
    // ── Step 1: Financial & Emergency ────────────────────────────────────
    setState(() => _financialAttempted = true);
    if (!_isFinancialValid) {
      setState(() => _step = 1);
      _ecAddressKey.currentState?.validate();
      _focusOn(_firstInvalidFinancialKey());
      return;
    }
    // ── Step 2: Co-Maker ─────────────────────────────────────────────────
    final cmValid = _coMakerFormKey.currentState?.validate() ?? false;
    if (!cmValid) {
      setState(() => _step = 2);
      _focusOn(_coMakerFormKey);
      return;
    }
    // ── Step 3: Signature + Valid ID ─────────────────────────────────────
    if (_coMakerSignature == null || _coMakerSignature!.isEmpty) {
      setState(() {
        _step = 3;
        _signatureError = 'Co-maker must sign the pad before submission';
      });
      _focusOn(_coMakerSignatureKey);
      return;
    }
    // 00147: co-maker Valid ID Front + Back required alongside signature.
    if (!_hasCoMakerValidIdComplete) {
      setState(() {
        _step = 3;
        if (!_hasCoMakerValidIdFront) {
          _validIdError = 'Co-maker Valid ID is required';
        } else {
          _validIdError = 'Back side of Co-maker Valid ID is required';
        }
      });
      _focusOn(_coMakerValidIdKey);
      return;
    }
    // ── Step 4: Terms & Conditions (required) ────────────────────────────
    if (!_termsAccepted) {
      setState(() => _step = 4);
      _showTermsErrorBriefly();
      _focusOn(_termsKey);
      return;
    }
    // ── Confirm modal + device credential authentication ─────────────────
    final proceed = await _confirmAndAuthenticate();
    if (!proceed || !mounted) return;

    Uint8List? validIdBytes = _coMakerValidId!.bytes;
    if (validIdBytes == null) {
      final path = _coMakerValidId!.path;
      if (path != null) validIdBytes = await File(path).readAsBytes();
    }
    final validIdExt = (_coMakerValidId!.name.split('.').lastOrNull ?? '')
        .toLowerCase();
    final validIdMime = validIdExt == 'png'
        ? 'image/png'
        : validIdExt == 'jpg' || validIdExt == 'jpeg'
            ? 'image/jpeg'
            : 'application/octet-stream';
    Uint8List? validIdBackBytes = _coMakerValidIdBack!.bytes;
    if (validIdBackBytes == null) {
      final path = _coMakerValidIdBack!.path;
      if (path != null) validIdBackBytes = await File(path).readAsBytes();
    }
    final validIdBackExt =
        (_coMakerValidIdBack!.name.split('.').lastOrNull ?? '').toLowerCase();
    final validIdBackMime = validIdBackExt == 'png'
        ? 'image/png'
        : validIdBackExt == 'jpg' || validIdBackExt == 'jpeg'
            ? 'image/jpeg'
            : 'application/octet-stream';
    final coMaker = Map<String, dynamic>.from(_coMaker ?? {})
      ..['signature'] = _coMakerSignature
      ..['valid_id_document'] = {
        if (validIdBytes != null) 'content_base64': base64Encode(validIdBytes),
        'file_name': _coMakerValidId!.name,
        'mime_type': validIdMime,
      }
      ..['valid_id_back_document'] = {
        if (validIdBackBytes != null)
          'content_base64': base64Encode(validIdBackBytes),
        'file_name': _coMakerValidIdBack!.name,
        'mime_type': validIdBackMime,
      };
    // 00128: per-loan declaration captured inside this wizard.
    final employment = {
      'type': _employmentType,
      'employer_name': _employerNameCtrl.text.trim(),
      'monthly_income': _parseMonthlyIncome(),
      if (_employmentType == 'other')
        'other_type': _employmentOtherCtrl.text.trim(),
    };
    final emergencyContacts = [
      {
        'name': _ecNameCtrl.text.trim(),
        'relationship': _ecRelationship == 'Other'
            ? (_ecRelationshipOtherCtrl.text.trim().isEmpty
                ? 'Other'
                : _ecRelationshipOtherCtrl.text.trim())
            : _ecRelationship,
        'phone_number': _ecPhoneCtrl.text.trim(),
        'address': _ecAddress.trim(),
      },
    ];

    // Nakapasa na sa confirm modal + device authentication: habang tumatakbo
    // ang request, ang Submit button sa Review step ang nagpapakita ng loading
    // spinner at nananatiling inert ang screen (`_submitting`) — walang
    // shimmer skeleton at walang status flash bago mag-modal at mag-home.
    setState(() => _submitting = true);
    final ok = await ref.read(lenderLoanProvider.notifier).applyLoan(
          amount: _amount,
          frequency: _frequency,
          termPeriods: _termPeriods,
          purpose: _purposeCtrl.text.trim(),
          employment: employment,
          sourceOfFunds: _sourceOfFunds,
          emergencyContacts: emergencyContacts,
          coMaker: coMaker,
        );

    if (!mounted) return;
    if (ok) {
      // Manatiling naka-loading ang Submit button (`_submitting` = true) at ang
      // wizard ang naka-render hanggang lumabas ang success modal — hindi ito
      // dapat huminto bago pa mag-modal. Hindi rin ito napapalitan ng shimmer
      // skeleton o ng "view status" kahit nagre-refresh ang loan list sa ilalim.
      // Success modal sits for ~2 seconds, then we go straight to Home — no
      // toast, no splash, no intermediate application-status screen.
      await SuccessDialog.showAutoDismiss(
        context,
        title: 'Successfully Submitted',
        message: 'Your loan application has been submitted successfully.',
        buttonText: 'Go to Home',
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _justSubmitted = true;
        });
        context.go(RouteConstants.lenderDashboard);
      }
    } else {
      setState(() => _submitting = false);
      final err = ref.read(lenderLoanProvider).error ?? 'An error occurred.';
      context.showSnackBarAsToast(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  /// Nagpapakita ng "Are you sure to submit this loan application?" na modal
  /// (Yes / Cancel) at pagkatapos ng Yes ay humihingi ng device credential
  /// authentication (fingerprint / Face ID, o device PIN/password fallback)
  /// bago ang final submission.
  Future<bool> _confirmAndAuthenticate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Submit Application'),
        content: const Text(
            'Are you sure you want to submit this loan application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    // Device credential (fingerprint / Face ID / device PIN) ang unang
    // hinihingi; kapag WALANG password ang phone, ang app-level MPIN ang
    // gagamitin — at kung wala pang MPIN, hihingin munang i-set ito bago
    // tuluyang maisumite ang application.
    return ref.read(submissionGuardProvider).confirm(
          context,
          reason: kSubmissionVerificationReason,
        );
  }

  void _goNext() {
    // Walang validation toast — ang bawat field ay may sariling inline (red)
    // error at direkta tayong nag-scroll sa unang kulang na field.
    if (_step == 0) {
      if (!_isAmountValid) {
        setState(() {
          if (_amountCtrl.text.trim().isEmpty) {
            _amountError = 'Please enter a loan amount.';
          }
        });
        _focusOn(_amountKey);
        return;
      }
      if (_purposeCtrl.text.trim().isEmpty) {
        _focusOn(_purposeKey);
        return;
      }
    } else if (_step == 1) {
      // Financial Details + Emergency Contact — reveal inline field errors on
      // the first attempt so the user sees exactly what is missing.
      _normalizeIncomeOnBlur();
      setState(() => _financialAttempted = true);
      if (!_isFinancialValid) {
        _ecAddressKey.currentState?.validate();
        _focusOn(_firstInvalidFinancialKey());
        return;
      }
    } else if (_step == 2) {
      final valid = _coMakerFormKey.currentState?.validate() ?? false;
      if (!valid) {
        _focusOn(_coMakerFormKey);
        return;
      }
    } else if (_step == 3) {
      if (_coMakerSignature == null || _coMakerSignature!.isEmpty) {
        setState(() =>
            _signatureError = 'Co-maker must sign the pad before submission');
        _focusOn(_coMakerSignatureKey);
        return;
      }
      // 00147: co-maker Valid ID Front + Back required before moving on.
      if (!_hasCoMakerValidIdComplete) {
        setState(() => _validIdError = !_hasCoMakerValidIdFront
            ? 'Co-maker Valid ID is required'
            : 'Back side of Co-maker Valid ID is required');
        _focusOn(_coMakerValidIdKey);
        return;
      }
    }
    setState(() => _step = _step + 1);
  }

  void _goBack() => setState(() => _step = _step - 1);

  String _termUnit() {
    switch (_frequency) {
      case 'daily':
        return 'days';
      case 'weekly':
        return 'weeks';
      default:
        return 'months';
    }
  }

  /// Common term choices for the selected frequency, capped by the server's
  /// maximum for the current amount. The max value is always included so the
  /// default (full) term stays selectable.
  List<int> _termOptions(int max) {
    if (_frequency == 'daily') {
      // Daily term choices run from 1 day up to 40 days (capped by the server
      // maximum, which is at least 40 for every valid amount).
      final last = max < 40 ? max : 40;
      return [for (int i = 1; i <= last; i++) i];
    }
    const candidates = <String, List<int>>{
      'weekly': [1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 26],
      'monthly': [1, 2, 3, 4, 5, 6],
    };
    final opts = (candidates[_frequency] ?? const <int>[])
        .where((v) => v <= max)
        .toList();
    if (!opts.contains(max)) opts.add(max);
    return opts;
  }

  /// Effective term label used in the review step and the submit dialog, e.g.
  /// "6 weeks", "30 days", or "2 months".
  String _termLabel() {
    final preview = ref.read(lenderLoanProvider).schedulePreview;
    final max = (preview?['max_periods'] as num?)?.toInt() ?? 0;
    final periods = _termPeriods ?? max;
    if (periods <= 0) return 'the full term';
    final unit = _termUnit();
    final singular =
        unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit;
    return '$periods ${periods == 1 ? singular : unit}';
  }

  Widget _buildTermSelector(int maxPeriods) {
    if (maxPeriods < 1) return const SizedBox.shrink();
    final unit = _termUnit();
    final options = _termOptions(maxPeriods);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Loan Term'),
        const SizedBox(height: 4),
        const Text(
          'Choose how long you want to repay this loan.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        // Pantay-pantay na lapad ang bawat card (3 kada row) para malinis ang
        // grid — dating `Wrap` na kanya-kanyang lapad ayon sa haba ng label
        // kaya "kalat kalat" ang ayos.
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            const perRow = 3;
            final cardWidth =
                (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: options.map((value) {
                final isMax = value == maxPeriods;
                final selected =
                    isMax ? _termPeriods == null : _termPeriods == value;
                final label =
                    '$value ${value == 1 && unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit}';
                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    onTap: () {
                      setState(() => _termPeriods = isMax ? null : value);
                      _refreshPreview();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.lenderBlue : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              selected ? AppColors.lenderBlue : AppColors.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color:
                                selected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  /// Bottom padding ng naka-PIN na Back/Next row: nakapatong ito sa TAAS ng
  /// floating bottom nav bar — safe area + float gap (36) + pill height (74) +
  /// [kStepNavGapAbovePill] na maliit na pagitan — kaya hindi dikit sa pill at
  /// hindi rin masyadong mataas.
  double get _stepNavBottomPadding =>
      MediaQuery.paddingOf(context).bottom +
      kFloatingNavFloatGap +
      kFloatingNavPillHeight +
      kStepNavGapAbovePill;

  Widget _buildLoanDetailsStep(
      NumberFormat fmt, Map<String, dynamic>? preview, bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Loan Amount'),
          const SizedBox(height: 4),
          TextField(
            key: _amountKey,
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _PesoAmountFormatter(),
            ],
            onChanged: _onAmountTextChanged,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.lenderBlue,
            ),
            decoration: InputDecoration(
              prefixText: '₱ ',
              prefixStyle: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.lenderBlue,
              ),
              hintText: 'Enter amount',
              hintStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
              errorText: _amountError,
              errorStyle: const TextStyle(fontSize: 12),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.lenderBlue),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color:
                      _amountError != null ? AppColors.error : AppColors.border,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Slider(
            value: _amount,
            min: _minAmount,
            max: _maxAmount,
            activeColor: AppColors.lenderBlue,
            inactiveColor: AppColors.lenderBlue.withValues(alpha: 0.2),
            onChanged: (v) {
              final rounded = (v / 1000).round() * 1000.0;
              setState(() {
                _amount = rounded;
                _amountError = null;
                _amountCtrl.text = _formatAmountInput(rounded.toInt());
              });
            },
            onChangeEnd: (_) => _refreshPreview(),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₱3,000',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text('₱500,000',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Payment Frequency'),
          const SizedBox(height: 10),
          Row(
            children: ['daily', 'weekly', 'monthly'].map((f) {
              final selected = f == _frequency;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _frequency = f;
                        _termPeriods = null;
                      });
                      _refreshPreview();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.lenderBlue : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.lenderBlue
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        f[0].toUpperCase() + f.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _buildTermSelector((preview?['max_periods'] as num?)?.toInt() ?? 0),
          const SizedBox(height: 20),
          const _SectionTitle('Purpose'),
          const SizedBox(height: 8),
          // Pinili na ang purpose sa full-screen na purpose selection bago
          // mapindot ang Apply Loan — read-only summary na lang ito dito.
          Container(
            key: _purposeKey,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _purposeCtrl.text.trim().isEmpty
                    ? AppColors.error
                    : AppColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _purposeCtrl.text.trim().isEmpty
                        ? 'Please choose a loan purpose.'
                        : _purposeCtrl.text.trim(),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _purposeCtrl.text.trim().isEmpty
                          ? AppColors.error
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _purposeChosen = false),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.lenderBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SchedulePreview(preview: preview, loading: _previewLoading),
        ],
      ),
    );
  }

  Widget _buildCoMakerStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Co-Maker Information'),
          const SizedBox(height: 6),
          const Text(
            'A co-maker is required for your loan application. You will be asked for their signature on the next step.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          _CoMakerForm(
            key: _coMakerFormKey,
            onChanged: (value) {
              setState(() => _coMaker = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Co-Maker Signature'),
          const SizedBox(height: 6),
          const Text(
            'Ask your co-maker to sign below to consent to this loan.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            key: _coMakerSignatureKey,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SignaturePad(
                  onSignatureChanged: (sig) {
                    // Kapag na-confirm (at kapag na-clear), agad nawawala ang
                    // status at validation text — hindi ito nananatiling
                    // naka-display.
                    setState(() {
                      _coMakerSignature = sig;
                      _signatureError = null;
                    });
                  },
                  onConfirmed: () {
                    // Panandaliang kumpirmasyon: 3 segundo lang tapos mawawala.
                    _coMakerSignatureTimer?.cancel();
                    setState(() => _showCoMakerSignatureConfirmed = true);
                    _coMakerSignatureTimer =
                        Timer(const Duration(seconds: 3), () {
                      if (mounted) {
                        setState(() => _showCoMakerSignatureConfirmed = false);
                      }
                    });
                  },
                  onCleared: () {
                    _coMakerSignatureTimer?.cancel();
                    if (_showCoMakerSignatureConfirmed) {
                      setState(() => _showCoMakerSignatureConfirmed = false);
                    }
                  },
                  height: 200,
                ),
                if (_showCoMakerSignatureConfirmed) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.success),
                      SizedBox(width: 6),
                      Text(
                        'Signature confirmed',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                if (_signatureError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _signatureError!,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 00147: co-maker Valid ID Front + Back — gaya sa Account Upgrade
          // scanner. Card lang ito (tap para mag-scan/upload) — walang
          // filename row, View buttons o Upload button sa ilalim.
          Container(
            key: _coMakerValidIdKey,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hasCoMakerValidIdComplete
                  ? AppColors.lenderBlue.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _validIdError != null
                    ? AppColors.error
                    : _hasCoMakerValidIdComplete
                        ? AppColors.lenderBlue.withValues(alpha: 0.3)
                        : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: isSubmitting ? null : _pickCoMakerValidId,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Image.asset(
                          'assets/icons/id_card.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.contact_page_rounded,
                              size: 32,
                              color: AppColors.textTertiary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Co-Maker Valid ID *',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              _hasCoMakerValidIdComplete
                                  ? 'Front ✓  •  Back ✓'
                                  : _hasCoMakerValidIdFront
                                      ? 'Front ✓  •  Back missing — tap to add'
                                      : "Front + Back of co-maker's government-issued ID",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _hasCoMakerValidIdComplete
                                      ? AppColors.lenderBlue
                                      : AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                          _hasCoMakerValidIdComplete
                              ? Icons.check_circle
                              : Icons.upload_file_outlined,
                          color: _hasCoMakerValidIdComplete
                              ? AppColors.success
                              : AppColors.textTertiary),
                    ],
                  ),
                ),
                if (_validIdError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validIdError!,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 00147: Co-maker Valid ID Front + Back — gaya sa Account Upgrade.
  /// Camera = ValidIdScannerScreen (front + back scan), gallery = up to 2 files.
  Future<void> _pickCoMakerValidId() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Co-Maker Valid ID',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.lenderBlue),
              title: const Text('Scan Front & Back'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.lenderBlue),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'camera') {
      final result = await Navigator.of(context).push<IdScanResult>(
        MaterialPageRoute(builder: (_) => const ValidIdScannerScreen()),
      );
      if (result != null && mounted) {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          _coMakerValidId = PlatformFile(
            name: 'comaker_valid_id_front_$stamp.jpg',
            size: result.frontBytes.length,
            bytes: result.frontBytes,
          );
          _coMakerValidIdBack = PlatformFile(
            name: 'comaker_valid_id_back_$stamp.jpg',
            size: result.backBytes.length,
            bytes: result.backBytes,
          );
          _validIdError = null;
        });
      }
      return;
    } else if (action == 'gallery') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      setState(() {
        final files = result.files;
        if (_hasCoMakerValidIdFront &&
            !_hasCoMakerValidIdBack &&
            files.length == 1) {
          _coMakerValidIdBack = files.first;
        } else {
          _coMakerValidId = files.first;
          if (files.length > 1) {
            _coMakerValidIdBack = files[1];
          } else {
            _coMakerValidIdBack = null;
          }
        }
        _validIdError = null;
      });
    }
  }

  /// 00128: borrower declares employment/income/source of funds + emergency
  /// contact FOR THIS APPLICATION. Stored on the loan record (not profile).
  Widget _buildFinancialEmergencyStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Financial Details'),
          const SizedBox(height: 6),
          const Text(
            'Tell us about your source of income. This declaration is attached to this loan application.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: _employmentKey,
                  initialValue: _employmentType,
                  decoration: _finFieldDeco('Employment Type'),
                  items: _employmentOptions
                      .map((e) =>
                          DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _employmentType = v),
                ),
                if (_employmentTypeError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _employmentTypeError!,
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.error),
                  ),
                ],
                // "Other" → bigyan ng blank na pwedeng sagutan ng user.
                if (_employmentType == 'other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _employmentOtherCtrl,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    scrollPadding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                    decoration: _finFieldDeco('Please specify employment type',
                        errorText: _employmentOtherError),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: _employerKey,
                  controller: _employerNameCtrl,
                  maxLength: 255,
                  onChanged: (_) => setState(() {}),
                  scrollPadding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                  decoration: _finFieldDeco('Employer / Business Name',
                      errorText: _employerNameError),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: _incomeKey,
                  controller: _monthlyIncomeCtrl,
                  focusNode: _monthlyIncomeFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    _PesoIncomeFormatter(),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: _finFieldDeco('Monthly Income',
                      errorText: _monthlyIncomeError, prefixText: '₱ '),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: _sourceKey,
                  initialValue: _sourceOfFunds,
                  decoration: _finFieldDeco('Source of Funds'),
                  items: _sourceOfFundsOptions
                      .map((e) =>
                          DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _sourceOfFunds = v),
                ),
                if (_sourceOfFundsError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _sourceOfFundsError!,
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.error),
                  ),
                ],
                if (_sourceOfFunds == 'other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sourceOtherCtrl,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    scrollPadding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                    decoration: _finFieldDeco('Please specify source of funds',
                        errorText: _sourceOtherError),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Emergency Contact'),
          const SizedBox(height: 6),
          const Text(
            'Who should we contact in case of an emergency regarding this loan?',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: _ecNameKey,
                  controller: _ecNameCtrl,
                  maxLength: 100,
                  onChanged: (_) => setState(() {}),
                  scrollPadding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                  decoration:
                      _finFieldDeco('Contact Name', errorText: _ecNameError),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: _ecRelationshipKey,
                  initialValue: _ecRelationship,
                  decoration: _finFieldDeco('Relationship'),
                  items: _relationshipOptions
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _ecRelationship = v),
                ),
                if (_ecRelationshipError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _ecRelationshipError!,
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.error),
                  ),
                ],
                if (_ecRelationship == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ecRelationshipOtherCtrl,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    scrollPadding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                    decoration: _finFieldDeco('Please specify relationship',
                        errorText: _ecRelationshipOtherError),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: _ecPhoneKey,
                  controller: _ecPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: _finFieldDeco('Contact Phone Number',
                      errorText: _ecPhoneError),
                ),
                const SizedBox(height: 12),
                // Required na; RPCMB cascading address (Region → Barangay).
                PhilippinesAddressField(
                  key: _ecAddressKey,
                  onChanged: (v) => setState(() => _ecAddress = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _finFieldDeco(String label,
      {String? errorText, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      errorText: errorText,
      errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.error),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lenderBlue),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: errorText != null ? AppColors.error : AppColors.border,
        ),
      ),
    );
  }

  Widget _buildReviewStep(
      NumberFormat fmt, Map<String, dynamic>? preview, bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final interest = preview == null ? null : (preview['interest'] ?? 0);
    final totalPayable =
        preview == null ? null : (preview['total_payable'] ?? 0);
    final installment =
        preview == null ? null : (preview['installment_amount'] ?? 0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Review Details'),
          const SizedBox(height: 6),
          const Text(
            'Please review the details below. If everything is correct, submit your application.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          // Review Details = loan amounts lang. Hindi na kasama dito ang
          // co-maker, financial & emergency declaration (nasa kani-kanilang
          // step na sila) para malinis at madaling i-review ang application.
          _ReviewCard(
            amount: _amount,
            frequency: _frequency,
            termLabel: _termLabel(),
            purpose: _purposeCtrl.text.trim(),
            fmt: fmt,
            interest: interest,
            totalPayable: totalPayable,
            installment: installment,
          ),
        ],
      ),
    );
  }

  /// Terms & Conditions validation: pinapakita ang mensahe nang 2 segundo lang
  /// tapos awtomatikong nawawala — hindi nananatiling nakabalandra ang red card.
  void _showTermsErrorBriefly() {
    _termsErrorTimer?.cancel();
    setState(() => _termsError =
        'Please accept the Terms and Conditions to submit your application.');
    _termsErrorTimer = Timer(_termsErrorVisibleFor, () {
      if (mounted) setState(() => _termsError = null);
    });
  }

  /// Terms & Conditions checkbox — REQUIRED bago maka-submit ng application.
  /// Kung hindi naka-check, hindi tumutuloy ang submission at may inline na
  /// red na mensahe sa ibaba ng checkbox.
  Widget _buildTermsCheckbox() {
    return Container(
      key: _termsKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: _termsError == null
            ? Colors.white
            : AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _termsError == null ? AppColors.border : AppColors.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _termsAccepted,
                activeColor: AppColors.lenderBlue,
                onChanged: (v) => setState(() {
                  _termsAccepted = v ?? false;
                  if (_termsAccepted) {
                    _termsErrorTimer?.cancel();
                    _termsError = null;
                  }
                }),
              ),
              Expanded(
                // Buong text ay tappable — bubukas ang Terms & Conditions sa
                // bottom sheet. Ang checkbox pa rin ang nag-a-accept.
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showTermsAndConditionsSheet(context),
                    child: const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'I have read and agree to the '),
                          TextSpan(
                            text: 'Terms and Conditions',
                            style: TextStyle(
                              color: AppColors.lenderBlue,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.lenderBlue,
                            ),
                          ),
                          TextSpan(
                            text:
                                ', and I certify that all information I provided is true and correct.',
                          ),
                        ],
                      ),
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_termsError != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                _termsError!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }

  /// Naka-PIN na nav row (Back/Next o Submit) sa ibaba ng wizard — nakapatong
  /// mismo sa ibabaw ng floating bottom nav bar, kaya hindi na kailangang
  /// mag-scroll ng user para makita ang mga button.
  Widget _buildStepNav(bool isSubmitting) {
    final isLast = _step == 4;
    // Next/Submit stay tappable so the step validators can run and surface
    // inline errors; the individual step handlers perform the real checks.
    final canProceed = !isSubmitting;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, _stepNavBottomPadding),
      child: Row(
        children: [
          // BACK at NEXT ay magkatabi sa kanan (dati, nasa kabilang dulo ang
          // Back kaya may malaking bakanteng gitna).
          const Spacer(),
          if (_step > 0) ...[
            _NavTextButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: isSubmitting ? null : _goBack,
            ),
            const SizedBox(width: 12),
          ],
          if (isLast)
            AppButton(
              label: 'Submit Application',
              icon: Icons.send,
              color: AppColors.lenderBlue,
              isLoading: isSubmitting,
              onTap: canProceed ? _submit : null,
            )
          else
            _NavTextButton(
              icon: Icons.arrow_forward_rounded,
              label: 'Next',
              // Arrow pagkatapos ng label: "Next →".
              iconAfterLabel: true,
              onTap: canProceed ? _goNext : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(lenderLoanProvider);
    final accountUpgradeState = ref.watch(lenderAccountUpgradeProvider);
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final upgradeStatus = accountUpgradeState.status;
    final needsUpgrade =
        upgradeStatus != 'verified' && upgradeStatus != 'approved';
    final scaffoldTitle = (accountUpgradeState.isLoading || loanState.isLoading)
        ? ''
        : (upgradeStatus == 'submitted' ||
                upgradeStatus == 'pending' ||
                upgradeStatus == 'under_review')
            ? 'Account Upgrade Status'
            : (needsUpgrade ? 'Upgrade Account' : '');

    return MobileScaffold(
      title: scaffoldTitle,
      accentColor: AppColors.lenderBlue,
      navItems: _navItems,
      showBackButton: true,
      centerTitle: scaffoldTitle == 'Account Upgrade Status',
      body: (_justSubmitted || _handedOff)
          // Submission accepted (o katatapos lang pumili ng disbursement
          // method): manatiling inert ang screen sa likod ng success modal,
          // PERO hindi blangkong PUTING screen — may malinaw na feedback
          // habang tinatapos ang request bago pumunta sa Home.
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.lenderBlue),
                  SizedBox(height: 16),
                  Text(
                    'Finalizing your request…',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          // Habang nagsu-submit (`_submitting`) manatili ang wizard na may
          // loading na Submit button — hindi dapat sumilip ang shimmer
          // skeleton o ang loan-state/status views bago mag-modal at mag-home.
          : _submitting
              ? _buildWizardStepContent(
                  fmt, loanState.schedulePreview, _submitting)
              : (loanState.isLoading || accountUpgradeState.isLoading)
                  ? const _LenderApplyLoanSkeleton()
                  : _buildFlow(loanState, accountUpgradeState, fmt),
    );
  }

  Widget _buildFlow(LenderLoanState loanState,
      LenderAccountUpgradeState accountUpgradeState, NumberFormat fmt) {
    final accountUpgrade = accountUpgradeState.status;
    final loans = loanState.loans;
    final activeLoan = loanState.activeLoan;

    final dob = ref.watch(lenderProfileProvider).user?.dateOfBirth;
    if (dob != null && !_isAdult(dob)) {
      return const _AgeGateView();
    }

    // When documents are already submitted/under review, pressing "Apply Now"
    // should directly show the Account Upgrade Status (timeline) instead of
    // a gate with a "View Status" button — render inline without splash/redirect.
    if (accountUpgrade == 'submitted' ||
        accountUpgrade == 'pending' ||
        accountUpgrade == 'under_review') {
      return _InlineSubmittedTimeline(accountUpgradeState: accountUpgradeState);
    }

    if (accountUpgrade != 'verified' && accountUpgrade != 'approved') {
      return _AccountUpgradeGate(state: accountUpgradeState);
    }
    // Approved-but-not-yet-released loan → lender chooses how to receive funds.
    final approvedLoan = _approvedUnreleasedLoan(loans);
    if (approvedLoan != null) {
      return _ChooseDisbursementView(
        loan: approvedLoan,
        onConfirmed: () {
          if (mounted) setState(() => _handedOff = true);
        },
      );
    }
    // Approved loan with a method already chosen → waiting for the office / rider.
    final awaitingRelease = _awaitingReleaseLoan(loans);
    if (awaitingRelease != null) {
      return _AwaitingReleaseView(loan: awaitingRelease);
    }
    if (activeLoan != null) {
      return _ActiveLoanView(loan: activeLoan);
    }
    final reviewLoan = _underReviewLoan(loans);
    if (reviewLoan != null) {
      return _ApplicationReviewView(loan: reviewLoan);
    }

    // Bago ang mismong wizard: full-screen na loan purpose selection. Dito
    // na pinipili ang purpose, kaya wala nang purpose field sa Loan Details.
    if (!_purposeChosen) {
      return _LoanPurposePicker(
        suggestions: _purposeSuggestions,
        onSelected: (purpose) {
          setState(() {
            _purposeCtrl.text = purpose;
            _purposeChosen = true;
          });
          _refreshPreview();
        },
      );
    }

    final state = loanState;
    final preview = state.schedulePreview;
    return _buildWizardStepContent(fmt, preview, state.isSubmitting);
  }

  /// Ang wizard mismo (step indicator + kasalukuyang step). Hiwalay ito para
  /// manatili itong naka-render habang nagsu-submit — hindi ito dapat mapalitan
  /// ng loan-state views ("view status") bago mag-modal at mag-home.
  Widget _buildWizardStepContent(
      NumberFormat fmt, Map<String, dynamic>? preview, bool isSubmitting) {
    return Column(
      children: [
        _StepIndicator(current: _step),
        Expanded(
          child: IndexedStack(
            index: _step,
            children: [
              _buildLoanDetailsStep(fmt, preview, isSubmitting),
              _buildFinancialEmergencyStep(isSubmitting),
              _buildCoMakerStep(isSubmitting),
              _buildSignatureStep(isSubmitting),
              _buildReviewStep(fmt, preview, isSubmitting),
            ],
          ),
        ),
        // Review step: ang Terms & Conditions checkbox card ay NAKA-PIN din —
        // nasa ibaba, sa ibabaw mismo ng Back/Submit button — kaya laging
        // nakikita bago mag-submit.
        if (_step == 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildTermsCheckbox(),
          ),
        // Back/Next (o Submit) na naka-pin sa TAAS ng floating bottom nav bar —
        // hindi na ito kasama sa scroll ng step, kaya laging nakikita.
        _buildStepNav(isSubmitting),
      ],
    );
  }

  bool _isAdult(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 18;
  }

  /// A loan that was approved but the lender has NOT yet chosen a disbursement
  /// method. The lender must pick how they want to receive the funds first.
  LoanModel? _approvedUnreleasedLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' &&
          loan.disbursedAt == null &&
          loan.disbursementMethod == null) {
        return loan;
      }
    }
    return null;
  }

  /// A loan that was approved, the lender already picked their method, but the
  /// funds have not been released yet (awaiting rider / office fulfilment).
  LoanModel? _awaitingReleaseLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' &&
          loan.disbursedAt == null &&
          loan.disbursementMethod != null) {
        return loan;
      }
    }
    return null;
  }

  LoanModel? _underReviewLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if ([
        'pending',
        'under_review',
        'ci_required',
        'ci_assigned',
        'ci_completed',
      ].contains(loan.status)) {
        return loan;
      }
    }
    return null;
  }
}

class _CoMakerForm extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>?> onChanged;
  const _CoMakerForm({super.key, required this.onChanged});

  @override
  State<_CoMakerForm> createState() => _CoMakerFormState();
}

class _CoMakerFormState extends State<_CoMakerForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationshipOtherCtrl = TextEditingController();
  final _addressKey = GlobalKey<PhilippinesAddressFieldState>();
  String _address = '';
  String? _relationship;
  DateTime? _dob;
  String? _dobError;

  static const _relationshipOptions = [
    'Spouse',
    'Parent',
    'Sibling',
    'Child',
    'Relative',
    'Friend',
    'Colleague',
    'Employer',
    'Other',
  ];

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _relationshipOtherCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final map = <String, dynamic>{
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'relationship': _relationship,
      'address': _address,
      'date_of_birth': _dob?.toIso8601String().substring(0, 10),
    };
    widget.onChanged(map);
  }

  bool validate() {
    final dobOk = _dob != null;
    setState(() {
      _dobError = dobOk ? null : 'Date of birth is required';
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    final addressOk = _addressKey.currentState?.validate() ?? false;
    return formOk && dobOk && addressOk;
  }

  Future<void> _pickDob() async {
    // Isara ang keyboard bago buksan ang date picker. Kung may naka-focus pa
    // (hal. Street / House No. ng address), ibinabalik ito ng Flutter pagkatapos
    // magsara ng picker — kaya "nagiging active" ulit ang street field at
    // natatakpan ng keyboard ang form/Next kahit may date of birth na.
    FocusScope.of(context).unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.lenderBlue,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = null;
      });
      _emit();
    }
    // Ang focus restoration ng dialog ay nangyayari pagkatapos ng pop
    // animation (~200ms), kaya dito pa lang siguradong hindi na nagiging active
    // muli ang street field.
    if (mounted) FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.groups_outlined,
                    color: AppColors.lenderBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'Co-Maker',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstCtrl,
              onChanged: (_) => _emit(),
              maxLength: 100,
              scrollPadding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 120),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'First name is required'
                  : null,
              decoration: _coFieldDeco('First Name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _lastCtrl,
              onChanged: (_) => _emit(),
              maxLength: 100,
              scrollPadding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 120),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Last name is required'
                  : null,
              decoration: _coFieldDeco('Last Name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              onChanged: (_) => _emit(),
              maxLength: 11,
              scrollPadding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 120),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Contact number is required';
                }
                final digits = v.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 11 || !digits.startsWith('09')) {
                  return 'Must be an 11-digit number starting with 09';
                }
                return null;
              },
              decoration: _coFieldDeco('Contact Number'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _relationship,
              decoration: _coFieldDeco('Relationship'),
              validator: (v) => v == null ? 'Relationship is required' : null,
              items: _relationshipOptions
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (v) {
                setState(() => _relationship = v);
                _emit();
              },
            ),
            // "Other" → blank na pwedeng sagutan ng user.
            if (_relationship == 'Other') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _relationshipOtherCtrl,
                onChanged: (_) => _emit(),
                maxLength: 100,
                scrollPadding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please specify the relationship'
                    : null,
                decoration: _coFieldDeco('Please specify relationship'),
              ),
            ],
            const SizedBox(height: 10),
            // Co-maker address — RPCMB cascading (Region → Barangay).
            PhilippinesAddressField(
              key: _addressKey,
              onChanged: (v) {
                setState(() => _address = v);
                _emit();
              },
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDob,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: _coFieldDeco('Date of Birth').copyWith(
                  errorText: _dobError,
                  errorStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(
                  _dob == null
                      ? 'Select date'
                      : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _dob == null
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'You will be asked for the co-maker\'s signature on the next step.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _coFieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lenderBlue),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }
}

/// Plain text nav button used in the wizard bar — an arrow followed by its
/// label (e.g. "→ Next"), with no box or background around it.
///
/// Kapag [iconAfterLabel] (hal. "Next →"), pagkatapos ng label ang arrow.
class _NavTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool iconAfterLabel;
  const _NavTextButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconAfterLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppColors.lenderBlue : AppColors.textTertiary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconAfterLabel) ...[
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (iconAfterLabel) ...[
                const SizedBox(width: 6),
                Icon(icon, color: color, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Reformats the amount as it is typed: digits only, with thousand separators
/// (e.g. 15000 -> "15,000").
class _PesoAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final value = int.tryParse(digits) ?? 0;
    final formatted = NumberFormat('#,##0').format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Monthly Income: auto-formats as peso (thousands separators, up to 2
/// decimals) so the value reads as ₱1,500.00 while typing. Digits-only input
/// is capped at 10M so `_monthlyIncomeError` can surface a clear message
/// instead of silently swallowing keystrokes.
class _PesoIncomeFormatter extends TextInputFormatter {
  static const double _maxIncome = 10000000;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(RegExp(r'[₱, ]'), '');
    // Only digits and one decimal point.
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    // Enforce a single decimal separator.
    var body = cleaned;
    if (cleaned.split('.').length > 2) {
      final first = cleaned.indexOf('.');
      body = cleaned.substring(0, first + 1) +
          cleaned.substring(first + 1).replaceAll('.', '');
    }
    // Cap decimals at 2 places.
    var dot = body.indexOf('.');
    if (dot != -1 && body.length - dot - 1 > 2) {
      body = body.substring(0, dot + 3);
    }
    // Reject values above the cap (truncate until within range, so pasting a
    // huge number can never exceed ₱10M).
    while (body.isNotEmpty &&
        (double.tryParse(body) ?? 0) > _maxIncome) {
      body = body.substring(0, body.length - 1);
    }
    // Recompute after any truncation above so the split below stays valid.
    dot = body.indexOf('.');

    final intPart = dot == -1 ? body : body.substring(0, dot);
    final decPart = dot == -1 ? '' : body.substring(dot);
    final formatted = intPart.isEmpty
        ? body
        : '${NumberFormat('#,##0').format(int.tryParse(intPart) ?? 0)}$decPart';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      );
}

class _SchedulePreview extends StatelessWidget {
  final Map<String, dynamic>? preview;
  final bool loading;
  const _SchedulePreview({this.preview, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.lenderBlue));
    }
    final preview = this.preview;
    if (preview == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text('Unable to load payment schedule. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final principal = (preview['principal'] ?? 0).toDouble();
    final totalPayable = (preview['total_payable'] ?? 0).toDouble();
    final interest =
        (preview['interest'] ?? preview['interest_amount'] ?? 0).toDouble();
    final installment = (preview['installment_amount'] ?? 0).toDouble();
    final installments = preview['installments'] ?? 0;
    final freq = (preview['frequency'] ?? '').toString();
    final termUnit =
        freq == 'weekly' ? 'weeks' : (freq == 'monthly' ? 'months' : 'days');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.lenderBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Payment Schedule Preview',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _PreviewRow('Loan Amount', '₱${fmt.format(principal)}',
                    AppColors.textPrimary),
                _PreviewRow('Interest (20%)', '₱${fmt.format(interest)}',
                    AppColors.warning),
                _PreviewRow('Total Payable', '₱${fmt.format(totalPayable)}',
                    AppColors.lenderBlue),
                _PreviewRow('Per Installment', '₱${fmt.format(installment)}',
                    AppColors.success),
                _PreviewRow('Number of Periods', '$installments',
                    AppColors.textSecondary),
                _PreviewRow(
                    'Term', '$installments $termUnit', AppColors.textSecondary),
                const Divider(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _PreviewRow(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor)),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});

  static const _labels = [
    'Loan Details',
    'Financial & Emergency',
    'Co-Maker',
    'Signature',
    'Review',
  ];

  /// Pantay na lapad para sa bawat step. Dating nakasentro ang mga bilog sa
  /// lapad ng kani-kanilang label ("Financial & Emergency" ang pinakamahaba),
  /// kaya hindi pantay ang espasyo ng 1, 2, 3...
  static const double _stepWidth = 62;

  /// Taas ng kahon ng bilog — pareho para sa lahat kaya pantay ang linya.
  static const double _dotBoxHeight = 32;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bilog + connecting line. Nakasentro ang bilog sa fixed-width na
          // kahon, at nakasentro din ang line sa taas ng kahon — kaya pantay.
          Row(
            children: [
              for (int i = 0; i < _labels.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i <= current
                          ? AppColors.lenderBlue
                          : AppColors.border,
                    ),
                  ),
                SizedBox(
                  width: _stepWidth,
                  height: _dotBoxHeight,
                  child: Center(
                    child: _StepDot(
                      index: i,
                      isActive: i == current,
                      isDone: i < current,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Labels sa ilalim — KAPAREHONG layout (fixed width + Expanded
          // spacer) para eksaktong nakasentro sa ilalim ng kani-kanilang bilog.
          // `FittedBox` ang humahawak sa mahahabang label (lumiit, hindi putol).
          Row(
            children: [
              for (int i = 0; i < _labels.length; i++) ...[
                if (i > 0) const Expanded(child: SizedBox()),
                SizedBox(
                  width: _stepWidth,
                  height: 14,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _labels[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: i == current
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i <= current
                              ? AppColors.lenderBlue
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Bilog na may numero (o check kapag tapos na). Walang label dito — nasa
/// [_StepIndicator] na hiwalay na row ang mga label para pantay ang alignment.
class _StepDot extends StatelessWidget {
  final int index;
  final bool isActive;
  final bool isDone;
  const _StepDot({
    required this.index,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = isActive || isDone;
    final size = isActive ? 30.0 : 24.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlighted ? AppColors.lenderBlue : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted ? AppColors.lenderBlue : AppColors.border,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: isDone
          ? const Icon(Icons.check, color: Colors.white, size: 14)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final double amount;
  final String frequency;
  final String termLabel;
  final String purpose;
  final NumberFormat fmt;
  final dynamic interest;
  final dynamic totalPayable;
  final dynamic installment;
  const _ReviewCard({
    required this.amount,
    required this.frequency,
    required this.termLabel,
    required this.purpose,
    required this.fmt,
    this.interest,
    this.totalPayable,
    this.installment,
  });

  @override
  Widget build(BuildContext context) {
    // Naka-card para malinis at hindi nakakalat ang review details sa page.
    // Kapareho ng style ng terms card sa ibaba (puti + border + radius 12).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            'Loan Amount',
            '₱${fmt.format(amount)}',
          ),
          _row(
            'Payment Frequency',
            frequency[0].toUpperCase() + frequency.substring(1),
          ),
          _row('Loan Term', termLabel),
          _row('Purpose', purpose.isEmpty ? '-' : purpose),
          if (interest != null) ...[
            _row('Interest (20%)',
                '₱${fmt.format((interest as num).toDouble())}'),
          ],
          if (totalPayable != null) ...[
            _row('Total Payable',
                '₱${fmt.format((totalPayable as num).toDouble())}'),
          ],
          if (installment != null) ...[
            _row('Per Installment',
                '₱${fmt.format((installment as num).toDouble())}'),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 146,
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _AccountUpgradeGate extends StatelessWidget {
  final LenderAccountUpgradeState state;
  const _AccountUpgradeGate({required this.state});

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    final isSubmitted = status == 'submitted' || status == 'pending';
    final isRejected = status == 'rejected';

    // Rejected: no icon, text "Account upgrade submission rejected" + button only.
    if (isRejected) {
      final inCooldown = state.isInCooldown;
      final days = state.cooldownDaysRemaining;
      final resubmit = state.resubmitAfter;
      String? cooldownLine;
      if (inCooldown) {
        cooldownLine = (days != null && days > 0)
            ? (resubmit != null
                ? 'You may resubmit after 1 month (${resubmit.toLocal().toString().substring(0, 10)}). $days day(s) remaining.'
                : 'You may resubmit after 1 month. $days day(s) remaining.')
            : 'You may resubmit after 1 month.';
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Account upgrade submission rejected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (cooldownLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  cooldownLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (inCooldown)
                AppButton(
                  label: days != null && days > 0
                      ? 'Resubmit after $days day(s)'
                      : 'Resubmit unavailable',
                  onPressed: null,
                  color: AppColors.lenderBlue,
                  icon: Icons.arrow_forward,
                )
              else
                AppButton(
                  label: 'Resubmit Account Upgrade',
                  onPressed: () =>
                      context.push(RouteConstants.lenderAccountUpgrade),
                  color: AppColors.lenderBlue,
                  icon: Icons.arrow_forward,
                ),
            ],
          ),
        ),
      );
    }

    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;
    final String actionLabel;
    final VoidCallback onAction;

    if (isSubmitted) {
      fg = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      title = 'Account Upgrade Under Review';
      subtitle =
          'Your documents are being reviewed. You can apply for a loan once your account upgrade is approved.';
      actionLabel = 'Account Upgrade Status';
      onAction = () => context.push(RouteConstants.lenderAccountUpgradeStatus);
    } else {
      fg = AppColors.warning;
      icon = Icons.verified_user_outlined;
      title = 'Complete Your Account Upgrade';
      subtitle = 'Verify your identity to start borrowing with Jireta Loans.';
      actionLabel = 'Upgrade Account';
      onAction = () => context.push(RouteConstants.lenderAccountUpgrade);
    }

    final isDefaultGate = !isSubmitted && !isRejected;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon + title/subtitle are hidden for the default unverified state
            // per request: remove icon and texts "Verify your identity..." /
            // "Complete Your Account Upgrade". Only the action button remains
            // for that state; submitted keeps its info.
            if (!isDefaultGate) ...[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: fg, size: 42),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
            ],
            if (isDefaultGate) ...[
              const Text(
                'Before you Apply a loan you need to Upgrade your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
            ],
            AppButton(
              label: actionLabel,
              onPressed: onAction,
              color: AppColors.lenderBlue,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineSubmittedTimeline extends StatelessWidget {
  final LenderAccountUpgradeState accountUpgradeState;
  const _InlineSubmittedTimeline({required this.accountUpgradeState});

  @override
  Widget build(BuildContext context) {
    final status = accountUpgradeState.status;
    final steps = [
      _InlineTimelineStep(
          'Documents Submitted',
          'Your account upgrade documents have been submitted for review.',
          status != 'not_submitted',
          Icons.upload_file),
      _InlineTimelineStep(
          'Under Review',
          'Our team is reviewing your documents.',
          ['under_review', 'verified', 'rejected'].contains(status),
          Icons.manage_search),
      _InlineTimelineStep(
        status == 'rejected' ? 'Rejected' : 'Verified',
        status == 'rejected'
            ? (accountUpgradeState.rejectionNotes ??
                'Documents were rejected. Please resubmit.')
            : 'Your identity has been verified. You may now apply for a loan.',
        ['verified', 'rejected'].contains(status),
        status == 'rejected' ? Icons.cancel : Icons.verified_user,
        isError: status == 'rejected',
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification Timeline',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((e) => _InlineTimelineTile(
              step: e.value, isLast: e.key == steps.length - 1)),
        ],
      ),
    );
  }
}

class _InlineTimelineStep {
  final String title;
  final String subtitle;
  final bool completed;
  final IconData icon;
  final bool isError;
  const _InlineTimelineStep(
      this.title, this.subtitle, this.completed, this.icon,
      {this.isError = false});
}

class _InlineTimelineTile extends StatelessWidget {
  final _InlineTimelineStep step;
  final bool isLast;
  const _InlineTimelineTile({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = step.isError
        ? AppColors.error
        : step.completed
            ? AppColors.success
            : AppColors.border;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: step.completed
                    ? color.withValues(alpha: 0.12)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                    color: step.completed ? color : AppColors.border, width: 2),
              ),
              child: Icon(step.icon,
                  size: 18,
                  color: step.completed ? color : AppColors.textTertiary),
            ),
            if (!isLast)
              Container(
                  width: 2,
                  height: 40,
                  color: step.completed
                      ? color.withValues(alpha: 0.3)
                      : AppColors.border),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: step.completed
                            ? AppColors.textPrimary
                            : AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text(step.subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AgeGateView extends StatelessWidget {
  const _AgeGateView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_outlined,
                  color: AppColors.error, size: 42),
            ),
            const SizedBox(height: 20),
            const Text(
              'Age Restriction',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You must be at least 18 years old to apply for a loan with Jireta Loans.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationReviewView extends StatelessWidget {
  final LoanModel loan;
  const _ApplicationReviewView({required this.loan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      loan.status == 'approved'
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_top_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      loan.status == 'approved'
                          ? 'Loan Approved'
                          : 'CI Submitted — Awaiting Manager Approval',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _SummaryRow('Loan #', loan.loanNumber),
                _SummaryRow('Amount', loan.principalAmount.toCurrency),
                _SummaryRow('Total Payable', loan.totalPayable.toCurrency),
                _SummaryRow('Frequency', loan.paymentFrequency.toUpperCase()),
                const SizedBox(height: 8),
                StatusBadge(status: loan.status, small: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'View Application Status',
            onPressed: () => context.push(
              RouteConstants.lenderLoanApplicationStatus
                  .replaceFirst(':id', loan.id),
            ),
            color: AppColors.lenderBlue,
            icon: Icons.timeline_outlined,
          ),
        ],
      ),
    );
  }
}

class _AwaitingReleaseView extends StatelessWidget {
  final LoanModel loan;
  const _AwaitingReleaseView({required this.loan});

  String get _statusText {
    switch (loan.disbursementMethod) {
      case 'rider_delivery':
        return 'Your loan was approved and you chose Cash on Delivery. A rider will be assigned to deliver your cash to your registered address.';
      case 'office_cash':
        return 'Your loan was approved and you chose Pick Up at Office. Your cash is being prepared and we will notify you when it is ready.';
      case 'gcash':
        return 'Your loan was approved and your GCash disbursement is being processed. We will notify you once the funds have been sent.';
      default:
        return 'Your loan was approved and your disbursement is being processed. We will notify you once the funds are released.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'View Application Status',
              onPressed: () => context.push(
                RouteConstants.lenderLoanApplicationStatus
                    .replaceFirst(':id', loan.id),
              ),
              color: AppColors.lenderBlue,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveLoanView extends StatelessWidget {
  final LoanModel loan;
  const _ActiveLoanView({required this.loan});

  @override
  Widget build(BuildContext context) {
    final outstanding = loan.outstandingBalance;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loan.status == 'overdue' ? 'Overdue Loan' : 'Active Loan',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Outstanding Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  outstanding.toCurrency,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Payable',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      loan.totalPayable.toCurrency,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'View Payment Schedule',
            onPressed: () => context.push(RouteConstants.lenderPayments),
            color: AppColors.lenderBlue,
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Loan History',
            onPressed: () => context.push(RouteConstants.lenderLoanHistory),
            color: AppColors.lenderBlueLight,
            icon: Icons.history,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _ChooseDisbursementView extends ConsumerStatefulWidget {
  final LoanModel loan;

  /// Tinatawag pagkatapos ma-save ang method — para manatiling inert ang
  /// apply screen (walang status view na sumilip) hanggang sa makarating sa Home.
  final VoidCallback? onConfirmed;

  const _ChooseDisbursementView({required this.loan, this.onConfirmed});

  @override
  ConsumerState<_ChooseDisbursementView> createState() =>
      _ChooseDisbursementViewState();
}

class _ChooseDisbursementViewState
    extends ConsumerState<_ChooseDisbursementView> {
  String _method = 'rider_delivery';

  Future<void> _confirm() async {
    // Ang CONFIRM BUTTON mismo sa loob ng modal ang nag-loading habang
    // tumatakbo ang save — hindi ang button ng method sa ilalim. Nananatili
    // nakabukas ang modal para makita ang spinner ng confirm button.
    final ok = await showAsyncConfirmationDialog(
      context,
      title: 'Confirm Disbursement Method',
      message: _method == 'rider_delivery'
          ? 'A rider will deliver the cash to your registered address. You will be notified once the rider is scheduled for delivery.'
          : 'You may pick up the cash at the Jireta Loans office. We will notify you once it is ready for pickup.',
      confirmLabel: 'Confirm',
      confirmColor: AppColors.lenderBlue,
      onConfirm: () async {
        // Kailangan ng password / device credential (o ang app-level MPIN)
        // bago i-save ang method — kapareho ng ibang lender submissions.
        final verified = await ref.read(submissionGuardProvider).confirm(
              context,
              reason: kSubmissionVerificationReason,
            );
        if (!verified) {
          return 'Identity verification failed. Please try again.';
        }
        final done = await ref
            .read(lenderLoanProvider.notifier)
            .selectDisbursementMethod(
              loanId: widget.loan.id,
              method: _method,
            );
        if (done) return null;
        return ref.read(lenderLoanProvider).error ??
            'Failed to save your disbursement method.';
      },
    );
    if (ok != true || !mounted) return;

    // Nakapili na: huwag nang ipakita ang "Awaiting Release"/status view sa
    // ilalim ng success modal — inert na ang screen hanggang mag-Home.
    widget.onConfirmed?.call();

    // Pagkatapos ng loading ng confirm button: 2-segundong success modal,
    // tapos DERETSO sa Home — walang status/shimmer na sasabit.
    await SuccessDialog.showAutoDismiss(
      context,
      title: _method == 'rider_delivery'
          ? 'Cash on Delivery Confirmed'
          : 'Office Pickup Confirmed',
      message: _method == 'rider_delivery'
          ? 'A rider will be scheduled to deliver your loan to your registered address.'
          : 'We will notify you once your cash is ready for pickup at the office.',
      buttonText: 'Done',
      duration: const Duration(seconds: 2),
    );
    if (mounted) context.go(RouteConstants.lenderDashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            // Bahagyang ibinaba ang simula + mas malaking title na naka-center
            // sa mobile view.
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'How would you like to receive the funds?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 28),
                _disbOption(
                  selected: _method == 'gcash',
                  icon: Icons.phone_android,
                  title: 'GCash',
                  subtitle: 'Funds will be sent to your GCash number.',
                  onTap: null,
                  badge: 'Coming soon',
                ),
                const SizedBox(height: 12),
                _disbOption(
                  selected: _method == 'rider_delivery',
                  icon: Icons.delivery_dining,
                  title: 'Cash on Delivery',
                  subtitle:
                      'A rider will deliver the cash to your registered address.',
                  onTap: () => setState(() => _method = 'rider_delivery'),
                ),
                const SizedBox(height: 12),
                _disbOption(
                  selected: _method == 'office_cash',
                  icon: Icons.business_center,
                  title: 'Pick Up at Office',
                  subtitle: 'Withdraw the cash at the Jireta Loans office.',
                  onTap: () => setState(() => _method = 'office_cash'),
                ),
              ],
            ),
          ),
        ),
        // Naka-pin sa baba ng mobile view.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
          child: AppButton(
            label:
                'Confirm ${_method == 'rider_delivery' ? 'COD' : 'Office Pickup'}',
            onTap: _confirm,
            color: AppColors.lenderBlue,
            isExpanded: true,
          ),
        ),
      ],
    );
  }

  Widget _disbOption({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    String? badge,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        // Bahagyang mas malaki ang cards (mas madaling i-tap).
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.lenderBlueLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.lenderBlue : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: enabled
                    ? (selected ? Colors.white : AppColors.textSecondary)
                    : AppColors.textTertiary,
                size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: enabled
                                ? (selected
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColors.textTertiary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? Colors.white70
                            : (enabled
                                ? AppColors.textSecondary
                                : AppColors.textTertiary)),
                  ),
                ],
              ),
            ),
            Icon(
              enabled
                  ? (selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked)
                  : Icons.radio_button_unchecked,
              color: enabled
                  ? (selected ? Colors.white : AppColors.textTertiary)
                  : AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Buong-screen na loan purpose selection. Ito ang unang lumalabas kapag
/// pinindot ang "Apply Loan" — pagkatapos pumili, diretso na sa Loan Details
/// step ng wizard (na wala nang sariling purpose field).
class _LoanPurposePicker extends StatefulWidget {
  final List<(String, IconData)> suggestions;
  final ValueChanged<String> onSelected;

  const _LoanPurposePicker({
    required this.suggestions,
    required this.onSelected,
  });

  @override
  State<_LoanPurposePicker> createState() => _LoanPurposePickerState();
}

class _LoanPurposePickerState extends State<_LoanPurposePicker> {
  static const String _otherLabel = 'Other';

  String? _selected;
  final _otherCtrl = TextEditingController();
  final _otherFieldKey = GlobalKey();
  bool _showError = false;

  /// Pinipili ang purpose. Kapag 'Other', i-scroll papasok sa viewport ang
  /// text field — kung hindi, lumalabas ito sa ilalim ng listahan at natatakpan
  /// ng naka-pin na Continue button.
  void _select(String label) {
    setState(() {
      _selected = label;
      _showError = false;
    });
    if (label != _otherLabel) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldCtx = _otherFieldKey.currentContext;
      if (fieldCtx == null) return;
      Scrollable.ensureVisible(
        fieldCtx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 1,
      );
    });
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool get _isOther => _selected == _otherLabel;

  String get _value {
    if (_isOther) return _otherCtrl.text.trim();
    return _selected ?? '';
  }

  void _continue() {
    final value = _value;
    if (value.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            // Kapag kasya ang laman, hindi na mahihila ang page; tuloy pa rin
            // ang scroll kapag talagang umaapaw.
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Walang "What is this loan for?" na header — ang subtitle na
                // lang ang nagpapaliwanag, at naka-center ito.
                const Text(
                  'Choose the purpose of your loan. This is the first step before the loan details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ...widget.suggestions.map((option) {
                  final label = option.$1;
                  final icon = option.$2;
                  final selected = _selected == label;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => _select(label),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.lenderBlueLight
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.lenderBlue
                                : AppColors.border,
                            width: selected ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icon,
                                size: 20,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: selected
                                  ? Colors.white
                                  : AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (_isOther) ...[
                  const SizedBox(height: 2),
                  TextField(
                    key: _otherFieldKey,
                    controller: _otherCtrl,
                    maxLines: 3,
                    maxLength: 255,
                    onChanged: (_) => setState(() => _showError = false),
                    decoration: InputDecoration(
                      hintText: 'Write the reason for your loan...',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.lenderBlue),
                      ),
                    ),
                  ),
                ],
                if (_showError)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Please choose a loan purpose to continue.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Naka-pin sa itaas ng floating bottom nav — eksaktong clearance mula
        // sa [mobileBottomNavInset] (kasama na ang safe area + float + pill).
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            mobileBottomNavInset(context),
          ),
          child: AppButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            color: AppColors.lenderBlue,
            isExpanded: true,
            onTap: _continue,
          ),
        ),
      ],
    );
  }
}

class _LenderApplyLoanSkeleton extends StatelessWidget {
  const _LenderApplyLoanSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator skeleton (4 dots)
            Row(
              children: List.generate(
                  4,
                  (i) => Expanded(
                        child: Column(
                          children: [
                            Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle)),
                            const SizedBox(height: 6),
                            Container(
                                width: 48,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4))),
                            if (i < 3)
                              Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  height: 2,
                                  color: Colors.white),
                          ],
                        ),
                      )),
            ),
            const SizedBox(height: 24),
            // Account upgrade gate skeleton (when direct to upgrade)
            Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 20),
            // Loan amount skeleton
            Container(
                width: 100,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 12),
            Container(
                width: 120,
                height: 28,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            // Frequency selector skeleton
            Container(
                width: 120,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 10),
            Row(
                children: List.generate(
                    3,
                    (_) => Expanded(
                        child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            height: 44,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10)))))),
            const SizedBox(height: 20),
            // Purpose field skeleton
            Container(
                width: 80,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 10),
            Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            // Preview card skeleton
            Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 20),
            // Button skeleton
            Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}
