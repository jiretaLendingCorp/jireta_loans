// lib/presentation/features/rider/dashboard/screens/widgets/rider_live_tracking_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:go_router/go_router.dart';
import '../../../../../../core/constants/route_constants.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../shared/widgets/map/live_map_header.dart';
import '../../../../../shared/widgets/map/map_anim_utils.dart';
import '../../../location/providers/rider_location_provider.dart';

/// Embedded **Live Map Tracking with Animated Marker** for the Rider Home.
///
/// Shows the rider's own real-time GPS position on an embedded map.
/// The marker animates smoothly between fixes (interpolated over ~1.8s)
/// instead of teleporting, with a pulsing halo, bearing rotation, and
/// auto-follow camera. Visible directly on the rider's home dashboard.
///
/// Data sources:
///  - `riderLocationProvider` → pushes GPS every ~30s (and on-device stream)
///  - `riderDashboardProvider` → task count for the subtitle
class RiderLiveTrackingCard extends ConsumerStatefulWidget {
  const RiderLiveTrackingCard({super.key});

  @override
  ConsumerState<RiderLiveTrackingCard> createState() => _RiderLiveTrackingCardState();
}

class _RiderLiveTrackingCardState extends ConsumerState<RiderLiveTrackingCard>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _didInitialFit = false;
  bool _followRider = true;
  bool _isAutoMoving = false;

  // ── Animated marker ────────────────────────────────────────
  late final AnimationController _markerCtrl;
  late final AnimationController _pulseCtrl;
  LatLng? _displayPos;
  LatLng? _animStart;
  LatLng? _animTarget;
  double _bearing = 0;

  static const _phCenter = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _markerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addListener(_onMarkerTick);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Auto-start tracking when the card appears so the live map is active
    // immediately on the home screen. Guarded — does nothing if already
    // tracking or if the user is not a rider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final locState = ref.read(riderLocationProvider);
      if (!locState.isTracking) {
        ref.read(riderLocationProvider.notifier).startTracking();
      } else if (locState.lastLat != null && locState.lastLng != null) {
        // Already has a fix — place marker instantly.
        _displayPos = LatLng(locState.lastLat!, locState.lastLng!);
        _animStart = _displayPos;
        _animTarget = _displayPos;
        if (mounted) setState(() {});
        _fitToDisplay();
      }
    });
  }

  void _onMarkerTick() {
    final start = _animStart;
    final target = _animTarget;
    if (start == null || target == null) return;
    final t = easeInOutCubic(_markerCtrl.value);
    _displayPos = lerpLatLng(start, target, t);
    if (_followRider && _mapController != null && _didInitialFit) {
      // Smooth follow: move camera with the marker each frame.
      // Use moveCamera (no animation) so the map glides frame-by-frame.
      _isAutoMoving = true;
      _mapController!.moveCamera(CameraUpdate.newLatLng(_displayPos!));
    }
    if (mounted) setState(() {});
  }

  void _handleLocationUpdate(double? lat, double? lng) {
    if (lat == null || lng == null) return;
    final newPos = LatLng(lat, lng);
    if (_displayPos == null) {
      // First fix — place directly.
      _displayPos = newPos;
      _animStart = newPos;
      _animTarget = newPos;
      if (mounted) setState(() {});
      _fitToDisplay();
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
    _markerCtrl.forward(from: 0);
    // If following and no animation in progress for camera, kick a camera
    // animation toward the target so the map stays centered.
    if (_followRider && _mapController != null && _didInitialFit) {
      // The per-tick moveCamera will keep it glued; also animate zoom level.
    }
  }

  Future<void> _fitToDisplay() async {
    final ctrl = _mapController;
    final pos = _displayPos;
    if (ctrl == null || pos == null) return;
    if (!_didInitialFit) {
      _didInitialFit = true;
      _isAutoMoving = true;
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
      _isAutoMoving = false;
    }
  }

  void _recenter() {
    final pos = _displayPos;
    final ctrl = _mapController;
    if (pos == null || ctrl == null) return;
    _followRider = true;
    _isAutoMoving = true;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  void _zoomIn() => _mapController?.animateCamera(CameraUpdate.zoomIn());
  void _zoomOut() => _mapController?.animateCamera(CameraUpdate.zoomOut());

  @override
  void dispose() {
    _markerCtrl.removeListener(_onMarkerTick);
    _markerCtrl.dispose();
    _pulseCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locState = ref.watch(riderLocationProvider);

    // React to location changes — animate marker smoothly.
    ref.listen(riderLocationProvider, (prev, next) {
      if (!mounted) return;
      final lat = next.lastLat;
      final lng = next.lastLng;
      // Only animate if position actually moved beyond noise.
      if (lat == null || lng == null) return;
      if (prev?.lastLat == lat && prev?.lastLng == lng) return;
      _handleLocationUpdate(lat, lng);
    });

    // Also handle initial displayPos sync if provider already has a fix but
    // we haven't placed the marker yet (e.g. hot-restart).
    if (_displayPos == null && locState.lastLat != null && locState.lastLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _displayPos != null) return;
        _displayPos = LatLng(locState.lastLat!, locState.lastLng!);
        _animStart = _displayPos;
        _animTarget = _displayPos;
        setState(() {});
        _fitToDisplay();
      });
    }

    final hasFix = _displayPos != null;
    final String? subtitle =
        (!hasFix && locState.error != null) ? locState.error : null;

    final isLive = hasFix && locState.isTracking && locState.error == null;

    final markers = <Marker>{};
    final circles = <Circle>{};
    if (hasFix) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider_live'),
          position: _displayPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          rotation: _bearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'You', snippet: ''),
        ),
      );
      circles.add(
        Circle(
          circleId: const CircleId('rider_halo'),
          center: _displayPos!,
          radius: 26,
          strokeWidth: 1,
          strokeColor: AppColors.riderGreen.withValues(alpha: 0.22),
          fillColor: AppColors.riderGreen.withValues(alpha: 0.07),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiveMapHeader(
          title: 'Live Map Tracking',
          subtitle: subtitle,
          accentColor: AppColors.riderGreen,
          isLive: isLive,
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
            children: [
              // ── Map ───────────────────────────────────────
              SizedBox(
                height: 220,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _displayPos ?? _phCenter,
                        zoom: hasFix ? 16 : 12,
                      ),
                      onMapCreated: (c) {
                        _mapController = c;
                        if (hasFix) _fitToDisplay();
                      },
                      onCameraMoveStarted: () {
                        if (!_isAutoMoving) _followRider = false;
                      },
                      onCameraIdle: () => _isAutoMoving = false,
                      markers: markers,
                      circles: circles,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: true,
                      mapToolbarEnabled: false,
                    ),
                    if (!hasFix)
                      Positioned.fill(
                        child: Container(
                          color: AppColors.surfaceVariant.withValues(alpha: 0.85),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (locState.error != null)
                                    const Icon(Icons.location_off, size: 36, color: AppColors.textTertiary)
                                  else
                                    const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.riderGreen),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    locState.error ?? 'Locating you…',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                  if (locState.error != null) ...[
                                    const SizedBox(height: 10),
                                    FilledButton.icon(
                                      onPressed: () =>
                                          ref.read(riderLocationProvider.notifier).startTracking(),
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Retry'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.riderGreen,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Live chip top-left
                    if (hasFix)
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
                              Text(
                                _followRider ? 'Following' : 'Live',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              if (!_followRider) ...[
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: _recenter,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.riderGreen,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text('Recenter',
                                        style: TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    // Map controls
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MapIconButton(icon: Icons.add, onTap: _zoomIn),
                          const SizedBox(height: 8),
                          _MapIconButton(icon: Icons.remove, onTap: _zoomOut),
                          const SizedBox(height: 8),
                          _MapIconButton(
                            icon: Icons.my_location,
                            color: _followRider ? AppColors.riderGreen : Colors.black87,
                            onTap: _recenter,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Footer strip ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.riderGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delivery_dining, size: 16, color: AppColors.riderGreen),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasFix ? 'You are here' : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            hasFix
                                ? '${_displayPos!.latitude.toStringAsFixed(5)}, ${_displayPos!.longitude.toStringAsFixed(5)}'
                                : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLive ? AppColors.successLight : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isLive
                                ? AppColors.success.withValues(alpha: 0.3)
                                : AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isLive ? AppColors.success : AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isLive ? 'Live' : 'Paused',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isLive ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push(RouteConstants.riderLiveTracking),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 16, color: AppColors.riderGreen),
                        SizedBox(width: 6),
                        Text('View Full Live Tracking',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.riderGreen)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 14, color: AppColors.riderGreen),
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

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _MapIconButton({required this.icon, required this.onTap, this.color = Colors.black87});

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
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
