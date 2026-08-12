// lib/presentation/features/head_manager/settings/screens/hm_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';

class HmSettingsScreen extends ConsumerStatefulWidget {
  const HmSettingsScreen({super.key});

  @override
  ConsumerState<HmSettingsScreen> createState() => _HmSettingsScreenState();
}

class _HmSettingsScreenState extends ConsumerState<HmSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      title: 'System Settings',
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.deepNavy,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Roles & Permissions'),
                Tab(text: 'SMS Templates'),
                Tab(text: 'Report Templates'),
                Tab(text: 'System Config'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RolesPermissionsTab(),
                _SmsTemplatesTab(),
                _ReportTemplatesTab(),
                _SystemConfigTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RolesPermissionsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final roles = ['Head Manager', 'Employee', 'Rider', 'Lender'];
    final modules = [
      'Dashboard',
      'Employees',
      'Riders',
      'Lenders',
      'Loans',
      'Account Upgrade',
      'Collections',
      'Payments',
      'Reports',
      'Audit',
      'Settings',
    ];

    final permissions = {
      'Head Manager': List.filled(modules.length, true),
      'Employee': [
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
      ],
      'Rider': [
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false
      ],
      'Lender': [
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false
      ],
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Role-Based Access Control',
            subtitle:
                'View module access permissions for each role. Permissions are enforced server-side.',
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    AppColors.deepNavy.withValues(alpha: 0.05),
                  ),
                  columns: [
                    const DataColumn(
                      label: Text(
                        'Module',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ...roles.map(
                      (r) => DataColumn(
                        label: Text(
                          r,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                  rows: List.generate(modules.length, (i) {
                    return DataRow(
                      cells: [
                        DataCell(Text(modules[i])),
                        ...roles.map((r) {
                          final perm = permissions[r]?[i] ?? false;
                          return DataCell(
                            Icon(
                              perm ? Icons.check_circle : Icons.cancel,
                              color: perm
                                  ? AppColors.success
                                  : AppColors.error.withValues(alpha: 0.3),
                              size: 20,
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All permissions are enforced server-side through Supabase Edge Functions and Row Level Security policies.',
                    style: TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmsTemplatesTab extends StatefulWidget {
  @override
  State<_SmsTemplatesTab> createState() => _SmsTemplatesTabState();
}

class _SmsTemplatesTabState extends State<_SmsTemplatesTab> {
  final _templates = [
    {
      'key': 'payment_reminder',
      'name': 'Payment Reminder',
      'content':
          'Dear {name}, your loan payment of {amount} is due on {due_date}. Please settle on time to avoid penalties. - Jireta Loans & Credit Corp 1966',
    },
    {
      'key': 'otp',
      'name': 'OTP Verification',
      'content':
          'Your Jireta Loans OTP is: {otp}. Valid for 5 minutes. Do not share this code.',
    },
    {
      'key': 'loan_approved',
      'name': 'Loan Approved',
      'content':
          'Dear {name}, your loan of {amount} has been approved and will be disbursed shortly. - Jireta Loans & Credit Corp',
    },
    {
      'key': 'loan_rejected',
      'name': 'Loan Rejected',
      'content':
          'Dear {name}, your loan application has been reviewed and not approved at this time. Please contact our office for more information.',
    },
    {
      'key': 'payment_received',
      'name': 'Payment Received',
      'content':
          'Dear {name}, your payment of {amount} has been received. Remaining balance: {balance}. Thank you! - Jireta Loans',
    },
  ];

  String? _editingKey;
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'SMS Templates',
            subtitle:
                'Manage automated SMS messages sent to lenders and riders.',
          ),
          const SizedBox(height: 20),
          ..._templates.map((t) => _buildTemplateCard(t)),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template) {
    final key = template['key'] as String;
    final isEditing = _editingKey == key;

    if (isEditing) {
      _ctrl.text = template['content'] as String;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEditing ? AppColors.deepNavy : AppColors.border,
          width: isEditing ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  template['key'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.deepNavy,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                template['name'] as String,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (!isEditing)
                TextButton.icon(
                  onPressed: () => setState(() => _editingKey = key),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isEditing) ...[
            TextField(
              controller: _ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'SMS content...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Variables: {name}, {amount}, {due_date}, {balance}, {otp}',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      template['content'] = _ctrl.text;
                      _editingKey = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Template saved'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _editingKey = null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else
            Text(
              template['content'] as String,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportTemplatesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final templates = [
      {
        'key': 'loan_summary',
        'name': 'Loan Summary Report',
        'desc': 'Overview of all loan applications and their statuses.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'collection_report',
        'name': 'Collection Report',
        'desc': 'Summary of all payment collections by riders and methods.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'payment_report',
        'name': 'Payment Report',
        'desc': 'Detailed list of all payments received including GCash.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'borrower_report',
        'name': 'Lender Report',
        'desc': 'List of all registered lenders with their loan status.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'financial_report',
        'name': 'Financial Report',
        'desc': 'Revenue, interest earned, penalties collected breakdown.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'overdue_report',
        'name': 'Overdue Loan Report',
        'desc': 'All loans past their due date with outstanding balances.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'ci_report',
        'name': 'Credit Investigation Report',
        'desc': 'Summary of all CI assignments and their outcomes.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'disbursement_report',
        'name': 'Disbursement Report',
        'desc': 'All loan disbursements by method (GCash, Cash, Rider).',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'rider_report',
        'name': 'Rider Performance Report',
        'desc': 'Collection and CI statistics per rider.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'employee_report',
        'name': 'Employee Activity Report',
        'desc': 'Loans processed and collections assigned per employee.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'account_upgrade_report',
        'name': 'Account Upgrade Verification Report',
        'desc': 'Account upgrade submission and verification status summary.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'audit_report',
        'name': 'Audit Trail Report',
        'desc': 'Complete system audit log export for compliance.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'interest_report',
        'name': 'Interest & Penalty Report',
        'desc': 'Interest earned and penalties applied per period.',
        'formats': ['PDF', 'Excel'],
      },
      {
        'key': 'revenue_report',
        'name': 'Revenue Report',
        'desc': 'Total revenue from interest, penalties, and fees.',
        'formats': ['PDF', 'Excel'],
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Report Templates',
            subtitle:
                'Manage report templates available in the Report Library (${templates.length} templates).',
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              childAspectRatio: 2.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: templates.length,
            itemBuilder: (context, i) {
              final t = templates[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: AppColors.deepNavy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t['name'] as String,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t['desc'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        ...(t['formats'] as List<String>).map(
                          (f) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: f == 'PDF'
                                  ? AppColors.error.withValues(alpha: 0.1)
                                  : AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: f == 'PDF'
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SystemConfigTab extends StatefulWidget {
  @override
  State<_SystemConfigTab> createState() => _SystemConfigTabState();
}

class _SystemConfigTabState extends State<_SystemConfigTab> {
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
    },
    {
      'key': 'penalty_delay_days',
      'label': 'Penalty After (days)',
      'value': '30',
      'type': 'number',
    },
    {
      'key': 'otp_expiry_minutes',
      'label': 'OTP Expiry (minutes)',
      'value': '5',
      'type': 'number',
    },
    {
      'key': 'max_login_attempts',
      'label': 'Max Login Attempts',
      'value': '5',
      'type': 'number',
    },
    {
      'key': 'lockout_minutes',
      'label': 'Account Lockout (minutes)',
      'value': '15',
      'type': 'number',
    },
    {
      'key': 'session_timeout_minutes',
      'label': 'Session Timeout (minutes)',
      'value': '60',
      'type': 'number',
    },
    {
      'key': 'payment_reminder_days_before',
      'label': 'SMS Reminder (days before due)',
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
          const _SectionHeader(
            title: 'System Configuration',
            subtitle:
                'Manage global system parameters. Changes take effect immediately.',
          ),
          const SizedBox(height: 20),
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
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Save Configuration'),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveConfig() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Save System Configuration',
      message:
          'Are you sure you want to update these system settings? Changes will affect all users immediately.',
      confirmLabel: 'Save',
      confirmColor: AppColors.deepNavy,
    );
    if (confirmed == true && mounted) {
      await SuccessDialog.show(
        context,
        title: 'Configuration Saved',
        message: 'System configuration has been updated successfully.',
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
