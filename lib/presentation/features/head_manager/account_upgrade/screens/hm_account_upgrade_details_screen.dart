// lib/presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/document_viewer.dart';

class HmAccountUpgradeDetailsScreen extends ConsumerStatefulWidget {
  final String lenderId;
  const HmAccountUpgradeDetailsScreen({super.key, required this.lenderId});

  @override
  ConsumerState<HmAccountUpgradeDetailsScreen> createState() =>
      _HmAccountUpgradeDetailsScreenState();
}

class _HmAccountUpgradeDetailsScreenState
    extends ConsumerState<HmAccountUpgradeDetailsScreen> {
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
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.error
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.cancel_rounded,
                              color: AppColors.error)),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Text('Reject Account Upgrade?',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16))),
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                        'Do you want to reject this lender\'s account upgrade submission?',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10))),
                              child: const Text('No'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10))),
                              child: const Text('Yes',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)))),
                    ]),
                  ]),
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showConfirmationDialog(
        context,
        title: 'Verify All Documents',
        message:
            'Verify the lender\'s entire account upgrade submission at once?',
        confirmLabel: 'Verify All',
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

  Future<void> _openDocument(Map<String, dynamic> doc, {List? allDocs}) async {
    final signedUrl = doc['signed_url'] as String?;
    final filePath = doc['file_url'] as String?;
    final docType = doc['document_type']?.toString() ?? '';
    try {
      String url;
      if (signedUrl != null && signedUrl.isNotEmpty) {
        url = signedUrl;
      } else if (filePath != null && filePath.startsWith('http')) {
        url = filePath;
      } else if (filePath != null) {
        url = await SupabaseStorageService.instance.getSignedUrl(bucket: 'account-upgrade-documents', path: filePath);
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
          } else if (backPath != null && backPath.startsWith('http')) {
            backUrl = backPath;
          } else if (backPath != null) {
            backUrl = await SupabaseStorageService.instance.getSignedUrl(bucket: 'account-upgrade-documents', path: backPath);
          }
        }
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)])),
                child: Row(children: [
                  Container(width: 30, height: 30, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.insert_drive_file_rounded, color: Colors.white, size: 16)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_docLabel(docType), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                  IconButton(icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 16, color: Colors.white)), onPressed: () => Navigator.pop(context)),
                ]),
              ),
              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: backUrl != null ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Front Side', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  DocumentViewer(url: url, height: 540),
                ])),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Back Side', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  DocumentViewer(url: backUrl, height: 540),
                ])),
              ]) : DocumentViewer(url: url, height: 540))),
            ]),
          ),
        ),
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
    final docs = _allDocs.where((d) => (d as Map<String, dynamic>)['document_type']?.toString() != 'valid_id_back').toList();
    final contacts = (data['emergency_contacts'] as List?) ?? [];
    final accountUpgradeStatus = (data['account_upgrade_status'] as String?) ?? 'pending';
    final pendingDocs = docs.where((d) => (d as Map<String, dynamic>)['status'] == 'pending').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 860;
            final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PremiumSectionCard(
                title: 'Lender Profile',
                subtitle: '',
                icon: Icons.person_rounded,
                accent: AppColors.lenderBlue,
                child: Column(children: [
                  _InfoRow('Full Name', '${lender['first_name'] ?? ''} ${lender['middle_name'] ?? ''} ${lender['last_name'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim()),
                  _InfoRow('Phone', lender['phone_number'] ?? '—'),
                  _InfoRow('Email', lender['email'] ?? '—'),
                  _InfoRow('Address', [lender['street_address'], lender['barangay'], lender['city'], lender['province'], lender['zip_code']].where((e) => e != null && e.toString().isNotEmpty).join(', ').isEmpty ? '—' : [lender['street_address'], lender['barangay'], lender['city'], lender['province'], lender['zip_code']].where((e) => e != null && e.toString().isNotEmpty).join(', ')),
                  const Divider(height: 20),
                  _InfoRow('Source of Funds', lender['source_of_funds'] ?? '—'),
                  _InfoRow('Employment', lender['employment_type'] ?? '—'),
                  _InfoRow('Employer', lender['employer_name'] ?? '—'),
                  _InfoRow('Monthly Income', lender['monthly_income'] != null ? '₱${lender['monthly_income']}' : '—', highlight: true),
                  const Divider(height: 20),
                  _InfoRow('Gender', lender['gender'] ?? '—'),
                  _InfoRow('Civil Status', lender['civil_status'] ?? '—'),
                  _InfoRow('Date of Birth', lender['date_of_birth'] ?? '—'),
                ]),
              ),
              const SizedBox(height: 16),
              _PremiumSectionCard(
                title: 'Submitted Documents',
                subtitle: '',
                icon: Icons.folder_copy_rounded,
                accent: const Color(0xFF00838F),
                child: docs.isEmpty
                    ? const Text('No documents submitted.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                    : Column(
                        children: [
                          for (int i = 0; i < docs.length; i++) ...[
                            Builder(builder: (context) {
                              final d = docs[i] as Map<String, dynamic>;
                              final docStatus = (d['status'] ?? 'pending').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: _docIcon(d['document_type']?.toString() ?? ''),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(d['document_type'] ?? 'Document', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                                    if (docStatus.toLowerCase() != 'submitted')
                                      Text(docStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: docStatus.toLowerCase() == 'verified' ? AppColors.success : AppColors.error)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textTertiary),
                                    const SizedBox(width: 4),
                                    Text(d['created_at'] != null ? 'Submitted: ${d['created_at'].toString().substring(0, 19)}' : '—', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ]),
                                  if (d['file_url'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: OutlinedButton(
                                        onPressed: () => _openDocument(d, allDocs: _allDocs),
                                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), side: const BorderSide(color: AppColors.deepNavy), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                                        child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                ]),
                              );
                            }),
                            if (i < docs.length - 1)
                              const Divider(height: 1, color: AppColors.border),
                          ],
                        ],
                      ),
              ),
            ]);

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
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PremiumSectionCard(
                    title: 'Emergency Contacts',
                    subtitle: 'Reference persons',
                    icon: Icons.contact_emergency_rounded,
                    accent: AppColors.warning,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: contacts.map((c) {
                        final m = c as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${m['name'] ?? '\u2014'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), Text('${m['relationship'] ?? '\u2014'} \u2022 ${m['phone_number'] ?? '\u2014'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))]),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ]),
            );

            if (isNarrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [leftColumn, const SizedBox(height: 16), rightRail]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: leftColumn), const SizedBox(width: 16), rightRail]);
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
    'birth_certificate': 'assets/icons/birth certificate.jpg',
  };

  String _docLabel(String docType) {
    switch (docType) {
      case 'valid_id': return 'Valid Government ID';
      case 'selfie': return 'Selfie with ID';
      case 'mayors_permit': return "Mayor's Permit";
      case 'birth_certificate': return 'Birth Certificate';
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
  final bool highlight;
  const _InfoRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: highlight ? AppColors.deepNavy : AppColors.textPrimary))),
      ]),
    );
  }
}
