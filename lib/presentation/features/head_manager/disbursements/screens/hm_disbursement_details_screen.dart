// lib/presentation/features/head_manager/disbursements/screens/hm_disbursement_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/details/collection_proof_viewer.dart';

final _disbursementDetailProvider =
    FutureProvider.family<DisbursementModel?, String>((ref, id) async {
  final ds = sl<DisbursementRemoteDataSource>();
  return ds.getDisbursementDetail(id);
});

/// Opens disbursement details as a modal — ginagamit ng Disbursements tab sa
/// Loan Records imbes na full page (kasama ang Cash on Delivery proof).
Future<void> showHmDisbursementDetailsModal(
    BuildContext context, String disbursementId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Disbursement Details',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close,
                        size: 20, color: AppColors.textSecondary),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: HmDisbursementDetailsContent(
                  disbursementId: disbursementId),
            ),
          ],
        ),
      ),
    ),
  );
}

class HmDisbursementDetailsScreen extends ConsumerWidget {
  final String disbursementId;
  const HmDisbursementDetailsScreen({super.key, required this.disbursementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebScaffold(
      title: 'Disbursement Details',
      body: HmDisbursementDetailsContent(disbursementId: disbursementId),
    );
  }
}

class HmDisbursementDetailsContent extends ConsumerWidget {
  final String disbursementId;
  const HmDisbursementDetailsContent(
      {super.key, required this.disbursementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_disbursementDetailProvider(disbursementId));
    return async.when(
      loading: () => const Center(child: ShimmerLoader()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (d) => d == null
          ? const Center(child: Text('Disbursement not found'))
          : _buildBody(context, d),
    );
  }

  Widget _buildBody(BuildContext context, DisbursementModel d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      // Isang card na lang ang buong modal — naka-section sa loob.
      child: AppCard(
        borderRadius: BorderRadius.zero,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Disbursement Information'),
            const SizedBox(height: 14),
            _row('Amount', d.amount.toCurrency, valueStyle: _amountStyle),
            _row('Method', d.methodLabel),
            _row('Status', _prettyStatus(d.status)),
            if (d.reference.isNotEmpty) _row('Reference', d.reference),
            _row('Date',
                DateFormat('MMM dd, yyyy hh:mm a').format(d.createdAt)),
            _sectionBreak(),
            ..._methodSection(context, d),
          ],
        ),
      ),
    );
  }

  static const _amountStyle = TextStyle(
      fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.deepNavy);

  Widget _title(String text) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.deepNavy));

  /// Manipis na hati lang sa pagitan ng dalawang section sa iisang card.
  Widget _sectionBreak() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
      );

  /// Method-specific na section — nasa loob pa rin ng parehong card.
  List<Widget> _methodSection(BuildContext context, DisbursementModel d) {
    if (d.method == 'gcash') {
      return [
        _title('GCash Details'),
        const SizedBox(height: 14),
        _row('Xendit Disbursement ID', d.xenditDisbursementId ?? 'N/A'),
        _row('Xendit Status', d.xenditStatus ?? 'N/A'),
        if (d.disbursedAt != null)
          _row('Disbursed At',
              DateFormat('MMM dd, yyyy hh:mm a').format(d.disbursedAt!)),
      ];
    }
    if (d.method == 'office_cash') {
      return [
        _title('Office Cash Release'),
        const SizedBox(height: 14),
        _row('Disbursed By', d.disbursedByLabel),
        if (d.disbursedAt != null)
          _row('Release Date',
              DateFormat('MMM dd, yyyy hh:mm a').format(d.disbursedAt!)),
      ];
    }
    return [
      _title('Cash on Delivery Details'),
      const SizedBox(height: 14),
      _row('Assigned Rider', d.riderName.isEmpty ? 'N/A' : d.riderName),
      const SizedBox(height: 14),
      // Proof photos na in-upload ni rider (Cash on Delivery).
      _buildDeliveryProof(context, d),
    ];
  }

  /// Thumbnails ng COD proof (max 2) + signature — tap para i-fullscreen.
  /// Kapag wala pang upload, "No proof uploaded yet" lang.
  Widget _buildDeliveryProof(BuildContext context, DisbursementModel d) {
    final items = <CollectionProofItem>[
      if ((d.deliveryProof ?? '').isNotEmpty)
        CollectionProofItem(label: 'Proof Photo 1', url: d.deliveryProof!),
      if ((d.deliveryProof2 ?? '').isNotEmpty)
        CollectionProofItem(label: 'Proof Photo 2', url: d.deliveryProof2!),
      if ((d.borrowerSignature ?? '').isNotEmpty)
        CollectionProofItem(
            label: 'Lender Signature', url: d.borrowerSignature!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cash on Delivery Proof',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Text('No proof uploaded yet',
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textTertiary))
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < items.length; i++)
                InkWell(
                  // Direkta sa fullscreen — walang maliit na dialog sa
                  // pagitan. Pwedeng mag-swipe sa iba pang proof doon.
                  onTap: () => showCollectionProofFullscreen(
                    context,
                    items,
                    initialIndex: i,
                  ),
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      color: AppColors.surfaceVariant,
                    ),
                    child: Image.network(
                      items[i].url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textTertiary),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// "rider_delivery" → "Rider delivery", "completed" → "Completed".
  String _prettyStatus(String s) {
    final v = s.replaceAll('_', ' ').trim();
    if (v.isEmpty) return '-';
    return v[0].toUpperCase() + v.substring(1);
  }

  /// Label sa fixed-width na column para isang linya lang lahat ng value —
  /// pareho ng `Payment Details` modal.
  Widget _row(String label, String value, {TextStyle? valueStyle}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 150,
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(
                child: Text(value,
                    style: valueStyle ??
                        const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary))),
          ],
        ),
      );
}
