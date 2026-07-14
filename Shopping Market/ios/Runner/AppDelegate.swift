import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Kick off APNs registration as early as possible. FirebaseAuth's phone-auth
    // silent-push handshake (used to verify the app without a reCAPTCHA) needs a
    // device token before the user reaches the phone-login screen; leaving this
    // to FlutterFire's automatic swizzling alone can lose the race on a fresh
    // install, surfacing a "notification-not-forwarded" error to the user.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
