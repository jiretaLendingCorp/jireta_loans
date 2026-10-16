// lib/presentation/features/head_manager/settings/widgets/xendit_diagnostics_card.dart
//
// HEAD MANAGER-only card: XENDIT SANDBOX DIAGNOSTICS.
//
// Tatlong hiwalay na hakbang, malinaw na pinaghihiwalay (hindi pinagsasama):
//   1. API connectivity  — read-only check ng `XENDIT_SECRET_KEY`.
//   2. Payment request   — sandbox TEST payment request (Payments API v3).
//   3. Confirmed payment — Xendit-confirmed status ng test payment.
//
// SINADYANG WALA dito: disbursement/payout. Ang test card na ito ay HINDI
// nagpapalabas ng pondo at HINDI nag-a-approve ng loan o nagmamarka ng bayad.
// Ang secret key ay server-side lang — walang key input, walang key display.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../providers/xendit_diagnostics_provider.dart';

class XenditDiagnosticsCard extends ConsumerWidget {
  const XenditDiagnosticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(xenditDiagnosticsProvider);
    final notifier = ref.read(xenditDiagnosticsProvider.notifier);

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
          _header(),
          const SizedBox(height: 4),
          const Text(
            'Sandbox/test checks only. The secret key stays in Supabase '
            'Edge Function secrets — it is never sent to or stored in the app.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _amountRow(context, state, notifier),
          const SizedBox(height: 16),
          if (state.errorMessage != null) ...[
            _banner(
              icon: Icons.error_outline,
              color: AppColors.error,
              background: AppColors.errorLight,
              text: state.errorMessage!,
            ),
            const SizedBox(height: 12),
          ],
          if (state.infoMessage != null) ...[
            _banner(
              icon: Icons.info_outline,
              color: AppColors.info,
              background: AppColors.infoLight,
              text: state.infoMessage!,
            ),
            const SizedBox(height: 12),
          ],
          _connectivitySection(state, notifier),
          const SizedBox(height: 16),
          _paymentRequestSection(state, notifier),
          const SizedBox(height: 16),
          _confirmedSection(state, notifier),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text(
            'Disbursement / payout testing is intentionally excluded from this '
            'card. Loan approval, loan status and payment records are never '
            'modified by these test actions.',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return const Row(
      children: [
        Icon(Icons.science_outlined, size: 18, color: AppColors.deepNavy),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Xendit Sandbox Diagnostics',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _amountRow(
    BuildContext context,
    XenditDiagnosticsState state,
    XenditDiagnosticsNotifier notifier,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            key: const ValueKey('xenditTestAmount'),
            initialValue: state.amount.toStringAsFixed(0),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Test amount (PHP)',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value.trim());
              if (parsed != null) notifier.setAmount(parsed);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('xenditTestChannel'),
            initialValue: state.channelCode,
            isDense: true,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Channel (test)',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: xenditTestChannels
                .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) {
              if (value != null) notifier.setChannelCode(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color background,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1) API connectivity ────────────────────────────────────────────────

  Widget _connectivitySection(
    XenditDiagnosticsState state,
    XenditDiagnosticsNotifier notifier,
  ) {
    final connectivity = state.connectivity;
    final status = (connectivity?['status'] ?? '').toString();
    return _section(
      title: '1. API connectivity (read-only)',
      subtitle:
          'Verifies the XENDIT_SECRET_KEY against the Xendit API. No payment is created.',
      trailing: ElevatedButton.icon(
        key: const ValueKey('xenditCheckConnectivity'),
        onPressed: state.busy ? null : notifier.checkConnectivity,
        icon: state.busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.wifi_tethering, size: 16),
        label: Text(state.busy ? 'Checking...' : 'Test API Connectivity'),
      ),
      children: [
        if (connectivity == null)
          const Text(
            'Not checked yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else ...[
          Row(
            children: [
              // Ang chip + ang text ay maaaring mahaba — hindi dapat mag-overflow
              // sa makitid na screen (mobile) o maliit na window (web).
              Flexible(
                child: _statusChip(_verdictLabel(status), _verdictColor(status)),
              ),
              if (connectivity['environment'] != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Key: ${connectivity['key_preview'] ?? '(hidden)'} · '
                    'environment: ${connectivity['environment']}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _kv('Authenticated', connectivity['authenticated'] == true
              ? 'yes'
              : 'no'),
          if (connectivity['http_status'] != null)
            _kv('HTTP status', '${connectivity['http_status']}'),
          if (connectivity['error_code'] != null)
            _kv('Xendit error code', '${connectivity['error_code']}'),
          if (connectivity['latency_ms'] != null)
            _kv('Latency', '${connectivity['latency_ms']} ms'),
          if (connectivity['endpoint'] != null)
            _kv('Endpoint', '${connectivity['endpoint']}'),
          if (connectivity['checked_at'] != null)
            _kv('Checked at', '${connectivity['checked_at']}'),
          if ((connectivity['warning'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${connectivity['warning']}',
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
        ],
      ],
    );
  }

  // ── 2) Test payment request creation ────────────────────────────────────

  Widget _paymentRequestSection(
    XenditDiagnosticsState state,
    XenditDiagnosticsNotifier notifier,
  ) {
    final payment = state.testPayment;
    final actions = (payment?['actions'] as List?) ?? const [];
    // Ang checkout URL (kung mayroon) — para matapos ang sandbox payment.
    String? checkoutUrl;
    for (final action in actions) {
      if (action is Map &&
          action['type'] == 'REDIRECT_CUSTOMER' &&
          action['value'] is String) {
        checkoutUrl = action['value'] as String;
        break;
      }
    }
    return _section(
      title: '2. Sandbox payment request (separate step)',
      subtitle:
          'Creates a clearly-marked TEST payment request via POST /v3/payment_requests. '
          'Creating it does NOT mark any payment as paid.',
      trailing: Wrap(
        spacing: 8,
        children: [
          ElevatedButton.icon(
            key: const ValueKey('xenditCreateTestPayment'),
            onPressed: (state.busy || !state.sandboxTestReady)
                ? null
                : () => notifier.createTestPayment(),
            icon: const Icon(Icons.add_card, size: 16),
            label: const Text('Create Test Payment'),
          ),
          if (state.lastIdempotencyKey != null)
            OutlinedButton.icon(
              key: const ValueKey('xenditReplayTestPayment'),
              onPressed: state.busy
                  ? null
                  : () => notifier.createTestPayment(reuseKey: true),
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Replay (same idempotency key)'),
            ),
        ],
      ),
      children: [
        if (!state.sandboxTestReady)
          const Text(
            'Available after a successful test-key connectivity check '
            '(status: connected, environment: test).',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else if (payment == null)
          const Text(
            'Ready — no sandbox payment request created yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else ...[
          if (state.isDuplicateRequest)
            _statusChip('Idempotent replay (no new record)', AppColors.info),
          if (state.isDuplicateRequest) const SizedBox(height: 8),
          _kv('Payment request ID', '${payment['payment_request_id'] ?? '—'}'),
          _kv('Reference ID', '${payment['reference_id'] ?? '—'}'),
          _kv('Status', '${payment['status'] ?? '—'}'),
          _kv(
            'Amount',
            '${payment['currency'] ?? 'PHP'} ${payment['amount'] ?? payment['request_amount'] ?? '—'}',
          ),
          _kv('Channel', '${payment['channel_code'] ?? '—'}'),
          if (payment['created'] != null) _kv('Created', '${payment['created']}'),

          _kv('Idempotency key', state.lastIdempotencyKey ?? '—'),
          if (checkoutUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                'Checkout URL: $checkoutUrl',
                style: const TextStyle(fontSize: 11, color: AppColors.info),
              ),
            ),
        ],
      ],
    );
  }

  // ── 3) Confirmed payment ───────────────────────────────────────────────

  Widget _confirmedSection(
    XenditDiagnosticsState state,
    XenditDiagnosticsNotifier notifier,
  ) {
    final status = state.testStatus;
    final hasPayment = state.paymentRequestId != null;
    return _section(
      title: '3. Confirmed payment (Xendit-verified)',
      subtitle:
          '"Paid" comes only from Xendit (status API or validated webhook) — '
          'never from the client.',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('xenditRefreshTestStatus'),
            onPressed:
                (state.busy || !hasPayment) ? null : notifier.refreshTestPaymentStatus,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Check Payment Status'),
          ),
          if (hasPayment)
            OutlinedButton.icon(
              key: const ValueKey('xenditSimulateTestPayment'),
              onPressed: state.busy ? null : notifier.simulateTestPayment,
              icon: const Icon(Icons.play_circle_outline, size: 16),
              label: const Text('Simulate Sandbox Payment'),
            ),
        ],
      ),
      children: [
        if (status == null)
          const Text(
            'No status checked yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else ...[
          Row(
            children: [
              Flexible(
                child: _statusChip(
                  state.paymentConfirmed ? 'PAYMENT CONFIRMED' : 'NOT CONFIRMED',
                  state.paymentConfirmed ? AppColors.success : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Xendit status: ${status['status'] ?? 'unknown'}'
                  '${state.testStatusTerminal ? ' (terminal)' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv(
            'Reference ID',
            '${status['reference_id'] ?? '—'}',
          ),
          _kv('Currency', '${status['currency'] ?? '—'}'),
          _kv(
            'Requested amount',
            '${status['request_amount'] ?? '—'}',
          ),
          if (status['recorded'] == true)
            _kv('Status recorded', 'xendit_logs (test row)'),
        ],
      ],
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────

  Widget _section({
    required String title,
    required String subtitle,
    required Widget trailing,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          trailing,
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _verdictLabel(String status) {
    switch (status) {
      case 'connected':
        return 'CONNECTED (authenticated)';
      case 'auth_failed':
        return 'AUTH FAILED (invalid key)';
      case 'permission_denied':
        return 'KEY VALID — PERMISSION DENIED';
      case 'unverified':
        return 'COULD NOT VERIFY';
      default:
        return status.isEmpty ? 'NOT CHECKED' : status.toUpperCase();
    }
  }

  Color _verdictColor(String status) {
    switch (status) {
      case 'connected':
        return AppColors.success;
      case 'auth_failed':
        return AppColors.error;
      case 'permission_denied':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }
}
