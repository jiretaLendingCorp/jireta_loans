// lib/presentation/features/head_manager/in_office/widgets/step2_address_contacts.dart
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';

class Step2AddressContacts extends StatefulWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onDataChanged;

  const Step2AddressContacts({
    super.key,
    required this.data,
    required this.onDataChanged,
  });

  @override
  State<Step2AddressContacts> createState() => _Step2AddressContactsState();
}

class _Step2AddressContactsState extends State<Step2AddressContacts> {
  final _homeStreetCtrl = TextEditingController();
  final _homeCityCtrl = TextEditingController();
  final _homeProvinceCtrl = TextEditingController();
  final _homeZipCtrl = TextEditingController();

  final _workStreetCtrl = TextEditingController();
  final _workCityCtrl = TextEditingController();
  final _workProvinceCtrl = TextEditingController();

  bool _hasWorkAddress = false;

  @override
  void dispose() {
    _homeStreetCtrl.dispose();
    _homeCityCtrl.dispose();
    _homeProvinceCtrl.dispose();
    _homeZipCtrl.dispose();
    _workStreetCtrl.dispose();
    _workCityCtrl.dispose();
    _workProvinceCtrl.dispose();
    super.dispose();
  }

  void _update() {
    widget.onDataChanged({
      'home_address': {
        'street': _homeStreetCtrl.text.trim(),
        'city': _homeCityCtrl.text.trim(),
        'province': _homeProvinceCtrl.text.trim(),
        'zip': _homeZipCtrl.text.trim(),
        'type': 'home',
      },
      if (_hasWorkAddress)
        'work_address': {
          'street': _workStreetCtrl.text.trim(),
          'city': _workCityCtrl.text.trim(),
          'province': _workProvinceCtrl.text.trim(),
          'type': 'work',
        },
      // Emergency contact now lives on the loans table per-loan
      // (loan_emergency_contacts) — no longer collected in-office.
      'emergency_contacts': <Map<String, dynamic>>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Address',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Provide the lender\'s home address.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          const _SectionHeader(
              title: 'Home Address', icon: Icons.home_outlined),
          const SizedBox(height: 12),
          AppTextField(
            controller: _homeStreetCtrl,
            label: 'Street Address *',
            maxLength: 100,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _homeCityCtrl,
                  label: 'City / Municipality *',
                  maxLength: 100,
                  onChanged: (_) => _update(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _homeProvinceCtrl,
                  label: 'Province *',
                  maxLength: 100,
                  onChanged: (_) => _update(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _homeZipCtrl,
            label: 'ZIP Code',
            keyboardType: TextInputType.number,
            maxLength: 4,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Switch(
                value: _hasWorkAddress,
                activeThumbColor: AppColors.gold,
                onChanged: (v) {
                  setState(() => _hasWorkAddress = v);
                  _update();
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'Add Work/Business Address',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (_hasWorkAddress) ...[
            const SizedBox(height: 12),
            const _SectionHeader(
                title: 'Work / Business Address',
                icon: Icons.business_outlined),
            const SizedBox(height: 12),
            AppTextField(
              controller: _workStreetCtrl,
              label: 'Street Address',
              maxLength: 100,
              onChanged: (_) => _update(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _workCityCtrl,
                    label: 'City / Municipality',
                    maxLength: 100,
                    onChanged: (_) => _update(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _workProvinceCtrl,
                    label: 'Province',
                    maxLength: 100,
                    onChanged: (_) => _update(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
