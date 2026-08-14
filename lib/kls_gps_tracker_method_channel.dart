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

  @override
  Future<KlsLocationPermission> requestPermission() async {
    final value = await methodChannel.invokeMethod<String>('requestPermission');
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
    return KlsGpsReadiness.fromMap(value);
  }

  @override
  Future<String> start({String? workoutId}) async {
    final value = await methodChannel.invokeMethod<String>(
      'start',
      <String, Object?>{'workoutId': workoutId},
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
  Future<void> stop({bool finishWorkout = true}) =>
      methodChannel.invokeMethod<void>('stop', <String, Object?>{
        'finishWorkout': finishWorkout,
      });

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
    return KlsGpsTrackingState.fromMap(value);
  }

  @override
  Future<List<KlsGpsPoint>> getStoredPoints({
    required String workoutId,
    int afterPointIndex = -1,
    int limit = 1000,
  }) async {
    final value = await methodChannel
        .invokeListMethod<Object?>('getStoredPoints', <String, Object?>{
          'workoutId': workoutId,
          'afterPointIndex': afterPointIndex,
          'limit': limit.clamp(1, 5000),
        });
    return (value ?? const <Object?>[])
        .map((item) => KlsGpsPoint.fromMap(item as Map<Object?, Object?>))
        .toList(growable: false);
  }

  @override
  Future<List<String>> listStoredWorkoutIds() async {
    final value = await methodChannel.invokeListMethod<String>(
      'listStoredWorkoutIds',
    );
    return List<String>.unmodifiable(value ?? const <String>[]);
  }

  @override
  Future<void> deleteStoredWorkout(String workoutId) {
    return methodChannel.invokeMethod<void>(
      'deleteStoredWorkout',
      <String, Object?>{'workoutId': workoutId},
    );
  }

  @override
  Stream<KlsGpsPoint> get positionStream {
    return _positionStream ??= eventChannel.receiveBroadcastStream().map(
      (event) => KlsGpsPoint.fromMap(event as Map<Object?, Object?>),
    );
  }
}
