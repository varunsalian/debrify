import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    /// Retained so the channel outlives `application(_:didFinishLaunchingWithOptions:)`.
    private var logChannel: FlutterMethodChannel?
    private var keyboardChannel: FlutterMethodChannel?

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

        // Apple TV's keyboard never tells Flutter the user finished.
        //
        // The engine raises a submit action from exactly one place — when the
        // platform inserts a literal "\n" (FlutterTextInputPlugin.mm,
        // -shouldChangeTextInRange:replacementText:). That is the iOS inline
        // keyboard's contract. tvOS presents a full-screen keyboard whose
        // action button commits and dismisses WITHOUT inserting anything, so
        // the trigger never fires and `onSubmitted` never runs: every text
        // field on the platform is a dead end.
        //
        // UIKit does post the fact, though — verified on an Apple TV 4K
        // (tvOS 26.6): pressing the action key emits exactly one
        // UITextFieldTextDidEndEditingNotification, and typing emits none.
        // Bridge it to Dart, which treats it as "editing finished".
        //
        // Caveat, measured rather than assumed: dismissing with the remote's
        // BACK button emits the SAME notification, so commit and cancel are
        // indistinguishable here. Dart side decides what that's worth.
        let keyboardChannel = FlutterMethodChannel(
            name: "debrify/tvkeyboard",
            binaryMessenger: flutterViewController.binaryMessenger)
        self.keyboardChannel = keyboardChannel
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UITextFieldTextDidEndEditingNotification"),
            object: nil,
            queue: .main
        ) { [weak keyboardChannel] _ in
            keyboardChannel?.invokeMethod("endEditing", arguments: nil)
        }


        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
