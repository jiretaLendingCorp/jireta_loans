// lib/presentation/features/lender/collections/screens/lender_track_rider_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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
  double? _destLat;
  double? _destLng;
  String? _destAddress;
  String? _destLabel;
  String? _assignmentType;
  DateTime? _lastUpdated;
  double? _lenderLat;
  double? _lenderLng;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _fetchLenderLocation();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetchLocation());
    _lenderGpsTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _fetchLenderLocation());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lenderGpsTimer?.cancel();
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

  Future<void> _fetchLocation() async {
    try {
      final data = await ref
          .read(lenderCollectionProvider.notifier)
          .getRiderLocation(widget.riderId);
      if (!mounted) return;
      final lat = (data?['latitude'] as num?)?.toDouble();
      final lng = (data?['longitude'] as num?)?.toDouble();
      final dLat = (data?['destination_latitude'] as num?)?.toDouble();
      final dLng = (data?['destination_longitude'] as num?)?.toDouble();
      final rawAddr = data?['destination_address'];
      final destAddress = (rawAddr is String && rawAddr.trim().isNotEmpty &&
              rawAddr.trim() != 'Address not available')
          ? rawAddr.trim()
          : null;
      setState(() {
        _riderLat = lat;
        _riderLng = lng;
        _destLat = dLat;
        _destLng = dLng;
        _destAddress = destAddress;
        _destLabel = data?['destination_label'] as String?;
        _assignmentType = data?['assignment_type'] as String?;
        _isLoading = false;
        _error = null;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      final failure = ErrorHandler.handle(e);
      if (failure is NotFoundFailure) {
        // Rider hasn't shared a live location yet — keep the idle "not
        // available" state and keep polling so it appears automatically.
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

    if (!hasDestination) {
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.lenderBlue.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${assignmentLabel ?? 'Tracking'} — Last updated: ${_lastUpdated!.hour}:${_lastUpdated!.minute.toString().padLeft(2, '0')} · Auto-refreshes every 30s',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
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