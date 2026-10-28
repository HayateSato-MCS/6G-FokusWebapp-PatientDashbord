import 'dart:convert';

import '../core/patient_confirmed.dart';
import '../core/time_utils.dart';

/// Which stage of a fall an MQTT message describes.
enum FallEventStatus {
  /// `fall/possible/<patient_id>`: the model detected a fall; the patient has
  /// not answered the popup yet.
  pending,

  /// `fall/alert/<patient_id>`: the patient answered (or the popup timed out).
  confirmed,
}

/// One fall message from the mobile app, parsed and normalised: topic and
/// `fall_detected` handling, patient_confirmed conversion and the
/// caregiver-alert rule.
class FallEvent {
  const FallEvent({
    required this.status,
    required this.patientId,
    required this.topic,
    required this.payload,
    this.observationId,
    this.confidence,
    this.modelVersion,
    this.deviceId,
    this.detectionTime,
    this.patientConfirmed,
    this.needsHelp,
    this.caregiverAlert = false,
  });

  final FallEventStatus status;

  /// From the payload's `patient_id`, or the last topic segment if missing.
  /// Must match the patient ID shown in the dashboard exactly.
  final String patientId;
  final String topic;

  /// The decoded JSON payload as received.
  final Map<String, Object?> payload;

  /// UUID from the inference server's `/predict` response. Links the
  /// `fall/possible` and `fall/alert` messages of the same fall.
  final String? observationId;
  final double? confidence;
  final String? modelVersion;
  final String? deviceId;

  /// Detection time from the payload's `timestamp`, in UTC.
  final DateTime? detectionTime;

  /// [PatientConfirmed] int; null for pending events.
  final int? patientConfirmed;

  /// True/false only when the patient answered "Do you need help?";
  /// null when that question was not asked or not answered.
  final bool? needsHelp;

  /// Whether the caregiver must act: no answer at all, or confirmed fall with
  /// help requested. Always false for pending events.
  final bool caregiverAlert;

  bool get isPending => status == FallEventStatus.pending;

  /// Parses one MQTT message. Returns null when the message is not a fall
  /// event: invalid JSON, `fall_detected` not true, or an unexpected topic.
  static FallEvent? fromMqtt({
    required String topic,
    required String payload,
    String possibleTopic = 'fall/possible',
    String alertTopic = 'fall/alert',
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    if (decoded['fall_detected'] != true) return null;

    final FallEventStatus status;
    if (topic.startsWith('$possibleTopic/')) {
      status = FallEventStatus.pending;
    } else if (topic.startsWith('$alertTopic/')) {
      status = FallEventStatus.confirmed;
    } else {
      return null;
    }

    final payloadPatient = decoded['patient_id'];
    final patientId = payloadPatient is String && payloadPatient.isNotEmpty
        ? payloadPatient
        : topic.split('/').last;

    final rawNeedsHelp = decoded['needs_help'];
    final needsHelp = rawNeedsHelp is bool ? rawNeedsHelp : null;

    int? confirmed;
    var caregiverAlert = false;
    if (status == FallEventStatus.confirmed) {
      confirmed = PatientConfirmed.fromPayload(decoded['patient_confirmed']);
      // Caregiver must act: no answer, or a confirmed fall with help requested.
      caregiverAlert = confirmed == PatientConfirmed.notAnswered ||
          (confirmed == PatientConfirmed.yes && needsHelp == true);
    }

    final rawConfidence = decoded['confidence'];
    final rawObservation = decoded['observation_id'];
    final rawModel = decoded['model_version'];
    final rawDevice = decoded['device_id'];

    return FallEvent(
      status: status,
      patientId: patientId,
      topic: topic,
      payload: decoded,
      observationId:
          rawObservation is String && rawObservation.isNotEmpty ? rawObservation : null,
      confidence: rawConfidence is num ? rawConfidence.toDouble() : null,
      modelVersion: rawModel is String && rawModel.isNotEmpty ? rawModel : null,
      deviceId: rawDevice is String && rawDevice.isNotEmpty ? rawDevice : null,
      detectionTime: parseUtcTimestamp(decoded['timestamp']),
      patientConfirmed: confirmed,
      needsHelp: needsHelp,
      caregiverAlert: caregiverAlert,
    );
  }
}
