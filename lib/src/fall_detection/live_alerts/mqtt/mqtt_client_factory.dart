import 'package:mqtt_client/mqtt_client.dart';

import '../../config.dart';
import 'mqtt_client_factory_stub.dart'
    if (dart.library.io) 'mqtt_client_factory_io.dart'
    if (dart.library.js_interop) 'mqtt_client_factory_web.dart' as platform;

/// Creates the right MQTT client for the platform: a browser WebSocket client
/// on Flutter web, a server client (WebSocket or TCP) everywhere else.
MqttClient createMqttClient(MqttSettings settings, String clientId) =>
    platform.createPlatformClient(settings, clientId);
