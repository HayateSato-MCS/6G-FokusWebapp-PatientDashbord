import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/patient_confirmed.dart';
import 'fall_event.dart';

/// What a patient's tile should show right now.
enum PatientAlertKind {
  /// A possible fall; waiting for the patient's answer. Pale red.
  pending,

  /// The caregiver must act (help requested, or no answer). Red; stays until
  /// [AlertController.acknowledge] is called.
  alert,

  /// The patient dismissed the possible fall. Green; clears by itself.
  resolved,
}

@immutable
class PatientAlertState {
  const PatientAlertState(this.kind, this.notice, {this.overlay});

  final PatientAlertKind kind;

  /// Short banner text, e.g. "Fall is confirmed".
  final String notice;

  /// Large call-to-action text for [PatientAlertKind.alert], e.g.
  /// "Help is requested". Null for the other kinds.
  final String? overlay;
}

/// Emitted once per incoming event that changes what the caregiver sees, so
/// the app can show a popup. Tiles should read [AlertController.stateFor].
@immutable
class FallAlertNotification {
  const FallAlertNotification({
    required this.patientId,
    required this.state,
    required this.event,
  });

  final String patientId;
  final PatientAlertState state;
  final FallEvent event;
}

/// Per-patient alert state for the caregiver UI.
///
/// The rules (see handover/02_live_fall_alerts.md, section 6):
///
/// * `fall/possible` -> [PatientAlertKind.pending]. Cleared after
///   [pendingTimeout] if no `fall/alert` with the same observation_id arrives.
/// * `fall/alert`, caregiver alert -> [PatientAlertKind.alert] until
///   [acknowledge]. "Patient did not respond" when no answer, otherwise
///   "Fall is confirmed".
/// * `fall/alert`, no caregiver alert -> [PatientAlertKind.resolved] for
///   [resolvedDisplay], then nothing. An earlier unacknowledged alert for the
///   same patient stays: a later "no" must not hide it.
class AlertController extends ChangeNotifier {
  AlertController({
    this.pendingTimeout = const Duration(seconds: 60),
    this.resolvedDisplay = const Duration(seconds: 8),
  });

  /// Popup timers are 2 x 10 s, so 60 s is well past any normal answer.
  final Duration pendingTimeout;
  final Duration resolvedDisplay;

  static const pendingNotice = 'Möglicher Sturz, warte auf Bestätigung';

  // observation_id (or a generated key) -> patient_id
  final Map<String, String> _pending = {};
  final Map<String, Timer> _pendingTimers = {};
  final Map<String, PatientAlertState> _alerts = {};
  final Map<String, PatientAlertState> _resolved = {};
  final Map<String, Timer> _resolvedTimers = {};
  final _notifications = StreamController<FallAlertNotification>.broadcast();
  int _keylessPending = 0;
  bool _disposed = false;

  /// One notification per event that changes a patient's state.
  Stream<FallAlertNotification> get notifications => _notifications.stream;

  /// Patients with an unacknowledged caregiver alert.
  Iterable<String> get patientsWithAlert => _alerts.keys;

  /// Current state for one patient, or null when nothing is going on.
  PatientAlertState? stateFor(String patientId) {
    final alert = _alerts[patientId];
    if (alert != null) return alert;
    final resolved = _resolved[patientId];
    if (resolved != null) return resolved;
    if (_pending.containsValue(patientId)) {
      return const PatientAlertState(PatientAlertKind.pending, pendingNotice);
    }
    return null;
  }

  /// Feeds every event from [stream] into [handleEvent].
  StreamSubscription<FallEvent> attach(Stream<FallEvent> stream) =>
      stream.listen(handleEvent);

  void handleEvent(FallEvent event) {
    if (_disposed) return;
    final patientId = event.patientId;

    if (event.isPending) {
      final key = event.observationId ?? 'no-observation-id-${_keylessPending++}';
      _pending[key] = patientId;
      _pendingTimers[key]?.cancel();
      _pendingTimers[key] = Timer(pendingTimeout, () => _expirePending(key));
      _clearResolved(patientId);
      notifyListeners();
      // Announce the new possible fall even if an older alert is still shown
      _emit(event, const PatientAlertState(PatientAlertKind.pending, pendingNotice));
      return;
    }

    if (event.caregiverAlert) {
      final noResponse = event.patientConfirmed == PatientConfirmed.notAnswered;
      final state = PatientAlertState(
        PatientAlertKind.alert,
        noResponse ? 'Patient:in reagiert nicht' : 'Sturz bestätigt',
        overlay: noResponse ? 'Bitte nach Patient:in sehen' : 'Hilfe angefordert',
      );
      _dropPending(patientId);
      _clearResolved(patientId);
      _alerts[patientId] = state;
      notifyListeners();
      _emit(event, state);
      return;
    }

    _dropPending(patientId);
    if (_alerts.containsKey(patientId)) {
      // Keep the earlier, unacknowledged alert visible.
      notifyListeners();
      return;
    }
    final state = PatientAlertState(PatientAlertKind.resolved, resolvedNoticeText(event));
    _resolved[patientId] = state;
    _resolvedTimers[patientId]?.cancel();
    _resolvedTimers[patientId] = Timer(resolvedDisplay, () {
      _clearResolved(patientId);
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    _emit(event, state);
  }

  /// The caregiver has seen the alert (opened the patient, or pressed
  /// "Acknowledge"): clears every state for this patient.
  void acknowledge(String patientId) {
    _dropPending(patientId);
    _alerts.remove(patientId);
    _clearResolved(patientId);
    notifyListeners();
  }

  static String resolvedNoticeText(FallEvent event) {
    if (event.patientConfirmed == PatientConfirmed.no) return 'Patient:in meldet keinen Sturz';
    if (event.patientConfirmed == PatientConfirmed.yes && event.needsHelp == false) {
      return 'Sturz bestätigt, Patient:in ist okay';
    }
    return 'Möglicher Sturz aufgehoben';
  }

  void _expirePending(String key) {
    _pendingTimers.remove(key);
    if (_pending.remove(key) != null && !_disposed) notifyListeners();
  }

  void _dropPending(String patientId) {
    final keys = [
      for (final entry in _pending.entries)
        if (entry.value == patientId) entry.key,
    ];
    for (final key in keys) {
      _pending.remove(key);
      _pendingTimers.remove(key)?.cancel();
    }
  }

  void _clearResolved(String patientId) {
    _resolvedTimers.remove(patientId)?.cancel();
    _resolved.remove(patientId);
  }

  void _emit(FallEvent event, PatientAlertState state) {
    if (_notifications.isClosed) return;
    _notifications.add(
      FallAlertNotification(patientId: event.patientId, state: state, event: event),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in [..._pendingTimers.values, ..._resolvedTimers.values]) {
      timer.cancel();
    }
    _notifications.close();
    super.dispose();
  }
}
