import Flutter
import UIKit

/// Presents 学期周数 / 提醒时间 with official [UIGlassEffect] sheet chrome
/// and a system [UIPickerView].
///
/// Spec:
/// https://developer.apple.com/documentation/uikit/uiglasseffect
/// https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
enum LiquidGlassPickerPresenter {
  private static let channelName = "campus_app/liquid_glass_picker"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let title = args["title"] as? String,
            let options = args["options"] as? [String] else {
        result(
          FlutterError(
            code: "INVALID_ARG",
            message: "title and options required",
            details: nil
          )
        )
        return
      }
      let selectedIndex = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
      present(title: title, options: options, selectedIndex: selectedIndex, result: result)
    }
  }

  private static func present(
    title: String,
    options: [String],
    selectedIndex: Int,
    result: @escaping FlutterResult
  ) {
    guard let root = keyWindowRoot() else {
      result(
        FlutterError(code: "NO_ROOT", message: "No root view controller", details: nil)
      )
      return
    }

    let vc = LiquidGlassPickerViewController(
      titleText: title,
      options: options,
      selectedIndex: max(0, min(options.count - 1, selectedIndex))
    )
    vc.modalPresentationStyle = .overFullScreen
    vc.modalTransitionStyle = .crossDissolve
    vc.onFinish = { index in
      result(index) // null if cancelled → pass NSNull
    }
    root.present(vc, animated: true)
  }

  private static func keyWindowRoot() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
        return top(from: root)
      }
    }
    return nil
  }

  private static func top(from root: UIViewController) -> UIViewController {
    if let presented = root.presentedViewController {
      return top(from: presented)
    }
    return root
  }
}

private final class LiquidGlassPickerViewController: UIViewController, UIPickerViewDataSource,
  UIPickerViewDelegate
{
  var onFinish: ((Any?) -> Void)?

  private let titleText: String
  private let options: [String]
  private var selectedIndex: Int
  private var finished = false

  private let dimView = UIView()
  private let sheet = UIView()
  private let picker = UIPickerView()
  private var glassView: UIVisualEffectView?

  init(titleText: String, options: [String], selectedIndex: Int) {
    self.titleText = titleText
    self.options = options
    self.selectedIndex = selectedIndex
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    // Light dim so glass sheet can still read content behind (half-sheet peek).
    dimView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
    dimView.alpha = 0
    dimView.translatesAutoresizingMaskIntoConstraints = false
    let tap = UITapGestureRecognizer(target: self, action: #selector(cancel))
    dimView.addGestureRecognizer(tap)
    view.addSubview(dimView)

    sheet.translatesAutoresizingMaskIntoConstraints = false
    sheet.backgroundColor = .clear
    sheet.layer.cornerRadius = 34
    sheet.layer.cornerCurve = .continuous
    sheet.clipsToBounds = true
    view.addSubview(sheet)

    if #available(iOS 26.0, *) {
      // Clear glass: more translucent half-sheet so underlying UI peeks through.
      let glass = UIGlassEffect(style: .clear)
      glass.isInteractive = false
      let ev = UIVisualEffectView(effect: glass)
      ev.translatesAutoresizingMaskIntoConstraints = false
      ev.clipsToBounds = true
      ev.layer.cornerRadius = 34
      ev.layer.cornerCurve = .continuous
      ev.backgroundColor = .clear
      ev.contentView.backgroundColor = .clear
      sheet.addSubview(ev)
      glassView = ev
      NSLayoutConstraint.activate([
        ev.topAnchor.constraint(equalTo: sheet.topAnchor),
        ev.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
        ev.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
        ev.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
      ])
    } else {
      let ev = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      ev.translatesAutoresizingMaskIntoConstraints = false
      ev.backgroundColor = .clear
      sheet.addSubview(ev)
      glassView = ev
      NSLayoutConstraint.activate([
        ev.topAnchor.constraint(equalTo: sheet.topAnchor),
        ev.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
        ev.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
        ev.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
      ])
    }

    let content = glassView?.contentView ?? sheet

    let grabber = UIView()
    grabber.backgroundColor = UIColor.separator.withAlphaComponent(0.6)
    grabber.layer.cornerRadius = 2.5
    grabber.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(grabber)

    let cancelBtn = UIButton(type: .system)
    cancelBtn.setTitle("取消", for: .normal)
    cancelBtn.titleLabel?.font = .systemFont(ofSize: 17)
    cancelBtn.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    cancelBtn.translatesAutoresizingMaskIntoConstraints = false

    let doneBtn = UIButton(type: .system)
    doneBtn.setTitle("完成", for: .normal)
    doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    doneBtn.addTarget(self, action: #selector(done), for: .touchUpInside)
    doneBtn.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = UILabel()
    titleLabel.text = titleText
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textAlignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let toolbar = UIView()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(toolbar)
    toolbar.addSubview(cancelBtn)
    toolbar.addSubview(titleLabel)
    toolbar.addSubview(doneBtn)

    let sep = UIView()
    sep.backgroundColor = UIColor.separator.withAlphaComponent(0.5)
    sep.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(sep)

    picker.dataSource = self
    picker.delegate = self
    picker.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(picker)
    picker.selectRow(selectedIndex, inComponent: 0, animated: false)

    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      dimView.topAnchor.constraint(equalTo: view.topAnchor),
      dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      sheet.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
      sheet.heightAnchor.constraint(equalToConstant: 320),

      grabber.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
      grabber.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      grabber.widthAnchor.constraint(equalToConstant: 36),
      grabber.heightAnchor.constraint(equalToConstant: 5),

      toolbar.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 4),
      toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 48),

      cancelBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
      cancelBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      doneBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
      doneBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

      sep.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      sep.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      sep.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      sep.heightAnchor.constraint(equalToConstant: 0.5),

      picker.topAnchor.constraint(equalTo: sep.bottomAnchor),
      picker.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      picker.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    UIView.animate(withDuration: 0.25) { self.dimView.alpha = 1 }
  }

  func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    options.count
  }

  func pickerView(
    _ pickerView: UIPickerView,
    titleForRow row: Int,
    forComponent component: Int
  ) -> String? {
    options[row]
  }

  func pickerView(
    _ pickerView: UIPickerView,
    didSelectRow row: Int,
    inComponent component: Int
  ) {
    selectedIndex = row
  }

  @objc private func cancel() {
    finish(nil)
  }

  @objc private func done() {
    finish(selectedIndex)
  }

  private func finish(_ value: Any?) {
    guard !finished else { return }
    finished = true
    UIView.animate(withDuration: 0.2, animations: {
      self.dimView.alpha = 0
      self.sheet.transform = CGAffineTransform(translationX: 0, y: 40)
      self.sheet.alpha = 0
    }, completion: { _ in
      self.dismiss(animated: false) {
        self.onFinish?(value ?? NSNull())
      }
    })
  }
}
