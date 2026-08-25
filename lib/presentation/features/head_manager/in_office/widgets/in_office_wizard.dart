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

  const InOfficeWizard({
    super.key,
    this.applicationId,
    required this.onComplete,
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

  static const List<(String, String)> _docTypes = [
    ('valid_id', 'Valid Government ID'),
    ('proof_of_income', 'Proof of Income'),
    ('barangay_clearance', 'Barangay Clearance'),
    ('pay_slip', 'Pay Slip'),
  ];

  int _step = 0;
  String? _appId;
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();

  // Step 1 controllers
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _monthlyIncomeCtrl = TextEditingController();

  // Step 2 controllers
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  String? _emergencyRel;

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

  @override
  void initState() {
    super.initState();
    _appId = widget.applicationId;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 680,
        height: 600,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
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
          const Icon(Icons.person_add, color: AppColors.gold, size: 22),
          const SizedBox(width: 10),
          const Text('Walk-in Loan Application',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Identify', 'Address', 'Loan', 'Co-Maker', 'Docs & Sign'];
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: switch (_step) {
          0 => _buildStep1(),
          1 => _buildStep2(),
          2 => _buildStep3(),
          3 => _buildStep4(),
          4 => _buildStep5(),
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
        const Text('Search for an existing lender or create a new account.',
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
        _field('Monthly Income', _monthlyIncomeCtrl,
            keyboardType: TextInputType.number,
            prefix: '₱',
            maxLength: 12,
            validator: _numberValidator),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Address & Emergency Contacts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Enter home/work address and emergency contact.',
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
        const SizedBox(height: 20),
        _sectionTitle('Emergency Contact'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _simpleField('Contact Name',
                    controller: _emergencyNameCtrl, maxLength: 100)),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown(
                'Relationship',
                _emergencyRel,
                _relationshipOptions,
                (v) => setState(() => _emergencyRel = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _simpleField('Phone Number',
            controller: _emergencyPhoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 11),
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
      ],
    );
  }

  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Documents & Signature',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Upload all required documents and capture the lender signature.',
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
        const SizedBox(height: 16),
        const Text('Lender Signature',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _docUploadCard(String type, String label) {
    final file = _docs[type];
    final hasFile = file != null;
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
        leading: Icon(
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
              onPressed: () => setState(() => _step--),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_step < 4)
            ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Next'),
            )
          else
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
              ),
              child: const Text('Submit Application'),
            ),
        ],
      ),
    );
  }

  Future<void> _nextStep() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_appId != null) {
      final data = _collectStepData(_step);
      if (data.isNotEmpty) {
        final ok = await ref
            .read(hmInOfficeProvider.notifier)
            .saveStep(_appId!, _step + 1, data);
        if (!ok) {
          if (mounted) _showMessage('Failed to save step ${_step + 1}. Please try again.');
          return;
        }
      }
    }
    if (mounted) setState(() => _step++);
  }

  Map<String, dynamic> _collectStepData(int step) {
    return switch (step) {
      0 => {
          'phone': _phoneCtrl.text.trim(),
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          // Strip commas so backend Number() does not produce NaN (e.g. "10,000" → "10000").
          'monthly_income': _monthlyIncomeCtrl.text.replaceAll(',', '').trim(),
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
          'emergency_contacts': [
            {
              'name': _emergencyNameCtrl.text.trim(),
              'relationship': _emergencyRel,
              'phone_number': _emergencyPhoneCtrl.text.trim(),
            }
          ],
        },
      2 => {
          // Strip commas: Number("10,000") === NaN on the server, causing INCOMPLETE_WIZARD/DB_ERROR.
          'principal_amount':
              _amountCtrl.text.replaceAll(',', '').trim(),
          'frequency': _frequency,
          'term_periods': _termPeriods,
          'purpose': _purposeCtrl.text.trim(),
        },
      3 => {
          'first_name': _coFirstCtrl.text.trim(),
          'last_name': _coLastCtrl.text.trim(),
          'relationship': _coRel,
          'phone_number': _coPhoneCtrl.text.trim(),
          'address': _coAddressCtrl.text.trim(),
        },
      4 => {'documents': <Map<String, dynamic>>[]},
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
      setState(() => _docsError =
          'Please upload all required documents: ${missingDocs.join(', ')}');
      return;
    }
    if (_signature == null || _signature!.isEmpty) {
      setState(() => _signatureError = 'Lender signature is required');
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
      for (var step = 0; step < 5; step++) {
        var data = _collectStepData(step);
        if (step == 4) {
          data = await _buildStep5Data();
        }
        if (data.isNotEmpty) {
          final ok = await ref
              .read(hmInOfficeProvider.notifier)
              .saveStep(_appId!, step + 1, data);
          if (!ok) {
            if (mounted) _showMessage('Failed to save step ${step + 1}. Server rejected the data.');
            setState(() => _loading = false);
            return;
          }
        }
      }
      final submitted = await ref.read(hmInOfficeProvider.notifier).submitApplication(_appId!);
      if (!submitted) {
        if (mounted) _showMessage('Submit failed. Application data is incomplete or already submitted.');
        setState(() => _loading = false);
        return;
      }
      widget.onComplete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showMessage('Submit failed: $e');
      setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _buildStep5Data() async {
    final docs = <Map<String, dynamic>>[];
    for (final entry in _docs.entries) {
      final f = entry.value;
      final path = await SupabaseStorageService.instance.uploadFile(
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
    String? signaturePath;
    if (_signature != null && _signature!.isNotEmpty) {
      try {
        // _signature is base64-encoded PNG bytes (no data: prefix). Upload to
        // storage so DB column (VARCHAR 255 / future TEXT) stores a short path,
        // not a 20KB base64 string that overflows and causes PATCH 500.
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
        // server will also truncate/log. Signature will be degraded but wizard
        // can still complete and submit.
        // ignore: avoid_print
        print('[InOfficeWizard] signature upload failed, falling back to truncated base64: $e');
        signaturePath = _signature!.length > 255 ? _signature!.substring(0, 255) : _signature;
      }
    }
    return {
      'documents': docs,
      if (signaturePath != null) 'borrower_signature': signaturePath,
    };
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _numberValidator(String? value) {
    final v = _requiredValidator(value);
    if (v != null) return v;
    final d = double.tryParse(value!.trim());
    if (d == null || d <= 0) {
      return 'Enter a valid amount';
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
    _lastNameCtrl.dispose();
    _monthlyIncomeCtrl.dispose();
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    _coFirstCtrl.dispose();
    _coLastCtrl.dispose();
    _coPhoneCtrl.dispose();
    _coAddressCtrl.dispose();
    super.dispose();
  }
}
