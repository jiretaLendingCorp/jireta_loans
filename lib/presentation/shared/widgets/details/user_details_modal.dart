// lib/presentation/shared/widgets/details/user_details_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';

Future<void> showUserDetailsModal(BuildContext context, UserModel user) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _UserDetailsModalContent(user: user),
    ),
  );
}

class _UserDetailsModalContent extends ConsumerStatefulWidget {
  final UserModel user;
  const _UserDetailsModalContent({required this.user});

  @override
  ConsumerState<_UserDetailsModalContent> createState() => _UserDetailsModalContentState();
}

class _UserDetailsModalContentState extends ConsumerState<_UserDetailsModalContent> {
  UserModel? _fullUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchFullProfile();
  }

  Future<void> _fetchFullProfile() async {
    try {
      final ds = sl<UserRemoteDataSource>();
      final full = await ds.getProfile(userId: widget.user.id);
      if (mounted) setState(() { _fullUser = full; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _fullUser = widget.user; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final size = MediaQuery.of(context).size;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size.width > 640 ? 560.0 : size.width * 0.94, maxHeight: size.height * 0.88),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))]),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final user = _fullUser ?? widget.user;
    final role = user.role;
    final accent = _roleColor(role);
    final roleLabel = _roleLabel(role);
    final displayName =
        '${user.firstName}${user.middleName != null && user.middleName!.isNotEmpty ? ' ${user.middleName}' : ''} ${user.lastName}'.trim();
    final subtitle = _subtitleForRole(user);
    final subtitleIcon = _subtitleIconForRole(role);

    final size = MediaQuery.of(context).size;
    final maxW = size.width > 640 ? 560.0 : size.width * 0.94;
    final maxH = size.height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          boxShadow: [
            BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: const Color(0xFF5C6370),
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.zero),
                    child: Icon(_roleIcon(role), color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$roleLabel Details',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                        const Text('Detailed profile information',
                            style: TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderCard(
                      photoUrl: user.profilePhotoUrl,
                      name: displayName.isEmpty ? 'N/A' : displayName,
                      subtitle: subtitle,
                      subtitleIcon: subtitleIcon,
                      roleLabel: roleLabel,
                      accentColor: accent,
                      accountStatus: user.accountStatus,
                    ),
                    const SizedBox(height: 14),
                    ..._sectionsForRole(user, accent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleForRole(UserModel u) {
    switch (u.role) {
      case 'employee':
        return u.email ?? 'N/A';
      case 'rider':
        return u.phoneNumber ?? 'N/A';
      case 'lender':
        return u.email ?? u.phoneNumber ?? 'N/A';
      case 'head_manager':
        return u.email ?? 'N/A';
      default:
        return u.email ?? u.phoneNumber ?? 'N/A';
    }
  }

  IconData _subtitleIconForRole(String role) {
    switch (role) {
      case 'rider':
        return Icons.phone_outlined;
      case 'lender':
        return Icons.contact_phone_outlined;
      case 'employee':
      case 'head_manager':
      default:
        return Icons.email_outlined;
    }
  }

  List<Widget> _sectionsForRole(UserModel u, Color accent) {
    switch (u.role) {
      case 'employee':
        return [
          _SectionCard(
            title: 'Account Information',
            icon: Icons.account_circle_outlined,
            accentColor: accent,
            items: [
              const _Kv('Role', 'Employee'),
              _Kv('Email', u.email ?? 'N/A'),
              _Kv('Phone', u.phoneNumber ?? 'N/A'),
              _Kv('Position', u.position ?? 'N/A'),
              _Kv('Gender', u.gender ?? 'N/A'),
              _Kv('Civil Status', u.civilStatus ?? 'N/A'),
              _Kv('Created At', u.createdAt.toString().substring(0, 10)),
              _Kv('Last Login', u.lastLoginAt?.toString().substring(0, 16) ?? 'N/A'),
            ],
          ),
        ];
      case 'rider':
        return [
          _SectionCard(
            title: 'Vehicle Information',
            icon: Icons.directions_bike_outlined,
            accentColor: accent,
            items: [
              _Kv('Vehicle Type', u.vehicleType ?? 'N/A'),
              _Kv('Vehicle Brand', u.vehicleBrand ?? 'N/A'),
              _Kv('Plate Number', u.plateNumber ?? 'N/A'),
              _Kv("Driver's License", u.driversLicenseNumber ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Account Information',
            icon: Icons.account_circle_outlined,
            accentColor: accent,
            items: [
              const _Kv('Role', 'Rider'),
              _Kv('Phone', u.phoneNumber ?? 'N/A'),
              _Kv('Account Status', u.accountStatus),
              _Kv('Member Since', u.createdAt.toString().substring(0, 10)),
            ],
          ),
        ];
      case 'lender':
        return [
          _SectionCard(
            title: 'Personal Information',
            icon: Icons.person_outline,
            accentColor: accent,
            items: [
              _Kv('Gender', u.gender ?? 'N/A'),
              _Kv('Civil Status', u.civilStatus ?? 'N/A'),
              _Kv('Date of Birth', u.dateOfBirth?.toString().substring(0, 10) ?? 'N/A'),
              _Kv('Employment', u.employmentType ?? 'N/A'),
              _Kv('Employer', u.employerName ?? 'N/A'),
              _Kv('Monthly Income', u.monthlyIncome != null ? '₱${u.monthlyIncome!.toStringAsFixed(2)}' : 'N/A'),
              _Kv('Source of Funds', u.sourceOfFunds ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            accentColor: accent,
            items: [
              _Kv('Phone', u.phoneNumber ?? 'N/A'),
              _Kv('Email', u.email ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Address',
            icon: Icons.location_on_outlined,
            accentColor: accent,
            items: [
              _Kv('Street', u.streetAddress ?? 'N/A'),
              _Kv('Barangay', u.barangay ?? 'N/A'),
              _Kv('City', u.city ?? 'N/A'),
              _Kv('Province', u.province ?? 'N/A'),
              _Kv('Zip Code', u.zipCode ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Account',
            icon: Icons.account_circle_outlined,
            accentColor: accent,
            items: [
              _Kv('Account Status', u.accountStatus),
              _Kv('Member Since', u.createdAt.toString().substring(0, 10)),
              _KvWidget(
                label: 'Account Upgrade',
                widget: u.accountUpgradeStatus == null || u.accountUpgradeStatus!.isEmpty
                    ? const Text('N/A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
                    : Text(u.accountUpgradeStatus!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ];
      default:
        return [
          _SectionCard(
            title: 'Account Information',
            icon: Icons.account_circle_outlined,
            accentColor: accent,
            items: [
              _Kv('Role', _roleLabel(u.role)),
              _Kv('Email', u.email ?? 'N/A'),
              _Kv('Phone', u.phoneNumber ?? 'N/A'),
              _Kv('Status', u.accountStatus),
              _Kv('Member Since', u.createdAt.toString().substring(0, 10)),
            ],
          ),
        ];
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'employee':
        return AppColors.deepNavy;
      case 'rider':
        return AppColors.riderGreen;
      case 'lender':
        return AppColors.lenderBlue;
      case 'head_manager':
        return AppColors.gold;
      default:
        return AppColors.textSecondary;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'head_manager':
        return 'Head Manager';
      case 'employee':
        return 'Employee';
      case 'rider':
        return 'Rider';
      case 'lender':
        return 'Lender';
      default:
        return role;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'employee':
        return Icons.badge_outlined;
      case 'rider':
        return Icons.directions_bike_outlined;
      case 'lender':
        return Icons.account_balance_wallet_outlined;
      case 'head_manager':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outline;
    }
  }
}

class _HeaderCard extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final String? subtitle;
  final IconData? subtitleIcon;
  final String roleLabel;
  final Color accentColor;
  final String accountStatus;
  const _HeaderCard({
    required this.photoUrl,
    required this.name,
    this.subtitle,
    this.subtitleIcon,
    required this.roleLabel,
    required this.accentColor,
    required this.accountStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 2),
            ),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded, size: 32, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    Text(roleLabel.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accentColor, letterSpacing: 0.6)),
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(subtitleIcon ?? Icons.info_outline, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text(accountStatus.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accountStatus.toLowerCase() == 'active' ? AppColors.success : AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kv {
  final String label;
  final String value;
  const _Kv(this.label, this.value);
}

class _KvWidget {
  final String label;
  final Widget widget;
  const _KvWidget({required this.label, required this.widget});
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<dynamic> items;
  const _SectionCard({required this.title, required this.icon, required this.accentColor, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
          ),
          if (items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 28,
                runSpacing: 16,
              children: items.map((e) {
                if (e is _KvWidget) {
                  return SizedBox(
                    width: 210,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      e.widget,
                    ]),
                  );
                }
                final kv = e as _Kv;
                return SizedBox(
                  width: 210,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(kv.label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(kv.value, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ]),
                );
              }).toList(),
            ),
            ),
          ],
        ],
      ),
    );
  }
}
