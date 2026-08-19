// lib/presentation/features/rider/collections/screens/rider_navigate_to_borrower_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_collection_provider.dart';
import '../../location/providers/rider_location_provider.dart';
import '../../location/widgets/rider_trip_map.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderNavigateToBorrowerScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderNavigateToBorrowerScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderNavigateToBorrowerScreen> createState() =>
      _RiderNavigateToBorrowerScreenState();
}

class _RiderNavigateToBorrowerScreenState
    extends ConsumerState<RiderNavigateToBorrowerScreen> {
  double? _destLat;
  double? _destLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
      ref.read(riderLocationProvider.notifier).startTracking();
    });
  }

  @override
  void dispose() {
    ref.read(riderLocationProvider.notifier).stopTracking();
    super.dispose();
  }

  Future<void> _openGoogleMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        context.showSnackBarAsToast(
          const SnackBar(
              content: Text('Could not open Google Maps'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _openGoogleMapsDirections(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    return MobileScaffold(
      title: 'Navigate to Lender',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: col == null
          ? state.isLoading
              ? const ShimmerLoader()
              : const Center(child: Text('Collection not found'))
          : _buildContent(col),
    );
  }

  Widget _buildContent(dynamic col) {
    final addresses = col.lenderAddresses as List? ?? [];
    final borrowerName =
        (col.lenderName as String).isEmpty ? 'Lender' : col.lenderName;

    final homeAddr = addresses.firstWhere(
      (a) => (a as Map)['address_type'] == 'home',
      orElse: () => addresses.isNotEmpty ? addresses.first : null,
    );

    String formattedAddress = 'Address not available';
    double? lat;
    double? lng;

    if (homeAddr != null) {
      final a = homeAddr as Map<String, dynamic>;
      lat = (a['latitude'] as num?)?.toDouble();
      lng = (a['longitude'] as num?)?.toDouble();
      formattedAddress = [
        a['street'],
        a['barangay'],
        a['city'],
        a['province'],
      ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
    }

    final destLat = _destLat ?? lat;
    final destLng = _destLng ?? lng;
    final canDirections = destLat != null && destLng != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _HeaderCard(name: borrowerName),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: RiderTripMap(
              destinationLat: lat,
              destinationLng: lng,
              destinationTitle: 'Lender Location',
              destinationSnippet: formattedAddress == 'Address not available'
                  ? 'Destination'
                  : formattedAddress,
              destinationAddress: formattedAddress == 'Address not available'
                  ? null
                  : formattedAddress,
              height: double.infinity,
              onDestinationResolved: (rLat, rLng) {
                if (_destLat != rLat || _destLng != rLng) {
                  setState(() {
                    _destLat = rLat;
                    _destLng = rLng;
                  });
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _BottomCard(
            address: formattedAddress,
            canDirections: canDirections,
            onDirections: canDirections
                ? () => _openGoogleMapsDirections(destLat, destLng)
                : null,
            onSearch: formattedAddress != 'Address not available'
                ? () => _openGoogleMaps(formattedAddress)
                : null,
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String name;
  const _HeaderCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreenDark, AppColors.riderGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lender',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  final String address;
  final bool canDirections;
  final VoidCallback? onDirections;
  final VoidCallback? onSearch;
  const _BottomCard({
    required this.address,
    required this.canDirections,
    required this.onDirections,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Text('Destination Address',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            address,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary, height: 1.4),
          ),
          const SizedBox(height: 12),
          const RiderMapLegend(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.riderGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: canDirections ? onDirections : onSearch,
              icon: Icon(
                  canDirections ? Icons.navigation : Icons.map_outlined,
                  size: 20),
              label: Text(
                canDirections
                    ? 'Open Directions in Maps'
                    : 'Search Address in Maps',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
