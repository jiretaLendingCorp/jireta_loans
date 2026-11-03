// lib/presentation/features/head_manager/account_deletion/screens/hm_account_deletion_screen.dart
//
// Head Manager queue para sa public /delete-account requests.
//
// Mahalaga: ang requests dito ay galing sa PUBLIC page (hindi naka-log-in).
// Ang in-app na Profile → Delete Account ay agad na dini-delete ang account at
// hindi na dumadaan sa queue. Bago i-approve, kailangang ma-verify ng staff na
// galing talaga sa may-ari ang request (tawagan ang registered number o
// i-reply sa registered email).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/account_deletion_request_model.dart';
import '../../../../shared/widgets/filter_dropdown.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../providers/hm_account_deletion_provider.dart';

/// Body lang ito — ang `WebScaffold` at ang tab bar ay pag-aari ng
/// `HmNotificationCenterScreen`, kung saan naka-mount ito sa Account Deletion
/// tab (`/hm/account-deletion`).
class HmAccountDeletionBody extends ConsumerStatefulWidget {
  const HmAccountDeletionBody({super.key});

  @override
  ConsumerState<HmAccountDeletionBody> createState() =>
      _HmAccountDeletionBodyState();
}

class _HmAccountDeletionBodyState extends ConsumerState<HmAccountDeletionBody> {
  static final _dateFormat = DateFormat('MMM d, yyyy • h:mm a');
  static final _shortDateFormat = DateFormat('MMM d, yyyy');

  /// Client-side search + date filter. Ang status (Pending / Completed / …)
  /// lang ang sinasabi sa API; ang search at petsa ay sinasala na lang dito sa
  /// mga na-load na request para hindi kailangang mag-round trip sa bawat
  /// letra.
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(hmAccountDeletionProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDateRangeChanged(DateTimeRange? range) {
    setState(() => _dateRange = range);
  }

  List<AccountDeletionRequestModel> _visibleRequests(
    HmAccountDeletionState state,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final range = _dateRange;
    return state.requests.where((request) {
      if (query.isNotEmpty) {
        final haystack = [
          request.displayName,
          request.reference,
          request.identifier ?? '',
          request.roleLabel,
          request.sourceLabel,
          request.reason ?? '',
          request.notes ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      if (range != null) {
        final requestedAt = request.requestedAt?.toLocal();
        if (requestedAt == null) return false;
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        );
        if (requestedAt.isBefore(start) || requestedAt.isAfter(end)) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() => _dateRange = null);
    ref.read(hmAccountDeletionProvider.notifier).setFilter('all');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmAccountDeletionProvider);

    return Column(
      children: [
        _toolbar(state),
        _infoBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(hmAccountDeletionProvider.notifier).load(silent: true),
            child: _content(state),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(HmAccountDeletionState state) {
    final visible = _visibleRequests(state);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: ResponsiveSearchToolbar(
        searchField: TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search name, reference, contact, reason…',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          FilterDropdown<String>(
            value: state.filter,
            icon: Icons.flag_outlined,
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref.read(hmAccountDeletionProvider.notifier).setFilter(value);
            },
          ),
          SearchResultsChip(count: visible.length),
          if (state.isProcessing)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 6),
                Text(
                  'Processing…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading
                ? null
                : () => ref
                    .read(hmAccountDeletionProvider.notifier)
                    .load(silent: true),
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.infoLight,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 17, color: AppColors.info),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Public requests need manual identity verification before approval. '
              'Call the registered number or reply to the registered email. '
              'In-app deletions happen immediately and do not appear here.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(HmAccountDeletionState state) {
    final visible = _visibleRequests(state);
    if (state.isLoading && state.requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (state.error != null && state.requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _messageState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load requests',
            message: state.error!,
            action: TextButton(
              onPressed: () =>
                  ref.read(hmAccountDeletionProvider.notifier).load(),
              child: const Text('Try again'),
            ),
          )
        ],
      );
    }

    if (state.requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _messageState(
            icon: Icons.delete_sweep_outlined,
            title: state.filter == 'pending'
                ? 'No pending deletion requests'
                : 'No deletion requests found',
            message: state.filter == 'pending'
                ? 'Requests submitted from the public Delete Account page will appear here.'
                : 'Try another filter or refresh the queue.',
          )
        ],
      );
    }

    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _messageState(
            icon: Icons.search_off_rounded,
            title: 'No matching requests',
            message: 'No requests match your search, status, or date filter. '
                'Try a different keyword or clear the filters.',
            action: TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: ResponsiveListCard(
        // Tabular sa desktop; stacked cards lang kapag mas maliit sa 1000px
        // ang content area (tablet / mobile), para walang horizontal scroll.
        minTableWidth: 1000,
        variant: ResponsiveListVariant.premium,
        columns: const [
          ResponsiveCol('Requester', icon: Icons.person_outline, flex: 4),
          ResponsiveCol('Contact', icon: Icons.contact_phone_outlined, flex: 3),
          ResponsiveCol('Role', icon: Icons.badge_outlined, flex: 2),
          ResponsiveCol('Reason', icon: Icons.notes_outlined, flex: 4),
          ResponsiveCol('Requested', icon: Icons.schedule_outlined, flex: 4),
          ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
        ],
        // Fixed na makitid na Actions column — isang View button lang, kaya
        // PAREHO ang posisyon nito sa lahat ng row (walang nakahilway na
        // space). Ang Approve / Reject ay nasa loob ng View modal.
        actionsCol: const ResponsiveActionsCol(
          label: 'Actions',
          icon: Icons.bolt_outlined,
          width: 104,
        ),
        rows: visible
            .map((request) => _requestRow(request, state))
            .toList(growable: false),
      ),
    );
  }

  ResponsiveRow _requestRow(
    AccountDeletionRequestModel request,
    HmAccountDeletionState state,
  ) {
    return ResponsiveRow(
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: request.displayName,
              child: Text(
                request.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              request.reference,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.goldDark,
              ),
            ),
          ],
        ),
        _contactCell(request),
        Text(
          request.roleLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        _reasonCell(request),
        _requestedCell(request),
        _statusCell(request),
      ],
      // Isang View button — kapareho ng Loan Records table. Buong detalye
      // (reason, staff notes, contact) at ang Approve / Reject para sa pending
      // requests ay nasa loob ng modal.
      actions: OutlinedButton.icon(
        onPressed: () => _showDetails(request, state),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.info,
          side: BorderSide(color: AppColors.info.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        icon: const Icon(Icons.visibility_outlined, size: 14),
        label: const Text(
          'View',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Contact number + kung saan galing ang request (public page / in-app).
  Widget _contactCell(AccountDeletionRequestModel request) {
    if (request.identifier == null) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          request.identifier!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              request.identifierType == 'email' ? 'Email' : 'Mobile',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const Text(
              ' · ',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            Flexible(
              child: Text(
                request.sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Reason ng requester, at ang staff notes kung naproseso na.
  ///
  /// Tig-isang linya lang ang dalawa para PAREHO-PAREHO ang taas ng lahat ng
  /// row — ang buong teksto ay nasa tooltip at sa View modal.
  Widget _reasonCell(AccountDeletionRequestModel request) {
    final reason = request.reason;
    final notes = request.notes;
    final showNotes = notes != null && !request.isPending;
    if (reason == null && !showNotes) {
      return const Text(
        '—',
        style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reason != null)
          Tooltip(
            message: reason,
            child: Text(
              reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        if (showNotes) ...[
          if (reason != null) const SizedBox(height: 2),
          Tooltip(
            message: 'Staff notes: $notes',
            child: Text(
              'Staff notes: $notes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _requestedCell(AccountDeletionRequestModel request) {
    return Text(
      request.requestedAt == null
          ? '—'
          : _dateFormat.format(request.requestedAt!.toLocal()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
    );
  }

  /// Status chip + ang petsa kung kailan naproseso (kung meron).
  Widget _statusCell(AccountDeletionRequestModel request) {
    final processed = request.processedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(request: request),
        if (processed != null) ...[
          const SizedBox(height: 4),
          Text(
            _shortDateFormat.format(processed.toLocal()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return SizedBox(
      height: 320,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(
    AccountDeletionRequestModel request,
    HmAccountDeletionState state,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => _RequestDetailsDialog(
        request: request,
        canProcess: request.isPending && !state.isProcessing,
      ),
    );
    if (!mounted || action == null) return;
    // Nakasara na ang details modal bago magbukas ang confirmation dialog.
    if (action == 'reject') {
      await _reject(request);
    } else if (action == 'approve') {
      await _approve(request);
    }
  }

  Future<void> _approve(AccountDeletionRequestModel request) async {
    final result = await showDialog<_ApprovalResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApproveDeletionDialog(request: request),
    );
    if (result == null || !mounted) return;

    final error = await ref
        .read(hmAccountDeletionProvider.notifier)
        .approve(requestId: request.id, notes: result.notes);
    if (!mounted) return;
    if (error != null) {
      await _showError('Deletion failed', error);
      return;
    }
    context.showSnackBarAsToast(
      SnackBar(
        content: Text('${request.displayName} — account deleted'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _reject(AccountDeletionRequestModel request) async {
    final notes = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RejectDeletionDialog(request: request),
    );
    if (notes == null || !mounted) return;

    final error = await ref
        .read(hmAccountDeletionProvider.notifier)
        .reject(requestId: request.id, notes: notes);
    if (!mounted) return;
    if (error != null) {
      await _showError('Could not reject request', error);
      return;
    }
    context.showSnackBarAsToast(
      const SnackBar(
        content: Text('Deletion request rejected'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _showError(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Status pill — ginagamit sa table at sa details modal.
class _StatusChip extends StatelessWidget {
  final AccountDeletionRequestModel request;

  const _StatusChip({required this.request});

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (request.status) {
      'pending' => (AppColors.warning, AppColors.warningLight),
      'processing' => (AppColors.info, AppColors.infoLight),
      'completed' => (AppColors.success, AppColors.successLight),
      'rejected' => (AppColors.error, AppColors.errorLight),
      _ => (AppColors.textSecondary, AppColors.surfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        request.statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Read-only na detalye ng isang deletion request — buong reason at staff
/// notes, walang truncation.
class _RequestDetailsDialog extends StatelessWidget {
  final AccountDeletionRequestModel request;

  /// Pending pa ba at pwedeng i-approve/reject mula sa modal?
  final bool canProcess;

  const _RequestDetailsDialog({
    required this.request,
    required this.canProcess,
  });

  static final _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

  String _date(DateTime? value) =>
      value == null ? '—' : _dateFormat.format(value.toLocal());

  String get _contact {
    final identifier = request.identifier;
    if (identifier == null) return '—';
    final type = request.identifierType == 'email' ? 'email' : 'mobile';
    return '$identifier ($type)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Square corners — walang border radius.
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 10, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(request.displayName)),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      request.reference,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.goldDark,
                      ),
                    ),
                  ),
                  _StatusChip(request: request),
                ],
              ),
              const SizedBox(height: 14),
              _field('Registered contact', _contact),
              _field('Role', request.roleLabel),
              _field('Source', request.sourceLabel),
              _field('Requested', _date(request.requestedAt)),
              if (request.processedAt != null)
                _field('Processed', _date(request.processedAt)),
              _field('Reason', request.reason ?? '—'),
              if (request.notes != null) _field('Staff notes', request.notes!),
            ],
          ),
        ),
      ),
      actions: canProcess
          ? [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop('reject'),
                child: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop('approve'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: const Text('Approve & delete'),
              ),
            ]
          : null,
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalResult {
  final String notes;

  const _ApprovalResult(this.notes);
}

/// Sariling StatefulWidget ang dialog para ito ang may-ari ng
/// [TextEditingController]. Kung nasa labas ito at idi-dispose agad pagkatapos
/// ng `showDialog`, ginagamit pa ito ng exit animation ng route.
class _ApproveDeletionDialog extends StatefulWidget {
  final AccountDeletionRequestModel request;

  const _ApproveDeletionDialog({required this.request});

  @override
  State<_ApproveDeletionDialog> createState() => _ApproveDeletionDialogState();
}

class _ApproveDeletionDialogState extends State<_ApproveDeletionDialog> {
  final _notesCtrl = TextEditingController();
  bool _verified = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve account deletion?'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes ${widget.request.displayName} '
                '(${widget.request.reference}), their profile, contact details, '
                'uploaded KYC files, and login access. Loan, payment, and '
                'audit records remain for the legal retention period.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Verification notes (optional)',
                  hintText:
                      'e.g. Called the registered number and confirmed the request',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                value: _verified,
                onChanged: (value) =>
                    setState(() => _verified = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I verified that this request came from the account owner.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _verified
              ? () => Navigator.of(context)
                  .pop(_ApprovalResult(_notesCtrl.text.trim()))
              : null,
          child: const Text('Approve & delete'),
        ),
      ],
    );
  }
}

class _RejectDeletionDialog extends StatefulWidget {
  final AccountDeletionRequestModel request;

  const _RejectDeletionDialog({required this.request});

  @override
  State<_RejectDeletionDialog> createState() => _RejectDeletionDialogState();
}

class _RejectDeletionDialogState extends State<_RejectDeletionDialog> {
  final _notesCtrl = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final notes = _notesCtrl.text.trim();
    if (notes.length < 3) {
      setState(
        () => _validationError = 'Enter a short reason (3+ characters).',
      );
      return;
    }
    Navigator.of(context).pop(notes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject deletion request?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reject ${widget.request.reference}? The account stays active. '
                'The requester must submit a new request.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Reason for rejection',
                  hintText: 'e.g. Could not verify the account owner',
                  border: const OutlineInputBorder(),
                  errorText: _validationError,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _submit,
          child: const Text('Reject request'),
        ),
      ],
    );
  }
}
