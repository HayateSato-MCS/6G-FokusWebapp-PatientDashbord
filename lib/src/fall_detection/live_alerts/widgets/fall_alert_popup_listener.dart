import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/fall_colors.dart';
import '../alert_controller.dart';
import '../fall_event.dart';

/// Shows popups for live fall events, on top of whatever page is open.
///
/// * possible fall -> pale red snack bar, until the patient answers
/// * caregiver alert -> red dialog that must be acknowledged
/// * dismissed by the patient -> green snack bar for a few seconds
///
/// Place it in `MaterialApp.builder` and pass the app's [navigatorKey] and
/// [scaffoldMessengerKey] (that context sits above the Navigator, so the keys
/// are needed to show dialogs). Inside a page, the keys can be omitted.
class FallAlertPopupListener extends StatefulWidget {
  const FallAlertPopupListener({
    super.key,
    required this.controller,
    required this.child,
    this.navigatorKey,
    this.scaffoldMessengerKey,
    this.patientLabel,
    this.onOpenPatient,
  });

  final AlertController controller;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Maps a patient ID to the name the caregiver knows. Defaults to the ID.
  final String Function(String patientId)? patientLabel;

  /// Called from the alert dialog's "Open patient" button, after the alert
  /// has been acknowledged.
  final void Function(String patientId)? onOpenPatient;

  @override
  State<FallAlertPopupListener> createState() => _FallAlertPopupListenerState();
}

class _FallAlertPopupListenerState extends State<FallAlertPopupListener> {
  StreamSubscription<FallAlertNotification>? _subscription;
  final Set<String> _openDialogs = {};

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.notifications.listen(_onNotification);
  }

  @override
  void didUpdateWidget(FallAlertPopupListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscription?.cancel();
      _subscription = widget.controller.notifications.listen(_onNotification);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _label(String patientId) => widget.patientLabel?.call(patientId) ?? patientId;

  ScaffoldMessengerState? get _messenger =>
      widget.scaffoldMessengerKey?.currentState ?? ScaffoldMessenger.maybeOf(context);

  BuildContext? get _dialogContext {
    final navigator = widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    return navigator?.overlay?.context;
  }

  void _onNotification(FallAlertNotification notification) {
    if (!mounted) return;
    switch (notification.state.kind) {
      case PatientAlertKind.pending:
        _showSnack(
          'Möglicher Sturz: ${_label(notification.patientId)}. Warte auf Antwort der Patient:in.',
          FallColors.pendingNotice,
          FallColors.pendingNoticeText,
          widget.controller.pendingTimeout,
        );
      case PatientAlertKind.resolved:
        _showSnack(
          '${_label(notification.patientId)}: ${notification.state.notice}',
          FallColors.resolvedNotice,
          FallColors.resolvedNoticeText,
          widget.controller.resolvedDisplay,
        );
      case PatientAlertKind.alert:
        _messenger?.hideCurrentSnackBar();
        _showAlertDialog(notification);
    }
  }

  void _showSnack(String text, Color background, Color foreground, Duration duration) {
    final messenger = _messenger;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
        backgroundColor: background,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _showAlertDialog(FallAlertNotification notification) async {
    final patientId = notification.patientId;
    final dialogContext = _dialogContext;
    // One dialog per patient; a second alert for the same patient updates the tile only.
    if (dialogContext == null || !_openDialogs.add(patientId)) return;

    final open = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        // White and evenly rounded, with the red header clipped to the
        // corners; independent of the app's (purple) theme.
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        title: Container(
          color: FallColors.alertNotice,
          padding: const EdgeInsets.all(16),
          child: Text(
            notification.state.notice,
            style: const TextStyle(color: FallColors.alertNoticeText, fontWeight: FontWeight.w700),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.state.overlay ?? '',
              style: const TextStyle(
                color: FallColors.alertOverlayText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text('Patient:in: ${_label(patientId)}'),
            Text(_timeLine(notification.event)),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: FallColors.textPrimary,
              shape: _buttonShape,
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Quittieren'),
          ),
          if (widget.onOpenPatient != null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FallColors.alertNotice,
                foregroundColor: FallColors.alertNoticeText,
                shape: _buttonShape,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Patient:in öffnen'),
            ),
        ],
      ),
    );

    _openDialogs.remove(patientId);
    widget.controller.acknowledge(patientId);
    if (open == true) widget.onOpenPatient?.call(patientId);
  }

  static final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

  /// "Erkannt: 28.10.2026, 18:40:12" from the payload's detection time, or
  /// the time the message arrived when the payload has none.
  static String _timeLine(FallEvent event) {
    final detected = event.detectionTime;
    final time = (detected ?? event.receivedAt)?.toLocal();
    if (time == null) return 'Erkannt: –';
    String two(int v) => v.toString().padLeft(2, '0');
    final text = '${two(time.day)}.${two(time.month)}.${time.year}, '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return detected != null ? 'Erkannt: $text' : 'Empfangen: $text';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
