// lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../../data/models/loan_model.dart';
import '../../account_upgrade/providers/lender_account_upgrade_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_loan_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
  PlatformFile? _coMakerValidId;
  String? _validIdError;

  // 00128: financial + emergency are declared PER APPLICATION (this loan).
  final _employerNameCtrl = TextEditingController();
  final _monthlyIncomeCtrl = TextEditingController();
  final _ecNameCtrl = TextEditingController();
  final _ecPhoneCtrl = TextEditingController();
  final _ecAddressCtrl = TextEditingController();
  String? _employmentType;
  String? _sourceOfFunds;
  String? _ecRelationship;

  /// Set the first time the user taps Next on the Financial step so inline
  /// field errors become visible and stay until every field is fixed.
  bool _financialAttempted = false;

  /// True once the application was accepted — hides the skeleton/shimmer and
  /// the loan-state views that would otherwise rebuild behind the success
  /// modal while the list refreshes with the new application.
  bool _justSubmitted = false;

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

  @override
  void initState() {
    super.initState();
    _purposeCtrl.addListener(_onPurposeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lenderAccountUpgradeProvider.notifier).loadStatus();
      ref.read(lenderLoanProvider.notifier).loadLoans();
      _refreshPreview();
    });
  }

  void _onPurposeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _purposeCtrl.removeListener(_onPurposeChanged);
    _purposeCtrl.dispose();
    _amountCtrl.dispose();
    _employerNameCtrl.dispose();
    _monthlyIncomeCtrl.dispose();
    _ecNameCtrl.dispose();
    _ecPhoneCtrl.dispose();
    _ecAddressCtrl.dispose();
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
    if (_employerNameCtrl.text.trim().isEmpty) return false;
    final income = _parseMonthlyIncome();
    if (income == null || income <= 0) return false;
    if (_sourceOfFunds == null) return false;
    if (_ecNameCtrl.text.trim().isEmpty) return false;
    final ecPhone = _ecPhoneCtrl.text.trim();
    if (ecPhone.length != 11 ||
        !ecPhone.startsWith('09') ||
        !RegExp(r'^\d{11}$').hasMatch(ecPhone)) {
      return false;
    }
    if (_ecRelationship == null) return false;
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

  Future<void> _submit() async {
    if (_purposeCtrl.text.trim().isEmpty) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Please enter your loan purpose.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final cmValid = _coMakerFormKey.currentState?.validate() ?? false;
    if (!cmValid) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Please complete the co-maker details.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_coMakerSignature == null || _coMakerSignature!.isEmpty) {
      setState(() =>
          _signatureError = 'Co-maker must sign the pad before submission');
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Please provide the co-maker signature.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    // 00147: co-maker Valid ID is required alongside the signature.
    if (_coMakerValidId == null) {
      setState(() => _validIdError = 'Co-maker Valid ID is required');
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Please upload the co-maker valid ID.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

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
    final coMaker = Map<String, dynamic>.from(_coMaker ?? {})
      ..['signature'] = _coMakerSignature
      ..['valid_id_document'] = {
        if (validIdBytes != null) 'content_base64': base64Encode(validIdBytes),
        'file_name': _coMakerValidId!.name,
        'mime_type': validIdMime,
      };
    // 00128: per-loan declaration captured inside this wizard.
    final employment = {
      'type': _employmentType,
      'employer_name': _employerNameCtrl.text.trim(),
      'monthly_income': _parseMonthlyIncome(),
    };
    final emergencyContacts = [
      {
        'name': _ecNameCtrl.text.trim(),
        'relationship': _ecRelationship,
        'phone_number': _ecPhoneCtrl.text.trim(),
        if (_ecAddressCtrl.text.trim().isNotEmpty)
          'address': _ecAddressCtrl.text.trim(),
      },
    ];

    // No blocking confirm modal: while the request runs the Submit button on
    // the Review step shows its loading spinner (state.isSubmitting).
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
      // Hide the step content so no shimmer / "view status" flash can appear
      // behind the success modal while the loan list refreshes underneath.
      setState(() => _justSubmitted = true);
      // Success modal sits for ~2 seconds, then we go straight to Home — no
      // toast, no splash, no intermediate application-status screen.
      await SuccessDialog.showAutoDismiss(
        context,
        title: 'Successfully Submitted',
        message: 'Your loan application has been submitted successfully.',
        buttonText: 'Go to Home',
      );
      if (mounted) {
        context.go(RouteConstants.lenderDashboard);
      }
    } else {
      final err = ref.read(lenderLoanProvider).error ?? 'An error occurred.';
      context.showSnackBarAsToast(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  void _goNext() {
    if (_step == 0) {
      if (!_isAmountValid) {
        context.showSnackBarAsToast(
          const SnackBar(
            content:
                Text('Please enter a valid loan amount (₱3,000 – ₱500,000).'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (_purposeCtrl.text.trim().isEmpty) {
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Please enter your loan purpose to continue.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    } else if (_step == 1) {
      // Financial Details + Emergency Contact — reveal inline field errors on
      // the first attempt so the user sees exactly what is missing.
      setState(() => _financialAttempted = true);
      if (!_isFinancialValid) {
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text(
                'Please complete the financial details and emergency contact.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    } else if (_step == 2) {
      final valid = _coMakerFormKey.currentState?.validate() ?? false;
      if (!valid) {
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Please complete the co-maker details.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    } else if (_step == 3) {
      if (_coMakerSignature == null || _coMakerSignature!.isEmpty) {
        setState(() =>
            _signatureError = 'Co-maker must sign the pad before submission');
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Please provide the co-maker signature to continue.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      // 00147: co-maker Valid ID is required before moving on.
      if (_coMakerValidId == null) {
        setState(() => _validIdError = 'Co-maker Valid ID is required');
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Please upload the co-maker valid ID to continue.'),
            backgroundColor: AppColors.error,
          ),
        );
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((value) {
            final isMax = value == maxPeriods;
            final selected =
                isMax ? _termPeriods == null : _termPeriods == value;
            return InkWell(
              onTap: () {
                setState(() => _termPeriods = isMax ? null : value);
                _refreshPreview();
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.lenderBlue : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.lenderBlue : AppColors.border,
                  ),
                ),
                child: Text(
                  '$value ${value == 1 && unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit}',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLoanDetailsStep(
      NumberFormat fmt, Map<String, dynamic>? preview, bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      // Bottom clearance sized so the last element (the inline Next button)
      // rests just above the floating bottom nav pill (pill ≈ 93px + safe
      // area above the screen bottom) when fully scrolled — no big gap.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + bottomInset + MediaQuery.of(context).padding.bottom + 84,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Loan Amount'),
          const SizedBox(height: 4),
          TextField(
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
          TextField(
            controller: _purposeCtrl,
            maxLines: 3,
            maxLength: 255,
            scrollPadding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 120),
            decoration: InputDecoration(
              hintText: 'Enter purpose of loan...',
              counterText: '',
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
            ),
          ),
          const SizedBox(height: 20),
          _SchedulePreview(preview: preview, loading: _previewLoading),
          _buildStepNav(isSubmitting),
        ],
      ),
    );
  }

  Widget _buildCoMakerStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      // Bottom clearance sized so the last element (the inline Next button)
      // rests just above the floating bottom nav pill (pill ≈ 93px + safe
      // area above the screen bottom) when fully scrolled — no big gap.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + bottomInset + MediaQuery.of(context).padding.bottom + 84,
      ),
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
          _buildStepNav(isSubmitting),
        ],
      ),
    );
  }

  Widget _buildSignatureStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      // Bottom clearance sized so the last element (the inline Next button)
      // rests just above the floating bottom nav pill (pill ≈ 93px + safe
      // area above the screen bottom) when fully scrolled — no big gap.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + bottomInset + MediaQuery.of(context).padding.bottom + 84,
      ),
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
                    setState(() {
                      _coMakerSignature = sig;
                      _signatureError = (sig != null && sig.isNotEmpty)
                          ? null
                          : 'Co-maker must sign the pad before submission';
                    });
                  },
                  height: 200,
                ),
                const SizedBox(height: 4),
                const Text(
                  'The co-maker signature above serves as consent for this loan.',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
                if (_coMakerSignature != null &&
                    _coMakerSignature!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppColors.success, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Signature confirmed',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success),
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
          // 00147: co-maker Valid ID — required alongside the signature and
          // visible to head manager / employee reviewers after submission.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _validIdError != null
                    ? AppColors.error
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Co-Maker Valid ID *',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                const Text(
                  "A clear photo of the co-maker's government-issued ID.",
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                if (_coMakerValidId != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _coMakerValidId!.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: isSubmitting ? null : _pickCoMakerValidId,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(_coMakerValidId != null
                      ? 'Change Valid ID'
                      : 'Upload Valid ID'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.lenderBlue,
                    side: const BorderSide(color: AppColors.lenderBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
          _buildStepNav(isSubmitting),
        ],
      ),
    );
  }

  /// 00147: capture the co-maker's Valid ID (camera or gallery).
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
              title: const Text('Take photo'),
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
      final img = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (img == null || !mounted) return;
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      setState(() {
        _coMakerValidId = PlatformFile(
          name: img.name,
          size: bytes.length,
          bytes: bytes,
        );
        _validIdError = null;
      });
    } else if (action == 'gallery') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      setState(() {
        _coMakerValidId = result.files.first;
        _validIdError = null;
      });
    }
  }

  /// 00128: borrower declares employment/income/source of funds + emergency
  /// contact FOR THIS APPLICATION. Stored on the loan record (not profile).
  Widget _buildFinancialEmergencyStep(bool isSubmitting) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      // Bottom clearance sized so the last element (the inline Next button)
      // rests just above the floating bottom nav pill when fully scrolled.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + bottomInset + MediaQuery.of(context).padding.bottom + 84,
      ),
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
                const SizedBox(height: 12),
                TextField(
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
                  controller: _monthlyIncomeCtrl,
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
                const SizedBox(height: 12),
                TextField(
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
                TextField(
                  controller: _ecAddressCtrl,
                  maxLength: 255,
                  onChanged: (_) => setState(() {}),
                  scrollPadding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 120),
                  decoration: _finFieldDeco('Address (Optional)'),
                ),
              ],
            ),
          ),
          _buildStepNav(isSubmitting),
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
      // Bottom clearance sized so the last element (the inline Next button)
      // rests just above the floating bottom nav pill (pill ≈ 93px + safe
      // area above the screen bottom) when fully scrolled — no big gap.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + bottomInset + MediaQuery.of(context).padding.bottom + 84,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Review Information'),
          const SizedBox(height: 6),
          const Text(
            'Please review the details below. If everything is correct, submit your application.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _ReviewCard(
            amount: _amount,
            frequency: _frequency,
            termLabel: _termLabel(),
            purpose: _purposeCtrl.text.trim(),
            coMaker: _coMaker,
            fmt: fmt,
            signatureProvided:
                _coMakerSignature != null && _coMakerSignature!.isNotEmpty,
            interest: interest,
            totalPayable: totalPayable,
            installment: installment,
          ),
          const SizedBox(height: 12),
          _buildLoanDeclarationCard(),
          _buildStepNav(isSubmitting),
        ],
      ),
    );
  }

  /// 00128: show the per-application declaration (financial + emergency)
  /// on the Review step so the borrower can confirm before submitting.
  Widget _buildLoanDeclarationCard() {
    String labelOf(List<(String, String)> options, String? code) {
      for (final e in options) {
        if (e.$1 == code) return e.$2;
      }
      return code?.isEmpty ?? true ? '—' : (code ?? '—');
    }

    final income = _parseMonthlyIncome();
    final incomeLabel =
        income != null ? '₱${NumberFormat('#,##0.00').format(income)}' : '—';
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
          const Text(
            'Financial & Emergency Declaration',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _declRow('Employment', labelOf(_employmentOptions, _employmentType)),
          _declRow(
              'Employer',
              _employerNameCtrl.text.trim().isEmpty
                  ? '—'
                  : _employerNameCtrl.text.trim()),
          _declRow('Monthly Income', incomeLabel),
          _declRow('Source of Funds',
              labelOf(_sourceOfFundsOptions, _sourceOfFunds)),
          const Divider(height: 20),
          _declRow('Emergency Contact',
              _ecNameCtrl.text.trim().isEmpty ? '—' : _ecNameCtrl.text.trim()),
          _declRow('Relationship', _ecRelationship ?? '—'),
          _declRow(
              'Contact Number',
              _ecPhoneCtrl.text.trim().isEmpty
                  ? '—'
                  : _ecPhoneCtrl.text.trim()),
          _declRow(
              'Address',
              _ecAddressCtrl.text.trim().isEmpty
                  ? '—'
                  : _ecAddressCtrl.text.trim()),
        ],
      ),
    );
  }

  Widget _declRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );

  /// Inline nav row at the end of each step's scrollable content — on the
  /// Loan Details step the Next button sits right below the payment schedule
  /// preview card, scrolling with the content.
  Widget _buildStepNav(bool isSubmitting) {
    final isLast = _step == 4;
    // Next/Submit stay tappable so the step validators can run and surface
    // inline errors; the individual step handlers perform the real checks.
    final canProceed = !isSubmitting;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          if (_step > 0) ...[
            _NavTextButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: isSubmitting ? null : _goBack,
            ),
            const SizedBox(width: 12),
          ],
          const Spacer(),
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
      body: _justSubmitted
          // Submission accepted: keep the screen inert behind the success
          // modal (no skeleton, no loan-state rebuild) until we go Home.
          ? const SizedBox.shrink()
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
      return _ChooseDisbursementView(loan: approvedLoan);
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

    final state = loanState;
    final preview = state.schedulePreview;
    return Column(
      children: [
        _StepIndicator(current: _step),
        Expanded(
          child: IndexedStack(
            index: _step,
            children: [
              _buildLoanDetailsStep(fmt, preview, state.isSubmitting),
              _buildFinancialEmergencyStep(state.isSubmitting),
              _buildCoMakerStep(state.isSubmitting),
              _buildSignatureStep(state.isSubmitting),
              _buildReviewStep(fmt, preview, state.isSubmitting),
            ],
          ),
        ),
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
  final _addressCtrl = TextEditingController();
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
    _addressCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final map = <String, dynamic>{
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'relationship': _relationship,
      'address': _addressCtrl.text.trim(),
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
    return formOk && dobOk;
  }

  Future<void> _pickDob() async {
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
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              onChanged: (_) => _emit(),
              maxLength: 100,
              scrollPadding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 120),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Address is required'
                  : null,
              decoration: _coFieldDeco('Address'),
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
class _NavTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _NavTextButton({
    required this.icon,
    required this.label,
    this.onTap,
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
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          for (int i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: i <= current ? AppColors.lenderBlue : AppColors.border,
                ),
              ),
            _StepDot(
              index: i,
              isActive: i == current,
              isDone: i < current,
              label: _labels[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool isActive;
  final bool isDone;
  final String label;
  const _StepDot({
    required this.index,
    required this.isActive,
    required this.isDone,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = isActive || isDone;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isActive ? 32 : 24,
          height: isActive ? 32 : 24,
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
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: highlighted ? AppColors.lenderBlue : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final double amount;
  final String frequency;
  final String termLabel;
  final String purpose;
  final Map<String, dynamic>? coMaker;
  final NumberFormat fmt;
  final bool signatureProvided;
  final dynamic interest;
  final dynamic totalPayable;
  final dynamic installment;
  const _ReviewCard({
    required this.amount,
    required this.frequency,
    required this.termLabel,
    required this.purpose,
    required this.coMaker,
    required this.fmt,
    required this.signatureProvided,
    this.interest,
    this.totalPayable,
    this.installment,
  });

  String _s(String key) {
    final v = coMaker?[key];
    return v?.toString().trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
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
          const Divider(height: 24),
          const Text(
            'Co-Maker',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _row('Full Name', '${_s('first_name')} ${_s('last_name')}'.trim()),
          _row(
              'Contact', _s('phone_number').isEmpty ? '-' : _s('phone_number')),
          _row('Relationship',
              _s('relationship').isEmpty ? '-' : _s('relationship')),
          _row('Address', _s('address').isEmpty ? '-' : _s('address')),
          _row('Date of Birth',
              _s('date_of_birth').isEmpty ? '-' : _s('date_of_birth')),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                signatureProvided ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: signatureProvided ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                signatureProvided
                    ? 'Co-maker signature provided'
                    : 'Co-maker signature missing',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      signatureProvided ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
  const _ChooseDisbursementView({required this.loan});

  @override
  ConsumerState<_ChooseDisbursementView> createState() =>
      _ChooseDisbursementViewState();
}

class _ChooseDisbursementViewState
    extends ConsumerState<_ChooseDisbursementView> {
  String _method = 'rider_delivery';
  bool _submitting = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Confirm Disbursement Method',
        message: _method == 'rider_delivery'
            ? 'A rider will deliver the cash to your registered address. You will be notified once the rider is scheduled for delivery.'
            : 'You may pick up the cash at the Jireta Loans office. We will notify you once it is ready for pickup.',
        confirmLabel: 'Confirm',
        confirmColor: AppColors.lenderBlue,
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    final ok =
        await ref.read(lenderLoanProvider.notifier).selectDisbursementMethod(
              loanId: widget.loan.id,
              method: _method,
            );
    if (!mounted) return;
    setState(() => _submitting = false);

    final err = ref.read(lenderLoanProvider).error;
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(
          ok
              ? 'Your disbursement method has been saved.'
              : err ?? 'Failed to save your disbursement method.',
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
    if (ok) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) context.go(RouteConstants.lenderDashboard);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('How would you like to receive the funds?'),
          const SizedBox(height: 12),
          _disbOption(
            selected: _method == 'gcash',
            icon: Icons.phone_android,
            title: 'GCash',
            subtitle: 'Funds will be sent to your GCash number.',
            onTap: null,
            badge: 'Coming soon',
          ),
          const SizedBox(height: 8),
          _disbOption(
            selected: _method == 'rider_delivery',
            icon: Icons.delivery_dining,
            title: 'Cash on Delivery',
            subtitle:
                'A rider will deliver the cash to your registered address.',
            onTap: () => setState(() => _method = 'rider_delivery'),
          ),
          const SizedBox(height: 8),
          _disbOption(
            selected: _method == 'office_cash',
            icon: Icons.business_center,
            title: 'Pick Up at Office',
            subtitle: 'Withdraw the cash at the Jireta Loans office.',
            onTap: () => setState(() => _method = 'office_cash'),
          ),
          const SizedBox(height: 24),
          AppButton(
            label:
                'Confirm ${_method == 'rider_delivery' ? 'COD' : 'Office Pickup'}',
            onTap: _confirm,
            color: AppColors.lenderBlue,
            isLoading: _submitting,
            isExpanded: true,
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.lenderBlueLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
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
                size: 22),
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
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
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
