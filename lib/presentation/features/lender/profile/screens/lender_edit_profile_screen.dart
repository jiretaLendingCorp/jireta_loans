// lib/presentation/features/lender/profile/screens/lender_edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/lender_profile_provider.dart';

class LenderProfileEditScreen extends ConsumerStatefulWidget {
  const LenderProfileEditScreen({super.key});

  @override
  ConsumerState<LenderProfileEditScreen> createState() =>
      _LenderEditProfileScreenState();
}

class _LenderEditProfileScreenState
    extends ConsumerState<LenderProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();

  String? _gender;
  String? _civilStatus;
  String? _employmentType;
  DateTime? _dob;
  bool _initialized = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  void _initFromState() {
    if (_initialized) return;
    final user = ref.read(lenderProfileProvider).user;
    if (user == null) return;
    _firstNameCtrl.text = user.firstName;
    _lastNameCtrl.text = user.lastName;
    _middleNameCtrl.text = user.middleName ?? '';
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _gcashCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 6570)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.lenderPurple,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = <String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      if (_middleNameCtrl.text.trim().isNotEmpty)
        'middle_name': _middleNameCtrl.text.trim(),
      if (_gender != null) 'gender': _gender,
      if (_civilStatus != null) 'civil_status': _civilStatus,
      if (_dob != null) 'date_of_birth': DateFormat('yyyy-MM-dd').format(_dob!),
      if (_gcashCtrl.text.trim().isNotEmpty)
        'gcash_number': _gcashCtrl.text.trim(),
      if (_employmentType != null) 'employment_type': _employmentType,
      if (_employerCtrl.text.trim().isNotEmpty)
        'employer_name': _employerCtrl.text.trim(),
      if (_incomeCtrl.text.trim().isNotEmpty)
        'monthly_income': double.tryParse(_incomeCtrl.text.trim()),
    };

    final ok =
        await ref.read(lenderProfileProvider.notifier).updateProfile(payload);

    if (!mounted) return;
    if (ok) {
      await showDialog(
        context: context,
        builder: (_) => const SuccessDialog(
          title: 'Profile Updated',
          message: 'Your profile has been updated successfully.',
        ),
      );
      if (mounted) context.go(RouteConstants.lenderProfile);
    } else {
      final err = ref.read(lenderProfileProvider).error;
      await showErrorDialog(
        context,
        message: err ?? 'Failed to update profile. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderProfileProvider);

    if (!_initialized && state.user != null) {
      _initFromState();
    }

    return MobileScaffold(
      title: 'Edit Profile',
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionCard(
                      'Personal Information',
                      Icons.person_outline,
                      [
                        AppTextField(
                          label: 'First Name',
                          controller: _firstNameCtrl,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'First name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Middle Name (Optional)',
                          controller: _middleNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Last Name',
                          controller: _lastNameCtrl,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Last name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Gender',
                          value: _gender,
                          items: const ['Male', 'Female', 'Prefer not to say'],
                          onChanged: (v) => setState(() => _gender = v),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Civil Status',
                          value: _civilStatus,
                          items: const [
                            'Single',
                            'Married',
                            'Widowed',
                            'Separated'
                          ],
                          onChanged: (v) => setState(() => _civilStatus = v),
                        ),
                        const SizedBox(height: 12),
                        _buildDateField(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Financial Information',
                      Icons.account_balance_wallet_outlined,
                      [
                        AppTextField(
                          label: 'GCash Number',
                          controller: _gcashCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            if (v.length != 11) {
                              return 'GCash number must be 11 digits';
                            }
                            if (!v.startsWith('09')) {
                              return 'Must start with 09';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Employment Type',
                          value: _employmentType,
                          items: const [
                            'Employed',
                            'Self-Employed',
                            'Business Owner',
                            'OFW',
                            'Freelancer',
                            'Unemployed',
                          ],
                          onChanged: (v) => setState(() => _employmentType = v),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Employer / Business Name',
                          controller: _employerCtrl,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Monthly Income (₱)',
                          controller: _incomeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            final d = double.tryParse(v);
                            if (d == null || d < 0) {
                              return 'Enter a valid amount';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: state.isSaving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.lenderPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: state.isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            context.go(RouteConstants.lenderProfile),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.lenderPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: AppColors.lenderPurple),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.lenderPurple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDateField() {
    final fmt = DateFormat('MMMM d, yyyy');
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Date of Birth',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dob != null ? fmt.format(_dob!) : 'Select date',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dob != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontWeight:
                          _dob != null ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
