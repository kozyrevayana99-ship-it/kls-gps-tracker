# FlutterFlow installation

Copy the complete contents of `KlsGpsWorkoutRecorderWidget.dart` into the
existing FlutterFlow custom widget with the same name.

Do not create a second widget. Keep the existing parameters:

- `currentUserId`
- `startWorkoutUrl`
- `saveWorkoutBatchUrl`
- `finishWorkoutUrl`
- `getWorkoutUrl`
- `getWorkoutRouteUrl`
- `addTrainingUrl`

After pushing this repository to GitHub, run Pub Get in FlutterFlow and create a
fresh TestFlight/Android build. The map and native GPS changes are not applied
by hot reload.
