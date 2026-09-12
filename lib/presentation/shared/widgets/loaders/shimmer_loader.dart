// lib/presentation/shared/widgets/loaders/shimmer_loader.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_colors.dart';

class ShimmerLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    // Dark mode: itim / dark gray ang shimmer (hindi puting block sa dark bg).
    final base =
        context.isDarkMode ? AppColors.darkShimmerBase : AppColors.shimmerBase;
    final highlight = context.isDarkMode
        ? AppColors.darkShimmerHighlight
        : AppColors.shimmerHighlight;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final base =
        context.isDarkMode ? AppColors.darkShimmerBase : AppColors.shimmerBase;
    final highlight = context.isDarkMode
        ? AppColors.darkShimmerHighlight
        : AppColors.shimmerHighlight;
    final surface = context.isDarkMode ? AppColors.darkSurface : Colors.white;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 14, color: base, width: 100),
            const SizedBox(height: 8),
            Container(height: 28, color: base, width: 140),
            const SizedBox(height: 6),
            Container(height: 12, color: base, width: 80),
          ],
        ),
      ),
    );
  }
}
