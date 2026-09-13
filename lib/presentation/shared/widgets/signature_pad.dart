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

  /// Kapag false, text-only ang Clear/Confirm (walang X/check icons).
  final bool showActionIcons;

  /// Tinatawag LANG kapag pinindot ang Confirm at may laman ang pad — para
  /// maipakita ng screen ang panandaliang "Signature confirmed" feedback na
  /// hindi kasama sa onSignatureChanged (na tumatakbo rin sa Clear).
  final VoidCallback? onConfirmed;

  /// Tinatawag LANG kapag pinindot ang Clear — para maitago agad ng screen
  /// ang "Signature confirmed" feedback.
  final VoidCallback? onCleared;

  const SignaturePad({
    super.key,
    this.onSigned,
    this.onSignatureChanged,
    this.height = 200,
    this.showActionIcons = true,
    this.onConfirmed,
    this.onCleared,
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
    widget.onConfirmed?.call();
  }

  void _onClear() {
    _ctrl.clear();
    _notify(null);
    widget.onCleared?.call();
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
            // Walang "Sign here" placeholder — malinis na canvas.
            child: Signature(
              controller: _ctrl,
              backgroundColor: Colors.white,
              width: double.infinity,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            widget.showActionIcons
                ? TextButton.icon(
                    onPressed: _onClear,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.error),
                  )
                : TextButton(
                    onPressed: _onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear',
                        style: TextStyle(fontSize: 12)),
                  ),
            const SizedBox(width: 8),
            widget.showActionIcons
                ? ElevatedButton.icon(
                    onPressed: _onSave,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Confirm'),
                  ),
          ],
        ),
      ],
    );
  }
}
