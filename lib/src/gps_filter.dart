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
/// Important architecture rule:
/// - native iOS/Android stores every RAW GPS fix first;
/// - this filter only decides whether a fix is TRUSTED for route/distance;
/// - a rejected point is never erased from the durable native journal.
///
/// The filter deliberately does NOT treat an OS-reported speed near zero as
/// proof that the athlete is stationary. CLLocation/Android speed can lag for
/// several fixes after starting, stopping, turning, or returning from the
/// background. Movement is therefore decided primarily from coordinates,
/// timestamps, accuracy, and a sport-specific physical speed ceiling.
class KlsGpsFilter {
  KlsGpsFilter({
    this.startupAccuracyMeters = 20,
    this.maxAccuracyMeters = 30,
    this.warmupPointCount = 3,
    this.minimumMovementMeters = 2.5,
    this.stationarySpeedMetersPerSecond = 0.8,
    this.maxSpeedMetersPerSecond = 20,
    this.maximumGapSeconds = 15,
  }) : assert(startupAccuracyMeters > 0),
       assert(maxAccuracyMeters >= startupAccuracyMeters),
       assert(warmupPointCount >= 1),
       assert(minimumMovementMeters >= 0),
       assert(maxSpeedMetersPerSecond > 0),
       assert(maximumGapSeconds > 0);

  final double startupAccuracyMeters;
  final double maxAccuracyMeters;
  final int warmupPointCount;
  final double minimumMovementMeters;

  /// Kept for API compatibility and for choosing a good live-speed source.
  /// It is NOT used to reject real coordinate movement by itself.
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

    // A long break means we cannot safely connect the two fixes. The new fix
    // becomes an anchor for a new visual segment, but the gap itself adds zero
    // distance.
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
    final speedAllowance = _speedAllowance(previous, point, dt);

    // Only a physically implausible coordinate displacement is a jump.
    // OS-reported speed is intentionally NOT allowed to veto otherwise
    // plausible coordinate movement.
    if (derivedSpeed > maxSpeedMetersPerSecond + speedAllowance) {
      return _result(KlsGpsPointDecision.rejectedJump, point);
    }

    // Suppress sub-accuracy drift without moving the accepted anchor. This is
    // important: slow real movement accumulates against the same anchor until
    // it leaves the GPS noise radius, so walking/running does not disappear.
    final movementThreshold = max(
      minimumMovementMeters,
      _noiseRadius(previous, point),
    );
    if (segment < movementThreshold) {
      return _result(KlsGpsPointDecision.stationary, point);
    }

    _lastAcceptedPoint = point;

    return _accepted(
      point,
      segmentMeters: segment,
      speed: _chooseLiveSpeed(
        point: point,
        derivedSpeed: derivedSpeed,
        speedAllowance: speedAllowance,
      ),
    );
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
      if (!segment.isFinite) {
        _warmupAccepted = 1;
        _lastWarmupPoint = point;
        return _result(KlsGpsPointDecision.rejectedInvalid, point);
      }

      final derivedSpeed = segment / dt;
      final speedAllowance = _speedAllowance(previous, point, dt);
      if (derivedSpeed > maxSpeedMetersPerSecond + speedAllowance) {
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

  KlsGpsFilterResult _result(KlsGpsPointDecision decision, KlsGpsPoint point) {
    return KlsGpsFilterResult(
      decision: decision,
      point: point,
      gpsLocked: _locked,
      currentSpeedMetersPerSecond: _median(_speedWindow),
    );
  }

  double _noiseRadius(KlsGpsPoint previous, KlsGpsPoint current) {
    final accuracy = max(
      max(0.0, previous.accuracyMeters),
      max(0.0, current.accuracyMeters),
    );

    if (accuracy <= 0) return 2.0;
    return (accuracy * 0.30).clamp(2.0, 10.0).toDouble();
  }

  double _speedAllowance(
    KlsGpsPoint previous,
    KlsGpsPoint current,
    double dt,
  ) {
    final accuracy = max(
      max(0.0, previous.accuracyMeters),
      max(0.0, current.accuracyMeters),
    );
    return max(3.0, accuracy / max(1.0, dt));
  }

  double _chooseLiveSpeed({
    required KlsGpsPoint point,
    required double derivedSpeed,
    required double speedAllowance,
  }) {
    final reported = _reportedSpeed(point);
    if (reported == null || reported < stationarySpeedMetersPerSecond) {
      return derivedSpeed;
    }

    if (reported > maxSpeedMetersPerSecond + speedAllowance) {
      return derivedSpeed;
    }

    final allowedDifference = max(2.5, max(derivedSpeed, 1.0) * 0.75);
    if ((reported - derivedSpeed).abs() > allowedDifference) {
      return derivedSpeed;
    }

    return reported;
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
    final h =
        sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return radius * 2 * atan2(sqrt(h), sqrt(max(0.0, 1.0 - h)));
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
