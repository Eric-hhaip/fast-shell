import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 默认窗口尺寸与最小尺寸：保证终端 + 文件面板可以同时铺开
    let defaultSize = NSSize(width: 1360, height: 880)
    let visible =
      self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height)
    let width = min(defaultSize.width, visible.width - 40)
    let height = min(defaultSize.height, visible.height - 40)
    let origin = NSPoint(
      x: visible.midX - width / 2,
      y: visible.midY - height / 2
    )
    self.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    self.minSize = NSSize(width: 1020, height: 640)

    // 标题栏只保留红绿灯按钮，不显示应用名
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
