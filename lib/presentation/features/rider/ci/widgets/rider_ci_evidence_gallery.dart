// lib/presentation/features/rider/ci/widgets/rider_ci_evidence_gallery.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

class RiderCiEvidenceGallery extends StatelessWidget {
  final List<Map<String, dynamic>> documents;
  const RiderCiEvidenceGallery({super.key, required this.documents});

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.photo_library_outlined,
                size: 48, color: AppColors.textTertiary),
            SizedBox(height: 8),
            Text('No photos uploaded yet',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: documents.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (ctx, i) {
        final doc = documents[i];
        final url = doc['file_url'] as String? ?? '';
        final caption = doc['caption'] as String?;
        final lat = doc['latitude'] as num?;
        final lng = doc['longitude'] as num?;

        return _GalleryItem(
          url: url,
          caption: caption,
          lat: lat?.toDouble(),
          lng: lng?.toDouble(),
          onTap: () => _showFullImage(ctx, url, caption),
        );
      },
    );
  }

  void _showFullImage(BuildContext context, String url, String? caption) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
            if (caption != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.all(12),
                  child: Text(caption,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryItem extends StatelessWidget {
  final String url;
  final String? caption;
  final double? lat;
  final double? lng;
  final VoidCallback onTap;

  const _GalleryItem({
    required this.url,
    this.caption,
    this.lat,
    this.lng,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: AppColors.shimmerBase,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textTertiary, size: 36),
              ),
            ),
            if (lat != null && lng != null)
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on,
                          size: 10, color: Colors.white),
                      const SizedBox(width: 2),
                      Text(
                        '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}',
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            if (caption != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    caption!,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
