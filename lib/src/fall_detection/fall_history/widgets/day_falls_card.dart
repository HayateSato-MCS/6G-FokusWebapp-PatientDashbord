import 'package:flutter/material.dart';

import '../../core/patient_confirmed.dart';
import '../../ui/fall_colors.dart';
import '../fall_record.dart';

/// "Stürze" card for the patient page: falls on the selected day. Same size
/// and style as the measurement cards next to it. Tap opens the list.
class DayFallsCard extends StatelessWidget {
  const DayFallsCard({
    super.key,
    required this.day,
    required this.falls,
    required this.failed,
  });

  /// The selected day (local).
  final DateTime day;

  /// Null while loading.
  final DayFalls? falls;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final falls = this.falls;
    final String value;
    final String detail;
    if (failed) {
      value = 'n. v.';
      detail = 'Sturzdaten nicht verfügbar';
    } else if (falls == null) {
      value = '—';
      detail = 'wird geladen';
    } else {
      final listed = falls.listed;
      value = '${falls.total}';
      detail = [
        if (falls.total == 0) 'Keine Stürze an diesem Tag',
        if (listed.isNotEmpty)
          'bestätigt: ${listed.where((f) => f.isConfirmed).length}, '
              'Hilfe: ${listed.where((f) => f.needsHelp == true).length}',
        if (falls.simulated > 0) '+${falls.simulated} simuliert',
      ].join('\n');
    }

    return SizedBox(
      width: 220,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: falls == null || failed ? null : () => showDayFallsList(context, day, falls),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.personal_injury, size: 30),
                    const SizedBox(width: 10),
                    const Text('Stürze', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 5),
                Text(detail, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// List of the day's falls, newest first. Simulated falls are not listed,
/// only counted in a note below the list.
Future<void> showDayFallsList(BuildContext context, DateTime day, DayFalls falls) {
  String two(int v) => v.toString().padLeft(2, '0');
  final listed = falls.listed;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Stürze am ${two(day.day)}.${two(day.month)}.${day.year}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (listed.isEmpty)
              const Text('Keine echten Stürze an diesem Tag.')
            else
              Flexible(
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 36,
                    columns: const [
                      DataColumn(label: Text('Uhrzeit')),
                      DataColumn(label: Text('Antwort')),
                      DataColumn(label: Text('Hilfe')),
                    ],
                    rows: [
                      for (final fall in listed)
                        DataRow(cells: [
                          DataCell(Text(_time(fall.detectionTime))),
                          DataCell(_tag(
                            PatientConfirmed.label(fall.patientConfirmed),
                            // same tag colours as the Python fall dashboard
                            switch (fall.patientConfirmed) {
                              PatientConfirmed.yes => (FallColors.tagYes, FallColors.tagYesText),
                              PatientConfirmed.no => (FallColors.tagNo, FallColors.tagNoText),
                              _ => (FallColors.tagPending, FallColors.tagPendingText),
                            },
                          )),
                          DataCell(fall.needsHelp == true
                              ? _tag('Ja', (FallColors.tagYes, FallColors.tagYesText))
                              : _tag('Nein', (FallColors.tagNo, FallColors.tagNoText))),
                        ]),
                    ],
                  ),
                ),
              ),
            if (falls.simulated > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  falls.simulated == 1
                      ? '+1 simulierter Sturz (Test aus der App, nicht aufgelistet)'
                      : '+${falls.simulated} simulierte Stürze (Test aus der App, nicht aufgelistet)',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
      ],
    ),
  );
}

String _time(DateTime? time) {
  if (time == null) return '–';
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Widget _tag(String text, (Color, Color) colors) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: colors.$2, fontWeight: FontWeight.w600)),
    );
