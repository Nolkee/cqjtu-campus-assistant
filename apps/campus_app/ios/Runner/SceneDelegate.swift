import Flutter
import UIKit
import WebKit
import Foundation

class SceneDelegate: FlutterSceneDelegate {
  private let cookieChannelName = "campus_app/cookie_manager"
  private var cookieChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let flutterVC = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: cookieChannelName,
      binaryMessenger: flutterVC.binaryMessenger
    )
    channel.setMethodCallHandler(handleCookieChannel)
    cookieChannel = channel
  }

  private func handleCookieChannel(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCookies":
      getCookies(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getCookies(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let rawUrl = args["url"] as? String,
          let url = URL(string: rawUrl) else {
      result(FlutterError(code: "INVALID_ARG", message: "url parameter is required", details: nil))
      return
    }

    let host = (url.host ?? "").lowercased()
    let scheme = (url.scheme ?? "").lowercased()
    let requestPath = url.path.isEmpty ? "/" : url.path
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      let sharedCookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
      let allCookies = self.mergeCookies(primary: cookies, secondary: sharedCookies)
      let matched = self.matchCookies(
        cookies: allCookies,
        host: host,
        scheme: scheme,
        requestPath: requestPath,
        strictPath: true
      )
      let fallback = matched.isEmpty
        ? self.matchCookies(
            cookies: allCookies,
            host: host,
            scheme: scheme,
            requestPath: requestPath,
            strictPath: false
          )
        : matched
      let headerFields = HTTPCookie.requestHeaderFields(with: fallback)
      let value = headerFields["Cookie"] ?? ""
      result(value)
    }
  }

  private func mergeCookies(primary: [HTTPCookie], secondary: [HTTPCookie]) -> [HTTPCookie] {
    var map: [String: HTTPCookie] = [:]
    for cookie in primary + secondary {
      let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
      map[key] = cookie
    }
    return Array(map.values)
  }

  private func matchCookies(
    cookies: [HTTPCookie],
    host: String,
    scheme: String,
    requestPath: String,
    strictPath: Bool
  ) -> [HTTPCookie] {
    return cookies.filter { cookie in
      let domain = cookie.domain
        .lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      let domainMatch = host == domain || host.hasSuffix(".\(domain)")
      if !domainMatch {
        return false
      }
      if cookie.isSecure && scheme != "https" {
        return false
      }
      if strictPath {
        return requestPath.hasPrefix(cookie.path)
      }
      return true
    }
  }
}
