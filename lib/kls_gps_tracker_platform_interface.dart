import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'kls_gps_tracker_method_channel.dart';
import 'src/gps_models.dart';

abstract class KlsGpsTrackerPlatform extends PlatformInterface {
  /// Constructs a KlsGpsTrackerPlatform.
  KlsGpsTrackerPlatform() : super(token: _token);

  static final Object _token = Object();

  static KlsGpsTrackerPlatform _instance = MethodChannelKlsGpsTracker();

  /// The default instance of [KlsGpsTrackerPlatform] to use.
  ///
  /// Defaults to [MethodChannelKlsGpsTracker].
  static KlsGpsTrackerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [KlsGpsTrackerPlatform] when
  /// they register themselves.
  static set instance(KlsGpsTrackerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<KlsLocationPermission> requestPermission();

  Future<KlsGpsReadiness> checkReadiness();

  Future<String> start({String? workoutId});

  /// Stops native location updates.
  ///
  /// When [finishWorkout] is false, the durable workout remains active and can
  /// be resumed with the same id. This is used for a manual pause.
  Future<void> stop({bool finishWorkout = true});

  Future<KlsGpsTrackingState> getTrackingState();

  Future<List<KlsGpsPoint>> getStoredPoints({
    required String workoutId,
    int afterPointIndex = -1,
    int limit = 1000,
  });

  Future<List<String>> listStoredWorkoutIds();

  Future<void> deleteStoredWorkout(String workoutId);

  Stream<KlsGpsPoint> get positionStream;
}
