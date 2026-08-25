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
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  String? _gender;
  String? _civilStatus;
  String? _employmentType;
  String? _sourceOfFunds;
  DateTime? _dob;
  String? _dobError;
  bool _initialized = false;

  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _civilOptions = ['Single', 'Married', 'Widowed', 'Separated'];
  static const _employmentOptions = [
    'Employed',
    'Self-Employed',
    'Business Owner',
    'OFW',
    'Freelancer',
    'Unemployed',
  ];
  static const _sourceOfFundsOptions = [
    'Salary',
    'Business Income',
    'Remittance',
    'Allowance',
    'Pension',
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  /// Convert a display value (e.g. "Self-Employed", "Prefer not to say") to
  /// the lowercase/underscored form the lender_profiles CHECK constraints use.
  String _toDbEnum(String value) {
    final v = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
    if (v == 'prefer_not_to_say') return 'other';
    return v;
  }

  /// Pick the exact option label for a stored enum value so the dropdown value
  /// always exists in its items list (otherwise DropdownButtonFormField throws
  /// a "There should be exactly one item with [DropdownButton]'s value"
  /// assertion). Falls back to null when the stored value doesn't match.
  String? _normalizeOption(
    String? value,
    List<String> options, {
    Map<String, String>? aliases,
  }) {
    if (value == null || value.isEmpty) return null;
    final key = value.trim().toLowerCase();
    if (aliases != null && aliases.containsKey(key)) {
      final target = aliases[key]!;
      return options.contains(target) ? target : null;
    }
    for (final opt in options) {
      if (opt.toLowerCase().replaceAll(RegExp(r'[\s-]'), '_') == key) {
        return opt;
      }
    }
    return null;
  }

  void _initFromState() {
    if (_initialized) return;
    final user = ref.read(lenderProfileProvider).user;
    if (user == null) return;
    _firstNameCtrl.text = user.firstName;
    _lastNameCtrl.text = user.lastName;
    _middleNameCtrl.text = user.middleName ?? '';
    _gender = _normalizeOption(user.gender, _genderOptions, aliases: {
      'other': 'Prefer not to say',
      'prefer_not_to_say': 'Prefer not to say',
    });
    _civilStatus = _normalizeOption(user.civilStatus, _civilOptions);
    _employmentType = _normalizeOption(user.employmentType, _employmentOptions);
    _sourceOfFunds =
        _normalizeOption(user.sourceOfFunds, _sourceOfFundsOptions);
    _dob = user.dateOfBirth;
    _employerCtrl.text = user.employerName ?? '';
    _incomeCtrl.text = user.monthlyIncome != null
        ? (user.monthlyIncome! % 1 == 0
            ? user.monthlyIncome!.toInt().toString()
            : user.monthlyIncome.toString())
        : '';
    _streetCtrl.text = user.streetAddress ?? '';
    _barangayCtrl.text = user.barangay ?? '';
    _cityCtrl.text = user.city ?? '';
    _provinceCtrl.text = user.province ?? '';
    _zipCtrl.text = user.zipCode ?? '';
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
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
            primary: AppColors.lenderBlue,
            onPrimary: Colors.white,
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
    }
  }

  Future<void> _submit() async {
    setState(
        () => _dobError = _dob == null ? 'Date of birth is required' : null);
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) return;

    final payload = <String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      if (_middleNameCtrl.text.trim().isNotEmpty)
        'middle_name': _middleNameCtrl.text.trim(),
      'lender_profile': {
        'gender': _toDbEnum(_gender!),
        'civil_status': _toDbEnum(_civilStatus!),
        'dob': DateFormat('yyyy-MM-dd').format(_dob!),
        'employment_type': _toDbEnum(_employmentType!),
        'employer_name': _employerCtrl.text.trim(),
        'monthly_income': double.tryParse(_incomeCtrl.text.trim()),
        'source_of_funds': _toDbEnum(_sourceOfFunds ?? 'other'),
        'street_address': _streetCtrl.text.trim(),
        'barangay': _barangayCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'zip_code': _zipCtrl.text.trim(),
      },
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
      accentColor: AppColors.lenderBlue,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                          maxLength: 100,
                          validator: _requiredValidator('First name'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Middle Name (Optional)',
                          controller: _middleNameCtrl,
                          maxLength: 100,
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            if (v.trim().length < 2) {
                              return 'Middle name must be at least 2 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Last Name',
                          controller: _lastNameCtrl,
                          maxLength: 100,
                          validator: _requiredValidator('Last name'),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Gender',
                          value: _gender,
                          items: _genderOptions,
                          validator: (v) =>
                              v == null ? 'Gender is required' : null,
                          onChanged: (v) => setState(() => _gender = v),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Civil Status',
                          value: _civilStatus,
                          items: _civilOptions,
                          validator: (v) =>
                              v == null ? 'Civil status is required' : null,
                          onChanged: (v) => setState(() => _civilStatus = v),
                        ),
                        const SizedBox(height: 12),
                        _buildDateField(),
                        if (_dobError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 12),
                            child: Text(
                              _dobError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Financial Information',
                      Icons.account_balance_wallet_outlined,
                      [
                        _buildDropdownField(
                          label: 'Employment Type',
                          value: _employmentType,
                          items: _employmentOptions,
                          validator: (v) =>
                              v == null ? 'Employment type is required' : null,
                          onChanged: (v) => setState(() => _employmentType = v),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Employer / Business Name',
                          controller: _employerCtrl,
                          maxLength: 255,
                          validator:
                              _requiredValidator('Employer / business name'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Monthly Income (₱)',
                          controller: _incomeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          maxLength: 12,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Monthly income is required';
                            }
                            final d = double.tryParse(v.trim());
                            if (d == null || d <= 0) {
                              return 'Enter a valid amount greater than 0';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField(
                          label: 'Source of Funds',
                          value: _sourceOfFunds,
                          items: _sourceOfFundsOptions,
                          validator: (v) =>
                              v == null ? 'Source of funds is required' : null,
                          onChanged: (v) => setState(() => _sourceOfFunds = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Residence Address',
                      Icons.location_on_outlined,
                      [
                        AppTextField(
                          label: 'Street Address',
                          controller: _streetCtrl,
                          maxLength: 100,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Barangay',
                          controller: _barangayCtrl,
                          maxLength: 100,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'City / Municipality',
                          controller: _cityCtrl,
                          maxLength: 100,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Province',
                          controller: _provinceCtrl,
                          maxLength: 100,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'ZIP Code',
                          controller: _zipCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: state.isSaving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.lenderBlue,
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

  String? Function(String?) _requiredValidator(String label) {
    return (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.lenderBlue),
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
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required String? Function(String?) validator,
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
          borderSide: const BorderSide(color: AppColors.lenderBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
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
          border: Border.all(
            color: _dobError != null ? AppColors.error : AppColors.border,
          ),
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
                    'Date of Birth *',
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
