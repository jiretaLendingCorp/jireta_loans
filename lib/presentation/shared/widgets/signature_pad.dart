// lib/presentation/shared/widgets/signature_pad.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../../../core/theme/app_colors.dart';

class SignaturePad extends StatefulWidget {
  final Function(Uint8List? bytes)? onSigned;
  final ValueChanged<String?>? onSignatureChanged;
  final double height;

  const SignaturePad({
    super.key,
    this.onSigned,
    this.onSignatureChanged,
    this.height = 200,
  });

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final SignatureController _ctrl = SignatureController(
    penStrokeWidth: 2,
    penColor: AppColors.deepNavy,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _notify(Uint8List? bytes) {
    final signed = widget.onSigned;
    if (signed != null) {
      signed(bytes);
      return;
    }
    widget.onSignatureChanged?.call(bytes == null ? null : base64Encode(bytes));
  }

  Future<void> _onSave() async {
    if (_ctrl.isEmpty) return;
    final bytes = await _ctrl.toPngBytes();
    _notify(bytes);
  }

  void _onClear() {
    _ctrl.clear();
    _notify(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Signature(
                  controller: _ctrl,
                  backgroundColor: Colors.white,
                  width: double.infinity,
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Text(
                    'Sign here',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _onClear,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _onSave,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Confirm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
