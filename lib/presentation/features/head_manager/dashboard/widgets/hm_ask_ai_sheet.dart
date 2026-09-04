// lib/presentation/features/head_manager/dashboard/widgets/hm_ask_ai_sheet.dart
//
// "Ask AI" — a compact catalog-style modal anchored to the RIGHT side of the
// screen, floating just above the "Ask AI" button. Includes a Recent chats
// list (persisted locally) so the user can reopen earlier conversations.
//
// Every question goes through the ai-dashboard-insights Edge Function — the
// AI answers only from verified aggregated statistics, and sensitive/PII
// requests are refused server-side.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/asset_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_ai_provider.dart';

const _suggestedQuestions = [
  'How many loans are overdue?',
  'How much did we collect this month?',
  'Compare this month with last month.',
  'Summarize our current lending performance.',
];

/// Compact pill button (height matched to the modal's input text box, uses
/// the Ask AI.png asset) that opens the modal.
class AskAiFab extends ConsumerWidget {
  /// YYYY-MM of the dashboard month the chat should analyze with.
  final String month;
  const AskAiFab({super.key, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.deepNavy,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAskAiDialog(context, month: month),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AssetConstants.askAiIcon,
                  width: 18,
                  height: 18,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppColors.goldLight,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Ask AI',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Ask AI modal anchored to the right side, floating above the
/// Ask AI button (bottom-right of the dashboard).
void showAskAiDialog(BuildContext context, {required String month}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => Stack(
      children: [
        Positioned(
          right: 24,
          bottom: 100,
          child: _AskAiModal(month: month),
        ),
      ],
    ),
  );
}

class _AskAiModal extends ConsumerStatefulWidget {
  final String month;
  const _AskAiModal({required this.month});

  @override
  ConsumerState<_AskAiModal> createState() => _AskAiModalState();
}

class _AskAiModalState extends ConsumerState<_AskAiModal> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _showSuggestions = true;
  bool _showRecent = false;

  @override
  void initState() {
    super.initState();
    // Make sure the locally-persisted Recent list is loaded up front.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(hmAiChatProvider.notifier).refreshRecent();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String question) {
    final text = question.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() => _showSuggestions = false);
    ref.read(hmAiChatProvider.notifier).ask(
          question: text,
          month: widget.month,
        );
  }

  void _newChat() {
    ref.read(hmAiChatProvider.notifier).clear();
    _input.clear();
    setState(() {
      _showSuggestions = true;
      _showRecent = false;
    });
  }

  void _openRecent(SavedAiChat chat) {
    ref.read(hmAiChatProvider.notifier).openSaved(chat);
    setState(() {
      _showSuggestions = false;
      _showRecent = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(hmAiChatProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final modalW = screenW < 520 ? screenW - 48 : 480.0;
    final modalH = screenH < 640 ? screenH - 160 : 560.0;

    return SizedBox(
      width: modalW,
      height: modalH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.white,
          elevation: 12,
          shadowColor: Colors.black26,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context, chat),
              const Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: _showRecent
                    ? _recentList(chat)
                    : _chatList(chat),
              ),
              const Divider(height: 1, color: AppColors.divider),
              _inputBar(chat),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _header(BuildContext context, HmAiChatState chat) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              AssetConstants.askAiIcon,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: AppColors.goldLight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask AI',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Ask questions about your lending data',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          _headerChip(
            icon: Icons.history_rounded,
            label: 'Recent',
            active: _showRecent,
            tooltip: 'Recent chats',
            onTap: () => setState(() => _showRecent = !_showRecent),
          ),
          const SizedBox(width: 4),
          _headerChip(
            icon: Icons.add_comment_rounded,
            label: 'New Chat',
            active: false,
            tooltip: 'Save this chat and start a new one',
            onTap: _newChat,
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _headerChip({
    required IconData icon,
    required String label,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.gold.withValues(alpha: 0.22)
                : AppColors.deepNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: AppColors.goldDark.withValues(alpha: 0.6))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: active ? AppColors.goldDark : AppColors.deepNavy),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.goldDark : AppColors.deepNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat view ────────────────────────────────────────────────────────────
  Widget _chatList(HmAiChatState chat) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      children: [
        if (chat.messages.isEmpty && _showSuggestions)
          _suggestions()
        else ...[
          for (final msg in chat.messages) ...[
            if (msg.role == 'user')
              _userBubble(msg.text)
            else
              _aiBubble(msg.text),
            const SizedBox(height: 12),
          ],
          if (chat.isBusy) ...[
            _aiBubble('Analyzing your question...', busy: true),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  // ── Recent chats view ────────────────────────────────────────────────────
  Widget _recentList(HmAiChatState chat) {
    final notifier = ref.read(hmAiChatProvider.notifier);
    if (chat.recentChats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 34, color: AppColors.textTertiary),
              SizedBox(height: 10),
              Text(
                'No recent chats yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Ask a question, then tap "New Chat" to save it here '
                'so you can come back to it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: chat.recentChats.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: AppColors.divider,
      ),
      itemBuilder: (context, i) {
        final saved = chat.recentChats[i];
        return InkWell(
          onTap: () => _openRecent(saved),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 17, color: AppColors.deepNavy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        saved.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${saved.messages.length} messages • ${_timeLabel(saved.updatedAt)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => notifier.removeSaved(saved.id),
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 17, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _timeLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(local.hour)}:${two(local.minute)}';
    if (sameDay) return 'Today $hm';
    return '${two(local.month)}/${two(local.day)}/${local.year} $hm';
  }

  Widget _suggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggested questions',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        for (final q in _suggestedQuestions) ...[
          ActionChip(
            onPressed: () => _send(q),
            backgroundColor: AppColors.deepNavy.withValues(alpha: 0.05),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            label: Text(
              q,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.deepNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.deepNavy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            color: Colors.white,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _aiBubble(String text, {bool busy = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(7),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              AssetConstants.askAiIcon,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.auto_awesome_rounded,
                size: 13,
                color: AppColors.goldLight,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: busy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Thinking...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar — ONE unified box (no nested/divided boxes) ───────────────
  Widget _inputBar(HmAiChatState chat) {
    final canSend = !chat.isBusy;
    const boxHeight = 46.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              height: boxHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.deepNavy, width: 1.4),
              ),
              child: TextField(
                controller: _input,
                enabled: canSend,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.center,
                onSubmitted: (v) => _send(v),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask about your lending data...',
                  hintStyle:
                      TextStyle(fontSize: 14, color: AppColors.textHint),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  border: InputBorder.none,
                  isCollapsed: false,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: boxHeight,
            height: boxHeight,
            child: Material(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: canSend ? () => _send(_input.text) : null,
                child: Center(
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: canSend ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}