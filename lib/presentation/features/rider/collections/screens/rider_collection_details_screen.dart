// lib/presentation/features/rider/collections/screens/rider_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../providers/rider_collection_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderCollectionDetailsScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderCollectionDetailsScreen> createState() =>
      _RiderCollectionDetailsScreenState();
}

class _RiderCollectionDetailsScreenState
    extends ConsumerState<RiderCollectionDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  XFile? _proofPhoto;
  XFile? _scenePhoto;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isProof) async {
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
    if (picked != null) {
      setState(() {
        if (isProof) {
          _proofPhoto = picked;
        } else {
          _scenePhoto = picked;
        }
      });
    }
  }

  Future<void> _recordCollection(CollectionAssignmentModel col) async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final ok =
          await ref.read(riderCollectionProvider.notifier).recordCollection(
                assignmentId: widget.collectionId,
                amountCollected: amount,
                notes: _notesCtrl.text.trim(),
              );
      if (mounted) {
        if (ok) {
          showDialog(
              context: context,
              builder: (_) => const SuccessDialog(
                  message: 'Collection recorded successfully'));
        } else {
          showDialog(
              context: context,
              builder: (_) =>
                  const ErrorDialog(message: 'Failed to record collection'));
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _uploadProof() async {
    if (_proofPhoto == null) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please take a proof photo')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final ok = await ref.read(riderCollectionProvider.notifier).uploadProof(
            assignmentId: widget.collectionId,
            proofPhoto: _proofPhoto!,
            scenePhoto: _scenePhoto,
          );
      if (mounted) {
        if (ok) {
          showDialog(
              context: context,
              builder: (_) => const SuccessDialog(
                  message: 'Proof uploaded and collection completed!'));
        } else {
          showDialog(
              context: context,
              builder: (_) =>
                  const ErrorDialog(message: 'Failed to upload proof'));
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.riderGreen,
        foregroundColor: Colors.white,
        title: const Text('Collection Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (col != null)
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: StatusBadge(status: col.status, small: false)),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Collect'),
            Tab(text: 'Upload Proof')
          ],
        ),
      ),
      body: state.isLoading
          ? const ShimmerLoader()
          : col == null
              ? const Center(child: Text('Collection not found'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDetailsTab(col),
                    _buildCollectTab(col),
                    _buildProofTab(col),
                  ],
                ),
    );
  }

  Widget _buildDetailsTab(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Collection Summary',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        AppColors.riderGreen,
                        AppColors.riderGreenDark
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Amount Due',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Text(amountDue.toCurrency,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
                  _InfoTile(
                      'Period', 'Period ${schedule?['period_number'] ?? ''}'),
                  _InfoTile('Status', col.status),
                  if (col.amountCollected != null)
                    _InfoTile('Collected', col.amountCollected!.toCurrency),
                  if (col.completedAt != null)
                    _InfoTile(
                        'Completed At',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.completedAt!)),
                  if (col.collectionSchedule != null)
                    _InfoTile(
                        'Scheduled At',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.collectionSchedule!)),
                  if (col.notes != null && col.notes!.isNotEmpty)
                    _InfoTile('Notes', col.notes!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lender Information',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  _InfoTile('Name', col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #', col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
                  _InfoTile(
                      'Phone',
                      col.loanSchedule?['loan']?['lender_profiles']?['users']
                              ?['phone_number'] ??
                          'N/A'),
                ],
              ),
            ),
          ),
          if (col.status == 'assigned') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await ref
                          .read(riderCollectionProvider.notifier)
                          .decline(widget.collectionId);
                      if (mounted && ok) context.pop();
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        minimumSize: const Size(0, 48)),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await ref
                          .read(riderCollectionProvider.notifier)
                          .accept(widget.collectionId);
                      if (mounted) setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen,
                        minimumSize: const Size(0, 48)),
                    child: const Text('Accept',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
          if (col.status == 'accepted') ...[
            const SizedBox(height: 16),
            AppButton(
                label: 'Navigate to Lender',
                onPressed: () => context.push(
                    RouteConstants.riderNavigateToBorrower.replaceFirst(
                        ':id', widget.collectionId)),
                icon: Icons.map_outlined,
                color: AppColors.info),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectTab(CollectionAssignmentModel col) {
    if (col.status == 'completed' || col.status == 'declined') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 56, color: AppColors.riderGreen),
              SizedBox(height: 12),
              Text(
                  'This collection has been processed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    if (col.status != 'accepted' && col.status != 'in_progress') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: AppColors.textTertiary),
              SizedBox(height: 12),
              Text(
                  'You must accept the assignment before recording a collection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.2))),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.riderGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Expected amount: ${amountDue.toCurrency}',
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppTextField(
              controller: _amountCtrl,
              label: 'Amount Collected (₱)',
              keyboardType: TextInputType.number,
              prefixIcon: Icons.payments_outlined),
          const SizedBox(height: 14),
          AppTextField(
              controller: _notesCtrl, label: 'Notes (optional)', maxLines: 3),
          const SizedBox(height: 20),
          AppButton(
            label: _isSubmitting ? 'Recording...' : 'Record Collection',
            onPressed: _isSubmitting ? null : () => _recordCollection(col),
            color: AppColors.riderGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildProofTab(CollectionAssignmentModel col) {
    if (col.status == 'completed') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_outlined,
                  size: 56, color: AppColors.riderGreen),
              const SizedBox(height: 12),
              const Text('Collection completed successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Amount collected: ${col.amountCollected?.toCurrency ?? '—'}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              if (col.completedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Completed: ${DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upload Proof',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Upload payment proof and scene photo to complete the collection.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          _PhotoPicker(
            label: 'Payment Proof *',
            photo: _proofPhoto,
            onPick: () => _pickImage(true),
          ),
          const SizedBox(height: 16),
          _PhotoPicker(
            label: 'Scene Photo (optional)',
            photo: _scenePhoto,
            onPick: () => _pickImage(false),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: _isSubmitting ? 'Uploading...' : 'Upload & Complete',
            onPressed: _isSubmitting ? null : _uploadProof,
            color: AppColors.riderGreen,
          ),
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final String label;
  final XFile? photo;
  final VoidCallback onPick;
  const _PhotoPicker({required this.label, this.photo, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: photo == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined,
                          size: 36, color: AppColors.textTertiary),
                      SizedBox(height: 8),
                      Text('Tap to take photo',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: XFilePreview(file: photo!),
                  ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}
