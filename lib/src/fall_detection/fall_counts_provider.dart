import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fall_history/influx_fall_repository.dart';

/// Fall counts of the last [window] for all patients, loaded with one query
/// (not one per tile) and refreshed every [refreshEvery].
class FallCountsProvider extends ChangeNotifier {
  FallCountsProvider(
    this._repository, {
    this.window = const Duration(days: 7),
    this.refreshEvery = const Duration(minutes: 5),
  });

  final InfluxFallRepository _repository;
  final Duration window;
  final Duration refreshEvery;

  Map<String, int>? _counts;
  bool _failed = false;
  bool _loading = false;
  bool _reloadAgain = false;
  bool _disposed = false;
  Timer? _timer;

  /// Falls of [patientId] in the window; null while the first load runs or
  /// when it failed (see [failed]).
  int? countFor(String patientId) => _counts == null ? null : (_counts![patientId] ?? 0);

  /// The last load failed and there is no earlier result to show.
  bool get failed => _failed && _counts == null;

  void start() {
    if (_timer != null) return;
    unawaited(reload());
    _timer = Timer.periodic(refreshEvery, (_) => reload());
  }

  Future<void> reload() async {
    if (_disposed) return;
    if (_loading) {
      _reloadAgain = true;
      return;
    }
    _loading = true;
    try {
      if (!_repository.settings.isConfigured) {
        throw InfluxQueryException('InfluxDB settings incomplete (INFLUXDB_TOKEN set?)');
      }
      _counts = await _repository.fetchFallCounts(window: window);
      _failed = false;
    } on InfluxQueryException catch (error) {
      debugPrint('Fall counts unavailable: $error');
      _failed = true;
    } finally {
      _loading = false;
    }
    if (_disposed) return;
    notifyListeners();
    if (_reloadAgain) {
      _reloadAgain = false;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
