class MCSDashboardEnvironment {
  static const String idpScheme = String.fromEnvironment("BACKEND_SCHEME", defaultValue: "https");
  static const String idpHost =
      // String.fromEnvironment("BACKEND_HOST", defaultValue: "internal.e-healthservice.de");
      String.fromEnvironment("BACKEND_HOST", defaultValue: "6g-path.apps.osc.fokus.fraunhofer.de");

  static const String fhirBaseUrl = "$idpScheme://$idpHost/fhir/";

  // influxdb.internal.e-healthservice.de = original FOKUS instance, retired after issues.
  // 6g-path.apps.osc.fokus.fraunhofer.de/influxdb = the "instance on OpenShift"; current,
  // shared with the 6G mobile app (also for fall_events). See README "InfluxDB instances".
  static const String influxDBHost = String.fromEnvironment("INFLUXDB_URL",
      // defaultValue: "https://influxdb.internal.e-healthservice.de");
      defaultValue: "https://6g-path.apps.osc.fokus.fraunhofer.de/influxdb");

  // No default on purpose: never commit a token. Pass it at build/run time with
  // --dart-define=INFLUXDB_TOKEN=... or --dart-define-from-file=dart_defines.local.json.
  static const String influxDBAPIToken = String.fromEnvironment("INFLUXDB_TOKEN");
  static const bool hasInfluxDBToken = influxDBAPIToken != "";
  static const String influxDBOrg =
      String.fromEnvironment("INFLUXDB_ORG", defaultValue: "mcs-data-labs");
  static const String influxDBBucket =
      String.fromEnvironment("INFLUXDB_BUCKET", defaultValue: "6g-path");

  static const String keyAccessToken = "access_token";
  // static const String headerKeyAuthorization = "Authorization";
  static const String headerKeyAuthorization = "serviceaccesstoken";
  static const String headerValuePrefixBearer = "Bearer ";
  static const String headerContentType = "Content-Type";
  static const String headerAccept = "Accept";
  static const String jsonContentType = "application/json";
  static const String octetStreamContentType = 'application/octet-stream';

  static const String headerKeyCacheControl = "Cache-Control";
  static const String headerValueCacheControlNoCache = "no-cache";
  static const String headerValueContentTypeFhirJson = 'application/fhir+json';
}
