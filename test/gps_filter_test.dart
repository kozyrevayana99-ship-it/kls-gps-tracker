import 'package:flutter_test/flutter_test.dart';
import 'package:kls_gps_tracker/kls_gps_tracker.dart';

void main() {
  KlsGpsPoint point({
    required double lat,
    required double lng,
    required int second,
    double accuracy = 4,
    double? speed = 0,
  }) {
    return KlsGpsPoint(
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      speedMetersPerSecond: speed,
      timestamp: DateTime.utc(2026, 7, 30, 10, 0, second),
    );
  }

  test('locks only after consecutive stable points', () {
    final filter = KlsGpsFilter();

    expect(
      filter.add(point(lat: 57, lng: 41, second: 0)).decision,
      KlsGpsPointDecision.warmingUp,
    );
    expect(
      filter.add(point(lat: 57, lng: 41, second: 1)).decision,
      KlsGpsPointDecision.warmingUp,
    );
    final result = filter.add(point(lat: 57, lng: 41, second: 2));

    expect(result.shouldRecord, isTrue);
    expect(result.gpsLocked, isTrue);
    expect(result.segmentMeters, 0);
  });

  test('does not add stationary drift to distance', () {
    final filter = KlsGpsFilter();
    filter.add(point(lat: 57, lng: 41, second: 0));
    filter.add(point(lat: 57, lng: 41, second: 1));
    filter.add(point(lat: 57, lng: 41, second: 2));

    final result = filter.add(
      point(lat: 57.00003, lng: 41.00003, second: 3, speed: 0),
    );

    expect(result.shouldRecord, isFalse);
    expect(result.segmentMeters, 0);
  });

  test('rejects a large stationary jump', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 20);
    filter.add(point(lat: 57, lng: 41, second: 0));
    filter.add(point(lat: 57, lng: 41, second: 1));
    filter.add(point(lat: 57, lng: 41, second: 2));

    final result = filter.add(
      point(lat: 57.001, lng: 41, second: 6, speed: 0),
    );

    expect(result.decision, KlsGpsPointDecision.rejectedJump);
    expect(result.shouldRecord, isFalse);
  });

  test('accepts car-like 60 km/h for rollerski diagnostics', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 20);
    filter.add(point(lat: 57, lng: 41, second: 0, speed: 16.67));
    filter.add(point(lat: 57.00015, lng: 41, second: 1, speed: 16.67));
    filter.add(point(lat: 57.00030, lng: 41, second: 2, speed: 16.67));

    final result = filter.add(
      point(lat: 57.00045, lng: 41, second: 3, speed: 16.67),
    );

    expect(result.shouldRecord, isTrue);
    expect(result.currentSpeedMetersPerSecond, closeTo(16.67, 0.01));
  });

  test('reset requires a new lock and forgets the old point', () {
    final filter = KlsGpsFilter();
    filter.add(point(lat: 57, lng: 41, second: 0));
    filter.add(point(lat: 57, lng: 41, second: 1));
    filter.add(point(lat: 57, lng: 41, second: 2));

    filter.reset();
    final result = filter.add(point(lat: 58, lng: 42, second: 3));

    expect(result.decision, KlsGpsPointDecision.warmingUp);
    expect(result.gpsLocked, isFalse);
  });
}
