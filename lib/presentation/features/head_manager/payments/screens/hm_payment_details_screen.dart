// lib/presentation/features/head_manager/payments/screens/hm_payment_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../widgets/payment_details_modal.dart';

/// Full-page payment details — deep link ito ng `/hm/payments/:id` (hal. FCM
/// notification). Ang body ay pareho ng modal na binubuksan ng View action sa
/// Payments/Collections tables: [HmPaymentDetailsContent].
class HmPaymentDetailsScreen extends ConsumerWidget {
  final String paymentId;
  const HmPaymentDetailsScreen({super.key, required this.paymentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebScaffold(
      title: 'Payment Details',
      body: HmPaymentDetailsContent(paymentId: paymentId, onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteConstants.hmPayments);
        }
      }),
    );
  }
}
