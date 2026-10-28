import 'dart:convert';

import 'package:dca/src/fall_detection/fall_detection.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent? parse(String topic, Map<String, Object?> payload) =>
    FallEvent.fromMqtt(topic: topic, payload: jsonEncode(payload));

Map<String, Object?> alertPayload(Object? confirmed, Object? needsHelp) => {
      'patient_id': 'p1',
      'observation_id': 'obs-1',
      'fall_detected': true,
      'confidence': 0.91,
      'model_version': 'v3',
      'timestamp': '2026-10-21T08:00:00.123Z',
      'patient_confirmed': confirmed,
      'needs_help': needsHelp,
    };

void main() {
  test('fall/possible becomes a pending event without caregiver alert', () {
    final event = parse('fall/possible/p1', {
      'patient_id': 'p1',
      'observation_id': 'obs-1',
      'fall_detected': true,
      'confidence': 0.91,
    })!;
    expect(event.status, FallEventStatus.pending);
    expect(event.patientConfirmed, isNull);
    expect(event.caregiverAlert, isFalse);
    expect(event.observationId, 'obs-1');
    expect(event.confidence, 0.91);
  });

  group('caregiver alert rule', () {
    final cases = <(Object?, Object?, int, bool)>[
      ('not_answered', null, -1, true),
      ('yes', true, 1, true),
      ('yes', false, 1, false),
      ('yes', null, 1, false),
      ('no', null, 0, false),
      (null, null, -1, true), // missing answer counts as not answered
      ('yes', 'true', 1, false), // needs_help must be a real boolean
      (1, true, 1, true), // int encoding is accepted too
    ];
    for (final (confirmed, needsHelp, expectedInt, expectedAlert) in cases) {
      test('patient_confirmed=$confirmed needs_help=$needsHelp', () {
        final event = parse('fall/alert/p1', alertPayload(confirmed, needsHelp))!;
        expect(event.status, FallEventStatus.confirmed);
        expect(event.patientConfirmed, expectedInt);
        expect(event.caregiverAlert, expectedAlert);
      });
    }
  });

  test('messages that are not falls are ignored', () {
    expect(parse('fall/alert/p1', {'patient_id': 'p1', 'fall_detected': false}), isNull);
    expect(parse('fall/alert/p1', {'patient_id': 'p1'}), isNull);
    expect(parse('fall/ack/p1', {'patient_id': 'p1', 'fall_detected': true}), isNull);
    expect(FallEvent.fromMqtt(topic: 'fall/alert/p1', payload: 'not json'), isNull);
    expect(FallEvent.fromMqtt(topic: 'fall/alert/p1', payload: '[1,2]'), isNull);
  });

  test('patient_id falls back to the topic when missing from the payload', () {
    final event = parse('fall/alert/from_topic', {'fall_detected': true})!;
    expect(event.patientId, 'from_topic');
  });

  test('detection timestamp is parsed as UTC, with or without a zone', () {
    final withZone = parse('fall/alert/p1', alertPayload('no', null))!;
    expect(withZone.detectionTime, DateTime.utc(2026, 10, 21, 8, 0, 0, 123));

    final naive = parse('fall/alert/p1', {
      ...alertPayload('no', null),
      'timestamp': '2026-10-21T08:00:00',
    })!;
    expect(naive.detectionTime, DateTime.utc(2026, 10, 21, 8));
  });

  test('epoch timestamps (seconds or ms, number or text) and alert_time fallback', () {
    final expected = DateTime.utc(2026, 10, 28, 17);
    final seconds = expected.millisecondsSinceEpoch ~/ 1000;
    Map<String, Object?> withTime(Object? timestamp, [Object? alertTime]) {
      final payload = {...alertPayload('not_answered', null), 'timestamp': timestamp};
      if (alertTime != null) payload['alert_time'] = alertTime;
      return payload;
    }

    expect(parse('fall/alert/p1', withTime(seconds))!.detectionTime, expected);
    expect(parse('fall/alert/p1', withTime(seconds * 1000))!.detectionTime, expected);
    expect(parse('fall/alert/p1', withTime('$seconds'))!.detectionTime, expected);
    expect(
      parse('fall/alert/p1', withTime(null, '2026-10-28T17:00:00Z'))!.detectionTime,
      expected,
    );

    final noTime = parse('fall/alert/p1', withTime(null))!;
    expect(noTime.detectionTime, isNull);
    expect(noTime.receivedAt, isNotNull);
  });
}
