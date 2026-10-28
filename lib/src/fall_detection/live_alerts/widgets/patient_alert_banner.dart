import 'package:flutter/material.dart';

import '../../ui/fall_colors.dart';
import '../alert_controller.dart';

/// Banner for one patient's tile: shows the current alert state from
/// [AlertController] and nothing when there is none. Drop it into any
/// existing patient widget.
class PatientAlertBanner extends StatelessWidget {
  const PatientAlertBanner({
    super.key,
    required this.controller,
    required this.patientId,
    this.showOverlay = true,
  });

  final AlertController controller;
  final String patientId;

  /// Also show the large "Help is requested" / "Check on patient" line.
  final bool showOverlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.stateFor(patientId);
        if (state == null) return const SizedBox.shrink();
        final (background, foreground) = switch (state.kind) {
          PatientAlertKind.pending => (FallColors.pendingNotice, FallColors.pendingNoticeText),
          PatientAlertKind.alert => (FallColors.alertNotice, FallColors.alertNoticeText),
          PatientAlertKind.resolved => (FallColors.resolvedNotice, FallColors.resolvedNoticeText),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: background,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                state.notice,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            if (showOverlay && state.overlay != null)
              Container(
                color: FallColors.alertOverlay,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: Text(
                  state.overlay!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: FallColors.alertOverlayText,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Card background and border colours for a patient's current alert state,
/// or null when the default should be used.
(Color background, Color border)? alertCardColors(PatientAlertState? state) =>
    switch (state?.kind) {
      PatientAlertKind.pending => (FallColors.pendingCard, FallColors.pendingBorder),
      PatientAlertKind.alert => (FallColors.pendingCard, FallColors.alertBorder),
      PatientAlertKind.resolved => (FallColors.resolvedCard, FallColors.resolvedBorder),
      null => null,
    };
