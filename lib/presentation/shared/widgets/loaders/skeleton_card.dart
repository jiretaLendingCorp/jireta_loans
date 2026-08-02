// lib/presentation/shared/widgets/loaders/skeleton_card.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SkeletonCard extends StatelessWidget {
  final double height;
  final double? width;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;

  const SkeletonCard({
    super.key,
    this.height = 120,
    this.width,
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        width: width ?? double.infinity,
        margin: margin ?? const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class SkeletonKpiCard extends StatelessWidget {
  const SkeletonKpiCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Container(width: 80, height: 14, color: Colors.white),
            ]),
            Container(width: 100, height: 24, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(height: 14, color: Colors.white),
                const SizedBox(height: 8),
                Container(height: 12, width: 120, color: Colors.white),
              ])),
        ]),
      ),
    );
  }
}
