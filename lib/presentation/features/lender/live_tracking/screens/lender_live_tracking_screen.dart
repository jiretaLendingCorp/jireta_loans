// ignore_for_file: prefer_const_constructors
// lib/presentation/features/lender/live_tracking/screens/lender_live_tracking_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/services/route_service.dart';
import '../../../../../data/models/tracked_rider_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/map/map_anim_utils.dart';
import '../../dashboard/providers/lender_rider_tracking_provider.dart';
import '../../collections/providers/lender_collection_provider.dart';

class LenderLiveTrackingScreen extends ConsumerStatefulWidget {
  const LenderLiveTrackingScreen({super.key});

  @override
  ConsumerState<LenderLiveTrackingScreen> createState() => _LenderLiveTrackingScreenState();
}

class _LenderLiveTrackingScreenState extends ConsumerState<LenderLiveTrackingScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapCtrl;
  bool _didInitialFit = false;
  bool _showRoutes = true;
  String? _selectedRiderId;

  // Animated markers
  late final AnimationController _animCtrl;
  late final AnimationController _pulseCtrl;
  final Map<String, LatLng> _displayPos = {};
  final Map<String, LatLng> _animStart = {};
  final Map<String, LatLng> _animTarget = {};
  final Map<String, double> _bearings = {};

  // Route for selected rider (road route + authoritative metrics)
  List<LatLng>? _routePoints;
  LatLng? _selectedDest;
  String? _selectedDestLabel;
  bool _fetchingRoute = false;
  double? _selectedDistanceKm;
  int? _selectedDurationSecs;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  final Map<String, double> _riderSpeedsKmh = {};
  final Map<String, DateTime> _riderPrevTime = {};

  static const _phCenter = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..addListener(_onAnimTick);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  void _onAnimTick() {
    final t = easeInOutCubic(_animCtrl.value);
    var changed = false;
    for (final id in _animTarget.keys) {
      final s = _animStart[id];
      final e = _animTarget[id];
      if (s == null || e == null) continue;
      _displayPos[id] = lerpLatLng(s, e, t);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _maybeUpdateTargets(List<TrackedRiderModel> riders) {
    final activeIds = <String>{};
    for (final r in riders) {
      if (!r.hasLocation || r.isStale) continue;
      activeIds.add(r.riderId);
      final newPos = LatLng(r.latitude!, r.longitude!);
      // Prefer authoritative GPS speed from provider; else derive from delta.
      final gpsSpeed = r.validatedSpeedKmh;
      if (gpsSpeed != null) {
        _riderSpeedsKmh[r.riderId] = gpsSpeed;
      }
      if (!_displayPos.containsKey(r.riderId)) {
        _displayPos[r.riderId] = newPos;
        _animStart[r.riderId] = newPos;
        _animTarget[r.riderId] = newPos;
        _bearings[r.riderId] = 0;
        if (r.locationUpdatedAt != null) _riderPrevTime[r.riderId] = r.locationUpdatedAt!;
        // Seed speed from GPS if available
        if (gpsSpeed == null && r.locationUpdatedAt != null) {
          _riderPrevTime[r.riderId] = r.locationUpdatedAt!;
        }
        continue;
      }
      final existing = _animTarget[r.riderId];
      if (existing != null &&
          (existing.latitude - newPos.latitude).abs() < 0.00001 &&
          (existing.longitude - newPos.longitude).abs() < 0.00001) {
        continue;
      }
      // If GPS speed missing, derive from distance/time as fallback (not invented).
      if (gpsSpeed == null) {
        final prevPos = existing ?? _displayPos[r.riderId];
        final prevTime = _riderPrevTime[r.riderId];
        final newTime = r.locationUpdatedAt;
        if (prevPos != null && prevTime != null && newTime != null) {
          final distKm = haversineKm(prevPos, newPos);
          final secs = newTime.difference(prevTime).inSeconds;
          if (secs > 5 && distKm > 0.01) {
            final kmh = distKm / (secs / 3600);
            if (kmh >= 1 && kmh <= 90) _riderSpeedsKmh[r.riderId] = kmh;
          } else if (secs > 10 && distKm < 0.005) {
            _riderSpeedsKmh[r.riderId] = 0;
          }
        }
      }
      if (r.locationUpdatedAt != null) _riderPrevTime[r.riderId] = r.locationUpdatedAt!;
      _animStart[r.riderId] = _displayPos[r.riderId]!;
      _animTarget[r.riderId] = newPos;
      _bearings[r.riderId] = bearingBetween(_animStart[r.riderId]!, newPos);
      _animCtrl.forward(from: 0);
      // Update selected distance if this is the selected rider — keep route distance authoritative.
      if (r.riderId == _selectedRiderId && _selectedDest != null) {
        if (_selectedDurationSecs == null || _routePoints == null) {
          // No route duration: use haversine until road route arrives.
          _selectedDistanceKm = haversineKm(newPos, _selectedDest!);
          if (_selectedDurationSecs == null) {
            // Trigger route fetch for new position
            _fetchRoute(newPos, _selectedDest!);
          }
        }
      }
    }
    final toRemove = _displayPos.keys.where((k) => !activeIds.contains(k)).toList();
    for (final id in toRemove) {
      _displayPos.remove(id);
      _animStart.remove(id);
      _animTarget.remove(id);
      _bearings.remove(id);
      _riderPrevTime.remove(id);
      // keep speed for history? clear to avoid stale display
      _riderSpeedsKmh.remove(id);
    }
  }

  Future<void> _selectRider(String riderId) async {
    setState(() {
      _selectedRiderId = riderId;
      _routePoints = null;
      _selectedDest = null;
      _selectedDistanceKm = null;
      _selectedDurationSecs = null;
      _lastRouteOrigin = null;
      _lastRouteDest = null;
    });
    try {
      final data = await ref.read(lenderCollectionProvider.notifier).getRiderLocation(riderId);
      if (!mounted || data == null) return;
      final dLat = (data['destination_latitude'] as num?)?.toDouble();
      final dLng = (data['destination_longitude'] as num?)?.toDouble();
      final label = data['destination_label'] as String?;
      final rLat = (data['latitude'] as num?)?.toDouble();
      final rLng = (data['longitude'] as num?)?.toDouble();
      // Also hydrate speed from rider location payload if present
      final speedRaw = (data['speed_kmh'] ?? data['speed']) as num?;
      if (speedRaw != null) {
        final kmh = speedRaw < 70 && data['speed_mps'] == null && data['speed'] != null
            ? speedRaw.toDouble() * 3.6
            : speedRaw.toDouble();
        if (kmh.isFinite && kmh >= 0 && kmh <= 120) _riderSpeedsKmh[riderId] = kmh;
      }
      if (dLat != null && dLng != null) {
        final dest = LatLng(dLat, dLng);
        setState(() {
          _selectedDest = dest;
          _selectedDestLabel = label;
          final riderPos = (rLat != null && rLng != null) ? LatLng(rLat, rLng) : _displayPos[riderId];
          if (riderPos != null) _selectedDistanceKm = haversineKm(riderPos, dest);
        });
        if (rLat != null && rLng != null) {
          await _fetchRoute(LatLng(rLat, rLng), dest);
        } else {
          final display = _displayPos[riderId];
          if (display != null) await _fetchRoute(display, dest);
        }
        _fitToSelected();
      }
    } catch (_) {}
  }

  Future<void> _fetchRoute(LatLng origin, LatLng dest) async {
    if (_fetchingRoute) return;
    // Throttle: only refetch if origin moved > ~500m or dest changed
    final originMoved = _lastRouteOrigin == null ||
        (_lastRouteOrigin!.latitude - origin.latitude).abs() > 0.0045 ||
        (_lastRouteOrigin!.longitude - origin.longitude).abs() > 0.0045;
    final destMoved = _lastRouteDest == null ||
        (_lastRouteDest!.latitude - dest.latitude).abs() > 0.0001 ||
        (_lastRouteDest!.longitude - dest.longitude).abs() > 0.0001;
    if (!originMoved && !destMoved && _routePoints != null) return;

    _fetchingRoute = true;
    final result = await RouteService.fetchRoute(origin, dest);
    _fetchingRoute = false;
    if (!mounted) return;
    if (result != null && result.points.isNotEmpty) {
      setState(() {
        _routePoints = result.points;
        _selectedDistanceKm = result.distanceKm;
        _selectedDurationSecs = result.durationSecs;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    } else {
      // No road route — keep haversine distance, no duration (ETA will use speed)
      setState(() {
        _selectedDistanceKm = haversineKm(origin, dest);
        _selectedDurationSecs = null;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    }
  }

  Future<void> _fitToSelected() async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    final riderPos = _selectedRiderId != null ? _displayPos[_selectedRiderId] : null;
    final points = <LatLng>[
      if (riderPos != null) riderPos,
      if (_selectedDest != null) _selectedDest!,
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await ctrl.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 80));
  }

  Future<void> _fitAll(Set<Marker> markers) async {
    final ctrl = _mapCtrl;
    if (ctrl == null || markers.isEmpty) return;
    final pts = markers.map((m) => m.position).toList();
    if (pts.length == 1) {
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 14));
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
    await ctrl.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 60));
  }

  double _hueFor(String type) => switch (type) {
        'disbursement' => BitmapDescriptor.hueGreen,
        'ci' => BitmapDescriptor.hueOrange,
        _ => BitmapDescriptor.hueViolet,
      };

  String _typeLabel(String t) => switch (t) {
        'disbursement' => 'Loan Delivery',
        'ci' => 'Credit Investigation',
        _ => 'Collection',
      };

  String _displayRiderName(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'RIDER';
    if (t.toUpperCase().startsWith('RIDER:')) return t;
    return 'RIDER: $t';
  }

  String _relative(DateTime? dt) {
    if (dt == null) return 'Waiting';
    final d = nowManila().difference(dt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_onAnimTick);
    _animCtrl.dispose();
    _pulseCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderRiderTrackingProvider);
    final riders = state.riders;

    // Sync animated positions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final before = _displayPos.length;
      _maybeUpdateTargets(riders);
      if (_displayPos.length != before && mounted) setState(() {});
      // auto-select first active if none selected
      if (_selectedRiderId == null && riders.isNotEmpty) {
        final firstLive = riders.firstWhere((r) => r.hasLocation && !r.isStale, orElse: () => riders.first);
        if (_selectedRiderId != firstLive.riderId) {
          _selectRider(firstLive.riderId);
        }
      }
    });
    if (_displayPos.isEmpty) {
      for (final r in riders) {
        if (r.hasLocation && !r.isStale && !_displayPos.containsKey(r.riderId)) {
          _displayPos[r.riderId] = LatLng(r.latitude!, r.longitude!);
          _animTarget[r.riderId] = _displayPos[r.riderId]!;
          _animStart[r.riderId] = _displayPos[r.riderId]!;
        }
      }
    }

    final selected = _selectedRiderId != null
        ? riders.where((r) => r.riderId == _selectedRiderId).cast<TrackedRiderModel?>().firstWhere((e) => e != null, orElse: () => null)
        : null;

    // Dynamic distance/ETA/speed for selected rider — real GPS + road route.
    // Distance: from routing API distance when available, else haversine live.
    // ETA: prefer routing API duration, else speed-based.
    // Speed: GPS speed (validated) else derived; show -- if invalid.
    String? selectedDistText;
    String? selectedEtaText;
    String selectedSpeedText = '—';
    if (selected != null) {
      double? distKm = _selectedDistanceKm;
      // Keep distance live as rider moves even without refetch.
      if (_selectedDest != null && _displayPos[selected.riderId] != null) {
        final liveDist = haversineKm(_displayPos[selected.riderId]!, _selectedDest!);
        // If we have a route, blend? Use route distance when recent, else live.
        distKm ??= liveDist;
        // If route is stale (rider moved significantly since last fetch), show live until refetch.
        if (_lastRouteOrigin != null) {
          final moved = (_lastRouteOrigin!.latitude - _displayPos[selected.riderId]!.latitude).abs() > 0.004 ||
              (_lastRouteOrigin!.longitude - _displayPos[selected.riderId]!.longitude).abs() > 0.004;
          if (moved) distKm = liveDist;
        }
      }
      if (distKm != null) {
        selectedDistText = formatDistanceKm(distKm);
        if (_selectedDurationSecs != null && _selectedDurationSecs! > 0) {
          selectedEtaText = formatEtaFromDuration(_selectedDurationSecs!);
        } else {
          final gpsSpd = selected.validatedSpeedKmh ?? _riderSpeedsKmh[selected.riderId];
          selectedEtaText = formatEta(distKm, speedKmh: gpsSpd, fallbackToEstimate: true);
        }
      }
      final gpsSpd = selected.validatedSpeedKmh;
      final derived = _riderSpeedsKmh[selected.riderId];
      final displaySpd = gpsSpd ?? derived;
      selectedSpeedText = formatSpeedKmh(displaySpd);
    }

    // Counts for controls
    final total = riders.length;
    final active = riders.where((r) => r.hasLocation && !r.isStale).length;
    final onBreak = riders.where((r) => r.isStale).length;
    final offline = riders.where((r) => !r.hasLocation).length;

    // Build markers & circles
    final markers = <Marker>{};
    final seen = <String>{};
    for (final r in riders) {
      if (!r.hasLocation || r.isStale || seen.contains(r.riderId)) continue;
      seen.add(r.riderId);
      final pos = _displayPos[r.riderId] ?? LatLng(r.latitude!, r.longitude!);
      final isSelected = r.riderId == _selectedRiderId;
      markers.add(Marker(
        markerId: MarkerId('rider-${r.riderId}'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(r.assignmentType)),
        rotation: _bearings[r.riderId] ?? 0,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: isSelected ? 2 : 1,
        infoWindow: InfoWindow(title: _displayRiderName(r.riderName), snippet: '${_typeLabel(r.assignmentType)} • ${r.loanNumber}'),
        onTap: () => _selectRider(r.riderId),
      ));
    }
    // Destination marker for selected
    if (_selectedDest != null) {
      markers.add(Marker(
        markerId: const MarkerId('dest'),
        position: _selectedDest!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _selectedDestLabel ?? 'Destination', snippet: 'Lender location'),
      ));
    }
    // No placeholder office marker — only real rider/destination positions.

    final circles = <Circle>{
      for (final e in _displayPos.entries)
        Circle(
          circleId: CircleId('pulse-${e.key}'),
          center: e.value,
          radius: e.key == _selectedRiderId ? 28 : 20,
          strokeWidth: 1,
          strokeColor: AppColors.lenderBlue.withValues(alpha: e.key == _selectedRiderId ? 0.35 : 0.18),
          fillColor: AppColors.lenderBlue.withValues(alpha: e.key == _selectedRiderId ? 0.12 : 0.06),
        ),
    };

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

    return MobileScaffold(
      title: 'Live Tracking',
      accentColor: AppColors.lenderBlue,
      showBackButton: true,
      navItems: const [
        MobileNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', route: RouteConstants.lenderDashboard),
        MobileNavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Payments', route: RouteConstants.lenderPayments),
        MobileNavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'History', route: RouteConstants.lenderPaymentHistory),
        MobileNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', route: RouteConstants.lenderProfile),
      ],
      body: riders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_off, size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  const Text('No active riders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('Your assigned riders will appear here once they accept a collection or delivery.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.read(lenderRiderTrackingProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.lenderBlue),
                  ),
                ]),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: markers.isNotEmpty ? markers.first.position : _phCenter,
                    zoom: 13,
                  ),
                  onMapCreated: (c) {
                    _mapCtrl = c;
                    if (!_didInitialFit && markers.isNotEmpty) {
                      _didInitialFit = true;
                      _fitAll(markers);
                    }
                  },
                  markers: markers,
                  circles: circles,
                  polylines: polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                ),
                // Top Live badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) {
                          final s = 0.85 + 0.25 * _pulseCtrl.value;
                          return Stack(alignment: Alignment.center, children: [
                            Opacity(
                                opacity: (1 - _pulseCtrl.value) * 0.45,
                                child: Container(width: 10 * s, height: 10 * s, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle))),
                            Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                          ]);
                        },
                      ),
                      const SizedBox(width: 6),
                      const Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success)),
                    ]),
                  ),
                ),
                // Tracking Controls (top-left card)
                Positioned(
                  top: 56,
                  left: 12,
                  child: Container(
                    width: 168,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Tracking Controls', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      _ControlRow(icon: Icons.people_outline, label: 'All Riders', count: total, color: AppColors.textPrimary),
                      const SizedBox(height: 6),
                      _ControlRow(icon: Icons.circle, label: 'Active Riders', count: active, color: AppColors.success, dot: true),
                      const SizedBox(height: 6),
                      _ControlRow(icon: Icons.pause_circle_outline, label: 'On Break', count: onBreak, color: AppColors.warning),
                      const SizedBox(height: 6),
                      _ControlRow(icon: Icons.cloud_off_outlined, label: 'Offline', count: offline, color: AppColors.textTertiary),
                      const Divider(height: 16),
                      Row(children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(value: _showRoutes, onChanged: (v) => setState(() => _showRoutes = v ?? true), activeColor: AppColors.lenderBlue, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        ),
                        const SizedBox(width: 6),
                        const Text('Show Routes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(lenderRiderTrackingProvider.notifier).refresh();
                            if (_selectedRiderId != null) _selectRider(_selectedRiderId!);
                          },
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), side: const BorderSide(color: AppColors.border)),
                        ),
                      ),
                    ]),
                  ),
                ),
                // Rider detail overlay (top-right)
                if (selected != null)
                  Positioned(
                    top: 56,
                    right: 12,
                    child: Container(
                      width: 210,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(radius: 20, backgroundColor: AppColors.lenderBlue.withValues(alpha: 0.1), child: Text((selected.riderName.isEmpty ? 'R' : selected.riderName[0]).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.lenderBlue))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_displayRiderName(selected.riderName), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(20)),
                                child: Text(selected.isStale ? 'Paused' : 'On Delivery', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                              ),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _DetailRow(icon: Icons.confirmation_number_outlined, label: 'Loan', value: selected.loanNumber.isEmpty ? '-' : selected.loanNumber),
                        _DetailRow(icon: Icons.local_offer_outlined, label: 'Type', value: _typeLabel(selected.assignmentType)),
                        _DetailRow(icon: Icons.speed, label: 'Speed', value: selectedSpeedText),
                        _DetailRow(icon: Icons.access_time, label: 'Last Update', value: _relative(selected.locationUpdatedAt)),
                        if (selectedDistText != null) _DetailRow(icon: Icons.route_outlined, label: 'Distance', value: selectedDistText),
                        if (selectedEtaText != null) _DetailRow(icon: Icons.timer_outlined, label: 'ETA', value: selectedEtaText),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => context.push(RouteConstants.lenderTrackRider.replaceFirst(':id', selected.riderId)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('View Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.lenderBlue)), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 14, color: AppColors.lenderBlue)]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                // ETA tooltip above selected marker
                if (selected != null && _displayPos[selected.riderId] != null)
                  Positioned(
                    top: 220,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                        child: Text(
                            selectedDistText != null && selectedEtaText != null
                                ? '${_displayRiderName(selected.riderName)}  •  ETA: $selectedEtaText  •  $selectedDistText'
                                : '${_displayRiderName(selected.riderName)}  •  Locating…',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                    ),
                  ),
                // Map controls right
                Positioned(
                  right: 12,
                  bottom: 16,
                  child: Column(children: [
                    _MapBtn(icon: Icons.add, onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomIn())),
                    const SizedBox(height: 8),
                    _MapBtn(icon: Icons.remove, onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomOut())),
                    const SizedBox(height: 8),
                    _MapBtn(icon: Icons.my_location, onTap: () => _fitAll(markers)),
                  ]),
                ),
              ],
            ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool dot;
  const _ControlRow({required this.icon, required this.label, required this.count, required this.color, this.dot = false});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      ),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Text('$label:', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ]),
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
