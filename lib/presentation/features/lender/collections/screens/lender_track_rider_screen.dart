// lib/presentation/features/lender/collections/screens/lender_track_rider_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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
  GoogleMapController? _mapController;
  LatLng? _riderLocation;
  Timer? _pollTimer;
  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetchLocation());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final data = await ref
          .read(lenderCollectionProvider.notifier)
          .getRiderLocation(widget.riderId);
      if (data != null && mounted) {
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final loc = LatLng(lat, lng);
          setState(() {
            _riderLocation = loc;
            _isLoading = false;
            _lastUpdated = DateTime.now();
          });
          _mapController?.animateCamera(CameraUpdate.newLatLng(loc));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to fetch rider location.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Track Rider',
      accentColor: AppColors.lenderPurple,
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
          if (_lastUpdated != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.lenderPurple.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Last updated: ${_lastUpdated!.hour}:${_lastUpdated!.minute.toString().padLeft(2, '0')} — Auto-refreshes every 30s',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                            color: AppColors.lenderPurple),
                        SizedBox(height: 16),
                        Text('Locating rider...',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_off,
                                size: 64, color: AppColors.textTertiary),
                            const SizedBox(height: 16),
                            Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _fetchLocation,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.lenderPurple),
                            ),
                          ],
                        ),
                      )
                    : _riderLocation == null
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delivery_dining,
                                    size: 64, color: AppColors.textTertiary),
                                SizedBox(height: 12),
                                Text('Rider location not available yet',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 15)),
                                SizedBox(height: 6),
                                Text('The rider may not have started the trip.',
                                    style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 13)),
                              ],
                            ),
                          )
                        : GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _riderLocation!,
                              zoom: 15,
                            ),
                            onMapCreated: (c) => _mapController = c,
                            markers: {
                              Marker(
                                markerId: const MarkerId('rider'),
                                position: _riderLocation!,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueViolet),
                                infoWindow: const InfoWindow(
                                  title: 'Rider Location',
                                  snippet: 'Your assigned collection rider',
                                ),
                              ),
                            },
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            zoomControlsEnabled: false,
                          ),
          ),
          if (_riderLocation != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.lenderPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.delivery_dining,
                        color: AppColors.lenderPurple),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your rider is on the way',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        SizedBox(height: 2),
                        Text('Location updates every 30 seconds',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
