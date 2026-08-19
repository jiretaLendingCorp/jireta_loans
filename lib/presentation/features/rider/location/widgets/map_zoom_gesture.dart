// lib/presentation/features/rider/location/widgets/map_zoom_gesture.dart
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Recognizes the Apple-Maps-style "double tap, hold, then drag" one-finger
/// zoom gesture:
///
/// * tap, tap (both quick) → plain double tap → falls through to the native
///   map, which zooms in at the double-tapped location.
/// * tap, then tap-and-HOLD, then drag up/down → smooth zoom in/out with a
///   single finger, anchored at the hold point (drag up = zoom in, drag
///   down = zoom out).
///
/// Single taps, pans, pinches and long-presses are never claimed, so the
/// native Google Map keeps handling those.
class DoubleTapDragZoomRecognizer extends OneSequenceGestureRecognizer {
  DoubleTapDragZoomRecognizer();

  void Function(Offset anchor)? onZoomStart;
  void Function(Offset anchor, double totalDeltaPixels)? onZoomUpdate;
  VoidCallback? onZoomEnd;

  static const double _tapSlop = 20;
  static const double _dragSlop = 8;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 320);

  Offset? _firstDown;
  int? _firstPointer;
  Offset? _firstUpPos;
  DateTime? _firstUpAt;
  Timer? _deadline;

  int? _secondPointer;
  Offset? _anchor;
  bool _zooming = false;

  final Set<int> _heldPointers = <int>{};

  @override
  String get debugDescription => 'double tap drag zoom';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    final now = DateTime.now();
    final firstUpAt = _firstUpAt;
    final firstUpPos = _firstUpPos;
    if (firstUpAt != null &&
        firstUpPos != null &&
        now.difference(firstUpAt) <= _doubleTapTimeout &&
        (event.position - firstUpPos).distance <= _tapSlop) {
      // Second tap inside the double-tap window → potential zoom drag.
      _deadline?.cancel();
      _secondPointer = event.pointer;
      _anchor = event.position;
      _zooming = false;
    } else {
      _resetPending();
      _firstDown = event.position;
      _firstPointer = event.pointer;
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _handleMove(event);
    } else if (event is PointerUpEvent) {
      _handleUp(event);
    } else if (event is PointerCancelEvent) {
      _handleCancel();
    }
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer == _secondPointer) {
      final anchor = _anchor;
      if (anchor == null) return;
      if (!_zooming) {
        if ((event.position - anchor).distance <= _dragSlop) return;
        // Drag started while holding the second tap → own the gesture.
        _zooming = true;
        _deadline?.cancel();
        _releaseHolds();
        resolve(GestureDisposition.accepted);
        onZoomStart?.call(anchor);
      }
      // Drag up (finger moves up on screen) zooms in; drag down zooms out.
      onZoomUpdate?.call(anchor, anchor.dy - event.position.dy);
    } else if (event.pointer == _firstPointer) {
      final firstDown = _firstDown;
      if (firstDown != null &&
          (event.position - firstDown).distance > _tapSlop) {
        // It's a pan, not a tap. Reject immediately so the map gets it.
        _rejectAll();
      }
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer == _secondPointer) {
      if (_zooming) {
        onZoomEnd?.call();
        _resetPending();
      } else {
        // Plain double tap → yield to the native map so it performs the zoom.
        _rejectAll();
      }
    } else if (event.pointer == _firstPointer) {
      final firstDown = _firstDown;
      if (firstDown != null &&
          (event.position - firstDown).distance <= _tapSlop) {
        // First tap complete. Hold the arena and wait briefly for a possible
        // second tap so the map doesn't win (and eat the tap) in between.
        _firstUpPos = event.position;
        _firstUpAt = DateTime.now();
        _holdPointer(event.pointer);
        _deadline?.cancel();
        _deadline = Timer(_doubleTapTimeout, _rejectAll);
      } else {
        _rejectAll();
      }
    }
  }

  void _handleCancel() {
    if (_zooming) onZoomEnd?.call();
    _rejectAll();
  }

  void _holdPointer(int pointer) {
    if (_heldPointers.add(pointer)) {
      GestureBinding.instance.gestureArena.hold(pointer);
    }
  }

  void _releaseHolds() {
    for (final pointer in _heldPointers) {
      GestureBinding.instance.gestureArena.release(pointer);
    }
    _heldPointers.clear();
  }

  void _rejectAll() {
    _deadline?.cancel();
    if (_zooming) onZoomEnd?.call();
    _releaseHolds();
    resolve(GestureDisposition.rejected);
    _resetPending();
  }

  void _resetPending() {
    _deadline?.cancel();
    _deadline = null;
    _firstDown = null;
    _firstPointer = null;
    _firstUpPos = null;
    _firstUpAt = null;
    _secondPointer = null;
    _anchor = null;
    _zooming = false;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _deadline?.cancel();
    if (_zooming) onZoomEnd?.call();
    _releaseHolds();
    _resetPending();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _deadline?.cancel();
    _releaseHolds();
    super.dispose();
  }
}

/// Transparent layer over a [GoogleMap] that wires the double-tap-hold-drag
/// zoom gesture to the map controller. All other gestures pass through to the
/// native map (which already provides pinch-zoom and double-tap zoom).
class MapZoomGestureOverlay extends StatefulWidget {
  const MapZoomGestureOverlay({
    super.key,
    required this.child,
    required this.controller,
    this.onInteractionStart,
  });

  final Widget child;
  final GoogleMapController? Function() controller;
  final VoidCallback? onInteractionStart;

  @override
  State<MapZoomGestureOverlay> createState() => _MapZoomGestureOverlayState();
}

class _MapZoomGestureOverlayState extends State<MapZoomGestureOverlay> {
  /// Zoom level at the moment the gesture started; deltas are added to it so
  /// the zoom is smooth and monotonic while dragging.
  double? _zoomBase;
  LatLng? _anchorLatLng;

  Future<void> _onZoomStart(Offset anchor) async {
    final c = widget.controller();
    if (c == null) return;
    widget.onInteractionStart?.call();
    _zoomBase = await c.getZoomLevel();
    _anchorLatLng = await c.getLatLng(
      ScreenCoordinate(x: anchor.dx.round(), y: anchor.dy.round()),
    );
  }

  Future<void> _onZoomUpdate(Offset anchor, double delta) async {
    final c = widget.controller();
    final base = _zoomBase;
    final anchorLatLng = _anchorLatLng;
    if (c == null || base == null || anchorLatLng == null) return;
    final target = (base + delta / 100).clamp(3.0, 21.0);
    await c.moveCamera(CameraUpdate.newLatLngZoom(anchorLatLng, target));
  }

  void _onZoomEnd() {
    _zoomBase = null;
    _anchorLatLng = null;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        DoubleTapDragZoomRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapDragZoomRecognizer>(
          DoubleTapDragZoomRecognizer.new,
          (instance) {
            instance.onZoomStart = _onZoomStart;
            instance.onZoomUpdate = _onZoomUpdate;
            instance.onZoomEnd = _onZoomEnd;
          },
        ),
      },
      child: widget.child,
    );
  }
}