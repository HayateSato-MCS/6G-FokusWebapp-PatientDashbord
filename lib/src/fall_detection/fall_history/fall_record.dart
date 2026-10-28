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

  /// Test fall triggered from the mobile app; they all share one observation_id.
  bool get isSimulated => observationId == simulatedObservationId;
}

/// observation_id the mobile app uses for every simulated (test) fall.
const simulatedObservationId = 'simulated-fall';

/// The falls of one patient on one day, newest first, one entry per fall.
///
/// Simulated falls count (decision 2026-10-28, plan Q5) but are not listed,
/// so the UI shows them as "+N simuliert" under the list.
class DayFalls {
  const DayFalls(this.falls);

  static const empty = DayFalls([]);

  final List<FallRecord> falls;

  int get total => falls.length;
  List<FallRecord> get listed => [for (final f in falls) if (!f.isSimulated) f];
  int get simulated => total - listed.length;
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
