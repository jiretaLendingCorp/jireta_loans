// lib/presentation/features/lender/profile/screens/lender_edit_profile_screen.dart
//
// HIWALAY na edit: ang Personal Information, Email Address, at Residence
// Address ay may tig-sariling screen at sariling Save (dati isang form na
// pinagsama ang lahat). Bawat isa, sariling `users-manage?fn=update-profile`
// na tawag — kaya ang pag-save sa isa ay hindi ginagalaw ang iba pa.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../providers/lender_profile_provider.dart';

/// Bottom nav na kapareho ng lender profile — pareho ito sa dalawang edit
/// screen.
const _lenderProfileNavItems = <MobileNavItem>[
  MobileNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    label: 'Home',
    route: RouteConstants.lenderDashboard,
  ),
  MobileNavItem(
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments,
    label: 'Payments',
    route: RouteConstants.lenderPayments,
  ),
  MobileNavItem(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    label: 'Transaction',
    route: RouteConstants.lenderPaymentHistory,
  ),
  MobileNavItem(
    icon: Icons.person_outline,
    activeIcon: Icons.person,
    label: 'Profile',
    route: RouteConstants.lenderProfile,
  ),
];

/// Card na may icon + title sa itaas ng mga field — kapareho ng dating
/// combined edit screen, ibinahagi lang ng dalawang screen.
Widget _lenderFormSection(
  String title,
  IconData icon,
  List<Widget> children,
) {
  return Container(
    width: double.infinity,
    decoration: ModernProfileStyles.card,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: ModernProfileStyles.iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child:
                  Icon(icon, size: 16, color: ModernProfileStyles.iconColor),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

/// Minimal na outer scaffold: content + NAKA-PIN na action bar sa ibaba ng
/// mobile view.
///
/// [scrollable] = true (default): naka-scroll at naka-center ang content.
/// [scrollable] = false: pinupuno ng content ang natitirang espasyo (para
/// mailagay sa ibaba ang field gamit ang `Spacer`) — hindi ito nag-scroll.
Widget _lenderEditScaffold({
  required String title,
  required bool loading,
  required Widget child,
  required Widget bottomBar,
  bool scrollable = true,
}) {
  final content = Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: child,
    ),
  );
  return MobileScaffold(
    title: title,
    accentColor: AppColors.lenderBlue,
    navItems: _lenderProfileNavItems,
    // May back arrow sa header — bumabalik sa Profile (push ito, kaya
    // Navigator.canPop() ang unang tinatakbo ng MobileScaffold).
    showBackButton: true,
    body: loading
        ? const ShimmerLoader()
        : Column(
            children: [
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: content,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: content,
                      ),
              ),
              bottomBar,
            ],
          ),
  );
}

/// NAKA-PIN na action bar sa ibaba ng mobile view — nakataas sa floating
/// bottom nav pill (safe area + float gap + pill), kaya hindi ito natatakpan
/// ng nav at hindi na kailangang mag-scroll para makita ang button.
Widget _lenderPinnedActions({
  required BuildContext context,
  required bool saving,
  required VoidCallback onSave,
}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      // Ang `context` dito ay ang SCREEN context (nasa labas pa ng body ng
      // MobileScaffold), kaya [mobileBottomNavHeight] ang tamang gamitin —
      // hindi ang [mobileBottomNavInset] na para lang sa loob ng body. Kasama
      // na rito ang safe area + float gap + pill ng bottom nav; maliit na
      // dagdag para hindi dikit sa pill ang button.
      mobileBottomNavHeight(context) + 12,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: saving
                      ? null
                      : () => context.go(RouteConstants.lenderProfile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                        color: ModernProfileStyles.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Pantay ang lapad ng Cancel at Save (`flex: 1` pareho).
            Expanded(
              child: ModernPrimaryButton(
                label: 'Save Changes',
                color: AppColors.lenderBlue,
                loading: saving,
                onPressed: onSave,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 1) Personal Information
// ─────────────────────────────────────────────────────────────────────────────
class LenderEditPersonalInfoScreen extends ConsumerStatefulWidget {
  const LenderEditPersonalInfoScreen({super.key});

  @override
  ConsumerState<LenderEditPersonalInfoScreen> createState() =>
      _LenderEditPersonalInfoScreenState();
}

class _LenderEditPersonalInfoScreenState
    extends ConsumerState<LenderEditPersonalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();

  String? _gender;
  String? _civilStatus;
  DateTime? _dob;
  String? _dobError;
  bool _initialized = false;

  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _civilOptions = ['Single', 'Married', 'Widowed', 'Separated'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  /// Convert a display value (e.g. "Self-Employed", "Prefer not to say") to
  /// the lowercase/underscored form the lender_profiles CHECK constraints use.
  String _toDbEnum(String value) {
    final v = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
    if (v == 'prefer_not_to_say') return 'other';
    return v;
  }

  /// Pick the exact option label for a stored enum value so the dropdown value
  /// always exists in its items list (otherwise DropdownButtonFormField throws
  /// a "There should be exactly one item with [DropdownButton]'s value"
  /// assertion). Falls back to null when the stored value doesn't match.
  String? _normalizeOption(
    String? value,
    List<String> options, {
    Map<String, String>? aliases,
  }) {
    if (value == null || value.isEmpty) return null;
    final key = value.trim().toLowerCase();
    if (aliases != null && aliases.containsKey(key)) {
      final target = aliases[key]!;
      return options.contains(target) ? target : null;
    }
    for (final opt in options) {
      if (opt.toLowerCase().replaceAll(RegExp(r'[\s-]'), '_') == key) {
        return opt;
      }
    }
    return null;
  }

  void _initFromState() {
    if (_initialized) return;
    final user = ref.read(lenderProfileProvider).user;
    if (user == null) return;
    _firstNameCtrl.text = user.firstName;
    _lastNameCtrl.text = user.lastName;
    _middleNameCtrl.text = user.middleName ?? '';
    _gender = _normalizeOption(user.gender, _genderOptions, aliases: {
      'other': 'Prefer not to say',
      'prefer_not_to_say': 'Prefer not to say',
    });
    _civilStatus = _normalizeOption(user.civilStatus, _civilOptions);
    // 00128: employment / income / source of funds are declared per loan now,
    // not stored or edited on the lender profile.
    _dob = user.dateOfBirth;
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 6570)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.lenderBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(
        () => _dobError = _dob == null ? 'Date of birth is required' : null);
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) return;

    final payload = <String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      if (_middleNameCtrl.text.trim().isNotEmpty)
        'middle_name': _middleNameCtrl.text.trim(),
      // Ang email ay HIWALAY na screen ngayon (`LenderEditEmailScreen`) — hindi
      // na kasama sa personal information payload.
      'lender_profile': {
        'gender': _toDbEnum(_gender!),
        'civil_status': _toDbEnum(_civilStatus!),
        'dob': DateFormat('yyyy-MM-dd').format(_dob!),
      },
    };

    final ok =
        await ref.read(lenderProfileProvider.notifier).updateProfile(payload);

    if (!mounted) return;
    if (ok) {
      await showDialog(
        context: context,
        builder: (_) => const SuccessDialog(
          title: 'Profile Updated',
          message: 'Your personal information has been updated successfully.',
        ),
      );
      if (mounted) context.go(RouteConstants.lenderProfile);
    } else {
      final err = ref.read(lenderProfileProvider).error;
      await showErrorDialog(
        context,
        message: err ?? 'Failed to update profile. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderProfileProvider);

    if (!_initialized && state.user != null) {
      _initFromState();
    }

    return _lenderEditScaffold(
      title: 'Edit Personal Information',
      loading: state.isLoading,
      bottomBar: _lenderPinnedActions(
        context: context,
        saving: state.isSaving,
        onSave: _submit,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lenderFormSection(
              'Personal Information',
              Icons.person_outline,
              [
                AppTextField(
                  label: 'First Name',
                  controller: _firstNameCtrl,
                  maxLength: 100,
                  validator: _requiredValidator('First name'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Middle Name (Optional)',
                  controller: _middleNameCtrl,
                  maxLength: 2,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z.]')),
                    LengthLimitingTextInputFormatter(2),
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    if (!RegExp(r'^[a-zA-Z.]{1,2}$').hasMatch(v)) {
                      return 'Max 2 letters or "." only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Last Name',
                  controller: _lastNameCtrl,
                  maxLength: 100,
                  validator: _requiredValidator('Last name'),
                ),
                const SizedBox(height: 12),
                _buildDropdownField(
                  label: 'Gender',
                  value: _gender,
                  items: _genderOptions,
                  validator: (v) => v == null ? 'Gender is required' : null,
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 12),
                _buildDropdownField(
                  label: 'Civil Status',
                  value: _civilStatus,
                  items: _civilOptions,
                  validator: (v) =>
                      v == null ? 'Civil status is required' : null,
                  onChanged: (v) => setState(() => _civilStatus = v),
                ),
                const SizedBox(height: 12),
                _buildDateField(),
                if (_dobError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      _dobError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _requiredValidator(String label) {
    return (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required String? Function(String?) validator,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lenderBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDateField() {
    final fmt = DateFormat('MMMM d, yyyy');
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: _dobError != null ? AppColors.error : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Date of Birth *',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dob != null ? fmt.format(_dob!) : 'Select date',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dob != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontWeight:
                          _dob != null ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) Residence Address
// ─────────────────────────────────────────────────────────────────────────────
class LenderEditAddressScreen extends ConsumerStatefulWidget {
  const LenderEditAddressScreen({super.key});

  @override
  ConsumerState<LenderEditAddressScreen> createState() =>
      _LenderEditAddressScreenState();
}

class _LenderEditAddressScreenState
    extends ConsumerState<LenderEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  void _initFromState() {
    if (_initialized) return;
    final user = ref.read(lenderProfileProvider).user;
    if (user == null) return;
    _streetCtrl.text = user.streetAddress ?? '';
    _barangayCtrl.text = user.barangay ?? '';
    _cityCtrl.text = user.city ?? '';
    _provinceCtrl.text = user.province ?? '';
    _zipCtrl.text = user.zipCode ?? '';
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Flat na address fields — ito ang inaasahan ng `users-manage`
    // (`addresses` table upsert ng primary home address).
    final payload = <String, dynamic>{
      'street_address': _streetCtrl.text.trim(),
      'barangay': _barangayCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'province': _provinceCtrl.text.trim(),
      'zip_code': _zipCtrl.text.trim(),
    };

    final ok =
        await ref.read(lenderProfileProvider.notifier).updateProfile(payload);

    if (!mounted) return;
    if (ok) {
      await showDialog(
        context: context,
        builder: (_) => const SuccessDialog(
          title: 'Address Updated',
          message: 'Your residence address has been updated successfully.',
        ),
      );
      if (mounted) context.go(RouteConstants.lenderProfile);
    } else {
      final err = ref.read(lenderProfileProvider).error;
      await showErrorDialog(
        context,
        message: err ?? 'Failed to update address. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderProfileProvider);

    if (!_initialized && state.user != null) {
      _initFromState();
    }

    return _lenderEditScaffold(
      title: 'Edit Residence Address',
      loading: state.isLoading,
      bottomBar: _lenderPinnedActions(
        context: context,
        saving: state.isSaving,
        onSave: _submit,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lenderFormSection(
              'Residence Address',
              Icons.location_on_outlined,
              [
                AppTextField(
                  label: 'Street Address',
                  controller: _streetCtrl,
                  maxLength: 100,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Barangay',
                  controller: _barangayCtrl,
                  maxLength: 100,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'City / Municipality',
                  controller: _cityCtrl,
                  maxLength: 100,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Province',
                  controller: _provinceCtrl,
                  maxLength: 100,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'ZIP Code',
                  controller: _zipCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) Email Address
// ─────────────────────────────────────────────────────────────────────────────
class LenderEditEmailScreen extends ConsumerStatefulWidget {
  const LenderEditEmailScreen({super.key});

  @override
  ConsumerState<LenderEditEmailScreen> createState() =>
      _LenderEditEmailScreenState();
}

class _LenderEditEmailScreenState extends ConsumerState<LenderEditEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromState());
  }

  void _initFromState() {
    if (_initialized) return;
    final user = ref.read(lenderProfileProvider).user;
    if (user == null) return;
    // `${phone}@jireta.temp` = internal GoTrue credential lang ng phone login
    // (hindi ito totoong email) — blangko ang ipinapakita.
    final prefilledEmail = (user.email ?? '').trim();
    _emailCtrl.text = prefilledEmail.toLowerCase().endsWith('@jireta.temp')
        ? ''
        : prefilledEmail;
    _initialized = true;
    setState(() {});
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Opsyonal (phone ang pangunahing login ng lender), pero kapag may nilagay,
  /// dapat wastong email format — kapareho ng pinapatupad ng `users-manage`
  /// (validateEmail) para hindi tumalbog ang save.
  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : 'Enter a valid email address';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Laging ipinapadala — blangko = alisin ang email (pinapayagan ito ng
    // users-manage para sa lender; phone naman ang tunay na login).
    final ok = await ref.read(lenderProfileProvider.notifier).updateProfile({
      'email': _emailCtrl.text.trim().toLowerCase(),
    });

    if (!mounted) return;
    if (ok) {
      await showDialog(
        context: context,
        builder: (_) => const SuccessDialog(
          title: 'Email Updated',
          message: 'Your email address has been updated successfully.',
        ),
      );
      if (mounted) context.go(RouteConstants.lenderProfile);
    } else {
      final err = ref.read(lenderProfileProvider).error;
      await showErrorDialog(
        context,
        message: err ?? 'Failed to update email. Please try again.',
      );
    }
  }

  /// Walang white card: ang email icon ay nasa TAAS ng screen; ang "Email"
  /// text (sa taas ng field) at ang naka-center na form field naman ay nasa
  /// GITNA ng natitirang espasyo.
  Widget _buildEmailContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        // Email icon — nasa TAAS ng screen.
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.lenderBlue.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.email_outlined,
              size: 28, color: AppColors.lenderBlue),
        ),
        // Text + form field — naka-center sa natitirang espasyo (gitna ng app).
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Text sa TAAS ng form field.
              const Text(
                'Email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              // Naka-center na form field (may hangganan ang lapad, hindi buong
              // screen).
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AppTextField(
                  label: '',
                  hint: 'Enter your email address',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 150,
                  validator: _validateEmail,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderProfileProvider);

    if (!_initialized && state.user != null) {
      _initFromState();
    }

    return _lenderEditScaffold(
      title: 'Edit Email',
      loading: state.isLoading,
      // Hindi scrollable: pinupuno ng content ang espasyo para umabot sa ibaba
      // (sa ibabaw ng naka-pin na button) ang email field.
      scrollable: false,
      bottomBar: _lenderPinnedActions(
        context: context,
        saving: state.isSaving,
        onSave: _submit,
      ),
      child: Form(
        key: _formKey,
        child: _buildEmailContent(),
      ),
    );
  }
}
