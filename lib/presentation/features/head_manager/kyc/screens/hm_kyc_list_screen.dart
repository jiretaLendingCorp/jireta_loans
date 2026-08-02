// lib/presentation/features/head_manager/kyc/screens/hm_kyc_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/tables/table_filter_bar.dart';
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/hm_kyc_provider.dart';

class HmKycListScreen extends ConsumerStatefulWidget {
  const HmKycListScreen({super.key});

  @override
  ConsumerState<HmKycListScreen> createState() => _HmKycListScreenState();
}

class _HmKycListScreenState extends ConsumerState<HmKycListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmKycProvider);

    return WebScaffold(
      title: 'KYC Review',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmKycProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          buildFilterBar(
            searchController: _search,
            searchHint: 'Search lender name...',
            filters: [
              (
                label: 'Status',
                value: state.statusFilter,
                options: ['all', 'submitted', 'verified', 'rejected'],
                onChanged: (v) => ref.read(hmKycProvider.notifier).setStatus(v),
              ),
            ],
            onExport: null,
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.docs.isEmpty
                    ? _buildEmpty()
                    : _buildTable(context, state),
          ),
          if (state.totalPages > 1)
            TablePagination(
              currentPage: state.currentPage,
              totalPages: state.totalPages,
              totalCount: state.totalCount,
              onPageChange: (p) =>
                  ref.read(hmKycProvider.notifier).fetch(page: p),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, HmKycState state) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: state.docs.map((doc) {
            return _KycRow(
              doc: doc,
              onTap: () => context.go(
                RouteConstants.hmKycDetails.replaceFirst(':id', doc.id),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text(
            'No KYC submissions found',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _KycRow extends StatefulWidget {
  final dynamic doc;
  final VoidCallback onTap;

  const _KycRow({required this.doc, required this.onTap});

  @override
  State<_KycRow> createState() => _KycRowState();
}

class _KycRowState extends State<_KycRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final date =
        DateFormat('MMM d, y').format(doc.submittedAt ?? doc.createdAt);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.deepNavy.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.deepNavy.withValues(alpha: 0.2)
                  : AppColors.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.deepNavy.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    )
                  ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.info.withValues(alpha: 0.1),
                child: const Icon(Icons.verified_user_outlined,
                    size: 20, color: AppColors.info),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.lenderName ?? 'Unknown Lender',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Document Type: ${doc.documentType ?? 'KYC Submission'}  •  $date',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: doc.status),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
