// lib/presentation/features/rider/profile/screens/rider_edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/rider_profile_provider.dart';

class RiderProfileEditScreen extends ConsumerStatefulWidget {
  const RiderProfileEditScreen({super.key});

  @override
  ConsumerState<RiderProfileEditScreen> createState() =>
      _RiderEditProfileScreenState();
}

class _RiderEditProfileScreenState
    extends ConsumerState<RiderProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _initialized = false;

  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard),
    MobileNavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments,
        label: 'Collections',
        route: RouteConstants.riderCollections),
    MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  void _initFromState() {
    if (_initialized) return;
    final state = ref.read(riderProfileProvider);
    final user = state.user;
    if (user == null) return;
    _firstNameCtrl.text = user.firstName;
    _lastNameCtrl.text = user.lastName;
    _plateCtrl.text = state.plateNumber ?? '';
    _licenseCtrl.text = state.licenseNumber ?? '';
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'rider_profile': {
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
      },
    });
    if (!mounted) return;
    if (ok) {
      await showDialog(
        context: context,
        builder: (_) => const SuccessDialog(
          title: 'Profile Updated',
          message: 'Your profile has been updated successfully.',
        ),
      );
      if (mounted) context.go(RouteConstants.riderProfile);
    } else {
      final err = ref.read(riderProfileProvider).error;
      await showErrorDialog(
        context,
        message: err ?? 'Failed to update profile. Please try again.',
      );
    }
  }

  String? Function(String?) _requiredValidator(String label) {
    return (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderProfileProvider);

    if (!_initialized && state.user != null) {
      _initFromState();
    }

    return MobileScaffold(
      title: 'Edit Profile',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionCard(
                      'Personal Information',
                      Icons.person_outline,
                      [
                        AppTextField(
                          label: 'First Name',
                          controller: _firstNameCtrl,
                          validator: _requiredValidator('First name'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Last Name',
                          controller: _lastNameCtrl,
                          validator: _requiredValidator('Last name'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      'Rider Information',
                      Icons.directions_bike_outlined,
                      [
                        AppTextField(
                          label: 'Plate Number',
                          controller: _plateCtrl,
                          validator: _requiredValidator('Plate number'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: "Driver's License Number",
                          controller: _licenseCtrl,
                          validator:
                              _requiredValidator("Driver's license number"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: state.isSaving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.riderGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: state.isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            context.go(RouteConstants.riderProfile),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.riderGreen),
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
    );
  }
}
