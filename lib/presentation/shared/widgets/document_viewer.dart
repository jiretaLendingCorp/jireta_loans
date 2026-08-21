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
  static const double _maxScale = 6.0;
  static const double _buttonZoomStep = 1.25;

  final TransformationController _inlineTransformer =
      TransformationController();
  final GlobalKey _inlineViewerKey = GlobalKey();
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
    // Rebuild on inline zoom changes so +/− enable/disable states stay fresh.
    _inlineTransformer.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant DocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.bucket != widget.bucket) {
      _resolve();
      _inlineTransformer.value = Matrix4.identity();
    }
  }

  double get _inlineScale => _inlineTransformer.value.getMaxScaleOnAxis();

  /// Zooms the inline preview by [factor], anchored to the preview's center.
  void _zoomInline(double factor) {
    final box =
        _inlineViewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || size.isEmpty) return;
    final m = _inlineTransformer.value;
    final sOld = m.getMaxScaleOnAxis();
    final sNew = (sOld * factor).clamp(1.0, _maxScale).toDouble();
    if (sNew == sOld) return;
    final t = m.getTranslation();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final childX = (cx - t.x) / sOld;
    final childY = (cy - t.y) / sOld;
    _inlineTransformer.value = Matrix4.identity()
      ..translateByDouble(cx - sNew * childX, cy - sNew * childY, 0, 1)
      ..scaleByDouble(sNew, sNew, 1, 1);
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
  void dispose() {
    _inlineTransformer.dispose();
    super.dispose();
  }

  Widget _viewButton({required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text('VIEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineZoomButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? Colors.black.withValues(alpha: 0.65)
            : Colors.black.withValues(alpha: 0.25),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }

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
      child: Stack(
        children: [
          Container(
            height: widget.height,
            width: double.infinity,
            color: Colors.white,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // BoxFit.contain (not cover) so the whole document stays visible —
              // cover crops edges, which hides parts of IDs / payslips.
              // InteractiveViewer lets the preview itself be pinched/panned,
              // and the +/− buttons above drive the same transformation.
              child: InteractiveViewer(
                key: _inlineViewerKey,
                transformationController: _inlineTransformer,
                // Zoom ONLY via the +/− buttons. All gesture/pointer zoom and
                // pan are disabled so mouse-wheel & trackpad scroll fall
                // through to the page (IV would otherwise hijack them —
                // trackpad scroll is even treated as pan internally).
                scaleEnabled: false,
                panEnabled: false,
                minScale: 1.0,
                maxScale: _maxScale,
                child: CachedNetworkImage(
                  imageUrl: url,
                  height: widget.height,
                  width: double.infinity,
                  fit: BoxFit.contain,
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
            ),
          ),
          // Controls OUTSIDE the image, at the TOP: VIEW | + | −
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewButton(onTap: () => _showFullScreen(context, url)),
                const SizedBox(width: 6),
                _inlineZoomButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  enabled: _inlineScale < _maxScale,
                  onTap: () => _zoomInline(_buttonZoomStep),
                ),
                const SizedBox(width: 4),
                _inlineZoomButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  enabled: _inlineScale > 1.05,
                  onTap: () => _zoomInline(1 / _buttonZoomStep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreen(BuildContext context, String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullscreenDocument(
        imageUrl: imageUrl,
        label: widget.label ?? 'Document',
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

/// Full-screen document page. Zoom is controlled ONLY by the − / + / reset
/// buttons (top-right); dragging pans the document while zoomed.
class FullscreenDocument extends StatefulWidget {
  final String imageUrl;
  final String label;

  const FullscreenDocument({
    super.key,
    required this.imageUrl,
    required this.label,
  });

  @override
  State<FullscreenDocument> createState() => _FullscreenDocumentState();
}

class _FullscreenDocumentState extends State<FullscreenDocument> {
  static const double _maxScale = 6.0;
  static const double _buttonZoomStep = 1.25;

  final TransformationController _transformer = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Rebuild on every zoom change so button enable/disable states stay fresh.
    _transformer.addListener(() {
      if (mounted) setState(() {});
    });
  }

  bool get _isZoomed =>
      _transformer.value.getMaxScaleOnAxis() > 1.05;

  void _resetZoom() => _transformer.value = Matrix4.identity();

  /// Zooms by [factor], anchored to the viewport center so the document
  /// stays centered instead of flying off-screen.
  void _zoomBy(double factor) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || size.isEmpty) return;
    final m = _transformer.value;
    final sOld = m.getMaxScaleOnAxis();
    final sNew = (sOld * factor).clamp(1.0, _maxScale).toDouble();
    if (sNew == sOld) return;
    final t = m.getTranslation();
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Child point currently under the viewport center.
    final childX = (cx - t.x) / sOld;
    final childY = (cy - t.y) / sOld;
    _transformer.value = Matrix4.identity()
      ..translateByDouble(cx - sNew * childX, cy - sNew * childY, 0, 1)
      ..scaleByDouble(sNew, sNew, 1, 1);
  }

  @override
  void dispose() {
    _transformer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.label),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              key: _viewerKey,
              transformationController: _transformer,
              // Zoom ONLY via the buttons; wheel/trackpad/pinch do nothing.
              scaleEnabled: false,
              panEnabled: true,
              minScale: 1.0,
              maxScale: _maxScale,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 64, color: Colors.white24),
                  ),
                ),
              ),
            ),
          ),
          // Zoom controls (top-right): − / + / reset side by side.
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _zoomButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    enabled: _isZoomed,
                    onTap: () => _zoomBy(1 / _buttonZoomStep),
                  ),
                  _zoomButton(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    enabled:
                        _transformer.value.getMaxScaleOnAxis() < _maxScale,
                    onTap: () => _zoomBy(_buttonZoomStep),
                  ),
                  if (_isZoomed)
                    _zoomButton(
                      icon: Icons.zoom_out_map,
                      tooltip: 'Reset zoom',
                      enabled: true,
                      onTap: _resetZoom,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 20,
              color: enabled ? Colors.white : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
