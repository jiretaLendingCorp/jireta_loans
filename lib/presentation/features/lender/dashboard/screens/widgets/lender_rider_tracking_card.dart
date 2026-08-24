// lib/presentation/features/lender/dashboard/screens/widgets/lender_rider_tracking_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../../../core/constants/route_constants.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../data/models/tracked_rider_model.dart';
import '../../providers/lender_rider_tracking_provider.dart';

/// Live rider tracking section for the lender home screen.
///
/// Renders only while the lender has riders with ACCEPTED (or in-flight)
/// assignments on their loans (collection / delivery / credit investigation).
/// A collection disappears as soon as the rider records it (amount taken from
/// the lender); the embedded map + per-rider status list stay live via
/// realtime (`rider_locations` pushes every ~30s; assignment accept/completion
/// appears and disappears automatically).
class LenderRiderTrackingCard extends ConsumerStatefulWidget {
  const LenderRiderTrackingCard({super.key});

  @override
  ConsumerState<LenderRiderTrackingCard> createState() =>
      _LenderRiderTrackingCardState();
}

class _LenderRiderTrackingCardState
    extends ConsumerState<LenderRiderTrackingCard> {
  GoogleMapController? _mapController;
  bool _didInitialFit = false;

  @override
  void dispose() {
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

  /// One marker per rider, deduplicated across assignment rows.
  /// Stale locations (GPS off >120s) are filtered — no pin is drawn, the
  /// rider appears as "Location paused" / "Waiting" in the list.
  Set<Marker> _buildMarkers(List<TrackedRiderModel> riders) {
    final markers = <Marker>{};
    final seen = <String>{};
    for (final rider in riders) {
      if (!rider.hasLocation || rider.isStale || seen.contains(rider.riderId)) continue;
      seen.add(rider.riderId);
      markers.add(
        Marker(
          markerId: MarkerId('rider-${rider.riderId}'),
          position: LatLng(rider.latitude!, rider.longitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(rider.assignmentType)),
          infoWindow: InfoWindow(
            title: rider.riderName.isEmpty ? 'Rider' : rider.riderName,
            snippet: '${_typeLabel(rider.assignmentType)} · ${rider.loanNumber}',
          ),
          onTap: () => _openRider(rider.riderId),
        ),
      );
    }
    return markers;
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

    final markers = _buildMarkers(riders);
    final hasLiveMarkers = markers.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Live Rider Tracking',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasLiveMarkers)
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
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    compassEnabled: true,
                  ),
                ),
              if (!hasLiveMarkers)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surfaceVariant,
                  child: const Row(
                    children: [
                      Icon(Icons.location_searching,
                          color: AppColors.textTertiary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your rider is preparing their trip. Location will appear here once they start moving.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasLiveMarkers)
                const Divider(height: 1, color: AppColors.divider),
              ...riders.map(
                (rider) => _RiderStatusTile(
                  rider: rider,
                  icon: _typeIcon(rider.assignmentType),
                  color: _typeColor(rider.assignmentType),
                  typeLabel: _typeLabel(rider.assignmentType),
                  relativeTime: _relativeTime(rider.locationUpdatedAt),
                  onTap: () => _openRider(rider.riderId),
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

  const _RiderStatusTile({
    required this.rider,
    required this.icon,
    required this.color,
    required this.typeLabel,
    required this.relativeTime,
    required this.onTap,
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
      dotLabel = 'On the move';
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relativeTime,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
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
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        dotLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: dotColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}