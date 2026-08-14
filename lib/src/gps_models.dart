enum KlsLocationPermission {
  notDetermined,
  denied,
  deniedForever,
  approximate,
  precise,
}

enum KlsLocationServiceStatus { enabled, disabled }

class KlsGpsReadiness {
  const KlsGpsReadiness({
    required this.permission,
    required this.serviceStatus,
    this.backgroundCapable = false,
  });

  final KlsLocationPermission permission;
  final KlsLocationServiceStatus serviceStatus;
  final bool backgroundCapable;

  bool get canStart =>
      serviceStatus == KlsLocationServiceStatus.enabled &&
      (permission == KlsLocationPermission.approximate ||
          permission == KlsLocationPermission.precise);

  factory KlsGpsReadiness.fromMap(Map<Object?, Object?> map) {
    return KlsGpsReadiness(
      permission: _permissionFromString(map['permission'] as String?),
      serviceStatus: map['serviceEnabled'] == true
          ? KlsLocationServiceStatus.enabled
          : KlsLocationServiceStatus.disabled,
      backgroundCapable: map['backgroundCapable'] == true,
    );
  }
}

class KlsGpsTrackingState {
  const KlsGpsTrackingState({
    required this.isTracking,
    required this.pointCount,
    required this.backgroundCapable,
    this.workoutId,
  });

  final bool isTracking;
  final String? workoutId;
  final int pointCount;
  final bool backgroundCapable;

  factory KlsGpsTrackingState.fromMap(Map<Object?, Object?> map) {
    final rawWorkoutId = map['workoutId']?.toString();
    return KlsGpsTrackingState(
      isTracking: map['isTracking'] == true,
      workoutId: rawWorkoutId == null || rawWorkoutId.isEmpty
          ? null
          : rawWorkoutId,
      pointCount: (map['pointCount'] as num?)?.toInt() ?? 0,
      backgroundCapable: map['backgroundCapable'] == true,
    );
  }
}

class KlsGpsPoint {
  const KlsGpsPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.altitudeMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
    this.pointIndex,
    this.workoutId,
    this.provider,
    this.isMock = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;
  final DateTime timestamp;
  final int? pointIndex;
  final String? workoutId;
  final String? provider;
  final bool isMock;

  factory KlsGpsPoint.fromMap(Map<Object?, Object?> map) {
    double? optionalDouble(String key) {
      final value = map[key];
      return value is num ? value.toDouble() : null;
    }

    return KlsGpsPoint(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracy'] as num).toDouble(),
      altitudeMeters: optionalDouble('altitude'),
      speedMetersPerSecond: optionalDouble('speed'),
      headingDegrees: optionalDouble('heading'),
      pointIndex: (map['pointIndex'] as num?)?.toInt(),
      workoutId: map['workoutId']?.toString(),
      provider: map['provider']?.toString(),
      isMock: map['isMock'] == true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMillis'] as num).round(),
        isUtc: true,
      ),
    );
  }
}

KlsLocationPermission _permissionFromString(String? value) {
  return switch (value) {
    'denied' => KlsLocationPermission.denied,
    'deniedForever' => KlsLocationPermission.deniedForever,
    'approximate' => KlsLocationPermission.approximate,
    'precise' => KlsLocationPermission.precise,
    _ => KlsLocationPermission.notDetermined,
  };
}
