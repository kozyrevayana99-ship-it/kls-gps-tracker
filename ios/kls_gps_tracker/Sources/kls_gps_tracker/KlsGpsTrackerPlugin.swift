import CoreLocation
import Flutter
import UIKit

public final class KlsGpsTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  CLLocationManagerDelegate
{
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?
  private var permissionResult: FlutterResult?

  public override init() {
    super.init()
    locationManager.delegate = self
    locationManager.activityType = .fitness
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = 1
    locationManager.pausesLocationUpdatesAutomatically = false
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = KlsGpsTrackerPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "kls_gps_tracker",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "kls_gps_tracker/positions",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "checkReadiness":
      result(readiness())
    case "start":
      start(result: result)
    case "stop":
      locationManager.stopUpdatingLocation()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    let status = permissionStatus()
    if status == "precise" || status == "approximate" || status == "deniedForever" {
      result(status)
      return
    }
    guard permissionResult == nil else {
      result(
        FlutterError(
          code: "permission_request_in_progress",
          message: "A permission request is already active.",
          details: nil
        )
      )
      return
    }
    permissionResult = result
    locationManager.requestWhenInUseAuthorization()
  }

  private func start(result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(
        FlutterError(
          code: "location_service_disabled",
          message: "Location services are disabled.",
          details: nil
        )
      )
      return
    }
    let status = permissionStatus()
    guard status == "precise" || status == "approximate" else {
      result(
        FlutterError(
          code: "permission_denied",
          message: "Location permission has not been granted.",
          details: nil
        )
      )
      return
    }
    locationManager.startUpdatingLocation()
    result(nil)
  }

  private func readiness() -> [String: Any] {
    [
      "permission": permissionStatus(),
      "serviceEnabled": CLLocationManager.locationServicesEnabled(),
    ]
  }

  private func permissionStatus() -> String {
    let authorizationStatus: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      authorizationStatus = locationManager.authorizationStatus
    } else {
      authorizationStatus = CLLocationManager.authorizationStatus()
    }

    switch authorizationStatus {
    case .notDetermined:
      return "notDetermined"
    case .restricted, .denied:
      return "deniedForever"
    case .authorizedAlways, .authorizedWhenInUse:
      if #available(iOS 14.0, *) {
        return locationManager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate"
      }
      return "precise"
    @unknown default:
      return "notDetermined"
    }
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let pendingResult = permissionResult else { return }
    guard manager.authorizationStatus != .notDetermined else { return }
    permissionResult = nil
    pendingResult(permissionStatus())
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    var point: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "altitude": location.altitude,
      "timestampMillis": location.timestamp.timeIntervalSince1970 * 1000,
    ]
    if location.speed >= 0 {
      point["speed"] = location.speed
    }
    if location.course >= 0 {
      point["heading"] = location.course
    }
    eventSink?(point)
  }

  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let locationError = error as? CLError
    if locationError?.code == .locationUnknown {
      return
    }
    eventSink?(
      FlutterError(
        code: "location_error",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
