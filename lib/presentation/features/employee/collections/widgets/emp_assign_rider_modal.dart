// lib/presentation/features/employee/collections/widgets/emp_assign_rider_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/forms/app_dropdown.dart';
import '../../../../shared/widgets/forms/app_date_picker.dart';
import '../providers/emp_collection_provider.dart';

class EmpAssignRiderModal extends ConsumerStatefulWidget {
  final String loanScheduleId;
  final VoidCallback onAssigned;

  const EmpAssignRiderModal({
    super.key,
    required this.loanScheduleId,
    required this.onAssigned,
  });

  @override
  ConsumerState<EmpAssignRiderModal> createState() =>
      _EmpAssignRiderModalState();
}

class _EmpAssignRiderModalState extends ConsumerState<EmpAssignRiderModal> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _scheduleDate;
  bool _loading = false;
  bool _loadingRiders = true;
  List<Map<String, dynamic>> _riders = [];

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    final riders =
        await ref.read(empCollectionListProvider.notifier).getAvailableRiders();
    setState(() {
      _riders = riders;
      _loadingRiders = false;
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedRiderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a rider.')));
      return;
    }
    setState(() => _loading = true);
    final ok = await ref.read(empCollectionListProvider.notifier).assign(
          loanScheduleId: widget.loanScheduleId,
          riderId: _selectedRiderId!,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          schedule: _scheduleDate?.toIso8601String(),
        );
    setState(() => _loading = false);
    if (ok && mounted) {
      Navigator.of(context).pop();
      widget.onAssigned();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to assign rider. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      color: AppColors.deepNavy),
                  const SizedBox(width: 10),
                  const Text('Assign Rider for Collection',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loadingRiders)
                const Center(child: CircularProgressIndicator())
              else ...[
                AppDropdown<String>(
                  label: 'Select Available Rider *',
                  value: _selectedRiderId,
                  items: _riders
                      .map((r) => DropdownMenuItem<String>(
                            value: r['id'] as String,
                            child: Text(
                                '${r['full_name'] ?? '-'} — ${r['vehicle_type'] ?? ''}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedRiderId = v;
                  }),
                ),
                const SizedBox(height: 14),
                AppDatePicker(
                  label: 'Collection Schedule',
                  selectedDate: _scheduleDate,
                  onDateSelected: (d) => setState(() => _scheduleDate = d),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _notesCtrl,
                  label: 'Collection Notes (optional)',
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading || _loadingRiders ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Assign Rider'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
