import 'package:flutter_test/flutter_test.dart';
import 'package:kls_gps_tracker/kls_gps_tracker.dart';
import 'package:kls_gps_tracker/kls_gps_tracker_method_channel.dart';
import 'package:kls_gps_tracker/kls_gps_tracker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKlsGpsTrackerPlatform
    with MockPlatformInterfaceMixin
    implements KlsGpsTrackerPlatform {
  var started = false;

  @override
  Future<KlsGpsReadiness> checkReadiness() async => const KlsGpsReadiness(
    permission: KlsLocationPermission.precise,
    serviceStatus: KlsLocationServiceStatus.enabled,
  );

  @override
  Stream<KlsGpsPoint> get positionStream => const Stream.empty();

  @override
  Future<KlsLocationPermission> requestPermission() async =>
      KlsLocationPermission.precise;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;
}

void main() {
  final initialPlatform = KlsGpsTrackerPlatform.instance;

  test('$MethodChannelKlsGpsTracker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelKlsGpsTracker>());
  });

  test('delegates GPS lifecycle to the platform', () async {
    final tracker = KlsGpsTracker();
    final fakePlatform = MockKlsGpsTrackerPlatform();
    KlsGpsTrackerPlatform.instance = fakePlatform;

    expect((await tracker.checkReadiness()).canStart, isTrue);
    expect(await tracker.requestPermission(), KlsLocationPermission.precise);

    await tracker.start();
    expect(fakePlatform.started, isTrue);
    await tracker.stop();
    expect(fakePlatform.started, isFalse);
  });
}
