// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/ci/screens/rider_submit_ci_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../providers/rider_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderSubmitCiReportScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderSubmitCiReportScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderSubmitCiReportScreen> createState() =>
      _RiderSubmitCiReportScreenState();
}

class _RiderSubmitCiReportScreenState
    extends ConsumerState<RiderSubmitCiReportScreen> {
  final _reportCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(riderCiProvider);
      final ci = state.ciList.where((c) => c.id == widget.ciId).firstOrNull;
      if (ci?.reportSummary != null) {
        _reportCtrl.text = ci!.reportSummary!;
      }
    });
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reportCtrl.text.trim().length < 30) {
      setState(() => _error =
          'Report must be at least 30 characters. Describe your investigation findings.');
      return;
    }

    final confirmed = await showConfirmationDialog(
      context,
      title: 'Submit Report',
      message: 'Are you sure to submit this ci?',
      confirmLabel: 'Submit',
      confirmColor: AppColors.riderGreen,
    );
    if (confirmed != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await ref.read(riderCiProvider.notifier).submitReport(
        ciId: widget.ciId, reportSummary: _reportCtrl.text.trim());

    setState(() => _submitting = false);

    if (ok && mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('CI Report submitted successfully!'),
          backgroundColor: AppColors.riderGreen,
        ),
      );
      context.go(RouteConstants.riderCi);
    } else if (mounted) {
      setState(() =>
          _error = 'Submission failed. Ensure at least 1 photo is uploaded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);
    final ci = state.ciList.where((c) => c.id == widget.ciId).firstOrNull;
    final docCount = ci?.documents?.length ?? 0;

    return MobileScaffold(
      title: 'Submit CI Report',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      showBackButton: true,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: docCount > 0
                    ? AppColors.successLight
                    : AppColors.warningLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    docCount > 0
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color:
                        docCount > 0 ? AppColors.riderGreen : AppColors.warning,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      docCount > 0
                          ? '$docCount photo(s) uploaded and ready.'
                          : 'No photos uploaded yet. Upload at least 1 photo before submitting.',
                      style: TextStyle(
                        fontSize: 13,
                        color: docCount > 0
                            ? AppColors.riderGreen
                            : AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            if (docCount == 0)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go(
                    RouteConstants.riderUploadCiDocuments
                        .replaceFirst(':id', widget.ciId),
                  ),
                  icon: Icon(Icons.camera_alt_outlined,
                      color: AppColors.riderGreen),
                  label: Text('Upload CI Photos',
                      style: TextStyle(color: AppColors.riderGreen)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.riderGreen),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            SizedBox(height: 16),
            Text(
              'Investigation Report *',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: context.cTextPrimary),
            ),
            SizedBox(height: 6),
            Text(
              'Describe your findings: visit details, lender verification, property assessment, neighbor statements, and any observations relevant to creditworthiness.',
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
            SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: context.cSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _error != null ? AppColors.error : context.cBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: TextField(
                controller: _reportCtrl,
                maxLines: 10,
                minLines: 6,
                style: TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Visited lender at provided address on [date]. Property confirmed as residential. Spoke with neighbor who confirmed lender has lived here for 3 years. Lender showed employment ID. No red flags observed.',
                  hintStyle:
                      TextStyle(fontSize: 13, color: context.cTextTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 14, color: AppColors.error),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.error)),
                  ),
                ],
              ),
            ],
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_submitting || docCount == 0) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.riderGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor:
                      AppColors.riderGreen.withValues(alpha: 0.4),
                ),
                child: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Submit',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
