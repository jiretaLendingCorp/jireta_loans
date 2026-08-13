// lib/presentation/shared/widgets/offline_toast.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Centered "No Internet Connection" toast, matching the login page's
/// offline-banner look (light red container + border + spinner + text).
/// Used both by the global [ConnectivityOverlay] and the splash screen so the
/// offline state looks identical everywhere.
class OfflineToast extends StatelessWidget {
  const OfflineToast({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.error,
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
