import CoreLocation
import Foundation

final class KlsGpsStorage {
  private let fileManager = FileManager.default
  private let defaults = UserDefaults.standard
  private let lock = NSLock()

  private lazy var storageDirectory: URL = {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    var directory = base.appendingPathComponent("kls_gps_tracker", isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? directory.setResourceValues(resourceValues)
    return directory
  }()

  func beginWorkout(requestedWorkoutId: String?) throws -> String {
    lock.lock()
    defer { lock.unlock() }

    let requested = requestedWorkoutId?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let requested, !requested.isEmpty {
      try validateWorkoutId(requested)
    }

    let active = activeWorkoutId
    if let active, let requested, !requested.isEmpty, active != requested {
      throw storageError("Workout \(active) is already being recorded.")
    }

    let workoutId = active ?? ((requested?.isEmpty == false) ? requested! : UUID().uuidString.lowercased())
    defaults.set(workoutId, forKey: Keys.activeWorkoutId)
    defaults.set(true, forKey: Keys.shouldAutoResume)
    _ = ensureNextPointIndex(workoutId)
    return workoutId
  }

  var activeWorkoutId: String? {
    defaults.string(forKey: Keys.activeWorkoutId)?.nilIfEmpty
  }

  var isTracking: Bool {
    defaults.bool(forKey: Keys.isTracking)
  }

  func setTracking(_ value: Bool) {
    defaults.set(value, forKey: Keys.isTracking)
  }

  var shouldAutoResume: Bool {
    defaults.bool(forKey: Keys.shouldAutoResume)
  }

  func pauseWorkout() {
    defaults.set(false, forKey: Keys.isTracking)
    defaults.set(false, forKey: Keys.shouldAutoResume)
  }

  func finishWorkout(_ workoutId: String?) {
    lock.lock()
    defer { lock.unlock() }

    defaults.set(false, forKey: Keys.isTracking)
    defaults.set(false, forKey: Keys.shouldAutoResume)
    if workoutId == nil || activeWorkoutId == workoutId {
      defaults.removeObject(forKey: Keys.activeWorkoutId)
    }
  }

  func append(location: CLLocation, workoutId: String) throws -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }

    try validateWorkoutId(workoutId)
    let pointIndex = ensureNextPointIndex(workoutId)
    var point: [String: Any] = [
      "workoutId": workoutId,
      "pointIndex": pointIndex,
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "timestampMillis": location.timestamp.timeIntervalSince1970 * 1000,
      "provider": "coreLocation",
      "isMock": false,
    ]

    if location.verticalAccuracy >= 0 {
      point["altitude"] = location.altitude
      point["verticalAccuracy"] = location.verticalAccuracy
    }
    if location.speed >= 0 {
      point["speed"] = location.speed
      point["speedAccuracy"] = location.speedAccuracy
    }
    if location.course >= 0 {
      point["heading"] = location.course
      if #available(iOS 13.4, *) {
        point["headingAccuracy"] = location.courseAccuracy
      }
    }
    if #available(iOS 15.0, *) {
      point["isMock"] = location.sourceInformation?.isSimulatedBySoftware == true
    }

    var encoded = try JSONSerialization.data(withJSONObject: point)
    encoded.append(0x0A)
    let fileURL = fileURL(for: workoutId)
    if !fileManager.fileExists(atPath: fileURL.path) {
      fileManager.createFile(atPath: fileURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: fileURL)
    handle.seekToEndOfFile()
    handle.write(encoded)
    handle.synchronizeFile()
    handle.closeFile()

    defaults.set(pointIndex + 1, forKey: nextIndexKey(workoutId))
    return point
  }

  func readPoints(
    workoutId: String,
    afterPointIndex: Int,
    limit: Int
  ) throws -> [[String: Any]] {
    try validateWorkoutId(workoutId)
    let fileURL = fileURL(for: workoutId)
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

    let raw = try String(contentsOf: fileURL, encoding: .utf8)
    var result: [[String: Any]] = []
    let safeLimit = min(max(limit, 1), 5000)
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
      guard
        let data = String(line).data(using: .utf8),
        let point = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let pointIndex = (point["pointIndex"] as? NSNumber)?.intValue,
        pointIndex > afterPointIndex
      else {
        continue
      }
      result.append(point)
      if result.count >= safeLimit { break }
    }
    return result
  }

  func pointCount(workoutId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return ensureNextPointIndex(workoutId)
  }

  func listStoredWorkoutIds() -> [String] {
    let files = (try? fileManager.contentsOfDirectory(
      at: storageDirectory,
      includingPropertiesForKeys: nil
    )) ?? []
    return files
      .filter { $0.pathExtension == "jsonl" }
      .map { $0.deletingPathExtension().lastPathComponent }
      .sorted()
  }

  func deleteWorkout(_ workoutId: String) throws {
    lock.lock()
    defer { lock.unlock() }

    try validateWorkoutId(workoutId)
    if activeWorkoutId == workoutId {
      throw storageError("The active workout cannot be deleted.")
    }
    let fileURL = fileURL(for: workoutId)
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    defaults.removeObject(forKey: nextIndexKey(workoutId))
  }

  private func ensureNextPointIndex(_ workoutId: String) -> Int {
    let key = nextIndexKey(workoutId)
    if defaults.object(forKey: key) != nil {
      return defaults.integer(forKey: key)
    }

    let fileURL = fileURL(for: workoutId)
    let count: Int
    if let raw = try? String(contentsOf: fileURL, encoding: .utf8) {
      count = raw.split(separator: "\n", omittingEmptySubsequences: true).count
    } else {
      count = 0
    }
    defaults.set(count, forKey: key)
    return count
  }

  private func fileURL(for workoutId: String) -> URL {
    storageDirectory.appendingPathComponent("\(workoutId).jsonl", isDirectory: false)
  }

  private func nextIndexKey(_ workoutId: String) -> String {
    "kls_gps_next_index_\(workoutId)"
  }

  private func validateWorkoutId(_ workoutId: String) throws {
    let range = NSRange(location: 0, length: workoutId.utf16.count)
    guard Self.workoutIdRegex.firstMatch(in: workoutId, range: range) != nil else {
      throw storageError(
        "workoutId must contain only letters, digits, dots, underscores, or hyphens."
      )
    }
  }

  private func storageError(_ message: String) -> NSError {
    NSError(
      domain: "com.kls.kls_gps_tracker.storage",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private static let workoutIdRegex = try! NSRegularExpression(
    pattern: "^[A-Za-z0-9._-]{1,128}$"
  )

  private enum Keys {
    static let activeWorkoutId = "kls_gps_active_workout_id"
    static let isTracking = "kls_gps_is_tracking"
    static let shouldAutoResume = "kls_gps_should_auto_resume"
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
