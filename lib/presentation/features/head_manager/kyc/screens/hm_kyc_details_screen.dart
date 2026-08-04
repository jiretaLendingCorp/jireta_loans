// lib/presentation/features/head_manager/kyc/screens/hm_kyc_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/kyc_remote_datasource.dart';
import '../../../../../data/models/kyc_document_model.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';

class HmKycDetailsScreen extends ConsumerStatefulWidget {
  final String kycId;
  const HmKycDetailsScreen({super.key, required this.kycId});

  @override
  ConsumerState<HmKycDetailsScreen> createState() => _HmKycDetailsScreenState();
}

class _HmKycDetailsScreenState extends ConsumerState<HmKycDetailsScreen> {
  final _ds = sl<KycRemoteDataSource>();
  KycDocumentModel? _doc;
  bool _loading = true;
  String? _error;
  final _rejectionCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rejectionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _ds.getKycDetails(kycDocId: widget.kycId);
      setState(() {
        _doc = res;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorHandler.handle(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _verify(String action) async {
    if (action == 'rejected' && _rejectionCtrl.text.trim().isEmpty) {
      showErrorSnackBar(context, 'Please enter rejection notes.');
      return;
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: action == 'verified' ? 'Verify Document' : 'Reject Document',
      message: action == 'verified'
          ? 'Mark this KYC document as verified?'
          : 'Reject this KYC document? The lender will be notified.',
      confirmLabel: action == 'verified' ? 'Verify' : 'Reject',
      isDangerous: action == 'rejected',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _ds.verifyKyc(
        kycDocId: widget.kycId,
        action: action,
        rejectionNotes:
            action == 'rejected' ? _rejectionCtrl.text.trim() : null,
      );
      if (mounted) {
        showSuccessSnackBar(
            context,
            action == 'verified'
                ? 'Document verified successfully.'
                : 'Document rejected.');
        await _load();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'Action failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      title: 'KYC Details',
      body: _loading
          ? const ShimmerLoader()
          : _error != null
              ? Center(child: Text(_error!))
              : _doc == null
                  ? const Center(child: Text('Document not found.'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final doc = _doc!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionCard(
                  title: 'KYC Document Info',
                  child: Column(
                    children: [
                      _InfoRow('Lender', doc.lenderName),
                      _InfoRow('Document Type', doc.documentType),
                      _InfoRow('Status', doc.status),
                      _InfoRow(
                        'Submitted',
                        doc.submittedAt.toString().substring(0, 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (doc.fileUrl != null)
                  _SectionCard(
                    title: 'Document Preview',
                    child: Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_outlined,
                              size: 48, color: AppColors.textTertiary),
                          const SizedBox(height: 8),
                          Text(
                            doc.fileUrl ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('View Document'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _SectionCard(
                  title: 'Actions',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatusBadge(status: doc.status),
                      const SizedBox(height: 16),
                      if (doc.status == 'submitted' ||
                          doc.status == 'pending') ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.riderGreen,
                          ),
                          onPressed:
                              _submitting ? null : () => _verify('verified'),
                          icon:
                              const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Verify Document'),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _rejectionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Rejection Notes',
                            hintText: 'Required when rejecting...',
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                          onPressed:
                              _submitting ? null : () => _verify('rejected'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Reject Document'),
                        ),
                      ] else
                        Text(
                          'This document has been ${doc.status}.',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
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
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
