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

  const DisburseModal({
    super.key,
    required this.loanId,
    required this.loanAmount,
    required this.lenderName,
    required this.onDisburse,
    this.availableRiders = const [],
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
    _tabCtrl = TabController(length: 3, vsync: this);
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
              height: 160,
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
    return Column(
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
      ],
    );
  }

  Widget _buildOfficeCashTab() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.business_center, size: 40, color: AppColors.success),
        SizedBox(height: 12),
        Text(
          'Confirm that the lender\'s KYC identity has been verified before releasing cash at the office.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRiderTab() {
    return Column(
      children: [
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
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final tab = _tabCtrl.index;
      if (tab == 0) {
        await widget
            .onDisburse('gcash', {'gcash_number': _gcashCtrl.text.trim()});
      } else if (tab == 1) {
        await widget.onDisburse('office_cash', {});
      } else {
        if (_selectedRiderId == null) return;
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
