/// Fall-detection features for the Patient Dashboard Webapp.
///
/// Live fall alerts (MQTT + popups): `live_alerts/`
/// Fall counts and history (InfluxDB): `fall_history/`
///
/// Copied from FallDetection_new/_6G_integration_v3_flutter/fall_dashboard
/// and adapted; see docs/fall_integration_plan.md.
library;

export 'config.dart';
export 'core/patient_confirmed.dart';
export 'core/time_utils.dart';
export 'fall_counts_provider.dart';
export 'fall_detection_scope.dart';
export 'fall_history/fall_record.dart';
export 'fall_history/flux_csv.dart';
export 'fall_history/influx_fall_repository.dart';
export 'fall_history/widgets/day_falls_card.dart';
export 'live_alerts/alert_controller.dart';
export 'live_alerts/fall_event.dart';
export 'live_alerts/fall_mqtt_service.dart';
export 'live_alerts/widgets/fall_alert_popup_listener.dart';
export 'live_alerts/widgets/mqtt_status_chip.dart';
export 'live_alerts/widgets/patient_alert_banner.dart';
export 'patient_id.dart';
export 'ui/fall_colors.dart';
