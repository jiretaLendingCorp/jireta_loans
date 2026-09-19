// lib/presentation/shared/widgets/profile/personal_details_dialog.dart
//
// Mandatory onboarding step para sa mga bagong gawang Head Manager / Employee
// account: bago sila makarating sa dashboard, kailangan muna nilang punan ang
// personal details na lumalabas sa Profile → Personal Details.
//
// NON-DISMISSIBLE: walang close button at hindi maisasara sa labas — kailangang
// ma-save ang impormasyon bago magpatuloy. May "Log out" option para sa user
// na ayaw mag-fill out.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../data/models/user_model.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../providers/auth_state_provider.dart';
import '../dialogs/success_dialog.dart';
import '../philippines_address_field.dart';

/// Tinatawag sa dashboard entry ng head manager / employee: kung hindi pa
/// nakukumpleto ng account ang kanilang personal details, ipakita ang REQUIRED
/// dialog bago sila makapagpatuloy sa dashboard.
///
/// DASHBOARD-ONLY gate: huwag itong tawagin sa ForceChangePasswordScreen.
/// Flow: login → /force-change-password (password lang) → logout → login
/// ulit → dashboard → dito lang lalabas ang dialog.
Future<void> runStaffProfileOnboarding(
    BuildContext context, WidgetRef ref) async {
  final authState = ref.read(authStateProvider);
  final role = authState.role;
  final isStaff = role == AppConstants.roleHeadManager ||
      role == AppConstants.roleEmployee;
  if (!isStaff) return;
  // Kapag naka-force-change-password pa, sa /force-change-password dapat
  // ang user — hindi dito sa dashboard magpapakita ng dialog.
  if (authState.forcePasswordChange) return;
  final userId = authState.user?.id ?? (await SecureStorage.getUserId() ?? '');
  if (userId.isEmpty) return;
  if (await SecureStorage.isProfileOnboardingDone(userId)) return;
  if (!context.mounted) return;
  await PersonalDetailsDialog.show(context);
}

class PersonalDetailsDialog extends ConsumerStatefulWidget {
  const PersonalDetailsDialog({super.key});

  /// Pinapakita ang dialog at nagbabalik ng `true` kapag na-save na ang mga
  /// personal details. Hindi ito maisasara nang hindi naka-save (maliban sa
  /// "Log out" na option).
  static Future<bool> show(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PersonalDetailsDialog(),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<PersonalDetailsDialog> createState() =>
      _PersonalDetailsDialogState();
}

class _PersonalDetailsDialogState extends ConsumerState<PersonalDetailsDialog> {
  static const _accent = AppColors.deepNavy;
  static const _genders = ['male', 'female'];
  static const _civilStatuses = [
    'single',
    'married',
    'widowed',
    'separated',
  ];

  final _phoneCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  // Keys ng bawat field — para ma-scroll pabalik sa pinaka-unang field na may
  // red validation error kapag pinindot ang Save.
  final _firstKey = GlobalKey();
  final _lastKey = GlobalKey();
  final _phoneKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _civilKey = GlobalKey();
  final _dobKey = GlobalKey();
  final _addressKey = GlobalKey<PhilippinesAddressFieldState>();

  String _email = '';
  String? _gender;
  String? _civilStatus;
  DateTime? _dob;

  bool _loading = true;
  bool _saving = false;
  bool _loggingOut = false;
  String? _loadError;
  String? _saveError;

  // Validation errors sa bawat field — inline silang ipinapakita sa card ng
  // kaukulang input, at awtomatikong nawawala pagkalipas ng 3 segundo.
  bool _showErrors = false;
  String? _firstError;
  String? _lastError;
  String? _phoneError;
  String? _genderError;
  String? _civilError;
  String? _dobError;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadProfile);
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _scrollCtrl.dispose();
    _phoneCtrl.dispose();
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    UserModel? user;
    String? error;
    try {
      user = await sl<UserRemoteDataSource>().getProfile();
    } catch (e) {
      // Hindi hadlang ang load failure — ang naka-cache na auth user ang
      // gagamitin para makapag-fill in pa rin ang user; mananatili ang maliit
      // na notice sa itaas ng form.
      error = ErrorHandler.handle(e).message;
      user = ref.read(authStateProvider).user;
    }
    if (!mounted) return;
    setState(() {
      if (user != null) _applyProfile(user);
      _loading = false;
      _loadError = error;
    });
  }

  void _applyProfile(UserModel user) {
    // Editable na ang pangalan dito (dati read-only na full name) — para
    // maitama ng bagong head manager / employee ang kanilang pangalan
    // bago magpatuloy sa dashboard.
    //
    // BLANKO ang dummy placeholders na nilalagay pag-create ng account
    // (e.g. First="Head", Last="Manager") — hindi sila pre-filled, kaya
    // required na itype ng user ang tunay na pangalan.
    _firstCtrl.text = _cleanName(user.firstName);
    _middleCtrl.text = _cleanName(user.middleName);
    _lastCtrl.text = _cleanName(user.lastName);
    _email = user.email ?? '';
    _phoneCtrl.text = user.phoneNumber ?? '';
    _gender = _pick(_genders, user.gender);
    _civilStatus = _pick(_civilStatuses, user.civilStatus);
    _dob = user.dateOfBirth;
  }

  /// Dummy placeholders mula sa account creation (hindi tunay na pangalan).
  /// Kapag ganito ang naka-save, ibablanko sa dialog para mapilitang mag-type
  /// ng tunay na pangalan ang user.
  static const _namePlaceholders = {
    'head',
    'manager',
    'head manager',
    'headmanager',
    'admin',
    'administrator',
    'employee',
    'staff',
    'test',
    'user',
    'new',
    'unknown',
    'n/a',
    'na',
    '-',
  };

  String _cleanName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '';
    if (_namePlaceholders.contains(v.toLowerCase())) return '';
    return v;
  }

  /// Ibinalik ang normalized value kapag kasama ito sa listahan ng dropdown
  /// (kung hindi, `null` — kailangan itong piliin muli ng user).
  String? _pick(List<String> allowed, String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return allowed.contains(v) ? v : null;
  }

  /// Kinukwenta ang kasalukuyang validation errors para sa inline display.
  void _computeErrors() {
    _firstError = _firstCtrl.text.trim().isEmpty
        ? 'First name is required'
        : null;
    _lastError =
        _lastCtrl.text.trim().isEmpty ? 'Last name is required' : null;
    _phoneError = AppValidators.phone(_phoneCtrl.text.trim());
    _genderError =
        (_gender == null || _gender!.isEmpty) ? 'Gender is required' : null;
    _civilError = (_civilStatus == null || _civilStatus!.isEmpty)
        ? 'Civil status is required'
        : null;
    _dobError = _dob == null ? 'Date of birth is required' : null;
  }

  /// Ipinapakita ang inline errors at, pagkalipas ng 3 segundo, awtomatikong
  /// itinatago ang mga ito (kapareho ng auto-hide na gawi sa ibang forms ng app).
  void _flashErrors() {
    _errorTimer?.cancel();
    setState(() => _showErrors = true);
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showErrors = false);
      // Tinatago rin ang sariling inline errors ng address field.
      _addressKey.currentState?.clearErrors();
    });
  }

  /// Ini-scroll pabalik ang form sa PINAKA-UNANG field na may red validation
  /// error, para agad itong makita ng user imbes na nakatago sa ibaba.
  void _scrollToFirstError(bool addressOk) {
    final GlobalKey? key = _firstError != null
        ? _firstKey
        : _lastError != null
            ? _lastKey
            : _phoneError != null
                ? _phoneKey
        : _genderError != null
            ? _genderKey
            : _civilError != null
                ? _civilKey
                : _dobError != null
                    ? _dobKey
                    : (!addressOk ? _addressKey : null);
    if (key == null) return;
    // Post-frame — naka-layout na ang bagong error text bago i-scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      // Direktang kalkulahin ang offset ng unang field na may error at
      // i-animate pabalik doon (leading edge sa itaas ng viewport).
      final viewport = RenderAbstractViewport.of(box);
      final target = viewport.getOffsetToReveal(box, 0.0).offset;
      final position = _scrollCtrl.position;
      _scrollCtrl.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saveError = null;
      _computeErrors();
    });

    // Ipakita agad ang inline errors ng address field (Region/Province/City/
    // Barangay/Street) bago kunin ang resulta nito.
    final addressOk = _addressKey.currentState?.validate() ?? false;
    final hasFieldErrors = _firstError != null ||
        _lastError != null ||
        _phoneError != null ||
        _genderError != null ||
        _civilError != null ||
        _dobError != null;
    if (hasFieldErrors || !addressOk) {
      _flashErrors();
      _scrollToFirstError(addressOk);
      return;
    }
    final dob = _dob!;
    _errorTimer?.cancel();

    setState(() => _saving = true);
    final addr = _addressKey.currentState;
    final payload = <String, dynamic>{
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'middle_name': _middleCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'employee_profile': {
        'gender': _gender,
        'civil_status': _civilStatus,
        'date_of_birth': dob.toIso8601String().substring(0, 10),
      },
      if (addr != null) ...{
        'street_address': addr.street,
        'barangay': addr.barangay,
        'city': addr.city,
        'province': addr.province,
      },
    };

    try {
      await sl<UserRemoteDataSource>().updateProfile(payload);
      // Markahan na kumpleto na ang onboarding para sa account na ito — hindi
      // na muling lalabas ang dialog sa mga susunod na login.
      final userId = ref.read(authStateProvider).user?.id ??
          (await SecureStorage.getUserId() ?? '');
      await SecureStorage.markProfileOnboardingDone(userId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = ErrorHandler.handle(e).message;
      });
    }
  }

  /// Ayaw i-fill out ng user ang form — confirm modal muna, tapos maliit na
  /// loading modal, tapos "Successfully Logged Out" modal, tapos login page.
  ///
  /// HINDI minamarkahan na "done" ang onboarding, kaya lalabas pa rin ang dialog
  /// sa susunod nilang login.
  Future<void> _logout() async {
    if (_saving || _loggingOut) return;

    // (1) Confirm modal muna — "Are you sure you want to logout?".
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);

    // Kukunin bago pa isara ang dialog para may stable na context para sa
    // success modal (mawawala na kasi ang State context nito pagka-pop).
    final rootNav = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);

    // Hold the auto-redirect while the modals are up.
    AppConstants.suppressLogoutRedirect = true;

    // (2) Maliit na loading modal.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Text('Logging out…',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ));

    try {
      await ref.read(authProvider.notifier).logout();
    } catch (_) {
      // Tuloy pa rin — naka-clear na ang session.
    } finally {
      AppConstants.suppressLogoutRedirect = false;
    }

    if (!mounted) return;
    // (3) Isara ang loading modal, tapos ang personal details dialog na ito.
    rootNav.pop(); // loading
    rootNav.pop(false); // ang dialog na ito

    // (4) Success modal — steady 2s, tapos diretso sa login page.
    await SuccessDialog.showAutoDismiss(
      rootNav.context,
      title: 'Successfully Logged Out',
      message: 'You have been logged out successfully.',
    );
    router.go(RouteConstants.webLogin);
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.deepNavy,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    // Blocking step: hindi pwedeng i-back o i-dismiss bago ma-save (o mag-log out).
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 24,
        shadowColor: AppColors.deepNavy.withValues(alpha: 0.30),
        // Kapareho ng design language ng web login / change password page.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFECEEF3)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            child: _loading ? _buildLoading() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 180,
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 2, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadError != null) ...[
                  _banner(
                    'We could not load your saved details. Please double-check '
                    'the information below.',
                    AppColors.warning,
                  ),
                  const SizedBox(height: 14),
                ],
                const _FieldLabel('First Name'),
                const SizedBox(height: 8),
                TextFormField(
                  key: _firstKey,
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  style: const TextStyle(fontSize: 14),
                  decoration: _dec('Enter first name',
                      errorText: _fieldError(_firstError)),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Middle Name (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _middleCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  style: const TextStyle(fontSize: 14),
                  decoration: _dec('Enter middle name'),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Last Name'),
                const SizedBox(height: 8),
                TextFormField(
                  key: _lastKey,
                  controller: _lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  style: const TextStyle(fontSize: 14),
                  decoration: _dec('Enter last name',
                      errorText: _fieldError(_lastError)),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Email Address'),
                const SizedBox(height: 8),
                _readOnlyRow(_email.isEmpty ? '—' : _email),
                const SizedBox(height: 18),
                // Validation errors ay INLINE sa ilalim ng kaukulang field
                // (katulad ng login card) at nawawala pagkatapos ng 3s.
                const _FieldLabel('Phone Number'),
                const SizedBox(height: 8),
                TextFormField(
                  key: _phoneKey,
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  style: const TextStyle(fontSize: 14),
                  decoration: _dec('09XXXXXXXXX',
                      errorText: _fieldError(_phoneError)),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Gender'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: _genderKey,
                  initialValue: _gender,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14),
                  decoration:
                      _dec('Select gender', errorText: _fieldError(_genderError)),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Civil Status'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: _civilKey,
                  initialValue: _civilStatus,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: _dec('Select civil status',
                      errorText: _fieldError(_civilError)),
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('Single')),
                    DropdownMenuItem(value: 'married', child: Text('Married')),
                    DropdownMenuItem(value: 'widowed', child: Text('Widowed')),
                    DropdownMenuItem(
                        value: 'separated', child: Text('Separated')),
                  ],
                  onChanged: (v) => setState(() => _civilStatus = v),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Date of Birth'),
                const SizedBox(height: 8),
                InkWell(
                  key: _dobKey,
                  onTap: _saving ? null : _pickDob,
                  child: InputDecorator(
                    isEmpty: _dob == null,
                    decoration: _dec('Select date of birth',
                        errorText: _fieldError(_dobError)).copyWith(
                      suffixIcon: const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.textSecondary),
                    ),
                    child: Text(
                      _dob != null ? AppFormatters.date(_dob!) : '',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _FieldLabel('Address'),
                const SizedBox(height: 8),
                PhilippinesAddressField(key: _addressKey),
              ],
            ),
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 14),
          _banner(_saveError!, AppColors.error),
        ],
        const SizedBox(height: 20),
        // Log out + Save & Continue (pareho ang lapad) — kapareho ng premium
        // gradient CTA at outlined button ng login page.
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: (_saving || _loggingOut) ? null : _logout,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.deepNavy,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: const BorderSide(
                        color: Color(0xFFE4E7EE), width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Log out',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _gradientCta(),
            ),
          ],
        ),
      ],
    );
  }

  /// Premium gradient na "Save & Continue" — kapareho ng login CTA.
  Widget _gradientCta() {
    final disabled = _saving || _loggingOut;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: disabled
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D1B2A),
                  Color(0xFF1E3A5F),
                  Color(0xFF0D1B2A),
                ],
              ),
        color: disabled ? AppColors.deepNavy.withValues(alpha: 0.42) : null,
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 6)),
              ],
      ),
      child: ElevatedButton(
        onPressed: disabled ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
          shadowColor: Colors.transparent,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('Save & Continue'),
      ),
    );
  }

  /// Maikling paliwanag sa itaas ng form — walang icon, walang heading, at
  /// compact ang agwat.
  Widget _buildHeader() {
    return const Text(
      'Fill in your personal details to continue.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// Read-only na display ng Email — kaparehong hugis ng input.
  Widget _readOnlyRow(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EE)),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary),
      ),
    );
  }

  Widget _banner(String message, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Ibinalik ang error message kapag aktibo ang validation display, kung
  /// hindi ay `null` — dito naka-base ang inline na pagpapakita/tago ng error.
  String? _fieldError(String? message) =>
      _showErrors && message != null ? message : null;

  /// Input style ng login card: light fill, rounded 12, soft border, navy focus.
  InputDecoration _dec(String hint, {String? errorText}) {
    final hasError = errorText != null;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontSize: 13.5,
          color: AppColors.textTertiary.withValues(alpha: 0.75)),
      counterText: '',
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      errorText: errorText,
      errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.error),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: hasError ? AppColors.error : const Color(0xFFE4E7EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: hasError ? AppColors.error : const Color(0xFFE4E7EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: hasError ? AppColors.error : AppColors.deepNavy,
            width: 1.4),
      ),
    );
  }
}

/// Maliit na label sa itaas ng bawat input — kapareho ng login card.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
    );
  }
}
