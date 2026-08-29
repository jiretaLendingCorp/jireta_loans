// lib/presentation/features/lender/dashboard/screens/widgets/lender_rider_tracking_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../../../core/constants/route_constants.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../data/models/tracked_rider_model.dart';
import '../../../../../shared/widgets/map/live_map_header.dart';
import '../../../../../shared/widgets/map/map_anim_utils.dart';
import '../../providers/lender_rider_tracking_provider.dart';

/// Live rider tracking section for the lender home screen.
///
/// **Live Map Tracking with Animated Marker** — Embedded Map + Real-Time
/// Location + Animated Moving Marker. The lender sees every rider currently
/// assigned to their loans (collection / delivery / CI) moving live on an
/// embedded map. Markers animate smoothly between GPS fixes instead of
/// teleporting, with a pulsing halo and bearing rotation.
///
/// Renders only while the lender has riders with ACCEPTED (or in-flight)
/// assignments on their loans. A collection disappears as soon as the rider
/// records it; the embedded map + per-rider status list stay live via
/// realtime (`rider_locations` pushes every ~30s; assignment changes appear
/// / disappear automatically).
class LenderRiderTrackingCard extends ConsumerStatefulWidget {
  const LenderRiderTrackingCard({super.key});

  @override
  ConsumerState<LenderRiderTrackingCard> createState() =>
      _LenderRiderTrackingCardState();
}

class _LenderRiderTrackingCardState extends ConsumerState<LenderRiderTrackingCard>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _didInitialFit = false;

  // ── Animated marker state ──────────────────────────────────
  late final AnimationController _animCtrl;
  final Map<String, LatLng> _displayPositions = {};
  final Map<String, LatLng> _animStarts = {};
  final Map<String, LatLng> _animTargets = {};
  final Map<String, double> _bearings = {};
  // pulse for halo
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addListener(_onAnimTick);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  void _onAnimTick() {
    final t = easeInOutCubic(_animCtrl.value);
    var needsRebuild = false;
    for (final id in _animTargets.keys) {
      final start = _animStarts[id];
      final target = _animTargets[id];
      if (start == null || target == null) continue;
      _displayPositions[id] = lerpLatLng(start, target, t);
      needsRebuild = true;
    }
    if (needsRebuild && mounted) setState(() {});
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_onAnimTick);
    _animCtrl.dispose();
    _pulseCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  double _hueFor(String type) => switch (type) {
        'disbursement' => BitmapDescriptor.hueGreen,
        'ci' => BitmapDescriptor.hueOrange,
        _ => BitmapDescriptor.hueViolet,
      };

  String _typeLabel(String type) => switch (type) {
        'disbursement' => 'Loan Delivery',
        'ci' => 'Credit Investigation',
        _ => 'Collection',
      };

  IconData _typeIcon(String type) => switch (type) {
        'disbursement' => Icons.delivery_dining_outlined,
        'ci' => Icons.search_outlined,
        _ => Icons.monetization_on_outlined,
      };

  Color _typeColor(String type) => switch (type) {
        'disbursement' => AppColors.riderGreen,
        'ci' => AppColors.warning,
        _ => AppColors.lenderBlue,
      };

  void _maybeUpdateTargets(List<TrackedRiderModel> riders) {
    final activeIds = <String>{};
    for (final rider in riders) {
      if (!rider.hasLocation || rider.isStale) continue;
      activeIds.add(rider.riderId);
      final newPos = LatLng(rider.latitude!, rider.longitude!);
      final existingTarget = _animTargets[rider.riderId];
      // First time: place directly, no animation.
      if (!_displayPositions.containsKey(rider.riderId)) {
        _displayPositions[rider.riderId] = newPos;
        _animStarts[rider.riderId] = newPos;
        _animTargets[rider.riderId] = newPos;
        _bearings[rider.riderId] = 0;
        continue;
      }
      // Same target — nothing to do.
      if (existingTarget != null &&
          (existingTarget.latitude - newPos.latitude).abs() < 0.00001 &&
          (existingTarget.longitude - newPos.longitude).abs() < 0.00001) {
        continue;
      }
      // New target — animate from current displayed position.
      final start = _displayPositions[rider.riderId]!;
      _animStarts[rider.riderId] = start;
      _animTargets[rider.riderId] = newPos;
      _bearings[rider.riderId] = bearingBetween(start, newPos);
      _animCtrl.forward(from: 0);
    }
    // Remove riders who are no longer live (stale / removed assignment).
    final toRemove =
        _displayPositions.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in toRemove) {
      _displayPositions.remove(id);
      _animStarts.remove(id);
      _animTargets.remove(id);
      _bearings.remove(id);
    }
  }

  Set<Marker> _buildMarkers(List<TrackedRiderModel> riders) {
    final markers = <Marker>{};
    final seen = <String>{};
    // Map riderId -> model for label lookup
    final byId = <String, TrackedRiderModel>{};
    for (final r in riders) {
      if (!byId.containsKey(r.riderId)) byId[r.riderId] = r;
    }
    for (final rider in riders) {
      if (!rider.hasLocation || rider.isStale || seen.contains(rider.riderId)) {
        continue;
      }
      seen.add(rider.riderId);
      final displayPos = _displayPositions[rider.riderId] ??
          LatLng(rider.latitude!, rider.longitude!);
      final bearing = _bearings[rider.riderId] ?? 0;
      markers.add(
        Marker(
          markerId: MarkerId('rider-${rider.riderId}'),
          position: displayPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(rider.assignmentType)),
          // Rotation gives the "moving" feel; anchor centers the icon.
          rotation: bearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: rider.riderName.isEmpty ? 'Rider' : rider.riderName,
            snippet: '${_typeLabel(rider.assignmentType)} · ${rider.loanNumber}',
          ),
          onTap: () => _openRider(rider.riderId),
        ),
      );
      // Keep lookup for deduplication — only one marker per rider.
      byId[rider.riderId] = rider;
    }
    return markers;
  }

  Set<Circle> _buildPulseCircles() {
    final circles = <Circle>{};
    for (final entry in _displayPositions.entries) {
      circles.add(
        Circle(
          circleId: CircleId('pulse-${entry.key}'),
          center: entry.value,
          radius: 22,
          strokeWidth: 1,
          strokeColor: AppColors.lenderBlue.withValues(alpha: 0.25),
          fillColor: AppColors.lenderBlue.withValues(alpha: 0.08),
        ),
      );
    }
    return circles;
  }

  Future<void> _fitCameraToMarkers(Set<Marker> markers) async {
    final controller = _mapController;
    if (controller == null || markers.isEmpty) return;
    final points = markers.map((m) => m.position).toList();
    if (points.length == 1) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
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
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  void _openRider(String riderId) {
    context.push(RouteConstants.lenderTrackRider.replaceFirst(':id', riderId));
  }

  String _relativeTime(DateTime? updated) {
    if (updated == null) return 'Waiting for location';
    final diff = DateTime.now().difference(updated);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${updated.hour}:${updated.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderRiderTrackingProvider);
    final riders = state.riders;
    if (riders.isEmpty) return const SizedBox.shrink();

    // Sync animated positions with new data (triggers smooth tween).
    // Use post-frame to avoid setState during build for the initial placement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final beforeCount = _displayPositions.length;
      _maybeUpdateTargets(riders);
      // If first load introduced positions, we need a rebuild.
      if (_displayPositions.length != beforeCount && mounted) setState(() {});
    });
    // Also ensure first frame has positions for marker build (fallback).
    if (_displayPositions.isEmpty) {
      for (final r in riders) {
        if (r.hasLocation && !r.isStale && !_displayPositions.containsKey(r.riderId)) {
          _displayPositions[r.riderId] = LatLng(r.latitude!, r.longitude!);
          _animTargets[r.riderId] = LatLng(r.latitude!, r.longitude!);
          _animStarts[r.riderId] = LatLng(r.latitude!, r.longitude!);
        }
      }
    }

    final markers = _buildMarkers(riders);
    final circles = _buildPulseCircles();
    final hasLiveMarkers = markers.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        LiveMapHeader(
          title: 'Live Rider Tracking',
          subtitle: hasLiveMarkers
              ? '${markers.length} rider${markers.length == 1 ? '' : 's'} on the move · Embedded live map'
              : 'Waiting for rider to share location',
          accentColor: AppColors.lenderBlue,
          isLive: hasLiveMarkers,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasLiveMarkers)
                Stack(
                  children: [
                    SizedBox(
                      height: 210,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: markers.first.position,
                          zoom: 15,
                        ),
                        onMapCreated: (controller) {
                          _mapController = controller;
                          if (!_didInitialFit && markers.isNotEmpty) {
                            _didInitialFit = true;
                            _fitCameraToMarkers(markers);
                          }
                        },
                        markers: markers,
                        circles: circles,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: true,
                        mapToolbarEnabled: false,
                      ),
                    ),
                    // Top live chip
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (_, __) {
                                final s = 0.85 + 0.25 * _pulseCtrl.value;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Opacity(
                                      opacity: (1 - _pulseCtrl.value) * 0.45,
                                      child: Container(
                                        width: 10 * s,
                                        height: 10 * s,
                                        decoration: const BoxDecoration(
                                            color: AppColors.success, shape: BoxShape.circle),
                                      ),
                                    ),
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                          color: AppColors.success, shape: BoxShape.circle),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            const Text('Live tracking',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ),
                    // Recenter button
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GestureDetector(
                        onTap: () => _fitCameraToMarkers(markers),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                          child: const Icon(Icons.center_focus_strong, size: 18, color: AppColors.lenderBlue),
                        ),
                      ),
                    ),
                  ],
                ),
              if (!hasLiveMarkers)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surfaceVariant,
                  child: const Row(
                    children: [
                      Icon(Icons.location_searching, color: AppColors.textTertiary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your rider is preparing their trip. Location will appear here once they start moving.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasLiveMarkers) const Divider(height: 1, color: AppColors.divider),
              ...riders.map(
                (rider) => _RiderStatusTile(
                  rider: rider,
                  icon: _typeIcon(rider.assignmentType),
                  color: _typeColor(rider.assignmentType),
                  typeLabel: _typeLabel(rider.assignmentType),
                  relativeTime: _relativeTime(rider.locationUpdatedAt),
                  onTap: () => _openRider(rider.riderId),
                  isMoving: !rider.isStale && rider.hasLocation && _animCtrl.isAnimating,
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push(RouteConstants.lenderLiveTracking),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 16, color: AppColors.lenderBlue),
                        SizedBox(width: 6),
                        Text('View Full Live Tracking',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.lenderBlue)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 14, color: AppColors.lenderBlue),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiderStatusTile extends StatelessWidget {
  final TrackedRiderModel rider;
  final IconData icon;
  final Color color;
  final String typeLabel;
  final String relativeTime;
  final VoidCallback onTap;
  final bool isMoving;

  const _RiderStatusTile({
    required this.rider,
    required this.icon,
    required this.color,
    required this.typeLabel,
    required this.relativeTime,
    required this.onTap,
    this.isMoving = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final String dotLabel;
    if (!rider.hasLocation) {
      dotColor = AppColors.textTertiary;
      dotLabel = 'Waiting';
    } else if (rider.isStale) {
      dotColor = AppColors.warning;
      dotLabel = 'Location paused';
    } else {
      dotColor = AppColors.success;
      dotLabel = isMoving ? 'Moving' : 'On the move';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rider.riderName.isEmpty ? 'Rider' : rider.riderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$typeLabel · Loan #${rider.loanNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relativeTime,
                      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        dotLabel,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: dotColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
