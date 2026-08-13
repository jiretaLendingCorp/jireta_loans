// lib/presentation/features/employee/collections/screens/emp_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../providers/emp_collection_provider.dart';
import '../widgets/emp_assign_rider_modal.dart';

class EmpCollectionDetailsScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const EmpCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  ConsumerState<EmpCollectionDetailsScreen> createState() =>
      _EmpCollectionDetailsScreenState();
}

class _EmpCollectionDetailsScreenState
    extends ConsumerState<EmpCollectionDetailsScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    final data = await ref
        .read(empCollectionListProvider.notifier)
        .getDetail(widget.collectionId);
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  Future<void> _reassign() async {
    if (_detail == null) return;
    await showDialog(
      context: context,
      builder: (_) => EmpAssignRiderModal(
        loanScheduleId: _detail!['loan_schedule_id'] as String? ?? '',
        onAssigned: () {
          _loadDetail();
          showSuccessDialog(context, message: 'Rider reassigned successfully.');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const WebScaffold(
          title: 'Collection Details', body: ShimmerLoader());
    }
    if (_detail == null) {
      return const WebScaffold(
          title: 'Collection Details',
          body: Center(child: Text('Collection not found.')));
    }

    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final status = _detail!['status'] as String? ?? '';
    final canReassign = ['assigned', 'declined'].contains(status);

    return WebScaffold(
      title: 'Collection Details',
      actions: [
        if (canReassign)
          ElevatedButton.icon(
            onPressed: _reassign,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Reassign Rider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
            ),
          ),
        const SizedBox(width: 12),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              title: 'Assignment Overview',
              child: Column(
                children: [
                  _InfoRow('Loan Number', _detail!['loan_number'] ?? '-'),
                  _InfoRow('Lender', _detail!['lender_name'] ?? '-'),
                  _InfoRow('Status', '', badge: status),
                  _InfoRow('Assigned By', _detail!['assigned_by_name'] ?? '-'),
                  _InfoRow('Assignment Date', _detail!['created_at'] ?? '-'),
                  _InfoRow('Amount Due',
                      '₱${fmt.format((_detail!['amount_due'] as num?)?.toDouble() ?? 0)}'),
                  if (_detail!['collection_schedule'] != null)
                    _InfoRow(
                        'Collection Schedule', _detail!['collection_schedule']),
                  if (_detail!['notes'] != null)
                    _InfoRow('Notes', _detail!['notes']),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Rider Information',
              child: Column(
                children: [
                  _InfoRow(
                      'Rider Name', _detail!['rider_name'] ?? 'Unassigned'),
                  _InfoRow('Rider Phone', _detail!['rider_phone'] ?? '-'),
                  _InfoRow('Response', _detail!['response_at'] ?? 'Pending'),
                ],
              ),
            ),
            if (_detail!['amount_collected'] != null) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Collection Result',
                child: Column(
                  children: [
                    _InfoRow('Amount Collected',
                        '₱${fmt.format((_detail!['amount_collected'] as num?)?.toDouble() ?? 0)}'),
                    _InfoRow('Collection Notes',
                        _detail!['collection_notes'] ?? '-'),
                    _InfoRow('Completed At', _detail!['completed_at'] ?? '-'),
                  ],
                ),
              ),
            ],
            if (_detail!['proof_photo'] != null ||
                _detail!['borrower_signature'] != null) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Proof of Collection',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_detail!['proof_photo'] != null)
                      _ProofImage(
                        label: 'Payment Proof',
                        url: _detail!['proof_photo'],
                      ),
                    if (_detail!['borrower_signature'] != null)
                      _ProofImage(
                        label: 'Borrower Signature',
                        url: _detail!['borrower_signature'],
                      ),
                    if (_detail!['collection_photo'] != null)
                      _ProofImage(
                        label: 'Scene Photo',
                        url: _detail!['collection_photo'],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.deepNavy)),
          ),
          const Divider(height: 24),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: child),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  const _InfoRow(this.label, this.value, {this.badge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          badge != null
              ? StatusBadge(status: badge!)
              : Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                ),
        ],
      ),
    );
  }
}

class _ProofImage extends StatelessWidget {
  final String label;
  final String url;
  const _ProofImage({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 160,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 160,
              height: 120,
              color: AppColors.surfaceVariant,
              child: const Icon(Icons.broken_image_outlined,
                  color: AppColors.textTertiary),
            ),
          ),
        ),
      ],
    );
  }
}
