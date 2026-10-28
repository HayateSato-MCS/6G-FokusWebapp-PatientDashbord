import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../config.dart';

/// Flutter web: browsers only allow WebSockets, so `serverUrl` must carry the
/// scheme (`wss://host`).
MqttClient createPlatformClient(MqttSettings settings, String clientId) =>
    MqttBrowserClient.withPort(settings.serverUrl, clientId, settings.port);
