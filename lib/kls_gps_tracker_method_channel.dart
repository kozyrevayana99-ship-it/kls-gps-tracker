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
  Future<void> start() => methodChannel.invokeMethod<void>('start');

  @override
  Future<void> stop() => methodChannel.invokeMethod<void>('stop');

  @override
  Stream<KlsGpsPoint> get positionStream {
    return _positionStream ??= eventChannel.receiveBroadcastStream().map(
      (event) => KlsGpsPoint.fromMap(event as Map<Object?, Object?>),
    );
  }
}
