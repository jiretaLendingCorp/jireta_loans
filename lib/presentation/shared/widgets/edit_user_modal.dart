// lib/presentation/shared/widgets/edit_user_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/user_remote_datasource.dart';
import 'forms/app_date_picker.dart';

class EditUserModal extends ConsumerStatefulWidget {
  final String userId;
  final String initialRole;
  final String initialStatus;
  final bool showRole;

  const EditUserModal({
    super.key,
    required this.userId,
    required this.initialRole,
    required this.initialStatus,
    this.showRole = true,
  });

  @override
  ConsumerState<EditUserModal> createState() => _EditUserModalState();
}

class _EditUserModalState extends ConsumerState<EditUserModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _email;
  // Staff-only fields (head_manager / employee live in employee_profiles).
  String? _gender;
  String? _civilStatus;
  DateTime? _dob;

  static const _genders = ['male', 'female', 'other'];
  static const _civilStatuses = ['single', 'married', 'widowed', 'separated'];

  bool get _isStaff =>
      widget.initialRole == 'head_manager' ||
      widget.initialRole == 'employee';

  String _label(String code) =>
      code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);

  String? _asKnownCode(Object? v, List<String> allowed) {
    final s = (v as String?)?.trim().toLowerCase();
    return (s != null && allowed.contains(s)) ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ds = sl<UserRemoteDataSource>();
      final data = await ds.getProfileMap(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _firstCtrl.text = (data['first_name'] as String?) ?? '';
        _middleCtrl.text = (data['middle_name'] as String?) ?? '';
        _lastCtrl.text = (data['last_name'] as String?) ?? '';
        _suffixCtrl.text = (data['suffix'] as String?) ?? '';
        _phoneCtrl.text = (data['phone_number'] as String?) ?? '';
        _email = (data['email'] as String?) ?? '';
        _gender = _asKnownCode(data['gender'], _genders);
        _civilStatus = _asKnownCode(data['civil_status'], _civilStatuses);
        final dobRaw = (data['date_of_birth'] as String?)?.trim();
        _dob = (dobRaw != null && dobRaw.isNotEmpty)
            ? DateTime.tryParse(dobRaw.substring(0, 10))
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorHandler.handle(e).message;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ds = sl<UserRemoteDataSource>();
      await ds.updateProfile({
        'user_id': widget.userId,
        'first_name': _firstCtrl.text.trim(),
        'middle_name': _middleCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'suffix': _suffixCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        if (_isStaff)
          'employee_profile': {
            if (_gender != null) 'gender': _gender,
            if (_civilStatus != null) 'civil_status': _civilStatus,
            if (_dob != null)
              'date_of_birth':
                  '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
          },
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorHandler.handle(e).message;
      });
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    _suffixCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          child: _loading
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              color: AppColors.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Edit User',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Edit user details. Changes apply immediately.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: AppColors.errorLight,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: _f('First Name', _firstCtrl,
                                  req: true, maxLength: 100),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _f('Last Name', _lastCtrl,
                                  req: true, maxLength: 100),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _f('Middle Name', _middleCtrl,
                                  maxLength: 100),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _f('Suffix', _suffixCtrl, maxLength: 100),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _f('Phone Number', _phoneCtrl, maxLength: 11),
                        if (_isStaff) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _gender,
                                  decoration: const InputDecoration(
                                    labelText: 'Gender',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.zero),
                                  ),
                                  items: _genders
                                      .map((g) => DropdownMenuItem(
                                          value: g, child: Text(_label(g))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _gender = v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _civilStatus,
                                  decoration: const InputDecoration(
                                    labelText: 'Civil Status',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.zero),
                                  ),
                                  items: _civilStatuses
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(_label(c))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _civilStatus = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppDatePicker(
                            label: 'Date of Birth',
                            value: _dob,
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now(),
                            onChanged: (d) => setState(() => _dob = d),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: TextEditingController(text: _email),
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.zero),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Role and Account Status removed per spec — only profile fields are editable.
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );



  Widget _f(String label, TextEditingController c,
          {bool req = false, int? maxLength}) =>
      TextFormField(
        controller: c,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
          counterText: '',
        ),
        validator: req
            ? (v) => (v == null || v.trim().isEmpty)
                ? '$label is required'
                : null
            : null,
      );
}
