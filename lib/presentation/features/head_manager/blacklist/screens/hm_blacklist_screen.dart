// lib/presentation/features/head_manager/blacklist/screens/hm_blacklist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/blacklist_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';

class _BlacklistState {
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;

  const _BlacklistState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
  });

  _BlacklistState copyWith({
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
  }) => _BlacklistState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
  );
}

class _BlacklistNotifier extends StateNotifier<_BlacklistState> {
  final BlacklistRemoteDataSource _ds;

  _BlacklistNotifier(this._ds) : super(const _BlacklistState()) {
    fetch();
  }

  Future<void> fetch({int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getBlacklist(page: page);
      final items = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        items: items,
        isLoading: false,
        currentPage: meta['page'] as int? ?? 1,
        totalPages: meta['total_pages'] as int? ?? 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> removeFromBlacklist(String lenderId) async {
    try {
      await _ds.removeFromBlacklist(lenderId: lenderId);
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final _blacklistProvider = StateNotifierProvider<_BlacklistNotifier, _BlacklistState>((ref) {
  return _BlacklistNotifier(sl<BlacklistRemoteDataSource>());
});

class HmBlacklistScreen extends ConsumerWidget {
  const HmBlacklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_blacklistProvider);
    return WebScaffold(
      title: 'Blacklist Management',
      actions: [
        IconButton(
          onPressed: () => ref.read(_blacklistProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 12),
      ],
      body: state.isLoading
          ? const ShimmerLoader()
          : state.items.isEmpty
              ? _buildEmpty()
              : _buildContent(context, ref, state),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, _BlacklistState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, color: AppColors.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Blacklisted Lenders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.error)),
                      Text('${state.items.length} lender(s) are currently blacklisted', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                _buildHeader(),
                const Divider(height: 1),
                ...state.items.asMap().entries.map((e) => _buildRow(context, ref, e.value, e.key.isEven)),
              ],
            ),
          ),
          if (state.totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: state.currentPage > 1 ? () => ref.read(_blacklistProvider.notifier).fetch(page: state.currentPage - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page ${state.currentPage} of ${state.totalPages}'),
                  IconButton(
                    onPressed: state.currentPage < state.totalPages ? () => ref.read(_blacklistProvider.notifier).fetch(page: state.currentPage + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    const s = TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('LENDER', style: s)),
          Expanded(flex: 2, child: Text('PHONE', style: s)),
          Expanded(flex: 3, child: Text('REASON', style: s)),
          Expanded(flex: 2, child: Text('BLACKLISTED BY', style: s)),
          Expanded(flex: 2, child: Text('DATE', style: s)),
          Expanded(flex: 1, child: Text('ACTION', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, Map<String, dynamic> item, bool isEven) {
    final lender = item['lender'] as Map<String, dynamic>? ?? {};
    final blacklistedBy = item['blacklisted_by_user'] as Map<String, dynamic>? ?? {};
    return Container(
      color: isEven ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.errorLight,
                  child: Icon(Icons.block, size: 16, color: AppColors.error),
                ),
                const SizedBox(width: 10),
                Text('${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(_maskPhone(lender['phone_number'] as String? ?? '-'), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
            flex: 3,
            child: Text(
              item['reason'] as String? ?? '-',
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${blacklistedBy['first_name'] ?? ''} ${blacklistedBy['last_name'] ?? ''}'.trim(),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(item['created_at']),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 1,
            child: TextButton(
              onPressed: () => _confirmRemove(context, ref, item['lender_id'] as String? ?? ''),
              child: const Text('Remove', style: TextStyle(color: AppColors.success, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: AppColors.success),
            SizedBox(height: 16),
            Text('No blacklisted lenders', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            SizedBox(height: 8),
            Text('All lenders are in good standing', style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
          ],
        ),
      );

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String lenderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from Blacklist'),
        content: const Text('Are you sure you want to remove this lender from the blacklist?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      final ok = await ref.read(_blacklistProvider.notifier).removeFromBlacklist(lenderId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Removed from blacklist' : 'Failed to remove'), backgroundColor: ok ? AppColors.success : AppColors.error),
        );
      }
    }
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)}****${p.substring(p.length - 3)}';
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('MMM dd, yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }
}