// lib/presentation/features/rider/collections/screens/rider_borrower_info_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../providers/rider_collection_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderBorrowerInfoScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderBorrowerInfoScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderBorrowerInfoScreen> createState() =>
      _RiderBorrowerInfoScreenState();
}

class _RiderBorrowerInfoScreenState
    extends ConsumerState<RiderBorrowerInfoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
    });
  }

  Future<void> _callBorrower(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _smsLender(String phone) async {
    final uri = Uri.parse('sms:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    return MobileScaffold(
      title: 'Lender Info',
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
    final fullName = (col.lenderName as String).isEmpty ? '—' : col.lenderName;
    final phone = (col.lenderPhone as String).isEmpty ? '—' : col.lenderPhone;
    final gcash = (col.lenderGcash as String).isEmpty ? '—' : col.lenderGcash;
    final addresses = col.lenderAddresses as List? ?? [];

    return RefreshIndicator(
      color: AppColors.riderGreen,
      onRefresh: () async {
        await ref
            .read(riderCollectionProvider.notifier)
            .loadDetails(widget.collectionId);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileCard(name: fullName, phone: phone),
          const SizedBox(height: 16),
          _ContactActionsCard(
            phone: phone,
            onCall: () => _callBorrower(phone),
            onSms: () => _smsLender(phone),
            onCopy: () {
              Clipboard.setData(ClipboardData(text: phone));
              context.showSnackBarAsToast(
                const SnackBar(
                    content: Text('Phone copied'),
                    backgroundColor: AppColors.riderGreen),
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'GCash Number',
            icon: Icons.account_balance_wallet_outlined,
            child: Text(gcash.maskPhone(),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 16),
          if (addresses.isNotEmpty) _AddressesCard(addresses: addresses),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: () => context.push(
              RouteConstants.riderNavigateToBorrower
                  .replaceFirst(':id', widget.collectionId),
            ),
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Navigate to Lender',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String phone;
  const _ProfileCard({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(phone.maskPhone(),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactActionsCard extends StatelessWidget {
  final String phone;
  final VoidCallback onCall;
  final VoidCallback onSms;
  final VoidCallback onCopy;
  const _ContactActionsCard(
      {required this.phone,
      required this.onCall,
      required this.onSms,
      required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact Lender',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                    icon: Icons.phone,
                    label: 'Call',
                    color: AppColors.riderGreen,
                    onTap: onCall),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                    icon: Icons.sms_outlined,
                    label: 'SMS',
                    color: AppColors.info,
                    onTap: onSms),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                    icon: Icons.copy_outlined,
                    label: 'Copy',
                    color: AppColors.textSecondary,
                    onTap: onCopy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.riderGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressesCard extends StatelessWidget {
  final List addresses;
  const _AddressesCard({required this.addresses});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Text('Addresses',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          ...addresses.map((addr) {
            final a = addr as Map<String, dynamic>;
            final type = (a['address_type'] as String? ?? '').toUpperCase();
            final full = [
              a['street'],
              a['barangay'],
              a['city'],
              a['province'],
            ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(type,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.riderGreen)),
                  ),
                  const SizedBox(height: 4),
                  Text(full.isEmpty ? '—' : full,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
