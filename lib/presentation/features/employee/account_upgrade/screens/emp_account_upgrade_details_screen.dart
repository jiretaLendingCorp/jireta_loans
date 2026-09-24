// lib/presentation/features/employee/account_upgrade/screens/emp_account_upgrade_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/document_preview_dialog.dart';
import '../../../../shared/utils/account_upgrade_checklist.dart';

class EmpAccountUpgradeDetailsScreen extends ConsumerStatefulWidget {
  final String lenderId;
  const EmpAccountUpgradeDetailsScreen({super.key, required this.lenderId});

  @override
  ConsumerState<EmpAccountUpgradeDetailsScreen> createState() =>
      _EmpAccountUpgradeDetailsScreenState();
}

class _EmpAccountUpgradeDetailsScreenState
    extends ConsumerState<EmpAccountUpgradeDetailsScreen> {
  final _ds = sl<AccountUpgradeRemoteDataSource>();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  List _allDocs = [];

  @override
  void initState() {
    super.initState();
    _load();
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
    // Reject requires no reason — simple Yes / No confirm.
    // Yes => reject, No => cancel (do not reject).
    if (action == 'rejected') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmationDialog(
          title: 'Reject Account Upgrade?',
          message:
              'Do you want to reject this lender\'s account upgrade submission?',
          confirmLabel: 'Yes',
          cancelLabel: 'No',
          confirmColor: AppColors.error,
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showConfirmationDialog(
        context,
        title: 'Verify All Documents',
        message:
            'Verify the lender\'s entire account upgrade submission at once?',
        confirmLabel: 'Verify',
        icon: Icons.verified_rounded,
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _submitting = true);
    try {
      await _ds.verifyAllAccountUpgrade(
        lenderId: widget.lenderId,
        action: action,
      );
      if (mounted) {
        showSuccessSnackBar(context, action == 'verified' ? 'All documents verified successfully.' : 'All documents rejected.');
        await _load();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'Action failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Resolves a document file to a viewable URL. Signed URLs and absolute
  /// http(s) URLs pass through untouched; relative storage paths are signed
  /// from the account-upgrade-documents bucket first and fall back to the
  /// loan-documents bucket, where walk-in documents backfilled into
  /// account_upgrade_documents (migration 00133) actually live. Throws when
  /// the file is not found in either bucket.
  Future<String> _resolveDocFile(String filePath) async {
    if (filePath.startsWith('http')) return filePath;
    Object? lastError;
    for (final bucket in const ['account-upgrade-documents', 'loan-documents']) {
      try {
        return await SupabaseStorageService.instance
            .getSignedUrl(bucket: bucket, path: filePath);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Unable to resolve document file');
  }

  Future<void> _openDocument(Map<String, dynamic> doc, {List? allDocs}) async {
    final signedUrl = doc['signed_url'] as String?;
    final filePath = doc['file_url'] as String?;
    final docType = doc['document_type']?.toString() ?? '';
    try {
      String url;
      if (signedUrl != null && signedUrl.isNotEmpty) {
        url = signedUrl;
      } else if (filePath != null && filePath.isNotEmpty) {
        url = await _resolveDocFile(filePath);
      } else {
        return;
      }

      // For valid_id, also find and load the back side
      String? backUrl;
      if (docType == 'valid_id' && allDocs != null) {
        final backDoc = allDocs.cast<Map<String, dynamic>?>().firstWhere(
          (d) => d?['document_type']?.toString() == 'valid_id_back',
          orElse: () => null,
        );
        if (backDoc != null) {
          final backSigned = backDoc['signed_url'] as String?;
          final backPath = backDoc['file_url'] as String?;
          if (backSigned != null && backSigned.isNotEmpty) {
            backUrl = backSigned;
          } else if (backPath != null && backPath.isNotEmpty) {
            backUrl = await _resolveDocFile(backPath);
          }
        }
      }

      if (!mounted) return;
      // Carousel na preview: ISA-ISA ang titignan (Front tapos Back) na may
      // arrows/swipe/dots at rotate — dating magkatabi kaya maliit at mahirap
      // basahin ang detalye ng ID.
      await showDocumentPreviewDialog(
        context,
        title: _docLabel(docType),
        pages: [
          DocumentPreviewPage(
            label: backUrl != null ? 'Front Side' : 'Document',
            url: url,
            // Ang ID ay landscape na card — auto-landscape kapag portrait ang
            // na-upload na litrato.
            autoLandscape: docType.startsWith('valid_id'),
          ),
          if (backUrl != null)
            DocumentPreviewPage(
              label: 'Back Side',
              url: backUrl,
              autoLandscape: docType.startsWith('valid_id'),
            ),
        ],
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'Failed to open document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      title: 'Lender Account Upgrade Details',
      body: _loading
          ? const ShimmerLoader()
          : _error != null
              ? Center(child: Text(_error!))
              : _data == null
                  ? const Center(child: Text('Account upgrade data not found.'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final data = _data!;
    final lender = (data['lender'] as Map<String, dynamic>?) ?? {};
    _allDocs = (data['documents'] as List?) ?? [];
    // Checklist: LAGING kasama ang lahat ng inaasahang dokumento kahit wala
    // sa DB, para makita ng reviewer ang "Not submitted" (hal. Face
    // Recognition na na-skip sa web/desktop) sa halip na basta mawala.
    final docs = buildAccountUpgradeChecklist(_allDocs);
    final accountUpgradeStatus = (data['account_upgrade_status'] as String?) ?? 'pending';
    final pendingDocs = docs.where((item) => item.status == 'pending').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 860;
            final profileCard = _PremiumSectionCard(
              title: 'Lender Profile',
                subtitle: '',
                icon: Icons.person_rounded,
                accent: AppColors.lenderBlue,
                child: Column(children: [
                  _InfoRow('Full Name', '${lender['first_name'] ?? ''} ${lender['middle_name'] ?? ''} ${lender['last_name'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim()),
                  _InfoRow('Phone', lender['phone_number'] ?? '—'),
                  _InfoRow('Email', lender['email'] ?? '—'),
                  _InfoRow('Address', [lender['street_address'], lender['barangay'], lender['city'], lender['province'], lender['zip_code']].where((e) => e != null && e.toString().isNotEmpty).join(', ').isEmpty ? '—' : [lender['street_address'], lender['barangay'], lender['city'], lender['province'], lender['zip_code']].where((e) => e != null && e.toString().isNotEmpty).join(', ')),
                  // 00128: financial details are declared per LOAN and are no
                  // longer part of the account-upgrade (lender profile) review.
                  _InfoRow('Gender', lender['gender'] ?? '—'),
                  _InfoRow('Civil Status', lender['civil_status'] ?? '—'),
                  _InfoRow('Date of Birth', lender['date_of_birth'] ?? '—'),
                ]),
            );
            final docsCard = _PremiumSectionCard(
              title: 'Submitted Documents',
                subtitle: '',
                icon: Icons.folder_copy_rounded,
                accent: const Color(0xFF00838F),
                child: docs.isEmpty
                    ? const Text('No documents submitted.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                    : LayoutBuilder(builder: (context, grid) {
                        // 2 dokumento kada row kapag sapat ang lapad — puno na
                        // kasi ang buong section ngayon, hindi na makitid.
                        const gap = 16.0;
                        final twoUp = grid.maxWidth >= 720;
                        final tileWidth =
                            twoUp ? (grid.maxWidth - gap) / 2 : grid.maxWidth;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (int i = 0; i < docs.length; i++)
                              SizedBox(
                                width: tileWidth,
                                child: Builder(builder: (context) {
                              final item = docs[i];
                              final d = item.doc;
                              final docStatus = (d?['status'] ?? 'pending').toString();
                              final hasFile = d != null &&
                                  [d['file_url'], d['signed_url']].any((v) =>
                                      v != null && v.toString().trim().isNotEmpty);
                              // Symmetric na padding (dati ay bottom-only) para may
                              // hangin sa itaas at ibaba ng bawat dokumento.
                              // Tile na may border (dati'y plain row na may
                              // divider) — mas malinaw sa 2-kada-row na grid.
                              // Grey + pulang border kapag wala sa DB (hal. Face
                              // Recognition na hindi na-submit) para halata agad
                              // ang kulang.
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: item.submitted
                                      ? Colors.white
                                      : AppColors.surfaceGray.withValues(alpha: 0.35),
                                  border: Border.all(
                                    color: item.submitted
                                        ? AppColors.border
                                        : AppColors.error.withValues(alpha: 0.4),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: _docIcon(item.type),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_docLabel(item.type), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: item.submitted ? null : AppColors.textSecondary))),
                                    if (!item.submitted)
                                      Text(
                                        item.required
                                            ? 'Not submitted'
                                            : 'Not submitted · optional',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: item.required
                                              ? AppColors.error
                                              : AppColors.textTertiary,
                                        ),
                                      )
                                    else if (docStatus.toLowerCase() != 'submitted')
                                      Text(docStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: docStatus.toLowerCase() == 'verified' ? AppColors.success : AppColors.error)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textTertiary),
                                    const SizedBox(width: 4),
                                    // `created_at` dito ay `uploaded_at` (TIMESTAMPTZ,
                                    // totoong UTC) — dati ay hilaw na ISO slice
                                    // (`2026-09-20T09:29:10`) at 8 oras mali.
                                    Text(
                                      d != null
                                          ? 'Submitted: ${AppFormatters.dateTimeOr(d['created_at'])}'
                                          : 'No upload found',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary),
                                    ),
                                  ]),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(children: [
                                      // Redesigned: navy na rounded button na may
                                      // eye icon (dati'y bare outlined button).
                                      Material(
                                        color: hasFile ? AppColors.deepNavy : AppColors.surfaceGray,
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: hasFile ? () => _openDocument(d, allDocs: _allDocs) : null,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                                              Icon(Icons.visibility_outlined, size: 15, color: hasFile ? Colors.white : AppColors.textTertiary),
                                              const SizedBox(width: 6),
                                              Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hasFile ? Colors.white : AppColors.textTertiary)),
                                            ]),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Ipakitang malinaw sa tabi ng View kung may laman
                                      // (na-upload) o walang laman ang dokumento.
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(hasFile ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 14, color: hasFile ? AppColors.success : AppColors.error),
                                        const SizedBox(width: 4),
                                        Text(
                                          hasFile
                                              ? 'File uploaded'
                                              : (d != null
                                                  ? 'Empty — no file'
                                                  : 'Not submitted'),
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: hasFile ? AppColors.success : AppColors.error),
                                        ),
                                      ]),
                                    ]),
                                  ),
                                ]),
                              );
                                }),
                              ),
                          ],
                        );
                      }),
            );

            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: pendingDocs.isEmpty ? AppColors.riderGreen.withValues(alpha: 0.3) : AppColors.border), boxShadow: [BoxShadow(color: (pendingDocs.isEmpty ? AppColors.riderGreen : AppColors.deepNavy).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF5C6370),
                      ),
                      child: Row(children: [
                        const Expanded(child: Text('Review Actions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                        if (accountUpgradeStatus.toLowerCase() != 'submitted')
                          Text(accountUpgradeStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accountUpgradeStatus.toLowerCase() == 'verified' ? Colors.white : AppColors.error)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(builder: (_) {
                        final s = accountUpgradeStatus.toLowerCase();
                        final isRejected = s == 'rejected';
                        final isVerified = s == 'verified';
                        // Rejected: Verify must NOT appear. No further action.
                        if (isRejected) {
                          final resubmitAfter =
                              (_data?['resubmit_after'] as String?);
                          final dateStr =
                              (resubmitAfter != null &&
                                      resubmitAfter.length >= 10)
                                  ? resubmitAfter.substring(0, 10)
                                  : null;
                          return Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                                dateStr != null
                                    ? 'Lender may resubmit after 1 month ($dateStr).'
                                    : 'Lender may resubmit after the 1-month cooldown.',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          );
                        }
                        if (isVerified || pendingDocs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text('All documents reviewed.', style: TextStyle(color: AppColors.riderGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                          );
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text('Pending documents require your decision.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            OutlinedButton(
                              onPressed: _submitting ? null : () => _verifyAll('verified'),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), side: const BorderSide(color: AppColors.deepNavy), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                              child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _submitting ? null : () => _verifyAll('rejected'),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), side: const BorderSide(color: AppColors.error), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                              child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.error)),
                            ),
                          ]),
                        ]);
                      }),
                    ),
                  ]),
                ),
              ]),
            );

            final topRow = isNarrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [profileCard, const SizedBox(height: 16), rightRail])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: profileCard), const SizedBox(width: 16), rightRail]);
            // Full width na ang Submitted Documents (dati'y nasa loob ng flex-5
            // na column, kaya may sayang na espasyo sa kanan) at 2 kada row.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                topRow,
                const SizedBox(height: 16),
                docsCard,
              ],
            );
          }),
        ],
      ),
    );
  }

  IconData _iconForDocType(String type) {
    final t = type.toLowerCase();
    if (t.contains('id') || t.contains('government')) return Icons.badge_rounded;
    if (t.contains('selfie')) return Icons.face_rounded;
    if (t.contains('proof') || t.contains('income')) return Icons.receipt_long_rounded;
    if (t.contains('address')) return Icons.location_on_rounded;
    return Icons.description_rounded;
  }

  static const Map<String, String> _docAssetIcons = {
    'valid_id': 'assets/icons/id_card.png',
    'selfie': 'assets/icons/selfie with id.png',
    'mayors_permit': 'assets/icons/PERMIT.png',
    'face_recognition': 'assets/icons/FACE RECOGNITION.jpg',
  };

  String _docLabel(String docType) {
    switch (docType) {
      case 'valid_id': return 'Valid Government ID';
      case 'selfie': return 'Selfie with ID';
      case 'mayors_permit': return 'Business Permit';
      case 'lender_signature': return 'Lender Signature';
      default: return docType.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');
    }
  }

  Widget _docIcon(String docType, {double size = 18}) {
    final asset = _docAssetIcons[docType];
    if (asset != null) {
      return Image.asset(asset, width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.high);
    }
    return Icon(_iconForDocType(docType), size: size, color: AppColors.deepNavy);
  }
}

class _PremiumSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _PremiumSectionCard({required this.title, required this.subtitle, required this.icon, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)), if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white70))]),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ]),
    );
  }
}
