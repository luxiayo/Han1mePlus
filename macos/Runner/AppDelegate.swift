import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.liar.han1meplus/fullscreen"
  private var fullscreenChannel: FlutterMethodChannel?
  // 仅当 Flutter 侧打开了全屏播放路由时为 true：此时 ESC 交给 Dart 处理而非系统。
  private var escapeIntercept = false

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
      case "setEscapeIntercept":
        self.escapeIntercept = (call.arguments as? Bool) ?? false
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // 原生全屏下 macOS 会用 ESC 退出全屏，Flutter 收不到按键。这里拦截并转交
    // Dart（退出全屏路由并回主页），与改动前路由式全屏的 ESC 行为一致。
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self, self.escapeIntercept, event.keyCode == 53,
            let window = self.mainFlutterWindow,
            window.styleMask.contains(.fullScreen) else { return event }
      self.fullscreenChannel?.invokeMethod("onEscape", arguments: nil)
      return nil
    }
  }
}
