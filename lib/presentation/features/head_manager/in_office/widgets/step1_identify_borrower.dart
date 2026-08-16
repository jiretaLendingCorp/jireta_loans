// lib/presentation/features/head_manager/in_office/widgets/step1_identify_borrower.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../domain/repositories/i_user_repository.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/app_button.dart';

class Step1IdentifyBorrower extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onDataChanged;

  const Step1IdentifyBorrower({
    super.key,
    required this.data,
    required this.onDataChanged,
  });

  @override
  ConsumerState<Step1IdentifyBorrower> createState() =>
      _Step1IdentifyBorrowerState();
}

class _Step1IdentifyBorrowerState extends ConsumerState<Step1IdentifyBorrower> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedLender;
  bool _isSearching = false;
  bool _isNewLender = false;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
  String _employmentType = 'employed';
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    if (widget.data['lender_id'] != null) {
      _selectedLender = widget.data['lender'] as Map<String, dynamic>?;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _gcashCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() => _isSearching = true);
    try {
      final repo = sl<IUserRepository>();
      final results = await repo.getUserList(
        role: 'lender',
        search: query.trim(),
        page: 1,
        limit: 10,
      );
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(
          (results['users'] as List? ?? [])
              .map((u) => u as Map<String, dynamic>),
        );
      });
    } catch (_) {
      setState(() => _searchResults = []);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _selectLender(Map<String, dynamic> lender) {
    setState(() {
      _selectedLender = lender;
      _isNewLender = false;
      _searchResults = [];
      _searchCtrl.text =
          '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    });
    widget.onDataChanged({
      'lender_id': lender['id'],
      'lender': lender,
      'is_new_lender': false,
    });
  }

  void _startNewLender() {
    setState(() {
      _isNewLender = true;
      _selectedLender = null;
      _searchResults = [];
    });
    widget.onDataChanged({'is_new_lender': true});
  }

  void _updateNewLenderData() {
    widget.onDataChanged({
      'is_new_lender': true,
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'gcash_number': _gcashCtrl.text.trim(),
      'monthly_income':
          double.tryParse(_incomeCtrl.text.replaceAll(',', '')) ?? 0,
      'gender': _gender,
      'civil_status': _civilStatus,
      'employment_type': _employmentType,
      'dob': _dob?.toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Identify Lender',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Search for an existing lender or create a new walk-in applicant.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (!_isNewLender) ...[
            AppTextField(
              controller: _searchCtrl,
              label: 'Search by name or phone number',
              prefixIcon: Icons.search,
              onChanged: (v) => _search(v),
            ),
            const SizedBox(height: 8),
            if (_isSearching) const Center(child: CircularProgressIndicator()),
            if (_searchResults.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final l = _searchResults[i];
                    return ListTile(
                      onTap: () => _selectLender(l),
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        child: Text(
                          (l['first_name'] as String? ?? 'L')[0].toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      title: Text(
                          '${l['first_name'] ?? ''} ${l['last_name'] ?? ''}'
                              .trim()),
                      subtitle: Text(l['phone_number'] ?? l['email'] ?? ''),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    );
                  },
                ),
              ),
            if (_selectedLender != null) ...[
              const SizedBox(height: 12),
              _SelectedLenderCard(lender: _selectedLender!),
            ],
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Create New Walk-in Applicant',
              onPressed: _startNewLender,
              variant: AppButtonVariant.secondary,
              icon: Icons.person_add_outlined,
            ),
          ],
          if (_isNewLender) ...[
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _isNewLender = false),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'New Applicant Details',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _firstNameCtrl,
                    label: 'First Name *',
                    onChanged: (_) => _updateNewLenderData(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _lastNameCtrl,
                    label: 'Last Name *',
                    onChanged: (_) => _updateNewLenderData(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _phoneCtrl,
              label: 'Phone Number *',
              keyboardType: TextInputType.phone,
              onChanged: (_) => _updateNewLenderData(),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _emailCtrl,
              label: 'Email (Optional)',
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => _updateNewLenderData(),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _gcashCtrl,
              label: 'GCash Number',
              keyboardType: TextInputType.phone,
              onChanged: (_) => _updateNewLenderData(),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _incomeCtrl,
              label: 'Monthly Income (₱)',
              keyboardType: TextInputType.number,
              onChanged: (_) => _updateNewLenderData(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) {
                setState(() => _gender = v ?? 'male');
                _updateNewLenderData();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _civilStatus,
              decoration: InputDecoration(
                labelText: 'Civil Status',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
              items: const [
                DropdownMenuItem(value: 'single', child: Text('Single')),
                DropdownMenuItem(value: 'married', child: Text('Married')),
                DropdownMenuItem(value: 'widowed', child: Text('Widowed')),
                DropdownMenuItem(value: 'separated', child: Text('Separated')),
              ],
              onChanged: (v) {
                setState(() => _civilStatus = v ?? 'single');
                _updateNewLenderData();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _employmentType,
              decoration: InputDecoration(
                labelText: 'Employment Type',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
              items: const [
                DropdownMenuItem(value: 'employed', child: Text('Employed')),
                DropdownMenuItem(
                    value: 'self_employed', child: Text('Self-Employed')),
                DropdownMenuItem(
                    value: 'business', child: Text('Business Owner')),
                DropdownMenuItem(
                    value: 'unemployed', child: Text('Unemployed')),
              ],
              onChanged: (v) {
                setState(() => _employmentType = v ?? 'employed');
                _updateNewLenderData();
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(1990),
                  firstDate: DateTime(1920),
                  lastDate:
                      DateTime.now().subtract(const Duration(days: 365 * 18)),
                );
                if (picked != null) {
                  setState(() => _dob = picked);
                  _updateNewLenderData();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(
                      _dob == null
                          ? 'Date of Birth'
                          : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                      style: TextStyle(
                        color: _dob == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedLenderCard extends StatelessWidget {
  final Map<String, dynamic> lender;

  const _SelectedLenderCard({required this.lender});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary,
            radius: 20,
            child: Text(
              (lender['first_name'] as String? ?? 'L')[0].toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                      .trim(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  lender['phone_number'] ?? lender['email'] ?? '',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Selected',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
