// Regression test for the App Review 2.1(a) rejections (builds 15-23):
// "The app kept loading indefinitely when trying to login using the provided
// demo credentials or Sign in with Apple."
//
// ApiService's `onRequest` interceptor awaits a Keychain read BEFORE the
// request is dispatched. On iOS that read can block without returning *or*
// throwing — so `try/catch` cannot see it, and Dio's connect/receive timeouts
// have not started yet and never fire. `handler.next` is never called and the
// request's future never settles: no error, just a spinner forever.
//
// That one await sits under every authenticated call, which is why both the
// demo-credential login and Sign in with Apple hung identically, and why build
// 22 — which bounded the Keychain *write* in AuthProvider.setAuthenticated —
// did not fix it.
//
// This test simulates exactly that: a secure-storage channel that never
// answers. The assertion is deliberately weak about the OUTCOME (the request
// may succeed unauthenticated or fail on the network) and strict about the one
// thing that broke: it must SETTLE rather than hang.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_fresh/providers/auth_provider.dart';
import 'package:market_fresh/services/api_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('a Keychain read that never returns cannot strand a request', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _secureStorageChannel,
      (call) => Completer<Object?>().future, // hangs forever, never throws
    );

    ApiService().init();

    // Whatever happens — a 2xx without the auth header, or a network error —
    // this future must complete. Before the fix it never did.
    await expectLater(
      ApiService().getCategories().then((_) => 'settled').catchError((_) => 'settled'),
      completion('settled'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // AuthProvider holds its OWN FlutterSecureStorage instance, separate from
  // ApiService's — which is why bounding the reads above did not cover it, and
  // why the spinner survived into build 25. init() runs at cold start and gates
  // the splash screen's auth resolution: if it never returns, the app never
  // leaves the spinner. That is the "first install" condition App Review kept
  // hitting on the iPad.
  test('a Keychain that never answers cannot strand AuthProvider.init', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _secureStorageChannel,
      (call) => Completer<Object?>().future, // hangs forever, never throws
    );

    // No ApiService().init() here: with the Keychain hung the token read yields
    // null, so init() resolves to "unauthenticated" without dispatching a
    // request. (ApiService is a singleton — init() twice throws.)
    await expectLater(
      AuthProvider().init().then((_) => 'settled').catchError((_) => 'settled'),
      completion('settled'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
