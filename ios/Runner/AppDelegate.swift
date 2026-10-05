import Flutter
import UIKit
import Darwin
import CoreLocation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil { FirebaseApp.configure() }
    ProxBackgroundMatching.shared.restore()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let deviceChannel = FlutterMethodChannel(name: "prox/device_metadata", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    deviceChannel.setMethodCallHandler { call, result in
      guard call.method == "getMetadata" else { result(FlutterMethodNotImplemented); return }
      var hardware = utsname()
      uname(&hardware)
      let model = withUnsafePointer(to: &hardware.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
      }
      result(["device": model, "os": "iOS \(UIDevice.current.systemVersion)"])
    }
    let channel = FlutterMethodChannel(name: "prox/background_matching", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "configure" {
        let args = call.arguments as? [String: Any] ?? [:]
        result(ProxBackgroundMatching.shared.configure(args))
      } else if call.method == "status" {
        result(["permissionGranted": ProxBackgroundMatching.shared.permitted])
      } else { result(FlutterMethodNotImplemented) }
    }
  }
}


/// Runs independently of the Flutter engine on location-triggered launches.
final class ProxBackgroundMatching: NSObject, CLLocationManagerDelegate {
  static let shared = ProxBackgroundMatching()
  private let manager = CLLocationManager()
  private let defaults = UserDefaults.standard
  private var authHandle: AuthStateDidChangeListenerHandle?
  private var owner = ""
  private var deviceId = ""
  private var enabled = false
  private var travel = false
  private var generation = 0
  private var pending = false
  private var lastUploaded: CLLocation?
  private var lastWrite: Date?
  private let buildAvailable: Bool = {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "ProxBackgroundMatchingDartDefines") as? String,
          !raw.isEmpty else { return false }
    var available = false
    for item in raw.split(separator: ",") {
      guard let bytes = Data(base64Encoded: String(item)),
            let define = String(data: bytes, encoding: .utf8) else { return false }
      let parts = define.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.first == "PROX_BACKGROUND_MATCHING_AVAILABLE" {
        available = parts.count == 2 && parts[1] == "true"
      }
    }
    return available
  }()
  var permitted: Bool { buildAvailable && manager.authorizationStatus == .authorizedAlways && CLLocationManager.locationServicesEnabled() }

  private func clearDisabledBuild() {
    for key in ["prox.bg.enabled", "prox.bg.uid", "prox.bg.deviceId", "prox.bg.mode"] {
      defaults.removeObject(forKey: key)
    }
    stop()
  }

  override private init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = kCLDistanceFilterNone
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    // Standard reduced-accuracy updates maintain stationary discoverability.
    // Significant-change monitoring permits system-driven relaunch after termination.
    manager.pausesLocationUpdatesAutomatically = false
  }
  func restore() {
    guard buildAvailable else { clearDisabledBuild(); return }
    if authHandle == nil {
      authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
        guard let self = self else { return }
        if self.enabled && user?.uid != self.owner { self.stop() }
      }
    }
    guard defaults.bool(forKey: "prox.bg.enabled") else { return }
    _ = configure([
      "uid": defaults.string(forKey: "prox.bg.uid") ?? "",
      "deviceId": defaults.string(forKey: "prox.bg.deviceId") ?? "",
      "mode": defaults.string(forKey: "prox.bg.mode") ?? "normal", "enabled": true
    ])
  }
  func configure(_ args: [String: Any]) -> Bool {
    guard buildAvailable else { clearDisabledBuild(); return false }
    let uid = args["uid"] as? String ?? ""
    let nextMode = args["mode"] as? String ?? "normal"
    let requested = args["enabled"] as? Bool ?? false
    let nextDevice = args["deviceId"] as? String ?? ""
    let allowed = requested && permitted && Auth.auth().currentUser?.uid == uid && !uid.isEmpty
    defaults.set(allowed, forKey: "prox.bg.enabled")
    defaults.set(uid, forKey: "prox.bg.uid")
    defaults.set(nextDevice, forKey: "prox.bg.deviceId")
    defaults.set(nextMode, forKey: "prox.bg.mode")
    if !allowed { stop(); return false }
    if enabled && owner == uid && deviceId == nextDevice && travel == (nextMode == "travel") { return true }
    generation += 1
    pending = false
    owner = uid
    deviceId = nextDevice
    travel = nextMode == "travel"
    enabled = true
    lastWrite = nil
    lastUploaded = nil
    manager.startMonitoringSignificantLocationChanges()
    manager.startUpdatingLocation()
    return true
  }
  private func stop() {
    enabled = false
    generation += 1
    pending = false
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if !permitted { stop() }
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if (error as? CLError)?.code == .denied { stop() }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard buildAvailable, enabled, permitted, !pending, Auth.auth().currentUser?.uid == owner,
          let location = locations.last else { return }
    let now = Date()
    let age = now.timeIntervalSince(location.timestamp)
    guard age >= -5, age <= 120, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 220 else { return }
    let gap = lastWrite.map { now.timeIntervalSince($0) } ?? .infinity
    if gap < (travel ? 60 : 300) { return }
    if !travel, let last = lastUploaded, location.distance(from: last) < 250, gap < 900 { return }
    let revision = generation
    let uid = owner
    pending = true
    // A short OS task allows this one write to finish; it does not keep the app awake.
    var task = UIBackgroundTaskIdentifier.invalid
    task = UIApplication.shared.beginBackgroundTask(withName: "Prox area update") {
      if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
    }
    Firestore.firestore().document("users/\(uid)/backgroundPresence/current").setData([
      "enabled": true, "deviceId": deviceId,
      "latitude": (location.coordinate.latitude * 1000).rounded() / 1000,
      "longitude": (location.coordinate.longitude * 1000).rounded() / 1000,
      "locationAt": Timestamp(date: location.timestamp), "receivedAt": FieldValue.serverTimestamp(),
      "accuracyMeters": location.horizontalAccuracy + 80, "speedMps": location.speed,
      "utcOffsetMinutes": TimeZone.current.secondsFromGMT(for: now) / 60,
      "expiresAt": Timestamp(date: now.addingTimeInterval(1800))
    ]) { [weak self] error in
      if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
      guard let self = self, self.generation == revision else { return }
      self.pending = false
      if error == nil { self.lastUploaded = location; self.lastWrite = now }
    }
  }
}
