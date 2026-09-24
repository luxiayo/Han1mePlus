import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.liar.han1meplus/fullscreen"

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
    guard fullscreenChannel == nil, let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else { return }
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.engine.binaryMessenger)
    fullscreenChannel = methodChannel
    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self, let window = self.mainFlutterWindow else { result(false); return }
      switch call.method {
      case "toggleFullScreen":
        window.toggleFullScreen(nil)
        result(true)
      case "exitFullscreenIfActive":
        // 幂等退出：系统已先退出全屏（绿色按钮）时不再 toggle，避免二次进出。
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var fullscreenChannel: FlutterMethodChannel?
}
