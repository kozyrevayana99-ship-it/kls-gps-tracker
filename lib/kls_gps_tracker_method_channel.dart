import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kls_gps_tracker_platform_interface.dart';

/// An implementation of [KlsGpsTrackerPlatform] that uses method channels.
class MethodChannelKlsGpsTracker extends KlsGpsTrackerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kls_gps_tracker');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
