import Flutter
import CoreLocation
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var trackingBridge: IosTrackingBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "ora/session_store",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: Any],
            let key = arguments["key"] as? String,
            !key.isEmpty else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "A storage key is required.", details: nil))
        return
      }
      switch call.method {
      case "read":
        result(SecureSessionKeychain.read(key: key))
      case "write":
        guard let value = arguments["value"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "A storage value is required.", details: nil))
          return
        }
        if SecureSessionKeychain.write(key: key, value: value) {
          result(nil)
        } else {
          result(FlutterError(code: "SECURE_STORAGE_FAILURE", message: "Secure session storage failed.", details: nil))
        }
      case "delete":
        SecureSessionKeychain.delete(key: key)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    trackingBridge = IosTrackingBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

private final class IosTrackingBridge: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var permissionResult: FlutterResult?
  private var sessionId: String?
  private var sequence: Int64 = 0
  private var tracking = false

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "ora/tracking/methods/v1", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "ora/tracking/events/v1", binaryMessenger: messenger)
    super.init()
    manager.delegate = self
    manager.activityType = .fitness
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 2
    manager.pausesLocationUpdatesAutomatically = false
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    if call.method != "acknowledgePendingAction",
       arguments?["contractVersion"] as? Int != 1 {
      result(FlutterError(code: "CONTRACT_MISMATCH", message: "Unsupported tracking contract version.", details: nil))
      return
    }
    switch call.method {
    case "clockSnapshot": result(clockSnapshot())
    case "status": result(status())
    case "requestPermission": requestPermission(result)
    case "prepare": prepare(result)
    case "cancelPrepare": cancelPrepare(result)
    case "start": start(arguments, result: result)
    case "pause": pause(arguments, result: result)
    case "resume": resume(arguments, result: result)
    case "stop": stop(arguments, result: result)
    case "acknowledgePendingAction": result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    switch manager.authorizationStatus {
    case .notDetermined:
      guard permissionResult == nil else {
        result(FlutterError(code: "PERMISSION_REQUEST_ACTIVE", message: "A permission request is already active.", details: nil))
        return
      }
      permissionResult = result
      manager.requestWhenInUseAuthorization()
    default:
      result(status())
    }
  }

  private func start(_ arguments: [String: Any]?, result: FlutterResult) {
    guard let id = arguments?["sessionId"] as? String, !id.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "A run session id is required.", details: nil))
      return
    }
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(code: "LOCATION_DISABLED", message: "Location services are disabled.", details: nil))
      return
    }
    guard manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse else {
      result(FlutterError(code: "LOCATION_PERMISSION_DENIED", message: "Location permission is required.", details: nil))
      return
    }
    if #available(iOS 14.0, *), manager.accuracyAuthorization != .fullAccuracy {
      result(FlutterError(code: "PRECISE_LOCATION_REQUIRED", message: "Precise location is required.", details: nil))
      return
    }
    sessionId = id
    tracking = true
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.startUpdatingLocation()
    persist(state: "tracking")
    emit(["type": "serviceState", "state": "tracking"])
    result(nil)
  }

  private func prepare(_ result: FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(code: "LOCATION_DISABLED", message: "Location services are disabled.", details: nil))
      return
    }
    guard manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse else {
      result(FlutterError(code: "LOCATION_PERMISSION_DENIED", message: "Location permission is required.", details: nil))
      return
    }
    if #available(iOS 14.0, *), manager.accuracyAuthorization != .fullAccuracy {
      result(FlutterError(code: "PRECISE_LOCATION_REQUIRED", message: "Precise location is required.", details: nil))
      return
    }
    tracking = false
    manager.allowsBackgroundLocationUpdates = false
    manager.showsBackgroundLocationIndicator = false
    manager.startUpdatingLocation()
    result(nil)
  }

  private func cancelPrepare(_ result: FlutterResult) {
    if !tracking { manager.stopUpdatingLocation() }
    result(nil)
  }

  private func pause(_ arguments: [String: Any]?, result: FlutterResult) {
    guard validSession(arguments) else {
      result(FlutterError(code: "SESSION_MISMATCH", message: "Run session does not match.", details: nil))
      return
    }
    manager.stopUpdatingLocation()
    tracking = false
    persist(state: "paused")
    emit(["type": "serviceState", "state": "paused"])
    result(nil)
  }

  private func resume(_ arguments: [String: Any]?, result: FlutterResult) {
    start(arguments, result: result)
  }

  private func stop(_ arguments: [String: Any]?, result: FlutterResult) {
    if sessionId != nil && !validSession(arguments) {
      result(FlutterError(code: "SESSION_MISMATCH", message: "Run session does not match.", details: nil))
      return
    }
    manager.stopUpdatingLocation()
    manager.allowsBackgroundLocationUpdates = false
    tracking = false
    sessionId = nil
    UserDefaults.standard.removeObject(forKey: "ora.tracking.sessionId")
    persist(state: "stopped")
    emit(["type": "serviceState", "state": "stopped"])
    result(nil)
  }

  private func validSession(_ arguments: [String: Any]?) -> Bool {
    guard let id = arguments?["sessionId"] as? String else { return false }
    return sessionId == nil || sessionId == id
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if let result = permissionResult, manager.authorizationStatus != .notDetermined {
      permissionResult = nil
      result(status())
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for location in locations {
      sequence += 1
      let received = Int64(ProcessInfo.processInfo.systemUptime * 1000)
      let age = max(0, Int64(Date().timeIntervalSince(location.timestamp) * 1000))
      var mocked = false
      if #available(iOS 15.0, *) {
        mocked = location.sourceInformation?.isSimulatedBySoftware ?? false
      }
      let accuracyValue: Any
      if location.horizontalAccuracy > 0 {
        accuracyValue = location.horizontalAccuracy
      } else {
        accuracyValue = NSNull()
      }
      emit([
        "contractVersion": 1,
        "type": "location",
        "sessionId": sessionId ?? "",
        "sequence": sequence,
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "accuracyMeters": accuracyValue,
        "provider": "core_location",
        "providerMonotonicMillis": received - age,
        "receivedMonotonicMillis": received,
        "epochMillis": Int64(location.timestamp.timeIntervalSince1970 * 1000),
        "isMocked": mocked
      ])
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let locationError = error as? CLError
    if locationError?.code == .locationUnknown {
      emit(["type": "providerUnavailable", "code": "LOCATION_PROVIDER_UNAVAILABLE"])
    } else {
      emit(["type": "error", "code": "LOCATION_PROVIDER_UNAVAILABLE", "message": "Core Location failed."])
    }
  }

  private func status() -> [String: Any] {
    let permission: String
    switch manager.authorizationStatus {
    case .notDetermined: permission = "notDetermined"
    case .denied: permission = "denied"
    case .restricted: permission = "restricted"
    case .authorizedAlways, .authorizedWhenInUse:
      if #available(iOS 14.0, *) {
        permission = manager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate"
      } else {
        permission = "precise"
      }
    @unknown default: permission = "restricted"
    }
    let activeCheckpoint: Any
    if tracking {
      activeCheckpoint = Int64(ProcessInfo.processInfo.systemUptime * 1000)
    } else {
      activeCheckpoint = NSNull()
    }
    return [
      "contractVersion": 1,
      "permission": permission,
      "locationEnabled": CLLocationManager.locationServicesEnabled(),
      "serviceActive": tracking,
      "trackingState": tracking ? "tracking" : "stopped",
      "notificationGranted": true,
      "sessionId": sessionId ?? "",
      "lastActiveMonotonicMillis": activeCheckpoint
    ]
  }

  private func clockSnapshot() -> [String: Int64] {
    let monotonic = Int64(ProcessInfo.processInfo.systemUptime * 1000)
    let epoch = Int64(Date().timeIntervalSince1970 * 1000)
    return [
      "monotonicMillis": monotonic,
      "epochMillis": epoch,
      "bootEpochMillis": epoch - monotonic
    ]
  }

  private func persist(state: String) {
    UserDefaults.standard.set(state, forKey: "ora.tracking.state")
    if let sessionId { UserDefaults.standard.set(sessionId, forKey: "ora.tracking.sessionId") }
  }

  private func emit(_ value: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.sink?(value) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

private enum SecureSessionKeychain {
  private static let service = "com.otorunners.ora.session"

  static func read(key: String) -> String? {
    var query = baseQuery(key: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func write(key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    let query = baseQuery(key: key)
    let update = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
  }

  static func delete(key: String) {
    SecItemDelete(baseQuery(key: key) as CFDictionary)
  }

  private static func baseQuery(key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }
}
