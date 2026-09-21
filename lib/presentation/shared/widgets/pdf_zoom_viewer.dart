// lib/presentation/shared/widgets/pdf_zoom_viewer.dart
//
// Ang zoom/pan engine na ginagamit ng PDF report preview (`PdfZoomViewer`) at ng
// dokumento/litrato preview (`DocumentViewer`). Isang `ZoomPane` lang ang
// humahawak ng matrix, gestures, scrollbar at clamping — pare-pareho ang ugali
// sa lahat ng preview sa app.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';

/// Ang 2D scale ng matrix (x/y axis lang, wala ang z).
///
/// Hindi magamit ang `getMaxScaleOnAxis()` dito: dahil `scaleByDouble(s, s, 1, 1)`
/// ang gamit natin, ang z axis ay laging 1 — kaya kapag mas mababa sa 1 ang
/// zoom (fit ng malaking dokumento), 1.0 ang isinasauli niyon imbes na ang
/// aktwal na scale.
double uniformScale(Matrix4 m) =>
    math.sqrt(m.entry(0, 0) * m.entry(0, 0) + m.entry(1, 0) * m.entry(1, 0));

/// Sukat ng [docSize] sa loob ng [viewport].
///
/// * `cover: true` → **pinupuno ang buong viewport** (max na ratio) para walang
///   blangkong paligid. Naka-top align sa patayo — ang simula ng dokumento agad
///   ang nakikita — habang naka-center ang pahalang na crop.
/// * `cover: false` → buong dokumento ang kita (min na ratio, may letterbox).
Matrix4 fitMatrix(Size viewport, Size docSize, {bool cover = false}) {
  if (viewport.isEmpty || docSize.isEmpty) return Matrix4.identity();
  final scale = cover
      ? math.max(
          viewport.width / docSize.width,
          viewport.height / docSize.height,
        )
      : math.min(
          viewport.width / docSize.width,
          viewport.height / docSize.height,
        );
  return Matrix4.identity()
    ..translateByDouble(
      (viewport.width - docSize.width * scale) / 2,
      cover ? 0 : (viewport.height - docSize.height * scale) / 2,
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1);
}

/// Pan/pagulong [delta] sa VIEWPORT space.
///
/// Pre-multiplied (`T × M`) kaya hindi dumadaan sa kasalukuyang scale — pantay
/// ang bilis ng pag-scroll kahit naka-zoom in o out.
Matrix4 panBy(Matrix4 current, Offset delta) {
  if (delta == Offset.zero) return current;
  return (Matrix4.identity()
        ..translateByDouble(delta.dx, delta.dy, 0, 1))
      .multiplied(current);
}

/// Hindi pinapayagang lumabas ang dokumento sa viewport — walang blangkong
/// space kahit anong scroll o zoom.
///
/// Kapag mas malaki ang dokumento (naka-scaled) sa viewport sa isang axis,
/// naka-clamp ang translation sa gilid nito (`viewport - scaled` … `0`); kapag
/// mas maliit, naka-center.
Matrix4 clampToViewport(Matrix4 m, Size viewport, Size docSize) {
  if (viewport.isEmpty || docSize.isEmpty) return m;
  final scale = uniformScale(m);
  if (scale <= 0 || !scale.isFinite) return m;
  final t = m.getTranslation();
  final scaledW = docSize.width * scale;
  final scaledH = docSize.height * scale;
  final x = scaledW <= viewport.width
      ? (viewport.width - scaledW) / 2
      : t.x.clamp(viewport.width - scaledW, 0.0);
  final y = scaledH <= viewport.height
      ? (viewport.height - scaledH) / 2
      : t.y.clamp(viewport.height - scaledH, 0.0);
  if (x == t.x && y == t.y) return m;
  return Matrix4.identity()
    ..translateByDouble(x, y, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

/// Matrix para sa isang scale gesture (pinch o focal-point zoom).
///
/// Ang scene point na nasa ilalim ng [startFocal] ay lumalabas sa
/// [currentFocal] pagkatapos, na may scale na `start.scale × factor` (naka-clamp
/// sa [minScale]–[maxScale]). Kapag pareho ang dalawang focal (purong zoom),
/// hindi gumagalaw ang pinindot na punto; kapag `factor == 1` (purong drag),
/// pan lang ito.
Matrix4 scaleGestureMatrix(
  Matrix4 start, {
  required Offset startFocal,
  required Offset currentFocal,
  required double factor,
  required double minScale,
  required double maxScale,
}) {
  final sOld = uniformScale(start);
  if (sOld <= 0 || !sOld.isFinite) return start;
  final sNew = (sOld * factor).clamp(minScale, maxScale).toDouble();
  if (sNew == sOld && startFocal == currentFocal) return start;
  final k = sNew / sOld;
  return (Matrix4.identity()
        ..translateByDouble(
          currentFocal.dx - k * startFocal.dx,
          currentFocal.dy - k * startFocal.dy,
          0,
          1,
        )
        ..scaleByDouble(k, k, 1, 1))
      .multiplied(start);
}

/// Zoom-in ng [factor] na naka-angkla sa [anchor] (viewport coordinates) at
/// naka-clamp sa [minScale]–[maxScale] — para sa wheel at double-tap.
Matrix4 zoomAboutPoint(
  Matrix4 current,
  double factor,
  Offset anchor,
  double minScale,
  double maxScale,
) =>
    scaleGestureMatrix(
      current,
      startFocal: anchor,
      currentFocal: anchor,
      factor: factor,
      minScale: minScale,
      maxScale: maxScale,
    );

/// Panlabas na kontrol ng zoom ng [ZoomPane] — para sa mga +/− button sa labas
/// ng pane (hal. overlay ng `DocumentViewer`).
class ZoomPaneController extends ChangeNotifier {
  _ZoomPaneState? _state;

  /// Hindi pa naa-attach (wala pang naka-layout na pane) → 1.0.
  double get scale => _state?.scale ?? 1;

  bool get canZoomIn => _state?.canZoomIn ?? false;
  bool get canZoomOut => _state?.canZoomOut ?? false;

  void zoomIn([double factor = 1.25]) => _state?._zoomFromButton(factor);
  void zoomOut([double factor = 1.25]) => _state?._zoomFromButton(1 / factor);

  /// Bumalik sa punong view (walang blangkong paligid).
  void fit() => _state?._fitToViewport();

  void _attach(_ZoomPaneState state) => _state = state;

  void _detach(_ZoomPaneState state) {
    if (identical(_state, state)) _state = null;
  }

  void _markChanged() => notifyListeners();
}

/// Zoomable na pane — **pinupuno ang buong viewport** at naka-clamp doon, kaya
/// walang blangkong espasyo sa itaas/ibaba/gilid. May manipis na scrollbar
/// indicator sa kanan at sa ibaba kapag may dapat i-scroll, at pwedeng hilahin.
///
/// Ugali ng mga galaw:
///
/// * **Ctrl + mouse wheel** → zoom (kailangan ang Ctrl; kung wala, scroll lang).
/// * **Plain wheel / trackpad na dalawang-daliri na scroll** → pan.
/// * **Pinch** (touch o trackpad pinch) → zoom, naka-angkla sa pinindot.
/// * **Drag** → pan.
/// * **Double-tap** → punong view ↔ 2.5×.
///
/// Ang [child] ay dapat eksaktong [contentSize] ang layout (hal. `SizedBox` ng
/// natural size) — iyon ang batayan ng fit at clamping.
class ZoomPane extends StatefulWidget {
  const ZoomPane({
    super.key,
    required this.contentSize,
    required this.child,
    this.controller,
    this.backgroundColor,
    this.scrollBars = true,
    this.coverFit = true,
  });

  /// `true` = punuin ang buong pane (may bahagyang crop, walang blangkong
  /// paligid) — para sa malalaking preview. `false` = ipakita ang buong
  /// dokumento (may letterbox, walang crop) — para sa maliliit na thumbnail
  /// card kung saan mahalagang makita ang buong dokumento.
  final bool coverFit;

  /// Natural na sukat ng content (device pixels ng raster/litrato).
  final Size contentSize;

  final Widget child;

  /// Optional na panlabas na kontrol (para sa +/− buttons).
  final ZoomPaneController? controller;

  final Color? backgroundColor;

  /// Ipakita ang scrollbar indicator (kanan at ibaba).
  final bool scrollBars;

  @override
  State<ZoomPane> createState() => _ZoomPaneState();
}

class _ZoomPaneState extends State<ZoomPane> {
  static const double _doubleTapFactor = 2.5;
  static const double _wheelZoomDivisor = 300;
  static const double _barThickness = 6;
  static const double _barInset = 4;
  static const double _minThumb = 28;

  /// Child (scene) → viewport transformation. Identity = natural size.
  Matrix4 _matrix = Matrix4.identity();

  /// Scale ng panimulang view (cover o contain) — ito rin ang pinakamaliit na
  /// pwedeng i-zoom out, para laging puno/angkop ang pane.
  double _fitScale = 1;

  Size _viewport = Size.zero;

  Matrix4 _gestureStart = Matrix4.identity();
  Offset _gestureStartFocal = Offset.zero;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant ZoomPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    // Bagong sukat (hal. iniikot ang litrato) → i-fit muli.
    if (oldWidget.contentSize != widget.contentSize) {
      _scheduleFit();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  double get scale => uniformScale(_matrix);
  bool get canZoomIn => scale < _maxScale * 0.99;
  bool get canZoomOut => scale > _minScale * 1.01;

  double get _minScale => math.max(0.02, _fitScale);
  double get _maxScale => math.max(_fitScale * 6, 3.0);

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToViewport();
    });
  }

  void _fitToViewport() {
    if (_viewport.isEmpty || widget.contentSize.isEmpty) return;
    final fit = fitMatrix(_viewport, widget.contentSize,
        cover: widget.coverFit);
    _setMatrix(fit);
    setState(() => _fitScale = uniformScale(fit));
  }

  /// Itakda ang bagong matrix, naka-clamp sa loob ng viewport, at ipaalam sa
  /// controller para tuloy-tuloy ang enable/disable ng mga button.
  void _setMatrix(Matrix4 next) {
    final clamped = _viewport.isEmpty
        ? next
        : clampToViewport(next, _viewport, widget.contentSize);
    if (mounted) {
      setState(() => _matrix = clamped);
    } else {
      _matrix = clamped;
    }
    widget.controller?._markChanged();
  }

  // ── Wheel at trackpad signals ─────────────────────────────────────────────
  void _onPointerSignal(PointerSignalEvent event) {
    // Trackpad pinch (may sariling scale value) → zoom agad.
    if (event is PointerScaleEvent) {
      _zoomBy(event.scale, event.localPosition);
      return;
    }
    if (event is! PointerScrollEvent) return;

    final delta = event.scrollDelta;
    if (delta == Offset.zero) return;

    // Ctrl + wheel = zoom, gaya ng browser/PDF viewer. Kapag wala, scroll/pan
    // lang — hindi basta-basta nagzo-zoom.
    if (HardwareKeyboard.instance.isControlPressed) {
      if (delta.dy == 0) return;
      _zoomBy(math.exp(-delta.dy / _wheelZoomDivisor), event.localPosition);
      return;
    }

    _panBy(Offset(-delta.dx, -delta.dy));
  }

  void _zoomBy(double factor, Offset anchor) {
    _setMatrix(zoomAboutPoint(_matrix, factor, anchor, _minScale, _maxScale));
  }

  void _zoomFromButton(double factor) {
    final anchor = _viewport.isEmpty
        ? Offset.zero
        : _viewport.center(Offset.zero);
    _zoomBy(factor, anchor);
  }

  void _panBy(Offset delta) {
    _setMatrix(panBy(_matrix, delta));
  }

  // ── Pinch at drag (touch/trackpad gesture) ────────────────────────────────
  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _matrix.clone();
    _gestureStartFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _setMatrix(
      scaleGestureMatrix(
        _gestureStart,
        startFocal: _gestureStartFocal,
        currentFocal: details.localFocalPoint,
        factor: details.scale,
        minScale: _minScale,
        maxScale: _maxScale,
      ),
    );
  }

  /// Double-tap: panimulang view ↔ 2.5×, naka-angkla sa pinindot na punto.
  void _toggleDoubleTap() {
    if (scale > _fitScale * 1.05) {
      _fitToViewport();
      return;
    }
    if (_viewport.isEmpty) return;
    _zoomBy(_doubleTapFactor, _doubleTapPosition ?? _viewport.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final wasEmpty = _viewport.isEmpty;
          _viewport = size;
          // Unang layout (o bagong pane) → i-fit pagkatapos ng frame.
          if (wasEmpty && !size.isEmpty) _scheduleFit();

          return ClipRect(
            child: Listener(
              // Opaque: kunin ang wheel/drag kahit sa bakanteng espasyo sa
              // paligid ng content.
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _onPointerSignal,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onDoubleTapDown: (details) =>
                          _doubleTapPosition = details.localPosition,
                      onDoubleTap: _toggleDoubleTap,
                      child: OverflowBox(
                        // Same layering gaya ng InteractiveViewer: ClipRect >
                        // OverflowBox > Transform, para ang natural-size na
                        // content ay hindi nag-o-overflow.
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: double.infinity,
                        maxHeight: double.infinity,
                        child: Transform(
                          transform: _matrix,
                          child: SizedBox(
                            width: widget.contentSize.width,
                            height: widget.contentSize.height,
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.scrollBars) ..._buildScrollBars(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Manipis na scrollbar sa kanan (patayo) at sa ibaba (pahalang) — lumalabas
  /// lang kapag may dapat i-scroll sa axis na iyon, at pwedeng hilahin.
  List<Widget> _buildScrollBars() {
    if (_viewport.isEmpty || widget.contentSize.isEmpty) return const [];
    final translation = _matrix.getTranslation();
    final bars = <Widget>[];

    final scaledH = widget.contentSize.height * scale;
    if (scaledH > _viewport.height + 0.5) {
      final track = math
          .max(0.0, _viewport.height - _barInset * 2 - _barThickness);
      final thumb = (track * _viewport.height / scaledH)
          .clamp(math.min(_minThumb, track), track)
          .toDouble();
      final maxScroll = scaledH - _viewport.height;
      final progress =
          maxScroll <= 0 ? 0.0 : (-translation.y / maxScroll).clamp(0.0, 1.0);
      final movable = track - thumb;
      bars.add(Positioned(
        top: _barInset + progress * movable,
        right: _barInset,
        width: _barThickness,
        height: thumb,
        child: _ScrollBarThumb(
          axis: Axis.vertical,
          onDrag: (delta) => _panBy(
            Offset(0, movable <= 0 ? 0 : -delta * (maxScroll / movable)),
          ),
        ),
      ));
    }

    final scaledW = widget.contentSize.width * scale;
    if (scaledW > _viewport.width + 0.5) {
      final track =
          math.max(0.0, _viewport.width - _barInset * 2 - _barThickness * 3);
      final thumb = (track * _viewport.width / scaledW)
          .clamp(math.min(_minThumb, track), track)
          .toDouble();
      final maxScroll = scaledW - _viewport.width;
      final progress =
          maxScroll <= 0 ? 0.0 : (-translation.x / maxScroll).clamp(0.0, 1.0);
      final movable = track - thumb;
      bars.add(Positioned(
        left: _barInset + progress * movable,
        bottom: _barInset,
        height: _barThickness,
        width: thumb,
        child: _ScrollBarThumb(
          axis: Axis.horizontal,
          onDrag: (delta) => _panBy(
            Offset(movable <= 0 ? 0 : -delta * (maxScroll / movable), 0),
          ),
        ),
      ));
    }

    return bars;
  }
}

/// Manipis na scrollbar thumb na pwedeng hilahin.
class _ScrollBarThumb extends StatelessWidget {
  const _ScrollBarThumb({required this.axis, required this.onDrag});

  final Axis axis;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final isVertical = axis == Axis.vertical;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate:
            isVertical ? (details) => onDrag(details.delta.dy) : null,
        onHorizontalDragUpdate:
            isVertical ? null : (details) => onDrag(details.delta.dx),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// Preview ng report PDF — nirere-render ang mga page sa bitmap
/// (`Printing.raster`) at ipinapasa sa [ZoomPane] (parehong ugali ng gestures at
/// scrollbar ng dokumento preview).
class PdfZoomViewer extends StatefulWidget {
  const PdfZoomViewer({
    super.key,
    required this.buildDocument,
    this.dpi = 144,
    this.errorLabel = 'Unable to render the preview. Please try again.',
  });

  /// Gumagawa ng PDF bytes — dapat kapareho ng ipi-print/download na file.
  final Future<Uint8List> Function() buildDocument;

  /// Raster resolution. Ang 144 dpi = 2× ng 72dpi logical.
  final double dpi;

  final String errorLabel;

  @override
  State<PdfZoomViewer> createState() => _PdfZoomViewerState();
}

class _PdfZoomViewerState extends State<PdfZoomViewer> {
  static const double _pageGap = 12;

  List<PdfRaster> _pages = const [];
  bool _loading = true;
  bool _failed = false;

  double get _docWidth =>
      _pages.fold(0.0, (max, p) => math.max(max, p.width.toDouble()));
  double get _docHeight => _pages.isEmpty
      ? 0
      : _pages.fold(0.0, (sum, p) => sum + p.height.toDouble()) +
          _pageGap * (_pages.length - 1);

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant PdfZoomViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildDocument != widget.buildDocument ||
        oldWidget.dpi != widget.dpi) {
      _render();
    }
  }

  Future<void> _render() async {
    setState(() {
      _loading = true;
      _failed = false;
      _pages = const [];
    });
    try {
      final bytes = await widget.buildDocument();
      final pages = await Printing.raster(bytes, dpi: widget.dpi).toList();
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed || _pages.isEmpty) {
      return Container(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.errorLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return ZoomPane(
      backgroundColor: AppColors.surfaceVariant,
      contentSize: Size(_docWidth, _docHeight),
      child: Column(
        children: [
          for (var i = 0; i < _pages.length; i++) ...[
            if (i > 0) const SizedBox(height: _pageGap),
            SizedBox(
              width: _pages[i].width.toDouble(),
              height: _pages[i].height.toDouble(),
              child: Image(
                image: PdfRasterImage(_pages[i]),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
