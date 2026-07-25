// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kls_gps_tracker/kls_gps_tracker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkReadiness returns a native GPS state', (
    WidgetTester tester,
  ) async {
    final plugin = KlsGpsTracker();
    final readiness = await plugin.checkReadiness();
    expect(KlsLocationPermission.values, contains(readiness.permission));
  });
}
