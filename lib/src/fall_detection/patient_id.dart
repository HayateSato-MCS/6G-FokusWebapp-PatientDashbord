import 'package:fhir/r4/general_types/general_types.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';

/// The patient key used in MQTT topics and in `fall_events`.
///
/// The 6G mobile app's `patient_id` is the patient's FHIR ID (decision
/// 2026-10-28, plan Q1), the same value the tiles use as `userId`.
String patientIdOf(Patient patient) => patient.fhirId.toString();

/// Name as shown on the patient tile.
String patientDisplayName(Patient patient) {
  final names = patient.name;
  final name = names != null && names.isNotEmpty ? names[0] : const HumanName();
  return '${name.given?.join('-')} ${name.family}';
}

/// Route name for a patient's page, so the alert dialog can tell whether
/// that page is already open.
String patientRouteName(String patientId) => 'patient/$patientId';
