import 'package:mqtt_client/mqtt_client.dart';

import '../../config.dart';

MqttClient createPlatformClient(MqttSettings settings, String clientId) =>
    throw UnsupportedError('No MQTT client available on this platform');
