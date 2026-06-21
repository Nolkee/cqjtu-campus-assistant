/// Campus assistant runtime mode.
///
/// Decides where application data comes from:
/// - [localAndroid]: default Android app mode. The app talks directly to
///   school systems and keeps credentials on the device.
/// - [selfHosted]: optional user-hosted backend mode for web console,
///   multi-device access, and automation integrations.
enum CampusRuntimeMode {
  localAndroid,
  selfHosted,
}
