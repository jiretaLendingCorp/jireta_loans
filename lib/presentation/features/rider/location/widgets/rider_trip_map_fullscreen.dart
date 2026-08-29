// lib/presentation/features/rider/location/widgets/rider_trip_map_fullscreen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/config/env_config.dart';
import '../../../../../core/services/route_service.dart';
import '../../../../shared/widgets/map/map_anim_utils.dart';
import '../providers/rider_location_provider.dart';
import 'map_zoom_gesture.dart';
import 'rider_trip_map.dart';

/// Full-screen version of the trip map: lets the rider inspect the whole
/// route with pinch-zoom and pan on the entire screen.
///
/// When [originLat]/[originLng] are provided (lender tracking), they override
/// the device GPS from [riderLocationProvider] as the "rider" origin.
class RiderTripFullscreenMap extends ConsumerStatefulWidget {
  final double? destinationLat;
  final double? destinationLng;
  final String destinationTitle;
  final String destinationSnippet;
  final String? destinationAddress;
  final double? originLat;
  final double? originLng;
  final String originTitle;
  final String originSnippet;
  final double originHue;
  final bool autofitBoth;
  final double? lenderLat;
  final double? lenderLng;
  final String lenderTitle;
  final String lenderSnippet;
  final double lenderHue;

  const RiderTripFullscreenMap({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationTitle,
    required this.destinationSnippet,
    this.destinationAddress,
    this.originLat,
    this.originLng,
    this.originTitle = 'You (Rider)',
    this.originSnippet = 'Your current position',
    this.originHue = BitmapDescriptor.hueAzure,
    this.autofitBoth = false,
    this.lenderLat,
    this.lenderLng,
    this.lenderTitle = 'You (Lender)',
    this.lenderSnippet = '',
    this.lenderHue = BitmapDescriptor.hueBlue,
  });

  @override
  ConsumerState<RiderTripFullscreenMap> createState() =>
      _RiderTripFullscreenMapState();
}

class _RiderTripFullscreenMapState
    extends ConsumerState<RiderTripFullscreenMap>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _didInitialFit = false;
  int _lastFitCount = 0;
  LatLng? _lastFitDest;

  double? _resolvedLat;
  double? _resolvedLng;

  bool _followRider = true;
  bool _isAutoMoving = false;

  // Animated marker
  late final AnimationController _markerAnimCtrl;
  LatLng? _displayOrigin;
  LatLng? _animStartOrigin;
  LatLng? _animTargetOrigin;
  double _originBearing = 0;

  List<LatLng>? _routePoints;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  bool _fetchingRoute = false;

  static const _phCenter = LatLng(14.5995, 120.9842);

  double? get _effectiveLat => widget.destinationLat ?? _resolvedLat;
  double? get _effectiveLng => widget.destinationLng ?? _resolvedLng;

  bool get _hasExternalOrigin =>
      widget.originLat != null && widget.originLng != null;

  double? get _originLat =>
      widget.originLat ?? ref.read(riderLocationProvider).lastLat;

  double? get _originLng =>
      widget.originLng ?? ref.read(riderLocationProvider).lastLng;

  Color get _originLegendColor {
    final h = widget.originHue;
    if (h >= 300) return Colors.deepPurple;
    if (h >= 250) return Colors.purple;
    if (h >= 210) return Colors.blueAccent;
    if (h >= 180) return Colors.cyan;
    if (h >= 120) return Colors.green;
    if (h >= 60) return Colors.orange;
    return Colors.redAccent;
  }

  bool get _hasValidMapsKey {
    final key = EnvConfig.googleMapsApiKey.trim();
    if (key.isEmpty) return false;
    final lower = key.toLowerCase();
    if (lower.contains('your_google_maps') ||
        lower.contains('your-google-maps') ||
        lower.contains('placeholder')) {
      return false;
    }
    return true;
  }

  void _onMarkerTick() {
    final start = _animStartOrigin;
    final target = _animTargetOrigin;
    if (start == null || target == null) return;
    final t = easeInOutCubic(_markerAnimCtrl.value);
    _displayOrigin = lerpLatLng(start, target, t);
    if (_followRider && _didInitialFit && _mapController != null && _displayOrigin != null) {
      _isAutoMoving = true;
      _mapController!.moveCamera(CameraUpdate.newLatLng(_displayOrigin!));
    }
    if (mounted) setState(() {});
  }

  void _animateToNewOrigin(double lat, double lng) {
    final newPos = LatLng(lat, lng);
    if (_displayOrigin == null) {
      _displayOrigin = newPos;
      _animStartOrigin = newPos;
      _animTargetOrigin = newPos;
      if (mounted) setState(() {});
      return;
    }
    final target = _animTargetOrigin;
    if (target != null &&
        (target.latitude - newPos.latitude).abs() < 0.00001 &&
        (target.longitude - newPos.longitude).abs() < 0.00001) {
      return;
    }
    _animStartOrigin = _displayOrigin;
    _animTargetOrigin = newPos;
    _originBearing = bearingBetween(_animStartOrigin!, newPos);
    _markerAnimCtrl.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    if (widget.autofitBoth) {
      _followRider = false;
    }
    _markerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addListener(_onMarkerTick);
    final initLat = widget.originLat;
    final initLng = widget.originLng;
    if (initLat != null && initLng != null) {
      _displayOrigin = LatLng(initLat, initLng);
      _animStartOrigin = _displayOrigin;
      _animTargetOrigin = _displayOrigin;
    }
    _maybeGeocodeDestination();
  }

  Future<void> _maybeGeocodeDestination() async {
    if (widget.destinationLat != null && widget.destinationLng != null) {
      return;
    }
    final address = widget.destinationAddress?.trim();
    if (address == null || address.isEmpty || address == 'Address not available') {
      return;
    }
    try {
      final locations = await locationFromAddress(address);
      if (!mounted) return;
      if (locations.isNotEmpty) {
        setState(() {
          _resolvedLat = locations.first.latitude;
          _resolvedLng = locations.first.longitude;
        });
      }
    } catch (_) {
      // leave coords null; the rider's live position still shows
    }
  }

  @override
  void dispose() {
    _markerAnimCtrl.removeListener(_onMarkerTick);
    _markerAnimCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RiderTripFullscreenMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasExternalOrigin) return;
    final oLat = widget.originLat!;
    final oLng = widget.originLng!;
    final changed =
        oldWidget.originLat != oLat || oldWidget.originLng != oLng;
    if (!changed) return;
    _animateToNewOrigin(oLat, oLng);
    _fetchRoute(riderLat: oLat, riderLng: oLng);
  }

  void _recenterOnRider() {
    final rLat = _displayOrigin?.latitude ?? _originLat;
    final rLng = _displayOrigin?.longitude ?? _originLng;
    final controller = _mapController;
    if (rLat == null || rLng == null || controller == null) return;
    _followRider = true;
    _isAutoMoving = true;
    controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(rLat, rLng), 16));
  }

  Set<Circle> _buildCircles() {
    if (_displayOrigin == null) return const {};
    return {
      Circle(
        circleId: const CircleId('rider_halo'),
        center: _displayOrigin!,
        radius: 22,
        strokeWidth: 1,
        strokeColor: AppColors.riderGreen.withValues(alpha: 0.25),
        fillColor: AppColors.riderGreen.withValues(alpha: 0.07),
      ),
    };
  }

  Set<Marker> _buildMarkers({double? riderLat, double? riderLng}) {
    final markers = <Marker>{};
    final effectiveRiderPos = _displayOrigin ??
        (riderLat != null && riderLng != null ? LatLng(riderLat, riderLng) : null);
    if (effectiveRiderPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: effectiveRiderPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(widget.originHue),
          rotation: _originBearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: widget.originTitle,
            snippet: widget.originSnippet,
          ),
        ),
      );
    }
    final dLat = _effectiveLat;
    final dLng = _effectiveLng;
    if (dLat != null && dLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(dLat, dLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          infoWindow: InfoWindow(
            title: widget.destinationTitle,
            snippet: widget.destinationSnippet,
          ),
        ),
      );
    }
    final lLat = widget.lenderLat;
    final lLng = widget.lenderLng;
    if (lLat != null && lLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('lender_live'),
          position: LatLng(lLat, lLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(widget.lenderHue),
          infoWindow: InfoWindow(
            title: widget.lenderTitle,
            snippet: widget.lenderSnippet,
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines({double? riderLat, double? riderLng}) {
    final dLat = _effectiveLat;
    final dLng = _effectiveLng;
    if (riderLat == null || riderLng == null || dLat == null || dLng == null) {
      return const {};
    }
    // The route line MUST come from the Directions API road geometry. No
    // straight-line fallback between origin and destination.
    if (_routePoints == null || _routePoints!.isEmpty) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints!,
        color: AppColors.riderGreen,
        width: 5,
      ),
    };
  }

  double _minDistanceToRoute(double lat, double lng) {
    final route = _routePoints;
    if (route == null || route.isEmpty) return double.infinity;
    var min = double.infinity;
    for (final p in route) {
      final d = (p.latitude - lat).abs() + (p.longitude - lng).abs();
      if (d < min) min = d;
    }
    return min;
  }

  Future<void> _fetchRoute({
    required double riderLat,
    required double riderLng,
  }) async {
    final dLat = _effectiveLat;
    final dLng = _effectiveLng;
    if (dLat == null || dLng == null || _fetchingRoute) return;

    final dest = LatLng(dLat, dLng);
    final lastDest = _lastRouteDest;
    final destChanged = lastDest != null &&
        ((lastDest.latitude - dLat).abs() > 0.0001 ||
            (lastDest.longitude - dLng).abs() > 0.0001);
    if (destChanged) {
      _routePoints = null;
      _lastRouteOrigin = null;
      _lastRouteDest = null;
    }

    final origin = LatLng(riderLat, riderLng);
    final movedEnough = _lastRouteOrigin == null ||
        (_lastRouteOrigin!.latitude - riderLat).abs() > 0.005 ||
        (_lastRouteOrigin!.longitude - riderLng).abs() > 0.005 ||
        _minDistanceToRoute(riderLat, riderLng) > 0.004;
    if (!movedEnough) return;

    _fetchingRoute = true;
    final route = await RouteService.fetchDrivingRoute(origin, dest);
    _fetchingRoute = false;
    if (!mounted) return;
    if (route != null && route.isNotEmpty) {
      setState(() {
        _routePoints = route;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    }
  }

  Future<void> _fitCamera(Iterable<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;
    final pts = points.toList();
    if (pts.length == 1) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }

  /// Fits the camera to keep BOTH the rider and the lender in view, so the
  /// whole span — from the rider's current location to the lender's — is
  /// visible without the user having to zoom or search.
  ///
  /// Used for CI navigation ([autofitBoth]). It re-fits whenever a point first
  /// appears (the rider's first GPS fix or a geocoded destination), but not on
  /// every GPS tick, and it never re-centers on the rider at full zoom.
  void _tryFitBoth() {
    if (!widget.autofitBoth) return;
    final controller = _mapController;
    if (controller == null) return;
    final dLat = _effectiveLat;
    final dLng = _effectiveLng;
    final rLat = _originLat;
    final rLng = _originLng;
    final dest = (dLat != null && dLng != null) ? LatLng(dLat, dLng) : null;
    final points = <LatLng>[
      if (dest != null) dest,
      if (rLat != null && rLng != null) LatLng(rLat, rLng),
      if (widget.lenderLat != null && widget.lenderLng != null)
        LatLng(widget.lenderLat!, widget.lenderLng!),
    ];
    if (points.isEmpty) return;
    final destChanged = dest != _lastFitDest;
    if (_lastFitCount != 0 && points.length == _lastFitCount && !destChanged) {
      return;
    }
    _lastFitCount = points.length;
    _lastFitDest = dest;
    _fitCamera(points);
  }

  void _fitIfReady(bool hasDestination) {
    if (widget.autofitBoth) {
      _tryFitBoth();
      return;
    }
    final controller = _mapController;
    if (controller == null) return;
    final riderLat = _originLat;
    final riderLng = _originLng;
    final points = <LatLng>[
      if (_effectiveLat != null && _effectiveLng != null)
        LatLng(_effectiveLat!, _effectiveLng!),
      if (riderLat != null && riderLng != null) LatLng(riderLat, riderLng),
      if (widget.lenderLat != null && widget.lenderLng != null)
        LatLng(widget.lenderLat!, widget.lenderLng!),
    ];
    if (points.isEmpty) return;
    if (_didInitialFit && points.length <= _lastFitCount) return;
    _didInitialFit = true;
    _lastFitCount = points.length;
    _fitCamera(points);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(riderLocationProvider);
    final hasDestination = _effectiveLat != null && _effectiveLng != null;
    final originLat = _originLat;
    final originLng = _originLng;
    // Seed display from provider if needed.
    if (_displayOrigin == null && originLat != null && originLng != null) {
      _displayOrigin = LatLng(originLat, originLng);
      _animStartOrigin = _displayOrigin;
      _animTargetOrigin = _displayOrigin;
    }
    final markers = _buildMarkers(riderLat: originLat, riderLng: originLng);
    final polylines = _buildPolylines(
      riderLat: _displayOrigin?.latitude ?? originLat,
      riderLng: _displayOrigin?.longitude ?? originLng,
    );
    final circles = _buildCircles();

    if (_routePoints == null && hasDestination) {
      if (originLat != null && originLng != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchRoute(riderLat: originLat, riderLng: originLng);
        });
      }
    }
    // Animated follow: glide marker between GPS fixes.
    ref.listen(riderLocationProvider, (prev, next) {
      if (_hasExternalOrigin || !mounted) return;
      final rLat = next.lastLat;
      final rLng = next.lastLng;
      if (rLat == null || rLng == null) return;
      if (_displayOrigin == null) {
        _displayOrigin = LatLng(rLat, rLng);
        _animStartOrigin = _displayOrigin;
        _animTargetOrigin = _displayOrigin;
        if (mounted) setState(() {});
        if (_effectiveLat != null && _effectiveLng != null) {
          _fetchRoute(riderLat: rLat, riderLng: rLng);
        }
        return;
      }
      _animateToNewOrigin(rLat, rLng);
      if (_effectiveLat != null && _effectiveLng != null) {
        _fetchRoute(riderLat: rLat, riderLng: rLng);
      }
    });

    if (_didInitialFit && markers.length > _lastFitCount ||
        !_didInitialFit && (hasDestination || originLat != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitIfReady(hasDestination);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MapZoomGestureOverlay(
            controller: () => _mapController,
            onInteractionStart: () => _followRider = false,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.autofitBoth &&
                        _effectiveLat != null &&
                        _effectiveLng != null
                    ? LatLng(_effectiveLat!, _effectiveLng!)
                    : markers.isNotEmpty
                        ? markers.first.position
                        : _phCenter,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                _fitIfReady(hasDestination);
              },
              onCameraMoveStarted: () {
                if (!_isAutoMoving) {
                  _followRider = false;
                }
              },
              onCameraIdle: () {
                _isAutoMoving = false;
              },
              markers: markers,
              polylines: polylines,
              circles: circles,
              myLocationEnabled: _hasValidMapsKey,
              myLocationButtonEnabled: _hasValidMapsKey,
              zoomControlsEnabled: true,
              compassEnabled: true,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black87),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topRight,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.my_location, color: AppColors.riderGreen),
                    onPressed: _recenterOnRider,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: RiderMapLegend(
                      originLabel: widget.originTitle,
                      originColor: _originLegendColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}