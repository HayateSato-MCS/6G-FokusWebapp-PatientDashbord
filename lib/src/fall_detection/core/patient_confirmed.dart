/// Encoding of the patient's answer to "Did you fall?".
///
/// MQTT payloads from the mobile app carry a string (`yes` | `no` |
/// `not_answered`); InfluxDB and the UI use an int. Same mapping as the
/// mobile app's InfluxDB write.
abstract final class PatientConfirmed {
  /// The patient confirmed it was a fall.
  static const int yes = 1;

  /// The patient said it was not a fall (false positive).
  static const int no = 0;

  /// No answer within the popup timeout.
  static const int notAnswered = -1;

  /// Converts a payload value (string or number) to the int encoding.
  /// A missing or unknown value counts as [notAnswered] (the safe side).
  static int fromPayload(Object? raw) {
    if (raw is String) {
      if (raw == 'yes') return yes;
      if (raw == 'no') return no;
      return notAnswered;
    }
    if (raw is num) return raw.toInt();
    return notAnswered;
  }

  /// Short label for history tables.
  static String label(int? value) => switch (value) {
        yes => 'Bestätigt',
        no => 'Kein Sturz',
        notAnswered => 'Keine Antwort',
        _ => '-',
      };
}
