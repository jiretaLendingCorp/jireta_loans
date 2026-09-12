// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/ci/screens/rider_ci_borrower_info_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderCiBorrowerInfoScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderCiBorrowerInfoScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderCiBorrowerInfoScreen> createState() =>
      _RiderCiBorrowerInfoScreenState();
}

class _RiderCiBorrowerInfoScreenState
    extends ConsumerState<RiderCiBorrowerInfoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    });
  }

  Future<void> _callBorrower(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _smsBorrower(String phone) async {
    final uri = Uri.parse('sms:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);
    final ci = state.selectedCi;

    return MobileScaffold(
      title: 'Lender Info (CI)',
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
    final fullName = (loan?['lender_name'] as String?) ??
        (composedName.isEmpty ? '—' : composedName);
    final phone = user?['phone_number'] as String? ?? '—';
    final dob = lender?['date_of_birth'] as String?;
    final gender = lender?['gender'] as String? ?? '—';
    final civil = lender?['civil_status'] as String? ?? '—';
    final employment = lender?['employment_type'] as String? ?? '—';
    final employer = lender?['employer_name'] as String? ?? '—';
    final income = lender?['monthly_income'] as num?;
    final addresses = (lender?['users'] as Map<String, dynamic>?)?['addresses']
            as List? ??
        [];
    final emergencyContacts = lender?['emergency_contacts'] as List? ?? [];

    return RefreshIndicator(
      color: AppColors.riderGreen,
      onRefresh: () async =>
          ref.read(riderCiProvider.notifier).loadDetails(widget.ciId),
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _CiBanner(ciId: widget.ciId, notes: ci.investigationNotes as String?),
          SizedBox(height: 16),
          _ProfileHeaderCard(name: fullName, phone: phone),
          SizedBox(height: 12),
          _ContactRow(
            onCall: () => _callBorrower(phone),
            onSms: () => _smsBorrower(phone),
            onCopy: () {
              Clipboard.setData(ClipboardData(text: phone));
              context.showSnackBarAsToast(
                const SnackBar(
                    content: Text('Phone copied'),
                    backgroundColor: AppColors.riderGreen),
              );
            },
          ),
          SizedBox(height: 16),
          _InfoCard(title: 'Personal Information', items: [
            _InfoItem(label: 'Date of Birth', value: dob ?? '—'),
            _InfoItem(label: 'Gender', value: gender),
            _InfoItem(label: 'Civil Status', value: civil),
          ]),
          SizedBox(height: 12),
          _InfoCard(title: 'Employment', items: [
            _InfoItem(label: 'Employment Type', value: employment),
            _InfoItem(label: 'Employer', value: employer),
            _InfoItem(
                label: 'Monthly Income',
                value: income != null ? '₱${income.toStringAsFixed(2)}' : '—'),
          ]),
          SizedBox(height: 12),
          if (addresses.isNotEmpty) _AddressesSection(addresses: addresses),
          SizedBox(height: 12),
          if (emergencyContacts.isNotEmpty)
            _EmergencyContactsSection(contacts: emergencyContacts),
          SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: () => context.push(RouteConstants
                .riderNavigateToBorrowerCi
                .replaceFirst(':id', widget.ciId)),
            icon: Icon(Icons.navigation_outlined),
            label: Text('Navigate to Address',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _CiBanner extends StatelessWidget {
  final String ciId;
  final String? notes;
  const _CiBanner({required this.ciId, this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.riderGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined,
                  color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              Text('CI Investigation Notes',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.riderGreen)),
            ],
          ),
          if (notes != null && notes!.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(notes!,
                style: TextStyle(
                    fontSize: 13, color: context.cTextSecondary)),
          ] else ...[
            SizedBox(height: 6),
            Text('No additional notes provided.',
                style: TextStyle(
                    fontSize: 13,
                    color: context.cTextTertiary,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String phone;
  const _ProfileHeaderCard({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.riderGreenDark, AppColors.riderGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(phone.maskPhone(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onSms;
  final VoidCallback onCopy;
  const _ContactRow(
      {required this.onCall, required this.onSms, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _ContactBtn(
                icon: Icons.phone,
                label: 'Call',
                color: AppColors.riderGreen,
                onTap: onCall)),
        SizedBox(width: 8),
        Expanded(
            child: _ContactBtn(
                icon: Icons.sms_outlined,
                label: 'SMS',
                color: AppColors.info,
                onTap: onSms)),
        SizedBox(width: 8),
        Expanded(
            child: _ContactBtn(
                icon: Icons.copy_outlined,
                label: 'Copy',
                color: context.cTextSecondary,
                onTap: onCopy)),
      ],
    );
  }
}

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  _InfoItem({required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoItem> items;
  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: context.cTextPrimary)),
          SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 13, color: context.cTextSecondary)),
                    Flexible(
                        child: Text(item.value,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.cTextPrimary),
                            textAlign: TextAlign.end)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _AddressesSection extends StatelessWidget {
  final List addresses;
  const _AddressesSection({required this.addresses});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Addresses to Investigate',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: context.cTextPrimary)),
          SizedBox(height: 12),
          ...addresses.map((addr) {
            final a = addr as Map<String, dynamic>;
            final type = (a['address_type'] as String? ?? '').toUpperCase();
            final full = [a['street'], a['barangay'], a['city'], a['province']]
                .where((e) => e != null && (e as String).isNotEmpty)
                .join(', ');
            return Container(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.riderGreen)),
                  SizedBox(height: 4),
                  Text(full.isEmpty ? '—' : full,
                      style: TextStyle(
                          fontSize: 13, color: context.cTextPrimary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EmergencyContactsSection extends StatelessWidget {
  final List contacts;
  const _EmergencyContactsSection({required this.contacts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Emergency Contacts',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: context.cTextPrimary)),
          SizedBox(height: 12),
          ...contacts.map((c) {
            final contact = c as Map<String, dynamic>;
            return Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.emergency_outlined,
                      color: AppColors.warning, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contact['name'] as String? ?? '—',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 13)),
                        Text(contact['relationship'] as String? ?? '—',
                            style: TextStyle(
                                fontSize: 12, color: context.cTextSecondary)),
                      ],
                    ),
                  ),
                  Text(contact['phone_number'] as String? ?? '—',
                      style: TextStyle(
                          fontSize: 12, color: context.cTextSecondary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
