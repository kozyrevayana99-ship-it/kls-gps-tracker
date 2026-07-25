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
  });

  final KlsLocationPermission permission;
  final KlsLocationServiceStatus serviceStatus;

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
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;
  final DateTime timestamp;

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
