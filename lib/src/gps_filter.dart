import 'dart:math';

import 'gps_models.dart';

enum KlsGpsPointDecision {
  warmingUp,
  accepted,
  stationary,
  rejectedInvalid,
  rejectedAccuracy,
  rejectedTimestamp,
  rejectedJump,
  gapReset,
}

class KlsGpsFilterResult {
  const KlsGpsFilterResult({
    required this.decision,
    required this.point,
    required this.gpsLocked,
    this.segmentMeters = 0,
    this.currentSpeedMetersPerSecond = 0,
  });

  final KlsGpsPointDecision decision;
  final KlsGpsPoint point;
  final bool gpsLocked;
  final double segmentMeters;
  final double currentSpeedMetersPerSecond;

  bool get shouldRecord => decision == KlsGpsPointDecision.accepted;
}

/// Stateful quality gate for workout GPS points.
///
/// It waits for several consistent fixes, ignores low-quality coordinates,
/// suppresses stationary drift, rejects impossible jumps, and smooths current
/// speed. Call [reset] before every workout and after every pause.
class KlsGpsFilter {
  KlsGpsFilter({
    this.startupAccuracyMeters = 20,
    this.maxAccuracyMeters = 30,
    this.warmupPointCount = 3,
    this.minimumMovementMeters = 2.5,
    this.stationarySpeedMetersPerSecond = 0.8,
    this.maxSpeedMetersPerSecond = 20,
    this.maximumGapSeconds = 15,
  })  : assert(startupAccuracyMeters > 0),
        assert(maxAccuracyMeters >= startupAccuracyMeters),
        assert(warmupPointCount >= 1),
        assert(minimumMovementMeters >= 0),
        assert(maxSpeedMetersPerSecond > 0);

  final double startupAccuracyMeters;
  final double maxAccuracyMeters;
  final int warmupPointCount;
  final double minimumMovementMeters;
  final double stationarySpeedMetersPerSecond;
  final double maxSpeedMetersPerSecond;
  final double maximumGapSeconds;

  bool _locked = false;
  int _warmupAccepted = 0;
  KlsGpsPoint? _lastWarmupPoint;
  KlsGpsPoint? _lastAcceptedPoint;
  final List<double> _speedWindow = <double>[];

  bool get isLocked => _locked;
  int get warmupAccepted => _warmupAccepted;
  KlsGpsPoint? get lastAcceptedPoint => _lastAcceptedPoint;

  void reset() {
    _locked = false;
    _warmupAccepted = 0;
    _lastWarmupPoint = null;
    _lastAcceptedPoint = null;
    _speedWindow.clear();
  }

  KlsGpsFilterResult add(KlsGpsPoint point) {
    if (!_isCoordinateValid(point)) {
      return _result(KlsGpsPointDecision.rejectedInvalid, point);
    }

    final accuracy = point.accuracyMeters;
    if (!accuracy.isFinite || accuracy <= 0 || accuracy > maxAccuracyMeters) {
      if (!_locked) _resetWarmup();
      return _result(KlsGpsPointDecision.rejectedAccuracy, point);
    }

    if (!_locked) return _warmUp(point);

    final previous = _lastAcceptedPoint;
    if (previous == null) {
      _lastAcceptedPoint = point;
      return _accepted(point, segmentMeters: 0);
    }

    final dt = _secondsBetween(previous, point);
    if (!dt.isFinite || dt <= 0) {
      return _result(KlsGpsPointDecision.rejectedTimestamp, point);
    }

    if (dt > maximumGapSeconds) {
      _lastAcceptedPoint = point;
      _speedWindow.clear();
      return _result(KlsGpsPointDecision.gapReset, point);
    }

    final segment = _distanceMeters(previous, point);
    if (!segment.isFinite) {
      return _result(KlsGpsPointDecision.rejectedInvalid, point);
    }

    final derivedSpeed = segment / dt;
    final reportedSpeed = _reportedSpeed(point);

    // When the operating system reports that the device is stationary, a
    // large coordinate displacement is drift, not real motion.
    if (reportedSpeed != null &&
        reportedSpeed < stationarySpeedMetersPerSecond) {
      final driftRadius = max(
        12.0,
        previous.accuracyMeters + point.accuracyMeters,
      );
      if (segment <= driftRadius || derivedSpeed > 3) {
        return _result(
          derivedSpeed > 3
              ? KlsGpsPointDecision.rejectedJump
              : KlsGpsPointDecision.stationary,
          point,
        );
      }
    }

    final speedAllowance = max(3.0, point.accuracyMeters / max(1.0, dt));
    if (derivedSpeed > maxSpeedMetersPerSecond + speedAllowance) {
      return _result(KlsGpsPointDecision.rejectedJump, point);
    }

    if (reportedSpeed != null &&
        reportedSpeed > maxSpeedMetersPerSecond + speedAllowance) {
      return _result(KlsGpsPointDecision.rejectedJump, point);
    }

    if (segment < minimumMovementMeters) {
      return _result(KlsGpsPointDecision.stationary, point);
    }

    _lastAcceptedPoint = point;
    final speed = reportedSpeed != null &&
            reportedSpeed >= stationarySpeedMetersPerSecond
        ? reportedSpeed
        : derivedSpeed;
    return _accepted(point, segmentMeters: segment, speed: speed);
  }

  KlsGpsFilterResult _warmUp(KlsGpsPoint point) {
    if (point.accuracyMeters > startupAccuracyMeters) {
      _resetWarmup();
      return _result(KlsGpsPointDecision.warmingUp, point);
    }

    final previous = _lastWarmupPoint;
    if (previous != null) {
      final dt = _secondsBetween(previous, point);
      if (!dt.isFinite || dt <= 0 || dt > maximumGapSeconds) {
        _warmupAccepted = 1;
        _lastWarmupPoint = point;
        return _result(KlsGpsPointDecision.warmingUp, point);
      }

      final segment = _distanceMeters(previous, point);
      final derivedSpeed = segment / dt;
      final reportedSpeed = _reportedSpeed(point);
      final looksLikeStationaryJump = reportedSpeed != null &&
          reportedSpeed < stationarySpeedMetersPerSecond &&
          derivedSpeed > 3;

      if (!segment.isFinite ||
          derivedSpeed > maxSpeedMetersPerSecond + 3 ||
          looksLikeStationaryJump) {
        _warmupAccepted = 1;
        _lastWarmupPoint = point;
        return _result(KlsGpsPointDecision.rejectedJump, point);
      }
    }

    _lastWarmupPoint = point;
    _warmupAccepted++;

    if (_warmupAccepted < warmupPointCount) {
      return _result(KlsGpsPointDecision.warmingUp, point);
    }

    _locked = true;
    _lastAcceptedPoint = point;
    _speedWindow.clear();
    return _accepted(point, segmentMeters: 0);
  }

  void _resetWarmup() {
    _warmupAccepted = 0;
    _lastWarmupPoint = null;
  }

  KlsGpsFilterResult _accepted(
    KlsGpsPoint point, {
    required double segmentMeters,
    double? speed,
  }) {
    final candidate = speed ?? _reportedSpeed(point) ?? 0;
    if (candidate.isFinite && candidate >= 0) {
      _speedWindow.add(candidate);
      if (_speedWindow.length > 5) _speedWindow.removeAt(0);
    }

    return KlsGpsFilterResult(
      decision: KlsGpsPointDecision.accepted,
      point: point,
      gpsLocked: true,
      segmentMeters: segmentMeters,
      currentSpeedMetersPerSecond: _median(_speedWindow),
    );
  }

  KlsGpsFilterResult _result(
    KlsGpsPointDecision decision,
    KlsGpsPoint point,
  ) {
    return KlsGpsFilterResult(
      decision: decision,
      point: point,
      gpsLocked: _locked,
      currentSpeedMetersPerSecond: _median(_speedWindow),
    );
  }

  bool _isCoordinateValid(KlsGpsPoint point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180 &&
        !(point.latitude == 0 && point.longitude == 0);
  }

  double? _reportedSpeed(KlsGpsPoint point) {
    final value = point.speedMetersPerSecond;
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  double _secondsBetween(KlsGpsPoint a, KlsGpsPoint b) {
    return b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
  }

  double _distanceMeters(KlsGpsPoint a, KlsGpsPoint b) {
    const radius = 6371000.0;
    final phi1 = a.latitude * pi / 180;
    final phi2 = b.latitude * pi / 180;
    final dPhi = (b.latitude - a.latitude) * pi / 180;
    final dLambda = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return radius * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)));
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
