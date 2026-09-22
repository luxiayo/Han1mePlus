import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channel = "com.liar.han1meplus/fullscreen"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    setupChannel()
  }

  private func setupChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    let methodChannel = FlutterMethodChannel(name: channel, binaryMessenger: controller.engine.binaryMessenger)
    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      guard call.method == "toggleFullScreen" else { result(FlutterMethodNotImplemented); return }
      guard let window = self?.mainFlutterWindow else { result(false); return }
      window.toggleFullScreen(nil)
      result(true)
    }
  }
}
