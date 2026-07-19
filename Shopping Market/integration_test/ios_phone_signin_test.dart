// Regression test for the App Review 2.1(a) "sign-in spinner spins forever"
// rejections (builds 13-18): on iOS, `FirebaseAuth.verifyPhoneNumber` /
// `signInWithCredential` / `getIdToken()` go through native platform-channel
// calls that could stall indefinitely without ever invoking a callback —
// something no amount of Android testing ever caught, because the stall was
// iOS-specific. `FirebasePhoneRest` (services/firebase_phone_rest.dart)
// replaces that path with plain HTTPS for Firebase's test phone number, which
// this test exercises end-to-end on a real iOS runtime (simulator, via
// Codemagic's `flutter test integration_test` on macOS CI) — the same Dart
// engine and platform-channel stack that broke, just without physical
// hardware. A hang here fails the CI step and blocks the TestFlight
// publish, instead of shipping a build that only fails in front of App Review.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:market_fresh/services/firebase_phone_rest.dart';
import 'package:market_fresh/services/api_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Firebase test-number REST sign-in completes on iOS and the backend '
    'accepts the resulting token',
    (tester) async {
      await Firebase.initializeApp();

      const e164 = '+201000000099';
      const localPhone = '01000000099';
      const code = '123456';

      expect(FirebasePhoneRest.isTestNumber(e164), isTrue,
          reason: 'Test relies on the App Review demo number staying '
              'registered as a Firebase test number.');

      final sessionInfo = await FirebasePhoneRest.sendVerificationCode(e164)
          .timeout(const Duration(seconds: 20),
              onTimeout: () => throw TestFailure(
                  'sendVerificationCode hung past 20s on iOS — this is '
                  'exactly the App Review spinner bug.'));
      expect(sessionInfo, isNotEmpty);

      final idToken = await FirebasePhoneRest.signIn(
        sessionInfo: sessionInfo,
        code: code,
      ).timeout(const Duration(seconds: 20),
          onTimeout: () => throw TestFailure(
              'signIn hung past 20s on iOS — this is exactly the App '
              'Review spinner bug.'));
      expect(idToken, isNotEmpty);

      ApiService().init();
      final res = await ApiService()
          .firebaseTokenLogin(idToken: idToken, phone: localPhone)
          .timeout(const Duration(seconds: 20),
              onTimeout: () => throw TestFailure(
                  'Backend /auth/firebase-token/ exchange hung past 20s.'));
      expect(res['user'], isNotNull,
          reason: 'Backend should return a user object for the demo account.');
    },
  );
}
