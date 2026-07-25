import 'package:flutter_test/flutter_test.dart';
import 'package:kls_gps_tracker/kls_gps_tracker.dart';
import 'package:kls_gps_tracker/kls_gps_tracker_platform_interface.dart';
import 'package:kls_gps_tracker/kls_gps_tracker_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKlsGpsTrackerPlatform
    with MockPlatformInterfaceMixin
    implements KlsGpsTrackerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final KlsGpsTrackerPlatform initialPlatform = KlsGpsTrackerPlatform.instance;

  test('$MethodChannelKlsGpsTracker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelKlsGpsTracker>());
  });

  test('getPlatformVersion', () async {
    KlsGpsTracker klsGpsTrackerPlugin = KlsGpsTracker();
    MockKlsGpsTrackerPlatform fakePlatform = MockKlsGpsTrackerPlatform();
    KlsGpsTrackerPlatform.instance = fakePlatform;

    expect(await klsGpsTrackerPlugin.getPlatformVersion(), '42');
  });
}
