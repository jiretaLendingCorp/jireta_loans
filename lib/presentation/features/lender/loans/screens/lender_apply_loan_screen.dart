// lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
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
  double _amount = 3000;
  String _frequency = 'weekly';
  int? _termPeriods;
  final _purposeCtrl = TextEditingController();
  bool _previewLoading = false;
  Map<String, dynamic>? _coMaker;
  int _step = 0;
  final _coMakerFormKey = GlobalKey<_CoMakerFormState>();
  String? _coMakerSignature;
  String? _signatureError;

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
      label: 'History',
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
    _purposeCtrl.removeListener(_onPurposeChanged);
    _purposeCtrl.dispose();
    super.dispose();
  }

  // ── Validation for Next button ──
  bool _isLoanDetailsValid() => _purposeCtrl.text.trim().isNotEmpty;

  bool _isCoMakerValid() {
    final m = _coMaker;
    if (m == null) return false;
    bool notEmpty(String k) => (m[k]?.toString().trim().isNotEmpty ?? false);
    final phone = m['phone_number']?.toString().trim() ?? '';
    final phoneOk = phone.length == 11 &&
        phone.startsWith('09') &&
        RegExp(r'^\d{11}$').hasMatch(phone);
    final dob = m['date_of_birth']?.toString().trim() ?? '';
    return notEmpty('first_name') &&
        notEmpty('last_name') &&
        phoneOk &&
        notEmpty('relationship') &&
        notEmpty('address') &&
        dob.isNotEmpty;
  }

  bool _isSignatureValid() =>
      _coMakerSignature != null && _coMakerSignature!.isNotEmpty;

  bool get _canGoNext {
    if (_step == 0) return _isLoanDetailsValid();
    if (_step == 1) return _isCoMakerValid();
    if (_step == 2) return _isSignatureValid();
    // Review step (3) – enable Submit only if all previous are valid
    if (_step == 3) {
      return _isLoanDetailsValid() &&
          _isCoMakerValid() &&
          _isSignatureValid();
    }
    return true;
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmationDialog(
        title: 'Submit Loan Application',
        message:
            'Are you sure to apply this loan?',
        confirmLabel: 'Submit',
        confirmColor: AppColors.lenderBlue,
      ),
    );
    if (confirmed != true) return;

    final coMaker = Map<String, dynamic>.from(_coMaker ?? {})
      ..['signature'] = _coMakerSignature;
    final ok = await ref.read(lenderLoanProvider.notifier).applyLoan(
          amount: _amount,
          frequency: _frequency,
          termPeriods: _termPeriods,
          purpose: _purposeCtrl.text.trim(),
          coMaker: coMaker,
        );

    if (!mounted) return;
    if (ok) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Loan application submitted successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go(RouteConstants.lenderDashboard);
    } else {
      final err = ref.read(lenderLoanProvider).error ?? 'An error occurred.';
      context.showSnackBarAsToast(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  void _goNext() {
    if (_step == 0) {
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
    } else if (_step == 2) {
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
    const candidates = <String, List<int>>{                  'daily': [14, 21, 30, 45, 60, 90, 120, 180],
      'weekly': [1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 26],
      'monthly': [1, 2, 3, 4, 5, 6],
    };
    final opts =
        (candidates[_frequency] ?? const <int>[]).where((v) => v <= max).toList();
    if (!opts.contains(max)) opts.add(max);
    return opts;
  }

  /// Effective term label used in the review step and the submit dialog, e.g.
  /// "6 weeks", "30 days", or "2 months".
  String _termLabel() {
    final preview = ref.read(lenderLoanProvider).schedulePreview;
    final max = (preview?['max_periods'] as num?)?.toInt() ?? 0;
    final periods = _termPeriods ?? max;
    return periods > 0 ? '$periods ${_termUnit()}' : 'the full term';
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
            final selected = isMax
                ? _termPeriods == null
                : _termPeriods == value;
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
                  '$value $unit',
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
      NumberFormat fmt, Map<String, dynamic>? preview) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 80),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Loan Amount'),
          const SizedBox(height: 4),
          Text(
            '₱${fmt.format(_amount)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.lenderBlue,
            ),
          ),
          Slider(
            value: _amount,
            min: 3000,
            max: 500000,
            divisions: 497,
            activeColor: AppColors.lenderBlue,
            inactiveColor: AppColors.lenderBlue.withValues(alpha: 0.2),
            onChanged: (v) {
              setState(() => _amount = (v / 1000).round() * 1000.0);
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
          _buildTermSelector(
              (preview?['max_periods'] as num?)?.toInt() ?? 0),
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
        ],
      ),
    );
  }

  Widget _buildCoMakerStep() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 80),
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

  Widget _buildSignatureStep() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 80),
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
                if (_coMakerSignature != null && _coMakerSignature!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.success, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Signature confirmed',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
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
        ],
      ),
    );
  }

  Widget _buildReviewStep(NumberFormat fmt, Map<String, dynamic>? preview) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final interest = preview == null ? null : (preview['interest'] ?? 0);
    final totalPayable =
        preview == null ? null : (preview['total_payable'] ?? 0);
    final installment =
        preview == null ? null : (preview['installment_amount'] ?? 0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 80),
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
        ],
      ),
    );
  }

  Widget _buildWizardBar(LenderLoanState state) {
    final isLast = _step == 3;
    final canProceed = _canGoNext && !state.isSubmitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: AppButton(
                label: 'Back',
                variant: AppButtonVariant.outlined,
                color: AppColors.lenderBlue,
                onTap: _goBack,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: AppButton(
              label: isLast ? 'Submit Application' : 'Next',
              icon: isLast ? Icons.send : Icons.arrow_forward,
              color: AppColors.lenderBlue,
              isLoading: state.isSubmitting,
              onTap: canProceed ? (isLast ? _submit : _goNext) : null,
            ),
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
      body: (loanState.isLoading || accountUpgradeState.isLoading)
          ? const ShimmerLoader()
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
      return _AccountUpgradeGate(status: accountUpgrade);
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Column(
      children: [
        _StepIndicator(current: _step),
        Expanded(
          child: IndexedStack(
            index: _step,
            children: [
              _buildLoanDetailsStep(fmt, preview),
              _buildCoMakerStep(),
              _buildSignatureStep(),
              _buildReviewStep(fmt, preview),
            ],
          ),
        ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: _buildWizardBar(state),
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
    final termUnit = freq == 'weekly'
        ? 'weeks'
        : (freq == 'monthly' ? 'months' : 'days');
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
                _PreviewRow('Term', '$installments $termUnit',
                    AppColors.textSecondary),
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
  final String status;
  const _AccountUpgradeGate({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSubmitted = status == 'submitted' || status == 'pending';
    final isRejected = status == 'rejected';

    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;
    final String actionLabel;
    final VoidCallback onAction;

    if (isRejected) {
      fg = AppColors.error;
      icon = Icons.gpp_bad_outlined;
      title = 'Account Upgrade Submission Rejected';
      subtitle =
          'Your account upgrade documents could not be approved. Please resubmit to continue.';
      actionLabel = 'Resubmit Account Upgrade';
      onAction = () => context.push(RouteConstants.lenderAccountUpgrade);
    } else if (isSubmitted) {
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
            // for that state; submitted/rejected keep their info.
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
            ? (accountUpgradeState.rejectionNotes ?? 'Documents were rejected. Please resubmit.')
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
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((e) => _InlineTimelineTile(step: e.value, isLast: e.key == steps.length - 1)),
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
  const _InlineTimelineStep(this.title, this.subtitle, this.completed, this.icon, {this.isError = false});
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
                color: step.completed ? color.withValues(alpha: 0.12) : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: step.completed ? color : AppColors.border, width: 2),
              ),
              child: Icon(step.icon, size: 18, color: step.completed ? color : AppColors.textTertiary),
            ),
            if (!isLast)
              Container(width: 2, height: 40, color: step.completed ? color.withValues(alpha: 0.3) : AppColors.border),
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
                        fontWeight: FontWeight.w600, fontSize: 14, color: step.completed ? AppColors.textPrimary : AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text(step.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  String get _methodLabel {
    switch (loan.disbursementMethod) {
      case 'rider_delivery':
        return 'Cash via Rider';
      case 'office_cash':
        return 'Pick Up at Office';
      case 'gcash':
        return 'GCash';
      default:
        return loan.disbursementMethod ?? 'your chosen method';
    }
  }

  String get _message {
    switch (loan.disbursementMethod) {
      case 'rider_delivery':
        return 'A rider will be assigned to deliver your cash to your registered address. We will notify you once the delivery is on its way.';
      case 'office_cash':
        return 'Your cash is being prepared for pickup at the Jireta Loans office. We will notify you when it is ready.';
      case 'gcash':
        return 'Your GCash disbursement is being processed. We will notify you once the funds have been sent.';
      default:
        return 'Your disbursement is being processed. We will notify you once the funds are released.';
    }
  }

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
                const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        color: Colors.white, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'Loan Approved — Awaiting Release',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Your loan was approved and you chose "$_methodLabel". $_message',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
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
                _SummaryRow('Disbursement Method', _methodLabel),
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
            ? 'A rider will deliver your cash to the address in your account upgrade profile. A rider will be scheduled to deliver it.'
            : 'You will pick up the cash at the Jireta Loans office. We will notify you when it is ready.',
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
          ok ? 'Your disbursement method has been saved.' : err ?? 'Failed to save your disbursement method.',
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
    final loan = widget.loan;
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'Loan Approved',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Your loan has been approved! Choose how you want to receive the funds to complete the release.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SummaryRow('Loan #', loan.loanNumber),
                _SummaryRow('Amount', loan.principalAmount.toCurrency),
                _SummaryRow('Total Payable', loan.totalPayable.toCurrency),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
            title: 'Cash via Rider',
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
            label: 'Confirm ${_method == 'rider_delivery' ? 'Rider Delivery' : 'Office Pickup'}',
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
                    ? (selected ? AppColors.lenderBlue : AppColors.textSecondary)
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
                                    ? AppColors.lenderBlue
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
                            color: AppColors.textTertiary
                                .withValues(alpha: 0.12),
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
                        color: enabled
                            ? AppColors.textSecondary
                            : AppColors.textTertiary),
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
                  ? (selected
                      ? AppColors.lenderBlue
                      : AppColors.textTertiary)
                  : AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
