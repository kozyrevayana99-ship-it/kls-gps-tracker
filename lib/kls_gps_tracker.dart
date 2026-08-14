import 'kls_gps_tracker_platform_interface.dart';
import 'src/gps_models.dart';

export 'src/gps_filter.dart';
export 'src/gps_models.dart';
export 'src/offline_workout_sync.dart';

class KlsGpsTracker {
  Future<KlsLocationPermission> requestPermission() {
    return KlsGpsTrackerPlatform.instance.requestPermission();
  }

  Future<KlsGpsReadiness> checkReadiness() {
    return KlsGpsTrackerPlatform.instance.checkReadiness();
  }

  /// Starts a durable native GPS session and returns its workout id.
  ///
  /// Pass the client-generated [workoutId] when one already exists. When it is
  /// omitted, the native platform creates a UUID. Raw fixes are journaled on
  /// disk before they are emitted to [positionStream].
  Future<String> start({String? workoutId}) {
    return KlsGpsTrackerPlatform.instance.start(workoutId: workoutId);
  }

  Future<void> stop({bool finishWorkout = true}) {
    return KlsGpsTrackerPlatform.instance.stop(finishWorkout: finishWorkout);
  }

  Future<KlsGpsTrackingState> getTrackingState() {
    return KlsGpsTrackerPlatform.instance.getTrackingState();
  }

  Future<List<KlsGpsPoint>> getStoredPoints({
    required String workoutId,
    int afterPointIndex = -1,
    int limit = 1000,
  }) {
    return KlsGpsTrackerPlatform.instance.getStoredPoints(
      workoutId: workoutId,
      afterPointIndex: afterPointIndex,
      limit: limit,
    );
  }

  Future<List<String>> listStoredWorkoutIds() {
    return KlsGpsTrackerPlatform.instance.listStoredWorkoutIds();
  }

  Future<void> deleteStoredWorkout(String workoutId) {
    return KlsGpsTrackerPlatform.instance.deleteStoredWorkout(workoutId);
  }

  Stream<KlsGpsPoint> get positionStream =>
      KlsGpsTrackerPlatform.instance.positionStream;
}
