// lib/presentation/features/head_manager/profile/screens/hm_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar_upload.dart';
import '../providers/hm_profile_provider.dart';

class HmProfileScreen extends ConsumerStatefulWidget {
  const HmProfileScreen({super.key});

  @override
  ConsumerState<HmProfileScreen> createState() => _HmProfileScreenState();
}

class _HmProfileScreenState extends ConsumerState<HmProfileScreen> {
  bool _editMode = false;
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _showCurrentPw = false;
  bool _showNewPw = false;
  bool _showConfirmPw = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(hmProfileProvider.notifier).loadProfile());
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _populate(dynamic user) {
    if (user == null) return;
    _firstNameCtrl.text = user.firstName ?? '';
    _lastNameCtrl.text = user.lastName ?? '';
    _emailCtrl.text = user.email ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmProfileProvider);

    if (state.isLoading && state.user == null) {
      return const WebScaffold(
        title: 'My Profile',
        body: Padding(
          padding: EdgeInsets.all(24),
          child: ShimmerLoader(height: 300),
        ),
      );
    }

    return WebScaffold(
      title: 'My Profile',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: _buildAvatar(state)),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: _buildInfo(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(HmProfileState state) {
    final name = '${state.user?.firstName ?? ''} ${state.user?.lastName ?? ''}';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          ProfileAvatarUpload(
            photoUrl: state.user?.profilePhotoUrl,
            name: name,
            color: AppColors.deepNavy,
            radius: 48,
            onUploaded: (url) =>
                ref.read(hmProfileProvider.notifier).updatePhoto(url),
          ),
          const SizedBox(height: 16),
          Text(name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Head Manager',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          if (state.user?.email != null)
            Text(state.user!.email!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildInfo(HmProfileState state) {
    return Column(
      children: [
        _buildProfileCard(state),
        const SizedBox(height: 16),
        _buildPasswordCard(state),
      ],
    );
  }

  Widget _buildProfileCard(HmProfileState state) {
    final user = state.user;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Profile Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  if (_editMode) {
                    setState(() => _editMode = false);
                  } else {
                    _populate(user);
                    setState(() => _editMode = true);
                  }
                },
                icon: Icon(_editMode ? Icons.close : Icons.edit, size: 16),
                label: Text(_editMode ? 'Cancel' : 'Edit'),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.deepNavy),
              ),
            ],
          ),
          const Divider(height: 20),
          if (_editMode) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lastNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ] else ...[
            _infoRow('First Name', user?.firstName ?? '-'),
            _infoRow('Last Name', user?.lastName ?? '-'),
            _infoRow('Email', user?.email ?? '-'),
            _infoRow('Role', 'Head Manager'),
            _infoRow('Account Status',
                (user?.accountStatus ?? 'active').toUpperCase()),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordCard(HmProfileState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Change Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Divider(height: 20),
          _pwField('Current Password', _currentPwCtrl, _showCurrentPw,
              () => setState(() => _showCurrentPw = !_showCurrentPw)),
          const SizedBox(height: 12),
          _pwField('New Password', _newPwCtrl, _showNewPw,
              () => setState(() => _showNewPw = !_showNewPw)),
          const SizedBox(height: 12),
          _pwField('Confirm Password', _confirmPwCtrl, _showConfirmPw,
              () => setState(() => _showConfirmPw = !_showConfirmPw)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
  }

  Widget _pwField(String label, TextEditingController ctrl, bool visible,
      VoidCallback onToggle) {
    return TextField(
      controller: ctrl,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: IconButton(
          icon:
              Icon(visible ? Icons.visibility_off : Icons.visibility, size: 18),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await ref.read(hmProfileProvider.notifier).updateProfile(
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
          );
      setState(() {
        _editMode = false;
        _saving = false;
      });
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPwCtrl.text != _confirmPwCtrl.text) return;
    setState(() => _saving = true);
    try {
      await ref.read(hmProfileProvider.notifier).changePassword(
            currentPassword: _currentPwCtrl.text,
            newPassword: _newPwCtrl.text,
          );
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
    } catch (_) {}
    setState(() => _saving = false);
  }
}
