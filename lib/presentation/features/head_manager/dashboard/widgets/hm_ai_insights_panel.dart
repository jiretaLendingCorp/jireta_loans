// lib/presentation/features/head_manager/dashboard/widgets/hm_ai_insights_panel.dart
//
// "AI-Powered Dashboard Insights" section — a natural extension of the
// existing dashboard (same card style, grey header strip, colors). All
// content is generated server-side by the ai-dashboard-insights Edge
// Function from the CURRENT verified dashboard statistics. If the AI service
// is unavailable, this panel shows a friendly error and the rest of the
// dashboard keeps working untouched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/ai_insights_model.dart';
import '../providers/hm_ai_provider.dart';

class HmAiInsightsPanel extends ConsumerWidget {
  /// YYYY-MM of the dashboard month being analyzed.
  final String month;
  const HmAiInsightsPanel({super.key, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(hmAiInsightsProvider);
    final notifier = ref.read(hmAiInsightsProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grey header strip (gaya ng lahat ng dashboard cards)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF5C6370),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.gold, AppColors.goldDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 14, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-Powered Dashboard Insights',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'AI analysis based on current lending system data',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (ai.hasInsights)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.18),
                      border: Border.all(
                          color: AppColors.riderGreen.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: const Text(
                      'AI READY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ai.isLoading)
                  _buildLoading(context, phase: ai.phase)
                else if (ai.error != null && !ai.hasInsights)
                  _buildError(context, ai.error!, onRetry: () {
                    notifier.generate(month: month);
                  })
                else if (ai.hasInsights)
                  _buildInsights(
                    context,
                    ai.insights!,
                    month: month,
                    onRegenerate: () => notifier.generate(month: month),
                  )
                else
                  _buildIdle(context, onGenerate: () {
                    notifier.generate(month: month);
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Idle: Generate Insights ─────────────────────────────────────────────
  Widget _buildIdle(BuildContext context, {required VoidCallback onGenerate}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.deepNavy, AppColors.navyLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.zero,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppColors.goldLight),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get a professional AI read on your current data',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Summary, trends, attention flags and recommendations \u2014 '
                    'generated only from the verified statistics shown above.',
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Generate Insights'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
          ),
        ),
      ],
    );
  }

  // ── Loading with phase labels ────────────────────────────────────────────
  Widget _buildLoading(BuildContext context, {required String phase}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.deepNavy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(
              phase == 'generating'
                  ? 'Generating AI insights...'
                  : 'Analyzing lending data...',
              key: ValueKey(phase),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The AI only reads aggregated statistics from the backend \u2014 '
            'no financial values are modified.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Error state (AI failure never breaks the dashboard) ─────────────────
  Widget _buildError(BuildContext context, String message,
      {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 18, color: AppColors.error),
              SizedBox(width: 8),
              Text(
                'Unable to generate AI insights right now. Please try again.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Generated result ─────────────────────────────────────────────────────
  Widget _buildInsights(BuildContext context, AiInsightsModel insights,
      {required String month, required VoidCallback onRegenerate}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month changed since generation → hint to regenerate.
        if (insights.month != null && insights.month != month) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
            ),
            child: Text(
              'These insights cover ${insights.month} — the dashboard is now '
              'showing $month. Regenerate to analyze the current month.',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Regenerate Insights'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepNavy,
              side: const BorderSide(color: AppColors.borderDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          icon: Icons.assessment_rounded,
          title: 'Overall Performance',
          color: AppColors.deepNavy,
          child: Text(
            insights.summary,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.trending_up_rounded,
          title: 'Key Trends',
          color: AppColors.lenderBlue,
          child: _BulletList(
            items: insights.trends,
            color: AppColors.lenderBlue,
            icon: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.warning_amber_rounded,
          title: 'Attention Required',
          color: AppColors.statusOverdue,
          child: insights.attention.isEmpty
              ? const Text(
                  'No specific attention flags reported by the AI.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textTertiary),
                )
              : _BulletList(
                  items: insights.attention,
                  color: AppColors.statusOverdue,
                  icon: Icons.warning_amber_rounded,
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Recommendations',
          color: AppColors.goldDark,
          child: insights.recommendations.isEmpty
              ? const Text(
                  'No recommendations generated.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textTertiary),
                )
              : _BulletList(
                  items: insights.recommendations,
                  color: AppColors.goldDark,
                  icon: Icons.lightbulb_outline_rounded,
                ),
        ),
        const SizedBox(height: 16),
        if (insights.disclaimer.isNotEmpty) ...[
          Text(
            insights.disclaimer,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary,
                height: 1.35),
          ),
          const SizedBox(height: 6),
        ],
        _footer(insights),
      ],
    );
  }

  Widget _footer(AiInsightsModel insights) {
    String label;
    if (insights.month != null) {
      final parts = insights.month!.split('-');
      final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final monthLabel = (m >= 1 && m <= 12) ? '${months[m - 1]} ${parts[0]}' : insights.month!;
      label = '${insights.period == 'monthly' ? 'Monthly analysis' : 'Lifetime analysis'} — $monthLabel';
    } else {
      label = 'Lifetime analysis';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_alt_rounded,
              size: 15, color: AppColors.goldDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Generated by AI • Updated: ${_formatTimestamp(insights.generatedAt)} • $label',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final sameDay = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    if (sameDay) return 'Today, $time';
    return '${two(dt.month)}/${two(dt.day)}/${dt.year}, $time';
  }
}

// ── Section header + content ───────────────────────────────────────────────
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Expanded(
              child: Divider(color: AppColors.divider, height: 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// ── Bullet list ────────────────────────────────────────────────────────────
class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color color;
  final IconData icon;
  const _BulletList({
    required this.items,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No items.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      );
    }
    return Column(
      children: List.generate(items.length, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < items.length - 1 ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  items[i],
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}