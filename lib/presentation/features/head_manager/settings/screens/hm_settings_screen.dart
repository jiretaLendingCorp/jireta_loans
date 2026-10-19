// lib/presentation/features/head_manager/settings/screens/hm_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../domain/repositories/i_system_repository.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/providers/loan_settings_provider.dart';
import '../providers/hm_settings_provider.dart';

class HmSettingsScreen extends StatelessWidget {
  const HmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // System Config lang ang laman ng page na ito (Roles & Permissions, SMS
    // Templates, at Report Templates ay tinanggal).
    return WebScaffold(
      title: 'Settings',
      body: _SystemConfigTab(),
    );
  }
}

class _SystemConfigTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SystemConfigTab> createState() => _SystemConfigTabState();
}

class _SystemConfigTabState extends ConsumerState<_SystemConfigTab> {
  /// Mga config key na may row sa `system_config` - ito lang ang ise-save
  /// (may mga field sa screen na wala pang DB row).
  final Set<String> _serverKeys = {};
  bool _saving = false;
  final _configs = [
    {
      'key': 'min_loan_amount',
      'label': 'Minimum Loan Amount (₱)',
      'value': '3000',
      'type': 'number',
    },
    {
      'key': 'max_loan_amount',
      'label': 'Maximum Loan Amount (₱)',
      'value': '500000',
      'type': 'number',
    },
    {
      'key': 'interest_rate',
      'label': 'Interest Rate (%)',
      'value': '20',
      'type': 'number',
    },
    {
      'key': 'penalty_rate',
      'label': 'Penalty Rate (%)',
      'value': '20',
      'type': 'number',
      // Naka-fix ang penalty sa 20% - hindi ito binabago ng Head Manager.
      'locked': 'true',
    },
    {
      'key': 'penalty_delay_days',
      'label': 'Penalty After (days)',
      'value': '30',
      'type': 'number',
    },
    {
      'key': 'payment_reminder_days',
      'label': 'Payment Reminder (days before due)',
      'value': '2',
      'type': 'number',
    },
  ];

  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    for (final c in _configs) {
      _ctrls[c['key']!] = TextEditingController(text: c['value']);
    }
    // I-load ang aktwal na values mula sa `system_config` (interest rate, atbp.)
    // pagkatapos ng unang frame - hindi sa build, para hindi mag-setState habang
    // nagbu-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromServer());
  }

  Future<void> _loadFromServer() async {
    try {
      final configs = await ref.read(systemConfigProvider.future);
      if (!mounted) return;
      final byKey = <String, String>{};
      for (final c in configs) {
        if (c is! Map) continue;
        final key = (c['config_key'] ?? '').toString();
        if (key.isEmpty) continue;
        byKey[key] = (c['config_value'] ?? '').toString().trim();
      }
      setState(() {
        _serverKeys
          ..clear()
          ..addAll(byKey.keys);
        for (final cfg in _configs) {
          final key = cfg['key']!;
          // Naka-lock ang penalty rate sa 20% - hindi ito kinukuha/babaguhin.
          if (cfg['locked'] == 'true') continue;
          final serverValue = byKey[key];
          if (serverValue != null && serverValue.isNotEmpty) {
            _ctrls[key]?.text = serverValue;
          }
        }
      });
    } catch (_) {
      // Manatili sa defaults kapag bigong mag-load - hindi dapat mabara ang tab.
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                ..._configs.map((c) => _buildConfigRow(c)),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _saveConfig,
                      icon: const Icon(Icons.save, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save Configuration'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _resetDefaults,
                      child: const Text('Reset to Defaults'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Nakatago ang Xendit sandbox diagnostics card.
        ],
      ),
    );
  }

  Widget _buildConfigRow(Map<String, String> config) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              config['label']!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _ctrls[config['key']]!,
              enabled: config['locked'] != 'true',
              keyboardType: config['type'] == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixText: config['locked'] == 'true' ? 'fixed' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveConfig() async {
    // Ang interest rate ang kritikal na value - 0-100 lang ang tinatanggap
    // (katugma ng DB check ng `loans.interest_rate`).
    final rateText = _ctrls['interest_rate']?.text.trim() ?? '';
    final rate = double.tryParse(rateText);
    if (rate == null || rate < 0 || rate > 100) {
      await showErrorDialog(
        context,
        title: 'Invalid Interest Rate',
        message: 'Interest rate must be a number between 0 and 100.',
      );
      return;
    }

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Save System Configuration',
      message:
          'Are you sure you want to update these system settings? Changes will affect all users immediately.',
      confirmLabel: 'Save',
      confirmColor: AppColors.deepNavy,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    // Direkta sa repository (hindi sa AutoDispose notifier) — hindi kasi
    // naka-watch ang `hmSettingsProvider` sa build, kaya puwede itong ma-dispose
    // habang naghihintay ng network at sumabog kapag nag-set ng state.
    final repo = sl<ISystemRepository>();
    var allSaved = true;
    // I-save lang ang mga key na may row sa DB (at hindi naka-lock).
    for (final cfg in _configs) {
      final key = cfg['key']!;
      if (cfg['locked'] == 'true') continue;
      if (!_serverKeys.contains(key)) continue;
      final value = _ctrls[key]?.text.trim() ?? '';
      if (value.isEmpty) continue;
      try {
        await repo.updateSystemConfig(key, value);
      } catch (_) {
        allSaved = false;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (allSaved) {
      ref.invalidate(systemConfigProvider);
      // Agad na mapalitan ang min/max sa Apply Loan / In-Office wizard
      // (realtime din ang provider, pero sigurado dito sa parehong app).
      ref.invalidate(loanSettingsProvider);
      await SuccessDialog.show(
        context,
        title: 'Configuration Saved',
        message: 'System configuration has been updated successfully.',
      );
    } else {
      await showErrorDialog(
        context,
        title: 'Save Failed',
        message: 'Some settings could not be saved. Please try again.',
      );
    }
  }

  Future<void> _resetDefaults() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Reset to Defaults',
      message: 'Reset all configuration values to their default settings?',
      confirmLabel: 'Reset',
      confirmColor: AppColors.warning,
    );
    if (confirmed == true) {
      setState(() {
        for (final c in _configs) {
          _ctrls[c['key']]?.text = c['value']!;
        }
      });
    }
  }
}
