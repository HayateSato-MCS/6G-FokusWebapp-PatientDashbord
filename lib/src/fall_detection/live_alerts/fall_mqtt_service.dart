import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';

import '../config.dart';
import '../core/time_utils.dart';
import 'fall_event.dart';
import 'mqtt/mqtt_client_factory.dart';

/// State of the broker connection, for a "Live status" indicator.
enum MqttLinkState { disconnected, connecting, connected, reconnecting }

typedef MqttClientFactory = MqttClient Function(MqttSettings settings, String clientId);

/// Subscribes to `fall/possible/#` and `fall/alert/#` and emits each fall
/// message as a [FallEvent].
///
/// Every running app instance subscribes to the broker itself, which is why
/// [clientId] gets a random suffix per instance.
///
/// Pure Dart (no Flutter import), so it also runs in tools and tests.
class FallMqttService {
  FallMqttService(
    this.settings, {
    MqttClientFactory? clientFactory,
    String? clientId,
  })  : _clientFactory = clientFactory ?? createMqttClient,
        clientId = clientId ?? '${settings.clientIdPrefix}-${_randomSuffix()}';

  final MqttSettings settings;

  /// Unique per instance. Two clients with the same ID keep disconnecting
  /// each other at the broker.
  final String clientId;
  final MqttClientFactory _clientFactory;

  final _events = StreamController<FallEvent>.broadcast();
  final _linkStates = StreamController<MqttLinkState>.broadcast();
  MqttLinkState _linkState = MqttLinkState.disconnected;
  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  bool _running = false;

  /// Every parsed fall message, pending and confirmed, in arrival order.
  Stream<FallEvent> get events => _events.stream;

  /// Connection state changes. Read [linkState] for the current value.
  Stream<MqttLinkState> get linkStates => _linkStates.stream;
  MqttLinkState get linkState => _linkState;

  /// Starts connecting in the background and retries until connected.
  /// After the first successful connection the client reconnects and
  /// resubscribes by itself. Returns immediately; watch [linkStates].
  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connectLoop());
  }

  /// Disconnects. [start] can be called again afterwards.
  Future<void> stop() async {
    _running = false;
    await _updates?.cancel();
    _updates = null;
    _client?.disconnect();
    _client = null;
    _setLinkState(MqttLinkState.disconnected);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _linkStates.close();
  }

  Future<void> _connectLoop() async {
    var delay = const Duration(seconds: 2);
    while (_running) {
      try {
        await _connectOnce();
        return;
      } catch (error) {
        developer.log(
          'MQTT connect to ${settings.serverUrl}:${settings.port} failed ($error); '
          'retrying in ${delay.inSeconds}s',
          name: 'fall_dashboard.mqtt',
        );
        _setLinkState(MqttLinkState.disconnected);
        await Future<void>.delayed(delay);
        delay = Duration(seconds: min(delay.inSeconds * 2, 30));
      }
    }
  }

  Future<void> _connectOnce() async {
    final client = _clientFactory(settings, clientId)
      ..logging(on: false)
      ..keepAlivePeriod = settings.keepAliveSeconds
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      // Mosquitto expects the single `mqtt` WebSocket subprotocol
      ..websocketProtocols = MqttClientConstants.protocolsSingleDefault
      ..connectionMessage =
          MqttConnectMessage().withClientIdentifier(clientId).startClean();
    client
      ..setProtocolV311()
      ..onConnected = (() => _setLinkState(MqttLinkState.connected))
      ..onDisconnected = (() => _setLinkState(MqttLinkState.disconnected))
      ..onAutoReconnect = (() => _setLinkState(MqttLinkState.reconnecting))
      ..onAutoReconnected = (() => _setLinkState(MqttLinkState.connected));

    _setLinkState(MqttLinkState.connecting);
    try {
      await client.connect(
        settings.username.isEmpty ? null : settings.username,
        settings.password.isEmpty ? null : settings.password,
      );
    } catch (_) {
      client.disconnect();
      rethrow;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker refused the connection: ${client.connectionStatus}');
    }
    if (!_running) {
      client.disconnect();
      return;
    }

    _client = client;
    client
      ..subscribe('${settings.alertTopic}/#', MqttQos.atLeastOnce)
      ..subscribe('${settings.possibleTopic}/#', MqttQos.atLeastOnce);
    _updates = client.updates!.listen(_onMessages);
    _setLinkState(MqttLinkState.connected);
    developer.log(
      'MQTT connected as $clientId; subscribed to ${settings.alertTopic}/# '
      'and ${settings.possibleTopic}/#',
      name: 'fall_dashboard.mqtt',
    );
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final publish = message.payload;
      if (publish is! MqttPublishMessage) continue;
      final payload = utf8.decode(publish.payload.message, allowMalformed: true);
      handleMessage(message.topic, payload);
    }
  }

  /// Parses one message and emits it. Public so tests and tools can feed
  /// messages without a broker. Returns the event, or null if ignored.
  FallEvent? handleMessage(String topic, String payload) {
    final event = FallEvent.fromMqtt(
      topic: topic,
      payload: payload,
      possibleTopic: settings.possibleTopic,
      alertTopic: settings.alertTopic,
    );
    if (event == null) return null;
    if (!event.isPending && settings.publishAcks) _publishAck(event);
    if (!_events.isClosed) _events.add(event);
    return event;
  }

  /// Delivery-time ack: echoes the alert's observation_id straight back to
  /// the mobile app on `fall/ack/<patient_id>`. Off unless
  /// [MqttSettings.publishAcks] is set; the Patient Dashboard keeps it off.
  void _publishAck(FallEvent event) {
    final client = _client;
    if (client == null) return;
    final topicPatient = event.topic.split('/').last;
    final builder = MqttClientPayloadBuilder()
      ..addUTF8String(buildAckPayload(event.observationId, DateTime.now()));
    try {
      client.publishMessage(
        '${settings.ackTopic}/$topicPatient',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    } catch (error) {
      developer.log('Failed to publish ack for $topicPatient: $error',
          name: 'fall_dashboard.mqtt');
    }
  }

  /// `{"observation_id": ..., "received_at": "<UTC ISO, ms>"}`
  static String buildAckPayload(String? observationId, DateTime receivedAt) =>
      jsonEncode({
        'observation_id': observationId,
        'received_at': isoMillisUtc(receivedAt),
      });

  void _setLinkState(MqttLinkState state) {
    if (state == _linkState) return;
    _linkState = state;
    if (!_linkStates.isClosed) _linkStates.add(state);
  }

  static String _randomSuffix() {
    final random = Random.secure();
    return List.generate(4, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
