// lib/presentation/features/lender/kyc/screens/lender_kyc_submit_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/lender_kyc_provider.dart';

class LenderKycSubmitScreen extends ConsumerStatefulWidget {
  const LenderKycSubmitScreen({super.key});

  @override
  ConsumerState<LenderKycSubmitScreen> createState() =>
      _LenderKycSubmitScreenState();
}

class _LenderKycSubmitScreenState extends ConsumerState<LenderKycSubmitScreen> {
  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.lenderDashboard),
    MobileNavItem(
        icon: Icons.account_balance_outlined,
        activeIcon: Icons.account_balance,
        label: 'My Loan',
        route: RouteConstants.lenderLoans),
    MobileNavItem(
        icon: Icons.payment_outlined,
        activeIcon: Icons.payment,
        label: 'Payments',
        route: RouteConstants.lenderPayments),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.lenderProfile),
  ];

  final Map<String, PlatformFile?> _selectedFiles = {
    'valid_id': null,
    'selfie': null,
    'proof_of_billing': null,
    'proof_of_income': null,
  };

  final Map<String, String> _docLabels = {
    'valid_id': 'Valid Government ID *',
    'selfie': 'Selfie with ID *',
    'proof_of_billing': 'Proof of Billing *',
    'proof_of_income': 'Proof of Income *',
  };

  final Map<String, IconData> _docIcons = {
    'valid_id': Icons.badge_outlined,
    'selfie': Icons.face_outlined,
    'proof_of_billing': Icons.receipt_outlined,
    'proof_of_income': Icons.work_outline,
  };

  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _ecNameCtrl = TextEditingController();
  final _ecPhoneCtrl = TextEditingController();
  String? _gender;
  String? _civilStatus;
  String? _employmentType;
  String? _sourceOfFunds;
  String? _ecRelationship;
  DateTime? _dob;
  String? _dobError;

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
  static const _relationshipOptions = [
    'Spouse',
    'Parent',
    'Sibling',
    'Child',
    'Relative',
    'Friend',
    'Other',
  ];

  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _gcashCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    _ecNameCtrl.dispose();
    _ecPhoneCtrl.dispose();
    super.dispose();
  }

  /// Convert a display value (e.g. "Self-Employed", "Prefer not to say") to
  /// the lowercase/underscored form the lender_profiles CHECK constraints use.
  String _toDbEnum(String value) {
    final v = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
    if (v == 'prefer_not_to_say') return 'other';
    return v;
  }

  Future<void> _pickFile(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFiles[docType] = result.files.first);
    }
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
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = null;
      });
    }
  }

  Future<void> _submit() async {
    final missing = _selectedFiles.entries
        .where((e) => e.value == null)
        .map((e) => _docLabels[e.key]!)
        .toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please upload: ${missing.join(', ')}')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) return;

    setState(() => _isSubmitting = true);
    try {
      final docs = <Map<String, dynamic>>[];
      for (final e in _selectedFiles.entries) {
        final f = e.value;
        if (f == null) continue;
        final path = f.path;
        Uint8List? fileBytes;
        if (f.bytes != null) {
          fileBytes = f.bytes;
        } else if (path != null) {
          fileBytes = await File(path).readAsBytes();
        }
        docs.add({
          'document_type': e.key,
          'file_name': f.name,
          'file_size': f.size,
          if (fileBytes != null) 'content_base64': base64Encode(fileBytes),
        });
      }

      // Everything the lender fills in KYC lives on their profile — the
      // profile screen only displays these details afterwards.
      final payload = <String, dynamic>{
        'profile': {
          'first_name': _firstNameCtrl.text.trim(),
          if (_middleNameCtrl.text.trim().isNotEmpty)
            'middle_name': _middleNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          if (_suffixCtrl.text.trim().isNotEmpty)
            'suffix': _suffixCtrl.text.trim(),
          'gender': _toDbEnum(_gender!),
          'civil_status': _toDbEnum(_civilStatus!),
          'dob': DateFormat('yyyy-MM-dd').format(_dob!),
          'employment_type': _toDbEnum(_employmentType!),
          'employer_name': _employerCtrl.text.trim(),
          'monthly_income': double.tryParse(_incomeCtrl.text.trim()),
          'gcash_number': _gcashCtrl.text.trim(),
        },
        'address_info': {
          'street_address': _streetCtrl.text.trim(),
          'barangay': _barangayCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'province': _provinceCtrl.text.trim(),
          'zip_code': _zipCtrl.text.trim(),
        },
        'source_of_funds': _toDbEnum(_sourceOfFunds!),
        'emergency_contact': {
          'name': _ecNameCtrl.text.trim(),
          'relationship': _ecRelationship,
          'phone_number': _ecPhoneCtrl.text.trim(),
        },
      };

      final ok = await ref
          .read(lenderKycProvider.notifier)
          .submitKyc(docs, info: payload);
      // Use mounted (not context.mounted) to guard all async context use
      if (ok) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => const SuccessDialog(
            message: 'KYC documents submitted successfully. Under review.',
          ),
        );
        if (!mounted) return;
        context.go(RouteConstants.lenderDashboard);
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => const ErrorDialog(
            message: 'Failed to submit KYC documents. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderKycProvider);

    return MobileScaffold(
      title: 'KYC Verification',
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBanner(state),
                  const SizedBox(height: 20),
                  _buildInformationSection(),
                  const SizedBox(height: 20),
                  const Text('Required Documents',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  const Text(
                      'Upload clear, legible photos or scans. Files must be JPG, PNG, or PDF under 5MB.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                  ..._selectedFiles.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _DocUploadCard(
                          label: _docLabels[e.key]!,
                          icon: _docIcons[e.key]!,
                          file: e.value,
                          onPick: () => _pickFile(e.key),
                        ),
                      )),
                  const SizedBox(height: 8),
                  if (state.status == 'submitted' ||
                      state.status == 'under_review')
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3))),
                      child: const Row(
                        children: [
                          Icon(Icons.hourglass_top_outlined,
                              color: AppColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Your KYC is under review. We will notify you once verified.',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.warning))),
                        ],
                      ),
                    )
                  else
                    AppButton(
                      label: _isSubmitting
                          ? 'Submitting...'
                          : 'Submit KYC Documents',
                      onPressed: _isSubmitting ? null : _submit,
                      color: AppColors.lenderPurple,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInformationSection() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildSectionCard(
            'Personal Information',
            Icons.person_outline,
            [
              AppTextField(
                label: 'First Name *',
                controller: _firstNameCtrl,
                validator: _required('First name'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Middle Name (Optional)',
                controller: _middleNameCtrl,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Last Name *',
                controller: _lastNameCtrl,
                validator: _required('Last name'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Suffix (Optional)',
                hint: 'e.g. Jr., Sr., III',
                controller: _suffixCtrl,
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Gender *',
                value: _gender,
                items: _genderOptions,
                validator: (v) => v == null ? 'Gender is required' : null,
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Civil Status *',
                value: _civilStatus,
                items: _civilOptions,
                validator: (v) => v == null ? 'Civil status is required' : null,
                onChanged: (v) => setState(() => _civilStatus = v),
              ),
              const SizedBox(height: 12),
              _buildDateField(),
              if (_dobError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    _dobError!,
                    style: const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            'Financial Information',
            Icons.account_balance_wallet_outlined,
            [
              AppTextField(
                label: 'GCash Number *',
                controller: _gcashCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'GCash number is required';
                  }
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
              _buildDropdown(
                label: 'Employment Type *',
                value: _employmentType,
                items: _employmentOptions,
                validator: (v) => v == null ? 'Employment type is required' : null,
                onChanged: (v) => setState(() => _employmentType = v),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Employer / Business Name *',
                controller: _employerCtrl,
                validator: _required('Employer / business name'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Monthly Income (₱) *',
                controller: _incomeCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
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
              _buildDropdown(
                label: 'Source of Funds *',
                value: _sourceOfFunds,
                items: _sourceOfFundsOptions,
                validator: (v) => v == null ? 'Source of funds is required' : null,
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
                label: 'Street Address *',
                controller: _streetCtrl,
                validator: _required('Street address'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Barangay *',
                controller: _barangayCtrl,
                validator: _required('Barangay'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'City / Municipality *',
                      controller: _cityCtrl,
                      validator: _required('City / municipality'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      label: 'Province *',
                      controller: _provinceCtrl,
                      validator: _required('Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'ZIP Code *',
                controller: _zipCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'ZIP code is required';
                  }
                  if (v.trim().length != 4) {
                    return 'ZIP code must be 4 digits';
                  }
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            'Emergency Contact',
            Icons.emergency_outlined,
            [
              const Text(
                'In case we need to reach someone related to you.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Contact Name *',
                controller: _ecNameCtrl,
                validator: _required('Contact name'),
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Relationship *',
                value: _ecRelationship,
                items: _relationshipOptions,
                validator: (v) => v == null ? 'Relationship is required' : null,
                onChanged: (v) => setState(() => _ecRelationship = v),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Contact Phone Number *',
                controller: _ecPhoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Phone number is required';
                  }
                  if (v.length != 11 || !v.startsWith('09')) {
                    return 'Must be an 11-digit number starting with 09';
                  }
                  return null;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
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

  String? Function(String?) _required(String label) {
    return (v) =>
        (v == null || v.trim().isEmpty) ? '$label is required' : null;
  }

  Widget _buildDropdown({
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
          borderSide:
              const BorderSide(color: AppColors.lenderPurple, width: 1.5),
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

  Widget _buildStatusBanner(LenderKycState state) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String message;

    switch (state.status) {
      case 'verified':
        bgColor = AppColors.successLight;
        textColor = AppColors.success;
        icon = Icons.verified_user;
        message = 'Your identity has been verified!';
        break;
      case 'submitted':
      case 'under_review':
        bgColor = AppColors.warningLight;
        textColor = AppColors.warning;
        icon = Icons.pending_outlined;
        message = 'Documents under review';
        break;
      case 'rejected':
        bgColor = AppColors.errorLight;
        textColor = AppColors.error;
        icon = Icons.cancel_outlined;
        message = state.rejectionNotes ?? 'KYC rejected. Please resubmit.';
        break;
      default:
        bgColor = AppColors.infoLight;
        textColor = AppColors.info;
        icon = Icons.info_outline;
        message = 'Complete KYC to apply for a loan';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _DocUploadCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final PlatformFile? file;
  final VoidCallback onPick;
  const _DocUploadCard(
      {required this.label,
      required this.icon,
      this.file,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.lenderPurple.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: hasFile
                  ? AppColors.lenderPurple.withValues(alpha: 0.3)
                  : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile
                    ? AppColors.lenderPurple.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color:
                      hasFile ? AppColors.lenderPurple : AppColors.textTertiary,
                  size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    hasFile ? file!.name : 'Tap to upload',
                    style: TextStyle(
                        fontSize: 12,
                        color: hasFile
                            ? AppColors.lenderPurple
                            : AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(hasFile ? Icons.check_circle : Icons.upload_file_outlined,
                color: hasFile ? AppColors.success : AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
