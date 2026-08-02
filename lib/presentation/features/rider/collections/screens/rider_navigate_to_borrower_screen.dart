// lib/presentation/features/rider/collections/screens/rider_navigate_to_borrower_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_collection_provider.dart';

class RiderNavigateToBorrowerScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderNavigateToBorrowerScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderNavigateToBorrowerScreen> createState() =>
      _RiderNavigateToBorrowerScreenState();
}

class _RiderNavigateToBorrowerScreenState
    extends ConsumerState<RiderNavigateToBorrowerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
    });
  }

  Future<void> _openGoogleMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
      title: 'Navigate to Borrower',
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
    final schedule = col.loanSchedule as Map<String, dynamic>?;
    final loan = schedule?['loan'] as Map<String, dynamic>?;
    final lender = loan?['lender'] as Map<String, dynamic>?;
    final user = lender?['user'] as Map<String, dynamic>?;
    final addresses = lender?['addresses'] as List? ?? [];
    final borrowerName = user?['full_name'] as String? ?? 'Borrower';

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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
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
              const Icon(Icons.person_outline, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Borrower',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(borrowerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on,
                      color: AppColors.riderGreen, size: 20),
                  SizedBox(width: 8),
                  Text('Destination Address',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                formattedAddress,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary, height: 1.4),
              ),
              if (lat != null && lng != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Coordinates: $lat, $lng',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.riderGreen.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap "Open in Maps" to launch navigation in Google Maps. Your location will be tracked automatically during the assignment.',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (lat != null && lng != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () => _openGoogleMapsDirections(lat!, lng!),
            icon: const Icon(Icons.navigation),
            label: const Text('Open Directions in Maps',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: formattedAddress != 'Address not available'
                ? () => _openGoogleMaps(formattedAddress)
                : null,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Search Address in Maps',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
      ],
    );
  }
}
