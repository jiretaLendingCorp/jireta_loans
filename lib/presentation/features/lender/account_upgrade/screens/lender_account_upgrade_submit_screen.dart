// ignore_for_file: curly_braces_in_flow_control_structures
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
import '../../../../shared/widgets/forms/app_text_field.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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

  // Residence moved to Financial Info per request (was in final step)
  static const _steps = [
    'Personal Info',
    'Financial Info',
    'Emergency & Docs',
  ];

  final Map<String, PlatformFile?> _selectedFiles = {
    'valid_id': null,
    'selfie': null,
    'mayors_permit': null,
    'birth_certificate': null,
  };

  // Back side of the Valid ID, captured together with the front by the
  // scanner but shown as a single "Valid ID" document in the UI.
  PlatformFile? _validIdBackFile;

  bool get _hasValidIdFront => _selectedFiles['valid_id'] != null;
  bool get _hasValidIdBack => _validIdBackFile != null;
  bool get _hasValidIdComplete => _hasValidIdFront && _hasValidIdBack;

  final Map<String, String> _docLabels = {
    'valid_id': 'Valid Government ID *',
    'selfie': 'Selfie with ID *',
    'mayors_permit': "Mayor's Permit *",
    'birth_certificate': 'Birth Certificate *',
  };

  final Map<String, String> _docHints = {
    'valid_id': 'Philippine government-issued ID (UMID, PhilSys, Driver\'s License, Passport, etc.)',
    'selfie': 'A clear selfie holding your Valid ID',
    'mayors_permit': "Valid Mayor's Permit / Business Permit",
    'birth_certificate': 'PSA/NSO Birth Certificate',
  };

  final Map<String, IconData> _docIcons = {
    'valid_id': Icons.contact_page_rounded,
    'selfie': Icons.face_retouching_natural_rounded,
    'mayors_permit': Icons.business_rounded,
    'birth_certificate': Icons.child_care_rounded,
  };

  // Asset icons for verification docs — rendered without background per design
  final Map<String, String?> _docAssetIcons = {
    'valid_id': 'assets/icons/id_card.png',
    'selfie': 'assets/icons/selfie with id.png',
    'mayors_permit': 'assets/icons/PERMIT.png',
    'birth_certificate': 'assets/icons/birth certificate.jpg',
  };

  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _employmentOtherCtrl = TextEditingController();
  final _sourceOtherCtrl = TextEditingController();
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
  final ScrollController _scrollController = ScrollController();
  final FocusNode _streetFocusNode = FocusNode();
  final FocusNode _barangayFocusNode = FocusNode();
  final FocusNode _cityFocusNode = FocusNode();
  final FocusNode _provinceFocusNode = FocusNode();
  final FocusNode _zipFocusNode = FocusNode();
  final FocusNode _ecNameFocusNode = FocusNode();
  final FocusNode _ecPhoneFocusNode = FocusNode();

  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _civilOptions = ['Single', 'Married', 'Widowed', 'Separated'];
  static const _employmentOptions = [
    'Employed',
    'Self-Employed',
    'Business Owner',
    'OFW',
    'Freelancer',
    'Unemployed',
    'Student',
    'Other',
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
  void initState() {
    super.initState();
    _firstNameCtrl.addListener(_onFieldChanged);
    _middleNameCtrl.addListener(_onFieldChanged);
    _lastNameCtrl.addListener(_onFieldChanged);
    _suffixCtrl.addListener(_onFieldChanged);
    _emailCtrl.addListener(_onFieldChanged);
    _employerCtrl.addListener(_onFieldChanged);
    _incomeCtrl.addListener(_onFieldChanged);
    _employmentOtherCtrl.addListener(_onFieldChanged);
    _sourceOtherCtrl.addListener(_onFieldChanged);
    _streetCtrl.addListener(_onFieldChanged);
    _barangayCtrl.addListener(_onFieldChanged);
    _cityCtrl.addListener(_onFieldChanged);
    _provinceCtrl.addListener(_onFieldChanged);
    _zipCtrl.addListener(_onFieldChanged);
    _ecNameCtrl.addListener(_onFieldChanged);
    _ecPhoneCtrl.addListener(_onFieldChanged);
    _streetFocusNode.addListener(_onBottomFieldFocus);
    _barangayFocusNode.addListener(_onBottomFieldFocus);
    _cityFocusNode.addListener(_onBottomFieldFocus);
    _provinceFocusNode.addListener(_onBottomFieldFocus);
    _zipFocusNode.addListener(_onBottomFieldFocus);
    _ecNameFocusNode.addListener(_onBottomFieldFocus);
    _ecPhoneFocusNode.addListener(_onBottomFieldFocus);
  }

  void _onBottomFieldFocus() {
    FocusNode? focused;
    if (_streetFocusNode.hasFocus) focused = _streetFocusNode;
    else if (_barangayFocusNode.hasFocus) focused = _barangayFocusNode;
    else if (_cityFocusNode.hasFocus) focused = _cityFocusNode;
    else if (_provinceFocusNode.hasFocus) focused = _provinceFocusNode;
    else if (_zipFocusNode.hasFocus) focused = _zipFocusNode;
    else if (_ecNameFocusNode.hasFocus) focused = _ecNameFocusNode;
    else if (_ecPhoneFocusNode.hasFocus) focused = _ecPhoneFocusNode;
    if (focused == null) return;
    final ctx = focused.context;
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.25,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.removeListener(_onFieldChanged);
    _middleNameCtrl.removeListener(_onFieldChanged);
    _lastNameCtrl.removeListener(_onFieldChanged);
    _suffixCtrl.removeListener(_onFieldChanged);
    _emailCtrl.removeListener(_onFieldChanged);
    _employerCtrl.removeListener(_onFieldChanged);
    _incomeCtrl.removeListener(_onFieldChanged);
    _employmentOtherCtrl.removeListener(_onFieldChanged);
    _sourceOtherCtrl.removeListener(_onFieldChanged);
    _streetCtrl.removeListener(_onFieldChanged);
    _barangayCtrl.removeListener(_onFieldChanged);
    _cityCtrl.removeListener(_onFieldChanged);
    _provinceCtrl.removeListener(_onFieldChanged);
    _zipCtrl.removeListener(_onFieldChanged);
    _ecNameCtrl.removeListener(_onFieldChanged);
    _ecPhoneCtrl.removeListener(_onFieldChanged);
    _streetFocusNode.removeListener(_onBottomFieldFocus);
    _barangayFocusNode.removeListener(_onBottomFieldFocus);
    _cityFocusNode.removeListener(_onBottomFieldFocus);
    _provinceFocusNode.removeListener(_onBottomFieldFocus);
    _zipFocusNode.removeListener(_onBottomFieldFocus);
    _ecNameFocusNode.removeListener(_onBottomFieldFocus);
    _ecPhoneFocusNode.removeListener(_onBottomFieldFocus);
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    _employmentOtherCtrl.dispose();
    _sourceOtherCtrl.dispose();
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    _ecNameCtrl.dispose();
    _ecPhoneCtrl.dispose();
    _scrollController.dispose();
    _streetFocusNode.dispose();
    _barangayFocusNode.dispose();
    _cityFocusNode.dispose();
    _provinceFocusNode.dispose();
    _zipFocusNode.dispose();
    _ecNameFocusNode.dispose();
    _ecPhoneFocusNode.dispose();
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
      // Single Valid ID document: the scanner captures Front + Back in
      // one flow and returns both sides together.
      final result = await Navigator.of(context).push<IdScanResult>(
        MaterialPageRoute(builder: (_) => const ValidIdScannerScreen()),
      );
      if (result != null && mounted) {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          _selectedFiles['valid_id'] = PlatformFile(
            name: 'valid_id_front_$stamp.jpg',
            size: result.frontBytes.length,
            bytes: result.frontBytes,
          );
          _validIdBackFile = PlatformFile(
            name: 'valid_id_back_$stamp.jpg',
            size: result.backBytes.length,
            bytes: result.backBytes,
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
    if (docType == 'valid_id') {
      // Single Valid ID document: accept up to 2 images (front + back).
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      setState(() {
        final files = result.files;
        if (_hasValidIdFront && !_hasValidIdBack && files.length == 1) {
          // Front already captured — this one completes the back side.
          _validIdBackFile = files.first;
        } else {
          _selectedFiles['valid_id'] = files.first;
          if (files.length > 1) {
            _validIdBackFile = files[1];
          } else {
            _validIdBackFile = null;
          }
        }
      });
      if (mounted && !_hasValidIdComplete) {
        context.showSnackBarAsToast(const SnackBar(
          content: Text(
              'Valid ID needs both sides — pick the back side image too.'),
        ));
      }
      return;
    }
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

  // ── Helpers for peso formatting ──
  double? _parseIncome() {
    final raw = _incomeCtrl.text.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  // ── Validation for Next button (live, disables Next until required filled) ──
  bool _isPersonalInfoValid() {
    if (_firstNameCtrl.text.trim().isEmpty) return false;
    if (_lastNameCtrl.text.trim().isEmpty) return false;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return false;
    if (_gender == null) return false;
    if (_civilStatus == null) return false;
    if (_dob == null) return false;
    if (!_isAdult(_dob!)) return false;
    return true;
  }

  bool _isFinancialInfoValid() {
    if (_employmentType == null) return false;
    if (_employmentType == 'Other' &&
        _employmentOtherCtrl.text.trim().isEmpty) return false;
    if (_employerCtrl.text.trim().isEmpty) return false;
    final inc = _parseIncome();
    if (inc == null || inc <= 0) return false;
    if (_sourceOfFunds == null) return false;
    if (_sourceOfFunds == 'Other' &&
        _sourceOtherCtrl.text.trim().isEmpty) return false;
    // Residence is now part of Financial Info (step 1)
    if (!_isResidenceValid()) return false;
    return true;
  }

  bool _isResidenceValid() {
    if (_streetCtrl.text.trim().isEmpty) return false;
    if (_barangayCtrl.text.trim().isEmpty) return false;
    if (_cityCtrl.text.trim().isEmpty) return false;
    if (_provinceCtrl.text.trim().isEmpty) return false;
    final zip = _zipCtrl.text.trim();
    if (zip.length != 4 || int.tryParse(zip) == null) return false;
    return true;
  }

  bool _isEmergencyAndDocsValid() {
    if (_ecNameCtrl.text.trim().isEmpty) return false;
    if (_ecRelationship == null) return false;
    final phone = _ecPhoneCtrl.text.trim();
    if (phone.length != 11 ||
        !phone.startsWith('09') ||
        int.tryParse(phone) == null) return false;
    // all 4 docs must be uploaded (Valid ID needs front + back)
    if (_selectedFiles.values.any((f) => f == null)) return false;
    if (!_hasValidIdComplete) return false;
    return true;
  }

  bool get _canGoNext {
    // 3-step flow: 0 Personal, 1 Financial + Residence, 2 Emergency & Docs
    if (_step == 0) return _isPersonalInfoValid();
    if (_step == 1) return _isFinancialInfoValid();
    if (_step == 2) {
      return _isPersonalInfoValid() &&
          _isFinancialInfoValid() &&
          _isEmergencyAndDocsValid();
    }
    return false;
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
    if (_hasValidIdFront && !_hasValidIdBack) {
      missing.add('Valid Government ID (Back side)');
    }
    if (missing.isNotEmpty) {
      context.showSnackBarAsToast(
          SnackBar(content: Text('Please upload: ${missing.join(', ')}')));
      return;
    }
    // Full validation across all 3 steps (since final Form only holds residence+emergency)
    if (!_isPersonalInfoValid() ||
        !_isFinancialInfoValid() ||
        !_isResidenceValid() ||
        !_isEmergencyAndDocsValid()) {
      context.showSnackBarAsToast(const SnackBar(
        content: Text('Please complete all required fields in each step.'),
        backgroundColor: AppColors.error,
      ));
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
      // Back side of the Valid ID rides along with the single Valid ID card.
      final backFile = _validIdBackFile;
      if (backFile != null) {
        Uint8List? backBytes = backFile.bytes;
        if (backBytes == null) {
          final path = backFile.path;
          if (path != null) {
            backBytes = await File(path).readAsBytes();
          }
        }
        docs.add({
          'document_type': 'valid_id_back',
          'file_name': backFile.name,
          'file_size': backFile.size,
          if (backBytes != null) 'content_base64': base64Encode(backBytes),
        });
      }

      // Everything the lender fills in the account upgrade lives on their
      // profile — the profile screen only displays these details afterwards.
      final resolvedEmploymentType = _employmentType == 'Other'
          ? _employmentOtherCtrl.text.trim()
          : _employmentType!;
      final resolvedSourceOfFunds = _sourceOfFunds == 'Other'
          ? _sourceOtherCtrl.text.trim()
          : _sourceOfFunds!;
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
          'employment_type': _toDbEnum(resolvedEmploymentType),
          // When Other, also send the raw reason for debugging/audit
          if (_employmentType == 'Other')
            'employment_type_other': _employmentOtherCtrl.text.trim(),
          'employer_name': _employerCtrl.text.trim(),
          'monthly_income': _parseIncome(),
        },
        'address_info': {
          'street_address': _streetCtrl.text.trim(),
          'barangay': _barangayCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'province': _provinceCtrl.text.trim(),
          'zip_code': _zipCtrl.text.trim(),
        },
        'source_of_funds': _toDbEnum(resolvedSourceOfFunds),
        if (_sourceOfFunds == 'Other')
          'source_of_funds_other': _sourceOtherCtrl.text.trim(),
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
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Account upgrade documents submitted successfully. Under review.'),
            backgroundColor: AppColors.success,
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

    // When verified/success, hide verification UI and redirect directly to home
    if (!state.isLoading && (state.status == 'verified' || state.status == 'approved')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(RouteConstants.lenderDashboard);
      });
      return const MobileScaffold(
        title: 'Account Upgrade Verification',
        accentColor: AppColors.lenderBlue,
        navItems: _navItems,
        showBackButton: true,
        body: _AccountUpgradeVerificationSkeleton(),
      );
    }

    return MobileScaffold(
      title: 'Account Upgrade Verification',
      accentColor: AppColors.lenderBlue,
      navItems: _navItems,
      showBackButton: true,
      body: state.isLoading ? const _AccountUpgradeVerificationSkeleton() : _buildFlow(state),
    );
  }

  Widget _buildFlow(LenderAccountUpgradeState state) {
    final status = state.status;
    // Hide verification UI when already verified — handled via redirect in build()
    if (status == 'verified' || status == 'approved') {
      return const SizedBox.shrink();
    }
    if (status == 'submitted' || status == 'under_review') {
      return _buildSubmittedView(state);
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Column(
      children: [
        _buildStatusBanner(state),
        _StepIndicator(current: _step, labels: _steps),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 100 + bottomInset),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepContent(),
                const SizedBox(height: 14),
                _buildWizardBar(state),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmittedView(LenderAccountUpgradeState state) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final status = state.status;
    final isVerified = status == 'verified';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 100 + bottomInset),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              mainAxisAlignment: MainAxisAlignment.center,
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
                    textAlign: TextAlign.center,
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
            label: 'Account Upgrade Status',
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
      default:
        // Step 2 (last) = Emergency + Docs (Residence moved to Financial Info)
        return _buildEmergencyAndDocsStep();
    }
  }

  Widget _buildEmergencyAndDocsStep() {
    // Single Form for the final step to avoid duplicate GlobalKey.
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmergencyAndDocuments(wrapForm: false, includeDocs: false),
          const SizedBox(height: 16),
          _buildDocumentsSection(),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Required Documents',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Files must be JPG, PNG, or PDF under 5MB.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _ValidIdCard(
            hasFront: _hasValidIdFront,
            hasBack: _hasValidIdBack,
            onPick: () => _pickFile('valid_id'),
          ),
        ),
        ..._selectedFiles.entries
            .where((e) => e.key != 'valid_id')
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DocUploadCard(
                    label: _docLabels[e.key]!,
                    hint: _docHints[e.key]!,
                    icon: _docIcons[e.key]!,
                    assetPath: _docAssetIcons[e.key],
                    file: e.value,
                    onPick: () => _pickFile(e.key),
                  ),
                )),
      ],
    );
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
            maxLength: 2,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z.]')),
              LengthLimitingTextInputFormatter(2),
            ],
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              if (!RegExp(r'^[a-zA-Z.]{1,2}$').hasMatch(v)) {
                return 'Max 2 letters or "." only';
              }
              return null;
            },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            'Financial Information',
            Icons.account_balance_wallet_outlined,
            [
              _buildDropdown(
                label: 'Employment Type *',
                value: _employmentType,
                items: _employmentOptions,
                validator: (v) => v == null ? 'Employment type is required' : null,
                onChanged: (v) => setState(() {
                  _employmentType = v;
                  if (v != 'Other') _employmentOtherCtrl.clear();
                }),
              ),
              if (_employmentType == 'Other') ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Please specify employment type *',
                  controller: _employmentOtherCtrl,
                  maxLength: 100,
                  validator: _required('Employment type (Other)'),
                ),
              ],
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  _PesoCurrencyFormatter(),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Monthly income is required';
                  }
                  final cleaned = v.replaceAll(RegExp(r'[₱,\s]'), '').trim();
                  final d = double.tryParse(cleaned);
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
                validator: (v) =>
                    v == null ? 'Source of funds is required' : null,
                onChanged: (v) => setState(() {
                  _sourceOfFunds = v;
                  if (v != 'Other') _sourceOtherCtrl.clear();
                }),
              ),
              if (_sourceOfFunds == 'Other') ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Please specify source of funds *',
                  controller: _sourceOtherCtrl,
                  maxLength: 100,
                  validator: _required('Source of funds (Other)'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _buildResidenceAddress(wrapForm: false),
        ],
      ),
    );
  }

  Widget _buildResidenceAddress({bool wrapForm = true}) {
    final card = _buildSectionCard(
      'Residence Address',
      Icons.location_on_outlined,
      [
        AppTextField(
          label: 'Street Address *',
          controller: _streetCtrl,
          focusNode: _streetFocusNode,
          maxLength: 100,
          validator: _required('Street address'),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: 'Barangay *',
          controller: _barangayCtrl,
          focusNode: _barangayFocusNode,
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
                focusNode: _cityFocusNode,
                maxLength: 100,
                validator: _required('City / municipality'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppTextField(
                label: 'Province *',
                controller: _provinceCtrl,
                focusNode: _provinceFocusNode,
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
          focusNode: _zipFocusNode,
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
    );
    if (!wrapForm) return card;
    return Form(key: _formKey, child: card);
  }

  Widget _buildEmergencyAndDocuments(
      {bool wrapForm = true, bool includeDocs = true}) {
    final emergencyCard = _buildSectionCard(
      'Emergency Contact',
      Icons.emergency_outlined,
      [
        AppTextField(
          label: 'Contact Name *',
          controller: _ecNameCtrl,
          focusNode: _ecNameFocusNode,
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
          focusNode: _ecPhoneFocusNode,
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
    );

    final emergency = wrapForm
        ? Form(key: _formKey, child: emergencyCard)
        : emergencyCard;

    if (!includeDocs) return emergency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        emergency,
        const SizedBox(height: 16),
        _buildDocumentsSection(),
      ],
    );
  }

  Widget _buildWizardBar(LenderAccountUpgradeState state) {
    final isLast = _step == 2;
    final canProceed = _canGoNext && !_isSubmitting && !state.isLoading;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          const Spacer(),
          if (_step > 0) ...[
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.outlined,
              color: AppColors.lenderBlue,
              onTap: _goBack,
            ),
            const SizedBox(width: 12),
          ],
          AppButton(
            label: isLast
                ? (_isSubmitting
                    ? 'Submitting...'
                    : 'Submit')
                : 'Next',
            icon: isLast ? Icons.send : Icons.arrow_forward,
            color: AppColors.lenderBlue,
            isLoading: _isSubmitting,
            onTap: canProceed ? (isLast ? _submit : _goNext) : null,
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
        // Per request: remove icon + text "Complete Account Upgrade to apply for a loan"
        // for the default/unverified state – hide the banner entirely.
        return const SizedBox.shrink();
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

class _PesoCurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }

    // Keep only digits and dots for parsing
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');

    if (cleaned.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }

    if (cleaned == '.') {
      return const TextEditingValue(
          text: '₱', selection: TextSelection.collapsed(offset: 1));
    }

    // Prevent multiple dots
    if (cleaned.split('.').length > 2) return oldValue;

    // If user is typing decimal (ends with dot), keep dot visible with formatted integer
    if (cleaned.endsWith('.')) {
      final intPart = cleaned.substring(0, cleaned.length - 1);
      if (intPart.isEmpty) {
        return const TextEditingValue(
            text: '₱0.', selection: TextSelection.collapsed(offset: 3));
      }
      final intVal = int.tryParse(intPart.replaceAll(',', ''));
      if (intVal == null) return oldValue;
      final formattedInt = NumberFormat('#,##0', 'en_PH').format(intVal);
      final formatted = '₱$formattedInt.';
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    // Split integer and fractional parts, keep fractional as typed (max 2 decimals)
    final parts = cleaned.split('.');
    final intPartRaw = parts[0].isEmpty ? '0' : parts[0];
    final intVal = int.tryParse(intPartRaw);
    if (intVal == null) return oldValue;

    final formattedInt = NumberFormat('#,##0', 'en_PH').format(intVal);

    if (parts.length == 1) {
      final formatted = '₱$formattedInt';
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } else {
      var fraction = parts[1];
      if (fraction.length > 2) fraction = fraction.substring(0, 2);
      final formatted = '₱$formattedInt.$fraction';
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
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

/// Single Valid ID card showing combined Front + Back capture status.
class _ValidIdCard extends StatelessWidget {
  final bool hasFront;
  final bool hasBack;
  final VoidCallback onPick;

  const _ValidIdCard({
    required this.hasFront,
    required this.hasBack,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final complete = hasFront && hasBack;
    final subtitle = complete
        ? 'Front ✓  •  Back ✓'
        : hasFront
            ? 'Front ✓  •  Back missing — tap to add'
            : 'Front + Back of your government-issued ID';
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: complete
              ? AppColors.lenderBlue.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: complete
                  ? AppColors.lenderBlue.withValues(alpha: 0.3)
                  : AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Image.asset(
                'assets/icons/id_card.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Valid Government ID *',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: complete
                            ? AppColors.lenderBlue
                            : AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(complete ? Icons.check_circle : Icons.upload_file_outlined,
                color:
                    complete ? AppColors.success : AppColors.textTertiary),
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
  final String? assetPath;
  final PlatformFile? file;
  final VoidCallback onPick;

  const _DocUploadCard({
    required this.label,
    required this.hint,
    required this.icon,
    this.assetPath,
    this.file,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    final useAsset = assetPath != null;
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
            if (useAsset)
              // Asset icon without background — transparent, no container fill
              SizedBox(
                width: 44,
                height: 44,
                child: Image.asset(
                  assetPath!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              )
            else
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
                    color: hasFile
                        ? AppColors.lenderBlue
                        : AppColors.textTertiary,
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

class _AccountUpgradeVerificationSkeleton extends StatelessWidget {
  const _AccountUpgradeVerificationSkeleton();

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
            // Step indicator skeleton (3 steps)
            Row(
              children: List.generate(3, (i) => Expanded(
                child: Column(
                  children: [
                    Container(width: i == 0 ? 32 : 24, height: i == 0 ? 32 : 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(height: 6),
                    Container(width: 60, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    if (i < 2) Container(margin: const EdgeInsets.only(top: 14), height: 2, color: Colors.white),
                  ],
                ),
              )),
            ),
            const SizedBox(height: 20),
            // Section card skeleton: Personal Information
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.shimmerBase, borderRadius: BorderRadius.circular(8))), const SizedBox(width: 10), Container(width: 140, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)))]),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 16),
                  Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: Container(height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)))), const SizedBox(width: 10), Expanded(child: Container(height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))))]),
                  const SizedBox(height: 12),
                  Container(width: double.infinity, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Second card skeleton: Financial Info preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Button skeleton (Next) - no box, directly below form
            Container(width: double.infinity, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}
