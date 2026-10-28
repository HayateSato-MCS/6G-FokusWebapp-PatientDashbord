import '../core/patient_confirmed.dart';

/// One row of the `fall_events` measurement in InfluxDB.
///
/// Schema (written by the mobile app after the patient has answered):
///   tags   : patient_id, device_id
///   fields : fall_detected (bool), patient_confirmed (int 1/0/-1),
///            needs_help (bool), confidence (float), observation_id (string),
///            model_version (string)
///   time   : detection time of the fall
class FallRecord {
  const FallRecord({
    required this.patientId,
    this.detectionTime,
    this.fallDetected = true,
    this.patientConfirmed,
    this.needsHelp,
    this.confidence,
    this.observationId,
    this.modelVersion,
    this.deviceId,
  });

  final String patientId;
  final DateTime? detectionTime;
  final bool fallDetected;

  /// [PatientConfirmed] int: 1 yes, 0 no, -1 no response.
  final int? patientConfirmed;
  final bool? needsHelp;
  final double? confidence;
  final String? observationId;
  final String? modelVersion;
  final String? deviceId;

  bool get isConfirmed => patientConfirmed == PatientConfirmed.yes;
}

/// Fall counts shown on a patient tile and in the header.
class FallCounts {
  const FallCounts({required this.last30Days, required this.last24Hours});

  static const zero = FallCounts(last30Days: 0, last24Hours: 0);

  final int last30Days;
  final int last24Hours;
}

/// The three numbers at the top of the patient detail view.
class PatientFallStats {
  const PatientFallStats({
    required this.total,
    required this.confirmed,
    required this.helpRequested,
  });

  factory PatientFallStats.from(Iterable<FallRecord> records) => PatientFallStats(
        total: records.length,
        confirmed: records.where((r) => r.isConfirmed).length,
        helpRequested: records.where((r) => r.needsHelp == true).length,
      );

  final int total;
  final int confirmed;
  final int helpRequested;
}
