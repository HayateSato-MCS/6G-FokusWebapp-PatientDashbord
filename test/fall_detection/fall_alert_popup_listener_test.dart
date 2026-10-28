import 'dart:convert';

import 'package:dca/src/fall_detection/fall_detection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent event(String topic, [Map<String, Object?> extra = const {}]) => FallEvent.fromMqtt(
      topic: topic,
      payload: jsonEncode({
        'patient_id': 'p1',
        'observation_id': 'obs-1',
        'fall_detected': true,
        'timestamp': '2026-10-28T17:00:00Z',
        ...extra,
      }),
    )!;

void main() {
  late AlertController controller;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = AlertController();
    addTearDown(controller.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => FallAlertPopupListener(
        controller: controller,
        navigatorKey: navigatorKey,
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('page'))),
    ));
  }

  testWidgets('possible fall: banner at the top; a caregiver alert replaces it with the dialog',
      (tester) async {
    await pumpApp(tester);

    controller.handleEvent(event('fall/possible/p1'));
    await tester.pumpAndSettle();
    final banner = find.textContaining('Möglicher Sturz: p1');
    expect(banner, findsOneWidget);
    expect(tester.getTopLeft(banner).dy, lessThan(100), reason: 'banner sits at the top');

    controller.handleEvent(event('fall/alert/p1', {'patient_confirmed': 'not_answered'}));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(find.text('Patient:in reagiert nicht'), findsOneWidget);

    await tester.tap(find.text('Quittieren'));
    await tester.pumpAndSettle();
    expect(find.text('Patient:in reagiert nicht'), findsNothing);
  });

  testWidgets('green banner closes by itself after the resolved time', (tester) async {
    await pumpApp(tester);

    controller.handleEvent(event('fall/possible/p1'));
    await tester.pumpAndSettle();
    controller.handleEvent(event('fall/alert/p1', {'patient_confirmed': 'no'}));
    await tester.pumpAndSettle();
    final green = find.textContaining('Patient:in meldet keinen Sturz');
    expect(green, findsOneWidget);
    expect(find.textContaining('Möglicher Sturz'), findsNothing, reason: 'one banner at a time');

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(green, findsNothing);
  });

  testWidgets('the close button removes the banner', (tester) async {
    await pumpApp(tester);

    controller.handleEvent(event('fall/possible/p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Möglicher Sturz'), findsNothing);

    // Closing the banner doesn't change the alert state; clear the 60 s
    // pending timer so the test ends without timers.
    controller.acknowledge('p1');
  });
}
