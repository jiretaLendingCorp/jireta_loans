// lib/presentation/features/lender/kyc/screens/lender_kyc_submit_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/lender_kyc_provider.dart';

class LenderKycSubmitScreen extends ConsumerStatefulWidget {
  const LenderKycSubmitScreen({super.key});

  @override
  ConsumerState<LenderKycSubmitScreen> createState() =>
      _LenderKycSubmitScreenState();
}

class _LenderKycSubmitScreenState extends ConsumerState<LenderKycSubmitScreen> {
  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.lenderDashboard),
    MobileNavItem(
        icon: Icons.account_balance_outlined,
        activeIcon: Icons.account_balance,
        label: 'My Loan',
        route: RouteConstants.lenderLoans),
    MobileNavItem(
        icon: Icons.payment_outlined,
        activeIcon: Icons.payment,
        label: 'Payments',
        route: RouteConstants.lenderPayments),
    MobileNavItem(
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
        label: 'Alerts',
        route: RouteConstants.lenderNotifications),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.lenderProfile),
  ];

  final Map<String, PlatformFile?> _selectedFiles = {
    'valid_id': null,
    'selfie': null,
    'proof_of_billing': null,
    'proof_of_income': null,
  };

  final Map<String, String> _docLabels = {
    'valid_id': 'Valid Government ID *',
    'selfie': 'Selfie with ID *',
    'proof_of_billing': 'Proof of Billing *',
    'proof_of_income': 'Proof of Income *',
  };

  final Map<String, IconData> _docIcons = {
    'valid_id': Icons.badge_outlined,
    'selfie': Icons.face_outlined,
    'proof_of_billing': Icons.receipt_outlined,
    'proof_of_income': Icons.work_outline,
  };

  bool _isSubmitting = false;

  Future<void> _pickFile(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFiles[docType] = result.files.first);
    }
  }

  Future<void> _submit() async {
    final missing = _selectedFiles.entries
        .where((e) => e.value == null)
        .map((e) => _docLabels[e.key]!)
        .toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please upload: ${missing.join(', ')}')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final docs = <Map<String, dynamic>>[];
      for (final e in _selectedFiles.entries) {
        final f = e.value;
        if (f == null) continue;
        final path = f.path;
        String? contentBase64;
        if (path != null) {
          contentBase64 = base64Encode(await File(path).readAsBytes());
        }
        docs.add({
          'document_type': e.key,
          'file_name': f.name,
          'file_size': f.size,
          if (contentBase64 != null) 'content_base64': contentBase64,
        });
      }
      final ok = await ref.read(lenderKycProvider.notifier).submitKyc(docs);
      // Use context.mounted (not State.mounted) to guard all async context use
      if (ok) {
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (_) => const SuccessDialog(
            message: 'KYC documents submitted successfully. Under review.',
          ),
        );
        if (!context.mounted) return;
        context.go(RouteConstants.lenderDashboard);
      } else {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => const ErrorDialog(
            message: 'Failed to submit KYC documents. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderKycProvider);

    return MobileScaffold(
      title: 'KYC Verification',
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBanner(state),
                  const SizedBox(height: 20),
                  const Text('Required Documents',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  const Text(
                      'Upload clear, legible photos or scans. Files must be JPG, PNG, or PDF under 5MB.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                  ..._selectedFiles.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _DocUploadCard(
                          label: _docLabels[e.key]!,
                          icon: _docIcons[e.key]!,
                          file: e.value,
                          onPick: () => _pickFile(e.key),
                        ),
                      )),
                  const SizedBox(height: 8),
                  if (state.status == 'submitted' ||
                      state.status == 'under_review')
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3))),
                      child: const Row(
                        children: [
                          Icon(Icons.hourglass_top_outlined,
                              color: AppColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Your KYC is under review. We will notify you once verified.',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.warning))),
                        ],
                      ),
                    )
                  else
                    AppButton(
                      label: _isSubmitting
                          ? 'Submitting...'
                          : 'Submit KYC Documents',
                      onPressed: _isSubmitting ? null : _submit,
                      color: AppColors.lenderPurple,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(LenderKycState state) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String message;

    switch (state.status) {
      case 'verified':
        bgColor = AppColors.successLight;
        textColor = AppColors.success;
        icon = Icons.verified_user;
        message = 'Your identity has been verified!';
        break;
      case 'submitted':
      case 'under_review':
        bgColor = AppColors.warningLight;
        textColor = AppColors.warning;
        icon = Icons.pending_outlined;
        message = 'Documents under review';
        break;
      case 'rejected':
        bgColor = AppColors.errorLight;
        textColor = AppColors.error;
        icon = Icons.cancel_outlined;
        message = state.rejectionNotes ?? 'KYC rejected. Please resubmit.';
        break;
      default:
        bgColor = AppColors.infoLight;
        textColor = AppColors.info;
        icon = Icons.info_outline;
        message = 'Complete KYC to apply for a loan';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _DocUploadCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final PlatformFile? file;
  final VoidCallback onPick;
  const _DocUploadCard(
      {required this.label,
      required this.icon,
      this.file,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.lenderPurple.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: hasFile
                  ? AppColors.lenderPurple.withValues(alpha: 0.3)
                  : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile
                    ? AppColors.lenderPurple.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color:
                      hasFile ? AppColors.lenderPurple : AppColors.textTertiary,
                  size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    hasFile ? file!.name : 'Tap to upload',
                    style: TextStyle(
                        fontSize: 12,
                        color: hasFile
                            ? AppColors.lenderPurple
                            : AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(hasFile ? Icons.check_circle : Icons.upload_file_outlined,
                color: hasFile ? AppColors.success : AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
