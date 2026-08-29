// lib/presentation/features/lender/collections/screens/lender_track_rider_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/realtime_service.dart';
import '../../../../../core/services/route_service.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/map/map_anim_utils.dart';
import '../../../rider/location/widgets/rider_trip_map.dart';
import '../providers/lender_collection_provider.dart';
import '../../../../../core/constants/route_constants.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderTrackRiderScreen extends ConsumerStatefulWidget {
  final String riderId;
  const LenderTrackRiderScreen({super.key, required this.riderId});

  @override
  ConsumerState<LenderTrackRiderScreen> createState() => _State();
}

class _State extends ConsumerState<LenderTrackRiderScreen> {
  Timer? _pollTimer;
  Timer? _lenderGpsTimer;
  bool _isLoading = true;
  String? _error;

  double? _riderLat;
  double? _riderLng;
  double? _riderSpeedKmh;
  double? _destLat;
  double? _destLng;
  String? _destAddress;
  String? _destLabel;
  String? _assignmentType;
  DateTime? _lastUpdated;
  DateTime? _riderUpdatedAt;
  bool _isRiderStale = false;
  double? _lenderLat;
  double? _lenderLng;

  // Dynamic tracking metrics (recalculated on every GPS push)
  double? _distanceKm;
  int? _routeDurationSecs;
  List<LatLng>? _lastRoutePoints;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  bool _fetchingRoute = false;
  void Function()? _realtimeHandler;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _fetchLenderLocation();
    // Real-time: instant push when rider_locations changes (via Supabase Realtime).
    _realtimeHandler = () {
      if (mounted) _fetchLocation();
    };
    // ignore: discarded_futures
    RealtimeService.instance.subscribe('rider_locations', _realtimeHandler!);
    // Fallback polling every 60s (reduced from 30s since realtime is primary)
    _pollTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _fetchLocation());
    _lenderGpsTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _fetchLenderLocation());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lenderGpsTimer?.cancel();
    if (_realtimeHandler != null) {
      RealtimeService.instance.unsubscribe('rider_locations', _realtimeHandler!);
    }
    super.dispose();
  }

  String? _assignmentLabel(String? type) => switch (type) {
        'ci' => 'Credit Investigation',
        'collection' => 'Collection',
        'disbursement' => 'Loan Delivery',
        _ => null,
      };

  /// Reads this device's GPS (the lender's own live position) so the map can
  /// show where the lender is right now, next to the incoming rider's pin.
  Future<void> _fetchLenderLocation() async {
    final pos = await LocationService.instance.getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _lenderLat = pos.latitude;
      _lenderLng = pos.longitude;
    });
  }

  Future<void> _updateRouteIfNeeded() async {
    if (_riderLat == null || _riderLng == null || _destLat == null || _destLng == null) return;
    if (_fetchingRoute) return;
    final origin = LatLng(_riderLat!, _riderLng!);
    final dest = LatLng(_destLat!, _destLng!);
    final originMoved = _lastRouteOrigin == null ||
        (_lastRouteOrigin!.latitude - origin.latitude).abs() > 0.0045 ||
        (_lastRouteOrigin!.longitude - origin.longitude).abs() > 0.0045;
    final destMoved = _lastRouteDest == null ||
        (_lastRouteDest!.latitude - dest.latitude).abs() > 0.0001 ||
        (_lastRouteDest!.longitude - dest.longitude).abs() > 0.0001;
    if (!originMoved && !destMoved && _lastRoutePoints != null) {
      // Keep distance live with haversine until route moves significantly
      final live = haversineKm(origin, dest);
      if (_distanceKm != null && (live - _distanceKm!).abs() < 0.2) return;
    }
    if (!originMoved && !destMoved && _lastRoutePoints != null) return;
    _fetchingRoute = true;
    final result = await RouteService.fetchRoute(origin, dest);
    _fetchingRoute = false;
    if (!mounted) return;
    if (result != null && result.points.isNotEmpty) {
      setState(() {
        _lastRoutePoints = result.points;
        _distanceKm = result.distanceKm;
        _routeDurationSecs = result.durationSecs;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    } else {
      setState(() {
        _distanceKm = haversineKm(origin, dest);
        _routeDurationSecs = null;
        _lastRoutePoints = null;
        _lastRouteOrigin = origin;
        _lastRouteDest = dest;
      });
    }
  }

  Future<void> _fetchLocation() async {
    try {
      final data = await ref
          .read(lenderCollectionProvider.notifier)
          .getRiderLocation(widget.riderId);
      if (!mounted) return;
      final rawLat = (data?['latitude'] as num?)?.toDouble();
      final rawLng = (data?['longitude'] as num?)?.toDouble();
      final dLat = (data?['destination_latitude'] as num?)?.toDouble();
      final dLng = (data?['destination_longitude'] as num?)?.toDouble();
      final rawAddr = data?['destination_address'];
      final destAddress = (rawAddr is String && rawAddr.trim().isNotEmpty &&
              rawAddr.trim() != 'Address not available')
          ? rawAddr.trim()
          : null;

      // Speed: expect m/s*3.6 handling; accept speed_kmh, speed, speed_mps
      double? speedKmh;
      final rawSpeedKmh = (data?['speed_kmh'] as num?)?.toDouble();
      final rawSpeedMps = (data?['speed'] as num?)?.toDouble() ?? (data?['speed_mps'] as num?)?.toDouble();
      if (rawSpeedKmh != null && rawSpeedKmh.isFinite && rawSpeedKmh >= 0 && rawSpeedKmh <= 120) {
        speedKmh = rawSpeedKmh;
      } else if (rawSpeedMps != null && rawSpeedMps.isFinite && rawSpeedMps >= 0 && rawSpeedMps < 70) {
        final kmh = rawSpeedMps * 3.6;
        if (kmh >= 0 && kmh <= 120) speedKmh = kmh;
      }

      // ── Stale detection: rider's GPS is considered OFF if backend says
      // is_stale or if updated_at is older than 120s. In that case we hide
      // the rider pin (set to null) so the map doesn't show a stale ghost.
      final isStaleFlag = data?['is_stale'] == true;
      DateTime? riderUpdatedAt;
      final rawUpdated = data?['updated_at'] ?? data?['location_updated_at'];
      if (rawUpdated is String) riderUpdatedAt = DateTime.tryParse(rawUpdated);
      bool isStale = isStaleFlag;
      if (!isStale && riderUpdatedAt != null) {
        isStale = DateTime.now().difference(riderUpdatedAt).inSeconds > 120;
      }
      // If stale, hide the rider pin entirely — don't show ghost location.
      final lat = isStale ? null : rawLat;
      final lng = isStale ? null : rawLng;
      final wasSamePos = lat == _riderLat && lng == _riderLng && speedKmh == _riderSpeedKmh;
      setState(() {
        _riderLat = lat;
        _riderLng = lng;
        _riderSpeedKmh = speedKmh;
        _destLat = dLat;
        _destLng = dLng;
        _destAddress = destAddress;
        _destLabel = data?['destination_label'] as String?;
        _assignmentType = data?['assignment_type'] as String?;
        _isLoading = false;
        _error = null;
        _lastUpdated = DateTime.now();
        _riderUpdatedAt = riderUpdatedAt;
        _isRiderStale = isStale && rawLat != null;
        // Update distance immediately (haversine) until route arrives
        if (_riderLat != null && _riderLng != null && _destLat != null && _destLng != null) {
          _distanceKm = haversineKm(LatLng(_riderLat!, _riderLng!), LatLng(_destLat!, _destLng!));
        }
      });
      if (!wasSamePos) _updateRouteIfNeeded();
    } catch (e) {
      if (!mounted) return;
      final failure = ErrorHandler.handle(e);
      if (failure is NotFoundFailure) {
        // Rider hasn't shared a live location yet — keep the idle "not
        // available" state and keep listening so it appears automatically via realtime.
        setState(() {
          _isLoading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = failure.message;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildTrackingHeader() {
    final hasRider = _riderLat != null && !_isRiderStale && _destLat != null && _destLng != null;
    String distText = '--';
    String etaText = '--';
    String speedText = formatSpeedKmh(_riderSpeedKmh);
    if (hasRider && _distanceKm != null) {
      distText = formatDistanceKm(_distanceKm!);
      if (_routeDurationSecs != null && _routeDurationSecs! > 0) {
        etaText = formatEtaFromDuration(_routeDurationSecs!);
      } else {
        etaText = formatEta(_distanceKm!, speedKmh: _riderSpeedKmh, fallbackToEstimate: true);
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetricChip(icon: Icons.route_outlined, label: 'Distance', value: distText, color: AppColors.lenderBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MetricChip(icon: Icons.timer_outlined, label: 'ETA', value: hasRider ? 'Arriving in $etaText' : etaText, color: AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MetricChip(icon: Icons.speed, label: 'Speed', value: speedText, color: AppColors.warning),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.lenderBlue),
            SizedBox(height: 16),
            Text('Locating rider...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lenderBlue),
            ),
          ],
        ),
      );
    }

    final hasDestination =
        _destLat != null && _destLng != null ||
            (_destAddress != null && _destAddress!.isNotEmpty);
    final hasRiderLocation =
        _riderLat != null && _riderLng != null && !_isRiderStale;

    if (!hasDestination && !hasRiderLocation) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('Rider location not available yet',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 15)),
            SizedBox(height: 6),
            Text('The rider may not have started the trip.',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 13)),
          ],
        ),
      );
    }

    final destSnippet = (_destLabel?.isNotEmpty ?? false)
        ? _destLabel!
        : 'Your address';

    // Rider GPS off / stale: show map with destination + lender only,
    // with a banner explaining why the rider pin is hidden.
    if (!hasRiderLocation) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _isRiderStale
                    ? AppColors.warning.withValues(alpha: 0.12)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isRiderStale
                      ? AppColors.warning.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isRiderStale ? Icons.location_off : Icons.location_searching,
                    size: 18,
                    color: _isRiderStale ? AppColors.warning : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRiderStale
                          ? 'Rider GPS is paused (last update ${_riderUpdatedAt != null ? "${_riderUpdatedAt!.hour}:${_riderUpdatedAt!.minute.toString().padLeft(2, '0')}" : "a while ago"}). Pin is hidden until they move again.'
                          : 'Waiting for rider to start sharing location. Their pin will appear once GPS is on.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isRiderStale ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildTrackingHeader(),
            const SizedBox(height: 8),
            Expanded(
              child: RiderTripMap(
                originLat: null,
                originLng: null,
                originTitle: 'Rider',
                originSnippet: 'Live location',
                originHue: BitmapDescriptor.hueViolet,
                destinationLat: _destLat,
                destinationLng: _destLng,
                destinationTitle: 'Your Location',
                destinationSnippet: destSnippet,
                destinationAddress: _destAddress,
                lenderLat: _lenderLat,
                lenderLng: _lenderLng,
                lenderTitle: 'You (Lender)',
                lenderSnippet: 'Your live GPS',
                lenderHue: BitmapDescriptor.hueBlue,
                height: double.infinity,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          _buildTrackingHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: RiderTripMap(
              originLat: _riderLat,
              originLng: _riderLng,
              originTitle: 'Rider',
              originSnippet: 'Live location',
              originHue: BitmapDescriptor.hueViolet,
              destinationLat: _destLat,
              destinationLng: _destLng,
              destinationTitle: 'Your Location',
              destinationSnippet: destSnippet,
              destinationAddress: _destAddress,
              lenderLat: _lenderLat,
              lenderLng: _lenderLng,
              lenderTitle: 'You (Lender)',
              lenderSnippet: 'Your live GPS',
              lenderHue: BitmapDescriptor.hueBlue,
              height: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignmentLabel = _assignmentLabel(_assignmentType);

    return MobileScaffold(
      title: 'Track Rider',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      appBarActions: [
        IconButton(
          onPressed: _fetchLocation,
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          if (_lastUpdated != null && !_isLoading)
            Builder(builder: (context) {
              final hasRider = _riderLat != null && !_isRiderStale;
              final Color dotColor = !hasRider
                  ? (_isRiderStale ? AppColors.warning : AppColors.textTertiary)
                  : AppColors.success;
              final String statusLabel = !hasRider
                  ? (_isRiderStale ? 'GPS paused' : 'Waiting for GPS')
                  : 'Live';
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: hasRider
                    ? AppColors.lenderBlue.withValues(alpha: 0.1)
                    : dotColor.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: dotColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$statusLabel · ${assignmentLabel ?? 'Tracking'} — Last updated: ${_lastUpdated!.hour}:${_lastUpdated!.minute.toString().padLeft(2, '0')} · Live via Realtime',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          Expanded(child: _buildBody()),
          if (!_isLoading &&
              _error == null &&
              (_riderLat != null || (_destLat != null && _destLng != null)))
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 8),
              child: RiderMapLegend(
                originLabel: 'Rider',
                destinationLabel: 'Your Location',
                originColor: Colors.purple,
                extraLabel: 'Your live GPS',
                extraColor: Colors.blueAccent,
              ),
            ),
          if (_error == null && !_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    assignmentLabel == 'Credit Investigation'
                        ? Icons.search_outlined
                        : assignmentLabel == 'Loan Delivery'
                            ? Icons.delivery_dining_outlined
                            : Icons.monetization_on_outlined,
                    size: 20,
                    color: AppColors.lenderBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      assignmentLabel == null
                          ? 'Live tracking of your assigned rider.'
                          : '$assignmentLabel rider on the way to your address.',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MetricChip({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}