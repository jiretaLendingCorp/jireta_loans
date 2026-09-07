// lib/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../providers/hm_in_office_provider.dart';

class _DocFile {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  const _DocFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
}

class InOfficeWizard extends ConsumerStatefulWidget {
  final String? applicationId;
  final VoidCallback onComplete;

  /// When true (opened via the View action), steps 1-3 are rendered read-only
  /// with the exact values already entered — only the values inside the form
  /// fields are shown. Steps 4-5 stay accessible (and stay editable when the
  /// lender has not self-applied a loan yet).
  final bool viewOnly;

  const InOfficeWizard({
    super.key,
    this.applicationId,
    required this.onComplete,
    this.viewOnly = false,
  });

  @override
  ConsumerState<InOfficeWizard> createState() => _InOfficeWizardState();
}

class _InOfficeWizardState extends ConsumerState<InOfficeWizard> {
  static const double _minAmount = 3000;
  static const double _maxAmount = 500000;
  static const int _maxDocBytes = 5 * 1024 * 1024;

  static const List<String> _relationshipOptions = [
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

  // Valid ID is collected as FRONT + BACK (matches Account Upgrade), so the
  // required document set is: valid_id, valid_id_back, selfie, mayors_permit,
  // birth_certificate.
  static const List<(String, String)> _docTypes = [
    ('valid_id', 'Valid ID (Front)'),
    ('valid_id_back', 'Valid ID (Back)'),
    ('selfie', 'Selfie with ID'),
    ('mayors_permit', "Mayor's Permit"),
    ('birth_certificate', 'Birth Certificate'),
  ];

  static const Map<String, String> _docAssetIcons = {
    'valid_id': 'assets/icons/id_card.png',
    'valid_id_back': 'assets/icons/id_card.png',
    'selfie': 'assets/icons/selfie with id.png',
    'mayors_permit': 'assets/icons/PERMIT.png',
    'birth_certificate': 'assets/icons/birth certificate.jpg',
  };

  static const List<String> _genderOptions = ['male', 'female'];
  static const List<String> _civilStatusOptions = [
    'single',
    'married',
    'widowed',
    'separated',
  ];

  int _step = 0;
  String? _appId;
  bool _loading = false;

  // Loaded application details (get-details). Null until fetched for an
  // existing applicationId.
  Map<String, dynamic>? _details;
  bool _loadingDetails = false;
  String? _detailsError;

  // Documents already uploaded to storage (docType -> file_path). Kept so
  // continuing a draft does not re-upload (or upload empty) existing files.
  final Map<String, String> _existingDocPaths = {};

  final _formKey = GlobalKey<FormState>();

  // Step 1 controllers (mirrors Account Upgrade fields so walk-in creates
  // a complete lender account up to upgrade stage)
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _gender;
  String? _civilStatus;
  DateTime? _dob;

  // Step 2 controllers (address only — monthly income + emergency contact
  // now live on the loans table per-loan, not on the in-office application)
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  // Step 3 controllers
  final _amountCtrl = TextEditingController();
  String _frequency = 'monthly';
  int? _termPeriods;
  bool _previewLoading = false;
  String? _previewError;
  Map<String, dynamic>? _schedulePreview;
  final _purposeCtrl = TextEditingController();

  // Step 4 controllers
  final _coFirstCtrl = TextEditingController();
  final _coLastCtrl = TextEditingController();
  final _coPhoneCtrl = TextEditingController();
  final _coAddressCtrl = TextEditingController();
  String? _coRel;

  // Step 5 state
  final Map<String, _DocFile> _docs = {};
  String? _docsError;
  String? _signature;
  String? _signatureError;

  /// True when the whole wizard must be read-only: opened via View AND the
  /// lender already self-applied a loan (steps 4-5 are prefilled from the
  /// submitted loan + co-maker, nothing may change).
  bool get _fullyReadOnly => _isViewOnly || _hasLinkedLoan;

  bool get _isViewOnly => widget.viewOnly;

  bool get _hasLinkedLoan {
    final loan = _details?['loan'];
    return loan is Map && loan.isNotEmpty;
  }

  String? get _accountUpgradeStatus =>
      _details?['account_upgrade_status'] as String?;

  @override
  void initState() {
    super.initState();
    _appId = widget.applicationId;
    if (_appId != null) {
      _loadingDetails = true;
      Future.microtask(_loadApplication);
    }
  }

  /// Fetches the full application (saved steps + linked loan + co-makers +
  /// account upgrade status) and restores every field so View mode shows the
  /// exact values entered and continue-editing starts where it stopped.
  Future<void> _loadApplication() async {
    if (_appId == null) return;
    final details =
        await ref.read(hmInOfficeProvider.notifier).getDetails(_appId!);
    if (!mounted) return;
    setState(() {
      _loadingDetails = false;
      if (details == null) {
        _detailsError = 'Could not load this application. Please try again.';
      } else {
        _details = details;
        _applyDetails(details);
      }
    });
  }

  /// Restores controller values, uploaded document names and loan/co-maker
  /// fields from the get-details payload.
  void _applyDetails(Map<String, dynamic> details) {
    final pi = details['personal_info'] as Map<String, dynamic>?;
    if (pi != null) {
      _phoneCtrl.text = (pi['phone_number'] ?? pi['phone'] ?? '').toString();
      _firstNameCtrl.text = (pi['first_name'] ?? '').toString();
      _middleNameCtrl.text = (pi['middle_name'] ?? '').toString();
      _lastNameCtrl.text = (pi['last_name'] ?? '').toString();
      _suffixCtrl.text = (pi['suffix'] ?? '').toString();
      _emailCtrl.text = (pi['email'] ?? '').toString();
      _gender = pi['gender'] as String?;
      _civilStatus = pi['civil_status'] as String?;
      if (pi['date_of_birth'] != null) {
        _dob = DateTime.tryParse(pi['date_of_birth'].toString());
      }
    }

    final addresses = details['addresses'] as List? ?? const [];
    if (addresses.isNotEmpty) {
      final a = addresses.first as Map<String, dynamic>;
      _streetCtrl.text = (a['street'] ?? '').toString();
      _barangayCtrl.text = (a['barangay'] ?? '').toString();
      _cityCtrl.text = (a['city'] ?? '').toString();
      _provinceCtrl.text = (a['province'] ?? '').toString();
      _zipCtrl.text = (a['zip_code'] ?? '').toString();
    }

    // Documents: remember their storage paths so a continued draft never
    // re-uploads (or uploads empty) existing files.
    final documents = details['documents'] as List? ?? const [];
    for (final d in documents) {
      if (d is! Map<String, dynamic>) continue;
      final type = (d['document_type'] ?? '').toString();
      final path = (d['file_path'] ?? d['file_url'] ?? '').toString();
      if (type.isEmpty) continue;
      _docs[type] = _DocFile(
        name: (d['file_name'] ?? type).toString(),
        mimeType: (d['mime_type'] ?? 'application/octet-stream').toString(),
        bytes: Uint8List(0),
      );
      if (path.isNotEmpty) _existingDocPaths[type] = path;
    }

    final sig = details['borrower_signature'];
    if (sig != null && sig.toString().trim().isNotEmpty) {
      _signature = sig.toString();
    }

    // Steps 4-5 (Loan + Co-Maker): prefer the lender's own submitted loan
    // (feature: when the lender already applied, show their loan + co-maker),
    // otherwise fall back to the application's own saved loan details.
    final loan = details['loan'] as Map<String, dynamic>?;
    if (loan != null && loan.isNotEmpty) {
      final amount = loan['principal_amount'];
      if (amount != null) {
        _amountCtrl.text = amount.toString();
      }
      _frequency = (loan['payment_frequency'] ?? 'monthly').toString();
      _termPeriods = (loan['term_periods'] as num?)?.toInt();
      _purposeCtrl.text = (loan['purpose'] ?? '').toString();
      final coMakers = loan['co_makers'] as List? ?? const [];
      if (coMakers.isNotEmpty) {
        final cm = coMakers.first as Map<String, dynamic>;
        _coFirstCtrl.text = (cm['first_name'] ?? '').toString();
        _coLastCtrl.text = (cm['last_name'] ?? '').toString();
        _coPhoneCtrl.text = (cm['phone_number'] ?? '').toString();
        _coAddressCtrl.text = (cm['address'] ?? '').toString();
        _coRel = (cm['relationship'] ?? '').toString();
      }
    } else {
      final ld = details['loan_details'] as Map<String, dynamic>?;
      if (ld != null) {
        final amount = ld['principal_amount'];
        if (amount != null) {
          _amountCtrl.text = amount.toString();
        }
        _frequency =
            (ld['payment_frequency'] ?? ld['frequency'] ?? 'monthly').toString();
        _termPeriods = (ld['term_periods'] as num?)?.toInt();
        _purposeCtrl.text = (ld['purpose'] ?? '').toString();
      }
      final coMakers = details['co_makers'] as List? ?? const [];
      if (coMakers.isNotEmpty) {
        final cm = coMakers.first as Map<String, dynamic>;
        _coFirstCtrl.text = (cm['first_name'] ?? '').toString();
        _coLastCtrl.text = (cm['last_name'] ?? '').toString();
        _coPhoneCtrl.text =
            (cm['phone_number'] ?? cm['contact_number'] ?? '').toString();
        _coAddressCtrl.text = (cm['address'] ?? '').toString();
        _coRel = (cm['relationship'] ?? '').toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 680,
        height: 600,
        // Only the initial application-data fetch shows a full-modal spinner.
        // Submitting keeps the form visible — just the action button spins.
        child: _loadingDetails
            ? const Center(child: CircularProgressIndicator())
            : _detailsError != null
                ? _buildErrorState()
                : Column(
                    children: [
                      _buildHeader(),
                      _buildStepIndicator(),
                      Expanded(child: _buildStepContent()),
                      _buildFooter(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(_isViewOnly ? Icons.visibility_outlined : Icons.person_add,
              color: AppColors.gold, size: 22),
          const SizedBox(width: 10),
          Text(_isViewOnly ? 'View Walk-in Application' : 'Walk-in Loan Application',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_accountUpgradeStatus != null) ...[
            _accountUpgradeChip(_accountUpgradeStatus!),
            const SizedBox(width: 10),
          ],
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Small status chip in the header showing the lender's Account Upgrade
  /// state — makes it immediately visible that the walk-in account was
  /// auto-verified when Steps 1-3 were submitted.
  Widget _accountUpgradeChip(String status) {
    final s = status.toLowerCase();
    final (Color bg, Color fg, String label) = switch (s) {
      'verified' || 'approved' =>
        (AppColors.success, Colors.white, 'Account Verified'),
      'rejected' => (AppColors.error, Colors.white, 'Account Rejected'),
      'submitted' || 'pending' || 'under_review' =>
        (AppColors.info, Colors.white, 'Upgrade Under Review'),
      _ => (Colors.white24, Colors.white, 'Not Verified'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            s == 'verified'
                ? Icons.verified_rounded
                : s == 'rejected'
                    ? Icons.cancel_rounded
                    : Icons.hourglass_top_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_detailsError ?? 'Could not load application.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _detailsError = null;
                  _loadingDetails = true;
                });
                Future.microtask(_loadApplication);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Identify', 'Address', 'Documents', 'Loan', 'Co-Maker'];
    return Container(
      color: AppColors.surfaceVariant,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final label = e.value;
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? AppColors.success
                            : active
                                ? AppColors.deepNavy
                                : AppColors.border,
                      ),
                      alignment: Alignment.center,
                      child: done
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: active
                                      ? Colors.white
                                      : AppColors.textTertiary,
                                  fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            fontSize: 10,
                            color: active
                                ? AppColors.deepNavy
                                : AppColors.textTertiary,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400)),
                  ],
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin:
                          const EdgeInsets.only(bottom: 14, left: 4, right: 4),
                      color: done ? AppColors.success : AppColors.border,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStepContent() {
    // Fully read-only (View of an already-submitted loan): every step is a
    // read-only display. View mode without a loan yet: steps 1-3 read-only,
    // steps 4-5 stay editable so staff can finish encoding the loan.
    final readOnlyStep = _fullyReadOnly || (_isViewOnly && _step < 3);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        // UI order: Identify → Address → Documents → Loan → Co-Maker
        // (+ Lender Signature). Backend save-step numbers stay fixed
        // (1=personal, 2=address, 3=loan, 4=co-maker, 5=documents+signature)
        // and are remapped in _backendStepForUiStep().
        child: readOnlyStep
            ? switch (_step) {
                0 => _buildStep1ReadOnly(),
                1 => _buildStep2ReadOnly(),
                2 => _buildDocumentsReadOnly(),
                3 => _buildStep3ReadOnly(),
                4 => _buildStep4ReadOnly(),
                _ => const SizedBox(),
              }
            : switch (_step) {
                0 => _buildStep1(),
                1 => _buildStep2(),
                2 => _buildDocumentsStep(),
                3 => _buildStep3(),
                4 => _buildStep4(),
                _ => const SizedBox(),
              },
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Identify Lender',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Search for an existing lender or create a new account. These fields match Account Upgrade so the walk-in account is ready for verification.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _field('Phone Number', _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            validator: _phoneValidator),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _field('First Name', _firstNameCtrl, maxLength: 100)),
            const SizedBox(width: 12),
            Expanded(child: _field('Last Name', _lastNameCtrl, maxLength: 100)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _optionalField('Middle Name (Optional)',
                    _middleNameCtrl,
                    maxLength: 100)),
            const SizedBox(width: 12),
            Expanded(
                child: _optionalField('Suffix (Optional, e.g. Jr., Sr., III)',
                    _suffixCtrl,
                    maxLength: 20)),
          ],
        ),
        const SizedBox(height: 12),
        _field('Email Address', _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            maxLength: 100,
            validator: _emailValidator),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                'Gender',
                _gender,
                _genderOptions,
                (v) => setState(() => _gender = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown(
                'Civil Status',
                _civilStatus,
                _civilStatusOptions,
                (v) => setState(() => _civilStatus = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dobField(),
      ],
    );
  }

  Widget _dobField() {
    return TextFormField(
      readOnly: true,
      validator: (_) => _dob == null ? 'Date of birth is required' : null,
      controller: TextEditingController(
          text: _dob == null
              ? ''
              : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'),
      decoration: InputDecoration(
        labelText: 'Date of Birth',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(now.year - 21, now.month, now.day),
          firstDate: DateTime(1900),
          lastDate: DateTime(now.year - 18, now.month, now.day),
        );
        if (picked != null) setState(() => _dob = picked);
      },
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Address',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Enter home/work address.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _sectionTitle('Home Address'),
        const SizedBox(height: 8),
        _simpleField('Street / House No.',
            controller: _streetCtrl, maxLength: 100),
        const SizedBox(height: 8),
        _simpleField('Barangay', controller: _barangayCtrl, maxLength: 100),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _simpleField('City / Municipality',
                    controller: _cityCtrl, maxLength: 100)),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Province',
                    controller: _provinceCtrl, maxLength: 100)),
          ],
        ),
        const SizedBox(height: 8),
        _simpleField('ZIP Code',
            controller: _zipCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4),
      ],
    );
  }

  Widget _buildStep3() {
    final maxPeriods = (_schedulePreview?['max_periods'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Set the loan amount, frequency, and how many periods to pay.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _field('Loan Amount', _amountCtrl,
            keyboardType: TextInputType.number,
            prefix: '₱',
            maxLength: 12,
            validator: _amountValidator,
            onChanged: (_) => _onLoanInputChanged()),
        const SizedBox(height: 8),
        if (_currentAmount() > 0 &&
            (_currentAmount() < _minAmount || _currentAmount() > _maxAmount))
          const Text(
            'Amount must be between ₱3,000 and ₱500,000',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          ),
        const SizedBox(height: 16),
        const Text('Payment Frequency',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Row(
          children: [
            _freqChip('daily', Icons.calendar_today),
            const SizedBox(width: 10),
            _freqChip('weekly', Icons.date_range),
            const SizedBox(width: 10),
            _freqChip('monthly', Icons.calendar_month),
          ],
        ),
        const SizedBox(height: 16),
        _buildTermSelector(maxPeriods),
        const SizedBox(height: 16),
        _field('Purpose', _purposeCtrl, maxLines: 2, maxLength: 255),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Late payment penalty: an additional 20% is added automatically if the lender fails to pay within one month.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_previewLoading)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          )),
        if (_previewError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(
              _previewError!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        if (_schedulePreview != null && !_previewLoading)
          _buildSchedulePreview(),
      ],
    );
  }

  Widget _freqChip(String value, IconData icon) {
    final selected = _frequency == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _frequency = value;
            _termPeriods = null;
          });
          _onLoanInputChanged();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.deepNavy.withValues(alpha: 0.08)
                : Colors.white,
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? AppColors.gold : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                value[0].toUpperCase() + value.substring(1),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color:
                      selected ? AppColors.deepNavy : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<int> _termOptions(int max) {
    const candidates = <String, List<int>>{
      'daily': [
        7,
        10,
        14,
        20,
        21,
        28,
        30,
        35,
        40,
        45,
        60,
        70,
        80,
        90,
        120,
        180
      ],
      'weekly': [1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 26],
      'monthly': [1, 2, 3, 4, 5, 6],
    };
    final opts = (candidates[_frequency] ?? const <int>[])
        .where((v) => v <= max)
        .toList();
    if (!opts.contains(max)) opts.add(max);
    return opts;
  }

  Widget _buildTermSelector(int maxPeriods) {
    if (maxPeriods < 1) return const SizedBox.shrink();
    final unit = _termUnitFor(_frequency);
    final options = _termOptions(maxPeriods);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Term',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          'Choose how many $unit the lender wants to repay.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                _onLoanInputChanged();
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.deepNavy : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.deepNavy : AppColors.border,
                  ),
                ),
                child: Text(
                  isMax ? '$value $unit (Full)' : '$value $unit',
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

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Co-Maker Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: const Text(
            'Note: Co-maker is NOT subjected to Credit Investigation (CI).',
            style: TextStyle(fontSize: 12, color: AppColors.warning),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _simpleField('Co-Maker First Name',
                    controller: _coFirstCtrl, maxLength: 100)),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Co-Maker Last Name',
                    controller: _coLastCtrl, maxLength: 100)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                'Relationship',
                _coRel,
                _relationshipOptions,
                (v) => setState(() => _coRel = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Phone',
                    controller: _coPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 11)),
          ],
        ),
        const SizedBox(height: 12),
        _simpleField('Address', controller: _coAddressCtrl, maxLength: 100),
        const SizedBox(height: 20),
        const Text('Lender Signature',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
            'Lender signs here to confirm the walk-in application.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SignaturePad(
          onSignatureChanged: (sig) {
            setState(() {
              _signature = sig;
              _signatureError = (sig == null || sig.isEmpty)
                  ? 'Lender signature is required'
                  : null;
            });
          },
          height: 130,
        ),
        if (_signatureError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _signatureError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── Read-only (View) builders ─────────────────────

  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyCard(
      String title, IconData icon, List<Widget> rows, {Widget? footer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppColors.deepNavy),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
          ]),
          const SizedBox(height: 10),
          ...rows,
          if (footer != null) ...[
            const SizedBox(height: 6),
            footer,
          ],
        ],
      ),
    );
  }

  String get _displayName =>
      '${_firstNameCtrl.text.trim()} ${_middleNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  String _displayDob() {
    if (_dob == null) return '';
    return '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';
  }

  Widget _buildStep1ReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Identify Lender',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Read-only: these details were already submitted.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _readOnlyCard('Personal Information', Icons.person_outline, [
          _readOnlyRow('Full Name', _displayName),
          _readOnlyRow('Phone Number', _phoneCtrl.text.trim()),
          _readOnlyRow('Email', _emailCtrl.text.trim()),
          _readOnlyRow('Gender', _gender ?? ''),
          _readOnlyRow('Civil Status', _civilStatus ?? ''),
          _readOnlyRow('Date of Birth', _displayDob()),
          _readOnlyRow('Suffix', _suffixCtrl.text.trim()),
        ]),
      ],
    );
  }

  Widget _buildStep2ReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Address',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Read-only: these details were already submitted.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _readOnlyCard('Home Address', Icons.location_on_outlined, [
          _readOnlyRow('Street / House No.', _streetCtrl.text.trim()),
          _readOnlyRow('Barangay', _barangayCtrl.text.trim()),
          _readOnlyRow('City / Municipality', _cityCtrl.text.trim()),
          _readOnlyRow('Province', _provinceCtrl.text.trim()),
          _readOnlyRow('ZIP Code', _zipCtrl.text.trim()),
        ]),
      ],
    );
  }

  Widget _buildDocumentsReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Documents',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Read-only: these documents were already uploaded.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        ..._docTypes.map((d) {
          final type = d.$1;
          final file = _docs[type];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                  color: file != null
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.border),
              borderRadius: BorderRadius.circular(8),
              color: file != null
                  ? AppColors.success.withValues(alpha: 0.04)
                  : Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  file != null
                      ? Icons.check_circle
                      : Icons.description_outlined,
                  color: file != null
                      ? AppColors.success
                      : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(d.$2,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text(
                  file != null ? (file.name.isNotEmpty ? file.name : 'Uploaded') : 'Missing',
                  style: TextStyle(
                    fontSize: 12,
                    color: file != null
                        ? AppColors.success
                        : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }),
        _readOnlyCard('Lender Signature', Icons.draw_outlined, [
          _readOnlyRow('Signature',
              (_signature != null && _signature!.isNotEmpty) ? 'Signed ✓' : 'Not signed'),
        ]),
      ],
    );
  }

  Widget _buildStep3ReadOnly() {
    final loan = _details?['loan'] as Map<String, dynamic>?;
    final loanNumber =
        (loan?['loan_number'] ?? '').toString().trim();
    final amount = _amountCtrl.text.trim();
    final freq = _frequency;
    final term = _termPeriods?.toString() ?? '';
    final unit = _termUnitFor(freq);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          loanNumber.isNotEmpty
              ? 'This lender already applied for this loan — read-only view.'
              : 'Read-only: these loan details were already submitted.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _readOnlyCard('Loan', Icons.payments_outlined, [
          if (loanNumber.isNotEmpty)
            _readOnlyRow('Loan Number', loanNumber),
          _readOnlyRow('Loan Amount',
              amount.isEmpty ? '' : '₱${_formatMoney(amount)}'),
          _readOnlyRow('Payment Frequency',
              freq.isEmpty ? '' : freq[0].toUpperCase() + freq.substring(1)),
          _readOnlyRow('Loan Term',
              term.isEmpty ? '' : '$term $unit'),
          _readOnlyRow('Purpose', _purposeCtrl.text.trim()),
        ]),
      ],
    );
  }

  Widget _buildStep4ReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Co-Maker Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Read-only: these details were already submitted.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _readOnlyCard('Co-Maker', Icons.group_outlined, [
          _readOnlyRow('First Name', _coFirstCtrl.text.trim()),
          _readOnlyRow('Last Name', _coLastCtrl.text.trim()),
          _readOnlyRow('Relationship', _coRel ?? ''),
          _readOnlyRow('Phone', _coPhoneCtrl.text.trim()),
          _readOnlyRow('Address', _coAddressCtrl.text.trim()),
        ]),
      ],
    );
  }

  String _formatMoney(String raw) {
    final d = double.tryParse(raw.replaceAll(',', '').trim());
    if (d == null) return raw;
    return d.toStringAsFixed(2);
  }

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Documents',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Upload all required documents.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        ..._docTypes.map((d) => _docUploadCard(d.$1, d.$2)),
        if (_docsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              _docsError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _docUploadCard(String type, String label) {
    final file = _docs[type];
    final hasFile = file != null;
    final asset = _docAssetIcons[type];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: hasFile
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
        color:
            hasFile ? AppColors.success.withValues(alpha: 0.04) : Colors.white,
      ),
      child: ListTile(
        dense: true,
        leading: asset != null
            ? Image.asset(asset, width: 22, height: 22, fit: BoxFit.contain, filterQuality: FilterQuality.high)
            : Icon(
                hasFile ? Icons.check_circle : Icons.description_outlined,
                color: hasFile ? AppColors.success : AppColors.textSecondary,
                size: 22,
              ),
        title: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasFile ? file.name : 'Required — JPG, PNG or PDF (max 5MB)',
          style: TextStyle(
            fontSize: 12,
            color: hasFile ? AppColors.success : AppColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton.icon(
          onPressed: () {
            if (hasFile) {
              setState(() {
                _docs.remove(type);
                _existingDocPaths.remove(type);
                _docsError = null;
              });
            } else {
              _pickDocument(type);
            }
          },
          icon: Icon(hasFile ? Icons.close : Icons.upload_file, size: 16),
          label: Text(hasFile ? 'Remove' : 'Upload'),
          style: TextButton.styleFrom(foregroundColor: AppColors.deepNavy),
        ),
      ),
    );
  }

  Future<void> _pickDocument(String docType) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Choose File'),
              onTap: () => Navigator.pop(ctx, 'file')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'camera':
        await _pickFromCamera(docType);
      case 'gallery':
        await _pickFromGallery(docType);
      case 'file':
        await _pickFromFile(docType);
    }
  }

  Future<void> _pickFromCamera(String docType) async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    _setDoc(docType,
        _DocFile(name: img.name, mimeType: 'image/jpeg', bytes: bytes));
  }

  Future<void> _pickFromGallery(String docType) async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    _setDoc(docType,
        _DocFile(name: img.name, mimeType: 'image/jpeg', bytes: bytes));
  }

  Future<void> _pickFromFile(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    final ext = (f.extension ?? 'jpg').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
    _setDoc(docType, _DocFile(name: f.name, mimeType: mime, bytes: bytes));
  }

  void _setDoc(String docType, _DocFile file) {
    if (file.bytes.isEmpty) return;
    if (file.bytes.length > _maxDocBytes) {
      _showMessage('File exceeds the 5MB limit.');
      return;
    }
    setState(() {
      _docs[docType] = file;
      // A newly picked file replaces any previously uploaded one.
      _existingDocPaths.remove(docType);
      _docsError = null;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton(
              onPressed: _loading ? null : () => setState(() => _step--),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_fullyReadOnly)
            // View of an already-submitted loan (or plain View mode of a
            // converted application): nothing to edit or submit.
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            )
          else if (_step == 2 && !_isViewOnly)
            // Step 3 (Documents) is a SUBMIT: creates the lender account +
            // auto-verifies the upgrade (no loan yet). The lender logs in and
            // self-applies, or staff continues to Steps 4-5. Skipped in View
            // mode — the account was already created.
            ElevatedButton(
              onPressed: _loading ? null : _submitAccountAndContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black87),
                    )
                  : const Text('Submit'),
            )
          else if (_step < 4)
            ElevatedButton(
              onPressed: _loading ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Next'),
            )
          else
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black87),
                    )
                  : const Text('Submit Application'),
            ),
        ],
      ),
    );
  }

  /// Maps the visible UI step to the fixed backend save-step number.
  /// UI order is Identify(0) → Address(1) → Documents(2) → Loan(3) →
  /// Co-Maker(4), while the backend contract stays 1=personal, 2=address,
  /// 3=loan, 4=co-maker, 5=documents+signature.
  int _backendStepForUiStep(int uiStep) => switch (uiStep) {
        0 => 1,
        1 => 2,
        2 => 5,
        3 => 3,
        4 => 4,
        _ => uiStep + 1,
      };

  Future<void> _nextStep() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Documents live on UI step 2 — block Next until all uploads are present.
    if (_step == 2) {
      final missingDocs = _docTypes
          .where((d) => !_docs.containsKey(d.$1))
          .map((d) => d.$2)
          .toList();
      if (missingDocs.isNotEmpty) {
        setState(() => _docsError =
            'Please upload all required documents: ${missingDocs.join(', ')}');
        return;
      }
    }
    // Lender signature lives on the Co-Maker UI step (4).
    if (_step == 4 && (_signature == null || _signature!.isEmpty)) {
      setState(() => _signatureError = 'Lender signature is required');
      return;
    }
    // View mode: read-only steps (1-3) display the saved values and must
    // never overwrite them.
    final readOnlyStep = _isViewOnly && _step < 3;
    if (_appId != null && !readOnlyStep) {
      final backendStep = _backendStepForUiStep(_step);
      // Documents (UI step 2 → backend step 5): persist the uploaded files
      // (reusing existing uploads when continuing a draft) instead of the
      // empty documents placeholder.
      final data = _step == 2 ? await _buildDocsOnlyData() : _collectStepData(_step);
      if (data.isNotEmpty) {
        final ok = await ref
            .read(hmInOfficeProvider.notifier)
            .saveStep(_appId!, backendStep, data);
        if (!ok) {
          if (mounted) _showMessage('Failed to save step ${_step + 1}. Please try again.');
          return;
        }
      }
    }
    if (mounted) setState(() => _step++);
  }

  Map<String, dynamic> _collectStepData(int uiStep) {
    return switch (uiStep) {
      0 => {
          'phone': _phoneCtrl.text.trim(),
          'phone_number': _phoneCtrl.text.trim(),
          'first_name': _firstNameCtrl.text.trim(),
          'middle_name': _middleNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'suffix': _suffixCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'gender': _gender,
          'civil_status': _civilStatus,
          'date_of_birth': _dob == null
              ? null
              : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        },
      1 => {
          'addresses': [
            {
              'address_type': 'home',
              'street': _streetCtrl.text.trim(),
              'barangay': _barangayCtrl.text.trim(),
              'city': _cityCtrl.text.trim(),
              'province': _provinceCtrl.text.trim(),
              'zip_code': _zipCtrl.text.trim(),
            }
          ],
          // Emergency contact + monthly income now live on the loans table
          // per-loan (00128/00130) — no longer collected in-office.
          'emergency_contacts': <Map<String, dynamic>>[],
        },
      2 => {'documents': <Map<String, dynamic>>[]},
      3 => {
          // Strip commas: Number("10,000") === NaN on the server, causing INCOMPLETE_WIZARD/DB_ERROR.
          'principal_amount':
              _amountCtrl.text.replaceAll(',', '').trim(),
          'frequency': _frequency,
          'term_periods': _termPeriods,
          'purpose': _purposeCtrl.text.trim(),
        },
      4 => {
          'first_name': _coFirstCtrl.text.trim(),
          'last_name': _coLastCtrl.text.trim(),
          'relationship': _coRel,
          'phone_number': _coPhoneCtrl.text.trim(),
          'address': _coAddressCtrl.text.trim(),
        },
      _ => <String, dynamic>{},
    };
  }

  double _currentAmount() =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  void _onLoanInputChanged() {
    final amount = _currentAmount();
    if (amount < _minAmount || amount > _maxAmount) {
      setState(() {
        _schedulePreview = null;
        _previewError = null;
      });
      return;
    }
    _previewSchedule();
  }

  Future<void> _previewSchedule() async {
    final amount = _currentAmount();
    if (amount < _minAmount || amount > _maxAmount) {
      setState(() => _schedulePreview = null);
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      var preview = await ref
          .read(hmInOfficeProvider.notifier)
          .getSchedulePreview(amount, _frequency, termPeriods: _termPeriods);
      // Clamp the chosen term to the new maximum so a stale selection (after
      // the amount or frequency changed) never exceeds what the server allows.
      final maxPeriods = (preview?['max_periods'] as num?)?.toInt();
      if (maxPeriods != null &&
          _termPeriods != null &&
          _termPeriods! > maxPeriods) {
        _termPeriods = null;
        preview = await ref
            .read(hmInOfficeProvider.notifier)
            .getSchedulePreview(amount, _frequency);
      }
      if (!mounted) return;
      setState(() {
        _schedulePreview = preview;
        _previewError = preview == null
            ? 'Could not load preview. Please check the amount.'
            : null;
      });
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Widget _buildSchedulePreview() {
    final p = _schedulePreview!;
    final principal = (p['principal'] as num?)?.toDouble() ?? 0;
    final interest = (p['interest'] as num?)?.toDouble() ??
        (p['interest_amount'] as num?)?.toDouble() ??
        0;
    final totalPayable = (p['total_payable'] as num?)?.toDouble() ?? 0;
    final installments = (p['installments'] as num?)?.toInt() ?? 0;
    final installmentAmt = (p['installment_amount'] as num?)?.toDouble() ?? 0;
    final dueDates = (p['due_dates'] as List?) ?? const [];
    final amounts = (p['amounts'] as List?) ?? const [];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loan Schedule Preview',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _previewRow('Principal Amount', principal.toCurrency),
          _previewRow('Interest (20%)', interest.toCurrency),
          _previewRow('Total Payable', totalPayable.toCurrency),
          _previewRow('Term', '$installments ${_termUnitFor(p['frequency'])}'),
          _previewRow('Installment Amount', installmentAmt.toCurrency),
          _previewRow('Number of Payments', '$installments'),
          if (dueDates.isNotEmpty) ...[
            const Divider(height: 16),
            const Text('Payment Schedule',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: dueDates.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final date = dueDates[i]?.toString() ?? '';
                  final amt = (amounts[i] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Text('#${i + 1}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(date,
                                style: const TextStyle(fontSize: 12))),
                        Text(amt.toCurrency,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _termUnitFor(dynamic frequency) {
    final f = (frequency ?? _frequency).toString().toLowerCase();
    if (f == 'weekly') return 'weeks';
    if (f == 'monthly') return 'months';
    return 'days';
  }

  Widget _previewRow(String l, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(l,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text(v,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final missingDocs = _docTypes
        .where((d) => !_docs.containsKey(d.$1))
        .map((d) => d.$2)
        .toList();
    if (missingDocs.isNotEmpty) {
      // Documents live on UI step 2 — jump back so the user sees the error.
      setState(() {
        _docsError =
            'Please upload all required documents: ${missingDocs.join(', ')}';
        _step = 2;
      });
      return;
    }
    if (_signature == null || _signature!.isEmpty) {
      // Lender signature lives on the Co-Maker UI step (4).
      setState(() {
        _signatureError = 'Lender signature is required';
        _step = 4;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      if (_appId == null) {
        final id = await ref.read(hmInOfficeProvider.notifier).createDraft();
        if (id == null) {
          if (mounted) _showMessage('Failed to create draft. Check connection and try again.');
          setState(() => _loading = false);
          return;
        }
        _appId = id;
      }
      // Save in backend step order (1..5) regardless of UI order.
      // UI step → backend step: 0→1, 1→2, 3→3, 4→4, docs+signature→5.
      final backendPayloads = <int, Map<String, dynamic>>{
        1: _collectStepData(0),
        2: _collectStepData(1),
        3: _collectStepData(3),
        4: _collectStepData(4),
        5: await _buildStep5Data(),
      };
      for (var backendStep = 1; backendStep <= 5; backendStep++) {
        final data = backendPayloads[backendStep]!;
        if (data.isNotEmpty) {
          final ok = await ref
              .read(hmInOfficeProvider.notifier)
              .saveStep(_appId!, backendStep, data);
          if (!ok) {
            if (mounted) _showMessage('Failed to save step $backendStep. Server rejected the data.');
            setState(() => _loading = false);
            return;
          }
        }
      }
      final submittedRes = await ref.read(hmInOfficeProvider.notifier).submitApplication(_appId!);
      if (submittedRes == null) {
        if (mounted) _showMessage('Submit failed. Application data is incomplete or already submitted.');
        setState(() => _loading = false);
        return;
      }
      // Business rule parity: if lender not yet verified, account is created but loan is PENDING upgrade
      final pendingUpgrade = submittedRes['pending_upgrade'] == true;
      if (mounted) {
        if (pendingUpgrade) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created via Walk-in. Lender must complete Account Upgrade before loan is created.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(submittedRes['message']?.toString() ?? 'Application submitted.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
      widget.onComplete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showMessage('Submit failed: $e');
      setState(() => _loading = false);
    }
  }

  /// Step-3 SUBMIT: saves Identify + Address + uploads Documents, then calls
  /// the submit-account endpoint (creates the lender account + auto-verifies
  /// the upgrade — no loan yet). On success shows the login credentials and
  /// lets staff continue to Step 4 (Loan) or finish (lender self-applies).
  Future<void> _submitAccountAndContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final missingDocs = _docTypes
        .where((d) => !_docs.containsKey(d.$1))
        .map((d) => d.$2)
        .toList();
    if (missingDocs.isNotEmpty) {
      setState(() => _docsError =
          'Please upload all required documents: ${missingDocs.join(', ')}');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_appId == null) {
        final id = await ref.read(hmInOfficeProvider.notifier).createDraft();
        if (id == null) {
          if (mounted) _showMessage('Failed to create draft. Check connection and try again.');
          setState(() => _loading = false);
          return;
        }
        _appId = id;
      }
      // Backend steps 1 (personal) + 2 (address) + 5 (documents only).
      final saves = <int, Map<String, dynamic>>{
        1: _collectStepData(0),
        2: _collectStepData(1),
        5: await _buildDocsOnlyData(),
      };
      for (final e in saves.entries) {
        if (e.value.isEmpty) continue;
        final ok = await ref
            .read(hmInOfficeProvider.notifier)
            .saveStep(_appId!, e.key, e.value);
        if (!ok) {
          if (mounted) _showMessage('Failed to save step ${e.key}. Server rejected the data.');
          setState(() => _loading = false);
          return;
        }
      }
      final res = await ref.read(hmInOfficeProvider.notifier).submitAccount(_appId!);
      if (res == null) {
        if (mounted) _showMessage('Account submit failed. Please try again.');
        setState(() => _loading = false);
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
      final loginPhone = (res['login_phone']?.toString() ?? _phoneCtrl.text.trim());
      final goOn = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(child: Text('Account Created & Verified')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The lender can now log in and apply for a loan on their own. Or continue to encode the loan here.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _credentialRow('Phone', loginPhone),
              const SizedBox(height: 6),
              _credentialRow('Password', '12345678'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Done'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue to Loan'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onComplete();
      if (goOn == true) {
        setState(() => _step = 3);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showMessage('Account submit failed: $e');
      setState(() => _loading = false);
    }
  }

  Widget _credentialRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Uploads the picked document files and returns the backend step-5 payload
  /// WITHOUT the signature (used by the Step-3 account submit).
  Future<Map<String, dynamic>> _buildDocsOnlyData() async {
    final docs = await _uploadDocs();
    return {'documents': docs};
  }

  Future<List<Map<String, dynamic>>> _uploadDocs() async {
    final docs = <Map<String, dynamic>>[];
    for (final entry in _docs.entries) {
      final f = entry.value;
      // Reuse the already-uploaded file when continuing a draft — avoids
      // re-uploading (or uploading empty) existing documents.
      final existing = _existingDocPaths[entry.key];
      final path = (existing != null && existing.isNotEmpty)
          ? existing
          : await SupabaseStorageService.instance.uploadFile(
              bucket: 'loan-documents',
              folder: 'in-office-applications',
              bytes: f.bytes,
              fileName: f.name,
              contentType: f.mimeType,
            );
      docs.add({
        'document_type': entry.key,
        'file_url': path,
        'file_name': f.name,
        'mime_type': f.mimeType,
      });
    }
    return docs;
  }

  Future<Map<String, dynamic>> _buildStep5Data() async {
    final docs = await _uploadDocs();
    String? signaturePath;
    if (_signature != null && _signature!.isNotEmpty) {
      // Existing storage path (loaded from a saved draft) — reuse it directly
      // instead of trying to base64-decode a path.
      final sig = _signature!;
      final isExistingPath = sig.contains('/') &&
          sig.length < 500 &&
          !sig.startsWith('data:') &&
          !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(sig);
      if (isExistingPath) {
        signaturePath = sig;
      } else {
        try {
          // _signature is base64-encoded PNG bytes (no data: prefix). Upload
          // to storage so DB column (VARCHAR 255 / future TEXT) stores a short
          // path, not a 20KB base64 string that overflows and causes PATCH 500.
          final sigBytes = base64Decode(_signature!);
          final path = await SupabaseStorageService.instance.uploadFile(
            bucket: 'loan-documents',
            folder: 'in-office-applications/signatures',
            bytes: sigBytes,
            fileName: 'signature_${DateTime.now().millisecondsSinceEpoch}.png',
            contentType: 'image/png',
          );
          signaturePath = path;
        } catch (e) {
          // Fallback: if upload fails (offline, bucket missing), store the raw
          // base64 but truncated to 255 to avoid DB "value too long" 500. The
          // server will also truncate/log. Signature will be degraded but
          // wizard can still complete and submit.
          // ignore: avoid_print
          print('[InOfficeWizard] signature upload failed, falling back to truncated base64: $e');
          signaturePath = _signature!.length > 255 ? _signature!.substring(0, 255) : _signature;
        }
      }
    }
    return {
      'documents': docs,
      if (signaturePath != null) 'borrower_signature': signaturePath,
    };
  }

  String? _emailValidator(String? value) {
    final v = _requiredValidator(value);
    if (v != null) return v;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value!.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _amountValidator(String? value) {
    final v = _requiredValidator(value);
    if (v != null) return v;
    final d = double.tryParse(value!.replaceAll(',', '').trim());
    if (d == null || d < _minAmount || d > _maxAmount) {
      return 'Amount must be between ₱3,000 and ₱500,000';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final v = _requiredValidator(value);
    if (v != null) return v;
    if (!RegExp(r'^[0-9+\-() ]{7,15}$').hasMatch(value!.trim())) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType,
      int maxLines = 1,
      String? prefix,
      int? maxLength,
      FormFieldValidator<String>? validator,
      ValueChanged<String>? onChanged}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      validator: validator ?? _requiredValidator,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixText: prefix,
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _simpleField(String label,
      {TextEditingController? controller,
      TextInputType? keyboardType,
      int? maxLength}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      validator: _requiredValidator,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  /// Optional text field (middle name / suffix) — no required validator.
  Widget _optionalField(String label, TextEditingController ctrl,
      {int? maxLength}) {
    return TextFormField(
      controller: ctrl,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: _requiredValidator,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy));
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    _coFirstCtrl.dispose();
    _coLastCtrl.dispose();
    _coPhoneCtrl.dispose();
    _coAddressCtrl.dispose();
    super.dispose();
  }
}
