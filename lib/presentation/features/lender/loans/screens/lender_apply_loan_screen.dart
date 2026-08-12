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
import '../../kyc/providers/lender_kyc_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_loan_provider.dart';

class LenderApplyLoanScreen extends ConsumerStatefulWidget {
  const LenderApplyLoanScreen({super.key});

  @override
  ConsumerState<LenderApplyLoanScreen> createState() =>
      _LenderApplyLoanScreenState();
}

class _LenderApplyLoanScreenState extends ConsumerState<LenderApplyLoanScreen> {
  double _amount = 3000;
  String _frequency = 'weekly';
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
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lenderKycProvider.notifier).loadStatus();
      ref.read(lenderLoanProvider.notifier).loadLoans();
      _refreshPreview();
    });
  }

  @override
  void dispose() {
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPreview() async {
    setState(() => _previewLoading = true);
    await ref.read(lenderLoanProvider.notifier).getSchedulePreview(
          amount: _amount,
          frequency: _frequency,
        );
    setState(() => _previewLoading = false);
  }

  Future<void> _submit() async {
    if (_purposeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your loan purpose.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final cmValid = _coMakerFormKey.currentState?.validate() ?? false;
    if (!cmValid) {
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide the co-maker signature.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Submit Loan Application',
        message: 'Apply for ${_amount.toCurrency} via $_frequency payments?',
        confirmLabel: 'Submit Application',
        confirmColor: AppColors.lenderPurple,
      ),
    );
    if (confirmed != true) return;

    final coMaker = Map<String, dynamic>.from(_coMaker ?? {})
      ..['signature'] = _coMakerSignature;
    final ok = await ref.read(lenderLoanProvider.notifier).applyLoan(
          amount: _amount,
          frequency: _frequency,
          purpose: _purposeCtrl.text.trim(),
          coMaker: coMaker,
        );

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loan application submitted successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go(RouteConstants.lenderDashboard);
    } else {
      final err = ref.read(lenderLoanProvider).error ?? 'An error occurred.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  void _goNext() {
    if (_step == 0) {
      if (_purposeCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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

  Widget _buildLoanDetailsStep(NumberFormat fmt, Map<String, dynamic>? preview) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(),
          const SizedBox(height: 20),
          const _SectionTitle('Loan Amount'),
          const SizedBox(height: 4),
          Text(
            '₱${fmt.format(_amount)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.lenderPurple,
            ),
          ),
          Slider(
            value: _amount,
            min: 3000,
            max: 500000,
            divisions: 497,
            activeColor: AppColors.lenderPurple,
            inactiveColor: AppColors.lenderPurple.withValues(alpha: 0.2),
            onChanged: (v) {
              setState(() => _amount = (v / 1000).round() * 1000.0);
            },
            onChangeEnd: (_) => _refreshPreview(),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₱3,000',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text('₱500,000',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
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
                      setState(() => _frequency = f);
                      _refreshPreview();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.lenderPurple
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.lenderPurple
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        f[0].toUpperCase() + f.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
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
          const _SectionTitle('Purpose'),
          const SizedBox(height: 8),
          TextField(
            controller: _purposeCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter purpose of loan...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.lenderPurple),
              ),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: 20),
            _SchedulePreview(preview: preview, loading: _previewLoading),
          ] else ...[
            const SizedBox(height: 20),
            AppButton(
              label: 'Preview Schedule',
              onTap: _refreshPreview,
              color: AppColors.lenderPurpleLight,
              isLoading: _previewLoading,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoMakerStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                if (_signatureError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _signatureError!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error),
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
    final interest = preview == null ? null : (preview['interest'] ?? 0);
    final totalPayable = preview == null ? null : (preview['total_payable'] ?? 0);
    final installment = preview == null ? null : (preview['installment_amount'] ?? 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                color: AppColors.lenderPurple,
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
              color: AppColors.lenderPurple,
              isLoading: state.isSubmitting,
              onTap: isLast ? _submit : _goNext,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(lenderLoanProvider);
    final kycState = ref.watch(lenderKycProvider);
    final fmt = NumberFormat('#,##0.00', 'en_PH');

    return MobileScaffold(
      title: 'My Loans',
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      showBackButton: true,
      body: (loanState.isLoading || kycState.isLoading)
          ? const ShimmerLoader()
          : _buildFlow(loanState, kycState, fmt),
    );
  }

  Widget _buildFlow(
      LenderLoanState loanState, LenderKycState kycState, NumberFormat fmt) {
    final kyc = kycState.status;
    final loans = loanState.loans;
    final activeLoan = loanState.activeLoan;

    final dob = ref.watch(lenderProfileProvider).user?.dateOfBirth;
    if (dob != null && !_isAdult(dob)) {
      return const _AgeGateView();
    }

    if (kyc != 'verified' && kyc != 'approved') {
      return _KycGate(status: kyc);
    }
    // Approved-but-not-yet-released loan → lender chooses how to receive funds.
    final approvedLoan = _approvedUnreleasedLoan(loans);
    if (approvedLoan != null) {
      return _ChooseDisbursementView(loan: approvedLoan);
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
              _buildLoanDetailsStep(fmt, preview),
              _buildCoMakerStep(),
              _buildSignatureStep(),
              _buildReviewStep(fmt, preview),
            ],
          ),
        ),
        _buildWizardBar(state),
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

  /// A loan that was approved but has not yet been released (no disbursement).
  /// The lender must choose their disbursement method before it is released.
  LoanModel? _approvedUnreleasedLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' && loan.disbursedAt == null) {
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
            primary: AppColors.lenderPurple,
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
                    color: AppColors.lenderPurple, size: 20),
                SizedBox(width: 8),
                Text(
                  'Co-Maker',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstCtrl,
              onChanged: (_) => _emit(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'First name is required'
                  : null,
              decoration: _coFieldDeco('First Name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _lastCtrl,
              onChanged: (_) => _emit(),
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
              style: TextStyle(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _coFieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lenderPurple),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lenderPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lenderPurple.withValues(alpha: 0.15)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.lenderPurple, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'All amounts, interest, and schedules are computed by our system. Interest rate is 20% of loan amount.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.lenderPurple, height: 1.4),
            ),
          ),
        ],
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
  final Map<String, dynamic> preview;
  final bool loading;
  const _SchedulePreview({required this.preview, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.lenderPurple));
    }
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final principal = (preview['principal'] ?? 0).toDouble();
    final totalPayable = (preview['total_payable'] ?? 0).toDouble();
    final interest = (preview['interest'] ?? preview['interest_amount'] ?? 0)
        .toDouble();
    final installment = (preview['installment_amount'] ?? 0).toDouble();
    final termDays = preview['term_days'] ?? 0;
    final installments = preview['installments'] ?? 0;
    final schedule =
        List<dynamic>.from(preview['schedule'] ?? preview['due_dates'] ?? []);

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
              color: AppColors.lenderPurple,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12)),
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
                    AppColors.lenderPurple),
                _PreviewRow('Per Installment', '₱${fmt.format(installment)}',
                    AppColors.success),
                _PreviewRow('Number of Periods', '$installments',
                    AppColors.textSecondary),
                _PreviewRow('Term', '$termDays days', AppColors.textSecondary),
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Full Computation Per Period',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                if (schedule.isNotEmpty)
                  _buildScheduleTable(fmt, schedule, installment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTable(
      NumberFormat fmt, List<dynamic> schedule, double installment) {
    final hasItemized = schedule.every((p) =>
        p is Map<String, dynamic> && p.containsKey('balance'));

    Widget header(String text, bool bold) => Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: bold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        );

    final rows = schedule.map((p) {
      if (p is Map<String, dynamic> && p.containsKey('due_date')) {
        final period = p['period'] ?? '';
        final dueDate = p['due_date'].toString().substring(0, 10);
        final amount = (p['amount'] ?? 0).toDouble();
        final principal = (p['principal'] ?? amount).toDouble();
        final interest = (p['interest'] ?? 0).toDouble();
        final balance = (p['balance'] ?? 0).toDouble();
        return Row(
          children: [
            Expanded(
                flex: 1,
                child: header('$period', false)),
            Expanded(
                flex: 2,
                child: header(dueDate, false)),
            Expanded(
                flex: 2,
                child: header('₱${fmt.format(amount)}', false)),
            if (hasItemized)
              Expanded(
                  flex: 2,
                  child: header('₱${fmt.format(principal)}', false)),
            if (hasItemized)
              Expanded(
                  flex: 2,
                  child: header('₱${fmt.format(interest)}', false)),
            if (hasItemized)
              Expanded(
                  flex: 2,
                  child: header('₱${fmt.format(balance)}', false)),
          ],
        );
      }
      final dueDate = p.toString().substring(0, 10);
      return Row(
        children: [
          Expanded(flex: 1, child: header('-', false)),
          Expanded(flex: 2, child: header(dueDate, false)),
          Expanded(
              flex: 2,
              child: header('₱${fmt.format(installment)}', false)),
        ],
      );
    }).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(flex: 1, child: header('#', true)),
                Expanded(flex: 2, child: header('Due Date', true)),
                Expanded(flex: 2, child: header('Amount', true)),
                if (hasItemized) ...[
                  Expanded(flex: 2, child: header('Principal', true)),
                  Expanded(flex: 2, child: header('Interest', true)),
                  Expanded(flex: 2, child: header('Balance', true)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
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
                  color: i <= current
                      ? AppColors.lenderPurple
                      : AppColors.border,
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
            color: highlighted ? AppColors.lenderPurple : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted ? AppColors.lenderPurple : AppColors.border,
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
            color: highlighted ? AppColors.lenderPurple : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final double amount;
  final String frequency;
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
          _row('Purpose', purpose.isEmpty ? '-' : purpose),
          if (interest != null) ...[
            _row('Interest (20%)', '₱${fmt.format((interest as num).toDouble())}'),
          ],
          if (totalPayable != null) ...[
            _row('Total Payable', '₱${fmt.format((totalPayable as num).toDouble())}'),
          ],
          if (installment != null) ...[
            _row('Per Installment', '₱${fmt.format((installment as num).toDouble())}'),
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
          _row(
              'Full Name', '${_s('first_name')} ${_s('last_name')}'.trim()),
          _row(
              'Contact',
              _s('phone_number').isEmpty ? '-' : _s('phone_number')),
          _row(
              'Relationship',
              _s('relationship').isEmpty ? '-' : _s('relationship')),
          _row('Address', _s('address').isEmpty ? '-' : _s('address')),
          _row(
              'Date of Birth',
              _s('date_of_birth').isEmpty ? '-' : _s('date_of_birth')),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                signatureProvided ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: signatureProvided
                    ? AppColors.success
                    : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                signatureProvided
                    ? 'Co-maker signature provided'
                    : 'Co-maker signature missing',
                style: TextStyle(
                  fontSize: 12,
                  color: signatureProvided
                      ? AppColors.success
                      : AppColors.error,
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

class _KycGate extends StatelessWidget {
  final String status;
  const _KycGate({required this.status});

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
      title = 'KYC Submission Rejected';
      subtitle =
          'Your KYC documents could not be approved. Please resubmit to continue.';
      actionLabel = 'Resubmit KYC';
      onAction = () => context.push(RouteConstants.lenderKyc);
    } else if (isSubmitted) {
      fg = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      title = 'KYC Under Review';
      subtitle =
          'Your documents are being reviewed. You can apply for a loan once your KYC is approved.';
      actionLabel = 'View Status';
      onAction = () => context.push(RouteConstants.lenderKycStatus);
    } else {
      fg = AppColors.warning;
      icon = Icons.verified_user_outlined;
      title = 'Complete Your KYC';
      subtitle =
          'Verify your identity to start borrowing with Jireta Loans.';
      actionLabel = 'Verify Now';
      onAction = () => context.push(RouteConstants.lenderKyc);
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            AppButton(
              label: actionLabel,
              onPressed: onAction,
              color: AppColors.lenderPurple,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeGateView extends StatelessWidget {
  const _AgeGateView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderPurple, AppColors.lenderPurpleLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderPurple.withValues(alpha: 0.3),
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
                          : 'Loan Application Under Review',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  loan.status == 'approved'
                      ? 'Your loan has been approved. It will become active and available for payments once the funds are disbursed.'
                      : 'Your application has been submitted and is being reviewed by our team. We will notify you once a decision has been made.',
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
                _SummaryRow(
                    'Frequency', loan.paymentFrequency.toUpperCase()),
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
            color: AppColors.lenderPurple,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderPurple, AppColors.lenderPurpleLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderPurple.withValues(alpha: 0.3),
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
                      loan.status == 'overdue'
                          ? 'Overdue Loan'
                          : 'Active Loan',
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
            color: AppColors.lenderPurple,
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Loan History',
            onPressed: () => context.push(RouteConstants.lenderLoanHistory),
            color: AppColors.lenderPurpleLight,
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
  String _method = 'gcash';
  final _gcashCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _gcashCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_method == 'gcash' &&
        !RegExp(r'^09\d{9}$').hasMatch(_gcashCtrl.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 11-digit GCash number (09XXXXXXXXX).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Confirm Disbursement Method',
        message: _method == 'gcash'
            ? 'Receive loan proceeds via GCash? The funds will be released immediately.'
            : _method == 'rider_delivery'
                ? 'A rider will deliver your cash to the address in your KYC profile. A rider will be scheduled to deliver it.'
                : 'You will pick up the cash at the Jireta Loans office. We will notify you when it is ready.',
        confirmLabel: 'Confirm',
        confirmColor: AppColors.lenderPurple,
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    final ok = await ref
        .read(lenderLoanProvider.notifier)
        .selectDisbursementMethod(
          loanId: widget.loan.id,
          method: _method,
          gcashNumber: _method == 'gcash' ? _gcashCtrl.text.trim() : null,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    final err = ref.read(lenderLoanProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (_method == 'gcash'
                  ? 'Your loan has been released via GCash!'
                  : 'Your disbursement method has been saved.')
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
    final loan = widget.loan;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderPurple, AppColors.lenderPurpleLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderPurple.withValues(alpha: 0.3),
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
            subtitle:
                'Funds will be sent to your GCash number immediately.',
            onTap: () => setState(() => _method = 'gcash'),
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
          if (_method == 'gcash') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _gcashCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'GCash Number',
                hintText: '09XXXXXXXXX',
                prefixIcon: const Icon(Icons.phone_android, size: 18),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.lenderPurple),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: _method == 'gcash'
                ? 'Release via GCash'
                : 'Confirm ${
                    _method == 'rider_delivery'
                        ? 'Rider Delivery'
                        : 'Office Pickup'
                  }',
            onTap: _confirm,
            color: AppColors.lenderPurple,
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.lenderPurpleLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.lenderPurple : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.lenderPurple
                    : AppColors.textSecondary,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected
                          ? AppColors.lenderPurple
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.lenderPurple : AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
