import AVFoundation
import CoreLocation
import Flutter
import UIKit

// =============================================================================
// MARK: - Native voice coach
// =============================================================================

private struct KlsVoiceCue {
    let id: String
    let atElapsedSeconds: Double
    let text: String
}

private final class KlsNativeVoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    private var cues: [KlsVoiceCue] = []
    private var spokenCueIds = Set<String>()

    private var timer: Timer?

    private var configured = false
    private var enabled = true
    private var running = false
    private var paused = false

    private var startedAt: Date?
    private var pausedAt: Date?
    private var totalPausedSeconds: TimeInterval = 0
    private var initialElapsedSeconds: TimeInterval = 0

    private var language = "ru-RU"
    private var preferredVoiceIdentifier: String?
    private var speechRate: Float = 0.48
    private var speechPitch: Float = 0.98
    private var speechVolume: Float = 1.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // -------------------------------------------------------------------------
    // MARK: Configuration
    // -------------------------------------------------------------------------

    func configure(_ arguments: [String: Any]) {
        stopTimer()
        synthesizer.stopSpeaking(at: .immediate)

        configured = true
        running = false
        paused = false

        startedAt = nil
        pausedAt = nil
        totalPausedSeconds = 0
        initialElapsedSeconds = 0

        spokenCueIds.removeAll()

        if let value = arguments["enabled"] as? Bool {
            enabled = value
        } else {
            enabled = true
        }

        if let value = arguments["language"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            language = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            language = "ru-RU"
        }

        if let value = arguments["voiceIdentifier"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            preferredVoiceIdentifier = trimmed.isEmpty ? nil : trimmed
        } else {
            preferredVoiceIdentifier = nil
        }

        if let value = arguments["rate"] as? NSNumber {
            speechRate = Float(truncating: value)
        } else {
            speechRate = 0.48
        }

        if let value = arguments["pitch"] as? NSNumber {
            speechPitch = Float(truncating: value)
        } else {
            speechPitch = 0.98
        }

        if let value = arguments["volume"] as? NSNumber {
            speechVolume = Float(truncating: value)
        } else {
            speechVolume = 1.0
        }

        speechRate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(
                AVSpeechUtteranceMinimumSpeechRate,
                speechRate
            )
        )

        speechPitch = min(
            2.0,
            max(
                0.5,
                speechPitch
            )
        )

        speechVolume = min(
            1.0,
            max(
                0.0,
                speechVolume
            )
        )

        var parsedCues: [KlsVoiceCue] = []

        if let rawCues = arguments["cues"] as? [[String: Any]] {
            for (index, rawCue) in rawCues.enumerated() {
                guard
                    let rawText = rawCue["text"] as? String
                else {
                    continue
                }

                let text = rawText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !text.isEmpty else {
                    continue
                }

                let seconds: Double

                if let number = rawCue["atElapsedSeconds"] as? NSNumber {
                    seconds = number.doubleValue
                } else if let number = rawCue["at_elapsed_seconds"] as? NSNumber {
                    seconds = number.doubleValue
                } else if let value = rawCue["atElapsedSeconds"] as? String,
                          let parsed = Double(value) {
                    seconds = parsed
                } else {
                    continue
                }

                guard seconds >= 0 else {
                    continue
                }

                let rawId =
                    rawCue["id"] as? String ??
                    "cue_\(index)_\(Int(seconds.rounded()))"

                let id = rawId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                parsedCues.append(
                    KlsVoiceCue(
                        id: id.isEmpty
                            ? "cue_\(index)_\(Int(seconds.rounded()))"
                            : id,
                        atElapsedSeconds: seconds,
                        text: text
                    )
                )
            }
        }

        cues = parsedCues.sorted {
            if $0.atElapsedSeconds == $1.atElapsedSeconds {
                return $0.id < $1.id
            }

            return $0.atElapsedSeconds < $1.atElapsedSeconds
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Lifecycle
    // -------------------------------------------------------------------------

    func start(initialElapsedSeconds: Double = 0) {
        guard configured else {
            return
        }

        self.initialElapsedSeconds = max(
            0,
            initialElapsedSeconds
        )

        startedAt = Date()
        pausedAt = nil
        totalPausedSeconds = 0

        running = true
        paused = false

        startTimer()

        tick()
    }

    func pause() {
        guard running, !paused else {
            return
        }

        paused = true
        pausedAt = Date()

        stopTimer()

        synthesizer.stopSpeaking(
            at: .immediate
        )

        deactivateAudioSession()
    }

    func resume() {
        guard configured else {
            return
        }

        if !running {
            start(
                initialElapsedSeconds: initialElapsedSeconds
            )
            return
        }

        guard paused else {
            startTimer()
            return
        }

        if let pausedAt {
            totalPausedSeconds += Date().timeIntervalSince(
                pausedAt
            )
        }

        self.pausedAt = nil
        paused = false

        startTimer()

        tick()
    }

    func stop(clearConfiguration: Bool = true) {
        stopTimer()

        synthesizer.stopSpeaking(
            at: .immediate
        )

        deactivateAudioSession()

        running = false
        paused = false

        startedAt = nil
        pausedAt = nil
        totalPausedSeconds = 0
        initialElapsedSeconds = 0

        spokenCueIds.removeAll()

        if clearConfiguration {
            configured = false
            cues.removeAll()
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value

        if !value {
            synthesizer.stopSpeaking(
                at: .immediate
            )

            deactivateAudioSession()
        } else if running && !paused {
            startTimer()
            tick()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Timer
    // -------------------------------------------------------------------------

    private func startTimer() {
        guard running, !paused, enabled else {
            return
        }

        guard timer == nil else {
            return
        }

        let nextTimer = Timer(
            timeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.tick()
        }

        timer = nextTimer

        RunLoop.main.add(
            nextTimer,
            forMode: .common
        )
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // Called from CLLocation updates as an additional background wake-up source.
    // This is important because iOS may throttle ordinary Dart/Flutter timers
    // when the screen is locked.
    func handleBackgroundLocationWakeup() {
        if Thread.isMainThread {
            tick()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.tick()
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Elapsed time
    // -------------------------------------------------------------------------

    private var elapsedSeconds: Double {
        guard running else {
            return initialElapsedSeconds
        }

        guard let startedAt else {
            return initialElapsedSeconds
        }

        let endpoint: Date

        if paused, let pausedAt {
            endpoint = pausedAt
        } else {
            endpoint = Date()
        }

        let activeDuration =
            endpoint.timeIntervalSince(startedAt) -
            totalPausedSeconds

        return max(
            0,
            initialElapsedSeconds + activeDuration
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Cue processing
    // -------------------------------------------------------------------------

    private func tick() {
        guard configured else {
            return
        }

        guard enabled else {
            return
        }

        guard running else {
            return
        }

        guard !paused else {
            return
        }

        guard !cues.isEmpty else {
            return
        }

        let elapsed = elapsedSeconds

        let due = cues.filter {
            !spokenCueIds.contains($0.id) &&
            $0.atElapsedSeconds <= elapsed + 0.20
        }

        guard !due.isEmpty else {
            return
        }

        // If iOS delayed execution for a while, do not read every stale cue one
        // after another. Mark older cues as handled and speak only the newest
        // logical moment.
        guard let newestTime = due.map({
            $0.atElapsedSeconds
        }).max() else {
            return
        }

        for cue in due where cue.atElapsedSeconds < newestTime - 0.01 {
            spokenCueIds.insert(
                cue.id
            )
        }

        let currentMomentCues = due.filter {
            abs(
                $0.atElapsedSeconds - newestTime
            ) <= 0.01
        }

        guard !currentMomentCues.isEmpty else {
            return
        }

        for cue in currentMomentCues {
            spokenCueIds.insert(
                cue.id
            )
        }

        let text = currentMomentCues
            .map {
                $0.text
            }
            .joined(
                separator: " "
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !text.isEmpty else {
            return
        }

        speak(
            text
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Speech
    // -------------------------------------------------------------------------

    func speakNow(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard enabled, !trimmed.isEmpty else {
            return
        }

        speak(
            trimmed
        )
    }

    private func speak(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            guard self.enabled else {
                return
            }

            do {
                try self.activateAudioSession()
            } catch {
                print(
                    "[KLS GPS] Failed to activate voice audio session: \(error)"
                )
            }

            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(
                    at: .immediate
                )
            }

            let utterance = AVSpeechUtterance(
                string: text
            )

            utterance.voice = self.bestVoice()

            utterance.rate = self.speechRate
            utterance.pitchMultiplier = self.speechPitch
            utterance.volume = self.speechVolume

            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0

            self.synthesizer.speak(
                utterance
            )
        }
    }

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        if let preferredVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(
            identifier: preferredVoiceIdentifier
           ) {
            return voice
        }

        let normalizedLanguage = language.lowercased()

        let candidates = AVSpeechSynthesisVoice
            .speechVoices()
            .filter {
                let candidate = $0.language.lowercased()

                if candidate == normalizedLanguage {
                    return true
                }

                if normalizedLanguage.hasPrefix("ru") &&
                    candidate.hasPrefix("ru") {
                    return true
                }

                return false
            }
            .sorted {
                let leftExact =
                    $0.language.lowercased() ==
                    normalizedLanguage

                let rightExact =
                    $1.language.lowercased() ==
                    normalizedLanguage

                if leftExact != rightExact {
                    return leftExact
                }

                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }

                return $0.name < $1.name
            }

        if let first = candidates.first {
            return first
        }

        return AVSpeechSynthesisVoice(
            language: language
        )
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playback,
            mode: .voicePrompt,
            options: [
                .mixWithOthers,
                .duckOthers,
                .interruptSpokenAudioAndMixWithOthers,
                .allowBluetoothA2DP,
                .allowAirPlay,
            ]
        )

        try session.setActive(
            true
        )
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            // Another audio component in the host application may still own
            // the session. This must never stop GPS tracking.
        }
    }

    // -------------------------------------------------------------------------
    // MARK: AVSpeechSynthesizerDelegate
    // -------------------------------------------------------------------------

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        deactivateAudioSession()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        deactivateAudioSession()
    }

    // -------------------------------------------------------------------------
    // MARK: State
    // -------------------------------------------------------------------------

    func state() -> [String: Any] {
        [
            "configured": configured,
            "enabled": enabled,
            "running": running,
            "paused": paused,
            "elapsedSeconds": elapsedSeconds,
            "cueCount": cues.count,
            "spokenCueCount": spokenCueIds.count,
            "isSpeaking": synthesizer.isSpeaking,
        ]
    }
}

// =============================================================================
// MARK: - GPS plugin
// =============================================================================

public final class KlsGpsTrackerPlugin:
    NSObject,
    FlutterPlugin,
    FlutterStreamHandler,
    CLLocationManagerDelegate
{
    private let locationManager = CLLocationManager()
    private let storage = KlsGpsStorage()

    private let voiceCoach = KlsNativeVoiceCoach()

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

    public static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        let instance = KlsGpsTrackerPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "kls_gps_tracker",
            binaryMessenger: registrar.messenger()
        )

        let eventChannel = FlutterEventChannel(
            name: "kls_gps_tracker/positions",
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(
            instance,
            channel: methodChannel
        )

        eventChannel.setStreamHandler(
            instance
        )

        instance.resumeActiveWorkoutIfPossible()
    }

    // =========================================================================
    // MARK: Flutter methods
    // =========================================================================

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "requestPermission":
            requestPermission(
                result: result
            )

        case "checkReadiness":
            result(
                readiness()
            )

        case "start":
            start(
                call: call,
                result: result
            )

        case "stop":
            stop(
                call: call,
                result: result
            )

        case "getTrackingState":
            result(
                trackingState()
            )

        case "getStoredPoints":
            getStoredPoints(
                call: call,
                result: result
            )

        case "listStoredWorkoutIds":
            result(
                storage.listStoredWorkoutIds()
            )

        case "deleteStoredWorkout":
            deleteStoredWorkout(
                call: call,
                result: result
            )

        // ---------------------------------------------------------------------
        // Native voice coach
        // ---------------------------------------------------------------------

        case "configureVoiceCoach":
            configureVoiceCoach(
                call: call,
                result: result
            )

        case "startVoiceCoach":
            startVoiceCoach(
                call: call,
                result: result
            )

        case "pauseVoiceCoach":
            voiceCoach.pause()
            result(nil)

        case "resumeVoiceCoach":
            voiceCoach.resume()
            result(nil)

        case "stopVoiceCoach":
            voiceCoach.stop(
                clearConfiguration: true
            )
            result(nil)

        case "setVoiceCoachEnabled":
            setVoiceCoachEnabled(
                call: call,
                result: result
            )

        case "speakVoiceCoachNow":
            speakVoiceCoachNow(
                call: call,
                result: result
            )

        case "getVoiceCoachState":
            result(
                voiceCoach.state()
            )

        default:
            result(
                FlutterMethodNotImplemented
            )
        }
    }

    // =========================================================================
    // MARK: Permissions
    // =========================================================================

    private func requestPermission(
        result: @escaping FlutterResult
    ) {
        let status = permissionStatus()

        if status == "precise" ||
            status == "approximate" ||
            status == "deniedForever" {
            result(
                status
            )
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

    // =========================================================================
    // MARK: GPS start / stop
    // =========================================================================

    private func start(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
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

        guard status == "precise" ||
                status == "approximate" else {
            result(
                FlutterError(
                    code: "permission_denied",
                    message: "Location permission has not been granted.",
                    details: nil
                )
            )
            return
        }

        let arguments =
            call.arguments as? [String: Any]

        let requestedWorkoutId =
            arguments?["workoutId"] as? String

        do {
            let workoutId = try storage.beginWorkout(
                requestedWorkoutId: requestedWorkoutId
            )

            configureBackgroundUpdates()

            storage.setTracking(
                true
            )

            locationManager.startUpdatingLocation()

            // Optional single-call configuration.
            // The updated Dart layer will use this later.
            if let voiceConfiguration =
                arguments?["voiceCoach"] as? [String: Any] {
                voiceCoach.configure(
                    voiceConfiguration
                )

                let initialElapsed =
                    (
                        voiceConfiguration["initialElapsedSeconds"]
                            as? NSNumber
                    )?.doubleValue ?? 0

                voiceCoach.start(
                    initialElapsedSeconds: initialElapsed
                )
            } else {
                // If this was only a workout resume after a pause and the native
                // coach is already configured, resume it as well.
                let voiceState = voiceCoach.state()

                if voiceState["configured"] as? Bool == true,
                   voiceState["paused"] as? Bool == true {
                    voiceCoach.resume()
                }
            }

            result(
                workoutId
            )
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

    private func stop(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        let finishWorkout =
            arguments?["finishWorkout"] as? Bool ?? true

        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false

        if finishWorkout {
            storage.finishWorkout(
                storage.activeWorkoutId
            )

            voiceCoach.stop(
                clearConfiguration: true
            )
        } else {
            storage.pauseWorkout()

            voiceCoach.pause()
        }

        result(nil)
    }

    // =========================================================================
    // MARK: Native voice methods
    // =========================================================================

    private func configureVoiceCoach(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments =
                call.arguments as? [String: Any] else {
            result(
                FlutterError(
                    code: "invalid_voice_configuration",
                    message: "Voice coach configuration is required.",
                    details: nil
                )
            )
            return
        }

        voiceCoach.configure(
            arguments
        )

        result(
            voiceCoach.state()
        )
    }

    private func startVoiceCoach(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        let elapsed =
            (
                arguments?["elapsedSeconds"]
                    as? NSNumber
            )?.doubleValue ?? 0

        voiceCoach.start(
            initialElapsedSeconds: elapsed
        )

        result(
            voiceCoach.state()
        )
    }

    private func setVoiceCoachEnabled(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        guard let enabled =
                arguments?["enabled"] as? Bool else {
            result(
                FlutterError(
                    code: "invalid_voice_enabled",
                    message: "enabled must be a boolean.",
                    details: nil
                )
            )
            return
        }

        voiceCoach.setEnabled(
            enabled
        )

        result(
            voiceCoach.state()
        )
    }

    private func speakVoiceCoachNow(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        guard let rawText =
                arguments?["text"] as? String else {
            result(
                FlutterError(
                    code: "invalid_voice_text",
                    message: "text is required.",
                    details: nil
                )
            )
            return
        }

        let text = rawText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            result(
                FlutterError(
                    code: "invalid_voice_text",
                    message: "text must not be empty.",
                    details: nil
                )
            )
            return
        }

        voiceCoach.speakNow(
            text
        )

        result(nil)
    }

    // =========================================================================
    // MARK: Restore active GPS workout
    // =========================================================================

    private func resumeActiveWorkoutIfPossible() {
        guard storage.activeWorkoutId != nil else {
            return
        }

        guard storage.shouldAutoResume else {
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            return
        }

        let status = permissionStatus()

        guard status == "precise" ||
                status == "approximate" else {
            return
        }

        configureBackgroundUpdates()

        storage.setTracking(
            true
        )

        locationManager.startUpdatingLocation()
    }

    // =========================================================================
    // MARK: Background capability
    // =========================================================================

    private func configureBackgroundUpdates() {
        let enabled = backgroundLocationCapable()

        locationManager.allowsBackgroundLocationUpdates = enabled
        locationManager.showsBackgroundLocationIndicator = enabled
    }

    private func readiness() -> [String: Any] {
        [
            "permission": permissionStatus(),
            "serviceEnabled": CLLocationManager.locationServicesEnabled(),
            "backgroundCapable": backgroundLocationCapable(),
            "backgroundLocationCapable": backgroundLocationCapable(),
            "backgroundAudioCapable": backgroundAudioCapable(),
        ]
    }

    private func trackingState() -> [String: Any?] {
        let workoutId =
            storage.activeWorkoutId

        return [
            "isTracking": storage.isTracking,
            "workoutId": workoutId,
            "pointCount":
                workoutId.map {
                    storage.pointCount(
                        workoutId: $0
                    )
                } ?? 0,
            "backgroundCapable": backgroundLocationCapable(),
            "backgroundLocationCapable": backgroundLocationCapable(),
            "backgroundAudioCapable": backgroundAudioCapable(),
        ]
    }

    private func backgroundLocationCapable() -> Bool {
        let modes =
            Bundle.main.object(
                forInfoDictionaryKey: "UIBackgroundModes"
            ) as? [String]

        return modes?.contains(
            "location"
        ) == true
    }

    private func backgroundAudioCapable() -> Bool {
        let modes =
            Bundle.main.object(
                forInfoDictionaryKey: "UIBackgroundModes"
            ) as? [String]

        return modes?.contains(
            "audio"
        ) == true
    }

    // =========================================================================
    // MARK: Stored GPS points
    // =========================================================================

    private func getStoredPoints(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        guard let workoutId =
                arguments?["workoutId"] as? String,
              !workoutId.isEmpty else {
            result(
                FlutterError(
                    code: "invalid_workout_id",
                    message: "workoutId is required.",
                    details: nil
                )
            )
            return
        }

        let afterPointIndex =
            (
                arguments?["afterPointIndex"]
                    as? NSNumber
            )?.intValue ?? -1

        let limit =
            (
                arguments?["limit"]
                    as? NSNumber
            )?.intValue ?? 1000

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

    private func deleteStoredWorkout(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments =
            call.arguments as? [String: Any]

        guard let workoutId =
                arguments?["workoutId"] as? String,
              !workoutId.isEmpty else {
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
            try storage.deleteWorkout(
                workoutId
            )

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

    // =========================================================================
    // MARK: Permissions state
    // =========================================================================

    private func permissionStatus() -> String {
        let authorizationStatus: CLAuthorizationStatus

        if #available(iOS 14.0, *) {
            authorizationStatus =
                locationManager.authorizationStatus
        } else {
            authorizationStatus =
                CLLocationManager.authorizationStatus()
        }

        switch authorizationStatus {
        case .notDetermined:
            return "notDetermined"

        case .restricted, .denied:
            return "deniedForever"

        case .authorizedAlways, .authorizedWhenInUse:
            if #available(iOS 14.0, *) {
                return locationManager.accuracyAuthorization ==
                    .fullAccuracy
                    ? "precise"
                    : "approximate"
            }

            return "precise"

        @unknown default:
            return "notDetermined"
        }
    }

    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        completePermissionRequest(
            status: manager.authorizationStatus
        )
    }

    public func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        completePermissionRequest(
            status: status
        )
    }

    private func completePermissionRequest(
        status: CLAuthorizationStatus
    ) {
        guard let pendingResult =
                permissionResult else {
            return
        }

        guard status != .notDetermined else {
            return
        }

        permissionResult = nil

        pendingResult(
            permissionStatus()
        )
    }

    // =========================================================================
    // MARK: CLLocationManagerDelegate
    // =========================================================================

    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // A location callback also acts as a native background wake-up.
        // This means time-based voice cues do not rely only on Flutter's
        // Timer.periodic while the iPhone screen is locked.
        voiceCoach.handleBackgroundLocationWakeup()

        guard let workoutId =
                storage.activeWorkoutId else {
            return
        }

        for location in locations {
            guard CLLocationCoordinate2DIsValid(
                location.coordinate
            ) else {
                continue
            }

            do {
                // The durable RAW journal is written before Flutter sees the fix.
                // The Dart quality filter decides later whether it contributes
                // to distance.
                let point = try storage.append(
                    location: location,
                    workoutId: workoutId
                )

                eventSink?(
                    point
                )
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

    public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let locationError =
            error as? CLError

        if locationError?.code ==
            .locationUnknown {
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

    // =========================================================================
    // MARK: Flutter position stream
    // =========================================================================

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(
        withArguments arguments: Any?
    ) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
