import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:fall_dashboard/fall_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent possible(String patient, String? observation) => FallEvent.fromMqtt(
      topic: 'fall/possible/$patient',
      payload: jsonEncode({
        'patient_id': patient,
        // ignore: use_null_aware_elements (keeps the tests runnable before Dart 3.8)
        if (observation != null) 'observation_id': observation,
        'fall_detected': true,
      }),
    )!;

FallEvent alert(String patient, String observation, String confirmed, bool? needsHelp) =>
    FallEvent.fromMqtt(
      topic: 'fall/alert/$patient',
      payload: jsonEncode({
        'patient_id': patient,
        'observation_id': observation,
        'fall_detected': true,
        'patient_confirmed': confirmed,
        'needs_help': needsHelp,
      }),
    )!;

void main() {
  test('possible fall, then "no": pending -> resolved -> cleared after 8 s', () {
    fakeAsync((async) {
      final controller = AlertController();
      controller.handleEvent(possible('p1', 'o1'));
      expect(controller.stateFor('p1')!.kind, PatientAlertKind.pending);

      controller.handleEvent(alert('p1', 'o1', 'no', null));
      expect(controller.stateFor('p1')!.kind, PatientAlertKind.resolved);
      expect(controller.stateFor('p1')!.notice, 'Patient reported no fall');

      async.elapse(const Duration(seconds: 7));
      expect(controller.stateFor('p1'), isNotNull);
      async.elapse(const Duration(seconds: 2));
      expect(controller.stateFor('p1'), isNull);
      controller.dispose();
    });
  });

  test('"yes" without help is resolved with its own text', () {
    final controller = AlertController();
    controller.handleEvent(alert('p1', 'o1', 'yes', false));
    expect(controller.stateFor('p1')!.notice, 'Fall confirmed, patient is okay');
    controller.dispose();
  });

  test('help requested: alert stays until acknowledged', () {
    fakeAsync((async) {
      final controller = AlertController();
      controller.handleEvent(possible('p1', 'o1'));
      controller.handleEvent(alert('p1', 'o1', 'yes', true));
      final state = controller.stateFor('p1')!;
      expect(state.kind, PatientAlertKind.alert);
      expect(state.notice, 'Fall is confirmed');
      expect(state.overlay, 'Help is requested');

      async.elapse(const Duration(minutes: 10));
      expect(controller.stateFor('p1')!.kind, PatientAlertKind.alert);

      controller.acknowledge('p1');
      expect(controller.stateFor('p1'), isNull);
      controller.dispose();
    });
  });

  test('no answer: "Patient did not respond" alert', () {
    final controller = AlertController();
    controller.handleEvent(alert('p1', 'o1', 'not_answered', null));
    final state = controller.stateFor('p1')!;
    expect(state.kind, PatientAlertKind.alert);
    expect(state.notice, 'Patient did not respond');
    expect(state.overlay, 'Check on patient');
    controller.dispose();
  });

  test('a later "no" does not hide an unacknowledged alert', () {
    final controller = AlertController();
    controller.handleEvent(alert('p1', 'o1', 'yes', true));
    controller.handleEvent(possible('p1', 'o2'));
    expect(controller.stateFor('p1')!.kind, PatientAlertKind.alert);
    controller.handleEvent(alert('p1', 'o2', 'no', null));
    expect(controller.stateFor('p1')!.kind, PatientAlertKind.alert);
    controller.dispose();
  });

  test('possible fall without a follow-up clears after 60 s', () {
    fakeAsync((async) {
      final controller = AlertController();
      controller.handleEvent(possible('p1', 'o1'));
      controller.handleEvent(possible('p1', null)); // no observation_id
      async.elapse(const Duration(seconds: 59));
      expect(controller.stateFor('p1')!.kind, PatientAlertKind.pending);
      async.elapse(const Duration(seconds: 2));
      expect(controller.stateFor('p1'), isNull);
      controller.dispose();
    });
  });

  test('patients are independent', () {
    final controller = AlertController();
    controller.handleEvent(alert('p1', 'o1', 'yes', true));
    controller.handleEvent(possible('p2', 'o2'));
    expect(controller.stateFor('p1')!.kind, PatientAlertKind.alert);
    expect(controller.stateFor('p2')!.kind, PatientAlertKind.pending);
    expect(controller.stateFor('p3'), isNull);
    expect(controller.patientsWithAlert, ['p1']);
    controller.dispose();
  });

  test('notifications: one per state change, none for a suppressed "no"', () {
    fakeAsync((async) {
      final controller = AlertController();
      final kinds = <PatientAlertKind>[];
      controller.notifications.listen((n) => kinds.add(n.state.kind));

      controller.handleEvent(possible('p1', 'o1'));
      controller.handleEvent(alert('p1', 'o1', 'yes', true));
      controller.handleEvent(possible('p1', 'o2'));
      controller.handleEvent(alert('p1', 'o2', 'no', null)); // alert still up
      controller.acknowledge('p1');
      controller.handleEvent(alert('p1', 'o3', 'no', null));
      async.flushMicrotasks();

      expect(kinds, [
        PatientAlertKind.pending,
        PatientAlertKind.alert,
        PatientAlertKind.pending,
        PatientAlertKind.resolved,
      ]);
      controller.dispose();
    });
  });
}
