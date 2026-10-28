import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/fall_colors.dart';
import '../alert_controller.dart';
import '../fall_event.dart';

/// Shows popups for live fall events, on top of whatever page is open.
///
/// * possible fall -> pale red banner at the top, until the patient answers
/// * caregiver alert -> red dialog that must be acknowledged
/// * dismissed by the patient -> green banner at the top for a few seconds
///
/// Banners and dialogs go into the Navigator's overlay, so they appear above
/// every page and above dialogs that are already open (e.g. a date picker).
/// Place it in `MaterialApp.builder` and pass the app's [navigatorKey] (that
/// context sits above the Navigator). Inside a page, the key can be omitted.
class FallAlertPopupListener extends StatefulWidget {
  const FallAlertPopupListener({
    super.key,
    required this.controller,
    required this.child,
    this.navigatorKey,
    this.patientLabel,
    this.onOpenPatient,
  });

  final AlertController controller;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

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
  OverlayEntry? _banner;

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
    _removeBanner();
    super.dispose();
  }

  String _label(String patientId) => widget.patientLabel?.call(patientId) ?? patientId;

  NavigatorState? get _navigator => widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);

  BuildContext? get _dialogContext => _navigator?.overlay?.context;

  void _onNotification(FallAlertNotification notification) {
    if (!mounted) return;
    switch (notification.state.kind) {
      case PatientAlertKind.pending:
        _showBanner(
          text: 'Möglicher Sturz: ${_label(notification.patientId)}. Warte auf Antwort der Patient:in.',
          icon: Icons.warning_amber_rounded,
          background: FallColors.pendingNotice,
          foreground: FallColors.pendingNoticeText,
          border: FallColors.pendingBorder,
          duration: widget.controller.pendingTimeout,
        );
      case PatientAlertKind.resolved:
        _showBanner(
          text: '${_label(notification.patientId)}: ${notification.state.notice}',
          icon: Icons.check_circle_outline,
          background: FallColors.resolvedNotice,
          foreground: FallColors.resolvedNoticeText,
          border: FallColors.resolvedBorder,
          duration: widget.controller.resolvedDisplay,
        );
      case PatientAlertKind.alert:
        _removeBanner();
        _showAlertDialog(notification);
    }
  }

  /// One banner at a time at the top of the window; a new one replaces the old.
  void _showBanner({
    required String text,
    required IconData icon,
    required Color background,
    required Color foreground,
    required Color border,
    required Duration duration,
  }) {
    final overlay = _navigator?.overlay;
    if (overlay == null) return;
    _removeBanner();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopBanner(
        text: text,
        icon: icon,
        background: background,
        foreground: foreground,
        border: border,
        duration: duration,
        onClosed: () {
          if (_banner == entry) _removeBanner();
        },
      ),
    );
    _banner = entry;
    overlay.insert(entry);
  }

  void _removeBanner() {
    _banner?.remove();
    _banner = null;
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

/// Notice that slides in at the top of the window and closes itself after
/// [duration], or earlier with its close button.
class _TopBanner extends StatefulWidget {
  const _TopBanner({
    required this.text,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.border,
    required this.duration,
    required this.onClosed,
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color border;
  final Duration duration;
  final VoidCallback onClosed;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _animation.reverse();
    if (mounted) widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic);
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: SafeArea(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1.5), end: Offset.zero).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Material(
                  color: widget.background,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: widget.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: widget.foreground),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.text,
                            style: TextStyle(color: widget.foreground, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          icon: Icon(Icons.close, color: widget.foreground, size: 20),
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
