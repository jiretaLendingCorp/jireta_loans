// lib/presentation/shared/widgets/dialogs/loading_dialog.dart
//
// Maliit na loading modal na NAKA-CENTER sa screen: puting box na may spinner
// at text (default na "Loading…").
//
// Ito ang ginagamit sa maiikling operation kung saan kailangang makita ng user
// na may nangyayari (hal. pag-save o pag-reset ng MPIN) — imbes na maliit na
// spinner na nakalagay sa ibaba ng screen.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Ang visual na loading box (spinner + text) na ipinapakita sa gitna ng app.
class LoadingDialog extends StatelessWidget {
  const LoadingDialog({super.key, this.text = 'Loading…'});

  /// Ang text sa tabi ng spinner.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 14),
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ang function na isinasauli ng [showLoadingOverlay] — ito ang magsasara sa
/// modal.
typedef DismissLoadingOverlay = void Function();

/// Ipinapakita ang [LoadingDialog] sa GITNA ng screen.
///
/// Ang ibinabalik na function ang magsasara nito; ligtas itong tawagin kahit
/// ilang beses (minsan lang talaga magsasara).
DismissLoadingOverlay showLoadingOverlay(
  BuildContext context, {
  String text = 'Loading…',
}) {
  final nav = Navigator.of(context, rootNavigator: true);
  var visible = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(text: text),
    ).whenComplete(() => visible = false),
  );
  return () {
    if (!visible) return;
    visible = false;
    nav.pop();
  };
}
