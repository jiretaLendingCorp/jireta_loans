// lib/presentation/features/employee/ci/screens/emp_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../ci/providers/emp_ci_provider.dart';
import '../../ci/widgets/emp_ci_assign_modal.dart';

class EmpCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const EmpCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<EmpCiDetailsScreen> createState() => _EmpCiDetailsScreenState();
}

class _EmpCiDetailsScreenState extends ConsumerState<EmpCiDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empCiProvider.notifier).loadDetails(widget.ciId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empCiProvider);
    final ci = state.detail;

    return WebScaffold(
      title: 'CI Details',
      body: state.isLoadingDetail
          ? const ShimmerLoader()
          : ci == null
              ? const Center(child: Text('Investigation not found'))
              : _buildBody(ci),
    );
  }

  Widget _buildBody(Map<String, dynamic> ci) {
    final status = ci['status'] as String? ?? 'pending';
    final loanNumber = ci['loan_number'] as String? ?? '–';
    final lenderName = ci['lender_name'] as String? ?? '–';
    final riderName = ci['rider_name'] as String? ?? 'Unassigned';
    final deadline = ci['deadline'] as String?;
    final notes = ci['investigation_notes'] as String? ?? '–';
    final reportSummary = ci['report_summary'] as String?;
    final documents =
        (ci['ci_documents'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final assignedBy = ci['assigned_by_name'] as String? ?? '–';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(ci, status, loanNumber, lenderName),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 2,
                  child: _buildDetails(
                      ci, riderName, deadline, notes, assignedBy)),
              const SizedBox(width: 24),
              Expanded(
                  flex: 3,
                  child: _buildDocuments(documents, reportSummary, status)),
            ],
          ),
          if (status == 'pending' || status == 'ci_required') ...[
            const SizedBox(height: 24),
            _buildAssignAction(ci),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> ci, String status, String loanNumber,
      String lenderName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.search, color: AppColors.deepNavy, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'CI – $loanNumber',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lender: $lenderName',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(Map<String, dynamic> ci, String riderName,
      String? deadline, String notes, String assignedBy) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Investigation Details',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _detailRow('Assigned Rider', riderName, icon: Icons.delivery_dining),
          _detailRow('Assigned By', assignedBy, icon: Icons.person),
          _detailRow(
            'Deadline',
            deadline != null
                ? DateTime.parse(deadline).toDisplay()
                : 'No deadline',
            icon: Icons.event,
            valueColor: deadline != null &&
                    DateTime.parse(deadline).isBefore(DateTime.now())
                ? AppColors.error
                : null,
          ),
          _detailRow(
            'Created',
            ci['created_at'] != null
                ? DateTime.parse(ci['created_at'] as String).toDisplay()
                : '–',
            icon: Icons.schedule,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Investigation Notes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              notes,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {IconData? icon, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
          ],
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocuments(List<Map<String, dynamic>> documents,
      String? reportSummary, String status) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidence & Report',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (reportSummary != null && reportSummary.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.summarize, color: AppColors.success, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Investigation Report Summary',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reportSummary,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (documents.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 48, color: AppColors.textTertiary),
                    SizedBox(height: 12),
                    Text(
                      'No evidence uploaded yet',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Evidence Photos (${documents.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: documents.length,
              itemBuilder: (context, i) {
                final doc = documents[i];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceGray,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image,
                          size: 32, color: AppColors.textTertiary),
                      const SizedBox(height: 4),
                      Text(
                        doc['document_type'] as String? ?? 'Photo',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignAction(Map<String, dynamic> ci) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assign Rider',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Assign an available rider to conduct the credit investigation.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showAssignModal(ci),
            icon: const Icon(Icons.delivery_dining, size: 16),
            label: const Text('Assign Rider for CI'),
          ),
        ],
      ),
    );
  }

  void _showAssignModal(Map<String, dynamic> ci) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmpCiAssignModal(
        loanId: ci['loan_id'] as String? ?? '',
        ciId: ci['id'] as String? ?? '',
      ),
    );
  }
}
