// lib/presentation/shared/widgets/pii_mask_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';

enum PiiType { name, phone, gcash, email }

class PiiMaskWidget extends StatefulWidget {
  final String value;
  final PiiType type;
  final TextStyle? style;

  const PiiMaskWidget({
    super.key,
    required this.value,
    required this.type,
    this.style,
  });

  @override
  State<PiiMaskWidget> createState() => _PiiMaskWidgetState();
}

class _PiiMaskWidgetState extends State<PiiMaskWidget> {
  bool _revealed = false;

  String get _masked {
    switch (widget.type) {
      case PiiType.name:
        return AppFormatters.maskName(widget.value);
      case PiiType.phone:
        return AppFormatters.maskPhone(widget.value);
      case PiiType.gcash:
        return AppFormatters.maskGcash(widget.value);
      case PiiType.email:
        final parts = widget.value.split('@');
        if (parts.length != 2) return widget.value;
        final name = parts[0];
        return '${name.length > 2 ? '${name.substring(0, 2)}****' : name}@${parts[1]}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _revealed ? widget.value : _masked,
            style: widget.style ??
                const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
          ),
          const SizedBox(width: 4),
          Icon(
            _revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 14,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
