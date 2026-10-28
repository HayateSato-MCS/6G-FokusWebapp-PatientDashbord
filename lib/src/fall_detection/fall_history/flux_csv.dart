/// Parser for InfluxDB 2 query responses in CSV form (no annotations).
///
/// A Flux response is one or more tables. Each table starts with a header row
/// and tables are separated by an empty line. Returns one map per data row,
/// keyed by column name; values stay strings.
List<Map<String, String>> parseFluxCsv(String body) {
  final rows = <Map<String, String>>[];
  List<String>? header;
  for (final record in _csvRecords(body)) {
    final isBlank = record.length == 1 && record.first.isEmpty;
    if (isBlank) {
      header = null;
      continue;
    }
    if (header == null) {
      header = record;
      continue;
    }
    final row = <String, String>{};
    for (var i = 0; i < header.length && i < record.length; i++) {
      if (header[i].isNotEmpty) row[header[i]] = record[i];
    }
    rows.add(row);
  }
  return rows;
}

/// RFC 4180 records: quoted fields may contain commas, quotes and newlines.
List<List<String>> _csvRecords(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    record.add(field.toString());
    field.clear();
  }

  void endRecord() {
    endField();
    records.add(record);
    record = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        inQuotes = true;
      case ',':
        endField();
      case '\r':
        break;
      case '\n':
        endRecord();
      default:
        field.write(char);
    }
  }
  if (field.isNotEmpty || record.isNotEmpty) endRecord();
  return records;
}
