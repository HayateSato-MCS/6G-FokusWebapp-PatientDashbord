import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../config.dart';

/// Mobile, desktop and plain Dart: WebSocket (`wss://host`, port 443) by
/// default, or plain TCP to a hostname when `useWebSocket` is false.
MqttClient createPlatformClient(MqttSettings settings, String clientId) =>
    MqttServerClient.withPort(settings.serverUrl, clientId, settings.port)
      ..useWebSocket = settings.useWebSocket;
