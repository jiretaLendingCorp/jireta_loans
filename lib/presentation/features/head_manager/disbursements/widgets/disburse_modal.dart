// lib/presentation/features/head_manager/disbursements/widgets/disburse_modal.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

class DisburseModal extends StatefulWidget {
  final String loanId;
  final double loanAmount;
  final String lenderName;
  final Future<void> Function(String method, Map<String, dynamic> data)
      onDisburse;
  final List<Map<String, dynamic>> availableRiders;
  final String? preferredMethod;
  final String? preferredGcashNumber;
  final String? lenderAddress;

  const DisburseModal({
    super.key,
    required this.loanId,
    required this.loanAmount,
    required this.lenderName,
    required this.onDisburse,
    this.availableRiders = const [],
    this.preferredMethod,
    this.preferredGcashNumber,
    this.lenderAddress,
  });

  @override
  State<DisburseModal> createState() => _DisburseModalState();
}

class _DisburseModalState extends State<DisburseModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _gcashCtrl = TextEditingController();
  final _riderNotesCtrl = TextEditingController();
  String? _selectedRiderId;
  DateTime? _deliveryDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _gcashCtrl.text = widget.preferredGcashNumber ?? '';
    int initialIndex = 0;
    switch (widget.preferredMethod) {
      case 'office_cash':
        initialIndex = 1;
        break;
      case 'rider_delivery':
        initialIndex = 2;
        break;
      default:
        initialIndex = 0;
    }
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: initialIndex);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _gcashCtrl.dispose();
    _riderNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Disburse Loan',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(
              '${widget.lenderName} • ₱${widget.loanAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: const [
                Tab(text: 'GCash'),
                Tab(text: 'Office Cash'),
                Tab(text: 'Rider Delivery'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 210,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildGcashTab(),
                  _buildOfficeCashTab(),
                  _buildRiderTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold, foregroundColor: Colors.black87),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.deepNavy))
              : const Text('Disburse'),
        ),
      ],
    );
  }

  Widget _buildGcashTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
              'Enter the lender\'s GCash number for fund transfer via Xendit.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextField(
            controller: _gcashCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'GCash Number',
              prefixIcon: const Icon(Icons.phone_android, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (widget.lenderAddress != null &&
              widget.lenderAddress!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Registered: ${widget.lenderAddress}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfficeCashTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Icon(Icons.business_center, size: 40, color: AppColors.success),
          const SizedBox(height: 12),
          const Text(
            'Confirm that the lender\'s KYC identity has been verified before releasing cash at the office.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Documents the lender must bring:',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('• Valid government-issued ID (original)',
                    style: TextStyle(fontSize: 11, height: 1.4)),
                Text('• Signed loan agreement / promissory note',
                    style: TextStyle(fontSize: 11, height: 1.4)),
                Text('• Loan reference number',
                    style: TextStyle(fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildRiderTab() {
    final address = widget.lenderAddress;
    return SingleChildScrollView(
      child: Column(
        children: [
          if (address != null && address.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.home_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Deliver to: $address',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _selectedRiderId,
            decoration: InputDecoration(
              labelText: 'Select Rider',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: widget.availableRiders.map((r) {
              return DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(
                      '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim()));
            }).toList(),
            onChanged: (v) => setState(() => _selectedRiderId = v),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final dt = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (dt != null) setState(() => _deliveryDate = dt);
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_deliveryDate != null
                ? 'Delivery: ${_deliveryDate!.day}/${_deliveryDate!.month}/${_deliveryDate!.year}'
                : 'Pick Delivery Date'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final tab = _tabCtrl.index;
      if (tab == 0) {
        final gcash = _gcashCtrl.text.trim();
        if (gcash.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please enter the lender\'s GCash number.'),
                backgroundColor: AppColors.error),
          );
          setState(() => _loading = false);
          return;
        }
        await widget
            .onDisburse('gcash', {'gcash_number': gcash});
      } else if (tab == 1) {
        await widget.onDisburse('office_cash', {});
      } else {
        if (_selectedRiderId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please select a rider.'),
                backgroundColor: AppColors.error),
          );
          setState(() => _loading = false);
          return;
        }
        await widget.onDisburse('rider_delivery', {
          'rider_id': _selectedRiderId!,
          if (_deliveryDate != null)
            'delivery_date': _deliveryDate!.toIso8601String(),
          if (_riderNotesCtrl.text.isNotEmpty) 'notes': _riderNotesCtrl.text,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _loading = false);
    }
  }
}
