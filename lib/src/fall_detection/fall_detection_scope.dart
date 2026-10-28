import 'dart:async';

import 'package:flutter/material.dart';

import '../environment.dart';
import 'config.dart';
import 'fall_counts_provider.dart';
import 'fall_history/influx_fall_repository.dart';
import 'live_alerts/alert_controller.dart';
import 'live_alerts/fall_event.dart';
import 'live_alerts/fall_mqtt_service.dart';
import 'live_alerts/widgets/fall_alert_popup_listener.dart';

/// Everything the fall features need, created once per running app (each
/// browser tab is one). Don't create it inside a widget that rebuilds.
class FallDetectionServices {
  FallDetectionServices({
    required this.mqtt,
    required this.alerts,
    required this.repository,
    FallCountsProvider? counts,
    this.countsRefreshDelay = const Duration(seconds: 3),
  }) : counts = counts ?? FallCountsProvider(repository);

  /// Uses the `--dart-define` values in [MCSDashboardEnvironment].
  factory FallDetectionServices.fromEnvironment() => FallDetectionServices(
        mqtt: FallMqttService(const MqttSettings(
          serverUrl: MCSDashboardEnvironment.mqttUrl,
          port: MCSDashboardEnvironment.mqttPort,
          username: MCSDashboardEnvironment.mqttUsername,
          password: MCSDashboardEnvironment.mqttPassword,
          clientIdPrefix: 'patient-dashboard', // a random suffix is added
          // publishAcks stays false: every open screen would answer.
        )),
        alerts: AlertController(),
        repository: InfluxFallRepository(const InfluxSettings(
          url: MCSDashboardEnvironment.influxDBHost,
          org: MCSDashboardEnvironment.influxDBOrg,
          bucket: MCSDashboardEnvironment.influxDBBucket,
          token: MCSDashboardEnvironment.influxDBAPIToken,
        )),
      );

  final FallMqttService mqtt;
  final AlertController alerts;
  final InfluxFallRepository repository;
  final FallCountsProvider counts;

  /// The mobile app writes `fall_events` a moment after the answer, so
  /// counts are reloaded this long after each answered fall.
  final Duration countsRefreshDelay;

  final _answered = StreamController<String>.broadcast();
  final List<StreamSubscription<FallEvent>> _subscriptions = [];
  final Set<Timer> _refreshTimers = {};

  /// Patient IDs of answered falls, [countsRefreshDelay] after the answer,
  /// i.e. when the new `fall_events` row should be readable.
  Stream<String> get answeredFalls => _answered.stream;

  void start() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(alerts.attach(mqtt.events))
      ..add(mqtt.events.where((event) => !event.isPending).listen(_onAnswered));
    mqtt.start();
    counts.start();
  }

  void _onAnswered(FallEvent event) {
    // One timer per answer, so two patients answering close together both
    // get their refresh. FallCountsProvider merges overlapping reloads.
    late final Timer timer;
    timer = Timer(countsRefreshDelay, () {
      _refreshTimers.remove(timer);
      counts.reload();
      if (!_answered.isClosed) _answered.add(event.patientId);
    });
    _refreshTimers.add(timer);
  }

  Future<void> dispose() async {
    for (final timer in _refreshTimers) {
      timer.cancel();
    }
    _refreshTimers.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await mqtt.dispose();
    alerts.dispose();
    counts.dispose();
    repository.close();
    await _answered.close();
  }
}

/// Makes [FallDetectionServices] available below it and shows the fall
/// popups on every page.
///
/// Put it in `MaterialApp.builder` (above the Navigator, so it covers every
/// route and dialog) and pass the app's navigator key. A host app that
/// embeds this dashboard does the same in its own `MaterialApp.builder`.
class FallDetectionScope extends StatelessWidget {
  const FallDetectionScope({
    super.key,
    required this.services,
    required this.child,
    this.navigatorKey,
    this.patientLabel,
    this.onOpenPatient,
  });

  final FallDetectionServices services;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final String Function(String patientId)? patientLabel;
  final void Function(String patientId)? onOpenPatient;

  /// The services, or null when no scope is above [context] (the fall
  /// widgets then show nothing).
  static FallDetectionServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FallDetectionInherited>()?.services;

  @override
  Widget build(BuildContext context) => _FallDetectionInherited(
        services: services,
        child: FallAlertPopupListener(
          controller: services.alerts,
          navigatorKey: navigatorKey,
          patientLabel: patientLabel,
          onOpenPatient: onOpenPatient,
          child: child,
        ),
      );
}

class _FallDetectionInherited extends InheritedWidget {
  const _FallDetectionInherited({required this.services, required super.child});

  final FallDetectionServices services;

  @override
  bool updateShouldNotify(_FallDetectionInherited oldWidget) => services != oldWidget.services;
}
