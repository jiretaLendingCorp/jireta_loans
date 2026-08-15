// lib/presentation/features/employee/account_upgrade/screens/emp_account_upgrade_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/emp_account_upgrade_provider.dart';

final _empAccountUpgradeDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, lenderId) {
  return ref
      .read(empAccountUpgradeProvider.notifier)
      .getDetails(lenderId: lenderId);
});

class EmpAccountUpgradeDetailsScreen extends ConsumerStatefulWidget {
  final String lenderId;
  const EmpAccountUpgradeDetailsScreen({super.key, required this.lenderId});
  @override
  ConsumerState<EmpAccountUpgradeDetailsScreen> createState() => _State();
}

class _State extends ConsumerState<EmpAccountUpgradeDetailsScreen> {
  bool _busy = false;

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final signedUrl = doc['signed_url'] as String?;
    final filePath = doc['file_url'] as String?;
    try {
      String url;
      if (signedUrl != null && signedUrl.isNotEmpty) {
        url = signedUrl;
      } else if (filePath != null && filePath.startsWith('http')) {
        url = filePath;
      } else if (filePath != null) {
        url = await SupabaseStorageService.instance
            .getSignedUrl(bucket: 'account-upgrade-documents', path: filePath);
      } else {
        return;
      }
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to open document.'),
            backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to open document: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_empAccountUpgradeDetailProvider(widget.lenderId));
    return WebScaffold(
      title: 'Account Upgrade Review',
      body: async.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(24), child: ShimmerLoader(height: 400)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => data == null
            ? const Center(child: Text('Account upgrade data not found'))
            : _buildBody(data),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final docs = (data['documents'] as List?) ?? [];
    final lender = data['lender'] as Map<String, dynamic>?;
    final accountUpgradeStatus = data['account_upgrade_status'] ?? 'pending';
    final contacts = (data['emergency_contacts'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoCard(lender, accountUpgradeStatus),
            const SizedBox(height: 16),
            _financialCard(lender),
            const SizedBox(height: 16),
            _emergencyCard(contacts),
            const SizedBox(height: 16),
            _docsCard(docs),
          ]);
          if (stacked) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              leftColumn,
              const SizedBox(height: 16),
              _actionCard(docs, accountUpgradeStatus),
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: leftColumn),
              const SizedBox(width: 16),
              Expanded(child: _actionCard(docs, accountUpgradeStatus)),
            ],
          );
        },
      ),
    );
  }

  String _label(dynamic value) {
    if (value == null || value.toString().isEmpty) return '—';
    final s = value.toString();
    return s
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _address(Map<String, dynamic>? lender) {
    final parts = [
      lender?['street_address'],
      lender?['barangay'],
      lender?['city'],
      lender?['province'],
      lender?['zip_code'],
    ].where((e) => e != null && e.toString().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Widget _infoCard(Map<String, dynamic>? lender, String accountUpgradeStatus) {
    final name = lender != null
        ? [
            lender['first_name'],
            lender['middle_name'],
            lender['last_name'],
            lender['suffix'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(' ').trim()
        : 'N/A';
    return _Card(
        title: 'Personal Information',
        icon: Icons.person_outline,
        children: [
          Center(
            child: ProfileAvatar(
              photoUrl: lender?['profile_photo_url'] as String?,
              name: name == 'N/A' ? '' : name,
              color: AppColors.lenderBlue,
              radius: 32,
              fallback: const Icon(Icons.person_outline,
                  size: 28, color: AppColors.lenderBlue),
            ),
          ),
          const SizedBox(height: 12),
          _row('Full Name', name),
          _row('Phone', lender?['phone_number'] ?? 'N/A'),
          _row('Account Upgrade Status', accountUpgradeStatus),
          _row('Gender', _label(lender?['gender'])),
          _row('Civil Status', _label(lender?['civil_status'])),
          _row('Date of Birth', lender?['date_of_birth'] ?? '—'),
          _row('Address', _address(lender)),
        ]);
  }

  Widget _financialCard(Map<String, dynamic>? lender) {
    return _Card(
        title: 'Financial Details',
        icon: Icons.account_balance_wallet_outlined,
        children: [
          _row('Employment', _label(lender?['employment_type'])),
          _row('Employer', lender?['employer_name'] ?? '—'),
          _row(
              'Monthly Income',
              lender?['monthly_income'] != null
                  ? '₱${lender?['monthly_income']}'
                  : '—'),
          _row('GCash', lender?['gcash_number'] ?? '—'),
          _row('Source of Funds', _label(lender?['source_of_funds'])),
        ]);
  }

  Widget _emergencyCard(List contacts) {
    if (contacts.isEmpty) {
      return const _Card(
          title: 'Emergency Contact',
          icon: Icons.emergency_outlined,
          children: [
            Text('No emergency contact provided',
                style: TextStyle(color: AppColors.textSecondary))
          ]);
    }
    return _Card(
        title: 'Emergency Contact',
        icon: Icons.emergency_outlined,
        children: contacts.map((c) {
          final m = c as Map<String, dynamic>;
          return Column(children: [
            _row('Name', m['name'] ?? '—'),
            _row('Relationship', m['relationship'] ?? '—'),
            _row('Phone', m['phone_number'] ?? '—'),
            if (m['address'] != null && m['address'].toString().isNotEmpty)
              _row('Address', m['address'].toString()),
          ]);
        }).toList());
  }

  Widget _docsCard(List docs) {
    if (docs.isEmpty) {
      return const _Card(
          title: 'Documents',
          icon: Icons.folder_outlined,
          children: [
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
                      Flexible(
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(
                                d['document_type'] ??
                                    d['doc_type'] ??
                                    'Document',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.info))),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(status: d['status'] ?? 'pending'),
                    ]),
                    const SizedBox(height: 8),
                    if (d['submitted_at'] != null)
                      Text(
                          'Submitted: ${DateTime.tryParse(d['submitted_at'])?.toDisplayDate ?? '—'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    if (d['created_at'] != null && d['submitted_at'] == null)
                      Text(
                          'Submitted: ${DateTime.tryParse(d['created_at'])?.toDisplayDate ?? '—'}',
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
                          onPressed: () => _openDocument(d),
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

  Widget _actionCard(List docs, String accountUpgradeStatus) {
    final pendingDocs = docs
        .where((d) => (d as Map<String, dynamic>)['status'] == 'pending')
        .toList();
    return _Card(
        title: 'Review Actions',
        icon: Icons.check_circle_outline,
        children: [
          const SizedBox(height: 8),
          if (pendingDocs.isNotEmpty) ...[
            const Text(
                'One action verifies the lender\'s entire account upgrade submission.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _verifyAll('verified'),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: Text('Verify All (${pendingDocs.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
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

  Future<void> _verifyAll(String action) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(empAccountUpgradeProvider.notifier)
        .verifyAll(lenderId: widget.lenderId, action: action);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(ok ? 'All documents $action successfully' : 'Action failed'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ));
      if (ok) ref.invalidate(_empAccountUpgradeDetailProvider(widget.lenderId));
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
