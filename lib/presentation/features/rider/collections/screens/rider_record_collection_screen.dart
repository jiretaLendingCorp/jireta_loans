// lib/presentation/features/rider/collections/screens/rider_record_collection_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_collection_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderRecordCollectionScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderRecordCollectionScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderRecordCollectionScreen> createState() =>
      _RiderRecordCollectionScreenState();
}

class _RiderRecordCollectionScreenState
    extends ConsumerState<RiderRecordCollectionScreen> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCollection() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Enter a valid amount'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Confirm Collection',
        message:
            'Record ₱${amount.toStringAsFixed(2)} as collected from lender?',
        confirmText: 'Confirm',
        confirmColor: AppColors.riderGreen,
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final ok =
          await ref.read(riderCollectionProvider.notifier).recordCollection(
                assignmentId: widget.collectionId,
                amountCollected: amount,
                notes: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              );

      if (mounted) {
        if (ok) {
          await showDialog(
            context: context,
            builder: (_) => SuccessDialog(
              message:
                  'Collection of ${amount.toPeso()} recorded successfully.',
            ),
          );
          if (mounted) {
            context.push(
              RouteConstants.riderUploadProof
                  .replaceFirst(':id', widget.collectionId),
            );
          }
        } else {
          showDialog(
            context: context,
            builder: (_) => const ErrorDialog(
                message: 'Failed to record collection. Please try again.'),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    return MobileScaffold(
      title: 'Record Collection',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: col == null
          ? state.isLoading
              ? const ShimmerLoader()
              : const Center(child: Text('Collection not found'))
          : _buildForm(col),
    );
  }

  Widget _buildForm(CollectionAssignmentModel col) {
    final amountDue = col.amountDue;
    final borrowerName = col.lenderName.isEmpty ? '—' : col.lenderName;
    final loanNumber = col.loanNumber.isEmpty ? '—' : col.loanNumber;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CollectionSummaryCard(
            borrowerName: borrowerName,
            amountDue: amountDue,
            loanNumber: loanNumber,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Collection Details',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _amountCtrl,
                  label: 'Amount Collected (₱)',
                  hint: '0.00',
                  prefixIcon: Icons.monetization_on_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Amount is required';
                    final n = double.tryParse(v.replaceAll(',', ''));
                    if (n == null || n <= 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _notesCtrl,
                  label: 'Notes (Optional)',
                  hint: 'Add any collection notes...',
                  prefixIcon: Icons.notes_outlined,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.riderGreen.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.gps_fixed,
                          color: AppColors.riderGreen, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your GPS location is automatically captured and recorded with this collection.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Record Collection',
            onPressed: _isSubmitting ? null : _submitCollection,
            isLoading: _isSubmitting,
            backgroundColor: AppColors.riderGreen,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: () => context.pop(),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _CollectionSummaryCard extends StatelessWidget {
  final String borrowerName;
  final double amountDue;
  final String loanNumber;
  const _CollectionSummaryCard(
      {required this.borrowerName,
      required this.amountDue,
      required this.loanNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreenDark, AppColors.riderGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(borrowerName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.receipt_outlined,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(loanNumber,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Amount Due',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text(amountDue.toPeso(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ],
          ),
        ],
      ),
    );
  }
}
