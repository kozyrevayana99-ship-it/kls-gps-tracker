# GPS fixes in version 0.2.0

## What changed

- A new workout always starts with empty local route, distance, speed, pending
  batch, point index, and GPS filter state.
- GPS recording starts only after three consecutive precise and consistent
  fixes. This removes the diagonal line from an arbitrary corner during the
  initial phone location lock.
- Points with accuracy worse than 30 metres, invalid timestamps, impossible
  speed, and coordinate jumps are rejected.
- Small movements while the operating system reports zero speed are treated as
  stationary GPS drift and do not increase distance.
- Every pause/resume creates a separate route segment, so the map does not draw
  a straight line across a pause or GPS gap.
- Android uses the GPS provider when precise GPS is available instead of mixing
  GPS and network-provider coordinates.
- Current speed is shown from the filtered device speed. Average speed remains a
  separate metric calculated from accepted distance and active workout time.
- The route placeholder was replaced by a real OpenStreetMap map with roads,
  automatic following, a recenter button, full-screen mode, an accuracy circle,
  route line, and start/current/finish markers.
- The last unsent point batch is awaited before the workout is finalized.

## Installation

1. Push this repository version to the GitHub repository used by FlutterFlow.
2. Copy the entire contents of
   `flutterflow/KlsGpsWorkoutRecorderWidget.dart` into the existing FlutterFlow
   custom widget of the same name.
3. Run Pub Get.
4. Create a new iOS/Android build. Hot reload does not reload native GPS code.

## Test checklist

1. Start outdoors and stand still for one minute. Distance should remain near
   zero and no route zigzag should appear.
2. Start a new workout on another phone. It must start from an empty route and
   wait for a fresh GPS lock.
3. Walk or ride a known short route and compare current speed with another GPS
   application. Do not compare the car speedometer with the average-speed
   metric.
4. Pause, move to another place, and resume. The two route parts must not be
   connected by a diagonal line.
5. Finish the workout and confirm that the result map uses real map tiles and
   that the final distance matches the saved diary value.

## Backend boundary

The repository does not include the Yandex Cloud implementations of
`saveWorkoutBatchUrl` and `finishWorkoutUrl`. The widget now uploads only
accepted points and waits for the final batch, but server-side distance
recalculation cannot be verified from this archive.
