
import 'kls_gps_tracker_platform_interface.dart';

class KlsGpsTracker {
  Future<String?> getPlatformVersion() {
    return KlsGpsTrackerPlatform.instance.getPlatformVersion();
  }
}
