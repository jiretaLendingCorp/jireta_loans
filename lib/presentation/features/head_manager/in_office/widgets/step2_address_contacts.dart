// lib/presentation/features/head_manager/in_office/widgets/step2_address_contacts.dart
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
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

  final List<Map<String, TextEditingController>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _addContact();
  }

  @override
  void dispose() {
    _homeStreetCtrl.dispose();
    _homeCityCtrl.dispose();
    _homeProvinceCtrl.dispose();
    _homeZipCtrl.dispose();
    _workStreetCtrl.dispose();
    _workCityCtrl.dispose();
    _workProvinceCtrl.dispose();
    for (final c in _contacts) {
      for (final ctrl in c.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  void _addContact() {
    setState(() {
      _contacts.add({
        'name': TextEditingController(),
        'phone': TextEditingController(),
        'relationship': TextEditingController(),
      });
    });
  }

  void _removeContact(int index) {
    setState(() {
      for (final ctrl in _contacts[index].values) {
        ctrl.dispose();
      }
      _contacts.removeAt(index);
    });
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
      'emergency_contacts': _contacts
          .map((c) => {
                'name': c['name']!.text.trim(),
                'phone': c['phone']!.text.trim(),
                'relationship': c['relationship']!.text.trim(),
              })
          .where((c) => c['name']!.isNotEmpty)
          .toList(),
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
            'Address & Emergency Contacts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Provide the lender\'s home address and emergency contact information.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          const _SectionHeader(
              title: 'Home Address', icon: Icons.home_outlined),
          const SizedBox(height: 12),
          AppTextField(
            controller: _homeStreetCtrl,
            label: 'Street Address *',
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _homeCityCtrl,
                  label: 'City / Municipality *',
                  onChanged: (_) => _update(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _homeProvinceCtrl,
                  label: 'Province *',
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
              onChanged: (_) => _update(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _workCityCtrl,
                    label: 'City / Municipality',
                    onChanged: (_) => _update(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _workProvinceCtrl,
                    label: 'Province',
                    onChanged: (_) => _update(),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionHeader(
                  title: 'Emergency Contacts',
                  icon: Icons.contact_phone_outlined),
              AppButton(
                label: 'Add Contact',
                onPressed: _addContact,
                variant: AppButtonVariant.secondary,
                icon: Icons.add,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_contacts.length, (i) {
            final c = _contacts[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Contact ${i + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (_contacts.length > 1)
                        IconButton(
                          onPressed: () => _removeContact(i),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: AppColors.error,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: c['name']!,
                    label: 'Full Name *',
                    onChanged: (_) => _update(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: c['phone']!,
                          label: 'Phone Number *',
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => _update(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: c['relationship']!,
                          label: 'Relationship *',
                          onChanged: (_) => _update(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
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
