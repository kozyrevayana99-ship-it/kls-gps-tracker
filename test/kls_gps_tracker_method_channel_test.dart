import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kls_gps_tracker/kls_gps_tracker.dart';
import 'package:kls_gps_tracker/kls_gps_tracker_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelKlsGpsTracker();
  const channel = MethodChannel('kls_gps_tracker');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          calls.add(methodCall.method);
          return switch (methodCall.method) {
            'requestPermission' => 'precise',
            'checkReadiness' => <String, Object>{
              'permission': 'precise',
              'serviceEnabled': true,
            },
            'start' || 'stop' => null,
            _ => throw PlatformException(code: 'not_implemented'),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps permission and readiness responses', () async {
    expect(await platform.requestPermission(), KlsLocationPermission.precise);
    final readiness = await platform.checkReadiness();
    expect(readiness.permission, KlsLocationPermission.precise);
    expect(readiness.serviceStatus, KlsLocationServiceStatus.enabled);
    expect(readiness.canStart, isTrue);
  });

  test('sends start and stop methods', () async {
    await platform.start();
    await platform.stop();
    expect(calls, containsAllInOrder(['start', 'stop']));
  });
}
