// lib/presentation/features/head_manager/ci/widgets/ci_assign_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/forms/app_date_picker.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_ci_provider.dart';

class CiAssignModal extends ConsumerStatefulWidget {
  final String loanId;
  const CiAssignModal({super.key, required this.loanId});

  @override
  ConsumerState<CiAssignModal> createState() => _CiAssignModalState();
}

class _CiAssignModalState extends ConsumerState<CiAssignModal> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _deadline;
  bool _loading = false;
  bool _loadingRiders = true;
  List<Map<String, dynamic>> _riders = [];
  String? _error;
  final GlobalKey _riderKey = GlobalKey();

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
    } catch (e) {
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
    if (_deadline == null) {
      setState(() => _error = 'Please select an investigation deadline');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await ref.read(hmCiProvider.notifier).assignCI(
            loanId: widget.loanId,
            riderId: _selectedRiderId!,
            notes: _notesCtrl.text.trim(),
            deadline: _deadline,
          );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _loading = false;
          _error = 'Failed to assign rider. Please try again.';
        });
      }
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
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 520,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F2F5),
          borderRadius: BorderRadius.zero,
          boxShadow: [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRiderPicker(),
                      const SizedBox(height: 16),
                      AppDatePicker(
                        label: 'Investigation Deadline *',
                        value: _deadline,
                        onChanged: (d) => setState(() => _deadline = d),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _notesCtrl,
                        label: 'Investigation Notes (optional)',
                        hint: 'Instructions for the rider...',
                        maxLines: 3,
                        maxLength: 255,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.zero,
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
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                side: const BorderSide(
                                    color: AppColors.deepNavy),
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero),
                              ),
                              child: const Text('Cancel',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.deepNavy)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.deepNavy,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.deepNavy
                                    .withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Text('Assign Rider',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.manage_search_rounded,
                color: AppColors.gold, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Assign Rider for Credit Investigation',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Close',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderPicker() {
    if (_loadingRiders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_riders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'No available riders at the moment.',
          style: TextStyle(color: AppColors.warning, fontSize: 13),
        ),
      );
    }
    String? selectedName;
    if (_selectedRiderId != null) {
      final sel = _riders.where((r) => r['id'] == _selectedRiderId).toList();
      if (sel.isNotEmpty) {
        selectedName =
            '${sel.first['first_name'] ?? ''} ${sel.first['last_name'] ?? ''}'
                .trim();
      }
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
          key: _riderKey,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.zero,
          ),
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InkWell(
            onTap: _pickRider,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedName ?? 'Choose a rider...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selectedName != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selectedName != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down_rounded,
                    color: AppColors.textSecondary, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRider() async {
    if (_loadingRiders || _riders.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = _riderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height,
        pos.dx + box.size.width,
        pos.dy + box.size.height,
      ),
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      color: const Color(0xFFF0F2F5),
      elevation: 4,
      items: _riders.map((r) {
        final firstName = r['first_name'] ?? '';
        final lastName = r['last_name'] ?? '';
        return PopupMenuItem<String>(
          value: r['id'] as String,
          child: Row(
            children: [
              if (r['id'] == _selectedRiderId) ...[
                const Icon(Icons.check_rounded,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text('$firstName $lastName',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList(),
    );
    if (value != null && mounted) {
      setState(() => _selectedRiderId = value);
    }
  }
}
