import 'dart:convert';

import 'package:fall_dashboard/fall_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = MqttSettings(serverUrl: 'wss://broker.test');

void main() {
  test('each instance gets its own client ID with the configured prefix', () {
    final a = FallMqttService(settings);
    final b = FallMqttService(settings);
    expect(a.clientId, startsWith('fall-dashboard-ui-'));
    expect(a.clientId, isNot(b.clientId));
  });

  test('handleMessage emits parsed fall events and drops the rest', () async {
    final service = FallMqttService(settings);
    final received = <FallEvent>[];
    final subscription = service.events.listen(received.add);

    service.handleMessage(
        'fall/possible/p1', jsonEncode({'patient_id': 'p1', 'fall_detected': true}));
    service.handleMessage('fall/alert/p1', jsonEncode({'patient_id': 'p1', 'fall_detected': false}));
    service.handleMessage('fall/alert/p1',
        jsonEncode({'patient_id': 'p1', 'fall_detected': true, 'patient_confirmed': 'no'}));
    await Future<void>.delayed(Duration.zero);

    expect(received.map((e) => e.status),
        [FallEventStatus.pending, FallEventStatus.confirmed]);
    await subscription.cancel();
    await service.dispose();
  });

  test('ack payload format', () {
    final payload = FallMqttService.buildAckPayload(
        'obs-1', DateTime.utc(2026, 10, 21, 8, 0, 0, 123, 456));
    expect(jsonDecode(payload), {
      'observation_id': 'obs-1',
      'received_at': '2026-10-21T08:00:00.123Z',
    });
  });

  test('publishing acks is off by default', () {
    expect(settings.publishAcks, isFalse);
  });
}
