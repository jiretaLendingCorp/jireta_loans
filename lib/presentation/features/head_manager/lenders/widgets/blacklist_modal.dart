// lib/presentation/features/head_manager/lenders/widgets/blacklist_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_lender_provider.dart';

class BlacklistModal extends ConsumerStatefulWidget {
  final String lenderId;
  final String lenderName;
  final bool isBlacklisted;
  const BlacklistModal({
    super.key,
    required this.lenderId,
    required this.lenderName,
    required this.isBlacklisted,
  });

  @override
  ConsumerState<BlacklistModal> createState() => _BlacklistModalState();
}

class _BlacklistModalState extends ConsumerState<BlacklistModal> {
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.isBlacklisted && _reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please provide a reason for blacklisting');
      return;
    }
    if (!_confirmed) {
      setState(() => _error = 'Please confirm the action by checking the box');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.isBlacklisted) {
        await ref.read(hmLenderProvider.notifier).removeBlacklist(widget.lenderId);
      } else {
        await ref.read(hmLenderProvider.notifier).addBlacklist(
          widget.lenderId,
          _reasonCtrl.text.trim(),
        );
      }
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
    final isAdd = !widget.isBlacklisted;
    final color = isAdd ? AppColors.error : AppColors.riderGreen;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(isAdd ? Icons.block_outlined : Icons.check_circle_outline, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAdd ? 'Add to Blacklist' : 'Remove from Blacklist',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.lenderName,
                            style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAdd
                        ? 'Adding this lender to the blacklist will prevent them from applying for loans.'
                        : 'Removing this lender from the blacklist will restore their ability to apply for loans.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  if (isAdd) ...[
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _reasonCtrl,
                      label: 'Reason for Blacklisting *',
                      hint: 'Explain why this lender is being blacklisted...',
                      maxLines: 3,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _confirmed,
                        onChanged: (v) => setState(() => _confirmed = v!),
                        activeColor: color,
                      ),
                      Expanded(
                        child: Text(
                          isAdd
                              ? 'I confirm that I want to blacklist this lender'
                              : 'I confirm that I want to remove this lender from the blacklist',
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: _loading ? null : () => Navigator.of(context).pop(), child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: isAdd ? 'Blacklist' : 'Remove',
                          onPressed: _loading ? null : _submit,
                          isLoading: _loading,
                          color: color,
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
}
