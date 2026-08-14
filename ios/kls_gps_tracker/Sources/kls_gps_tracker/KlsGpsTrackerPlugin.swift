import CoreLocation
import Flutter
import UIKit

public final class KlsGpsTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  CLLocationManagerDelegate
{
  private let locationManager = CLLocationManager()
  private let storage = KlsGpsStorage()
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
    instance.resumeActiveWorkoutIfPossible()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "checkReadiness":
      result(readiness())
    case "start":
      start(call: call, result: result)
    case "stop":
      stop(call: call, result: result)
    case "getTrackingState":
      result(trackingState())
    case "getStoredPoints":
      getStoredPoints(call: call, result: result)
    case "listStoredWorkoutIds":
      result(storage.listStoredWorkoutIds())
    case "deleteStoredWorkout":
      deleteStoredWorkout(call: call, result: result)
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

  private func start(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

    let arguments = call.arguments as? [String: Any]
    let requestedWorkoutId = arguments?["workoutId"] as? String
    do {
      let workoutId = try storage.beginWorkout(requestedWorkoutId: requestedWorkoutId)
      configureBackgroundUpdates()
      storage.setTracking(true)
      locationManager.startUpdatingLocation()
      result(workoutId)
    } catch {
      result(
        FlutterError(
          code: "workout_already_active",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func stop(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let finishWorkout = arguments?["finishWorkout"] as? Bool ?? true
    locationManager.stopUpdatingLocation()
    locationManager.allowsBackgroundLocationUpdates = false
    if finishWorkout {
      storage.finishWorkout(storage.activeWorkoutId)
    } else {
      storage.pauseWorkout()
    }
    result(nil)
  }

  private func resumeActiveWorkoutIfPossible() {
    guard storage.activeWorkoutId != nil else { return }
    guard storage.shouldAutoResume else { return }
    guard CLLocationManager.locationServicesEnabled() else { return }
    let status = permissionStatus()
    guard status == "precise" || status == "approximate" else { return }
    configureBackgroundUpdates()
    storage.setTracking(true)
    locationManager.startUpdatingLocation()
  }

  private func configureBackgroundUpdates() {
    let enabled = backgroundCapable()
    locationManager.allowsBackgroundLocationUpdates = enabled
    locationManager.showsBackgroundLocationIndicator = enabled
  }

  private func readiness() -> [String: Any] {
    [
      "permission": permissionStatus(),
      "serviceEnabled": CLLocationManager.locationServicesEnabled(),
      "backgroundCapable": backgroundCapable(),
    ]
  }

  private func trackingState() -> [String: Any?] {
    let workoutId = storage.activeWorkoutId
    return [
      "isTracking": storage.isTracking,
      "workoutId": workoutId,
      "pointCount": workoutId.map { storage.pointCount(workoutId: $0) } ?? 0,
      "backgroundCapable": backgroundCapable(),
    ]
  }

  private func getStoredPoints(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let workoutId = arguments?["workoutId"] as? String, !workoutId.isEmpty else {
      result(
        FlutterError(
          code: "invalid_workout_id",
          message: "workoutId is required.",
          details: nil
        )
      )
      return
    }
    let afterPointIndex = (arguments?["afterPointIndex"] as? NSNumber)?.intValue ?? -1
    let limit = (arguments?["limit"] as? NSNumber)?.intValue ?? 1000
    do {
      result(
        try storage.readPoints(
          workoutId: workoutId,
          afterPointIndex: afterPointIndex,
          limit: limit
        )
      )
    } catch {
      result(
        FlutterError(
          code: "storage_error",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func deleteStoredWorkout(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let workoutId = arguments?["workoutId"] as? String, !workoutId.isEmpty else {
      result(
        FlutterError(
          code: "invalid_workout_id",
          message: "workoutId is required.",
          details: nil
        )
      )
      return
    }
    do {
      try storage.deleteWorkout(workoutId)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "storage_error",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func backgroundCapable() -> Bool {
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    return modes?.contains("location") == true
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

  @available(iOS 14.0, *)
  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    completePermissionRequest(status: manager.authorizationStatus)
  }

  public func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    completePermissionRequest(status: status)
  }

  private func completePermissionRequest(status: CLAuthorizationStatus) {
    guard let pendingResult = permissionResult else { return }
    guard status != .notDetermined else { return }
    permissionResult = nil
    pendingResult(permissionStatus())
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let workoutId = storage.activeWorkoutId else { return }

    for location in locations {
      guard CLLocationCoordinate2DIsValid(location.coordinate) else { continue }
      do {
        // The durable RAW journal is written before Flutter sees the fix. The
        // Dart quality filter decides later whether it contributes to distance.
        let point = try storage.append(location: location, workoutId: workoutId)
        eventSink?(point)
      } catch {
        eventSink?(
          FlutterError(
            code: "storage_error",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
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
