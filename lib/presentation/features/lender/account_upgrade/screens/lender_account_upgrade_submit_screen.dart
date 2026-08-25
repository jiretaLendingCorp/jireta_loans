// lib/presentation/features/lender/account_upgrade/screens/lender_account_upgrade_submit_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/lender_account_upgrade_provider.dart';
import 'valid_id_scanner_screen.dart';

class LenderAccountUpgradeSubmitScreen extends ConsumerStatefulWidget {
  const LenderAccountUpgradeSubmitScreen({super.key});

  @override
  ConsumerState<LenderAccountUpgradeSubmitScreen> createState() =>
      _LenderAccountUpgradeSubmitScreenState();
}

class _LenderAccountUpgradeSubmitScreenState
    extends ConsumerState<LenderAccountUpgradeSubmitScreen> {
  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.lenderDashboard),
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

  static const _steps = [
    'Personal Info',
    'Financial Info',
    'Residence',
    'Docs & Submit'
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

  final Map<String, String> _docHints = {
    'valid_id': 'A valid government-issued ID',
    'selfie': 'A clear selfie holding your ID',
    'proof_of_billing': 'Recent utility or billing statement',
    'proof_of_income': 'Pay slip, bank statement, or COE',
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
  final _emailCtrl = TextEditingController();
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

  int _step = 0;
  bool _isSubmitting = false;

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

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
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
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourcePickerSheet(
        title: _docLabels[docType]!,
        onCamera: () => Navigator.of(context).pop('camera'),
        onGallery: () => Navigator.of(context).pop('gallery'),
      ),
    );
    if (!mounted) return;
    if (action == 'camera') {
      await _pickFromCamera(docType);
    } else if (action == 'gallery') {
      await _pickFromGallery(docType);
    }
  }

  Future<void> _pickFromCamera(String docType) async {
    if (docType == 'valid_id') {
      // Launch the dedicated Valid ID Scanner UI.
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const ValidIdScannerScreen()),
      );
      if (bytes != null && mounted) {
        setState(() {
          _selectedFiles[docType] = PlatformFile(
            name: 'valid_id_${DateTime.now().millisecondsSinceEpoch}.jpg',
            size: bytes.length,
            bytes: bytes,
          );
        });
      }
      return;
    }

    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img != null && mounted) {
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedFiles[docType] = PlatformFile(
          name: '${docType}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          size: bytes.length,
          bytes: bytes,
        );
      });
    }
  }

  Future<void> _pickFromGallery(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
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

  bool _isAdult(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 18;
  }

  void _goNext() {
    if (!_formKey.currentState!.validate()) return;
    if (_step == 0) {
      if (_dob == null) {
        setState(() => _dobError = 'Date of birth is required');
        context.showSnackBarAsToast(const SnackBar(
          content: Text('Please select your date of birth to continue.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
      if (!_isAdult(_dob!)) {
        setState(() => _dobError =
            'You must be at least 18 years old to submit account upgrade.');
        context.showSnackBarAsToast(const SnackBar(
          content: Text('You must be at least 18 years old to continue.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }
    setState(() => _step = _step + 1);
  }

  void _goBack() => setState(() => _step = _step - 1);

  Future<void> _submit() async {
    final missing = _selectedFiles.entries
        .where((e) => e.value == null)
        .map((e) => _docLabels[e.key]!)
        .toList();
    if (missing.isNotEmpty) {
      context.showSnackBarAsToast(
          SnackBar(content: Text('Please upload: ${missing.join(', ')}')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _dobError = 'Date of birth is required');
      return;
    }
    if (!_isAdult(_dob!)) {
      setState(() => _dobError =
          'You must be at least 18 years old to submit account upgrade.');
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text(
              'You must be at least 18 years old to submit account upgrade documents.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final docs = <Map<String, dynamic>>[];
      for (final e in _selectedFiles.entries) {
        final f = e.value;
        if (f == null) continue;
        Uint8List? fileBytes;
        if (f.bytes != null) {
          fileBytes = f.bytes;
        } else {
          final path = f.path;
          if (path != null) {
            fileBytes = await File(path).readAsBytes();
          }
        }
        docs.add({
          'document_type': e.key,
          'file_name': f.name,
          'file_size': f.size,
          if (fileBytes != null) 'content_base64': base64Encode(fileBytes),
        });
      }

      // Everything the lender fills in the account upgrade lives on their
      // profile — the profile screen only displays these details afterwards.
      final payload = <String, dynamic>{
        'profile': {
          'first_name': _firstNameCtrl.text.trim(),
          if (_middleNameCtrl.text.trim().isNotEmpty)
            'middle_name': _middleNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          if (_suffixCtrl.text.trim().isNotEmpty)
            'suffix': _suffixCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'gender': _toDbEnum(_gender!),
          'civil_status': _toDbEnum(_civilStatus!),
          'dob': DateFormat('yyyy-MM-dd').format(_dob!),
          'employment_type': _toDbEnum(_employmentType!),
          'employer_name': _employerCtrl.text.trim(),
          'monthly_income': double.tryParse(_incomeCtrl.text.trim()),
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
          .read(lenderAccountUpgradeProvider.notifier)
          .submitAccountUpgrade(docs, info: payload);
      // Use mounted (not context.mounted) to guard all async context use
      if (ok) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => const SuccessDialog(
            message:
                'Account upgrade documents submitted successfully. Under review.',
          ),
        );
        if (!mounted) return;
        context.go(RouteConstants.lenderDashboard);
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => const ErrorDialog(
            message:
                'Failed to submit account upgrade documents. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderAccountUpgradeProvider);

    return MobileScaffold(
      title: 'Account Upgrade Verification',
      accentColor: AppColors.lenderBlue,
      navItems: _navItems,
      showBackButton: true,
      body: state.isLoading ? const ShimmerLoader() : _buildFlow(state),
    );
  }

  Widget _buildFlow(LenderAccountUpgradeState state) {
    final status = state.status;
    if (status == 'submitted' ||
        status == 'under_review' ||
        status == 'verified') {
      return _buildSubmittedView(state);
    }

    return Column(
      children: [
        _buildStatusBanner(state),
        _StepIndicator(current: _step, labels: _steps),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: _buildStepContent(),
          ),
        ),
        _buildWizardBar(state),
      ],
    );
  }

  Widget _buildSubmittedView(LenderAccountUpgradeState state) {
    final status = state.status;
    final isVerified = status == 'verified';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusBanner(state),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  isVerified ? AppColors.successLight : AppColors.warningLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isVerified ? AppColors.success : AppColors.warning)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isVerified
                      ? Icons.verified_user
                      : Icons.hourglass_top_outlined,
                  color: isVerified ? AppColors.success : AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isVerified
                        ? 'Your identity has been verified. You can now apply for a loan.'
                        : 'Your account upgrade is under review. We will notify you once verified.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isVerified ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'View Status',
            onPressed: () =>
                context.push(RouteConstants.lenderAccountUpgradeStatus),
            color: AppColors.lenderBlue,
            icon: Icons.timeline_outlined,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildPersonalInformation();
      case 1:
        return _buildFinancialInformation();
      case 2:
        return _buildResidenceAddress();
      default:
        return _buildEmergencyAndDocuments();
    }
  }

  Widget _buildPersonalInformation() {
    return Form(
      key: _formKey,
      child: _buildSectionCard(
        'Personal Information',
        Icons.person_outline,
        [
          AppTextField(
            label: 'First Name *',
            controller: _firstNameCtrl,
            maxLength: 100,
            validator: _required('First name'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Middle Name (Optional)',
            controller: _middleNameCtrl,
            maxLength: 100,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Last Name *',
            controller: _lastNameCtrl,
            maxLength: 100,
            validator: _required('Last name'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Suffix (Optional)',
            hint: 'e.g. Jr., Sr., III',
            controller: _suffixCtrl,
            maxLength: 20,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Email Address *',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            maxLength: 255,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Email address is required';
              }
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
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
    );
  }

  Widget _buildFinancialInformation() {
    return Form(
      key: _formKey,
      child: _buildSectionCard(
        'Financial Information',
        Icons.account_balance_wallet_outlined,
        [
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
            maxLength: 255,
            validator: _required('Employer / business name'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Monthly Income (₱) *',
            controller: _incomeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            maxLength: 12,
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
    );
  }

  Widget _buildResidenceAddress() {
    return Form(
      key: _formKey,
      child: _buildSectionCard(
        'Residence Address',
        Icons.location_on_outlined,
        [
          AppTextField(
            label: 'Street Address *',
            controller: _streetCtrl,
            maxLength: 100,
            validator: _required('Street address'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Barangay *',
            controller: _barangayCtrl,
            maxLength: 100,
            validator: _required('Barangay'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'City / Municipality *',
                  controller: _cityCtrl,
                  maxLength: 100,
                  validator: _required('City / municipality'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  label: 'Province *',
                  controller: _provinceCtrl,
                  maxLength: 100,
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
    );
  }

  Widget _buildEmergencyAndDocuments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Form(
          key: _formKey,
          child: _buildSectionCard(
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
                maxLength: 100,
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
        ),
        const SizedBox(height: 16),
        const Text(
          'Required Documents',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap each document to capture with your camera or choose from your gallery. Files must be JPG, PNG, or PDF under 5MB.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        ..._selectedFiles.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _DocUploadCard(
                label: _docLabels[e.key]!,
                hint: _docHints[e.key]!,
                icon: _docIcons[e.key]!,
                file: e.value,
                onPick: () => _pickFile(e.key),
              ),
            )),
      ],
    );
  }

  Widget _buildWizardBar(LenderAccountUpgradeState state) {
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
                color: AppColors.lenderBlue,
                onTap: _goBack,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: AppButton(
              label: isLast
                  ? (_isSubmitting
                      ? 'Submitting...'
                      : 'Submit Account Upgrade Documents')
                  : 'Next',
              icon: isLast ? Icons.send : Icons.arrow_forward,
              color: AppColors.lenderBlue,
              isLoading: _isSubmitting,
              onTap: isLast ? _submit : _goNext,
            ),
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
      ),
    );
  }

  String? Function(String?) _required(String label) {
    return (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;
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

  Widget _buildStatusBanner(LenderAccountUpgradeState state) {
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
        message = state.rejectionNotes ??
            'Account upgrade rejected. Please resubmit.';
        break;
      default:
        bgColor = AppColors.infoLight;
        textColor = AppColors.info;
        icon = Icons.info_outline;
        message = 'Complete Account Upgrade to apply for a loan';
    }

    return Container(
      width: double.infinity,
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

class _StepIndicator extends StatelessWidget {
  final int current;
  final List<String> labels;

  const _StepIndicator({required this.current, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
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
              label: labels[i],
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
            fontSize: 9.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: highlighted ? AppColors.lenderBlue : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _SourcePickerSheet extends StatelessWidget {
  final String title;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _SourcePickerSheet({
    required this.title,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose how you want to provide this document.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SourceOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Take Photo',
                    onTap: onCamera,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceOption(
                    icon: Icons.folder_outlined,
                    label: 'From Gallery',
                    onTap: onGallery,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.lenderBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.lenderBlue.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.lenderBlue, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocUploadCard extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final PlatformFile? file;
  final VoidCallback onPick;

  const _DocUploadCard({
    required this.label,
    required this.hint,
    required this.icon,
    this.file,
    required this.onPick,
  });

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
              ? AppColors.lenderBlue.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: hasFile
                  ? AppColors.lenderBlue.withValues(alpha: 0.3)
                  : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile
                    ? AppColors.lenderBlue.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color:
                      hasFile ? AppColors.lenderBlue : AppColors.textTertiary,
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
                    hasFile ? file!.name : hint,
                    style: TextStyle(
                        fontSize: 12,
                        color: hasFile
                            ? AppColors.lenderBlue
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
