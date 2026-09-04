// lib/presentation/features/head_manager/dashboard/widgets/hm_ask_ai_sheet.dart
//
// Compact "Ask AI" feature: a floating chat button that opens a small panel
// where the Head Manager can ask natural-language questions about the lending
// data. Every question goes through the ai-dashboard-insights Edge Function —
// the AI answers only from verified aggregated statistics, and sensitive/
// PII requests are refused server-side.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_ai_provider.dart';

const _suggestedQuestions = [
  'How many loans are overdue?',
  'How much did we collect this month?',
  'Compare this month with last month.',
  'Summarize our current lending performance.',
];

/// Floating action button that opens the Ask AI panel.
class AskAiFab extends ConsumerWidget {
  /// YYYY-MM of the dashboard month the chat should analyze with.
  final String month;
  const AskAiFab({super.key, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => showAskAiSheet(context, month: month),
      backgroundColor: AppColors.deepNavy,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gold, AppColors.goldDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
      ),
      label: const Text(
        'Ask AI',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

/// Opens the Ask AI chat panel as a modal bottom sheet.
void showAskAiSheet(BuildContext context, {required String month}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AskAiSheet(month: month),
  );
}

class _AskAiSheet extends ConsumerStatefulWidget {
  final String month;
  const _AskAiSheet({required this.month});

  @override
  ConsumerState<_AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends ConsumerState<_AskAiSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _showSuggestions = true;

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

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Header
              _header(context),
              const Divider(height: 1, color: AppColors.divider),
              // Messages + suggestions
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(14),
                  children: [
                    _aiBubble(
                      'I can answer questions from verified dashboard '
                      'statistics \u2014 loan counts, collections, financial '
                      'totals and trends. I cannot access individual '
                      'borrower details.',
                    ),
                    const SizedBox(height: 12),
                    if (chat.messages.isEmpty && _showSuggestions)
                      _suggestions(ctx)
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
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // Input bar
              _inputBar(context),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.deepNavy, AppColors.navyLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 20, color: AppColors.goldLight),
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
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _suggestions(BuildContext ctx) {
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
                borderRadius: BorderRadius.circular(8)),
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
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: const BoxDecoration(
          color: AppColors.deepNavy,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(3),
          ),
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
              gradient: const LinearGradient(
                colors: [AppColors.gold, AppColors.goldDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 13, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
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

  Widget _inputBar(BuildContext ctx) {
    final chat = ref.watch(hmAiChatProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: TextField(
                  controller: _input,
                  enabled: !chat.isBusy,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (v) => _send(v),
                  decoration: const InputDecoration(
                    hintText: 'Ask about your lending data...',
                    hintStyle: TextStyle(
                        fontSize: 12.5, color: AppColors.textHint),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: chat.isBusy ? null : () => _send(_input.text),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.deepNavy,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}