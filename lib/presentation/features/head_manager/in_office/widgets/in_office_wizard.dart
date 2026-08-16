// lib/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_in_office_provider.dart';

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
  int _step = 0;
  String? _appId;
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();

  // Step 1 controllers
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _monthlyIncomeCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();

  // Step 2 controllers
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyRelCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // Step 3 controllers
  final _amountCtrl = TextEditingController();
  String _frequency = 'monthly';
  final _purposeCtrl = TextEditingController();
  Map<String, dynamic>? _schedulePreview;

  // Step 4 controllers
  final _coFirstCtrl = TextEditingController();
  final _coLastCtrl = TextEditingController();
  final _coRelCtrl = TextEditingController();
  final _coPhoneCtrl = TextEditingController();
  final _coAddressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _appId = widget.applicationId;
  }

  Future<void> _createDraft() async {
    setState(() => _loading = true);
    try {
      final id = await ref.read(hmInOfficeProvider.notifier).createDraft();
      setState(() {
        _appId = id;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
            keyboardType: TextInputType.phone, validator: _phoneValidator),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field('First Name', _firstNameCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _field('Last Name', _lastNameCtrl)),
          ],
        ),
        const SizedBox(height: 12),
        _field('Monthly Income', _monthlyIncomeCtrl,
            keyboardType: TextInputType.number,
            prefix: '₱',
            validator: _numberValidator),
        const SizedBox(height: 12),
        _field('GCash Number', _gcashCtrl,
            keyboardType: TextInputType.phone, validator: _phoneValidator),
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
        _simpleField('Street / Barangay', controller: _streetCtrl),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _simpleField('City', controller: _cityCtrl)),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Province', controller: _provinceCtrl)),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('Emergency Contact'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _simpleField('Contact Name',
                    controller: _emergencyNameCtrl)),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Relationship',
                    controller: _emergencyRelCtrl)),
          ],
        ),
        const SizedBox(height: 8),
        _simpleField('Phone Number',
            controller: _emergencyPhoneCtrl, keyboardType: TextInputType.phone),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Set the loan amount and payment frequency.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _field('Loan Amount', _amountCtrl,
            keyboardType: TextInputType.number,
            prefix: '₱',
            validator: _numberValidator),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _frequency,
          decoration: InputDecoration(
            labelText: 'Payment Frequency',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (v) => setState(() => _frequency = v!),
        ),
        const SizedBox(height: 12),
        _field('Purpose', _purposeCtrl, maxLines: 2),
        const SizedBox(height: 16),
        if (_amountCtrl.text.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: _previewSchedule,
            icon: const Icon(Icons.calculate, size: 16),
            label: const Text('Preview Schedule'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
            ),
          ),
          if (_schedulePreview != null) ...[
            const SizedBox(height: 12),
            _buildSchedulePreview(),
          ],
        ],
      ],
    );
  }

  Widget _buildSchedulePreview() {
    final p = _schedulePreview!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _previewRow('Total Payable',
              '₱${(p['total_payable'] as num?)?.toStringAsFixed(2) ?? '0'}'),
          _previewRow('Interest (20%)',
              '₱${(p['interest_amount'] as num?)?.toStringAsFixed(2) ?? '0'}'),
          _previewRow('Installment',
              '₱${(p['installment_amount'] as num?)?.toStringAsFixed(2) ?? '0'}'),
          _previewRow('Term',
              '${p['installments'] ?? p['term_days'] ?? 0} ${_termUnitFor(p['frequency'])}'),
        ],
      ),
    );
  }

  String _termUnitFor(dynamic frequency) {
    final f = (frequency ?? '').toString().toLowerCase();
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
            Expanded(child: _simpleField('Co-Maker First Name',
                controller: _coFirstCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _simpleField('Co-Maker Last Name',
                controller: _coLastCtrl)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _simpleField('Relationship',
                controller: _coRelCtrl)),
            const SizedBox(width: 12),
            Expanded(
                child: _simpleField('Phone',
                    controller: _coPhoneCtrl,
                    keyboardType: TextInputType.phone)),
          ],
        ),
        const SizedBox(height: 12),
        _simpleField('Address', controller: _coAddressCtrl),
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
        const Text('Upload required documents and capture borrower signature.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _docUploadRow('Valid Government ID'),
        _docUploadRow('Proof of Income'),
        _docUploadRow('Barangay Clearance'),
        _docUploadRow('Pay Slip'),
        const SizedBox(height: 20),
        const Text('Borrower Signature',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text('Signature pad — capture here',
              style: TextStyle(color: AppColors.textTertiary)),
        ),
      ],
    );
  }

  Widget _docUploadRow(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Upload'),
            style: TextButton.styleFrom(foregroundColor: AppColors.deepNavy),
          ),
        ],
      ),
    );
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
    await _saveStepData();
    if (mounted) setState(() => _step++);
  }

  Future<void> _saveStepData() async {
    if (_appId == null) {
      await _createDraft();
      if (_appId == null) return;
    }
    final data = switch (_step) {
      0 => {
          'phone': _phoneCtrl.text,
          'first_name': _firstNameCtrl.text,
          'last_name': _lastNameCtrl.text,
          'monthly_income': _monthlyIncomeCtrl.text,
          'gcash_number': _gcashCtrl.text,
        },
      1 => {
          'addresses': [
            {
              'address_type': 'home',
              'street': _streetCtrl.text,
              'city': _cityCtrl.text,
              'province': _provinceCtrl.text,
            }
          ],
          'emergency_contacts': [
            {
              'name': _emergencyNameCtrl.text,
              'relationship': _emergencyRelCtrl.text,
              'phone_number': _emergencyPhoneCtrl.text,
            }
          ],
        },
      2 => {
          'principal_amount': _amountCtrl.text,
          'frequency': _frequency,
          'term_periods':
              (_schedulePreview?['installments'] as num?)?.toInt(),
          'purpose': _purposeCtrl.text,
        },
      3 => {
          'first_name': _coFirstCtrl.text,
          'last_name': _coLastCtrl.text,
          'relationship': _coRelCtrl.text,
          'phone_number': _coPhoneCtrl.text,
          'address': _coAddressCtrl.text,
        },
      _ => <String, dynamic>{},
    };
    if (data.isNotEmpty) {
      await ref
          .read(hmInOfficeProvider.notifier)
          .saveStep(_appId!, _step + 1, data);
    }
  }

  Future<void> _previewSchedule() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null) return;
    try {
      final preview = await ref
          .read(hmInOfficeProvider.notifier)
          .getSchedulePreview(amount, _frequency);
      setState(() => _schedulePreview = preview);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_appId == null) {
      await _createDraft();
      if (_appId == null) return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(hmInOfficeProvider.notifier).submitApplication(_appId!);
      widget.onComplete();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _loading = false);
    }
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
    if (double.tryParse(value!.trim()) == null) {
      return 'Enter a valid amount';
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
      FormFieldValidator<String>? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator ?? _requiredValidator,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _simpleField(String label,
      {TextEditingController? controller, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: _requiredValidator,
      decoration: InputDecoration(
        labelText: label,
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
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
    _gcashCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyRelCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    _coFirstCtrl.dispose();
    _coLastCtrl.dispose();
    _coRelCtrl.dispose();
    _coPhoneCtrl.dispose();
    _coAddressCtrl.dispose();
    super.dispose();
  }
}
