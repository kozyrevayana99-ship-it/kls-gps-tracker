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
      timestamp: DateTime.utc(2026, 8, 16, 10, 0, second),
    );
  }

  test('locks after consecutive accurate points', () {
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
  });

  test('does not add small stationary drift', () {
    final filter = KlsGpsFilter();
    filter.add(point(lat: 57, lng: 41, second: 0));
    filter.add(point(lat: 57, lng: 41, second: 1));
    filter.add(point(lat: 57, lng: 41, second: 2));

    final result = filter.add(
      point(lat: 57.00001, lng: 41.00001, second: 3, speed: 0),
    );

    expect(result.decision, KlsGpsPointDecision.stationary);
    expect(result.shouldRecord, isFalse);
  });

  test('accepts real running even when OS speed temporarily reports zero', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 12);
    filter.add(point(lat: 57, lng: 41, second: 0, speed: 0));
    filter.add(point(lat: 57, lng: 41, second: 1, speed: 0));
    filter.add(point(lat: 57, lng: 41, second: 2, speed: 0));

    // Roughly 4.4 m north in one second: a normal running speed.
    final result = filter.add(
      point(lat: 57.00004, lng: 41, second: 3, speed: 0),
    );

    expect(result.shouldRecord, isTrue);
    expect(result.decision, KlsGpsPointDecision.accepted);
    expect(result.segmentMeters, greaterThan(3));
  });

  test('slow movement accumulates instead of disappearing inside GPS noise', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 12);
    filter.add(point(lat: 57, lng: 41, second: 0, accuracy: 8, speed: 0));
    filter.add(point(lat: 57, lng: 41, second: 1, accuracy: 8, speed: 0));
    filter.add(point(lat: 57, lng: 41, second: 2, accuracy: 8, speed: 0));

    final first = filter.add(
      point(lat: 57.00001, lng: 41, second: 3, accuracy: 8, speed: 0),
    );
    expect(first.shouldRecord, isFalse);

    final second = filter.add(
      point(lat: 57.00004, lng: 41, second: 5, accuracy: 8, speed: 0),
    );
    expect(second.shouldRecord, isTrue);
    expect(second.segmentMeters, greaterThan(3));
  });

  test('rejects an impossible 800 metre jump', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 12);
    filter.add(point(lat: 57, lng: 41, second: 0, speed: 2));
    filter.add(point(lat: 57.00002, lng: 41, second: 1, speed: 2));
    filter.add(point(lat: 57.00004, lng: 41, second: 2, speed: 2));

    final result = filter.add(
      point(lat: 57.0072, lng: 41, second: 3, speed: 0),
    );

    expect(result.decision, KlsGpsPointDecision.rejectedJump);
    expect(result.shouldRecord, isFalse);
  });

  test('gap reset adds no distance across a long missing interval', () {
    final filter = KlsGpsFilter(maxSpeedMetersPerSecond: 12);
    filter.add(point(lat: 57, lng: 41, second: 0, speed: 2));
    filter.add(point(lat: 57.00002, lng: 41, second: 1, speed: 2));
    filter.add(point(lat: 57.00004, lng: 41, second: 2, speed: 2));

    final result = filter.add(
      point(lat: 57.001, lng: 41, second: 30, speed: 2),
    );

    expect(result.decision, KlsGpsPointDecision.gapReset);
    expect(result.segmentMeters, 0);
  });
}
