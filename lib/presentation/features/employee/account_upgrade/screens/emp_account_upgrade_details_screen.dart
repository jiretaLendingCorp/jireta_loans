// lib/presentation/features/employee/account_upgrade/screens/emp_account_upgrade_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/document_viewer.dart';

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
  final _rejectionCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rejectionCtrl.dispose();
    super.dispose();
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
    if (action == 'rejected' && _rejectionCtrl.text.trim().isEmpty) {
      showErrorSnackBar(context, 'Please enter rejection notes.');
      return;
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: action == 'verified' ? 'Verify All Documents' : 'Reject All Documents',
      message: action == 'verified'
          ? 'Verify the lender\'s entire account upgrade submission at once?'
          : 'Reject the lender\'s entire account upgrade submission? They will be notified.',
      confirmLabel: action == 'verified' ? 'Verify All' : 'Reject All',
      isDangerous: action == 'rejected',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _ds.verifyAllAccountUpgrade(
        lenderId: widget.lenderId,
        action: action,
        rejectionNotes: action == 'rejected' ? _rejectionCtrl.text.trim() : null,
      );
      if (mounted) {
        showSuccessSnackBar(
            context, action == 'verified' ? 'All documents verified successfully.' : 'All documents rejected.');
        await _load();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'Action failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)])),
                    child: Row(children: [
                      Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9)),
                          child: const Icon(Icons.insert_drive_file_rounded,
                              color: Colors.white, size: 18)),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('Document Preview',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                      IconButton(
                          icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white)),
                          onPressed: () => Navigator.pop(context)),
                    ]),
                  ),
                  Flexible(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16), child: DocumentViewer(url: url, height: 540))),
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
    final docs = (data['documents'] as List?) ?? [];
    final contacts = (data['emergency_contacts'] as List?) ?? [];
    final accountUpgradeStatus = (data['account_upgrade_status'] as String?) ?? 'pending';
    final pendingDocs = docs.where((d) => (d as Map<String, dynamic>)['status'] == 'pending').toList();
    final verifiedDocs = docs.where((d) => (d as Map<String, dynamic>)['status'] == 'verified').length;
    final accent = _accentForStatus(accountUpgradeStatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLenderHero(lender, accountUpgradeStatus, docs.length, verifiedDocs, pendingDocs.length, accent),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 860;
            final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PremiumSectionCard(
                title: 'Lender Profile',
                subtitle: 'Personal & KYC information',
                icon: Icons.person_rounded,
                accent: AppColors.lenderBlue,
                child: Column(children: [
                  _InfoRow('Full Name',
                      '${lender['first_name'] ?? ''} ${lender['middle_name'] ?? ''} ${lender['last_name'] ?? ''}'
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim()),
                  _InfoRow('Phone', lender['phone_number'] ?? '—'),
                  _InfoRow('Email', lender['email'] ?? '—'),
                  _InfoRow(
                      'Address',
                      [
                        lender['street_address'],
                        lender['barangay'],
                        lender['city'],
                        lender['province'],
                        lender['zip_code']
                      ]
                              .where((e) => e != null && e.toString().isNotEmpty)
                              .join(', ')
                              .isEmpty
                          ? '—'
                          : [
                              lender['street_address'],
                              lender['barangay'],
                              lender['city'],
                              lender['province'],
                              lender['zip_code']
                            ].where((e) => e != null && e.toString().isNotEmpty).join(', ')),
                  const Divider(height: 20),
                  _InfoRow('Source of Funds', lender['source_of_funds'] ?? '—'),
                  _InfoRow('Employment', lender['employment_type'] ?? '—'),
                  _InfoRow('Employer', lender['employer_name'] ?? '—'),
                  _InfoRow('Monthly Income', lender['monthly_income'] != null ? '₱${lender['monthly_income']}' : '—',
                      highlight: true),
                  const Divider(height: 20),
                  _InfoRow('GCash', lender['gcash_number'] ?? '—'),
                  _InfoRow('Gender', lender['gender'] ?? '—'),
                  _InfoRow('Civil Status', lender['civil_status'] ?? '—'),
                  _InfoRow('Date of Birth', lender['date_of_birth'] ?? '—'),
                ]),
              ),
              const SizedBox(height: 16),
              _PremiumSectionCard(
                title: 'Submitted Documents',
                subtitle: '${docs.length} file${docs.length == 1 ? '' : 's'} • tap to preview',
                icon: Icons.folder_copy_rounded,
                accent: const Color(0xFF00838F),
                child: docs.isEmpty
                    ? const Text('No documents submitted.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                    : Column(
                        children: docs.map((doc) {
                          final d = doc as Map<String, dynamic>;
                          final docStatus = (d['status'] ?? 'pending').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.border)),
                                  child: Icon(_iconForDocType(d['document_type']?.toString() ?? ''),
                                      size: 18, color: AppColors.deepNavy),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(d['document_type'] ?? 'Document',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                                StatusBadge(status: docStatus, small: true),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textTertiary),
                                const SizedBox(width: 4),
                                Text(
                                    d['created_at'] != null
                                        ? 'Submitted: ${d['created_at'].toString().substring(0, 19)}'
                                        : '—',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ]),
                              if (d['rejection_notes'] != null && (d['rejection_notes'] as String).isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: AppColors.error.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.error.withValues(alpha: 0.2))),
                                  child: Row(children: [
                                    const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(d['rejection_notes'] as String,
                                            style: const TextStyle(fontSize: 12, color: AppColors.error))),
                                  ]),
                                ),
                              if (d['file_url'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openDocument(d),
                                      icon: const Icon(Icons.visibility_rounded, size: 14),
                                      label: const Text('View Document',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          side: const BorderSide(color: AppColors.deepNavy),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                    ),
                                  ),
                                ),
                            ]),
                          );
                        }).toList(),
                      ),
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _PremiumSectionCard(
                  title: 'Emergency Contacts',
                  subtitle: 'Reference persons',
                  icon: Icons.contact_emergency_rounded,
                  accent: AppColors.warning,
                  child: Column(
                    children: contacts.map((c) {
                      final m = c as Map<String, dynamic>;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration:
                                  BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), shape: BoxShape.circle),
                              child: const Icon(Icons.person_rounded, size: 18, color: AppColors.warning)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${m['name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text('${m['relationship'] ?? '—'} • ${m['phone_number'] ?? '—'}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
                          ])),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ]);

            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: pendingDocs.isEmpty
                              ? AppColors.riderGreen.withValues(alpha: 0.3)
                              : AppColors.border),
                      boxShadow: [
                        BoxShadow(
                            color: (pendingDocs.isEmpty ? AppColors.riderGreen : AppColors.deepNavy)
                                .withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: pendingDocs.isEmpty
                                ? [AppColors.riderGreen, AppColors.riderGreenDark]
                                : [AppColors.deepNavy, const Color(0xFF1A2E4A)]),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: Row(children: [
                        Container(
                            width: 36,
                            height: 36,
                            decoration:
                                BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
                            child: Icon(pendingDocs.isEmpty ? Icons.verified_rounded : Icons.fact_check_rounded,
                                color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Review Actions',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                        StatusBadge(status: accountUpgradeStatus),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: pendingDocs.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: AppColors.successLight,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.2))),
                              child: const Row(children: [
                                Icon(Icons.check_circle_rounded, color: AppColors.riderGreen, size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                    child: Text('All documents reviewed.',
                                        style: TextStyle(
                                            color: AppColors.riderGreen, fontWeight: FontWeight.w700, fontSize: 13)))
                              ]),
                            )
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: AppColors.warningLight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
                                child: Row(children: [
                                  Container(
                                      width: 32,
                                      height: 32,
                                      decoration:
                                          BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(8)),
                                      child: Center(
                                          child: Text('${pendingDocs.length}',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                      child: Text('Pending documents require your decision.',
                                          style: TextStyle(
                                              fontSize: 12, color: Color(0xFF6D4C00), fontWeight: FontWeight.w600))),
                                ]),
                              ),
                              const SizedBox(height: 14),
                              const Text('One action verifies the lender\'s entire account upgrade submission.',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                    gradient:
                                        const LinearGradient(colors: [AppColors.riderGreen, AppColors.riderGreenDark]),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.riderGreen.withValues(alpha: 0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4))
                                    ]),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  onPressed: _submitting ? null : () => _verifyAll('verified'),
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
                                  label: Text('Verify All (${pendingDocs.length})',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 12),
                              const Text('Rejection Notes',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _rejectionCtrl,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'Required when rejecting… explain clearly for audit trail',
                                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                  filled: true,
                                  fillColor: AppColors.surfaceVariant,
                                  border:
                                      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppColors.border)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppColors.error)),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.error),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                onPressed: _submitting ? null : () => _verifyAll('rejected'),
                                icon: const Icon(Icons.cancel_rounded, size: 18),
                                label: const Text('Reject All', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border)),
                        child: const Icon(Icons.shield_rounded, size: 16, color: AppColors.deepNavy)),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('Decisions are logged to the audit trail and notify the lender instantly.',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4))),
                  ]),
                ),
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

  Widget _buildLenderHero(
      Map<String, dynamic> lender, String status, int totalDocs, int verified, int pending, Color accent) {
    final fullName =
        '${lender['first_name'] ?? ''} ${lender['middle_name'] ?? ''} ${lender['last_name'] ?? ''}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final progress = totalDocs == 0 ? 0.0 : verified / totalDocs;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0D1B2A), Color(0xFF1A2E4A), Color(0xFF1E3A5F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Row(children: [
          Stack(children: [
            ProfileAvatar(
                photoUrl: lender['profile_photo_url'] as String?,
                name: fullName,
                color: Colors.white,
                radius: 36,
                borderColor: Colors.white,
                fallback: const Icon(Icons.person_rounded, size: 32, color: AppColors.deepNavy)),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                  width: 22,
                  height: 22,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: Icon(_iconForStatus(status), size: 12, color: Colors.white)),
            ),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fullName.isEmpty ? 'Unknown Lender' : fullName,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.email_outlined, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(lender['email']?.toString() ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 10),
                const Icon(Icons.phone_outlined, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(lender['phone_number']?.toString() ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                StatusBadge(status: status),
                const SizedBox(width: 8),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text('$verified/$totalDocs verified',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(accent)),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$pending pending • $verified verified', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text('${(progress * 100).toStringAsFixed(0)}% complete',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'verified':
        return AppColors.riderGreen;
      case 'rejected':
        return AppColors.error;
      case 'submitted':
        return AppColors.lenderBlue;
      default:
        return AppColors.warning;
    }
  }

  IconData _iconForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'verified':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'submitted':
        return Icons.pending_actions_rounded;
      default:
        return Icons.pending_rounded;
    }
  }

  IconData _iconForDocType(String type) {
    final t = type.toLowerCase();
    if (t.contains('id') || t.contains('government')) return Icons.badge_rounded;
    if (t.contains('selfie')) return Icons.face_rounded;
    if (t.contains('proof') || t.contains('income')) return Icons.receipt_long_rounded;
    if (t.contains('address')) return Icons.location_on_rounded;
    return Icons.description_rounded;
  }
}

class _PremiumSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _PremiumSectionCard(
      {required this.title, required this.subtitle, required this.icon, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              border: const Border(bottom: BorderSide(color: AppColors.divider)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))
            ]),
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
        SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: highlight ? AppColors.deepNavy : AppColors.textPrimary))),
      ]),
    );
  }
}
