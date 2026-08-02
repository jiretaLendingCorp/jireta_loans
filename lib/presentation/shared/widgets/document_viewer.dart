// lib/presentation/shared/widgets/document_viewer.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';

class DocumentViewer extends StatelessWidget {
  final String? url;
  final String? label;
  final double height;

  const DocumentViewer({
    super.key,
    this.url,
    this.label,
    this.height = 200,
  });

  bool get isPdf => url?.toLowerCase().endsWith('.pdf') ?? false;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 48, color: AppColors.textHint),
            SizedBox(height: 8),
            Text('No document',
                style: TextStyle(color: AppColors.textHint, fontSize: 14)),
          ]),
        ),
      );
    }

    if (isPdf) {
      return GestureDetector(
        onTap: () => _openUrl(context, url!),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.picture_as_pdf, size: 48, color: AppColors.error),
            const SizedBox(height: 8),
            Text(label ?? 'PDF Document',
                style: const TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Tap to open',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullScreen(context, url!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            height: height,
            color: AppColors.surfaceGray,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            height: height,
            color: AppColors.surfaceGray,
            child: const Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 48, color: AppColors.textHint)),
          ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context, String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(label ?? 'Document')),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  void _openUrl(BuildContext context, String url) {
    // URL launcher handled by caller
  }
}
