import 'kls_gps_tracker_platform_interface.dart';
import 'src/gps_models.dart';

export 'src/gps_filter.dart';
export 'src/gps_models.dart';

class KlsGpsTracker {
  Future<KlsLocationPermission> requestPermission() {
    return KlsGpsTrackerPlatform.instance.requestPermission();
  }

  Future<KlsGpsReadiness> checkReadiness() {
    return KlsGpsTrackerPlatform.instance.checkReadiness();
  }

  Future<void> start() {
    return KlsGpsTrackerPlatform.instance.start();
  }

  Future<void> stop() {
    return KlsGpsTrackerPlatform.instance.stop();
  }

  Stream<KlsGpsPoint> get positionStream =>
      KlsGpsTrackerPlatform.instance.positionStream;
}
