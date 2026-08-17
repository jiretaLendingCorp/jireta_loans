// lib/presentation/shared/widgets/edit_user_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/user_remote_datasource.dart';

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
  String _role = '';
  String _status = 'active';

  static const List<String> _roles = [
    'head_manager',
    'employee',
    'rider',
    'lender',
  ];
  static const List<String> _statuses = ['active', 'inactive', 'archived'];

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _status = widget.initialStatus;
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
        if (data['role'] is Map) {
          _role = (data['role'] as Map)['name'] as String? ?? _role;
        } else if (data['role'] is String) {
          _role = data['role'] as String;
        }
        final status = (data['account_status'] as String?) ?? 'active';
        if (_statuses.contains(status)) _status = status;
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
        if (widget.showRole) 'role': _role,
        'account_status': _status,
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

  String _roleLabel(String r) => r.split('_').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            decoration: BoxDecoration(
                              color: AppColors.errorLight,
                              borderRadius: BorderRadius.circular(8),
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: TextEditingController(text: _email),
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (widget.showRole) ...[
                              Expanded(
                                child: _roleDropdown(),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: _statusDropdown(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _roleDropdown() => DropdownButtonFormField<String>(
        initialValue: _role,
        decoration: const InputDecoration(
          labelText: 'Role',
          border: OutlineInputBorder(),
        ),
        items: _roles
            .map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(_roleLabel(r)),
                ))
            .toList(),
        onChanged: (v) => setState(() => _role = v ?? _role),
      );

  Widget _statusDropdown() => DropdownButtonFormField<String>(
        initialValue: _status,
        decoration: const InputDecoration(
          labelText: 'Account Status',
          border: OutlineInputBorder(),
        ),
        items: _statuses
            .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(_statusLabel(s)),
                ))
            .toList(),
        onChanged: (v) => setState(() => _status = v ?? _status),
      );

  String _statusLabel(String s) {
    switch (s) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'archived':
        return 'Archived';
      default:
        return s;
    }
  }

  Widget _f(String label, TextEditingController c,
          {bool req = false, int? maxLength}) =>
      TextFormField(
        controller: c,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        validator: req
            ? (v) => (v == null || v.trim().isEmpty)
                ? '$label is required'
                : null
            : null,
      );
}
