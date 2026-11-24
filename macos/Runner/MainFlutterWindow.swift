import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerClipboardChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The HTML version of what's on the clipboard, for pasting text with
  /// its formatting (lib/features/note_editor/clipboard_html.dart). The
  /// pasteboard plugin reads HTML only on Windows and the web.
  private func registerClipboardChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "noote/clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "html" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = NSPasteboard.general
      if let html = pasteboard.string(forType: .html) {
        result(html)
      } else if let data = pasteboard.data(forType: .html) {
        result(String(decoding: data, as: UTF8.self))
      } else {
        result(nil)
      }
    }
  }
}
