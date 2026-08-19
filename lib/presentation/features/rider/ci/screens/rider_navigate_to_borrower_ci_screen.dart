// lib/presentation/features/rider/ci/screens/rider_navigate_to_borrower_ci_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_ci_provider.dart';
import '../../location/providers/rider_location_provider.dart';
import '../../location/widgets/rider_trip_map.dart';

class RiderNavigateToBorrowerCiScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderNavigateToBorrowerCiScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderNavigateToBorrowerCiScreen> createState() =>
      _RiderNavigateToBorrowerCiScreenState();
}

class _RiderNavigateToBorrowerCiScreenState
    extends ConsumerState<RiderNavigateToBorrowerCiScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
      ref.read(riderLocationProvider.notifier).startTracking();
    });
  }

  @override
  void dispose() {
    ref.read(riderLocationProvider.notifier).stopTracking();
    super.dispose();
  }

  Future<void> _openDirections(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);
    final ci = state.selectedCi;

    return MobileScaffold(
      title: 'Navigate for CI',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: ci == null
          ? state.isLoading
              ? const ShimmerLoader()
              : const Center(child: Text('CI not found'))
          : _buildContent(ci),
    );
  }

  Widget _buildContent(dynamic ci) {
    final loan = ci.loan as Map<String, dynamic>?;
    final lender = loan?['lender_profile'] as Map<String, dynamic>?;
    final user = lender?['users'] as Map<String, dynamic>?;
    final composedName =
        '${user?['first_name'] ?? ''} ${user?['last_name'] ?? ''}'.trim();
    final borrowerName = (loan?['lender_name'] as String?) ??
        (composedName.isEmpty ? 'Lender' : composedName);
    final addresses = (lender?['users'] as Map<String, dynamic>?)?['addresses']
            as List? ??
        [];

    Map<String, dynamic>? firstAddressWithCoords;
    for (final addr in addresses.whereType<Map<String, dynamic>>()) {
      final aLat = (addr['latitude'] as num?)?.toDouble();
      final aLng = (addr['longitude'] as num?)?.toDouble();
      if (aLat != null && aLng != null) {
        firstAddressWithCoords = addr;
        break;
      }
    }
    final mapLat = (firstAddressWithCoords?['latitude'] as num?)?.toDouble();
    final mapLng = (firstAddressWithCoords?['longitude'] as num?)?.toDouble();
    final mapLabel = firstAddressWithCoords == null
        ? 'Lender Location'
        : [
            firstAddressWithCoords['street'],
            firstAddressWithCoords['barangay'],
            firstAddressWithCoords['city'],
          ]
                .where((e) => e != null && (e as String).isNotEmpty)
                .join(', ');
    final firstAddr = addresses.whereType<Map<String, dynamic>>().firstOrNull;
    final mapAddress = firstAddr == null
        ? null
        : [
            firstAddr['street'],
            firstAddr['barangay'],
            firstAddr['city'],
            firstAddr['province'],
          ]
                .where((e) => e != null && (e as String).isNotEmpty)
                .join(', ')
                .trim();

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
              destinationLat: mapLat,
              destinationLng: mapLng,
              destinationTitle: 'Lender Location',
              destinationSnippet: mapLabel.isEmpty ? 'Destination' : mapLabel,
              destinationAddress: (mapAddress == null || mapAddress.isEmpty)
                  ? null
                  : mapAddress,
              height: double.infinity,
              autofitBoth: true,
            ),
          ),
        ),
        if (addresses.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'No addresses available for navigation.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _InstructionCard(),
                      const SizedBox(height: 12),
                      ...addresses.map((addr) {
                        final a = addr as Map<String, dynamic>;
                        final type = (a['address_type'] as String? ?? '')
                            .toUpperCase();
                        final full = [
                          a['street'],
                          a['barangay'],
                          a['city'],
                          a['province'],
                        ]
                            .where((e) => e != null && (e as String).isNotEmpty)
                            .join(', ');
                        final lat = (a['latitude'] as num?)?.toDouble();
                        final lng = (a['longitude'] as num?)?.toDouble();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.riderGreen
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(type,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.riderGreen)),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.location_on,
                                      color: AppColors.riderGreen, size: 18),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                full.isEmpty ? '—' : full,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                    height: 1.4),
                              ),
                              if (lat != null && lng != null) ...[
                                const SizedBox(height: 6),
                                Text('$lat, $lng',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary)),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.riderGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      minimumSize:
                                          const Size(double.infinity, 44),
                                    ),
                                    onPressed: () => _openDirections(lat, lng),
                                    icon: const Icon(Icons.navigation,
                                        size: 18),
                                    label: const Text(
                                      'Open Directions',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                      const Center(child: RiderMapLegend()),
                    ],
                  ),
                ),
              ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.riderGreenDark, AppColors.riderGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_outlined,
              color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CI Investigation',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.riderGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.riderGreen, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Navigate to the lender\'s address to conduct the credit investigation. Visit all provided addresses.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
