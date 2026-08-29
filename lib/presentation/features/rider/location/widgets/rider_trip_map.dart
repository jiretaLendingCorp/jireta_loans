// lib/presentation/features/rider/location/widgets/rider_trip_map.dart
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
import 'rider_trip_map_fullscreen.dart';

/// Embedded trip map for the rider: shows the lender's destination and the
/// rider's live GPS position (from [riderLocationProvider]) on a single
/// in-app map, with a line between the two.
///
/// If the lender's address has no saved coordinates, [destinationAddress] is
/// geocoded at runtime so the destination pin still appears, and the resolved
/// coordinates are reported via [onDestinationResolved].
///
/// For the LENDER tracking screen, pass [originLat]/[originLng] (the rider's
/// live position fetched from the API). When provided they override the device
/// GPS from [riderLocationProvider]; the widget then treats those as the
/// "rider" origin and draws the route from them.
class RiderTripMap extends ConsumerStatefulWidget {
  final double? destinationLat;
  final double? destinationLng;
  final String destinationTitle;
  final String destinationSnippet;
  final String? destinationAddress;
  final double height;
  final void Function(double lat, double lng)? onDestinationResolved;
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

  const RiderTripMap({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationTitle,
    required this.destinationSnippet,
    this.destinationAddress,
    this.height = 280,
    this.onDestinationResolved,
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
  ConsumerState<RiderTripMap> createState() => _RiderTripMapState();
}

class _RiderTripMapState extends ConsumerState<RiderTripMap>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _didInitialFit = false;
  int _lastFitCount = 0;
  LatLng? _lastFitDest;

  // ── Animated marker (smooth glide instead of teleport) ──
  late final AnimationController _markerAnimCtrl;
  late final AnimationController _pulseCtrl;
  LatLng? _displayOrigin;
  LatLng? _animStartOrigin;
  LatLng? _animTargetOrigin;
  double _originBearing = 0;

  double? _resolvedLat;
  double? _resolvedLng;
  bool _geocoding = false;
  bool _geocodeFailed = false;

  double? _lastReportedLat;
  double? _lastReportedLng;

  bool _followRider = true;
  bool _isAutoMoving = false;

  List<LatLng>? _routePoints;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  bool _fetchingRoute = false;

  double? get _effectiveLat => widget.destinationLat ?? _resolvedLat;
  double? get _effectiveLng => widget.destinationLng ?? _resolvedLng;

  bool get _hasExternalOrigin =>
      widget.originLat != null && widget.originLng != null;

  double? get _originLat =>
      widget.originLat ?? ref.read(riderLocationProvider).lastLat;

  double? get _originLng =>
      widget.originLng ?? ref.read(riderLocationProvider).lastLng;

  static const _phCenter = LatLng(14.5995, 120.9842);

  /// Only enable the map's native "my location" layer (which starts a device
  /// location stream on Android) when a real Google Maps API key is present.
  /// A placeholder / empty key makes the native Maps SDK crash when the
  /// permission is granted, so we keep the marker pins but skip that layer.
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
      _originBearing = 0;
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
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    // Seed display position from initial origin if available.
    final initLat = widget.originLat;
    final initLng = widget.originLng;
    if (initLat != null && initLng != null) {
      _displayOrigin = LatLng(initLat, initLng);
      _animStartOrigin = _displayOrigin;
      _animTargetOrigin = _displayOrigin;
    }
    _maybeGeocodeDestination();
  }

  /// If the lender address has no saved coordinates, resolve them from the
  /// formatted address text so the destination pin still shows.
  Future<void> _maybeGeocodeDestination() async {
    if (widget.destinationLat != null && widget.destinationLng != null) {
      return;
    }
    final address = widget.destinationAddress?.trim();
    if (address == null || address.isEmpty || address == 'Address not available') {
      return;
    }
    setState(() => _geocoding = true);
    try {
      final locations = await locationFromAddress(address);
      if (!mounted) return;
      if (locations.isNotEmpty) {
        setState(() {
          _resolvedLat = locations.first.latitude;
          _resolvedLng = locations.first.longitude;
          _geocoding = false;
        });
      } else {
        setState(() {
          _geocoding = false;
          _geocodeFailed = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geocoding = false;
        _geocodeFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _markerAnimCtrl.removeListener(_onMarkerTick);
    _markerAnimCtrl.dispose();
    _pulseCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RiderTripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasExternalOrigin) return;
    final oLat = widget.originLat!;
    final oLng = widget.originLng!;
    final changed =
        oldWidget.originLat != oLat || oldWidget.originLng != oLng;
    if (!changed) return;
    // Animate marker glide instead of teleport.
    _animateToNewOrigin(oLat, oLng);
    _fetchRoute(riderLat: oLat, riderLng: oLng);
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RiderTripFullscreenMap(
          destinationLat: _effectiveLat,
          destinationLng: _effectiveLng,
          destinationTitle: widget.destinationTitle,
          destinationSnippet: widget.destinationSnippet,
          destinationAddress: widget.destinationAddress,
          originLat: widget.originLat,
          originLng: widget.originLng,
          originTitle: widget.originTitle,
          originSnippet: widget.originSnippet,
          originHue: widget.originHue,
          autofitBoth: widget.autofitBoth,
          lenderLat: widget.lenderLat,
          lenderLng: widget.lenderLng,
          lenderTitle: widget.lenderTitle,
          lenderSnippet: widget.lenderSnippet,
          lenderHue: widget.lenderHue,
        ),
      ),
    );
  }

  /// Re-centers the camera on the rider's current position and re-enables
  /// follow mode (in case the user had panned/zoomed away).
  void _recenterOnRider() {
    final rLat = _displayOrigin?.latitude ?? _originLat;
    final rLng = _displayOrigin?.longitude ?? _originLng;
    final controller = _mapController;
    if (rLat == null || rLng == null || controller == null) return;
    _followRider = true;
    _isAutoMoving = true;
    controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(rLat, rLng), 16));
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  void _reportResolved(double? lat, double? lng) {
    final cb = widget.onDestinationResolved;
    if (cb == null || lat == null || lng == null) return;
    if (lat == _lastReportedLat && lng == _lastReportedLng) return;
    _lastReportedLat = lat;
    _lastReportedLng = lng;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(lat, lng);
    });
  }

  Set<Marker> _buildMarkers({double? riderLat, double? riderLng}) {
    final markers = <Marker>{};
    // Prefer animated display position for smooth glide.
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
    // The lender's own live GPS position (their device), shown when the
    // viewer is the lender tracking an incoming rider.
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

  /// Approximate distance (in degrees) from a point to the nearest point on
  /// the current route line. Used to detect when the rider deviates.
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

  /// Fetches the driving route on the actual roads from the Directions API.
  /// Re-fetches when the rider moves a meaningful distance OR deviates from
  /// the current route line (reroute), or when the destination changed.
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
  /// every GPS tick, and it never re-centers on the rider at full zoom (which
  /// would push the lender off-screen).
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

  /// Fits the camera once so all markers (rider + lender) are visible.
  /// Re-fits only when a new point appears (e.g. the lender's live GPS fix
  /// arriving after the map was first drawn), so an existing fit is never
  /// disturbed by the rider merely moving. Not used in [autofitBoth] mode.
  void _tryFitMarkersOnce(Set<Marker> markers) {
    if (widget.autofitBoth) return;
    final controller = _mapController;
    if (controller == null || markers.isEmpty) return;
    if (_didInitialFit && markers.length <= _lastFitCount) return;
    _didInitialFit = true;
    _lastFitCount = markers.length;
    _fitCamera(markers.map((m) => m.position));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderLocationProvider);
    final originLat = widget.originLat ?? state.lastLat;
    final originLng = widget.originLng ?? state.lastLng;
    final markers = _buildMarkers(
      riderLat: originLat,
      riderLng: originLng,
    );
    final polylines = _buildPolylines(
      riderLat: _displayOrigin?.latitude ?? originLat,
      riderLng: _displayOrigin?.longitude ?? originLng,
    );
    final circles = _buildCircles();
    final hasDestination =
        _effectiveLat != null && _effectiveLng != null;

    _reportResolved(_effectiveLat, _effectiveLng);

    // Follow the rider: animate the marker smoothly between GPS fixes
    // instead of teleporting. Camera follow is driven by _onMarkerTick
    // (frame-by-frame moveCamera) while _followRider is true.
    // For an external origin (lender tracking), updates arrive via widget
    // rebuilds handled in didUpdateWidget instead of the provider stream.
    ref.listen(riderLocationProvider, (prev, next) {
      if (_hasExternalOrigin || !mounted) return;
      final rLat = next.lastLat;
      final rLng = next.lastLng;
      if (rLat == null || rLng == null) return;
      // Seed display if first fix.
      if (_displayOrigin == null) {
        _displayOrigin = LatLng(rLat, rLng);
        _animStartOrigin = _displayOrigin;
        _animTargetOrigin = _displayOrigin;
        if (mounted) setState(() {});
        _tryFitBoth();
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

    // Seed from provider if we have a fix but no display yet (e.g. hot restart
    // or first build after tracking started elsewhere).
    if (_displayOrigin == null && originLat != null && originLng != null) {
      _displayOrigin = LatLng(originLat, originLng);
      _animStartOrigin = _displayOrigin;
      _animTargetOrigin = _displayOrigin;
    }

    // Fetch the road route once both points are known.
    if (_routePoints == null && hasDestination) {
      if (originLat != null && originLng != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchRoute(riderLat: originLat, riderLng: originLng);
        });
      }
    }

    // Autofit keeps both the rider and the lender in view; re-fit whenever a
    // point first appears (rider GPS fix or geocoded destination).
    if (widget.autofitBoth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryFitBoth();
      });
    } else if (!_didInitialFit || markers.length > _lastFitCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryFitMarkersOnce(markers);
      });
    }

    final hasCoords = hasDestination;
    final String? statusMessage;
    if (_geocoding) {
      statusMessage = 'Locating destination...';
    } else if (!hasCoords) {
      statusMessage = _geocodeFailed
          ? 'Could not pinpoint the address.'
          : 'No saved coordinates for this address yet.';
    } else {
      statusMessage = null;
    }

    // Surface GPS-posting failures (e.g. the backend rejecting the update) so
    // the rider can see why their live location isn't being shared.
    final locError = !_hasExternalOrigin ? state.error : null;
    final statusTop = locError != null ? 56.0 : 12.0;

    return Container(
      width: double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
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
                if (widget.autofitBoth) {
                  _tryFitBoth();
                } else {
                  _tryFitMarkersOnce(markers);
                }
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
              zoomControlsEnabled: false,
              compassEnabled: true,
            ),
          ),
          if (locError != null)
            Positioned(
              top: 12,
              left: 12,
              right: 56,
              child: _MapBanner(
                message: locError,
                loading: false,
                error: true,
              ),
            ),
          if (statusMessage != null)
            Positioned(
              top: statusTop,
              left: 12,
              right: 56,
              child: _MapBanner(
                message: statusMessage,
                loading: _geocoding,
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _openFullscreen,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fullscreen,
                  size: 20,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: GestureDetector(
              onTap: _openFullscreen,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fullscreen,
                        size: 16, color: AppColors.textPrimary),
                    SizedBox(width: 4),
                    Text(
                      'Fullscreen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 48,
            child: GestureDetector(
              onTap: _recenterOnRider,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  size: 20,
                  color: AppColors.riderGreen,
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 78,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ZoomButton(
                  icon: Icons.add,
                  onTap: _zoomIn,
                ),
                const SizedBox(height: 8),
                _ZoomButton(
                  icon: Icons.remove,
                  onTap: _zoomOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Legend chips shown next to the map so the user knows which pin is theirs.
class RiderMapLegend extends StatelessWidget {
  final String originLabel;
  final String destinationLabel;
  final Color originColor;
  final String? extraLabel;
  final Color? extraColor;
  const RiderMapLegend({
    super.key,
    this.originLabel = 'You (Rider)',
    this.destinationLabel = 'Lender',
    this.originColor = Colors.blueAccent,
    this.extraLabel,
    this.extraColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: originColor, label: originLabel),
        const SizedBox(width: 16),
        _LegendDot(color: Colors.pink, label: destinationLabel),
        if (extraLabel != null && extraColor != null) ...[
          const SizedBox(width: 16),
          _LegendDot(color: extraColor!, label: extraLabel!),
        ],
        const SizedBox(width: 16),
        const _LegendDot(color: AppColors.riderGreen, label: 'Route'),
      ],
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Icon(icon, size: 20, color: Colors.black87),
      ),
    );
  }
}

class _MapBanner extends StatelessWidget {
  final String message;
  final bool loading;
  final bool error;
  const _MapBanner({
    required this.message,
    required this.loading,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: error
            ? Colors.red.shade50.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color: error ? Colors.red : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 11,
                  color: error ? Colors.red.shade900 : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color, size: 18),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}