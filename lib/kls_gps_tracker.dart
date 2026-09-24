import 'kls_gps_tracker_platform_interface.dart';
import 'src/gps_models.dart';

export 'src/gps_filter.dart';
export 'src/gps_models.dart';
export 'src/offline_workout_sync.dart';

class KlsGpsTracker {
  // ===========================================================================
  // GPS PERMISSIONS / READINESS
  // ===========================================================================

  Future<KlsLocationPermission> requestPermission() {
    return KlsGpsTrackerPlatform.instance.requestPermission();
  }

  Future<KlsGpsReadiness> checkReadiness() {
    return KlsGpsTrackerPlatform.instance.checkReadiness();
  }

  // ===========================================================================
  // GPS TRACKING
  // ===========================================================================

  /// Starts a durable native GPS session and returns its workout id.
  ///
  /// Pass the client-generated [workoutId] when one already exists. When it is
  /// omitted, the native platform creates a UUID. Raw fixes are journaled on
  /// disk before they are emitted to [positionStream].
  Future<String> start({
    String? workoutId,
  }) {
    return KlsGpsTrackerPlatform.instance.start(
      workoutId: workoutId,
    );
  }

  /// Stops native location updates.
  ///
  /// When [finishWorkout] is false, the durable workout remains active and can
  /// later be resumed with the same workout id.
  Future<void> stop({
    bool finishWorkout = true,
  }) {
    return KlsGpsTrackerPlatform.instance.stop(
      finishWorkout: finishWorkout,
    );
  }

  Future<KlsGpsTrackingState> getTrackingState() {
    return KlsGpsTrackerPlatform.instance.getTrackingState();
  }

  // ===========================================================================
  // STORED GPS POINTS
  // ===========================================================================

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

  Future<void> deleteStoredWorkout(
    String workoutId,
  ) {
    return KlsGpsTrackerPlatform.instance.deleteStoredWorkout(
      workoutId,
    );
  }

  // ===========================================================================
  // NATIVE VOICE COACH
  //
  // On iOS these methods are backed by AVSpeechSynthesizer inside the native
  // plugin. This allows workout guidance to continue while the screen is locked
  // and Flutter timers may be suspended.
  // ===========================================================================

  /// Sends the complete voice schedule and voice settings to the native layer.
  ///
  /// Example:
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
  ) {
    return KlsGpsTrackerPlatform.instance.configureVoiceCoach(
      configuration,
    );
  }

  /// Starts the native voice timeline.
  ///
  /// Use [elapsedSeconds] when restoring a workout that has already been
  /// running for some time.
  Future<Map<String, dynamic>> startVoiceCoach({
    double elapsedSeconds = 0,
  }) {
    return KlsGpsTrackerPlatform.instance.startVoiceCoach(
      elapsedSeconds: elapsedSeconds,
    );
  }

  /// Pauses the native voice timeline without deleting its configuration.
  Future<void> pauseVoiceCoach() {
    return KlsGpsTrackerPlatform.instance.pauseVoiceCoach();
  }

  /// Resumes the previously paused native voice timeline.
  Future<void> resumeVoiceCoach() {
    return KlsGpsTrackerPlatform.instance.resumeVoiceCoach();
  }

  /// Stops the native voice assistant and clears its current schedule.
  Future<void> stopVoiceCoach() {
    return KlsGpsTrackerPlatform.instance.stopVoiceCoach();
  }

  /// Enables or disables native speech without deleting the configured cues.
  Future<Map<String, dynamic>> setVoiceCoachEnabled(
    bool enabled,
  ) {
    return KlsGpsTrackerPlatform.instance.setVoiceCoachEnabled(
      enabled,
    );
  }

  /// Speaks a dynamic phrase immediately.
  ///
  /// We will use this for messages that cannot always be scheduled in advance,
  /// for example live heart-rate warnings.
  Future<void> speakVoiceCoachNow(
    String text,
  ) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return Future<void>.value();
    }

    return KlsGpsTrackerPlatform.instance.speakVoiceCoachNow(
      trimmed,
    );
  }

  /// Returns diagnostic information about the current native voice assistant.
  Future<Map<String, dynamic>> getVoiceCoachState() {
    return KlsGpsTrackerPlatform.instance.getVoiceCoachState();
  }

  // ===========================================================================
  // LIVE GPS STREAM
  // ===========================================================================

  Stream<KlsGpsPoint> get positionStream =>
      KlsGpsTrackerPlatform.instance.positionStream;
}
