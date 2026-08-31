// lib/presentation/shared/widgets/details/user_details_modal.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../profile_avatar.dart';
import '../status_badge.dart';

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

class _UserDetailsModalContent extends StatelessWidget {
  final UserModel user;
  const _UserDetailsModalContent({required this.user});

  @override
  Widget build(BuildContext context) {
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
            // Header — no radius, square
            Container(
              color: Colors.white,
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
                        Text(roleLabel + ' Details',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const Text('Detailed profile information',
                            style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
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
                      name: displayName.isEmpty ? '—' : displayName,
                      subtitle: subtitle,
                      subtitleIcon: subtitleIcon,
                      roleLabel: roleLabel,
                      accentColor: accent,
                      accountStatus: user.accountStatus,
                    ),
                    const SizedBox(height: 14),
                    ..._sectionsForRole(user, accent),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
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
        return u.email ?? '—';
      case 'rider':
        return u.phoneNumber ?? '—';
      case 'lender':
        return u.email ?? u.phoneNumber ?? '—';
      case 'head_manager':
        return u.email ?? '—';
      default:
        return u.email ?? u.phoneNumber ?? '—';
    }
  }

  IconData _subtitleIconForRole(String role) {
    switch (role) {
      case 'rider':
        return Icons.phone_outlined;
      case 'lender':
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
              _Kv('Role', 'Employee'),
              _Kv('Email', u.email ?? '—'),
              _Kv('Phone', u.phoneNumber ?? '—'),
              _Kv('Position', u.position ?? '—'),
              _Kv('Gender', u.gender ?? '—'),
              _Kv('Civil Status', u.civilStatus ?? '—'),
              _Kv('Created At', u.createdAt.toString().substring(0, 10)),
              _Kv('Last Login', u.lastLoginAt?.toString().substring(0, 16) ?? '—'),
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
              _Kv('Vehicle Type', u.vehicleType ?? '—'),
              _Kv('Vehicle Brand', u.vehicleBrand ?? '—'),
              _Kv('Plate Number', u.plateNumber ?? '—'),
              _Kv("Driver's License", u.driversLicenseNumber ?? '—'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Account Information',
            icon: Icons.account_circle_outlined,
            accentColor: accent,
            items: [
              _Kv('Role', 'Rider'),
              _Kv('Phone', u.phoneNumber ?? '—'),
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
              _Kv('Gender', u.gender ?? '—'),
              _Kv('Civil Status', u.civilStatus ?? '—'),
              _Kv('Date of Birth', u.dateOfBirth?.toString().substring(0, 10) ?? '—'),
              _Kv('Employment', u.employmentType ?? '—'),
              _Kv('Employer', u.employerName ?? '—'),
              _Kv('Monthly Income', u.monthlyIncome != null ? '₱${u.monthlyIncome!.toStringAsFixed(2)}' : '—'),
              _Kv('Source of Funds', u.sourceOfFunds ?? '—'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            accentColor: accent,
            items: [
              _Kv('Phone', u.phoneNumber ?? '—'),
              _Kv('Email', u.email ?? '—'),
              _Kv('GCash Number', u.gcashNumber ?? '—'),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Address',
            icon: Icons.location_on_outlined,
            accentColor: accent,
            items: [
              _Kv('Street', u.streetAddress ?? '—'),
              _Kv('Barangay', u.barangay ?? '—'),
              _Kv('City', u.city ?? '—'),
              _Kv('Province', u.province ?? '—'),
              _Kv('Zip Code', u.zipCode ?? '—'),
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
                    ? const Text('—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
                    : StatusBadge(status: u.accountUpgradeStatus!, small: true),
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
              _Kv('Email', u.email ?? '—'),
              _Kv('Phone', u.phoneNumber ?? '—'),
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
            child: ProfileAvatar(
              photoUrl: photoUrl,
              name: name,
              color: accentColor,
              radius: 32,
              textColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.zero),
                      child: Text(roleLabel.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accentColor, letterSpacing: 0.6)),
                    ),
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
                const SizedBox(height: 10),
                StatusBadge(status: accountStatus),
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
  final List<dynamic> items; // _Kv or _KvWidget
  const _SectionCard({required this.title, required this.icon, required this.accentColor, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.zero),
                child: Icon(icon, size: 17, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.deepNavy, letterSpacing: 0.3)),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
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
          ],
        ],
      ),
    );
  }
}
