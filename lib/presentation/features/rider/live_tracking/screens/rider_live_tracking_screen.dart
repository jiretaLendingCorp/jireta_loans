// ignore_for_file: prefer_const_constructors
// lib/presentation/features/rider/live_tracking/screens/rider_live_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/services/route_service.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/map/map_anim_utils.dart';
import '../../dashboard/providers/rider_dashboard_provider.dart';
import '../../location/providers/rider_location_provider.dart';

class RiderLiveTrackingScreen extends ConsumerStatefulWidget {
  const RiderLiveTrackingScreen({super.key});

  @override
  ConsumerState<RiderLiveTrackingScreen> createState() => _RiderLiveTrackingScreenState();
}

class _RiderLiveTrackingScreenState extends ConsumerState<RiderLiveTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapCtrl;
  bool _didInitialFit = false;
  bool _showRoutes = true;
  String _filter = 'All'; // All, Collections, Deliveries, CI
  int _selectedTaskIndex = 0;

  late final AnimationController _animCtrl;
  late final AnimationController _pulseCtrl;
  LatLng? _displayPos;
  LatLng? _animStart;
  LatLng? _animTarget;
  double _bearing = 0;

  LatLng? _destPos;
  String? _destLabel;
  List<LatLng>? _routePoints;
  double? _routeDistanceKm;
  int? _routeDurationSecs;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  bool _fetchingRoute = false;
  bool _geocoding = false;

  static const _phCenter = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..addListener(_onAnimTick);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(riderLocationProvider);
      if (!s.isTracking) ref.read(riderLocationProvider.notifier).startTracking();
      if (s.lastLat != null && s.lastLng != null) {
        _displayPos = LatLng(s.lastLat!, s.lastLng!);
        _animStart = _displayPos;
        _animTarget = _displayPos;
        if (mounted) setState(() {});
      }
      _resolveSelectedDestination();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user switches to system Settings to flip the location toggle and
    // then returns, detected instantly without waiting for the next timer tick.
    if (state == AppLifecycleState.resumed) {
      ref.read(riderLocationProvider.notifier).onAppResumed();
    }
  }

  void _onAnimTick() {
    final s = _animStart;
    final e = _animTarget;
    if (s == null || e == null) return;
    final t = easeInOutCubic(_animCtrl.value);
    _displayPos = lerpLatLng(s, e, t);
    if (mounted) setState(() {});
  }

  void _animateTo(LatLng newPos) {
    if (_displayPos == null) {
      _displayPos = newPos;
      _animStart = newPos;
      _animTarget = newPos;
      if (mounted) setState(() {});
      _fitToAll();
      return;
    }
    final target = _animTarget;
    if (target != null &&
        (target.latitude - newPos.latitude).abs() < 0.00001 &&
        (target.longitude - newPos.longitude).abs() < 0.00001) {
      return;
    }
    _animStart = _displayPos;
    _animTarget = newPos;
    _bearing = bearingBetween(_animStart!, newPos);
    _animCtrl.forward(from: 0);
    // Route is recalculated only when rider moves significantly (see _fetchRoute throttling).
    if (_destPos != null) _fetchRoute(newPos, _destPos!);
  }

  Future<void> _resolveSelectedDestination() async {
    final dash = ref.read(riderDashboardProvider);
    final allTasks = _allTasks(dash);
    if (allTasks.isEmpty) return;
    final idx = _selectedTaskIndex.clamp(0, allTasks.length - 1);
    final task = allTasks[idx];
    final address = task['address'] as String? ?? '';
    final label = task['label'] as String? ?? 'Lender';
    if (address.trim().isEmpty || address == 'Address not available') {
      setState(() {
        _destPos = null;
        _destLabel = label;
        _routePoints = null;
        _routeDistanceKm = null;
        _routeDurationSecs = null;
        _lastRouteOrigin = null;
        _lastRouteDest = null;
      });
      return;
    }
    setState(() => _geocoding = true);
    try {
      final locs = await locationFromAddress(address);
      if (!mounted) return;
      if (locs.isNotEmpty) {
        final dest = LatLng(locs.first.latitude, locs.first.longitude);
        setState(() {
          _destPos = dest;
          _destLabel = label;
          _geocoding = false;
        });
        if (_displayPos != null) await _fetchRoute(_displayPos!, dest);
        _fitToAll();
      } else {
        setState(() => _geocoding = false);
      }
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  String _formatLenderLabel(String name, String fallback) {
    if (name.trim().isEmpty) return fallback;
    final trimmed = name.trim();
    if (trimmed.toUpperCase().startsWith('LENDER:')) return trimmed;
    return 'LENDER: $trimmed';
  }

  List<Map<String, dynamic>> _allTasks(RiderDashboardState dash) {
    final list = <Map<String, dynamic>>[];
    for (final c in dash.todayCollections) {
      final addrs = c.lenderAddresses;
      String addr = '';
      if (addrs.isNotEmpty && addrs.first is Map) {
        final m = addrs.first as Map;
        addr = [m['street'], m['barangay'], m['city'], m['province']].where((e) => e.toString().isNotEmpty).join(', ');
      }
      final rawLabel = c.lenderName.isEmpty ? 'Collection' : c.lenderName;
      final label = _formatLenderLabel(rawLabel, 'LENDER: Collection');
      list.add({'type': 'Collection', 'label': label, 'subtitle': c.loanNumber, 'address': addr, 'status': c.statusLabel, 'raw': c});
    }
    for (final d in dash.todayDeliveries) {
      final addr = d.loan?['lender_address']?.toString() ?? d.loan?['address']?.toString() ?? '';
      final rawLabel = d.lenderName.isEmpty ? 'Delivery' : d.lenderName;
      final label = _formatLenderLabel(rawLabel, 'LENDER: Delivery');
      list.add({'type': 'Delivery', 'label': label, 'subtitle': d.loanNumber, 'address': addr, 'status': d.status, 'raw': d});
    }
    for (final ci in dash.todayCiTasks) {
      final rawCiLabel = ci.borrowerName.isEmpty ? 'Lender' : ci.borrowerName;
      final ciLabel = _formatLenderLabel(rawCiLabel, 'LENDER');
      list.add({'type': 'CI', 'label': ciLabel, 'subtitle': ci.loanNumber, 'address': ci.borrowerAddress, 'status': ci.statusLabel, 'raw': ci});
    }
    // filter
    if (_filter == 'Collections') return list.where((e) => e['type'] == 'Collection').toList();
    if (_filter == 'Deliveries') return list.where((e) => e['type'] == 'Delivery').toList();
    if (_filter == 'CI') return list.where((e) => e['type'] == 'CI').toList();
    return list;
  }

  Future<void> _fetchRoute(LatLng origin, LatLng dest) async {
    if (_fetchingRoute) return;
    // Throttle route updates: same origin threshold ~500m or destination changed
    final originChanged = _lastRouteOrigin == null ||
        (_lastRouteOrigin!.latitude - origin.latitude).abs() > 0.0045 ||
        (_lastRouteOrigin!.longitude - origin.longitude).abs() > 0.0045;
    final destChanged = _lastRouteDest == null ||
        (_lastRouteDest!.latitude - dest.latitude).abs() > 0.0001 ||
        (_lastRouteDest!.longitude - dest.longitude).abs() > 0.0001;
    if (!originChanged && !destChanged && _routePoints != null) return;

    _fetchingRoute = true;
    final result = await RouteService.fetchRoute(origin, dest);
    _fetchingRoute = false;
    if (!mounted) return;
    if (result != null && result.points.isNotEmpty) {
      setState(() {
        _routePoints = result.points;
        _routeDistanceKm = result.distanceKm;
        _routeDurationSecs = result.durationSecs;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    } else {
      // No road route: keep haversine fallback for distance, clear route duration
      if (mounted) {
        setState(() {
          _routeDistanceKm = null;
          _routeDurationSecs = null;
        });
      }
    }
  }

  Future<void> _fitToAll() async {
    final c = _mapCtrl;
    if (c == null) return;
    final pts = <LatLng>[
      if (_displayPos != null) _displayPos!,
      if (_destPos != null) _destPos!,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
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
    await c.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 80));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animCtrl.removeListener(_onAnimTick);
    _animCtrl.dispose();
    _pulseCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(riderLocationProvider);
    final dash = ref.watch(riderDashboardProvider);

    ref.listen(riderLocationProvider, (prev, next) {
      if (!mounted) return;
      final lat = next.lastLat, lng = next.lastLng;
      if (lat == null || lng == null) return;
      if (prev?.lastLat == lat && prev?.lastLng == lng) return;
      _animateTo(LatLng(lat, lng));
    });

    if (_displayPos == null && loc.lastLat != null && loc.lastLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _displayPos != null) return;
        _displayPos = LatLng(loc.lastLat!, loc.lastLng!);
        _animStart = _displayPos;
        _animTarget = _displayPos;
        setState(() {});
        _fitToAll();
      });
    }

    final allTasks = _allTasks(dash);
    final hasTasks = allTasks.isNotEmpty;
    final selectedTask = hasTasks ? allTasks[_selectedTaskIndex.clamp(0, allTasks.length - 1)] : null;

    final markers = <Marker>{};
    final circles = <Circle>{};
    if (_displayPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('rider'),
        position: _displayPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        rotation: _bearing,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'You', snippet: ''),
      ));
      circles.add(Circle(
        circleId: const CircleId('halo'),
        center: _displayPos!,
        radius: 26,
        strokeWidth: 1,
        strokeColor: AppColors.riderGreen.withValues(alpha: 0.3),
        fillColor: AppColors.riderGreen.withValues(alpha: 0.08),
      ));
    }
    if (_destPos != null) {
      final destTitle = _destLabel != null
          ? (_destLabel!.toUpperCase().startsWith('LENDER:') ? _destLabel! : 'LENDER: $_destLabel')
          : 'LENDER';
      markers.add(Marker(
        markerId: const MarkerId('dest'),
        position: _destPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        infoWindow: InfoWindow(title: destTitle, snippet: 'Lender Location'),
      ));
    }

    final polylines = <Polyline>{};
    if (_showRoutes && _routePoints != null && _routePoints!.length > 1) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints!,
        color: const Color(0xFF1A73E8),
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
    }

    // Real distance / ETA / speed — all dynamic from GPS & routing API.
    // Distance: use authoritative route distance when available, else haversine.
    // ETA: prefer routing API duration, else speed-based estimate.
    // Speed: GPS speed m/s*3.6 with validation & smoothing from provider; show -- if invalid.
    double? riderDistKm;
    String? riderDistText;
    String? riderEtaText;
    if (_displayPos != null && _destPos != null) {
      if (_routeDistanceKm != null && _routePoints != null && _routePoints!.length > 1) {
        riderDistKm = _routeDistanceKm;
      } else if (_routePoints != null && _routePoints!.length > 1) {
        riderDistKm = polylineKm(_routePoints!);
      } else {
        riderDistKm = haversineKm(_displayPos!, _destPos!);
      }
      if (riderDistKm != null) {
        riderDistText = formatDistanceKm(riderDistKm);
        if (_routeDurationSecs != null && _routeDurationSecs! > 0) {
          riderEtaText = formatEtaFromDuration(_routeDurationSecs!);
        } else {
          riderEtaText = formatEta(riderDistKm, speedKmh: loc.lastSpeedKmh, fallbackToEstimate: true);
        }
      }
    }
    final riderSpeedText = formatSpeedKmh(loc.lastSpeedKmh);

    return MobileScaffold(
      title: 'Live Tracking',
      accentColor: AppColors.riderGreen,
      showBackButton: true,
      navItems: const [
        MobileNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', route: RouteConstants.riderDashboard),
        MobileNavItem(icon: Icons.delivery_dining_outlined, activeIcon: Icons.delivery_dining, label: 'Collections', route: RouteConstants.riderCollections),
        MobileNavItem(icon: Icons.search_outlined, activeIcon: Icons.search, label: 'CI Tasks', route: RouteConstants.riderCi),
        MobileNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', route: RouteConstants.riderProfile),
      ],
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _displayPos ?? _phCenter, zoom: _displayPos != null ? 15 : 12),
            onMapCreated: (c) {
              _mapCtrl = c;
              if (!_didInitialFit && _displayPos != null) {
                _didInitialFit = true;
                _fitToAll();
              }
            },
            markers: markers,
            circles: circles,
            polylines: polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),
          // Top live badge
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final s = 0.85 + 0.25 * _pulseCtrl.value;
                      return Stack(alignment: Alignment.center, children: [
                        Opacity(opacity: (1 - _pulseCtrl.value) * 0.45, child: Container(width: 10 * s, height: 10 * s, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle))),
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      ]);
                    },
                  ),
                  const SizedBox(width: 6),
                  const Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success)),
                  const SizedBox(width: 6),
                  Text(_displayPos != null ? 'You are on the move' : 'Acquiring GPS...', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ),
              const Spacer(),
              if (_geocoding)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 6), Text('Locating...', style: TextStyle(fontSize: 10))]),
                ),
            ]),
          ),
          // ── GPS off / permission banner — appears instantly when the rider
          // flips the system location toggle (serviceStatusStream) or denies
          // permission. "Turn On" jumps to system settings.
          if (loc.error != null)
            Positioned(
              top: 44,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: loc.error!.contains('permanently denied')
                      ? AppColors.error.withValues(alpha: 0.95)
                      : const Color(0xFFE53E3E),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.error!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        if (loc.error!.contains('permanently denied')) {
                          ref.read(riderLocationProvider.notifier).openAppSettings();
                        } else {
                          ref.read(riderLocationProvider.notifier).openLocationSettings();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          loc.error!.contains('permanently denied') ? 'Open Settings' : 'Turn On',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: loc.error!.contains('permanently denied') ? AppColors.error : const Color(0xFFE53E3E)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Tracking controls (top-left)
          Positioned(
            top: 56,
            left: 12,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Tracking Controls', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _FilterChip(label: 'All', count: allTasks.length, selected: _filter == 'All', onTap: () { setState(() { _filter = 'All'; _selectedTaskIndex = 0; }); _resolveSelectedDestination(); }),
                _FilterChip(label: 'Collections', count: dash.todayCollections.length, selected: _filter == 'Collections', onTap: () { setState(() { _filter = 'Collections'; _selectedTaskIndex = 0; }); _resolveSelectedDestination(); }),
                _FilterChip(label: 'Deliveries', count: dash.todayDeliveries.length, selected: _filter == 'Deliveries', onTap: () { setState(() { _filter = 'Deliveries'; _selectedTaskIndex = 0; }); _resolveSelectedDestination(); }),
                _FilterChip(label: 'CI', count: dash.todayCiTasks.length, selected: _filter == 'CI', onTap: () { setState(() { _filter = 'CI'; _selectedTaskIndex = 0; }); _resolveSelectedDestination(); }),
                const Divider(height: 16),
                Row(children: [
                  SizedBox(width: 18, height: 18, child: Checkbox(value: _showRoutes, onChanged: (v) => setState(() => _showRoutes = v ?? true), activeColor: AppColors.riderGreen, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                  const SizedBox(width: 6),
                  const Text('Show Routes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(riderLocationProvider.notifier).startTracking();
                      _resolveSelectedDestination();
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), side: const BorderSide(color: AppColors.border)),
                  ),
                ),
              ]),
            ),
          ),
          // Task detail overlay (top-right)
          if (selectedTask != null)
            Positioned(
              top: 56,
              right: 12,
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 18, backgroundColor: AppColors.riderGreen.withValues(alpha: 0.1), child: Icon(selectedTask['type'] == 'Collection' ? Icons.payments_outlined : selectedTask['type'] == 'Delivery' ? Icons.delivery_dining : Icons.search, size: 18, color: AppColors.riderGreen)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Builder(builder: (context) {
                          final raw = selectedTask['label'] as String;
                          final displayLabel = raw.toUpperCase().startsWith('LENDER:') ? raw : 'LENDER: $raw';
                          return Text(displayLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800));
                        }),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(20)),
                          child: Text(selectedTask['status'] as String, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(selectedTask['subtitle'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(selectedTask['address'] as String == '' ? 'No address on file' : selectedTask['address'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.speed, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text('Speed: $riderSpeedText', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(_relative(loc.lastUpdated), style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                  ]),
                  if (riderDistText != null && riderEtaText != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.route_outlined, size: 12, color: AppColors.riderGreen),
                      const SizedBox(width: 4),
                      Text('$riderDistText • ETA: $riderEtaText', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.riderGreen)),
                    ]),
                  ],
                ]),
              ),
            ),
          // ETA tooltip center
          if (_displayPos != null && _destPos != null)
            Positioned(
              top: 240,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                  child: Text(riderDistText != null && riderEtaText != null ? 'You → Lender  •  ETA: $riderEtaText  •  $riderDistText' : 'You → Lender  •  Locating…', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          // Bottom carousel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Active Tasks (${allTasks.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {},
                    child: const Row(children: [Text('View All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.riderGreen)), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 14, color: AppColors.riderGreen)]),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: allTasks.isEmpty
                      ? const Center(child: Text('No active tasks', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: allTasks.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final t = allTasks[i];
                            final isSel = i == _selectedTaskIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedTaskIndex = i);
                                _resolveSelectedDestination();
                              },
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSel ? AppColors.riderGreen : AppColors.border, width: isSel ? 1.5 : 1),
                                  boxShadow: isSel ? [BoxShadow(color: AppColors.riderGreen.withValues(alpha: 0.15), blurRadius: 8)] : null,
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(t['type'] == 'Collection' ? Icons.payments : t['type'] == 'Delivery' ? Icons.delivery_dining : Icons.search, size: 14, color: AppColors.riderGreen),
                                    const SizedBox(width: 4),
                                    Expanded(child: Builder(builder: (context) {
                                      final raw = t['label'] as String;
                                      final displayLabel = raw.toUpperCase().startsWith('LENDER:') ? raw : 'LENDER: $raw';
                                      return Text(displayLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700));
                                    })),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(t['subtitle'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(20)),
                                    child: Text(t['status'] as String, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: loc.error != null ? AppColors.error.withValues(alpha: 0.12) : AppColors.successLight,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(loc.error != null ? 'GPS Signal Lost' : 'All Systems Operational',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: loc.error != null ? AppColors.error : AppColors.success)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: loc.error != null ? AppColors.error.withValues(alpha: 0.12) : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: loc.error != null ? AppColors.error.withValues(alpha: 0.3) : AppColors.border)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: loc.error != null ? AppColors.error : AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(loc.error != null ? 'GPS Off' : (loc.isTracking ? 'GPS Online' : 'GPS Off'),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: loc.error != null ? AppColors.error : (loc.isTracking ? AppColors.success : AppColors.textSecondary))),
                    ]),
                  ),
                  const Spacer(),
                  Text(loc.lastUpdated != null ? 'Updated: ${_relative(loc.lastUpdated)}' : 'No fix yet', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                ]),
              ]),
            ),
          ),
          // Map controls
          Positioned(
            right: 12,
            bottom: 140,
            child: Column(children: [
              _MapBtn(icon: Icons.add, onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomIn())),
              const SizedBox(height: 8),
              _MapBtn(icon: Icons.remove, onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomOut())),
              const SizedBox(height: 8),
              _MapBtn(icon: Icons.my_location, onTap: _fitToAll),
            ]),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime? dt) {
    if (dt == null) return '—';
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.riderGreen : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppColors.riderGreen : AppColors.border),
          ),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: selected ? Colors.white : AppColors.riderGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? AppColors.riderGreen : AppColors.riderGreen)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]), child: Icon(icon, size: 18, color: Colors.black87)),
    );
  }
}
