// lib/presentation/features/head_manager/notifications/screens/hm_notification_center_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/hm_notification_provider.dart';

class HmNotificationCenterScreen extends ConsumerStatefulWidget {
  const HmNotificationCenterScreen({super.key});

  @override
  ConsumerState<HmNotificationCenterScreen> createState() =>
      _HmNotificationCenterScreenState();
}

class _HmNotificationCenterScreenState
    extends ConsumerState<HmNotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmNotificationProvider);

    return WebScaffold(
      title: 'Notification Center',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showSendModal(context),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send Notification'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
          ),
        ),
        const SizedBox(width: 12),
        if (state.notifications.any((n) => !n.isRead))
          TextButton(
            onPressed: () =>
                ref.read(hmNotificationProvider.notifier).markAllRead(),
            child: const Text('Mark All Read',
                style: TextStyle(color: AppColors.deepNavy)),
          ),
        const SizedBox(width: 8),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: const [
                Tab(text: 'Notifications'),
                Tab(text: 'SMS Logs'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildNotifications(state),
                _buildSmsLogs(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications(HmNotificationState state) {
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: List.generate(
              5,
              (i) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: ShimmerLoader(height: 80),
                  )),
        ),
      );
    }
    if (state.notifications.isEmpty) {
      return const EmptyStateWidget(
        title: 'No Notifications',
        message: 'Notifications will appear here',
        icon: Icons.notifications_none,
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(hmNotificationProvider.notifier).loadNotifications(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _NotifCard(
          notif: state.notifications[i],
          onMarkRead: () => ref
              .read(hmNotificationProvider.notifier)
              .markRead(state.notifications[i].id),
        ),
      ),
    );
  }

  Widget _buildSmsLogs(HmNotificationState state) {
    if (state.smsLogs.isEmpty) {
      return const EmptyStateWidget(
        title: 'No SMS Logs',
        message: 'SMS reminders sent to lenders appear here',
        icon: Icons.sms_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.smsLogs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final log = state.smsLogs[i];
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppColors.infoLight,
            child: Icon(Icons.sms, color: AppColors.info, size: 18),
          ),
          title: Text(log['recipient'] ?? 'Unknown',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(log['message'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            log['sent_at'] != null
                ? DateFormat('MMM d, h:mm a')
                    .format(DateTime.parse(log['sent_at']))
                : '',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        );
      },
    );
  }

  void _showSendModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SendNotifDialog(
        onSend: (userId, title, body, type) async {
          await ref.read(hmNotificationProvider.notifier).sendNotification(
                userId: userId,
                title: title,
                body: body,
                type: type,
              );
        },
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final NotificationModel notif;
  final VoidCallback onMarkRead;

  const _NotifCard({required this.notif, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: notif.isRead ? Colors.white : AppColors.infoLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: notif.isRead
                ? AppColors.border
                : AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications,
                size: 18, color: AppColors.deepNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notif.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(notif.body,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d, y h:mm a').format(notif.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          if (!notif.isRead)
            TextButton(
              onPressed: onMarkRead,
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              child: const Text('Mark Read',
                  style: TextStyle(fontSize: 11, color: AppColors.info)),
            ),
        ],
      ),
    );
  }
}

class _SendNotifDialog extends StatefulWidget {
  final Future<void> Function(
      String userId, String title, String body, String type) onSend;

  const _SendNotifDialog({required this.onSend});

  @override
  State<_SendNotifDialog> createState() => _SendNotifDialogState();
}

class _SendNotifDialogState extends State<_SendNotifDialog> {
  final _userIdCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _type = 'general';
  bool _loading = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Notification',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Recipient User ID', _userIdCtrl, hint: 'Enter user ID'),
            const SizedBox(height: 12),
            _field('Title', _titleCtrl, hint: 'Notification title'),
            const SizedBox(height: 12),
            _field('Message', _bodyCtrl,
                hint: 'Notification body', maxLines: 3),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: 'Type',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General')),
                DropdownMenuItem(value: 'loan', child: Text('Loan')),
                DropdownMenuItem(value: 'payment', child: Text('Payment')),
                DropdownMenuItem(
                    value: 'collection', child: Text('Collection')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _loading ? null : _send,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Send'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Future<void> _send() async {
    if (_userIdCtrl.text.isEmpty ||
        _titleCtrl.text.isEmpty ||
        _bodyCtrl.text.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.onSend(_userIdCtrl.text.trim(), _titleCtrl.text.trim(),
          _bodyCtrl.text.trim(), _type);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _loading = false);
    }
  }
}
