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
import '../../../../shared/widgets/signature_pad.dart';
import '../../kyc/providers/lender_kyc_provider.dart';
import '../providers/lender_loan_provider.dart';

class LenderApplyLoanScreen extends ConsumerStatefulWidget {
  const LenderApplyLoanScreen({super.key});

  @override
  ConsumerState<LenderApplyLoanScreen> createState() =>
      _LenderApplyLoanScreenState();
}

class _LenderApplyLoanScreenState extends ConsumerState<LenderApplyLoanScreen> {
  double _amount = 5000;
  String _frequency = 'weekly';
  final _purposeCtrl = TextEditingController();
  bool _previewLoading = false;
  Map<String, dynamic>? _coMaker;
  int _step = 0;
  final _coMakerFormKey = GlobalKey<_CoMakerFormState>();

  static const _navItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      label: 'My Loan',
      route: RouteConstants.lenderLoans,
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(lenderKycProvider.notifier).loadStatus();
      if (!mounted) return;
      final status = ref.read(lenderKycProvider).status;
      if (status != 'verified') {
        context.go(status == 'not_submitted'
            ? RouteConstants.lenderKyc
            : RouteConstants.lenderKycStatus);
      }
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
          content: Text('Please complete the co-maker details and signature.'),
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

    final ok = await ref.read(lenderLoanProvider.notifier).applyLoan(
          amount: _amount,
          frequency: _frequency,
          purpose: _purposeCtrl.text.trim(),
          coMaker: _coMaker,
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
    } else {
      final valid = _coMakerFormKey.currentState?.validate() ?? false;
      if (!valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete the co-maker details and signature.'),
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
            'A co-maker is required for your loan application.',
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

  Widget _buildReviewStep(NumberFormat fmt, Map<String, dynamic>? preview) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Review & Confirm'),
          const SizedBox(height: 12),
          _ReviewCard(
            amount: _amount,
            frequency: _frequency,
            purpose: _purposeCtrl.text.trim(),
            coMaker: _coMaker,
            fmt: fmt,
          ),
          if (preview != null) ...[
            const SizedBox(height: 16),
            _SchedulePreview(preview: preview, loading: _previewLoading),
          ],
        ],
      ),
    );
  }

  Widget _buildWizardBar(LenderLoanState state) {
    final isLast = _step == 2;
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
    final state = ref.watch(lenderLoanProvider);
    final preview = state.schedulePreview;
    final fmt = NumberFormat('#,##0.00', 'en_PH');

    return MobileScaffold(
      title: 'Apply for Loan',
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      showBackButton: true,
      body: state.activeLoan != null
          ? _ActiveLoanBlock(state.activeLoan!, context)
          : Column(
              children: [
                _StepIndicator(current: _step),
                Expanded(
                  child: IndexedStack(
                    index: _step,
                    children: [
                      _buildLoanDetailsStep(fmt, preview),
                      _buildCoMakerStep(),
                      _buildReviewStep(fmt, preview),
                    ],
                  ),
                ),
                _buildWizardBar(state),
              ],
            ),
    );
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
  String? _signature;
  String? _signatureError;

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
      'signature': _signature,
    };
    widget.onChanged(map);
  }

  bool validate() {
    final dobOk = _dob != null;
    final sigOk = _signature != null && _signature!.isNotEmpty;
    setState(() {
      _dobError = dobOk ? null : 'Date of birth is required';
      _signatureError =
          sigOk ? null : 'Co-maker must sign the pad before submission';
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    return formOk && dobOk && sigOk;
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
            SignaturePad(
              onSignatureChanged: (sig) {
                setState(() {
                  _signature = sig;
                  _signatureError =
                      (sig != null && sig.isNotEmpty)
                          ? null
                          : 'Co-maker must sign the pad before submission';
                });
                _emit();
              },
              height: 160,
            ),
            const SizedBox(height: 4),
            const Text(
              'The co-maker signature above serves as consent for this loan.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            if (_signatureError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _signatureError!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
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
    final totalPayable = (preview['total_payable'] ?? 0).toDouble();
    final interest = (preview['interest'] ?? 0).toDouble();
    final installment = (preview['installment_amount'] ?? 0).toDouble();
    final termDays = preview['term_days'] ?? 0;
    final dueDates = List<dynamic>.from(preview['due_dates'] ?? []);

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
                _PreviewRow('Total Payable', '₱${fmt.format(totalPayable)}',
                    AppColors.lenderPurple),
                _PreviewRow('Interest (20%)', '₱${fmt.format(interest)}',
                    AppColors.warning),
                _PreviewRow('Per Installment', '₱${fmt.format(installment)}',
                    AppColors.success),
                _PreviewRow('Term', '$termDays days', AppColors.textSecondary),
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Due Dates',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                if (dueDates.isNotEmpty)
                  Column(
                    children: dueDates
                        .take(5)
                        .map((d) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(d.toString().substring(0, 10),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                  Text('₱${fmt.format(installment)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                if (dueDates.length > 5)
                  Text(
                    '+ ${dueDates.length - 5} more installments',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
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

  static const _labels = ['Loan Details', 'Co-Maker', 'Review'];

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
  const _ReviewCard({
    required this.amount,
    required this.frequency,
    required this.purpose,
    required this.coMaker,
    required this.fmt,
  });

  String _s(String key) {
    final v = coMaker?[key];
    return v?.toString().trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final signed = _s('signature').isNotEmpty;
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
                signed ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: signed ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                signed
                    ? 'Co-maker signature provided'
                    : 'Co-maker signature missing',
                style: TextStyle(
                  fontSize: 12,
                  color: signed ? AppColors.success : AppColors.error,
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

class _ActiveLoanBlock extends StatelessWidget {
  final dynamic loan;
  final BuildContext ctx;
  const _ActiveLoanBlock(this.loan, this.ctx);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, color: AppColors.warning, size: 64),
            const SizedBox(height: 16),
            const Text(
              'You have an active loan',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please complete your current loan before applying for a new one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'View My Loan',
              onTap: () => ctx.push(RouteConstants.lenderPayments),
              color: AppColors.lenderPurple,
            ),
          ],
        ),
      ),
    );
  }
}
