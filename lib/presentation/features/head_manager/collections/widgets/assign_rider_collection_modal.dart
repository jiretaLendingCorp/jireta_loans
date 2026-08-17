// lib/presentation/features/head_manager/collections/widgets/assign_rider_collection_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_collection_provider.dart';

class AssignRiderCollectionModal extends ConsumerStatefulWidget {
  final String loanScheduleId;
  final String loanId;
  final String? assignmentId;
  const AssignRiderCollectionModal({
    super.key,
    required this.loanScheduleId,
    required this.loanId,
    this.assignmentId,
  });

  @override
  ConsumerState<AssignRiderCollectionModal> createState() =>
      _AssignRiderCollectionModalState();
}

class _AssignRiderCollectionModalState
    extends ConsumerState<AssignRiderCollectionModal> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _collectionSchedule;
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
          role: 'rider', status: 'active', page: 1, limit: 100);
      final list =
          (res['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _riders = list
            .where((r) => (r['rider_profiles']?['is_available'] ?? true) == true)
            .toList();
        _loadingRiders = false;
      });
    } catch (_) {
      setState(() => _loadingRiders = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _collectionSchedule = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_selectedRiderId == null) {
      setState(() => _error = 'Please select a rider');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmCollectionProvider.notifier).assignRider(
            loanScheduleId: widget.loanScheduleId,
            loanId: widget.loanId,
            riderId: _selectedRiderId!,
            assignmentId: widget.assignmentId,
            collectionSchedule: _collectionSchedule,
            notes: _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
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
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      color: AppColors.gold, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Assign Rider for Collection',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        color: Colors.white60, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingRiders)
                    const Center(child: CircularProgressIndicator())
                  else if (_riders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: const Text('No available riders at the moment.',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 13)),
                    )
                  else ...[
                    const Text('Select Rider *',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedRiderId,
                          isExpanded: true,
                          hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Choose a rider...',
                                  style: TextStyle(
                                      color: AppColors.textTertiary))),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          borderRadius: BorderRadius.circular(8),
                          items: _riders.map((r) {
                            final name =
                                '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}';
                            final plate =
                                r['rider_profile']?['plate_number'] ?? '';
                            return DropdownMenuItem<String>(
                                value: r['id'] as String,
                                child: Text('$name — $plate'));
                          }).toList(),
                          onChanged: (v) =>
                              setState(() => _selectedRiderId = v),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pickDateTime,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Text(
                            _collectionSchedule != null
                                ? '${_collectionSchedule!.day}/${_collectionSchedule!.month}/${_collectionSchedule!.year} ${_collectionSchedule!.hour.toString().padLeft(2, '0')}:${_collectionSchedule!.minute.toString().padLeft(2, '0')}'
                                : 'Collection Schedule (optional)',
                            style: TextStyle(
                                color: _collectionSchedule != null
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                      controller: _notesCtrl,
                      label: 'Notes (optional)',
                      maxLines: 2,
                      maxLength: 255),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3))),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13)),
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
                              child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppButton(
                              label: 'Assign Rider',
                              onPressed: _loading ? null : _submit,
                              isLoading: _loading,
                              color: AppColors.deepNavy)),
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
}
