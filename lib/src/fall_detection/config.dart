/// Runtime settings for the fall dashboard features.
///
/// The demo app reads them from `--dart-define` values (see README.md), so no
/// broker or InfluxDB credentials live in source code. When integrating into
/// another app, construct [MqttSettings] and [InfluxSettings] directly from
/// that app's own configuration instead.
library;

/// How to reach the MQTT broker that carries `fall/possible` and `fall/alert`.
class MqttSettings {
  const MqttSettings({
    required this.serverUrl,
    this.port = 443,
    this.useWebSocket = true,
    this.username = '',
    this.password = '',
    this.clientIdPrefix = 'fall-dashboard-ui',
    this.alertTopic = 'fall/alert',
    this.possibleTopic = 'fall/possible',
    this.ackTopic = 'fall/ack',
    this.publishAcks = false,
    this.keepAliveSeconds = 30,
  });

  /// Reads `--dart-define` values. Set `MQTT_URL` to your broker; the default
  /// is the hostname recommended in the handover guide.
  factory MqttSettings.fromEnvironment() => const MqttSettings(
        serverUrl: String.fromEnvironment(
          'MQTT_URL',
          defaultValue: 'wss://mqtt.e-healthservice.de',
        ),
        port: int.fromEnvironment('MQTT_PORT', defaultValue: 443),
        useWebSocket: bool.fromEnvironment('MQTT_USE_WEBSOCKET', defaultValue: true),
        username: String.fromEnvironment('MQTT_USERNAME'),
        password: String.fromEnvironment('MQTT_PASSWORD'),
        clientIdPrefix: String.fromEnvironment(
          'MQTT_CLIENT_ID_PREFIX',
          defaultValue: 'fall-dashboard-ui',
        ),
        publishAcks: bool.fromEnvironment('MQTT_PUBLISH_ACKS'),
      );

  /// WebSocket URL including the scheme, e.g. `wss://mqtt.example.org`.
  /// With [useWebSocket] false (non-web platforms only) this is a plain hostname.
  final String serverUrl;
  final int port;

  /// Browsers can only use WebSockets. Plain TCP is for in-cluster use on
  /// mobile/desktop/server builds.
  final bool useWebSocket;
  final String username;
  final String password;

  /// A random suffix is appended per app instance, because two clients with
  /// the same ID keep disconnecting each other at the broker.
  final String clientIdPrefix;

  final String alertTopic;
  final String possibleTopic;
  final String ackTopic;

  /// Whether this instance answers each `fall/alert` with a `fall/ack`
  /// (delivery-time measurement for the mobile app). Keep false in the
  /// Patient Dashboard; see handover/02_live_fall_alerts.md, section 5.4.
  final bool publishAcks;
  final int keepAliveSeconds;
}

/// How to reach the InfluxDB that holds the `fall_events` measurement.
class InfluxSettings {
  const InfluxSettings({
    required this.url,
    required this.org,
    required this.bucket,
    required this.token,
    this.writeFallEvents = false,
  });

  factory InfluxSettings.fromEnvironment() => const InfluxSettings(
        url: String.fromEnvironment('INFLUXDB_URL'),
        org: String.fromEnvironment('INFLUXDB_ORG'),
        bucket: String.fromEnvironment('INFLUXDB_FALL_EVENTS_BUCKET'),
        token: String.fromEnvironment('INFLUXDB_TOKEN'),
        writeFallEvents: bool.fromEnvironment('FALL_EVENTS_WRITE'),
      );

  /// Base URL without a trailing path, e.g. `https://influxdb.example.org`.
  final String url;
  final String org;
  final String bucket;
  final String token;

  /// Port of the Python service's `FALL_EVENTS_WRITE` workaround. Leave false
  /// in any app that runs in more than one place (every browser tab would
  /// write its own copy). See docs/01_isa_fall_history.md.
  ///
  /// DECISION 2026-10-28 (Hayate + Isa): keep this false; the mobile app owns
  /// `fall_events` writes. Approach under trial, may change later.
  final bool writeFallEvents;

  bool get isConfigured => url.isNotEmpty && bucket.isNotEmpty && token.isNotEmpty;
}
