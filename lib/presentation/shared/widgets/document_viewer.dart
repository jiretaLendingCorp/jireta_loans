// lib/presentation/shared/widgets/document_viewer.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import 'pdf_zoom_viewer.dart';

/// Sinusubaybayan ang intrinsic size ng litrato — kailangan ng `ZoomPane` para
/// sa fit/clamp, at para malaman kung PORTRAIT ito (ID na kinunan nang patayo →
/// kailangang i-rotate sa landscape).
///
/// Hindi EXIF ang sinusuri kundi ang aktwal na decoded na sukat, kaya gumagana
/// ito kahit walang orientation metadata ang upload.
class _ImageProbe {
  _ImageProbe({required this.onResolved});

  final VoidCallback onResolved;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;
  int _portraitQuarterTurns = 0;

  /// Natural na sukat ng litrato (null hangga't hindi pa na-resolve).
  Size? get size => _size;

  /// 1 quarter turn (90° clockwise) kapag portrait ang litrato, 0 kung landscape.
  int get portraitQuarterTurns => _portraitQuarterTurns;

  void watch(String url) {
    _detach();
    _size = null;
    _portraitQuarterTurns = 0;
    final stream =
        CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        _detach();
        _size = Size(width, height);
        _portraitQuarterTurns = height > width ? 1 : 0;
        onResolved();
      },
      onError: (_, __) => _detach(),
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void dispose() => _detach();
}

class DocumentViewer extends StatefulWidget {
  final String? url;
  final String? label;
  final double height;
  final String bucket;

  /// Awtomatikong i-rotate sa landscape kapag portrait ang litrato — para sa
  /// mga ID na kinunan nang patayo (hindi na kailangang pindutin ang ⟳).
  final bool autoLandscape;

  /// Ipakita ang VIEW at +/− (zoom) sa overlay.
  final bool showZoomControls;

  /// Ipakita ang ⟳ (manual rotate) sa overlay.
  ///
  /// Kapag `false` (ginagamit ng carousel dialog na may sariling rotate button
  /// sa toolbar), wala nang nakapatong na button sa ibabaw ng litrato.
  final bool showRotateControl;

  /// Karagdagang 90° rotation mula sa parent (hal. ⟳ button sa toolbar ng
  /// carousel). Nadadagdag ito sa auto-landscape detection at sa ⟳ ng viewer
  /// mismo — hiwalay na pinagmulan, pinagsasama lang.
  final int quarterTurns;

  /// `false` (default) = buong dokumento ang kita (may letterbox sa gilid) —
  /// ito ang tama para sa maliliit na thumbnail card. `true` = punuin ang pane
  /// (may bahagyang crop) — para sa malalaking preview.
  final bool coverFit;

  /// Panlabas na zoom controller — para makapag-zoom ang parent (hal. +/−
  /// buttons sa toolbar ng carousel dialog). Kapag `null`, sariling kontrol ng
  /// viewer ang mga button nito.
  final ZoomPaneController? zoomController;

  const DocumentViewer({
    super.key,
    this.url,
    this.label,
    this.height = 200,
    this.bucket = 'account-upgrade-documents',
    this.autoLandscape = false,
    this.showZoomControls = true,
    this.showRotateControl = true,
    this.quarterTurns = 0,
    this.coverFit = false,
    this.zoomController,
  });

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  /// Ginagamit lang kapag walang external controller (tingnan ang
  /// `DocumentViewer.zoomController`).
  final ZoomPaneController _ownZoomController = ZoomPaneController();
  ZoomPaneController? _listenedController;
  String? _resolved;

  ZoomPaneController get _zoomController =>
      widget.zoomController ?? _ownZoomController;

  /// Bilang ng 90° na pag-ikot (clockwise) mula sa ⟳ button. Kailangan ito
  /// dahil karamihan ng litrato ng ID ay nakahiga (landscape) na kinunan — hindi
  /// mababasa kung hindi iikot.
  int _quarterTurns = 0;

  late final _probe = _ImageProbe(
    onResolved: () {
      if (mounted) setState(() {});
    },
  );

  /// Awtomatikong rotation: 1 quarter turn kapag portrait ang litrato (ID).
  int get _autoQuarterTurns =>
      widget.autoLandscape ? _probe.portraitQuarterTurns : 0;

  /// Pinagsamang auto (kung portrait), ⟳ ng viewer, at rotation mula sa parent.
  int get _effectiveTurns =>
      (_autoQuarterTurns + _quarterTurns + widget.quarterTurns) % 4;

  Size? get _imageSize => _probe.size;

  @override
  void initState() {
    super.initState();
    _resolve();
    _syncZoomListener();
  }

  /// Rebuild on zoom changes so +/− enable/disable states stay fresh. Kung
  /// pinalitan ng parent ang controller, ilipat ang listener.
  void _syncZoomListener() {
    final controller = _zoomController;
    if (identical(_listenedController, controller)) return;
    _listenedController?.removeListener(_handleZoomChanged);
    _listenedController = controller;
    controller.addListener(_handleZoomChanged);
  }

  void _handleZoomChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.zoomController, widget.zoomController)) {
      _syncZoomListener();
    }
    if (oldWidget.url != widget.url || oldWidget.bucket != widget.bucket) {
      _resolve();
      _quarterTurns = 0;
    }
  }

  /// Iikot ang dokumento nang 90° (clockwise). Ang `ZoomPane` na ang bahala sa
  /// muling pag-fit dahil nagbago ang sukat ng content.
  void _rotateInline() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  /// `url` may be a full http(s) URL or a relative storage path (e.g.
  /// `account-upgrade/{id}/{file}.jpg`). The account-upgrade-documents bucket
  /// is private, so relative paths must be resolved to a signed URL before
  /// they can be displayed.
  Future<void> _resolve() async {
    final url = widget.url;
    if (url == null || url.isEmpty || url.startsWith('http')) {
      if (mounted && _resolved != url) setState(() => _resolved = url);
      if (url != null && url.isNotEmpty) _probeImage(url);
      return;
    }
    try {
      String signed;
      try {
        signed = await SupabaseStorageService.instance
            .getSignedUrl(bucket: widget.bucket, path: url);
      } catch (_) {
        // Rows in account_upgrade_documents can be copies of walk-in uploads
        // (migration 00133 backfill) whose files actually live in the
        // loan-documents bucket — retry there before giving up.
        if (widget.bucket == 'loan-documents') rethrow;
        signed = await SupabaseStorageService.instance
            .getSignedUrl(bucket: 'loan-documents', path: url);
      }
      if (mounted) setState(() => _resolved = signed);
      _probeImage(signed);
    } catch (_) {
      if (mounted) setState(() => _resolved = null);
    }
  }

  /// Alamin ang sukat ng litrato — kailangan ito ng `ZoomPane` (fit/clamp) at
  /// ng auto-landscape detection ng mga ID.
  void _probeImage(String url) => _probe.watch(url);

  bool get isPdf => widget.url?.toLowerCase().endsWith('.pdf') ?? false;

  @override
  void dispose() {
    _listenedController?.removeListener(_handleZoomChanged);
    _ownZoomController.dispose();
    _probe.dispose();
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

    final size = _imageSize;
    // Kapag iniikot (odd quarter turns), nagbabaliktad ang lapad/taas ng
    // content — iyon ang ipinapasa sa pane para tama ang fit at clamping.
    final contentSize = size == null
        ? Size.zero
        : (_effectiveTurns.isOdd ? Size(size.height, size.width) : size);

    return GestureDetector(
      // Tap-to-fullscreen lang kapag may VIEW button (sa carousel, wala nang
      // kontrol sa ibabaw ng litrato).
      onTap: widget.showZoomControls
          ? () => _showFullScreen(context, url)
          : null,
      child: Stack(
        children: [
          Container(
            height: widget.height,
            width: double.infinity,
            color: Colors.white,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // `ZoomPane` ang humahawak ng fit/zoom/pan dito — pareho ang ugali
              // ng PDF report preview: pinupuno ang viewport, naka-clamp kaya
              // walang blangkong espasyo, may scrollbar sa kanan/ibaba, at
              // **Ctrl + wheel** ang zoom (plain wheel = scroll lang).
              child: size == null
                  ? const Center(child: CircularProgressIndicator())
                  : ZoomPane(
                      controller: _zoomController,
                      coverFit: widget.coverFit,
                      contentSize: contentSize,
                      // `RotatedBox` (hindi `Transform.rotate`) para nagbabago rin
                      // ang LAYOUT kapag iniikot — kasya pa rin sa pane.
                      child: RotatedBox(
                        quarterTurns: _effectiveTurns,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          // `fill` (hindi `contain`): ang pane na ang nagpi-fit, na
                          // nakabatay sa natural na sukat — doble sana ang fit.
                          child: Image(
                            image: CachedNetworkImageProvider(url),
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.surfaceGray,
                              child: const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      size: 48, color: AppColors.textHint)),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          // Controls sa itaas-kanan (kapag pinagana): VIEW | + | − | ⟳
          if (widget.showZoomControls || widget.showRotateControl)
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showZoomControls) ...[
                    _viewButton(onTap: () => _showFullScreen(context, url)),
                    const SizedBox(width: 6),
                    _inlineZoomButton(
                      icon: Icons.add,
                      tooltip: 'Zoom in (Ctrl + wheel)',
                      enabled: _zoomController.canZoomIn,
                      onTap: _zoomController.zoomIn,
                    ),
                    const SizedBox(width: 4),
                    _inlineZoomButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom out',
                      enabled: _zoomController.canZoomOut,
                      onTap: _zoomController.zoomOut,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Manual override ng auto-landscape (maaaring nasa toolbar na
                  // ito ng parent kaya pwedeng itago dito).
                  if (widget.showRotateControl)
                    _inlineZoomButton(
                      icon: Icons.rotate_right,
                      tooltip: 'Rotate 90°',
                      enabled: true,
                      onTap: _rotateInline,
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
        autoLandscape: widget.autoLandscape,
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

  /// Awtomatikong i-rotate sa landscape kapag portrait ang litrato (ID).
  final bool autoLandscape;

  const FullscreenDocument({
    super.key,
    required this.imageUrl,
    required this.label,
    this.autoLandscape = false,
  });

  @override
  State<FullscreenDocument> createState() => _FullscreenDocumentState();
}

class _FullscreenDocumentState extends State<FullscreenDocument> {
  static const double _maxScale = 6.0;
  static const double _buttonZoomStep = 1.25;

  final TransformationController _transformer = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  /// Bilang ng 90° na pag-ikot (clockwise) — para sa nakahigang litrato.
  int _quarterTurns = 0;

  late final _probe = _ImageProbe(
    onResolved: () {
      if (mounted) setState(() {});
    },
  );

  /// Awtomatikong rotation: 1 quarter turn kapag portrait ang litrato (ID).
  int get _autoQuarterTurns =>
      widget.autoLandscape ? _probe.portraitQuarterTurns : 0;

  /// Pinagsamang auto (kung portrait) at manual na rotation.
  int get _effectiveTurns => (_autoQuarterTurns + _quarterTurns) % 4;

  @override
  void initState() {
    super.initState();
    // Rebuild on every zoom change so button enable/disable states stay fresh.
    _transformer.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.autoLandscape) _probe.watch(widget.imageUrl);
  }

  /// Iikot nang 90° (clockwise) at i-reset ang zoom.
  void _rotate() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _transformer.value = Matrix4.identity();
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
    _probe.dispose();
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
              // `RotatedBox` para nagbabago rin ang layout kapag iniikot (hindi
              // lang painted) — kasya pa rin sa screen ang portrait na resulta.
              child: Center(
                child: RotatedBox(
                  quarterTurns: _effectiveTurns,
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
          ),
          // Zoom at rotate controls (top-right): − / + / ⟳ (+ reset kapag naka-zoom).
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
                  // Laging available ang rotate (hindi nakasalalay sa zoom).
                  _zoomButton(
                    icon: Icons.rotate_right,
                    tooltip: 'Rotate 90°',
                    enabled: true,
                    onTap: _rotate,
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
