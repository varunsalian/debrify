import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    /// Retained so the channel outlives `application(_:didFinishLaunchingWithOptions:)`.
    private var logChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        // tvOS reports a screen scale of 1.0, so Flutter lays out against a
        // 1920x1080 LOGICAL canvas. Android TV reports 2.0 for the same panel —
        // a 960x540 logical canvas — and every size in this app (type scale,
        // padding, card and row dimensions, focus rings) was designed against
        // that. Left at 1.0 the whole UI renders at half its intended physical
        // size: readable on a monitor at desk distance, unreadable from a sofa.
        //
        // Raising the view's contentScaleFactor makes the engine lay out
        // against 960x540 while still rasterising into the full 1920x1080
        // surface, so this costs no sharpness — same pixels, correct sizes.
        flutterViewController.view.contentScaleFactor = 2.0

        // Dart's print()/debugPrint() goes to stdout, which the device console
        // does not carry in a release build — so on real hardware every Dart
        // error, including the framework's own, is invisible. Bridge it to
        // NSLog, which `devicectl ... --console` does capture. Dart side opts in
        // (tvOS only) by reassigning debugPrint.
        let logChannel = FlutterMethodChannel(
            name: "debrify/tvlog",
            binaryMessenger: flutterViewController.binaryMessenger)
        logChannel.setMethodCallHandler { call, result in
            if call.method == "log", let message = call.arguments as? String {
                NSLog("[dart] %@", message)
            }
            result(nil)
        }
        self.logChannel = logChannel

        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
