import Flutter
import UIKit

/// Hosts Apple's official [UIGlassEffect] via [UIVisualEffectView].
///
/// Spec:
/// https://developer.apple.com/documentation/uikit/uiglasseffect
/// https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
///
/// Do not paint extra Flutter borders/gradients on top — that is what made the
/// material look “fake”. Let the system glass render alone.
final class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    binaryMessenger messenger: FlutterBinaryMessenger
  ) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = true

    super.init()

    let params = args as? [String: Any] ?? [:]
    // Default clear: more see-through (regular is denser).
    let styleName = (params["style"] as? String)?.lowercased() ?? "clear"
    let interactive = (params["interactive"] as? Bool) ?? false
    let cornerRadius = CGFloat(
      (params["cornerRadius"] as? NSNumber)?.doubleValue ?? 28
    )

    container.layer.cornerRadius = cornerRadius
    container.layer.cornerCurve = .continuous
    container.layer.masksToBounds = true

    if #available(iOS 26.0, *) {
      let style: UIGlassEffect.Style =
        styleName == "clear" ? .clear : .regular
      let glass = UIGlassEffect(style: style)
      glass.isInteractive = interactive
      if let tintHex = params["tint"] as? String,
         let tint = Self.color(fromHex: tintHex) {
        glass.tintColor = tint
      }

      let effectView = UIVisualEffectView(effect: glass)
      effectView.translatesAutoresizingMaskIntoConstraints = false
      effectView.backgroundColor = .clear
      effectView.clipsToBounds = true
      effectView.layer.cornerRadius = cornerRadius
      effectView.layer.cornerCurve = .continuous
      // contentView must stay clear so only the glass material shows.
      effectView.contentView.backgroundColor = .clear

      container.addSubview(effectView)
      NSLayoutConstraint.activate([
        effectView.topAnchor.constraint(equalTo: container.topAnchor),
        effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ])
    } else {
      let effectView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
      )
      effectView.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(effectView)
      NSLayoutConstraint.activate([
        effectView.topAnchor.constraint(equalTo: container.topAnchor),
        effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ])
    }
  }

  func view() -> UIView { container }

  private static func color(fromHex hex: String) -> UIColor? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8,
          let value = UInt64(s, radix: 16) else { return nil }
    let a, r, g, b: UInt64
    if s.count == 8 {
      a = (value & 0xFF00_0000) >> 24
      r = (value & 0x00FF_0000) >> 16
      g = (value & 0x0000_FF00) >> 8
      b = value & 0x0000_00FF
    } else {
      a = 255
      r = (value & 0xFF0000) >> 16
      g = (value & 0x00FF00) >> 8
      b = value & 0x0000FF
    }
    return UIColor(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
}

final class LiquidGlassPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassPlatformView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      binaryMessenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
