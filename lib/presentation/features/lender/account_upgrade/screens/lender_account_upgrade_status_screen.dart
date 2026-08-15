// lib/presentation/features/lender/account_upgrade/screens/lender_account_upgrade_status_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_account_upgrade_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderAccountUpgradeStatusScreen extends ConsumerStatefulWidget {
  const LenderAccountUpgradeStatusScreen({super.key});

  @override
  ConsumerState<LenderAccountUpgradeStatusScreen> createState() =>
      _LenderAccountUpgradeStatusScreenState();
}

class _LenderAccountUpgradeStatusScreenState
    extends ConsumerState<LenderAccountUpgradeStatusScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderAccountUpgradeProvider.notifier).loadStatus());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderAccountUpgradeProvider);

    return MobileScaffold(
      title: 'Account Upgrade Status',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : RefreshIndicator(
              color: AppColors.lenderBlue,
              onRefresh: () =>
                  ref.read(lenderAccountUpgradeProvider.notifier).loadStatus(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBanner(status: state.status),
                    const SizedBox(height: 20),
                    _buildTimeline(state),
                    const SizedBox(height: 20),
                    if (state.documents.isNotEmpty) ...[
                      _sectionLabel('Submitted Documents'),
                      const SizedBox(height: 12),
                      ...state.documents
                          .map((d) => _DocumentTile(key: ValueKey(d.id), doc: d)),
                    ],
                    if (state.status == 'rejected') ...[
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Resubmit Documents',
                        onPressed: () =>
                            context.push(RouteConstants.lenderAccountUpgrade),
                        color: AppColors.lenderBlue,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTimeline(LenderAccountUpgradeState state) {
    final steps = [
      _TimelineStep(
          'Documents Submitted',
          'Your account upgrade documents have been submitted for review.',
          state.status != 'not_submitted',
          Icons.upload_file),
      _TimelineStep(
          'Under Review',
          'Our team is reviewing your documents.',
          ['under_review', 'verified', 'rejected'].contains(state.status),
          Icons.manage_search),
      _TimelineStep(
        state.status == 'rejected' ? 'Rejected' : 'Verified',
        state.status == 'rejected'
            ? (state.rejectionNotes ??
                'Documents were rejected. Please resubmit.')
            : 'Your identity has been verified. You may now apply for a loan.',
        ['verified', 'rejected'].contains(state.status),
        state.status == 'rejected' ? Icons.cancel : Icons.verified_user,
        isError: state.status == 'rejected',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Verification Timeline'),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((e) =>
            _TimelineTile(step: e.value, isLast: e.key == steps.length - 1)),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      );
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String message;
    switch (status) {
      case 'verified':
        color = AppColors.success;
        icon = Icons.verified_user;
        message =
            'Your account upgrade is verified. You can now apply for a loan.';
        break;
      case 'rejected':
        color = AppColors.error;
        icon = Icons.cancel;
        message =
            'Your account upgrade was rejected. Please resubmit your documents.';
        break;
      case 'under_review':
        color = AppColors.warning;
        icon = Icons.hourglass_bottom;
        message = 'Your documents are currently under review.';
        break;
      case 'submitted':
        color = AppColors.info;
        icon = Icons.cloud_done_outlined;
        message = 'Documents submitted and awaiting review.';
        break;
      default:
        color = AppColors.textSecondary;
        icon = Icons.help_outline;
        message = 'Please submit your account upgrade documents to proceed.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: ${status.replaceAll('_', ' ').toUpperCase()}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(message,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.8), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String title;
  final String subtitle;
  final bool completed;
  final IconData icon;
  final bool isError;
  const _TimelineStep(this.title, this.subtitle, this.completed, this.icon,
      {this.isError = false});
}

class _TimelineTile extends StatelessWidget {
  final _TimelineStep step;
  final bool isLast;
  const _TimelineTile({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = step.isError
        ? AppColors.error
        : step.completed
            ? AppColors.success
            : AppColors.border;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: step.completed
                    ? color.withValues(alpha: 0.12)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                    color: step.completed ? color : AppColors.border, width: 2),
              ),
              child: Icon(step.icon,
                  size: 18,
                  color: step.completed ? color : AppColors.textTertiary),
            ),
            if (!isLast)
              Container(
                  width: 2,
                  height: 40,
                  color: step.completed
                      ? color.withValues(alpha: 0.3)
                      : AppColors.border),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: step.completed
                            ? AppColors.textPrimary
                            : AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text(step.subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final dynamic doc;
  const _DocumentTile({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              color: AppColors.lenderBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.documentType ?? 'Document',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                Text(
                    doc.createdAt != null
                        ? (doc.createdAt as DateTime).toDateString()
                        : '',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          StatusBadge(status: doc.status ?? 'submitted'),
        ],
      ),
    );
  }
}
