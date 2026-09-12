// lib/presentation/shared/widgets/account_paused_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/account_status_provider.dart';
import '../providers/auth_state_provider.dart';

/// Binubuksan ang phone dialer para sa office support number, para hindi na
/// kailangang hanapin pa ng lender ang numero sa labas ng app.
Future<void> _callSupport() async {
  final uri = Uri.parse('tel:${AppConstants.supportPhone}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Global na blocking modal para sa mga account na na-pause ng escalation
/// rule (00152): pangalawa nang natapos ang loan term ng lender na may
/// natitirang utang.
///
/// Nakapatong ito sa LAHAT ng route (tingnan ang `app.dart` builder), kaya
/// pagka-login ay agad itong lumalabas at hindi makakausad ang lender sa app.
/// Hindi ito nadidismiss sa tap sa labas — kailangan ng staff action
/// (unpause) o logout.
///
/// Kapag in-unpause ng Head Manager/Employee ang account, nagre-refresh ang
/// [accountStatusProvider] (Realtime sa `users`) at awtomatikong nawawala
/// ang modal kahit bukas pa ang app.
class AccountPausedOverlay extends ConsumerWidget {
  final Widget child;

  const AccountPausedOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(
      authStateProvider.select((s) => s.isAuthenticated ? s.role : null),
    );
    final isPaused = ref.watch(isAccountPausedProvider);

    // Ang pause ay para sa borrower (lender) accounts lang.
    final shouldBlock = isPaused && role == RoleConstants.lender;

    return Stack(
      children: [
        child,
        if (shouldBlock)
          const Positioned.fill(
            child: Stack(
              children: [
                ModalBarrier(
                  dismissible: false,
                  // Fully opaque: hindi dapat makita (o maabot) ng paused na
                  // lender ang kahit anong screen sa likod — ito lang ang UI.
                  color: Color(0xFF0B1220),
                ),
                Center(child: _AccountPausedCard()),
              ],
            ),
          ),
      ],
    );
  }
}

class _AccountPausedCard extends ConsumerWidget {
  const _AccountPausedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxHeight = MediaQuery.of(context).size.height;
    final isLoggingOut = ref.watch(
      authStateProvider.select((s) => s.isLoggingOut),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: maxHeight * 0.85,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    decoration: const BoxDecoration(
                      color: AppColors.deepNavy,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            color: AppColors.gold, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Account Paused',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your account has been paused',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'A loan term of yours ended with an unpaid balance for the '
                          'second time. A 20% penalty has been added to that loan, and '
                          'your account is now paused.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.zero,
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.support_agent_rounded,
                                      color: AppColors.warning, size: 18),
                                  SizedBox(width: 8),
                                  // Expanded para hindi mag-overflow sa makitid
                                  // na screen kapag mahaba ang label.
                                  Expanded(
                                    child: Text(
                                      'Contact Our Services',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please contact our office or message our services '
                                'team so we can review your balance and reactivate '
                                'your account. Once reactivated, you can use the app '
                                'and apply for a new loan again.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _callSupport,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.zero,
                                    border: Border.all(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.call_rounded,
                                          size: 16, color: AppColors.warning),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Call us: ${AppConstants.supportPhone}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.deepNavy,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Tap to call',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'You may also settle your outstanding balance with the '
                          'office — our staff will reactivate your account after '
                          'the review.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Isang button lang — ang paused na account ay
                        // makakaalis lang sa "Log Out" (ang pag-unpause ay
                        // staff action; awtomatikong nawawala ang modal sa
                        // Realtime kapag in-unpause ng HM/Employee).
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: isLoggingOut
                                ? null
                                : () =>
                                    ref.read(authStateProvider.notifier).logout(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.deepNavy),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: isLoggingOut
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text(
                                    'Log Out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.deepNavy,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
