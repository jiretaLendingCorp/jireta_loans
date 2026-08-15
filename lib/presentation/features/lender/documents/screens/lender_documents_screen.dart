// lib/presentation/features/lender/documents/screens/lender_documents_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/document_viewer.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_documents_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderDocumentsScreen extends ConsumerStatefulWidget {
  const LenderDocumentsScreen({super.key});

  @override
  ConsumerState<LenderDocumentsScreen> createState() => _State();
}

class _State extends ConsumerState<LenderDocumentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderDocumentsProvider.notifier).loadDocuments());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDocumentsProvider);

    return MobileScaffold(
      title: 'My Documents',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RouteConstants.lenderUploadDocument),
        backgroundColor: AppColors.lenderBlue,
        icon: const Icon(Icons.upload_file, color: Colors.white),
        label: const Text('Upload', style: TextStyle(color: Colors.white)),
      ),
      body: state.isLoading
          ? const ShimmerLoader()
          : state.documents.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.folder_outlined,
                  title: 'No Documents Uploaded',
                  subtitle:
                      'Upload your account upgrade documents and loan requirements to get started.',
                )
              : RefreshIndicator(
                  color: AppColors.lenderBlue,
                  onRefresh: () =>
                      ref.read(lenderDocumentsProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: state.documents.length,
                    itemBuilder: (ctx, i) => _DocumentCard(
                        key: ValueKey(state.documents[i].id),
                        doc: state.documents[i]),
                  ),
                ),
    );
  }
}

class _DocumentCard extends StatefulWidget {
  final dynamic doc;
  const _DocumentCard({super.key, required this.doc});

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _expanded = false;

  IconData _iconFor(String type) {
    switch (type) {
      case 'valid_id':
        return Icons.badge_outlined;
      case 'selfie':
        return Icons.face_outlined;
      case 'proof_of_billing':
        return Icons.receipt_outlined;
      case 'proof_of_income':
        return Icons.attach_money;
      case 'co_maker':
        return Icons.people_outline;
      default:
        return Icons.description_outlined;
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'valid_id':
        return 'Valid ID';
      case 'selfie':
        return 'Selfie / Photo';
      case 'proof_of_billing':
        return 'Proof of Billing';
      case 'proof_of_income':
        return 'Proof of Income';
      case 'co_maker':
        return 'Co-Maker Document';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docType = widget.doc.documentType as String? ?? '';
    final status = widget.doc.status as String? ?? 'pending';
    final uploadedAt = widget.doc.createdAt;
    final fileUrl = widget.doc.fileUrl as String? ?? '';
    final rejectionNotes = widget.doc.rejectionNotes as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.lenderBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconFor(docType),
                        color: AppColors.lenderBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_labelFor(docType),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        if (uploadedAt != null)
                          Text(
                            'Uploaded ${(uploadedAt is DateTime ? uploadedAt : DateTime.tryParse(uploadedAt.toString()) ?? DateTime.now()).toShortDate}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  StatusBadge(status: status),
                  const SizedBox(width: 8),
                  Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textTertiary,
                      size: 20),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (rejectionNotes != null && status == 'rejected')
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(rejectionNotes,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.error))),
                  ],
                ),
              ),
            if (fileUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: DocumentViewer(url: fileUrl),
              ),
          ],
        ],
      ),
    );
  }
}
