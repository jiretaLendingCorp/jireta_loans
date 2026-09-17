// lib/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/document_viewer.dart';
import '../../../../shared/widgets/philippines_address_field.dart';
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
  static const int _maxDocBytes = 5 * 1024 * 1024;

  /// Lapad ng LABEL column sa lahat ng read-only row — para pantay ang
  /// "Full Name", "Valid ID (Front)", atbp.
  static const double _rowLabelWidth = 150;

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

  /// Ipinapakita ang error text sa ilalim ng mga field — 2 SEGUNDO lang
  /// pagkatapos ma-block ang Next/Submit, tapos nawawala.
  ///
  /// Hindi ito ang humaharang sa pag-next: LAGING tumatakbo ang validator ng
  /// `Form` (`_formKey.currentState!.validate()`), itong flag lang ang
  /// kumokontrol kung IGUHIT pa ang error (tingnan ang `_ValidatedTextField`).
  /// Kaya hindi na "naka-stack" pataas ang form habang may lumang error text.
  bool _showFieldErrors = false;
  static const Duration _errorVisibleFor = Duration(seconds: 2);
  Timer? _errorHideTimer;

  /// True after the step-3 SUBMIT (account creation) succeeded in this
  /// session — the SUBMIT button must not be offered again once submitted.
  bool _submittedInSession = false;

  // Loaded application details (get-details). Null until fetched for an
  // existing applicationId.
  Map<String, dynamic>? _details;
  bool _loadingDetails = false;
  String? _detailsError;

  // Documents already uploaded to storage (docType -> file_path). Kept so
  // continuing a draft does not re-upload (or upload empty) existing files.
  final Map<String, String> _existingDocPaths = {};

  /// Address step: opisyal na PH address (PSA data via philippines_rpcmb) —
  /// Region → Province → City/Municipality → Barangay + Street. Kinukuha ang
  /// structured parts sa `_collectStepData(1)` para ang `application_addresses`
  /// row ay standardized (tulad ng sa ibang address forms ng app).
  final _addressKey = GlobalKey<PhilippinesAddressFieldState>();



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

  // Loan/co-maker fields are retained for read-only display in View mode
  // (when a lender has already self-applied) — the walk-in wizard itself no
  // longer collects them.
  final _amountCtrl = TextEditingController();
  String _frequency = 'monthly';
  int? _termPeriods;
  final _purposeCtrl = TextEditingController();

  final _coFirstCtrl = TextEditingController();
  final _coLastCtrl = TextEditingController();
  final _coPhoneCtrl = TextEditingController();
  final _coAddressCtrl = TextEditingController();
  String? _coRel;

  // Documents + signature state
  final Map<String, _DocFile> _docs = {};
  String? _docsError;
  String? _signature;

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

  /// True once this application has been submitted (lender account created at
  /// step 3, or the whole application submitted/converted). Once submitted,
  /// the step-3 SUBMIT button is no longer offered so staff cannot resubmit
  /// an application that already has a (verified) lender account.
  bool get _isSubmitted {
    if (_submittedInSession) return true;
    final status = (_details?['status'] as String?) ?? '';
    if (status == 'submitted' || status == 'converted') return true;
    final lenderId = _details?['lender_id'];
    return lenderId != null && lenderId.toString().isNotEmpty;
  }

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
      // Walang border radius — flat/square ang buong modal (tugma sa ibang
      // dialogs ng app).
      shape: const RoundedRectangleBorder(),
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
                      // View mode: isang page lang na may LAHAT ng section —
                      // wala nang "1 → 2 → 3" stepper dahil walang
                      // navigation na kailangan.
                      if (!_isViewOnly) _buildStepIndicator(),
                      Expanded(child: _buildStepContent()),
                      // View mode: walang action na kailangan — ang X sa header
                      // ang pang-sara, kaya wala nang footer/Close button.
                      if (!_isViewOnly) _buildFooter(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      decoration: const BoxDecoration(color: AppColors.deepNavy),
      child: Row(
        children: [
          // Square na gold-tinted na icon box — unique na mark ng walk-in
          // modal (hindi lang basta icon sa tabi ng title).
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.16),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Icon(
              _isViewOnly ? Icons.visibility_outlined : Icons.person_add,
              color: AppColors.gold,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    // Ang walk-in wizard ay ACCOUNT UPGRADE ang aktwal na
                    // ginagawa (account setup, hindi loan application — si
                    // lender ang mag-a-apply ng loan sa app), kaya 'Lender
                    // Account Upgrade' ang titulo.
                    _isViewOnly
                        ? 'View Lender Account Upgrade'
                        : 'Lender Account Upgrade',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (_headerStatus != null) ...[
            _headerStatusLabel(),
            const SizedBox(width: 16),
          ],
          // Compact na close button — dating 48x48 default IconButton ang
          // nagpapataas sa header.
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            splashRadius: 20,
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Status na nakalagay sa header — ang TOTOONG progreso ng walk-in
  /// application at ng loan nito, hindi lang "Account Verified":
  ///   • May loan na   → status ng loan ('Active Loan', 'Loan Pending', ...)
  ///   • 'submitted'   → 'Upgraded Account' (na-upgrade na ang account,
  ///                     naghihintay lang na mag-apply si lender)
  ///   • 'draft'       → 'Draft'
  ///   • 'converted'   → 'Converted to Loan'
  /// Fallback lang ang account upgrade status kapag wala pang details.
  (Color, IconData, String)? get _headerStatus {
    final details = _details;
    if (details != null) {
      final loan = details['loan'];
      if (loan is Map && loan.isNotEmpty) {
        final s = (loan['status'] ?? '').toString().toLowerCase().trim();
        final (Color color, IconData icon) = switch (s) {
          'active' || 'approved' =>
            (AppColors.riderGreenLight, Icons.check_circle_rounded),
          'overdue' || 'rejected' || 'cancelled' =>
            (const Color(0xFFEF9A9A), Icons.error_rounded),
          'completed' => (const Color(0xFF64B5F6), Icons.verified_rounded),
          _ => (AppColors.goldLight, Icons.hourglass_top_rounded),
        };
        final label = switch (s) {
          'active' => 'Active Loan',
          'overdue' => 'Overdue Loan',
          'completed' => 'Completed Loan',
          'approved' => 'Loan Approved',
          'rejected' => 'Loan Rejected',
          'cancelled' => 'Loan Cancelled',
          'pending' => 'Loan Pending',
          'under_review' => 'Loan Under Review',
          '' => 'Loan Application',
          _ => 'Loan ${_titleCase(s)}',
        };
        return (color, icon, label);
      }

      switch ((details['status'] ?? '').toString().toLowerCase().trim()) {
        case 'submitted':
          return (
            AppColors.riderGreenLight,
            Icons.verified_rounded,
            'Upgraded Account'
          );
        case 'draft':
          return (Colors.white70, Icons.edit_note_rounded, 'Draft');
        case 'converted':
          return (
            AppColors.riderGreenLight,
            Icons.verified_rounded,
            'Converted to Loan'
          );
      }
    }

    final upgrade = _accountUpgradeStatus;
    if (upgrade == null) return null;
    return switch (upgrade.toLowerCase()) {
      'verified' || 'approved' => (
          AppColors.riderGreenLight,
          Icons.verified_rounded,
          'Account Verified'
        ),
      'rejected' =>
        (const Color(0xFFEF9A9A), Icons.cancel_rounded, 'Account Rejected'),
      'submitted' || 'pending' || 'under_review' => (
          const Color(0xFF64B5F6),
          Icons.hourglass_top_rounded,
          'Upgrade Under Review'
        ),
      _ => (Colors.white70, Icons.remove_circle_outline, 'Not Verified'),
    };
  }

  static String _titleCase(String raw) => raw
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Status label sa header — PLAIN label lang (icon + text), walang
  /// background/border kaya hindi ito mukhang button. Maliliwanag na kulay
  /// para mabasa sa navy na header.
  Widget _headerStatusLabel() {
    final (Color fg, IconData icon, String label) = _headerStatus!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ],
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
    // Walk-in wizard is account setup only — the lender applies for the loan
    // themselves. Steps: Identify → Address → Documents.
    final steps = ['Identify', 'Address', 'Documents'];
    return Container(
      // COMPACT na banda: ang label ay nasa TABI ng bilog (hindi sa ilalim) at
      // 8px lang ang vertical padding. Dating dalawang linya ito (28px na bilog
      // + 6px gap + label) na may 14px padding sa itaas at ibaba → ~76px ang
      // taas; ngayon isang linya lang (24px na bilog) → ~40px.
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        // center (hindi start): pantay sa gitna ng bilog ang 2px na connector
        // kahit one-line na ang bawat step.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            // Connector bago ang step i — hatiin ang matitirang lapad sa gitna
            // ng mga step group.
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 2,
                    color: i <= _step ? AppColors.success : AppColors.border,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _step
                        ? AppColors.success
                        : i == _step
                            ? AppColors.deepNavy
                            : AppColors.border,
                  ),
                  alignment: Alignment.center,
                  child: i < _step
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              color: i == _step
                                  ? Colors.white
                                  : AppColors.textTertiary,
                              fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 7),
                Text(steps[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: i == _step
                            ? AppColors.deepNavy
                            : AppColors.textTertiary,
                        fontWeight:
                            i == _step ? FontWeight.w700 : FontWeight.w400)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    // View mode: lahat ng section (Identify + Address + Documents + Signature)
    // sa ISANG scroll — tingnan ang `_buildReadOnlyPage`.
    if (_isViewOnly) return _buildReadOnlyPage();

    // Fully read-only (View of an already-submitted loan): every step is a
    // read-only display.
    final readOnlyStep = _fullyReadOnly || (_isViewOnly && _step < 3);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        // UI order: Identify → Address → Documents. Backend save-step numbers
        // stay fixed (1=personal, 2=address, 3=loan, 4=co-maker, 5=documents
        // +signature) and are remapped in _backendStepForUiStep().
        child: readOnlyStep
            ? switch (_step) {
                0 => _buildStep1ReadOnly(),
                1 => _buildStep2ReadOnly(),
                2 => _buildDocumentsReadOnly(),
                _ => const SizedBox(),
              }
            : switch (_step) {
                0 => _buildStep1(),
                1 => _buildStep2(),
                2 => _buildDocumentsStep(),
                _ => const SizedBox(),
              },
      ),
    );
  }

  Widget _buildStep1() {
    // Wala nang "Identify Lender" heading + paliwanag sa itaas — deretso na sa
    // unang field (ang stepper sa itaas na ang nagsasabi kung anong step ito).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    return _ValidatedTextField(
      label: 'Date of Birth',
      readOnly: true,
      showError: _showFieldErrors,
      controller: TextEditingController(
          text: _dob == null
              ? ''
              : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'),
      // Ang `_dob` ang sinusuri (hindi ang text) — pinipili ito sa date picker.
      validator: (_) => _dob == null ? 'Date of birth is required' : null,
      suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
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
        // Philippine address (PSA/PSGC data) — pareho ng Edit User (People) at
        // ng ibang address forms. Naka-prefill mula sa na-save nang address
        // kapag kinokontinue o tinitignan ang application.
        PhilippinesAddressField(
          key: _addressKey,
          initialStreet: _streetCtrl.text,
          initialCity: _cityCtrl.text,
          initialProvince: _provinceCtrl.text,
          initialBarangay: _barangayCtrl.text,
        ),
        const SizedBox(height: 8),
        _simpleField('ZIP Code',
            controller: _zipCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4),
      ],
    );
  }

  Widget _readOnlyRow(String label, String value) => _readOnlyDataRow(
        label,
        Text(value.isEmpty ? 'N/A' : value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );

  /// LABEL sa kaliwa (fixed na lapad, pantay lahat) at ang VALUE sa gild niya.
  Widget _readOnlyDataRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _rowLabelWidth,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  /// Read-only section: puting card na may manipis na border, header na may
  /// tinted na icon box, at divider — SQUARE ang corners (walang radius).
  Widget _readOnlyCard(
      String title, IconData icon, List<Widget> rows, {Widget? footer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                  ),
                  child: Icon(icon, size: 15, color: AppColors.deepNavy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...rows,
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  footer,
                ],
              ],
            ),
          ),
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

  /// Mga row ng "Personal Information" card — share ng step-by-step read-only
  /// view at ng isang-page na View mode.
  List<Widget> get _personalInfoRows => [
        _readOnlyRow('Full Name', _displayName),
        _readOnlyRow('Phone Number', _phoneCtrl.text.trim()),
        _readOnlyRow('Email', _emailCtrl.text.trim()),
        _readOnlyRow('Gender', _gender ?? ''),
        _readOnlyRow('Civil Status', _civilStatus ?? ''),
        _readOnlyRow('Date of Birth', _displayDob()),
        _readOnlyRow('Suffix', _suffixCtrl.text.trim()),
      ];

  /// Isang page na may lahat ng section — ito ang View mode (wala nang
  /// step-by-step navigation). Read-only lahat, sunod-sunod na cards.
  Widget _buildReadOnlyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _readOnlyCard('Personal Information', Icons.person_outline,
              _personalInfoRows),
          _readOnlyCard('Home Address', Icons.location_on_outlined,
              _addressRows),
          _readOnlyCard(
              'Documents', Icons.folder_outlined, _documentTiles(boxed: false)),
          _readOnlyCard('Lender Signature', Icons.draw_outlined, [
            _readOnlyRow(
                'Signature',
                (_signature != null && _signature!.isNotEmpty)
                    ? 'Signed ✓'
                    : 'Not signed'),
          ]),
        ],
      ),
    );
  }

  Widget _buildStep1ReadOnly() {
    // Kapareho ng editable step 1 — wala nang "Identify Lender" heading, ang
    // "Read-only" note na lang ang naiwan sa itaas ng card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Read-only: these details were already submitted.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _readOnlyCard('Personal Information', Icons.person_outline,
            _personalInfoRows),
      ],
    );
  }

  /// Mga row ng "Home Address" card (share ng step read-only at one-page view).
  List<Widget> get _addressRows => [
        _readOnlyRow('Street / House No.', _streetCtrl.text.trim()),
        _readOnlyRow('Barangay', _barangayCtrl.text.trim()),
        _readOnlyRow('City / Municipality', _cityCtrl.text.trim()),
        _readOnlyRow('Province', _provinceCtrl.text.trim()),
        _readOnlyRow('ZIP Code', _zipCtrl.text.trim()),
      ];

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
        _readOnlyCard('Home Address', Icons.location_on_outlined, _addressRows),
      ],
    );
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


  /// Maliit na VIEW button sa tabi ng filename — binuksan ang aktwal na
  /// dokumento sa dialog.
  Widget _viewDocButton(String type, String label) {
    return Tooltip(
      message: 'View uploaded file',
      child: OutlinedButton.icon(
        onPressed: () => _viewDocument(type, label),
        icon: const Icon(Icons.visibility_outlined, size: 14),
        label: const Text('View',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepNavy,
          side: BorderSide(color: AppColors.deepNavy.withValues(alpha: 0.25)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// Buksan ang naka-upload (o bagong piniling) dokumento sa isang dialog para
  /// makita ng staff ang aktwal na file, hindi lang ang filename.
  ///
  ///   • Naka-upload na dati (`_existingDocPaths`) → sine-sign ang storage path
  ///     para maging viewable URL.
  ///   • Bagong pinili pa lang (bytes, hindi pa naka-upload) → direkta sa
  ///     memory ipinapakita; ang PDF ay hindi kayang i-preview bago i-submit.
  Future<void> _viewDocument(String type, String label) async {
    final file = _docs[type];
    final path = (_existingDocPaths[type] ?? '').trim();
    final isPdf = (file?.mimeType ?? '').toLowerCase().contains('pdf') ||
        (file?.name ?? '').toLowerCase().endsWith('.pdf') ||
        path.toLowerCase().endsWith('.pdf');

    if (path.isEmpty) {
      final bytes = file?.bytes ?? Uint8List(0);
      if (bytes.isEmpty) return;
      if (isPdf) {
        _showMessage(
            'Mai-preview ang PDF pagkatapos i-submit ang application.');
        return;
      }
      if (!mounted) return;
      _showDocumentDialog(
        label: label,
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
      return;
    }

    try {
      final url = path.startsWith('http') ? path : await _resolveDocUrl(path);
      if (!mounted) return;
      _showDocumentDialog(
        label: label,
        // Sinusuportahan ng DocumentViewer ang image (may VIEW/zoom controls)
        // at ang PDF (tap-to-open card).
        child: DocumentViewer(url: url, height: 540),
      );
    } catch (e) {
      _showMessage('Unable to open document: $e');
    }
  }

  /// Sine-sign ang storage path para maging viewable URL. Ang walk-in
  /// documents ay naka-upload sa `loan-documents` bucket, pero ang mga
  /// na-backfill sa `account_upgrade_documents` (migration 00133) ay
  /// maaaring nasa `account-upgrade-documents` pa rin — kaya may fallback.
  Future<String> _resolveDocUrl(String path) async {
    Object? lastError;
    for (final bucket in const [
      'loan-documents',
      'account-upgrade-documents'
    ]) {
      try {
        return await SupabaseStorageService.instance
            .getSignedUrl(bucket: bucket, path: path);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Document not found');
  }

  /// Dialog na may parehong header (deep navy) ng document viewer sa Account
  /// Upgrade details — para isang hitsura lang ang pagtingin ng dokumento.
  void _showDocumentDialog({required String label, required Widget child}) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.deepNavy, Color(0xFF1A2E4A)])),
                child: Row(children: [
                  Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(7)),
                      child: const Icon(Icons.insert_drive_file_rounded,
                          color: Colors.white, size: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15))),
                  IconButton(
                      tooltip: 'Close',
                      icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.white)),
                      onPressed: () => Navigator.pop(context)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Document row — LABEL sa kaliwa ("Valid ID (Front)" etc.) at sa gild nito
  /// ang filename ng na-upload na file (green = uploaded, red = Missing) +
  /// VIEW button para makita ang aktwal na file.
  Widget _documentTile(String type, String label, {bool boxed = true}) {
    final file = _docs[type];
    final name = (file?.name ?? '').trim();
    final path = (_existingDocPaths[type] ?? '').trim();
    // May maipakikitang file: naka-upload na (may storage path) o bagong
    // pinili pa lang (may bytes) — kung wala, walang View button.
    final canView = path.isNotEmpty || (file?.bytes.isNotEmpty ?? false);
    final row = _readOnlyDataRow(
      label,
      // `Expanded` (hindi `Flexible`) ang filename — sinasapawan nito ang buong
      // natitirang lapad kaya ang VIEW button ay laging nasa parehong x
      // (dulong kanan ng value area), pantay-pantay lahat ng row kahit iba-iba
      // ang haba ng filename.
      Row(
        children: [
          Expanded(
            child: Text(
              name.isEmpty ? 'Missing' : name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: name.isEmpty || !canView
                      ? AppColors.error
                      : AppColors.success),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canView) ...[
            const SizedBox(width: 12),
            _viewDocButton(type, label),
          ],
        ],
      ),
    );
    if (!boxed) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: row);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
            color: file != null
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.border),
        color: file != null
            ? AppColors.success.withValues(alpha: 0.04)
            : Colors.white,
      ),
      child: row,
    );
  }

  List<Widget> _documentTiles({bool boxed = true}) =>
      _docTypes.map((d) => _documentTile(d.$1, d.$2, boxed: boxed)).toList();

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
        ..._documentTiles(),
        _readOnlyCard('Lender Signature', Icons.draw_outlined, [
          _readOnlyRow('Signature',
              (_signature != null && _signature!.isNotEmpty) ? 'Signed ✓' : 'Not signed'),
        ]),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ipakita ang error text ng mga invalid na field, tapos itago pagkatapos ng
  /// [_errorVisibleFor] — para hindi manatiling naka-stack ang form.
  void _flashErrors() {
    _errorHideTimer?.cancel();
    setState(() => _showFieldErrors = true);
    _errorHideTimer = Timer(_errorVisibleFor, () {
      if (!mounted) return;
      setState(() => _showFieldErrors = false);
      // Ang PH address picker ay may sariling inline errors (hindi galing sa
      // `_ValidatedTextField`) — parehong 2 segundo lang din silang nakikita.
      _addressKey.currentState?.clearErrors();
    });
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton(
              // Bumabalik sa naunang step nang walang dalang error text.
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _step--;
                        _showFieldErrors = false;
                      }),
              child: const Text('Back'),
            ),
          const Spacer(),
          // View mode ay walang footer (hindi na ito naabot) — ang X sa
          // header ang pang-sara.
          if (_fullyReadOnly)
            // Read-only (may naka-link nang loan): browse the steps, then
            // Close. Nothing to edit or submit.
            _step < 2
                ? ElevatedButton(
                    onPressed: () => setState(() => _step++),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Next'),
                  )
                : ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Close'),
                  )
          else if (_step == 2 && !_isViewOnly && !_isSubmitted)
            // Step 3 (Documents) is the FINAL step and a SUBMIT: creates the
            // lender account + auto-verifies the upgrade. The walk-in ends
            // here — the lender logs in and applies for a loan themselves.
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
          else if (_step < 2)
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
            // Already submitted in this session (or the application already
            // has an account): nothing left to do — just close.
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      // 2 segundo lang ang error text (tingnan ang _ValidatedTextField) —
      // hindi na naka-stack pataas ang form pagkatapos.
      _flashErrors();
      return;
    }
    // Address step: ang PH address picker ay hindi TextFormField kaya hindi
    // ito kasama sa `Form.validate()` — manwal itong sinusuri rito (dapat
    // kumpleto: Region, Province, City/Municipality, Barangay at Street).
    if (_step == 1 && !(_addressKey.currentState?.validate() ?? false)) {
      _flashErrors();
      return;
    }
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
    if (mounted) {
      _errorHideTimer?.cancel();
      setState(() {
        _showFieldErrors = false;
        _step++;
      });
    }
  }

  /// Isinasalin ang napiling PH address (Region → Province → City → Barangay +
  /// Street) sa mga controller. Ang `address_type` ay 'home' at walang Region
  /// column ang `application_addresses` — street/barangay/city/province ang
  /// naipapasa (kapareho ng dating payload).
  void _syncAddressParts() {
    final a = _addressKey.currentState;
    if (a == null) return;
    _streetCtrl.text = a.street;
    _barangayCtrl.text = a.barangay ?? '';
    _cityCtrl.text = a.city ?? '';
    _provinceCtrl.text = a.province ?? '';
  }

  Map<String, dynamic> _collectStepData(int uiStep) {
    // Ang piniling PH address ay nasa `PhilippinesAddressField` state —
    // isinasalin ito sa controllers (isa nang source of truth, ginagamit din
    // ng read-only summary). No-op kapag hindi naka-mount ang address step.
    _syncAddressParts();
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

  Future<void> _submitAccountAndContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // 2 segundo lang ang error text (tingnan ang _ValidatedTextField) —
      // hindi na naka-stack pataas ang form pagkatapos.
      _flashErrors();
      return;
    }

    // The step-3 SUBMIT creates the lender account. It must only run once:
    // resubmitting an already-submitted application would re-run account
    // creation / duplicate the notification.
    if (_isSubmitted) {
      if (mounted) _showMessage('This application is already submitted.');
      return;
    }

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
      setState(() {
        _loading = false;
        _submittedInSession = true;
      });
      final isNewLender = (res['is_new_lender'] as bool?) ?? true;
      final loginPhone = (res['login_phone']?.toString() ?? _phoneCtrl.text.trim());
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.verified_user, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(child: Text(isNewLender ? 'Account Created & Verified' : 'Existing Account Linked & Verified')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNewLender
                    ? 'The walk-in is complete. The lender can now log in and apply for a loan on their own.'
                    : 'This phone number already has a lender account — it was linked and verified. The lender can log in with their existing password and apply for a loan.',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if (isNewLender) ...[
                const SizedBox(height: 12),
                _credentialRow('Phone', loginPhone),
                const SizedBox(height: 6),
                _credentialRow('Password', '12345678'),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onComplete();
      Navigator.pop(context);
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
    return _ValidatedTextField(
      label: label,
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      prefix: prefix,
      showError: _showFieldErrors,
      validator: validator ?? _requiredValidator,
      onChanged: onChanged,
    );
  }

  Widget _simpleField(String label,
      {required TextEditingController controller,
      TextInputType? keyboardType,
      int? maxLength}) {
    return _ValidatedTextField(
      label: label,
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      showError: _showFieldErrors,
      validator: _requiredValidator,
    );
  }

  /// Optional text field (middle name / suffix) — no required validator.
  Widget _optionalField(String label, TextEditingController ctrl,
      {int? maxLength}) {
    return _ValidatedTextField(
      label: label,
      controller: ctrl,
      maxLength: maxLength,
      showError: _showFieldErrors,
      // Laging valid — walang error na maipapakita sa optional field.
      validator: (_) => null,
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return _ValidatedDropdownField(
      label: label,
      value: value,
      options: options,
      showError: _showFieldErrors,
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
    _errorHideTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation display helpers
// ─────────────────────────────────────────────────────────────────────────────

/// TextField na may SARILING `FormField` (sa halip na `TextFormField`) para
/// kontrolado natin kung kailan iginuguhit ang error text.
///
/// Mahalaga: laging tumatakbo ang [validator] at nakarehistro pa rin sa
/// `Form` — kaya hindi naaapektuhan ang `_formKey.currentState!.validate()`
/// (hindi ito humaharang o nagpapalusot sa Next/Submit). Ang tanging
/// kontrolado ay ang PAGPAPAKITA: kapag `showError == false` (lampas na sa
/// 2-second window), hindi iginuguhit ang error at wala ring reserbang space
/// sa ilalim ng field — hindi na "naka-stack" pataas ang form.
class _ValidatedTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool showError;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final String? prefix;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  const _ValidatedTextField({
    required this.label,
    required this.controller,
    required this.validator,
    required this.showError,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.prefix,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      // Ang `controller.text` ang sinusuri (hindi ang sariling value ng
      // FormField) — pwedeng ma-prefill ito ng `_applyDetails` pagkatapos ng
      // async load, kaya dapat laging kasalukuyang nilalaman ang tinitignan.
      validator: (_) => validator(controller.text),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: (v) {
          field.didChange(v);
          onChanged?.call(v);
        },
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          prefixText: prefix,
          suffixIcon: suffixIcon,
          errorMaxLines: 2,
          errorText: showError ? field.errorText : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

/// Dropdown version ng [_ValidatedTextField] — parehong 2-second show/hide ng
/// error text (hindi "naka-stack"), pero tuloy pa rin ang validation ng `Form`.
class _ValidatedDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final bool showError;
  final ValueChanged<String?> onChanged;

  const _ValidatedDropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.showError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Lokal na kopya ng `value` — ang mga instance field ay hindi nagpi-promote
    // sa Dart, kaya hindi basta-basta ma-che-check ang `value.isEmpty`.
    final selected = value;
    return FormField<String>(
      initialValue: selected,
      // Ang `value` ng parent (hal. `_gender`) ang sinusuri — maaaring
      // ma-prefill ito ng details pagkatapos ng unang build.
      validator: (_) => (selected == null || selected.isEmpty)
          ? 'This field is required'
          : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => InputDecorator(
        // Nakataas ang label kapag may napiling value — gaya ng
        // DropdownButtonFormField.
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          errorMaxLines: 2,
          errorText: showError ? field.errorText : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isDense: true,
            isExpanded: true,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              field.didChange(v);
              onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}
