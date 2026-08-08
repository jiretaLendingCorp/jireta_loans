// lib/presentation/features/head_manager/kyc/screens/hm_kyc_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/kyc_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';

class HmKycDetailsScreen extends ConsumerStatefulWidget {
  final String lenderId;
  const HmKycDetailsScreen({super.key, required this.lenderId});

  @override
  ConsumerState<HmKycDetailsScreen> createState() => _HmKycDetailsScreenState();
}

class _HmKycDetailsScreenState extends ConsumerState<HmKycDetailsScreen> {
  final _ds = sl<KycRemoteDataSource>();
  Map<String, dynamic>? _data;
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
      final res = await _ds.getDetails(lenderId: widget.lenderId);
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorHandler.handle(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _verifyAll(String action) async {
    if (action == 'rejected' && _rejectionCtrl.text.trim().isEmpty) {
      showErrorSnackBar(context, 'Please enter rejection notes.');
      return;
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: action == 'verified' ? 'Verify All Documents' : 'Reject All Documents',
      message: action == 'verified'
          ? 'Verify the lender\'s entire KYC submission at once?'
          : 'Reject the lender\'s entire KYC submission? They will be notified.',
      confirmLabel: action == 'verified' ? 'Verify All' : 'Reject All',
      isDangerous: action == 'rejected',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _ds.verifyAllKyc(
        lenderId: widget.lenderId,
        action: action,
        rejectionNotes: action == 'rejected' ? _rejectionCtrl.text.trim() : null,
      );
      if (mounted) {
        showSuccessSnackBar(
            context,
            action == 'verified'
                ? 'All documents verified successfully.'
                : 'All documents rejected.');
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
              : _data == null
                  ? const Center(child: Text('KYC data not found.'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final data = _data!;
    final lender = (data['lender'] as Map<String, dynamic>?) ?? {};
    final docs = (data['documents'] as List?) ?? [];
    final contacts = (data['emergency_contacts'] as List?) ?? [];
    final kycStatus = (data['kyc_status'] as String?) ?? 'pending';

    final pendingDocs =
        docs.where((d) => (d as Map<String, dynamic>)['status'] == 'pending').toList();

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
                  title: 'Lender Information',
                  child: Column(
                    children: [
                      _InfoRow('Full Name',
                          '${lender['first_name'] ?? ''} ${lender['middle_name'] ?? ''} ${lender['last_name'] ?? ''}'
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim()),
                      _InfoRow('Phone', lender['phone_number'] ?? '—'),
                      _InfoRow('Email', lender['email'] ?? '—'),
                      _InfoRow('KYC Status', kycStatus),
                      _InfoRow(
                        'Address',
                        [
                          lender['street_address'],
                          lender['barangay'],
                          lender['city'],
                          lender['province'],
                          lender['zip_code'],
                        ]
                            .where((e) =>
                                e != null && e.toString().isNotEmpty)
                            .join(', ')
                            .isEmpty
                            ? '—'
                            : [
                                lender['street_address'],
                                lender['barangay'],
                                lender['city'],
                                lender['province'],
                                lender['zip_code'],
                              ]
                                .where((e) =>
                                    e != null && e.toString().isNotEmpty)
                                .join(', '),
                      ),
                      _InfoRow('Source of Funds', lender['source_of_funds'] ?? '—'),
                      _InfoRow('Employment', lender['employment_type'] ?? '—'),
                      _InfoRow('Employer', lender['employer_name'] ?? '—'),
                      _InfoRow('Monthly Income',
                          lender['monthly_income'] != null
                              ? '₱${lender['monthly_income']}'
                              : '—'),
                      _InfoRow('GCash', lender['gcash_number'] ?? '—'),
                      _InfoRow('Gender', lender['gender'] ?? '—'),
                      _InfoRow('Civil Status', lender['civil_status'] ?? '—'),
                      _InfoRow(
                          'Date of Birth', lender['date_of_birth'] ?? '—'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Submitted Documents',
                  child: docs.isEmpty
                      ? const Text('No documents submitted.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13))
                      : Column(
                          children: docs.map((doc) {
                            final d = doc as Map<String, dynamic>;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          d['document_type'] ?? 'Document',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      StatusBadge(status: d['status'] ?? 'pending'),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (d['created_at'] != null)
                                    Text(
                                      'Submitted: ${d['created_at']}'.substring(0, 32),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  if (d['rejection_notes'] != null &&
                                      (d['rejection_notes'] as String).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Note: ${d['rejection_notes']}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.error),
                                      ),
                                    ),
                                  if (d['file_url'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(Icons.open_in_new,
                                            size: 14),
                                        label: const Text('View Document',
                                            style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6)),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Emergency Contact',
                    child: Column(
                      children: contacts.map((c) {
                        final m = c as Map<String, dynamic>;
                        return _InfoRow(
                            '${m['name'] ?? '—'} (${m['relationship'] ?? '—'})',
                            m['phone_number'] ?? '—');
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _SectionCard(
                  title: 'Review Actions',
                  child: pendingDocs.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: AppColors.success, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'All documents reviewed.',
                                  style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'One action verifies the lender\'s entire KYC submission.',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: _submitting
                                  ? null
                                  : () => _verifyAll('verified'),
                              icon: const Icon(
                                  Icons.verified_outlined,
                                  size: 18),
                              label: Text(
                                  'Verify All (${pendingDocs.length})'),
                            ),
                            const Divider(height: 28),
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
                                side:
                                    const BorderSide(color: AppColors.error),
                              ),
                              onPressed: _submitting
                                  ? null
                                  : () => _verifyAll('rejected'),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Reject All'),
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
