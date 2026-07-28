// Regression test for the App Review 2.1(a) rejection of build 22:
// "The app kept loading indefinitely when trying to login using the provided
// demo credentials or Sign in with Apple."
//
// Build 22 bounded the OTP screen but left the social path unbounded, so the
// social buttons could spin forever. There are two distinct ways that happens,
// and BOTH are covered here — fixing only one is exactly the mistake that
// produced rejections 15-19 and then 22 again:
//
//   1. the native sign-in platform-channel call never returns (a `finally`
//      cannot save you here — the `try` block it guards never completes), and
//   2. the backend exchange `handleSocialLogin` never settles.
//
// WHY THESE DRIVE THE GOOGLE BUTTON, NOT THE APPLE ONE: the Apple button is
// rendered behind `if (Platform.isIOS)`, which reads the real host OS and
// cannot be overridden in a host-run widget test, so it simply does not exist
// in the tree here. Both buttons funnel through the same `_completeSocialLogin`
// and are bounded by the same code, so exercising Google covers the identical
// invariant on every CI platform. Sign in with Apple also cannot be driven
// end-to-end anywhere in CI — it needs a real Apple ID and a native system
// modal — so rather than assert a successful login, these assert the invariant
// that actually broke: whatever the platform does, the button must never be
// left spinning.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:market_fresh/providers/auth_provider.dart';
import 'package:market_fresh/features/auth/presentation/phone_login_screen.dart';

const _googleChannel = MethodChannel('plugins.flutter.io/google_sign_in');

/// An [AuthProvider] whose social login never settles — the unbounded await
/// that stranded the spinner in build 22.
class _HangingAuthProvider extends AuthProvider {
  @override
  Future<SocialLoginResult> handleSocialLogin({
    required String provider,
    required String socialId,
    String? phone,
    String? fullName,
    String? email,
    String? token,
  }) =>
      Completer<SocialLoginResult>().future; // never completes
}

/// Resolves promptly, so the native-hang test isolates the platform hop rather
/// than the backend one.
class _FailingAuthProvider extends AuthProvider {
  @override
  Future<SocialLoginResult> handleSocialLogin({
    required String provider,
    required String socialId,
    String? phone,
    String? fullName,
    String? email,
    String? token,
  }) async =>
      SocialLoginResult.failed;
}

Widget _wrap(AuthProvider auth) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: PhoneLoginScreen()),
    );

bool get _isSpinning =>
    find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleChannel, null);
  });

  testWidgets(
    'social sign-in stops spinning when the native call never returns',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_googleChannel, (call) {
        // `init`/`signOut` must resolve so the flow reaches the hanging step.
        if (call.method != 'signIn') return Future<Object?>.value(null);
        return Completer<Object?>().future; // hangs forever
      });

      await tester.pumpWidget(_wrap(_FailingAuthProvider()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Google').first);
      await tester.pump();
      expect(_isSpinning, isTrue, reason: 'Tapping should show progress.');

      // Past the 120s cap on the native call.
      await tester.pump(const Duration(seconds: 121));
      await tester.pumpAndSettle();

      expect(_isSpinning, isFalse,
          reason: 'App Review 2.1(a), build 22: a native sign-in call that '
              'never returns left this spinner running forever.');
    },
  );

  testWidgets(
    'social sign-in stops spinning when the backend exchange never settles',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_googleChannel, (call) async {
        if (call.method != 'signIn') return null;
        return <String, dynamic>{
          'id': 'test-user',
          'email': 'review@example.com',
          'displayName': 'App Review',
        };
      });

      await tester.pumpWidget(_wrap(_HangingAuthProvider()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Google').first);
      await tester.pump();

      // Past the 20s cap on handleSocialLogin.
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();

      expect(_isSpinning, isFalse,
          reason: 'App Review 2.1(a), build 22: the unbounded '
              'handleSocialLogin await stranded this spinner.');
    },
  );
}
