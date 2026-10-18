// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rive/rive.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/extensions/num_extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/account_upgrade_document_model.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../../data/models/loan_schedule_model.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../../shared/widgets/layout/mobile_refresh.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../../data/models/payment_model.dart';
import '../../account_upgrade/providers/lender_account_upgrade_provider.dart';
import '../../collections/providers/lender_collection_provider.dart';
import '../../loans/providers/lender_loan_provider.dart';
import '../../payments/providers/lender_payment_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_dashboard_provider.dart';
import 'widgets/lender_promo_carousel.dart';
import 'widgets/lender_welcome_group.dart';

final lenderAmountObscuredProvider =
    StateNotifierProvider<LenderAmountObscuredNotifier, bool>(
        (ref) => LenderAmountObscuredNotifier());

class LenderAmountObscuredNotifier extends StateNotifier<bool> {
  static const _key = 'lender_amount_obscured';
  LenderAmountObscuredNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key) ?? false;
    if (mounted) state = v;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

/// `true` kapag may nakasulat nang pangalan sa file ang lender — senyales na
/// kumpleto (o umiiral) na ang account niya.
///
/// Hiwalay na function ito (hindi nakabaon sa widget) para masubukan nang
/// direkta — ito ang pumipigil sa paglabas ng one-time Terms & Conditions +
/// "Fill In Information" sa isang account na may record na, lalo na kapag ang
/// login ay dumaan sa MPIN (kung saan stub lang ang user ng auth state).
bool lenderHasNameOnFile(UserModel user) =>
    user.firstName.trim().isNotEmpty && user.lastName.trim().isNotEmpty;

/// `true` kapag may account-upgrade record na ang lender (kahit wala pang
/// pangalan) — nagsasabi rin ito na may account na siya.
bool lenderHasUpgradeRecord(UserModel user) {
  final status = (user.accountUpgradeStatus ?? '').trim().toLowerCase();
  return const {
    'submitted',
    'under_review',
    'verified',
    'rejected',
  }.contains(status);
}

/// `true` kapag may existing nang lender account — hindi na dapat makita ang
/// one-time Terms & Conditions / "Fill In Information"; deretso na sa Home.
bool lenderHasExistingAccount(UserModel? user) =>
    user != null && (lenderHasNameOnFile(user) || lenderHasUpgradeRecord(user));

class LenderDashboardScreen extends ConsumerStatefulWidget {
  const LenderDashboardScreen({super.key});

  @override
  ConsumerState<LenderDashboardScreen> createState() =>
      _LenderDashboardScreenState();
}

class _LenderDashboardScreenState extends ConsumerState<LenderDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  static const _riderNavItems = [
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

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // Terms & Conditions appear exactly once per lender account, right after
    // login on the dashboard.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTermsOnce());
  }

  /// Opens the full-screen Terms & Conditions page the first time each lender
  /// account logs in on the device. Same full-screen design as the original
  /// pre-login terms screen — it covers the whole screen. The decision is
  /// strictly per-account, so EVERY new lender account sees it on login even
  /// on a shared device where another account already accepted.
  Future<void> _maybeShowTermsOnce() async {
    if (!mounted) return;
    // Wait for the real logged-in user id — deciding before auth resolves
    // (empty id) is what used to hide the prompt for new accounts.
    var userId = ref.read(authStateProvider).user?.id ?? '';
    for (var i = 0; i < 50 && mounted && userId.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      userId = ref.read(authStateProvider).user?.id ?? '';
    }
    if (!mounted || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final perAccountKey = '${AppConstants.termsAcceptedKey}_$userId';
    if (prefs.getBool(perAccountKey) ?? false) return;

    // ── SERVER ang basehan, hindi lang ang device-local flag ────────────────
    // Ang `users.terms_accepted_at` (isinusulat ng `?fn=terms-accept` sa unang
    // pag-accept) ang tunay na katibayan ng one-time acceptance: kapag mayroon
    // na ito, HINDI na muling ipapakita ang Terms & Conditions at ang "Fill In
    // Information" — kahit bagong install, bagong device, o dumaan sa MPIN
    // (kung saan STUB lang ang user ng auth state: walang pangalan).
    final authUser = ref.read(authStateProvider).user;
    final profile = await _loadLenderProfile(userId);
    if (!mounted) return;

    if (profile?.termsAcceptedAt != null) {
      // I-sync ang local flag para hindi na kailangang magtanong sa server sa
      // susunod na pagbukas ng app.
      await prefs.setBool(perAccountKey, true);
      return;
    }

    // ── Existing account (may pangalan na sa file o may upgrade record) ─────
    // "Nagawa na niya ito noong unang bukas ng account niya" — hindi na dapat
    // ulitin. Profile muna (totoong datos mula sa server), tapos ang nasa auth
    // state bilang karagdagang senyales.
    if (lenderHasExistingAccount(profile) ||
        lenderHasExistingAccount(authUser)) {
      return;
    }

    // ── Hindi ma-confirm (offline / bigo ang profile fetch) ─────────────────
    // Huwag nang mang-istorbo: mas mabuting huwag ipakita ang one-time Terms
    // kaysa ipakita itong muli sa isang lumang account. Ang bagong account
    // naman ay dadaan pa rin dito sa susunod na pagbukas (wala pang lokal na
    // flag at wala pang `terms_accepted_at`).
    if (profile == null) return;

    if (!mounted || !context.mounted) return;
    context.push(RouteConstants.terms);
  }

  /// Kinukuha ang TOTOONG profile ng lender MULA SA SERVER.
  ///
  /// Dati, ang `lenderProfileProvider` (AutoDispose) ang hinihintay dito — at
  /// iyon ang bug: ang `ref.read` sa isang autoDispose provider na walang
  /// listener ay maaaring malinis agad, kaya `null` ang nakikita ng desisyon at
  /// BUMABALIK ang Terms & Conditions para sa isang existing account. Ang
  /// direktang fetch ay deterministic: isang tawag, isang kasagutan.
  ///
  /// `null` kapag hindi ito nag-load (hal. offline) o kapag iba ang account na
  /// nasa provider — sa mga ganong kaso, hindi na ipinapakita ang one-time
  /// Terms (tingnan ang tawag sa itaas).
  Future<UserModel?> _loadLenderProfile(String userId) async {
    try {
      final profile = await sl<UserRemoteDataSource>().getProfile();
      if (profile.id == userId) return profile;
    } catch (e) {
      if (kDebugMode) debugPrint('[terms] profile fetch failed: $e');
    }
    final cached = ref.read(lenderProfileProvider).user;
    return (cached != null && cached.id == userId) ? cached : null;
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  static const _inReviewStatuses = {
    'pending',
    'under_review',
    'ci_required',
    'ci_assigned',
    'ci_completed',
    'ci_approved',
  };

  LoanModel? _approvedUnreleased(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' && loan.disbursedAt == null) {
        return loan;
      }
    }
    return null;
  }

  LoanModel? _inReviewLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if (_inReviewStatuses.contains(loan.status)) {
        return loan;
      }
    }
    return null;
  }

  void _handlePromoTap(BuildContext context, int index, LoanModel? activeLoan) {
    switch (index) {
      case 1:
        // Cash on Delivery promo — diretso sa payment kung may active loan.
        if (activeLoan != null) {
          context.push(
            RouteConstants.lenderPaymentMethod,
            extra: {'loan_id': activeLoan.id},
          );
        } else {
          context.push(RouteConstants.lenderLoans);
        }
        break;
      default:
        context.push(RouteConstants.lenderLoans);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDashboardProvider);
    final loanState = ref.watch(lenderLoanProvider);
    final profileState = ref.watch(lenderProfileProvider);
    // Recent Activity sources — payments (Transaction) at collections (rider /
    // office pickup requests) kasama ng loans. Hindi hinihintay ang pag-load
    // nila: agad lumalabas ang Home, pagkatapos lang dumadagdag ang aktibidad.
    final paymentState = ref.watch(lenderPaymentProvider);
    final collectionState = ref.watch(lenderCollectionProvider);
    // Account upgrade (submission / verification / rejection) ay kasama rin sa
    // Recent Activity — kung hindi, "No recent activity yet" pa rin ang
    // lumalabas sa lender na kaka-submit lang ng upgrade at wala pang loan.
    final upgradeStatus =
        ref.watch(lenderAccountUpgradeProvider).accountUpgradeStatus;
    final collectionItems = <Map<String, dynamic>>[];
    final collectionRaw = collectionState.valueOrNull;
    if (collectionRaw != null) {
      final list = (collectionRaw['items'] as List?) ??
          (collectionRaw['data'] as List?) ??
          const [];
      for (final item in list) {
        if (item is Map) {
          collectionItems.add(Map<String, dynamic>.from(item));
        }
      }
    }
    final activeLoan = loanState.activeLoan;
    final approvedLoan = _approvedUnreleased(loanState.loans);
    final inReviewLoan = _inReviewLoan(loanState.loans);
    // Keep showing the loader until loans are resolved so the "no active loan"
    // layout (balance card / overview) never flashes before the active loan.
    final showLoanLoader = loanState.isLoading && loanState.loans.isEmpty;

    // ── Mga section ng dashboard — ISANG pinagmumulan lang ────────────────
    // Dito lang binubuo ang bawat piraso, at pareho ang listahang iyon para sa
    // mobile at desktop layout: ang tanging pinag-iba ay ang PAGKAKA-AYOS.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final welcome = _WelcomeBanner(
      kpi: state.kpi,
      firstName: profileState.user?.firstName,
      showBalance: activeLoan == null,
      // Sa desktop, nakadikit sa KALIWANG gilid ang Rive, at ang fox mismo ang
      // pinaka-kaliwa — nasa KANAN nito ang greeting dialog. Sa mobile, nasa
      // kaliwa pa rin ng fox ang dialog (walang binago).
      desktop: isDesktop,
    );
    final approvedBanner = (approvedLoan != null && activeLoan == null)
        ? _ApprovedLoanBanner(loan: approvedLoan)
        : null;
    final primaryAction = activeLoan != null
        ? null
        : (inReviewLoan != null
            ? _PendingLoanCard(loan: inReviewLoan)
            : (approvedLoan == null ? const _QuickActions() : null));
    final myLoanCard = activeLoan == null
        ? null
        : Transform.translate(
            offset: const Offset(0, -14),
            child: _MyLoanCard(loan: activeLoan),
          );
    // May active loan na → walang "Apply Loan" na button sa promo banner (hindi
    // na siya maaaring mag-apply ulit).
    final promo = LenderPromoCarousel(
      hideApplyLoanCta: activeLoan != null,
      onCtaTap: (index, _) => _handlePromoTap(context, index, activeLoan),
    );
    final loansOverview =
        activeLoan == null ? _MyLoansOverview(kpi: state.kpi) : null;
    // Recent Activity renders with or without an active loan: loans + payments +
    // collections, pinakabago muna. Kaya kahit active pa lang ang loan, may
    // nakikitang aktibidad ang lender (payment, collection request, atbp.).
    final recentActivity = _RecentActivitySection(
      loans: loanState.loans,
      activeLoanId: activeLoan?.id ?? '',
      payments: paymentState.payments,
      collections: collectionItems,
      upgrade: upgradeStatus,
    );
    final errorBanner = state.error == null ? null : _ErrorBanner(state.error!);

    return MobileScaffold(
      title: 'Account',
      accentColor: AppColors.lenderBlue,
      navItems: _riderNavItems,
      // Sa desktop, nasa top bar ang refresh — hindi kayang i-drag ng mouse ang
      // pull-to-refresh. Sa mobile walang idinadagdag ito (may pull-down doon).
      appBarActions: isDesktop
          ? [
              IconButton(
                tooltip: 'Refresh',
                // Habang tumatakbo, spinner ang icon — para kitang-kita na may
                // nangyayari talaga sa bawat pindot.
                onPressed: _refreshing ? null : _onRefreshTap,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ]
          : null,
      body: state.isLoading || showLoanLoader
          ? const _LenderDashboardSkeleton()
          : MobileRefresh(
              // Silent loads: kapag hindi, magiging `isLoading = true` ang
              // dashboard sa gitna ng pull-down at mapapalitan ng skeleton ang
              // RefreshIndicator mismo — nawawala ang spinner at ang gesture.
              onRefresh: _silentRefresh,
              color: AppColors.lenderBlue,
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: isDesktop
                    ? _desktopBody(
                        welcome: welcome,
                        loan: activeLoan,
                        approvedBanner: approvedBanner,
                        primaryAction: primaryAction,
                        myLoanCard: myLoanCard,
                        promo: promo,
                        loansOverview: loansOverview,
                        recentActivity: recentActivity,
                        errorBanner: errorBanner,
                      )
                    : _mobileBody(
                        welcome: welcome,
                        approvedBanner: approvedBanner,
                        activeLoan: activeLoan,
                        primaryAction: primaryAction,
                        myLoanCard: myLoanCard,
                        promo: promo,
                        loansOverview: loansOverview,
                        recentActivity: recentActivity,
                        errorBanner: errorBanner,
                      ),
              ),
            ),
    );
  }

  /// `true` habang tumatakbo ang refresh — spinner sa Refresh button at
  /// hindi na doble-doble ang pindot.
  bool _refreshing = false;

  /// Pindot sa Refresh button (desktop top bar). May nakikitang feedback
  /// pagkatapos, kaya malinaw na gumagana ito.
  Future<void> _onRefreshTap() async {
    await _silentRefresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Refreshed'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Silent refresh para sa pull-down at sa Refresh button ng desktop top bar —
  /// hindi ito nagpapalit ng screen sa skeleton.
  ///
  /// Kailangang i-refresh ang LAHAT ng pinagmumulan ng dashboard, hindi lang
  /// ang KPI at loans: ang Recent Activity ay binubuo rin mula sa payments,
  /// collections, at account-upgrade status. Dati, hindi kasama ang payments —
  /// kaya kahit bayad na at naging "Paid" sa server, nananatiling "Payment
  /// pending" sa Recent Activity kahit pindutin ang Refresh.
  Future<void> _silentRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final paymentNotifier = ref.read(lenderPaymentProvider.notifier);
      await Future.wait([
        ref.read(lenderDashboardProvider.notifier).load(silent: true),
        ref.read(lenderLoanProvider.notifier).loadLoans(silent: true),
        paymentNotifier.loadPayments(silent: true),
        ref.read(lenderCollectionProvider.notifier).loadList(silent: true),
        ref
            .read(lenderAccountUpgradeProvider.notifier)
            .loadStatus(silent: true),
      ]);
      if (!mounted) return;
      // Manual refresh = "check now": huwag hintayin ang 3-minutong throttle ng
      // Xendit reconciliation (pending GCash → Paid).
      await paymentNotifier.syncPendingXenditPayments(force: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// MOBILE na ayos: isang column lang, nakadikit sa floating bottom nav pill.
  /// Kapareho ito ng dating layout — walang binago sa phone.
  Widget _mobileBody({
    required Widget welcome,
    required Widget? approvedBanner,
    required LoanModel? activeLoan,
    required Widget? primaryAction,
    required Widget? myLoanCard,
    required Widget promo,
    required Widget? loansOverview,
    required Widget recentActivity,
    required Widget? errorBanner,
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Eksaktong dikit sa itaas ng floating bottom nav pill.
      // [mobileBottomNavHeight] ang tama dito dahil ang context ng screen build
      // ay nasa LABAS ng body (safe area lang ang nasa MediaQuery padding doon).
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        mobileBottomNavHeight(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          welcome,
          // Walang aktibong loan → HINDI ipinapakita ang Next Payment /
          // Installment tiles (walang saysay ang "—" kapag walang babayaran).
          const SizedBox(height: 16),
          if (approvedBanner != null) ...[
            approvedBanner,
            const SizedBox(height: 20),
          ],
          if (activeLoan == null) ...[
            if (primaryAction != null) primaryAction,
            const SizedBox(height: 16),
            // Promo carousel — nasa baba ng Apply Now button.
            promo,
            // HIDDEN: "Pay with" section (Cash on Delivery / Office cards) —
            // hindi na ipinapakita sa lender Home. Nasa code pa rin ang
            // `_PayWithSection` at ang mga route (`/lender/payment-method`,
            // `/lender/pay-office`) kung ibabalik ito.
            const SizedBox(height: 20),
          ],
          if (myLoanCard != null) ...[
            myLoanCard,
            // Next Payment + Installment — nasa ILALIM ng Outstanding Balance
            // card, at nakikita rin sa MOBILE (hindi desktop-only).
            const SizedBox(height: 16),
            _LenderKpiStats(loan: activeLoan),
            const SizedBox(height: 6),
            promo,
            const SizedBox(height: 20),
          ] else if (loansOverview != null)
            loansOverview,
          recentActivity,
          // HIDDEN: live rider tracking card — hindi na ipinapakita sa lender
          // (request). Nasa code pa rin ang widget / route
          // (`/lender/live-tracking`) kung ibabalik ito.
          // Walang trailing na spacing dito — dapat dikit ang huling nilalaman
          // sa itaas ng floating bottom nav.
          if (errorBanner != null) ...[
            const SizedBox(height: 20),
            errorBanner,
          ],
        ],
      ),
    );
  }

  /// DESKTOP na ayos: dalawang column — pangunahing nilalaman (balanse, loan
  /// cards, promo) sa kaliwa, at makitid na rail (overview + Recent Activity) sa
  /// kanan. Naka-cap ang lapad (1240) at naka-center, kaya hindi nakaunat ang
  /// mobile card sa buong lapad ng monitor, at normal na desktop padding ang
  /// gamit (wala nang espasyong nakalaan para sa bottom nav).
  Widget _desktopBody({
    required Widget welcome,
    // Aktibong loan (null kapag wala) — pinagmumulan ng "Next Payment" at
    // "Installment" na stat tiles sa desktop.
    required LoanModel? loan,
    required Widget? approvedBanner,
    required Widget? primaryAction,
    required Widget? myLoanCard,
    required Widget promo,
    required Widget? loansOverview,
    required Widget recentActivity,
    required Widget? errorBanner,
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Pangunahing column ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top row ──
                    // May aktibong loan: maliit lang ang `welcome` (fox + greeting
                    // dialog), kaya sinasamantala ang bakanteng espasyo sa KANAN
                    // nito para sa Next Payment / Installment — kaya hindi na
                    // naaaksaya ang taas, at ang kanang gilid ng tiles ay pantay
                    // sa kanang gilid ng Outstanding Balance card sa ibaba.
                    if (loan != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: welcome),
                          const SizedBox(width: 20),
                          Expanded(child: _LenderKpiStats(loan: loan)),
                        ],
                      )
                    // Walang aktibong loan: ang gradient na Balance card (bahagi
                    // ng `welcome`) ang outstanding balance, at HINDI na
                    // lumalabas ang Next Payment / Installment tiles.
                    else
                      welcome,
                    const SizedBox(height: 20),
                    if (approvedBanner != null) ...[
                      approvedBanner,
                      const SizedBox(height: 20),
                    ],
                    if (primaryAction != null) ...[
                      primaryAction,
                      const SizedBox(height: 18),
                    ],
                    if (myLoanCard != null) ...[
                      myLoanCard,
                      const SizedBox(height: 6),
                    ],
                    promo,
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // ── Right rail: buod ng loan + Recent Activity ──
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loansOverview != null) ...[
                      loansOverview,
                      const SizedBox(height: 20),
                    ],
                    recentActivity,
                    if (errorBanner != null) ...[
                      const SizedBox(height: 20),
                      errorBanner,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buod ng account — DALAWANG stat tiles: ang **Next Payment** (susunod na hindi
/// pa bayad na installment kasama ang due date) at ang **Installment** (halaga
/// ng bawat bayaran). Ipinapakita lang ito kapag MAY aktibong loan — kapag
/// wala (o bayad na), hindi na ito lumalabas sa desktop o mobile.
///
/// Ayos: sa DESKTOP, nakadikit ito sa KANANG bahagi ng greeting row — pantay ang
/// kanang gilid sa Outstanding Balance card sa ibaba. Sa MOBILE, sa ilalim ng
/// Outstanding Balance card.
class _LenderKpiStats extends ConsumerWidget {
  /// Aktibong loan — null kapag wala ("—" ang ipinapakita sa mga tile).
  final LoanModel? loan;

  const _LenderKpiStats({required this.loan});

  /// Ang NEXT na bayaran: ang pinakamaagang schedule na may natitirang balanse
  /// (`amount_due - amount_paid`) — mas tumpak ito kung may partial payment.
  ///
  /// Kapag WALANG schedules sa payload (ang `loans-view?fn=get-list` ay
  /// `due_date` + `installment_amount` lang ang ipinapadala, hindi ang buong
  /// schedule), bumabalik ito sa installment_amount na may kasamang next due
  /// date — kaya hindi "—" ang Next Payment ng aktibong loan. Null lang kapag
  /// wala talagang susunod na bayaran (bayad na lahat o wala pang due date).
  ({double amount, DateTime? dueDate})? _nextPayment() {
    final raw = loan?.schedules;
    if (raw != null && raw.isNotEmpty) {
      final unpaid = raw
          .whereType<Map>()
          .map((e) => LoanScheduleModel.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.remainingAmount > 0)
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return unpaid.isEmpty
          ? null // bayad na lahat ng schedule
          : (
              amount: unpaid.first.remainingAmount,
              dueDate: unpaid.first.dueDate,
            );
    }
    final amount = loan?.installmentAmount ?? 0;
    final due = loan?.dueDate;
    if (loan == null || amount <= 0 || due == null) return null;
    return (amount: amount, dueDate: due);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obscured = ref.watch(lenderAmountObscuredProvider);
    String money(double value) => obscured ? '₱ ••••••' : value.toPeso();

    final next = _nextPayment();
    final installmentAmount = loan?.installmentAmount ?? 0;

    final nextTile = _StatTile(
      icon: Icons.event_available_outlined,
      label: 'Next Payment',
      value: next == null ? '—' : money(next.amount),
      // Ang due date ay bahagi ng "next payment" — nakatago rin kapag obscured
      // ang mga halaga (privacy, gaya ng ibang amount sa app).
      hint: (next?.dueDate == null || obscured)
          ? null
          : 'Due ${next!.dueDate!.toDateString()}',
    );
    final installmentTile = _StatTile(
      icon: Icons.receipt_long_outlined,
      label: 'Installment',
      value: installmentAmount > 0 ? money(installmentAmount) : '—',
    );

    // ISANG ROW (desktop at mobile) — IntrinsicHeight + stretch para pantay ang
    // TAAS kahit may "Due …" na linya ang Next Payment. Ang mga teksto sa loob
    // ng tile ay nagsi-shrink (FittedBox) kaya buo pa rin silang nababasa kahit
    // makitid ang espasyo — hindi napuputol ng "…".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: nextTile),
          const SizedBox(width: 14),
          Expanded(child: installmentTile),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Opsyonal na maliit na linya sa ilalim ng halaga (hal. "Due Sep 28, 2026").
  final String? hint;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.lenderBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.lenderBlue),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // FittedBox (scaleDown): kapag makitid ang tile, LUMILIIT ang
                // teksto imbes na maputol ng "…" — kaya laging kita ang label,
                // halaga at due date.
                _TileText(
                  text: label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: context.cTextTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                _TileText(
                  text: value,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: context.cTextPrimary,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  _TileText(
                    text: hint!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: context.cTextTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Isang linya ng `_StatTile` na hindi kailanman napuputol: kapag mas makitid
/// ang espasyo kaysa sa teksto, ini-scale down ito (hindi ellipsis).
class _TileText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _TileText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    );
  }
}

class _WelcomeBanner extends ConsumerStatefulWidget {
  final dynamic kpi;
  final String? firstName;
  final bool showBalance;

  /// Kapag true (desktop layout): nakadikit sa KALIWANG gilid ang Rive group,
  /// at ang fox ang pinaka-kaliwa — nasa KANAN nito ang greeting dialog.
  final bool desktop;

  const _WelcomeBanner(
      {required this.kpi,
      this.firstName,
      this.showBalance = true,
      this.desktop = false});

  @override
  ConsumerState<_WelcomeBanner> createState() => _WelcomeBannerState();
}

class _WelcomeBannerState extends ConsumerState<_WelcomeBanner> {
  /// Ang fox (Rive) at ang greeting dialog — sa desktop, ang FOX ang
  /// pinaka-kaliwa at nasa KANAN nito ang dialog; sa mobile, baliktad.
  Widget get _welcomeGroup => LenderWelcomeGroup(
        firstName: widget.firstName,
        riveFirst: widget.desktop,
        rive: const SizedBox(
          width: 118,
          height: 118,
          child: _FoxyRive(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final obscured = ref.watch(lenderAmountObscuredProvider);
    if (!widget.showBalance) {
      return Align(
        alignment: widget.desktop ? Alignment.topLeft : Alignment.topRight,
        child: _welcomeGroup,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -10,
          left: widget.desktop ? 4 : null,
          right: widget.desktop ? null : 4,
          child: _welcomeGroup,
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 95),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.lenderBlue.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Balance',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  InkWell(
                    onTap: () => ref
                        .read(lenderAmountObscuredProvider.notifier)
                        .toggle(),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        obscured
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              obscured
                  ? const Text(
                      '₱ ••••••',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                        letterSpacing: 2,
                      ),
                    )
                  : CountUpAnimation(
                      value: (widget.kpi?.remainingBalance ?? 0).toDouble(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                      prefix: '₱',
                      decimalPlaces: 2,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ang fox (Rive) at ang greeting dialog — nasa [LenderWelcomeGroup] na ang
/// ayos ng dalawa (injectable ang Rive kaya nate-test ito nang hindi umaasa sa
/// Rive asset sa test host).

class _ApprovedLoanBanner extends StatelessWidget {
  final LoanModel loan;
  const _ApprovedLoanBanner({required this.loan});

  /// Kapareho ng copy sa Application Status screen — nakadepende sa napiling
  /// paraan ng disbursement ("Your loan was approved ...").
  String get _message {
    switch (loan.disbursementMethod) {
      case 'rider_delivery':
        return 'Your loan was approved and you chose Cash on Delivery. A rider will be assigned to deliver your cash to your registered address.';
      case 'office_cash':
        return 'Your loan was approved and you chose Pick Up at Office. Your cash is being prepared and we will notify you when it is ready.';
      case 'gcash':
        return 'Your loan was approved and your GCash disbursement is being processed. We will notify you once the funds have been sent.';
      case null:
        return 'Choose how you want to receive your funds to complete the release.';
      default:
        return 'Your loan was approved and your disbursement is being processed. We will notify you once the funds are released.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Walang card (box/border) at walang "Loan #..." title — plain na mensahe
    // lang + View Application Status button.
    // DEBUG FIX: Kapag hindi pa nakapili si lender ng disbursement method
    // (null/empty), hindi muna dapat lumabas ang View Application Status.
    // Lalabas lang ito kapag may napili nang method (awaiting release).
    final method = loan.disbursementMethod;
    final hasChosenMethod = method != null && method.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(RouteConstants.lenderLoans),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary),
                ),
              ),
              if (hasChosenMethod) ...[
                const SizedBox(height: 12),
                // Diretso sa Application Status — hindi full width at naka-center.
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      RouteConstants.lenderLoanApplicationStatus
                          .replaceFirst(':id', loan.id),
                    ),
                    icon: const Icon(Icons.timeline_outlined, size: 16),
                    label: const Text('View Application Status'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.lenderBlue,
                      side: BorderSide(
                          color: AppColors.lenderBlue.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                // Hindi pa nakapili ng disbursement — explicit CTA papunta
                // sa disbursement selection (lenderLoans route).
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(RouteConstants.lenderLoans),
                    icon: const Icon(Icons.touch_app_outlined, size: 16),
                    label: const Text('Choose'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.lenderBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upgradeState = ref.watch(lenderAccountUpgradeProvider);
    final upgradeVerified =
        upgradeState.status == 'verified' || upgradeState.status == 'approved';
    // Ang KPI ng lender ang may huling salita kapag may naunang loan na siya:
    // kapag natapos na niya ang isang loan (fully paid / approved / active),
    // hindi na dapat mag-claim ng "Upgrade Account" — halatang "Apply Loan" na
    // ito. Dati, nag-fla-flash pa ang "Upgrade Account" sa button kahit paid
    // na lahat ng loan term niya.
    final kpi = ref.watch(lenderDashboardProvider).kpi;
    final hadPriorLoan =
        kpi.totalCompleted > 0 || kpi.totalApproved > 0 || kpi.totalActive > 0;
    final kpiVerified = kpi.accountUpgradeStatus == 'verified' ||
        kpi.accountUpgradeStatus == 'approved';
    final isVerified = upgradeVerified || kpiVerified || hadPriorLoan;
    // Huwag mag-claim ng "Upgrade Account" habang hindi pa na-load ang tunay
    // na status — dati itong nag-fla-flash/splash sa button bago pa dumating
    // ang server status kahit verified na (at kaya pa mag-apply ng loan).
    final ready = upgradeState.hasStatus || hadPriorLoan;
    // Account must be upgraded before a loan can be applied: show
    // "Upgrade Account" until verification, then "Apply Loan".
    final label = isVerified ? 'Apply Loan' : 'Upgrade Account';
    final route = isVerified
        ? RouteConstants.lenderLoans
        : RouteConstants.lenderAccountUpgrade;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: ready ? () => context.push(route) : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!ready) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Loading…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.arrow_forward,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingLoanCard extends StatelessWidget {
  final LoanModel loan;
  const _PendingLoanCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    // Walang orange na "Application Status" card/icon/status — naka-center na
    // prompt lang + ang blue na View Status button sa ibaba nito.
    return Column(
      children: [
        const Text(
          'Tap View Status to track your loan application.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => context.push(
              RouteConstants.lenderLoanApplicationStatus
                  .replaceFirst(':id', loan.id),
            ),
            icon: const Icon(Icons.timeline_outlined, size: 16),
            label: const Text('View Status'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lenderBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

class _MyLoanCard extends ConsumerStatefulWidget {
  final LoanModel loan;
  const _MyLoanCard({required this.loan});

  @override
  ConsumerState<_MyLoanCard> createState() => _MyLoanCardState();
}

class _MyLoanCardState extends ConsumerState<_MyLoanCard> {
  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final obscured = ref.watch(lenderAmountObscuredProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => context.push(
            RouteConstants.lenderLoanDetails.replaceFirst(':id', loan.id),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        loan.status == 'overdue'
                            ? 'Overdue Loan'
                            : 'Active Loan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Pay button sa kanang bahagi ng card — deretso sa Payment
                    // Method (rider o office) para sa active loan.
                    _PayNowButton(loan: loan),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Outstanding Balance',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    InkWell(
                      onTap: () => ref
                          .read(lenderAmountObscuredProvider.notifier)
                          .toggle(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          obscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                obscured
                    ? const Text(
                        '₱ ••••••',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                          letterSpacing: 2,
                        ),
                      )
                    : CountUpAnimation(
                        value: loan.outstandingBalance,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                        ),
                        prefix: '₱',
                        decimalPlaces: 2,
                      ),
              ],
            ),
          ),
        ),
        // HIDDEN: "Pay with" section sa ilalim ng Active Loan card.
        // _PayWithSection(loan: loan),
      ],
    );
  }
}

/// Maliit na "Pay" button sa kanang bahagi ng Active Loan card.
/// Pumupunta sa Payment Method screen (Cash on Delivery) at awtomatikong
/// nire-resolve ang susunod na babayarang installment.
class _PayNowButton extends StatelessWidget {
  final LoanModel loan;
  const _PayNowButton({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(
          RouteConstants.lenderPaymentMethod,
          extra: {'loan_id': loan.id},
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.payments_outlined,
                  size: 15, color: AppColors.lenderBlue),
              SizedBox(width: 6),
              Text(
                'Pay',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.lenderBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayWithBubble extends StatefulWidget {
  final String text;
  const _PayWithBubble({required this.text});

  @override
  State<_PayWithBubble> createState() => _PayWithBubbleState();
}

class _PayWithBubbleState extends State<_PayWithBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-0.3, 0.2),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: _ctrl,
        child: Text(
          widget.text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// HIDDEN sa lender Home (hindi na naka-mount) — napanatili para madaling
// ibalik kasama ang mga `_PayWithCard` / `_PayWithBubble`.
// ignore: unused_element
class _PayWithSection extends StatelessWidget {
  final LoanModel? loan;
  const _PayWithSection({required this.loan});

  void _showNoActiveLoan(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No Active Loan'),
        content: const Text(
          'You don\'t have an active loan yet. Apply for a loan first to use rider or office payments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(RouteConstants.lenderLoans);
            },
            child: const Text('Apply Loan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const _PayWithBubble(text: 'Pay with'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PayWithCard(
                assetPath: 'assets/icons/paywithrider.jpg',
                color: AppColors.riderGreen,
                title: 'Cash on Delivery',
                onTap: () {
                  final current = loan;
                  if (current == null) {
                    _showNoActiveLoan(context);
                  } else {
                    context.push(
                      RouteConstants.lenderPaymentMethod,
                      extra: {'loan_id': current.id},
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PayWithCard(
                assetPath: 'assets/icons/pay_with_office.jpg',
                color: AppColors.info,
                title: 'Office',
                onTap: () {
                  final current = loan;
                  if (current == null) {
                    _showNoActiveLoan(context);
                  } else {
                    context.push(
                      RouteConstants.lenderOfficePayment,
                      extra: {'loan_id': current.id},
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PayWithCard extends StatelessWidget {
  final String assetPath;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _PayWithCard({
    required this.assetPath,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Select',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recent Activity" — pinagsama-samang timeline ng lender: loans, bayad
/// (payments) at collection requests, pinakabago muna.
///
/// Dati, past loans lang ang nasa seksyong ito ("Recent Transactions") kaya
/// kapag active pa lang ang loan (walang natapos/dismissed na application),
/// walang aktibidad na lumalabas dito.
class _RecentActivitySection extends StatelessWidget {
  final List<LoanModel> loans;
  final String activeLoanId;
  final List<PaymentModel> payments;
  final List<Map<String, dynamic>> collections;
  final AccountUpgradeStatusModel? upgrade;

  const _RecentActivitySection({
    required this.loans,
    required this.activeLoanId,
    this.payments = const [],
    this.collections = const [],
    this.upgrade,
  });

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries(context);
    final shown = entries.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: icon chip + label + bilang ng aktibidad + "View all" —
        // kaparehong estilo ng Recent Activity sa rider dashboard.
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.history_rounded,
                  color: AppColors.lenderBlue, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Recent Activity',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: context.cTextPrimary,
                ),
              ),
            ),
            if (shown.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lenderBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${shown.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.lenderBlue,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push(RouteConstants.lenderLoanHistory),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View all',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.lenderBlue,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 16, color: AppColors.lenderBlue),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          _emptyActivityCard(context)
        else
          ...shown.map((e) => _ActivityTile(entry: e)),
      ],
    );
  }

  /// Kapareho ng empty card ng rider dashboard. Theme-aware ang kulay para
  /// tama rin sa dark mode.
  Widget _emptyActivityCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off_rounded,
              color: context.cTextTertiary, size: 36),
          const SizedBox(height: 8),
          Text(
            'No recent activity yet',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cTextSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Pinagdugtong ang lahat ng pinagmumulan (loans, payments, collections) at
  /// inayos ayon sa petsa — pinakabago muna.
  List<_ActivityEntry> _buildEntries(BuildContext context) {
    final entries = <_ActivityEntry>[];

    // ── Account upgrade (submission, verification, rejection) ─────────────
    final upgradeEntry = _upgradeEntry(context);
    if (upgradeEntry != null) entries.add(upgradeEntry);

    // ── Payments (bawat bayad na naitala / na-verify) ─────────────────────
    for (final p in payments) {
      final verified = p.status == 'verified';
      final reversed = p.status == 'reversed';
      entries.add(_ActivityEntry(
        at: p.createdAt,
        icon: verified
            ? Icons.check_circle_rounded
            : reversed
                ? Icons.undo_rounded
                : Icons.schedule_rounded,
        accent: verified
            ? AppColors.success
            : reversed
                ? AppColors.error
                : AppColors.warning,
        // `verified` → "Payment paid" (dating "Payment verified").
        title: verified
            ? 'Payment paid'
            : 'Payment ${p.statusLabel.toLowerCase()}',
        body: '${p.methodLabel} • ${p.amount.toCurrency}',
        onTap: p.id.isEmpty
            ? null
            : () => context.push(
                RouteConstants.lenderPaymentReceipt.replaceAll(':id', p.id)),
      ));
    }

    // ── Collections (rider / office pickup requests) ──────────────────────
    for (final c in collections) {
      final status = (c['status'] as String? ?? '').toLowerCase();
      final at = _parseActivityDate(c['updated_at'] ??
          c['created_at'] ??
          c['collection_schedule'] ??
          c['completed_at']);
      if (at == null) continue;
      final amount = (c['amount_collected'] as num?)?.toDouble() ??
          (c['amount'] as num?)?.toDouble() ??
          0;
      final rider = (c['rider_name'] as String? ?? '').trim();
      final id = c['id'] as String? ?? '';
      final done = status == 'completed';
      final failed =
          const ['cancelled', 'declined', 'expired', 'failed'].contains(status);
      entries.add(_ActivityEntry(
        at: at,
        icon: Icons.delivery_dining_rounded,
        accent: done
            ? AppColors.success
            : failed
                ? AppColors.error
                : AppColors.lenderBlue,
        title: 'Collection ${_collectionStatusLabel(status)}',
        body: [
          rider.isNotEmpty ? rider : 'Payment pickup request',
          if (amount > 0) amount.toCurrency,
        ].join(' • '),
        onTap: id.isEmpty
            ? null
            : () => context.push('${RouteConstants.lenderCollections}/$id'),
      ));
    }

    // ── Loans (application, approval, release, tapos) ─────────────────────
    for (final loan in loans) {
      final status = loan.status.toLowerCase();
      entries.add(_ActivityEntry(
        at: loan.disbursedAt ??
            (status == 'active' ? loan.updatedAt : loan.createdAt),
        icon: _loanActivityIcon(status),
        accent: _loanActivityAccent(status),
        title: _loanActivityTitle(status),
        body: '${loan.loanNumber} • ${loan.principalAmount.toCurrency}',
        onTap: () => context.push(
            RouteConstants.lenderLoanDetails.replaceFirst(':id', loan.id)),
      ));
    }

    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  /// Timeline entry para sa account upgrade ng lender.
  ///
  /// Dati, loans + payments + collections lang ang pinagmumulan ng Recent
  /// Activity, kaya ang lender na kaka-submit pa lang ng account upgrade (at
  /// wala pang loan, bayad, o collection) ay "No recent activity yet" ang
  /// nakikita — kahit may nangyari na sa account niya.
  _ActivityEntry? _upgradeEntry(BuildContext context) {
    final current = upgrade;
    if (current == null) return null;
    final status = current.accountUpgradeStatus.trim().toLowerCase();
    if (status.isEmpty || status == 'not_submitted') return null;

    final docs = current.documents;
    DateTime? newest(DateTime? Function(AccountUpgradeDocumentModel d) pick) {
      DateTime? found;
      for (final d in docs) {
        final value = pick(d);
        if (value != null && (found == null || value.isAfter(found))) {
          found = value;
        }
      }
      return found;
    }

    final submittedAt = newest((d) => d.createdAt);
    final reviewedAt = newest((d) => d.reviewedAt);
    void openStatus() =>
        context.push(RouteConstants.lenderAccountUpgradeStatus);

    if (status == 'rejected') {
      final at = current.rejectedAt ?? reviewedAt ?? submittedAt;
      if (at == null) return null;
      String? notes;
      for (final d in docs) {
        final n = d.rejectionNotes?.trim();
        if (n != null && n.isNotEmpty) {
          notes = n;
          break;
        }
      }
      return _ActivityEntry(
        at: at,
        icon: Icons.gpp_bad_outlined,
        accent: AppColors.error,
        title: 'Account upgrade rejected',
        body: notes ?? 'You may resubmit after 1 month.',
        onTap: openStatus,
      );
    }

    if (status == 'verified' || status == 'approved') {
      final at = reviewedAt ?? submittedAt;
      if (at == null) return null;
      return _ActivityEntry(
        at: at,
        icon: Icons.verified_rounded,
        accent: AppColors.success,
        title: 'Account upgrade verified',
        body: 'You can now apply for a loan.',
        onTap: openStatus,
      );
    }

    // submitted / under review — nasa pipeline pa ang mga dokumento.
    final at = submittedAt ?? reviewedAt;
    if (at == null) return null;
    return _ActivityEntry(
      at: at,
      icon: Icons.verified_user_outlined,
      accent: AppColors.lenderBlue,
      title: 'Account upgrade submitted',
      body: docs.isEmpty
          ? 'Pending review'
          : '${docs.length} document${docs.length == 1 ? '' : 's'} • Pending review',
      onTap: openStatus,
    );
  }

  static DateTime? _parseActivityDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return parseManila(value) ?? DateTime.tryParse(value);
    }
    return null;
  }

  static String _collectionStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'completed';
      case 'in_progress':
        return 'in progress';
      case 'accepted':
        return 'accepted by rider';
      case 'assigned':
        return 'rider assigned';
      case 'requested':
      case 'pending':
        return 'requested';
      case 'cancelled':
        return 'cancelled';
      case 'declined':
        return 'declined';
      case 'expired':
        return 'expired';
      default:
        return status.isEmpty ? 'update' : status;
    }
  }

  static IconData _loanActivityIcon(String status) {
    if (status == 'active') return Icons.account_balance_wallet_rounded;
    if (status == 'overdue') return Icons.warning_amber_rounded;
    if (status == 'completed') return Icons.verified_rounded;
    if (status == 'approved') return Icons.check_circle_rounded;
    if (['rejected', 'cancelled'].contains(status)) {
      return Icons.cancel_rounded;
    }
    if (_inProgressStatuses.contains(status)) {
      return Icons.hourglass_top_rounded;
    }
    return Icons.receipt_long_rounded;
  }

  static Color _loanActivityAccent(String status) {
    if (status == 'active') return AppColors.lenderBlue;
    if (status == 'overdue') return AppColors.warning;
    if (status == 'completed' || status == 'approved') {
      return AppColors.success;
    }
    if (['rejected', 'cancelled'].contains(status)) return AppColors.error;
    if (_inProgressStatuses.contains(status)) return AppColors.warning;
    return AppColors.textTertiary;
  }

  static String _loanActivityTitle(String status) {
    switch (status) {
      case 'pending':
      case 'under_review':
        return 'Loan application submitted';
      case 'ci_required':
      case 'ci_assigned':
      case 'ci_completed':
      case 'ci_approved':
        return 'Loan under review';
      case 'approved':
        return 'Loan approved — choose how to receive';
      case 'active':
        return 'Loan released';
      case 'overdue':
        return 'Loan overdue';
      case 'completed':
        return 'Loan fully paid';
      case 'rejected':
        return 'Loan rejected';
      case 'cancelled':
        return 'Loan cancelled';
      default:
        return 'Loan updated';
    }
  }
}

/// Statuses na hindi pa tapos (nasa pipeline pa) — pareho ang tint.
const Set<String> _inProgressStatuses = {
  'pending',
  'under_review',
  'ci_required',
  'ci_assigned',
  'ci_completed',
  'ci_approved',
};

class _ActivityEntry {
  final DateTime at;
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final VoidCallback? onTap;

  const _ActivityEntry({
    required this.at,
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.onTap,
  });
}

/// Tile na kapareho ng Recent Activity tile ng rider dashboard: icon chip sa
/// kaliwa, title + detalye + "time ago" sa gitna, chevron sa kanan.
class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;
  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: entry.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(entry.icon, color: color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: context.cTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // "5m ago" / "2d ago" — parehong helper ng app
                        // (`DateExtensions.timeAgo`).
                        entry.at.timeAgo,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.cTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: context.cTextTertiary, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyLoansOverview extends StatelessWidget {
  final dynamic kpi;
  const _MyLoansOverview({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 20),
        Text(
          'Need cash now?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppColors.lenderBlue,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Borrow from ₱3,000\nto ₱500,000',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Fast approval · Flexible terms · Low monthly rates\n'
          'Apply today and get the cash you need, right when you need it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Must be 18 years old and above · Release in 1–2 business days.\n'
          'You can apply if you are eligible based on your details.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner(this.error);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoxyRive extends StatefulWidget {
  const _FoxyRive();

  @override
  State<_FoxyRive> createState() => _FoxyRiveState();
}

class _FoxyRiveState extends State<_FoxyRive> {
  late final FileLoader _loader;

  @override
  void initState() {
    super.initState();
    _loader = FileLoader.fromAsset(
      'assets/rive/foxy.riv',
      riveFactory: Factory.rive,
    );
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RiveWidgetBuilder(
      fileLoader: _loader,
      builder: (context, state) => switch (state) {
        RiveLoading() => const SizedBox.shrink(),
        RiveFailed() => const SizedBox.shrink(),
        RiveLoaded() => RiveWidget(
            controller: state.controller,
            fit: Fit.contain,
            alignment: Alignment.bottomCenter,
          ),
      },
    );
  }
}

class _LenderDashboardSkeleton extends StatelessWidget {
  const _LenderDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        mobileBottomNavInset(context),
      ),
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome / Balance card skeleton
            Container(
              width: double.infinity,
              height: 176,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 16),
            // Foxy + bubble placeholder row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                    width: 110,
                    height: 32,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12))),
                const SizedBox(width: 8),
                Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 16),
            // Apply Now / Pending card skeleton
            Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 20),
            // My Loans overview skeleton
            Center(
                child: Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6)))),
            const SizedBox(height: 10),
            Center(
                child: Container(
                    width: 180,
                    height: 22,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6)))),
            const SizedBox(height: 10),
            Center(
                child: Container(
                    width: 220,
                    height: 10,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6)))),
            const SizedBox(height: 10),
            Center(
                child: Container(
                    width: 160,
                    height: 10,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6)))),
            const SizedBox(height: 20),
            // Active loan card skeleton (if any)
            Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16))),
            const SizedBox(height: 16),
            // You can pay with (2 cards) skeleton
            Container(
                width: 120,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)))),
                const SizedBox(width: 12),
                Expanded(
                    child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)))),
              ],
            ),
            const SizedBox(height: 16),
            // Loan history title skeleton
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6))),
                Container(
                    width: 60,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6))),
              ],
            ),
            const SizedBox(height: 12),
            // 3 loan history tiles skeleton
            ...List.generate(
                3,
                (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: AppColors.shimmerBase,
                                    borderRadius: BorderRadius.circular(11))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Container(
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: AppColors.shimmerBase,
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                  const SizedBox(height: 8),
                                  Container(
                                      height: 10,
                                      width: 100,
                                      decoration: BoxDecoration(
                                          color: AppColors.shimmerBase,
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                  const SizedBox(height: 6),
                                  Container(
                                      height: 9,
                                      width: 80,
                                      decoration: BoxDecoration(
                                          color: AppColors.shimmerBase,
                                          borderRadius:
                                              BorderRadius.circular(6)))
                                ])),
                            const SizedBox(width: 12),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                      width: 70,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: AppColors.shimmerBase,
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                  const SizedBox(height: 8),
                                  Container(
                                      width: 54,
                                      height: 18,
                                      decoration: BoxDecoration(
                                          color: AppColors.shimmerBase,
                                          borderRadius:
                                              BorderRadius.circular(10)))
                                ]),
                          ],
                        ),
                      ),
                    )),
            // Tracking card skeleton
            Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14))),
          ],
        ),
      ),
    );
  }
}
