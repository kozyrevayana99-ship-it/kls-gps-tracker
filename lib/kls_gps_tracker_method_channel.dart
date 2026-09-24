import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kls_gps_tracker_platform_interface.dart';
import 'src/gps_models.dart';

/// An implementation of [KlsGpsTrackerPlatform] that uses method channels.
class MethodChannelKlsGpsTracker extends KlsGpsTrackerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kls_gps_tracker');

  @visibleForTesting
  final eventChannel = const EventChannel('kls_gps_tracker/positions');

  Stream<KlsGpsPoint>? _positionStream;

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Map<String, dynamic> _normalizeMap(
    Map<Object?, Object?>? value, {
    required String errorCode,
    required String errorMessage,
  }) {
    if (value == null) {
      throw PlatformException(
        code: errorCode,
        message: errorMessage,
      );
    }

    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): entry.value,
    };
  }

  // ===========================================================================
  // GPS PERMISSIONS / READINESS
  // ===========================================================================

  @override
  Future<KlsLocationPermission> requestPermission() async {
    final value = await methodChannel.invokeMethod<String>(
      'requestPermission',
    );

    return KlsGpsReadiness.fromMap({
      'permission': value,
      'serviceEnabled': true,
    }).permission;
  }

  @override
  Future<KlsGpsReadiness> checkReadiness() async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'checkReadiness',
    );

    if (value == null) {
      throw PlatformException(
        code: 'invalid_readiness',
        message: 'Native GPS readiness response was empty.',
      );
    }

    return KlsGpsReadiness.fromMap(
      value,
    );
  }

  // ===========================================================================
  // GPS TRACKING
  // ===========================================================================

  @override
  Future<String> start({
    String? workoutId,
  }) async {
    final value = await methodChannel.invokeMethod<String>(
      'start',
      <String, Object?>{
        'workoutId': workoutId,
      },
    );

    if (value == null || value.isEmpty) {
      throw PlatformException(
        code: 'invalid_workout_id',
        message: 'Native GPS start did not return a workout id.',
      );
    }

    return value;
  }

  @override
  Future<void> stop({
    bool finishWorkout = true,
  }) {
    return methodChannel.invokeMethod<void>(
      'stop',
      <String, Object?>{
        'finishWorkout': finishWorkout,
      },
    );
  }

  @override
  Future<KlsGpsTrackingState> getTrackingState() async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getTrackingState',
    );

    if (value == null) {
      throw PlatformException(
        code: 'invalid_tracking_state',
        message: 'Native GPS tracking state was empty.',
      );
    }

    return KlsGpsTrackingState.fromMap(
      value,
    );
  }

  // ===========================================================================
  // STORED GPS POINTS
  // ===========================================================================

  @override
  Future<List<KlsGpsPoint>> getStoredPoints({
    required String workoutId,
    int afterPointIndex = -1,
    int limit = 1000,
  }) async {
    final value = await methodChannel.invokeListMethod<Object?>(
      'getStoredPoints',
      <String, Object?>{
        'workoutId': workoutId,
        'afterPointIndex': afterPointIndex,
        'limit': limit.clamp(1, 5000),
      },
    );

    return (value ?? const <Object?>[])
        .map(
          (item) => KlsGpsPoint.fromMap(
            item as Map<Object?, Object?>,
          ),
        )
        .toList(
          growable: false,
        );
  }

  @override
  Future<List<String>> listStoredWorkoutIds() async {
    final value = await methodChannel.invokeListMethod<String>(
      'listStoredWorkoutIds',
    );

    return List<String>.unmodifiable(
      value ?? const <String>[],
    );
  }

  @override
  Future<void> deleteStoredWorkout(
    String workoutId,
  ) {
    return methodChannel.invokeMethod<void>(
      'deleteStoredWorkout',
      <String, Object?>{
        'workoutId': workoutId,
      },
    );
  }

  // ===========================================================================
  // NATIVE VOICE COACH
  // ===========================================================================

  @override
  Future<Map<String, dynamic>> configureVoiceCoach(
    Map<String, dynamic> configuration,
  ) async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'configureVoiceCoach',
      configuration,
    );

    return _normalizeMap(
      value,
      errorCode: 'invalid_voice_coach_state',
      errorMessage:
          'Native voice coach configuration returned an empty response.',
    );
  }

  @override
  Future<Map<String, dynamic>> startVoiceCoach({
    double elapsedSeconds = 0,
  }) async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'startVoiceCoach',
      <String, Object?>{
        'elapsedSeconds': elapsedSeconds,
      },
    );

    return _normalizeMap(
      value,
      errorCode: 'invalid_voice_coach_state',
      errorMessage: 'Native voice coach start returned an empty response.',
    );
  }

  @override
  Future<void> pauseVoiceCoach() {
    return methodChannel.invokeMethod<void>(
      'pauseVoiceCoach',
    );
  }

  @override
  Future<void> resumeVoiceCoach() {
    return methodChannel.invokeMethod<void>(
      'resumeVoiceCoach',
    );
  }

  @override
  Future<void> stopVoiceCoach() {
    return methodChannel.invokeMethod<void>(
      'stopVoiceCoach',
    );
  }

  @override
  Future<Map<String, dynamic>> setVoiceCoachEnabled(
    bool enabled,
  ) async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'setVoiceCoachEnabled',
      <String, Object?>{
        'enabled': enabled,
      },
    );

    return _normalizeMap(
      value,
      errorCode: 'invalid_voice_coach_state',
      errorMessage:
          'Native voice coach enable/disable returned an empty response.',
    );
  }

  @override
  Future<void> speakVoiceCoachNow(
    String text,
  ) async {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return;
    }

    await methodChannel.invokeMethod<void>(
      'speakVoiceCoachNow',
      <String, Object?>{
        'text': trimmed,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getVoiceCoachState() async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getVoiceCoachState',
    );

    return _normalizeMap(
      value,
      errorCode: 'invalid_voice_coach_state',
      errorMessage: 'Native voice coach state response was empty.',
    );
  }

  // ===========================================================================
  // LIVE GPS STREAM
  // ===========================================================================

  @override
  Stream<KlsGpsPoint> get positionStream {
    return _positionStream ??=
        eventChannel.receiveBroadcastStream().map(
              (event) => KlsGpsPoint.fromMap(
                event as Map<Object?, Object?>,
              ),
            );
  }
}
