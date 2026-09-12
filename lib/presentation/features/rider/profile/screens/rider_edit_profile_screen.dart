// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/profile/screens/rider_edit_profile_screen.dart
//
// Minimal "text-like" edit form: walang boxed inputs, manipis na underline
// lang ang mga value. Sinasalamin ang lahat ng nasa Personal Details at
// Rider Information (maliban sa Member since), kasama ang Phone, Email,
// Vehicle Type at Vehicle Brand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
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
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _otherBrandCtrl = TextEditingController();

  String _vehicleType = 'motorcycle';
  String? _vehicleBrand;
  bool _initialized = false;

  static const _brands = [
    'Honda',
    'Yamaha',
    'Suzuki',
    'Kawasaki',
    'Kymco',
    'Mio',
    'Vespa',
    'Piaggio',
    'Bajaj',
    'TVS',
    'Benelli',
    'Rusi',
    'Royal Enfield',
    'Toyota',
    'Mitsubishi',
    'Nissan',
    'Hyundai',
    'Isuzu',
    'Ford',
    'Chevrolet',
  ];

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
        icon: Icons.history_outlined,
        activeIcon: Icons.history_rounded,
        label: 'History',
        route: RouteConstants.riderHistory),
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
    final user = ref.read(riderProfileProvider).user;
    if (user == null) return;
    _firstNameCtrl.text = user.firstName;
    _middleNameCtrl.text = user.middleName ?? '';
    _lastNameCtrl.text = user.lastName;
    _suffixCtrl.text = user.suffix ?? '';
    _phoneCtrl.text = user.phoneNumber ?? '';
    _emailCtrl.text = user.email ?? '';
    _plateCtrl.text = user.plateNumber ?? '';
    _licenseCtrl.text = user.driversLicenseNumber ?? '';

    final type = (user.vehicleType ?? '').toString().toLowerCase();
    _vehicleType =
        (type == 'bicycle' || type == 'car') ? type : 'motorcycle';

    final brand = (user.vehicleBrand ?? '').toString().trim();
    if (brand.isEmpty) {
      _vehicleBrand = null;
    } else if (_brands.contains(brand)) {
      _vehicleBrand = brand;
    } else {
      _vehicleBrand = 'other';
      _otherBrandCtrl.text = brand;
    }

    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    _otherBrandCtrl.dispose();
    super.dispose();
  }

  String get _resolvedBrand {
    if (_vehicleBrand == null) return '';
    if (_vehicleBrand == 'other') return _otherBrandCtrl.text.trim();
    return _vehicleBrand!;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehicleBrand == null) {
      await showErrorDialog(context, message: 'Please select a vehicle brand.');
      return;
    }
    if (_vehicleBrand == 'other' && _otherBrandCtrl.text.trim().isEmpty) {
      await showErrorDialog(context, message: 'Please enter the vehicle brand.');
      return;
    }
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'first_name': _firstNameCtrl.text.trim(),
      'middle_name': _middleNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'suffix': _suffixCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'rider_profile': {
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        'vehicle_brand': _resolvedBrand,
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

  String? Function(String?) _required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : 'Enter a valid email address';
  }

  String? _validatePhone(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Phone number is required';
    if (value.length != 11) return 'Phone number must be 11 digits';
    return null;
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
      body: state.isLoading && state.user == null
          ? const ShimmerLoader()
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      'Personal Information',
                      Icons.person_outline_rounded,
                      [
                        AppTextField(
                          label: 'First Name',
                          controller: _firstNameCtrl,
                          minimal: true,
                          maxLength: 100,
                          validator: _required('First name'),
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Middle Name (optional)',
                          controller: _middleNameCtrl,
                          minimal: true,
                          maxLength: 100,
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Last Name',
                          controller: _lastNameCtrl,
                          minimal: true,
                          maxLength: 100,
                          validator: _required('Last name'),
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Suffix (optional)',
                          controller: _suffixCtrl,
                          minimal: true,
                          maxLength: 20,
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Phone Number',
                          controller: _phoneCtrl,
                          minimal: true,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: _validatePhone,
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Email Address',
                          controller: _emailCtrl,
                          minimal: true,
                          keyboardType: TextInputType.emailAddress,
                          maxLength: 150,
                          validator: _validateEmail,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _section(
                      'Rider Information',
                      Icons.two_wheeler_outlined,
                      [
                        AppTextField(
                          label: 'Plate Number',
                          controller: _plateCtrl,
                          minimal: true,
                          maxLength: 20,
                          validator: _required('Plate number'),
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: "Driver's License Number",
                          controller: _licenseCtrl,
                          minimal: true,
                          maxLength: 50,
                          validator: _required("Driver's license number"),
                        ),
                        const SizedBox(height: 18),
                        _minimalDropdown(
                          key: ValueKey('vt-$_vehicleType'),
                          label: 'Vehicle Type',
                          value: _vehicleType,
                          items: const [
                            DropdownMenuItem(
                                value: 'motorcycle', child: Text('Motorcycle')),
                            DropdownMenuItem(
                                value: 'bicycle', child: Text('Bicycle')),
                            DropdownMenuItem(value: 'car', child: Text('Car')),
                          ],
                          onChanged: (v) =>
                              setState(() => _vehicleType = v ?? 'motorcycle'),
                        ),
                        const SizedBox(height: 18),
                        _minimalDropdown(
                          key: ValueKey('vb-$_vehicleBrand'),
                          label: 'Vehicle Brand',
                          value: _vehicleBrand,
                          hint: 'Select brand',
                          items: [
                            ..._brands.map((b) => DropdownMenuItem(
                                value: b, child: Text(b))),
                            const DropdownMenuItem(
                                value: 'other', child: Text('Other')),
                          ],
                          onChanged: (v) =>
                              setState(() => _vehicleBrand = v),
                        ),
                        if (_vehicleBrand == 'other') ...[
                          const SizedBox(height: 18),
                          AppTextField(
                            label: 'Other Brand',
                            controller: _otherBrandCtrl,
                            minimal: true,
                            maxLength: 100,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 28),
                    ModernPrimaryButton(
                      label: 'Save Changes',
                      color: AppColors.riderGreen,
                      loading: state.isSaving,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () =>
                            context.go(RouteConstants.riderProfile),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cTextSecondary,
                          backgroundColor: context.cSurface,
                          side: BorderSide(color: context.cBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Minimal section: maliit na icon + title, hairlines lang — walang boxed
  /// input sa loob dahil text-like ang mga field.
  Widget _section(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: ModernProfileStyles.iconBgOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 15, color: ModernProfileStyles.iconColorOf(context)),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: context.cTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  /// Text-like dropdown para pantay sa minimal na AppTextField.
  Widget _minimalDropdown({
    Key? key,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: context.cSurface,
      style: TextStyle(fontSize: 14, color: context.cTextPrimary),
      hint: hint != null
          ? Text(hint,
              style: TextStyle(fontSize: 14, color: context.cTextTertiary))
          : null,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
        labelStyle: TextStyle(
          fontSize: 12,
          color: context.cTextTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          color: context.cTextPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        border: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cBorder)),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cBorder)),
        focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cTextPrimary, width: 1.5)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
