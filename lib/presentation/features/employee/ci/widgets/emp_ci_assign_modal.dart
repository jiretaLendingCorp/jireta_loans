// lib/presentation/features/employee/ci/widgets/emp_ci_assign_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/emp_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpCiAssignModal extends ConsumerStatefulWidget {
  final String loanId;
  final String ciId;

  const EmpCiAssignModal({
    super.key,
    required this.loanId,
    required this.ciId,
  });

  @override
  ConsumerState<EmpCiAssignModal> createState() => _EmpCiAssignModalState();
}

class _EmpCiAssignModalState extends ConsumerState<EmpCiAssignModal> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _deadline;
  bool _isLoading = false;
  List<Map<String, dynamic>> _riders = [];
  bool _loadingRiders = true;

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    final riders = await ref.read(empCiProvider.notifier).getAvailableRiders();
    if (mounted) {
      setState(() {
        _riders = riders
            .where((r) =>
                (r['rider_profiles']?['is_available'] ?? true) == true)
            .toList();
        _loadingRiders = false;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delivery_dining,
                        color: AppColors.deepNavy, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assign Rider for CI',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Assign an available rider for credit investigation',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Select Rider',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingRiders)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_riders.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'No available riders at this time.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedRiderId,
                  decoration: InputDecoration(
                    hintText: 'Choose a rider',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  items: _riders.map((r) {
                    final name =
                        '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'
                            .trim();
                    return DropdownMenuItem(
                      value: r['id'] as String,
                      child: Row(
                        children: [
                          const Icon(Icons.delivery_dining,
                              size: 16, color: AppColors.riderGreen),
                          const SizedBox(width: 8),
                          Text(name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedRiderId = val;
                    });
                  },
                ),
              const SizedBox(height: 16),
              const Text(
                'Investigation Deadline',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDeadline,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _deadline == null
                            ? 'Select deadline (optional)'
                            : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _deadline == null
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Investigation Notes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: 255,
                decoration: InputDecoration(
                  hintText: 'Enter notes for the rider...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedRiderId == null || _isLoading
                          ? null
                          : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Assign Rider'),
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

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.deepNavy),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _deadline = date);
  }

  Future<void> _submit() async {
    if (_selectedRiderId == null) return;
    setState(() => _isLoading = true);

    final ok = await ref.read(empCiProvider.notifier).assign(
          loanId: widget.loanId,
          riderId: _selectedRiderId!,
          notes:
              _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
          deadline: _deadline?.toIso8601String(),
        );

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context, ok);
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
              ok ? 'Rider assigned successfully' : 'Failed to assign rider'),
          backgroundColor: ok ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}
