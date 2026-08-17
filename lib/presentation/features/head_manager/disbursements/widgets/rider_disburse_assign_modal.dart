// lib/presentation/features/head_manager/disbursements/widgets/rider_disburse_assign_modal.dart
// Shared modal used by Head Manager and Employee to assign a delivery rider for
// an approved loan whose lender chose "Cash via Rider" as the disbursement method.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_date_picker.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';

class RiderDisburseAssignModal extends ConsumerStatefulWidget {
  final String loanId;
  final double loanAmount;
  final String? lenderName;
  final String? lenderAddress;

  const RiderDisburseAssignModal({
    super.key,
    required this.loanId,
    required this.loanAmount,
    this.lenderName,
    this.lenderAddress,
  });

  @override
  ConsumerState<RiderDisburseAssignModal> createState() =>
      _RiderDisburseAssignModalState();
}

class _RiderDisburseAssignModalState
    extends ConsumerState<RiderDisburseAssignModal> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _deliveryDate;
  bool _loading = false;
  bool _loadingRiders = true;
  List<Map<String, dynamic>> _riders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRiders() async {
    try {
      final ds = sl<UserRemoteDataSource>();
      final res = await ds.getUserList(
        role: 'rider',
        status: 'active',
        page: 1,
        limit: 100,
      );
      final list =
          (res['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _riders = list
            .where((r) =>
                (r['rider_profiles']?['is_available'] ?? true) == true)
            .toList();
        _loadingRiders = false;
      });
    } catch (_) {
      setState(() {
        _loadingRiders = false;
        _error = 'Failed to load riders';
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedRiderId == null) {
      setState(() => _error = 'Please select a rider');
      return;
    }
    if (_deliveryDate == null) {
      setState(() => _error = 'Please pick a delivery date');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await sl<DisbursementRemoteDataSource>().disburseRiderDelivery(
        loanId: widget.loanId,
        riderId: _selectedRiderId!,
        deliveryDate: _deliveryDate!.toIso8601String(),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLoanSummary(),
                  const SizedBox(height: 16),
                  _buildRiderPicker(),
                  const SizedBox(height: 16),
                  AppDatePicker(
                    label: 'Delivery Date *',
                    value: _deliveryDate,
                    onChanged: (d) => setState(() => _deliveryDate = d),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _notesCtrl,
                    label: 'Delivery Instructions',
                    hint: 'Instructions for the rider...',
                    maxLines: 3,
                    maxLength: 255,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Assign Rider',
                          onPressed: _loading ? null : _submit,
                          isLoading: _loading,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: AppColors.gold, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Assign Delivery Rider',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white60, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanSummary() {
    final address = widget.lenderAddress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.lenderName ?? 'Lender'} • ₱${widget.loanAmount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Deliver to: $address',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiderPicker() {
    if (_loadingRiders) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_riders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'No available riders at the moment.',
          style: TextStyle(color: AppColors.warning, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Available Rider *',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRiderId,
              isExpanded: true,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Choose a rider...',
                    style: TextStyle(color: AppColors.textTertiary)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              borderRadius: BorderRadius.circular(8),
              items: _riders.map((r) {
                final firstName = r['first_name'] ?? '';
                final lastName = r['last_name'] ?? '';
                final plate = r['rider_profiles']?['plate_number'] ?? '';
                return DropdownMenuItem<String>(
                  value: r['id'] as String,
                  child: Text('$firstName $lastName — $plate'),
                );
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedRiderId = v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
