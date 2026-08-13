// lib/presentation/features/head_manager/ci/screens/hm_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';

final _ciDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, ciId) async {
  final ds = sl<CiRemoteDataSource>();
  return ds.getCiDetails(ciId);
});

final _availableRidersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final ds = sl<UserRemoteDataSource>();
  return ds.getAvailableRiders();
});

class HmCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const HmCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<HmCiDetailsScreen> createState() => _HmCiDetailsScreenState();
}

class _HmCiDetailsScreenState extends ConsumerState<HmCiDetailsScreen> {
  final _fmt = NumberFormat('#,##0.00', 'en_PH');
  final _dateFmt = DateFormat('MMM d, yyyy h:mm a');

  @override
  Widget build(BuildContext context) {
    final ciAsync = ref.watch(_ciDetailProvider(widget.ciId));

    return WebScaffold(
      title: 'CI Assignment Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(RouteConstants.hmCi),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to CI List'),
        ),
        const SizedBox(width: 12),
      ],
      body: ciAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (ci) => ci == null
            ? const Center(child: Text('CI assignment not found'))
            : _buildContent(context, ci),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> ci) {
    final status = ci['status'] as String? ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(ci, status),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBorrowerCard(ci)),
              const SizedBox(width: 20),
              Expanded(child: _buildAssignmentCard(ci)),
            ],
          ),
          const SizedBox(height: 20),
          if ((ci['report_summary'] as String?)?.isNotEmpty == true)
            _buildReportCard(ci),
          if ((ci['ci_documents'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            _buildDocumentsCard(ci),
          ],
          if (status == 'pending' || status == 'declined') ...[
            const SizedBox(height: 20),
            _buildAssignRiderSection(context, ci),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> ci, String status) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.search_outlined,
                  color: AppColors.lenderBlue, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CI-${ci['id'].toString().substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Loan: ${ci['loan']?['loan_number'] ?? 'N/A'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            StatusBadge(status: status),
          ],
        ),
      ),
    );
  }

  Widget _buildBorrowerCard(Map<String, dynamic> ci) {
    final loan = ci['loan'] as Map<String, dynamic>? ?? {};
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final addresses = ci['borrower_addresses'] as List? ?? [];

    return _InfoCard(
      title: 'Borrower Information',
      icon: Icons.person_outline,
      children: [
        _InfoRow(
            'Name',
            '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                .trim()),
        _InfoRow('Phone', lender['phone_number'] ?? 'N/A'),
        _InfoRow(
            'Loan Amount',
            ci['loan']?['principal_amount'] != null
                ? '₱${_fmt.format((ci['loan']['principal_amount'] as num).toDouble())}'
                : 'N/A'),
        if (addresses.isNotEmpty)
          _InfoRow('Primary Address',
              _formatAddress(addresses.first as Map<String, dynamic>)),
        _InfoRow('CI Notes', ci['investigation_notes'] ?? 'None'),
        _InfoRow(
            'Deadline',
            ci['deadline'] != null
                ? DateFormat('MMM d, yyyy')
                    .format(DateTime.parse(ci['deadline']))
                : 'N/A'),
      ],
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> ci) {
    final rider = ci['rider'] as Map<String, dynamic>? ?? {};
    final assignedBy = ci['assigned_by_user'] as Map<String, dynamic>? ?? {};

    return _InfoCard(
      title: 'Assignment Details',
      icon: Icons.assignment_outlined,
      children: [
        _InfoRow('Status', ci['status'] ?? 'N/A'),
        _InfoRow(
            'Assigned Rider',
            rider.isNotEmpty
                ? '${rider['first_name'] ?? ''} ${rider['last_name'] ?? ''}'
                    .trim()
                : 'Not Assigned'),
        _InfoRow(
            'Assigned By',
            assignedBy.isNotEmpty
                ? '${assignedBy['first_name'] ?? ''} ${assignedBy['last_name'] ?? ''}'
                    .trim()
                : 'N/A'),
        _InfoRow(
            'Assigned At',
            ci['assigned_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['assigned_at']))
                : 'N/A'),
        _InfoRow(
            'Accepted At',
            ci['response_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['response_at']))
                : 'N/A'),
        _InfoRow(
            'Completed At',
            ci['completed_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['completed_at']))
                : 'N/A'),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> ci) {
    return _InfoCard(
      title: 'Investigation Report',
      icon: Icons.article_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            ci['report_summary'] as String? ?? '',
            style: const TextStyle(
                fontSize: 14, height: 1.6, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsCard(Map<String, dynamic> ci) {
    final docs = (ci['ci_documents'] as List?) ?? [];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library_outlined,
                    color: AppColors.deepNavy, size: 20),
                const SizedBox(width: 8),
                Text('Evidence Photos (${docs.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i] as Map<String, dynamic>;
                return _DocumentThumbnail(doc: doc);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignRiderSection(
      BuildContext context, Map<String, dynamic> ci) {
    final ridersAsync = ref.watch(_availableRidersProvider);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_ind_outlined,
                    color: AppColors.gold, size: 20),
                SizedBox(width: 8),
                Text('Assign Rider for CI',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            ridersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load riders: $e'),
              data: (riders) => _AssignRiderForm(
                ciId: widget.ciId,
                loanId: ci['loan_id'] as String? ?? '',
                riders: riders,
                onAssigned: () =>
                    ref.invalidate(_ciDetailProvider(widget.ciId)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAddress(Map<String, dynamic> addr) {
    final parts = [
      addr['street'],
      addr['barangay'],
      addr['city'],
      addr['province']
    ];
    return parts.where((p) => p != null && p.toString().isNotEmpty).join(', ');
  }
}

class _AssignRiderForm extends ConsumerStatefulWidget {
  final String ciId;
  final String loanId;
  final List<Map<String, dynamic>> riders;
  final VoidCallback onAssigned;

  const _AssignRiderForm({
    required this.ciId,
    required this.loanId,
    required this.riders,
    required this.onAssigned,
  });

  @override
  ConsumerState<_AssignRiderForm> createState() => _AssignRiderFormState();
}

class _AssignRiderFormState extends ConsumerState<_AssignRiderForm> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _deadline;
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedRiderId,
          decoration: const InputDecoration(
            labelText: 'Select Available Rider',
            border: OutlineInputBorder(),
          ),
          items: widget.riders.map((r) {
            return DropdownMenuItem<String>(
              value: r['id'] as String,
              child: Text('${r['first_name']} ${r['last_name']}'),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedRiderId = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Investigation Notes',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 3)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 30)),
            );
            if (d != null) setState(() => _deadline = d);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  _deadline != null
                      ? DateFormat('MMM d, yyyy').format(_deadline!)
                      : 'Select Deadline',
                  style: TextStyle(
                      color: _deadline != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _selectedRiderId == null || _loading ? null : _assign,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Assign Rider',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Future<void> _assign() async {
    if (_selectedRiderId == null) return;
    setState(() => _loading = true);
    try {
      final ds = sl<CiRemoteDataSource>();
      await ds.assignCi(
        loanId: widget.loanId,
        riderId: _selectedRiderId!,
        investigationNotes: _notesCtrl.text.trim(),
        deadline: _deadline?.toIso8601String(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Rider assigned successfully'),
              backgroundColor: AppColors.success),
        );
        widget.onAssigned();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _DocumentThumbnail extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocumentThumbnail({required this.doc});

  @override
  Widget build(BuildContext context) {
    final url = doc['file_url'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppColors.surfaceVariant,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: url.isNotEmpty
                ? Image.network(url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textTertiary))
                : const Icon(Icons.photo_outlined,
                    color: AppColors.textTertiary),
          ),
          if ((doc['caption'] as String?)?.isNotEmpty == true)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  doc['caption'] as String,
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.deepNavy, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
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
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
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
