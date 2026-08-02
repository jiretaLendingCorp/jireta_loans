// lib/presentation/features/auth/widgets/otp_input_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

class OtpInputWidget extends StatefulWidget {
  final int length;
  final Function(String) onCompleted;
  final Function(String)? onChange;
  final bool hasError;

  const OtpInputWidget({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChange,
    this.hasError = false,
  });

  @override
  State<OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<OtpInputWidget> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length == 1 && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (value.length > 1) {
      for (int i = 0; i < widget.length && i < value.length; i++) {
        _controllers[i].text = value[i];
      }
    }

    final otp = _controllers.map((c) => c.text).join();
    widget.onChange?.call(otp);
    if (otp.length == widget.length) {
      widget.onCompleted(otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 48,
          height: 56,
          child: TextFormField(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: widget.hasError
                  ? AppColors.errorLight
                  : AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.hasError ? AppColors.error : AppColors.border,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.hasError ? AppColors.error : AppColors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.hasError ? AppColors.error : AppColors.deepNavy,
                  width: 2,
                ),
              ),
            ),
            onChanged: (val) => _onChanged(val, i),
          ),
        );
      }),
    );
  }
}
