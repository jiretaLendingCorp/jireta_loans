// lib/presentation/features/employee/kyc/screens/emp_kyc_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_kyc_provider.dart';

final _empKycDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, lenderId) {
  return ref.read(empKycProvider.notifier).getStatus(lenderId);
});

class EmpKycDetailsScreen extends ConsumerStatefulWidget {
  final String kycId;
  const EmpKycDetailsScreen({super.key, required this.kycId});
  @override
  ConsumerState<EmpKycDetailsScreen> createState() => _State();
}

class _State extends ConsumerState<EmpKycDetailsScreen> {
  final _remarksCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_empKycDetailProvider(widget.kycId));
    return WebScaffold(
      title: 'KYC Review',
      body: async.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(24), child: ShimmerLoader(height: 400)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => data == null
            ? const Center(child: Text('KYC data not found'))
            : _buildBody(data),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final docs = (data['documents'] as List?) ?? [];
    final lender = data['lender'] as Map<String, dynamic>?;
    final kycStatus = data['kyc_status'] ?? 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 2,
            child: Column(children: [
              _infoCard(lender, kycStatus),
              const SizedBox(height: 16),
              _docsCard(docs),
            ])),
        const SizedBox(width: 16),
        Expanded(child: _actionCard(docs, kycStatus)),
      ]),
    );
  }

  Widget _infoCard(Map<String, dynamic>? lender, String kycStatus) {
    final name = lender != null
        ? '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
        : 'N/A';
    return _Card(
        title: 'Lender Information',
        icon: Icons.person_outline,
        children: [
          _row('Name', name.trim()),
          _row('Phone', lender?['phone_number'] ?? 'N/A'),
          _row('KYC Status', kycStatus),
        ]);
  }

  Widget _docsCard(List docs) {
    if (docs.isEmpty) {
      return const _Card(title: 'Documents', icon: Icons.folder_outlined, children: [
        Text('No documents submitted',
            style: TextStyle(color: AppColors.textSecondary))
      ]);
    }
    return _Card(
        title: 'Submitted Documents',
        icon: Icons.folder_outlined,
        children: [
          ...docs.map((doc) {
            final d = doc as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(d['doc_type'] ?? 'Document',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.info))),
                      const Spacer(),
                      StatusBadge(status: d['status'] ?? 'pending'),
                    ]),
                    const SizedBox(height: 8),
                    if (d['submitted_at'] != null)
                      Text(
                          'Submitted: ${DateTime.tryParse(d['submitted_at'])?.toDisplayDate ?? '—'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    if (d['rejection_notes'] != null &&
                        (d['rejection_notes'] as String).isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Note: ${d['rejection_notes']}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.error))),
                    if (d['file_url'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('View Document',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6)),
                        ),
                      ),
                  ]),
            );
          }),
        ]);
  }

  Widget _actionCard(List docs, String kycStatus) {
    final pendingDocs = docs
        .where((d) => (d as Map<String, dynamic>)['status'] == 'submitted')
        .toList();
    return _Card(
        title: 'Review Actions',
        icon: Icons.check_circle_outline,
        children: [
          const SizedBox(height: 8),
          if (pendingDocs.isNotEmpty) ...[
            const Text('Select document to review:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ...pendingDocs.map((doc) {
              final d = doc as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['doc_type'] ?? 'Document',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _remarksCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                            hintText: 'Rejection reason (optional)...',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.all(10)),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _verify(d['id'] ?? '', 'verified', null),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Verify'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10)),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _verify(
                                  d['id'] ?? '',
                                  'rejected',
                                  _remarksCtrl.text.trim().isEmpty
                                      ? null
                                      : _remarksCtrl.text.trim()),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10)),
                        )),
                      ]),
                    ]),
              );
            }),
          ] else
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('All documents reviewed.',
                          style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w500)))
                ]))
        ]);
  }

  Future<void> _verify(String docId, String action, String? notes) async {
    if (docId.isEmpty) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(empKycProvider.notifier)
        .verify(kycDocId: docId, action: action, rejectionNotes: notes);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Document $action successfully' : 'Action failed'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ));
      if (ok) ref.invalidate(_empKycDetailProvider(widget.kycId));
    }
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Text(l,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
              flex: 3,
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Card(
      {required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) => Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.deepNavy),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700))
            ]),
            const Divider(height: 20),
            ...children,
          ])));
}
