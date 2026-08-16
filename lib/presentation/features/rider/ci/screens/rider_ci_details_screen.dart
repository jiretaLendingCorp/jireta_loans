// lib/presentation/features/rider/ci/screens/rider_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/rider_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderCiDetailsScreen> createState() =>
      _RiderCiDetailsScreenState();
}

class _RiderCiDetailsScreenState extends ConsumerState<RiderCiDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reportCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<XFile> _pickedImages = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reportCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked =
        await _imagePicker.pickMultiImage(imageQuality: 80, maxWidth: 1920);
    if (picked.isNotEmpty) setState(() => _pickedImages.addAll(picked));
  }

  Future<void> _uploadDocuments() async {
    if (_pickedImages.isEmpty) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please select at least one photo')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final ok = await ref.read(riderCiProvider.notifier).uploadDocuments(
            ciId: widget.ciId,
            images: _pickedImages,
          );
      if (ok) {
        if (!mounted) return;
        setState(() => _pickedImages.clear());
        showDialog(
            context: context,
            builder: (_) => const SuccessDialog(
                message: 'Documents uploaded successfully'));
      } else {
        if (!mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const ErrorDialog(message: 'Failed to upload documents'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitReport() async {
    if (_reportCtrl.text.trim().isEmpty) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Please write your investigation report')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final ok = await ref.read(riderCiProvider.notifier).submitReport(
            ciId: widget.ciId,
            reportSummary: _reportCtrl.text.trim(),
          );
      // Use mounted (not context.mounted) to guard all async context use
      if (ok) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => const SuccessDialog(
            message: 'CI report submitted successfully',
          ),
        );
        if (!mounted) return;
        context.pop();
      } else {
        if (!mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const ErrorDialog(message: 'Failed to submit report'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);
    final ci = state.selectedCi;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.riderGreen,
        foregroundColor: Colors.white,
        title: const Text('CI Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (ci != null)
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: StatusBadge(status: ci.status, small: false)),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Upload Docs'),
            Tab(text: 'Submit Report')
          ],
        ),
      ),
      body: state.isLoading
          ? const ShimmerLoader()
          : ci == null
              ? const Center(child: Text('CI assignment not found'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDetailsTab(ci),
                    _buildUploadTab(),
                    _buildReportTab(ci),
                  ],
                ),
    );
  }

  Widget _buildDetailsTab(CreditInvestigationModel ci) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SectionCard(
            title: 'Lender Information',
            icon: Icons.person_outline,
            color: AppColors.lenderBlue,
            children: [
              _InfoTile(
                  'Name', ci.borrowerName.isEmpty ? 'N/A' : ci.borrowerName),
              _InfoTile(
                  'Loan #', ci.loanNumber.isEmpty ? 'N/A' : ci.loanNumber),
              _InfoTile('Address',
                  ci.borrowerAddress.isEmpty ? 'N/A' : ci.borrowerAddress),
              _InfoTile(
                  'Phone', ci.borrowerPhone.isEmpty ? 'N/A' : ci.borrowerPhone),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Assignment Details',
            icon: Icons.assignment_outlined,
            color: AppColors.riderGreen,
            children: [
              _InfoTile('Assigned By',
                  ci.assignedByName.isEmpty ? 'N/A' : ci.assignedByName),
              _InfoTile('Assigned At',
                  DateFormat('MMM d, yyyy h:mm a').format(ci.assignedAt)),
              _InfoTile(
                  'Deadline',
                  ci.deadline != null
                      ? DateFormat('MMM d, yyyy').format(ci.deadline!)
                      : 'N/A'),
              if (ci.investigationNotes != null &&
                  ci.investigationNotes!.isNotEmpty)
                _InfoTile('Notes', ci.investigationNotes!),
            ],
          ),
          if (ci.status == 'assigned') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await ref
                          .read(riderCiProvider.notifier)
                          .decline(ci.id);
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
                      await ref.read(riderCiProvider.notifier).accept(ci.id);
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
          if (ci.status == 'accepted' || ci.status == 'in_progress') ...[
            const SizedBox(height: 16),
            AppButton(
              label: 'Navigate to Lender',
              onPressed: () {},
              icon: Icons.map_outlined,
              color: AppColors.info,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upload Evidence Photos',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
              'Upload photos of the lender\'s residence, neighborhood, and supporting evidence.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.3),
                    style: BorderStyle.none),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: AppColors.riderGreen.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  const Text('Tap to add photos',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          if (_pickedImages.isNotEmpty) ...[
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: _pickedImages.length,
              itemBuilder: (ctx, i) => Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: XFilePreview(file: _pickedImages[i])),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _pickedImages.removeAt(i)),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                            color: AppColors.error, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: _isSubmitting ? 'Uploading...' : 'Upload Photos',
              onPressed: _isSubmitting ? null : _uploadDocuments,
              color: AppColors.riderGreen,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportTab(CreditInvestigationModel ci) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Investigation Report',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
              'Write your complete credit investigation report. Include observations, findings, and recommendation.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          TextField(
            controller: _reportCtrl,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: 'Write your investigation findings here...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.riderGreen, width: 2)),
            ),
          ),
          const SizedBox(height: 20),
          if (ci.status == 'accepted' || ci.status == 'in_progress')
            AppButton(
              label: _isSubmitting ? 'Submitting...' : 'Submit Report',
              onPressed: _isSubmitting ? null : _submitReport,
              color: AppColors.riderGreen,
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'You must accept the assignment before submitting a report.',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.warning))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  const _SectionCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: color)),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
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
