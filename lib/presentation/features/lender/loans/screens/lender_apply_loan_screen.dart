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
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Alerts',
      route: RouteConstants.lenderNotifications,
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
      final kycState = ref.read(lenderKycProvider);
      if (kycState.status == 'pending') {
        context.go(RouteConstants.lenderKyc);
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
          : SingleChildScrollView(
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
                        borderSide:
                            const BorderSide(color: AppColors.lenderPurple),
                      ),
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 20),
                    _SchedulePreview(
                        preview: preview, loading: _previewLoading),
                  ] else ...[
                    const SizedBox(height: 20),
                    AppButton(
                      label: 'Preview Schedule',
                      onTap: _refreshPreview,
                      color: AppColors.lenderPurpleLight,
                      isLoading: _previewLoading,
                    ),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Submit Application',
                    onTap: _submit,
                    color: AppColors.lenderPurple,
                    isLoading: state.isSubmitting,
                    icon: Icons.send,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
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
