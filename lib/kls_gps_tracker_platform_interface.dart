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

  // ===========================================================================
  // GPS PERMISSIONS / READINESS
  // ===========================================================================

  Future<KlsLocationPermission> requestPermission();

  Future<KlsGpsReadiness> checkReadiness();

  // ===========================================================================
  // GPS TRACKING
  // ===========================================================================

  Future<String> start({
    String? workoutId,
  });

  /// Stops native location updates.
  ///
  /// When [finishWorkout] is false, the durable workout remains active and can
  /// be resumed with the same id. This is used for a manual pause.
  Future<void> stop({
    bool finishWorkout = true,
  });

  Future<KlsGpsTrackingState> getTrackingState();

  // ===========================================================================
  // STORED GPS POINTS
  // ===========================================================================

  Future<List<KlsGpsPoint>> getStoredPoints({
    required String workoutId,
    int afterPointIndex = -1,
    int limit = 1000,
  });

  Future<List<String>> listStoredWorkoutIds();

  Future<void> deleteStoredWorkout(
    String workoutId,
  );

  // ===========================================================================
  // NATIVE VOICE COACH
  //
  // Primarily used on iOS so voice guidance can continue while Flutter/Dart is
  // suspended after the screen is locked.
  // ===========================================================================

  /// Sends the complete voice schedule/settings to the native layer.
  ///
  /// Expected configuration can contain:
  ///
  /// {
  ///   'enabled': true,
  ///   'language': 'ru-RU',
  ///   'rate': 0.48,
  ///   'pitch': 0.98,
  ///   'volume': 1.0,
  ///   'cues': [
  ///     {
  ///       'id': 'stage_0_start',
  ///       'atElapsedSeconds': 0,
  ///       'text': 'Начинаем разминку.',
  ///     },
  ///   ],
  /// }
  Future<Map<String, dynamic>> configureVoiceCoach(
    Map<String, dynamic> configuration,
  );

  /// Starts the native voice timeline.
  ///
  /// [elapsedSeconds] allows the native timeline to continue from an already
  /// running/restored workout instead of always starting from zero.
  Future<Map<String, dynamic>> startVoiceCoach({
    double elapsedSeconds = 0,
  });

  /// Temporarily pauses the native voice timeline.
  Future<void> pauseVoiceCoach();

  /// Resumes the previously paused native voice timeline.
  Future<void> resumeVoiceCoach();

  /// Stops and clears the native voice coach configuration.
  Future<void> stopVoiceCoach();

  /// Enables or disables native voice output without destroying the schedule.
  Future<Map<String, dynamic>> setVoiceCoachEnabled(
    bool enabled,
  );

  /// Speaks a message immediately using the native speech synthesizer.
  ///
  /// This is useful for dynamic messages that cannot be scheduled beforehand,
  /// for example a live heart-rate warning.
  Future<void> speakVoiceCoachNow(
    String text,
  );

  /// Returns diagnostic state from the native voice engine.
  Future<Map<String, dynamic>> getVoiceCoachState();

  // ===========================================================================
  // LIVE GPS STREAM
  // ===========================================================================

  Stream<KlsGpsPoint> get positionStream;
}
