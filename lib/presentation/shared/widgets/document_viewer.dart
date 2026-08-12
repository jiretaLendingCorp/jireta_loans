// lib/presentation/shared/widgets/document_viewer.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../core/theme/app_colors.dart';

class DocumentViewer extends StatefulWidget {
  final String? url;
  final String? label;
  final double height;
  final String bucket;

  const DocumentViewer({
    super.key,
    this.url,
    this.label,
    this.height = 200,
    this.bucket = 'account-upgrade-documents',
  });

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.bucket != widget.bucket) {
      _resolve();
    }
  }

  /// `url` may be a full http(s) URL or a relative storage path (e.g.
  /// `account-upgrade/{id}/{file}.jpg`). The account-upgrade-documents bucket
  /// is private, so relative paths must be resolved to a signed URL before
  /// they can be displayed.
  Future<void> _resolve() async {
    final url = widget.url;
    if (url == null || url.isEmpty || url.startsWith('http')) {
      if (mounted && _resolved != url) setState(() => _resolved = url);
      return;
    }
    try {
      final signed = await SupabaseStorageService.instance
          .getSignedUrl(bucket: widget.bucket, path: url);
      if (mounted) setState(() => _resolved = signed);
    } catch (_) {
      if (mounted) setState(() => _resolved = null);
    }
  }

  bool get isPdf => widget.url?.toLowerCase().endsWith('.pdf') ?? false;

  @override
  Widget build(BuildContext context) {
    final url = _resolved;
    if (url == null || url.isEmpty) {
      return Container(
        height: widget.height,
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
        onTap: () => _openUrl(context, url),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.picture_as_pdf, size: 48, color: AppColors.error),
            const SizedBox(height: 8),
            Text(widget.label ?? 'PDF Document',
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
      onTap: () => _showFullScreen(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            height: widget.height,
            color: AppColors.surfaceGray,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            height: widget.height,
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
            title: Text(widget.label ?? 'Document')),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  void _openUrl(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open PDF'),
        content: Text(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
