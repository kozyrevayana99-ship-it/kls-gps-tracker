# kls_gps_tracker

KLS GPS diagnostics plugin for Flutter.

Version `0.1.0` provides the first raw-location layer:

- foreground location permission requests;
- precise/approximate permission detection;
- location-service readiness checks;
- start/stop controls;
- a live stream of coordinates, accuracy, altitude, speed, heading, and time;
- native Android LocationManager and Apple Core Location implementations.

Distance calculation, point filtering, background recording, persistence, and
maps are intentionally not included yet.

## Basic usage

```dart
final tracker = KlsGpsTracker();
final permission = await tracker.requestPermission();
final readiness = await tracker.checkReadiness();

if (readiness.canStart) {
  tracker.positionStream.listen((point) {
    print('${point.latitude}, ${point.longitude}');
  });
  await tracker.start();
}
```

Always call `stop()` when the diagnostic session ends.

## iOS setup

Add a clear purpose string to the host application's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>КЛС использует геопозицию для записи маршрута тренировки.</string>
```

## Android setup

The plugin manifest contributes foreground coarse and fine location
permissions. Background permission and a foreground service will be added in a
later milestone.

## Example

The `example` application contains a Russian-language diagnostics screen that
shows readiness, permission state, received point count, coordinates, accuracy,
speed, and timestamp.
