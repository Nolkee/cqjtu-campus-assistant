import Flutter
import UIKit

/// Native Liquid Glass tab bar.
///
/// - Material: Apple's official [UIGlassEffect] via [UIVisualEffectView]
/// - A→B drag: raw UIKit touch tracking on a dedicated surface (not UIPan + UIControl,
///   which fail under Flutter Platform View gesture competition)
///
/// Spec:
/// https://developer.apple.com/documentation/uikit/uiglasseffect
/// https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
final class LiquidGlassTabBarPlatformView: NSObject, FlutterPlatformView {
  /// Full-size host; re-lays out pill when Flutter sizes the platform view.
  private final class HostView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
      super.layoutSubviews()
      onLayout?()
    }
  }

  /// Captures all touches for continuous A→B (tap = short press, drag = move).
  private final class DragSurface: UIView {
    var onBegin: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: ((CGPoint, CGPoint) -> Void)? // location, velocity

    private var lastPoint: CGPoint = .zero
    private var lastTime: TimeInterval = 0
    private var velocity: CGPoint = .zero

    override init(frame: CGRect) {
      super.init(frame: frame)
      isMultipleTouchEnabled = false
      backgroundColor = .clear
      isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let t = touches.first else { return }
      let p = t.location(in: self)
      lastPoint = p
      lastTime = t.timestamp
      velocity = .zero
      onBegin?(p)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let t = touches.first else { return }
      let p = t.location(in: self)
      let dt = max(t.timestamp - lastTime, 0.0001)
      velocity = CGPoint(x: (p.x - lastPoint.x) / CGFloat(dt), y: (p.y - lastPoint.y) / CGFloat(dt))
      lastPoint = p
      lastTime = t.timestamp
      onMove?(p)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let t = touches.first else { return }
      let p = t.location(in: self)
      onEnd?(p, velocity)
      velocity = .zero
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let t = touches.first else { return }
      onEnd?(t.location(in: self), .zero)
      velocity = .zero
    }
  }

  private let host: HostView
  private let channel: FlutterMethodChannel
  private let capsule = UIView()
  private var glassView: UIVisualEffectView?
  private let contentLayer = DragSurface()
  private let pill = UIView()
  private var iconViews: [UIImageView] = []
  private var labelViews: [UILabel] = []
  private var labels: [String] = []
  private var symbols: [String] = []
  private var selectedIndex: Int = 0
  private var continuousIndex: CGFloat = 0
  private var lastHapticIndex: Int = 0
  private var touchStartIndex: CGFloat = 0
  private var didDrag = false
  private let hPad: CGFloat = 5
  private let pillMargin: CGFloat = 2
  private let barHeight: CGFloat = 56
  private let feedback = UISelectionFeedbackGenerator()

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    binaryMessenger messenger: FlutterBinaryMessenger
  ) {
    host = HostView(frame: frame)
    host.backgroundColor = .clear
    host.isOpaque = false
    channel = FlutterMethodChannel(
      name: "campus_app/liquid_glass_tab_bar_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    let params = args as? [String: Any] ?? [:]
    selectedIndex = max(0, (params["selectedIndex"] as? NSNumber)?.intValue ?? 0)
    continuousIndex = CGFloat(selectedIndex)
    lastHapticIndex = selectedIndex
    if let raw = params["items"] as? [[String: Any]] {
      labels = raw.map { ($0["label"] as? String) ?? "" }
      symbols = raw.map { ($0["symbol"] as? String) ?? "circle" }
    }

    buildHierarchy()
    wireTouches()
    feedback.prepare()
    host.onLayout = { [weak self] in self?.relayout() }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "setSelectedIndex" {
        let idx = (call.arguments as? NSNumber)?.intValue ?? 0
        self.setSelectedIndex(idx, animated: true, notify: false)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { host }

  private func buildHierarchy() {
    capsule.translatesAutoresizingMaskIntoConstraints = false
    capsule.backgroundColor = .clear
    capsule.layer.cornerRadius = 30
    capsule.layer.cornerCurve = .continuous
    capsule.clipsToBounds = true
    host.addSubview(capsule)

    NSLayoutConstraint.activate([
      capsule.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
      capsule.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
      capsule.topAnchor.constraint(equalTo: host.topAnchor),
      capsule.heightAnchor.constraint(equalToConstant: barHeight + hPad * 2),
    ])

    // Official Liquid Glass — prefer **clear** so underlying content peeks through
    // (Adopting Liquid Glass: material should infuse / elevate content, not obscure it).
    // https://developer.apple.com/documentation/uikit/uiglasseffect/style-swift.enum/clear
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .clear)
      effect.isInteractive = true
      let ev = UIVisualEffectView(effect: effect)
      ev.translatesAutoresizingMaskIntoConstraints = false
      ev.isUserInteractionEnabled = false
      ev.backgroundColor = .clear
      ev.contentView.backgroundColor = .clear
      capsule.addSubview(ev)
      glassView = ev
      NSLayoutConstraint.activate([
        ev.topAnchor.constraint(equalTo: capsule.topAnchor),
        ev.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
        ev.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
        ev.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
      ])
    } else {
      // Lighter system material for pre-iOS 26
      let ev = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      ev.translatesAutoresizingMaskIntoConstraints = false
      ev.isUserInteractionEnabled = false
      ev.backgroundColor = .clear
      capsule.addSubview(ev)
      glassView = ev
      NSLayoutConstraint.activate([
        ev.topAnchor.constraint(equalTo: capsule.topAnchor),
        ev.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
        ev.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
        ev.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
      ])
    }

    // Touch + chrome layer above glass (must be on top for A→B).
    contentLayer.translatesAutoresizingMaskIntoConstraints = false
    contentLayer.backgroundColor = .clear
    capsule.addSubview(contentLayer)
    NSLayoutConstraint.activate([
      contentLayer.topAnchor.constraint(equalTo: capsule.topAnchor),
      contentLayer.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
      contentLayer.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
      contentLayer.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
    ])

    // Soft selection highlight only — keep translucent so glass stays visible.
    pill.backgroundColor = UIColor { tc in
      tc.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.12)
        : UIColor.white.withAlphaComponent(0.28)
    }
    pill.layer.cornerRadius = 24
    pill.layer.cornerCurve = .continuous
    pill.isUserInteractionEnabled = false
    contentLayer.addSubview(pill)

    let stack = UIStackView()
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.alignment = .fill
    stack.isUserInteractionEnabled = false // all touches go to DragSurface
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentLayer.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentLayer.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentLayer.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: contentLayer.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentLayer.trailingAnchor),
    ])

    let count = max(labels.count, 1)
    for i in 0..<count {
      let cell = UIView()
      cell.isUserInteractionEnabled = false

      let column = UIStackView()
      column.axis = .vertical
      column.alignment = .center
      column.spacing = 2
      column.translatesAutoresizingMaskIntoConstraints = false
      column.isUserInteractionEnabled = false

      let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
      let symbol = i < symbols.count ? symbols[i] : "circle"
      let iv = UIImageView(image: UIImage(systemName: symbol, withConfiguration: config))
      iv.tintColor = .secondaryLabel
      iv.contentMode = .scaleAspectFit
      iv.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        iv.widthAnchor.constraint(equalToConstant: 22),
        iv.heightAnchor.constraint(equalToConstant: 22),
      ])

      let lab = UILabel()
      lab.text = i < labels.count ? labels[i] : ""
      lab.font = .systemFont(ofSize: 10, weight: .medium)
      lab.textColor = .secondaryLabel
      lab.textAlignment = .center

      column.addArrangedSubview(iv)
      column.addArrangedSubview(lab)
      cell.addSubview(column)
      NSLayoutConstraint.activate([
        column.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
        column.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])

      stack.addArrangedSubview(cell)
      iconViews.append(iv)
      labelViews.append(lab)
    }
  }

  private func wireTouches() {
    contentLayer.onBegin = { [weak self] p in
      guard let self else { return }
      self.didDrag = false
      self.touchStartIndex = self.indexForX(p.x)
      self.continuousIndex = self.touchStartIndex
      self.layoutPill(animated: false)
      self.updateItemColors()
    }
    contentLayer.onMove = { [weak self] p in
      guard let self else { return }
      let idx = self.indexForX(p.x)
      if abs(idx - self.touchStartIndex) > 0.04 {
        self.didDrag = true
      }
      self.continuousIndex = idx
      self.layoutPill(animated: false)
      self.updateItemColors()
      let nearest = Int(self.continuousIndex.rounded())
      if nearest != self.lastHapticIndex {
        self.lastHapticIndex = nearest
        self.feedback.selectionChanged()
      }
    }
    contentLayer.onEnd = { [weak self] p, velocity in
      guard let self else { return }
      var target = self.indexForX(p.x)
      if abs(velocity.x) > 280 {
        target = velocity.x > 0 ? ceil(self.continuousIndex) : floor(self.continuousIndex)
      }
      let maxIdx = max(0, self.labels.count - 1)
      let snap = Int(max(0, min(CGFloat(maxIdx), target.rounded())))
      // Tap (no meaningful drag): still select under finger.
      self.setSelectedIndex(snap, animated: true, notify: true)
      self.didDrag = false
    }
  }

  private func relayout() {
    layoutPill(animated: false)
    updateItemColors()
  }

  private func layoutPill(animated: Bool) {
    let width = contentLayer.bounds.width
    let height = contentLayer.bounds.height
    guard width > 8, !labelViews.isEmpty else { return }
    let n = CGFloat(labelViews.count)
    let slot = width / n
    let pillW = max(8, slot - pillMargin * 2)
    let dist = abs(continuousIndex - continuousIndex.rounded())
    let stretch = min(dist * 2, 1) * 0.22
    let stretchedW = pillW * (1 + stretch)
    let x = continuousIndex * slot + pillMargin - (stretchedW - pillW) / 2
    let frame = CGRect(
      x: max(0, min(x, width - stretchedW)),
      y: hPad,
      width: stretchedW,
      height: max(barHeight, height - hPad * 2)
    )
    let apply = { self.pill.frame = frame }
    if animated {
      UIView.animate(
        withDuration: 0.4,
        delay: 0,
        usingSpringWithDamping: 0.84,
        initialSpringVelocity: 0.55,
        options: [.allowUserInteraction, .beginFromCurrentState],
        animations: apply
      )
    } else {
      apply()
    }
  }

  private func updateItemColors() {
    let traits = host.traitCollection
    let secondary = UIColor.secondaryLabel.resolvedColor(with: traits)
    let accent = UIColor.systemBlue.resolvedColor(with: traits)
    for i in 0..<labelViews.count {
      let p = max(0, min(1, 1 - abs(continuousIndex - CGFloat(i))))
      let color = secondary.blended(with: accent, amount: p) ?? accent
      iconViews[i].tintColor = color
      labelViews[i].textColor = color
      labelViews[i].font = .systemFont(ofSize: 10, weight: p > 0.5 ? .semibold : .medium)
      let s: CGFloat = 1 + 0.06 * p
      iconViews[i].transform = CGAffineTransform(scaleX: s, y: s)
    }
  }

  private func indexForX(_ x: CGFloat) -> CGFloat {
    let width = contentLayer.bounds.width
    let n = CGFloat(max(labelViews.count, 1))
    guard width > 1 else { return 0 }
    return max(0, min(n - 1, x / (width / n) - 0.5))
  }

  private func setSelectedIndex(_ index: Int, animated: Bool, notify: Bool) {
    let clamped = max(0, min(labelViews.count - 1, index))
    selectedIndex = clamped
    continuousIndex = CGFloat(clamped)
    lastHapticIndex = clamped
    layoutPill(animated: animated)
    updateItemColors()
    if notify {
      channel.invokeMethod("onSelected", arguments: clamped)
    }
  }
}

final class LiquidGlassTabBarPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
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
    LiquidGlassTabBarPlatformView(
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

private extension UIColor {
  func blended(with other: UIColor, amount: CGFloat) -> UIColor? {
    let t = max(0, min(1, amount))
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
          other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
    return UIColor(
      red: r1 + (r2 - r1) * t,
      green: g1 + (g2 - g1) * t,
      blue: b1 + (b2 - b1) * t,
      alpha: a1 + (a2 - a1) * t
    )
  }
}
