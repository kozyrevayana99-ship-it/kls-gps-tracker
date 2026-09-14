# kls_gps_tracker

KLS GPS diagnostics plugin for Flutter.

Version `0.4.3` provides the native raw-location layer plus a reusable workout
quality filter:

- foreground location permission requests;
- precise/approximate permission detection;
- location-service readiness checks;
- start/stop controls;
- a live stream of coordinates, accuracy, altitude, speed, heading, and time;
- a three-fix GPS warm-up lock;
- poor-accuracy, stationary-drift, timestamp, and impossible-jump rejection;
- median smoothing for current speed;
- native Android LocationManager and Apple Core Location implementations.
- an Android workout wake lock so Flutter timers and spoken workout cues keep
  running while the screen is locked.

The `flutterflow/KlsGpsWorkoutRecorderWidget.dart` file contains the full
FlutterFlow widget with a real `flutter_map` OpenStreetMap map, route segments,
current-location arrow, accuracy circle, start/finish markers, follow mode,
full-screen route view, current speed, average speed, and backend batch upload.

Backend persistence remains in the host KLS Yandex Cloud functions.

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

## FlutterFlow widget

1. Keep the Git dependency on this repository.
2. Replace the code of `KlsGpsWorkoutRecorderWidget` with
   `flutterflow/KlsGpsWorkoutRecorderWidget.dart`.
3. Run Pub Get so FlutterFlow resolves `flutter_map` and `latlong2` through this
   package.
4. Rebuild the application; hot reload is not enough after native package
   changes.

## iOS setup

Add a clear purpose string to the host application's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>КЛС использует геопозицию для записи маршрута тренировки.</string>

<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>audio</string>
</array>
```

The `location` mode keeps the workout session active behind the lock screen.
The `audio` mode lets the playback audio session used by workout voice prompts
remain audible while the iPhone is locked.

## Android setup

The plugin manifest contributes location and foreground-service permissions,
the workout foreground service, the TTS-service visibility query, and a partial
wake lock. The wake lock is held only while native workout recording is active
and is released on pause, finish, or service teardown.

## Example

The `example` application contains a Russian-language diagnostics screen that
shows readiness, permission state, received point count, coordinates, accuracy,
speed, and timestamp.
