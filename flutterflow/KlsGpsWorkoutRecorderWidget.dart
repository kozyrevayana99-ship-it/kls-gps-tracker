// Automatic FlutterFlow imports
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:kls_gps_tracker/kls_gps_tracker.dart';
import 'package:latlong2/latlong.dart' as ll;

const _klsGold = Color(0xFFD6A85A);
const _klsIce = Color(0xFF9ED8FF);
const _klsNavy = Color(0xFF061326);
const _klsGreen = Color(0xFF69E6A3);
const _klsRed = Color(0xFFFF6B6B);

class KlsGpsWorkoutRecorderWidget extends StatefulWidget {
  const KlsGpsWorkoutRecorderWidget({
    super.key,
    this.width,
    this.height,
    this.currentUserId,
    this.startWorkoutUrl,
    this.saveWorkoutBatchUrl,
    this.finishWorkoutUrl,
    this.getWorkoutUrl,
    this.getWorkoutRouteUrl,
    this.addTrainingUrl,
    this.trackEventUrl,
    this.planKey,
    this.planDayId,
    this.plannedDate,
    this.plannedTitle,
    this.plannedDescription,
    this.plannedDurationMinutes,
    this.plannedActivityType,
    this.planCompletionStatus,
  });

  final double? width;
  final double? height;
  final String? currentUserId;
  final String? startWorkoutUrl;
  final String? saveWorkoutBatchUrl;
  final String? finishWorkoutUrl;
  final String? getWorkoutUrl;
  final String? getWorkoutRouteUrl;
  final String? addTrainingUrl;
  final String? trackEventUrl;
  final String? planKey;
  final String? planDayId;
  final String? plannedDate;
  final String? plannedTitle;
  final String? plannedDescription;
  final int? plannedDurationMinutes;
  final String? plannedActivityType;
  final String? planCompletionStatus;

  @override
  State<KlsGpsWorkoutRecorderWidget> createState() =>
      _KlsGpsWorkoutRecorderWidgetState();
}

class _SportOption {
  const _SportOption({
    required this.key,
    required this.title,
    required this.icon,
    required this.diaryType,
    required this.maxSpeedMps,
  });

  final String key;
  final String title;
  final IconData icon;
  final String diaryType;
  final double maxSpeedMps;
}

class _TrackPoint {
  const _TrackPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  ll.LatLng get latLng => ll.LatLng(lat, lng);
}

class _WorkoutLap {
  const _WorkoutLap({
    required this.number,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    required this.isAutomatic,
  });

  final int number;
  final double distanceMeters;
  final int durationSeconds;
  final double elevationGainMeters;
  final bool isAutomatic;

  Map<String, dynamic> toJson() => {
        'number': number,
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'elevation_gain_meters': elevationGainMeters,
        'is_automatic': isAutomatic,
      };
}

class _KlsGpsWorkoutRecorderWidgetState
    extends State<KlsGpsWorkoutRecorderWidget> with WidgetsBindingObserver {
  final List<_SportOption> _sports = const [
    _SportOption(
      key: 'ski',
      title: 'Лыжи',
      icon: Icons.downhill_skiing_rounded,
      diaryType: 'Лыжи',
      maxSpeedMps: 35,
    ),
    _SportOption(
      key: 'run',
      title: 'Бег',
      icon: Icons.directions_run_rounded,
      diaryType: 'Бег',
      maxSpeedMps: 12,
    ),
    _SportOption(
      key: 'rollerski',
      title: 'Лыжероллеры',
      icon: Icons.directions_run_rounded,
      diaryType: 'Лыжероллеры',
      maxSpeedMps: 20,
    ),
    _SportOption(
      key: 'bike',
      title: 'Велосипед',
      icon: Icons.directions_bike_rounded,
      diaryType: 'Велосипед',
      maxSpeedMps: 30,
    ),
  ];

  final KlsGpsTracker _gpsTracker = KlsGpsTracker();
  final KlsOfflineWorkoutManager _offlineManager = KlsOfflineWorkoutManager();
  final MapController _mapController = MapController();
  final TextEditingController _commentController = TextEditingController();

  StreamSubscription<KlsGpsPoint>? _positionSub;
  StreamSubscription<int>? _heartRateSubscription;
  Future<String>? _gpsStartFuture;
  Future<void>? _journalReplayFuture;

  Timer? _timer;
  Timer? _syncTimer;

  KlsGpsFilter? _gpsFilter;

  String? _workoutId;
  String? _previewWorkoutId;
  String _sportType = 'rollerski';

  bool _isStarting = false;
  bool _isRestoring = true;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isFinishing = false;
  bool _isSavingDiary = false;
  bool _awaitingDiarySave = false;

  bool _gpsLocked = false;
  bool _mapReady = false;
  bool _followUser = true;
  bool _isLocating = true;
  bool _gpsNativeRunning = false;
  bool _backgroundGpsCapable = false;
  bool _backgroundGpsChecked = false;

  int? _countdownValue;
  String? _errorText;

  DateTime? _startedAt;
  DateTime? _pausedAt;
  DateTime? _lastMovementAt;
  DateTime? _lastGpsFixAt;

  int _elapsedSeconds = 0;
  int _pauseSeconds = 0;
  int _pointIndex = 0;
  int _lastProcessedPointIndex = -1;
  int _rejectedPointCount = 0;

  double _distanceMeters = 0;
  double _currentSpeedMps = 0;
  double _maxSpeedMps = 0;
  double _accuracy = 0;
  double _heading = 0;
  double _movementBearingDegrees = 0;
  bool _hasMovementBearing = false;

  final List<double> _liveSpeedWindow = <double>[];

  double _elevationGainMeters = 0;
  double? _currentAltitudeMeters;
  double? _smoothedAltitudeMeters;
  double? _elevationReferenceMeters;

  KlsGpsPoint? _currentPosition;
  _TrackPoint? _lastLiveTrackPoint;

  final List<List<_TrackPoint>> _routeSegments = [];
  final List<_WorkoutLap> _laps = [];

  double _autoLapStartDistanceMeters = 0;
  int _autoLapStartElapsedSeconds = 0;
  double _autoLapStartElevationGainMeters = 0;

  double _manualLapStartDistanceMeters = 0;
  int _manualLapStartElapsedSeconds = 0;
  double _manualLapStartElevationGainMeters = 0;

  int _nextAutoLapKm = 1;

  int _wellbeing = 4;
  int _rpe = 5;
  int _fatigue = 2;
  double _sleepHours = 8;

  int? _finishedAverageBpm;
  int? _finishedMaxBpm;
  int _finishedHeartRateSampleCount = 0;
  String? _finishedHeartRateDeviceName;

  _SportOption get _selectedSport => _sports.firstWhere(
        (sport) => sport.key == _sportType,
        orElse: () => _sports[2],
      );

  bool get _hasPlanContext =>
      (widget.planKey?.trim().isNotEmpty ?? false) &&
      (widget.planDayId?.trim().isNotEmpty ?? false);

  bool get _isRun => _sportType == 'run';
  bool get _isSkiLike => _sportType == 'ski' || _sportType == 'rollerski';
  bool get _isBike => _sportType == 'bike';

  // Used for lap display. Active screen metrics have their own per-sport layout.
  bool get _usesPace => _isRun;

  int? get _gpsFixAgeSeconds {
    final fix = _lastGpsFixAt;
    if (fix == null) return null;
    return DateTime.now().difference(fix).inSeconds.abs();
  }

  bool get _gpsReadyForStart =>
      _currentPosition != null &&
      !_isLocating &&
      _accuracy > 0 &&
      _accuracy <= 50 &&
      _backgroundGpsCapable;

  KlsWorkoutEndpoints get _endpoints => KlsWorkoutEndpoints(
        startWorkoutUrl: widget.startWorkoutUrl?.trim() ?? '',
        saveWorkoutBatchUrl: widget.saveWorkoutBatchUrl?.trim() ?? '',
        finishWorkoutUrl: widget.finishWorkoutUrl?.trim() ?? '',
        addTrainingUrl: widget.addTrainingUrl?.trim() ?? '',
      );

  bool get _heartRateConnected => KlsHeartRateDeviceWidget.sensorConnected;
  int? get _currentHeartRateBpm => KlsHeartRateDeviceWidget.currentBpm;

  String get _heartRateDeviceName {
    final name = KlsHeartRateDeviceWidget.sensorName.trim();
    return name.isEmpty ? 'Пульсометр' : name;
  }

  List<_TrackPoint> get _allRoutePoints => _routeSegments
      .expand((segment) => segment)
      .toList(growable: false);

  List<_TrackPoint> get _activeSegment {
    if (_routeSegments.isEmpty) {
      _routeSegments.add(<_TrackPoint>[]);
    }
    return _routeSegments.last;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final plannedType = widget.plannedActivityType?.trim() ?? '';
    if (_sports.any((sport) => sport.key == plannedType)) {
      _sportType = plannedType;
    }

    _createGpsFilter();

    _heartRateSubscription = KlsHeartRateDeviceWidget.bpmStream.listen(
      (_) {
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        debugPrint('Heart rate stream error: $error');
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeOfflineState());
    });

    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!_awaitingDiarySave) {
          unawaited(_offlineManager.syncPendingWorkouts());
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    }
  }

  Future<void> _handleAppResumed() async {
    if (!_awaitingDiarySave) {
      unawaited(_offlineManager.syncPendingWorkouts());
    }

    if (_isTracking && !_isPaused) {
      try {
        // First recover everything that native iOS/Android journaled while
        // Flutter was suspended behind a locked screen.
        await _replayNewJournalPoints();
        await _ensureGpsStream();
        await _replayNewJournalPoints();
      } catch (error) {
        if (mounted) {
          setState(() {
            _errorText = 'Ошибка восстановления GPS: ${_cleanError(error)}';
          });
        }
      }
    } else if (!_isTracking) {
      await _startLocationPreview();
    }
  }

  @override
  void didUpdateWidget(covariant KlsGpsWorkoutRecorderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isTracking || _isStarting) return;

    if (oldWidget.plannedActivityType != widget.plannedActivityType) {
      final plannedType = widget.plannedActivityType?.trim() ?? '';
      if (_sports.any((sport) => sport.key == plannedType) &&
          plannedType != _sportType) {
        setState(() {
          _sportType = plannedType;
          _createGpsFilter();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _syncTimer?.cancel();
    _positionSub?.cancel();
    _heartRateSubscription?.cancel();

    // A real workout owns a durable native GPS session and must continue if
    // FlutterFlow rebuilds/disposes this widget. Only a preparation preview is
    // disposable here.
    if (!_isTracking) {
      unawaited(_stopPreviewSession());
    }

    // Do NOT disconnect the HR sensor here. It belongs to the separate HR
    // widget/service and may stay connected between screens.
    _mapController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _initializeOfflineState() async {
    await _restoreLocalWorkout();

    if (mounted && !_isTracking) {
      await _startLocationPreview();
    }

    if (!_awaitingDiarySave) {
      unawaited(_offlineManager.syncPendingWorkouts());
    }
  }

  Future<void> _restoreLocalWorkout() async {
    if (_isTracking || _isStarting) {
      if (mounted) setState(() => _isRestoring = false);
      return;
    }

    try {
      final nativeState = await _gpsTracker.getTrackingState();
      _backgroundGpsCapable = nativeState.backgroundCapable;
      _backgroundGpsChecked = true;

      KlsOfflineWorkout? workout;
      final nativeWorkoutId = nativeState.workoutId;

      if (nativeWorkoutId != null && nativeWorkoutId.isNotEmpty) {
        workout = await _offlineManager.getWorkout(nativeWorkoutId);
      }

      if (workout == null) {
        final recordings = await _offlineManager.listRecordingWorkouts();
        if (recordings.isNotEmpty) workout = recordings.first;
      }

      if (workout == null || !workout.isRecording) {
        // An active native id without local workout metadata is an interrupted
        // preparation preview, not a real workout.
        if (nativeWorkoutId != null && nativeWorkoutId.isNotEmpty) {
          try {
            await _gpsTracker.stop(finishWorkout: true);
            await _gpsTracker.deleteStoredWorkout(nativeWorkoutId);
          } catch (_) {}
        }
        _gpsNativeRunning = false;
        return;
      }

      if (!mounted) return;

      _sportType = workout.sportType;
      _resetLocalWorkout();

      _workoutId = workout.workoutId;
      _startedAt = workout.startedAtUtc.toLocal();
      _pauseSeconds = workout.pauseSeconds;
      _pausedAt = workout.pausedAtUtc?.toLocal();
      _elapsedSeconds = workout.activeElapsedSeconds();
      _isPaused = workout.isPaused;
      _isTracking = true;
      _isLocating = false;
      _gpsNativeRunning = nativeState.isTracking &&
          nativeState.workoutId == workout.workoutId;

      await _rebuildRouteFromJournal(workout.workoutId);

      if (!workout.isPaused) {
        await _startGpsStream();
        await _replayNewJournalPoints();
      }

      _startTimer();

      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = 'Не удалось восстановить запись: ${_cleanError(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _rebuildRouteFromJournal(String workoutId) async {
    _lastProcessedPointIndex = -1;
    await _replayNewJournalPoints(followAtEnd: false);
  }

  Future<void> _replayNewJournalPoints({bool followAtEnd = true}) async {
    final workoutId = _workoutId;
    if (!_isTracking || workoutId == null || workoutId.isEmpty) return;

    final running = _journalReplayFuture;
    if (running != null) {
      await running;
      return;
    }

    final future = () async {
      _positionSub?.pause();
      try {
        var after = _lastProcessedPointIndex;

        while (true) {
          final points = await _gpsTracker.getStoredPoints(
            workoutId: workoutId,
            afterPointIndex: after,
            limit: 1000,
          );

          if (points.isEmpty) break;

          for (final point in points) {
            _handlePosition(point, notify: false);
            final index = point.pointIndex;
            if (index != null && index > after) after = index;
          }

          if (points.length < 1000) break;
        }
      } finally {
        _positionSub?.resume();
      }

      if (mounted) {
        setState(() {});
        if (followAtEnd) _followCurrentPoint();
      }
    }();

    _journalReplayFuture = future;
    try {
      await future;
    } finally {
      if (identical(_journalReplayFuture, future)) {
        _journalReplayFuture = null;
      }
    }
  }

  void _createGpsFilter() {
    _gpsFilter = KlsGpsFilter(
      startupAccuracyMeters: 20,
      maxAccuracyMeters: 30,
      warmupPointCount: 3,
      minimumMovementMeters: 2.5,
      stationarySpeedMetersPerSecond: 0.8,
      maxSpeedMetersPerSecond: _selectedSport.maxSpeedMps,
      maximumGapSeconds: 15,
    );
  }

  Future<void> _openHeartRateDevice() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.84,
          child: const KlsHeartRateDeviceWidget(
            width: double.infinity,
            height: double.infinity,
          ),
        );
      },
    );

    if (mounted) setState(() {});
  }

  void _captureHeartRateSummary() {
    if (KlsHeartRateDeviceWidget.hasWorkoutHeartRateData) {
      _finishedAverageBpm = KlsHeartRateDeviceWidget.workoutAverageBpm;
      _finishedMaxBpm = KlsHeartRateDeviceWidget.workoutMaxBpm;
      _finishedHeartRateSampleCount =
          KlsHeartRateDeviceWidget.workoutHeartRateSampleCount;
      final name = KlsHeartRateDeviceWidget.sensorName.trim();
      _finishedHeartRateDeviceName = name.isEmpty ? 'Пульсометр' : name;
    } else {
      _finishedAverageBpm = null;
      _finishedMaxBpm = null;
      _finishedHeartRateSampleCount = 0;
      _finishedHeartRateDeviceName = null;
    }
  }

  Future<void> _trackEvent(
    String eventName, {
    required Map<String, dynamic> metadata,
  }) async {
    final url = widget.trackEventUrl?.trim() ?? '';
    final userId = widget.currentUserId?.trim() ?? '';
    if (url.isEmpty || userId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'event_name': eventName,
          'event_category': 'training',
          'screen_name': 'KlsGpsWorkoutRecorderWidget',
          'metadata': metadata,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Не удалось записать $eventName: HTTP ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('Ошибка отправки $eventName: $error');
    }
  }

  void _resetLocalWorkout({bool preserveCurrentLocation = false}) {
    final previewPosition = preserveCurrentLocation ? _currentPosition : null;
    final previewAccuracy = preserveCurrentLocation ? _accuracy : 0.0;
    final previewHeading = preserveCurrentLocation ? _heading : 0.0;
    final previewAltitude =
        preserveCurrentLocation ? _currentAltitudeMeters : null;
    final previewFixAt = preserveCurrentLocation && previewPosition != null
        ? previewPosition.timestamp.toLocal()
        : null;

    _workoutId = null;
    _startedAt = null;
    _pausedAt = null;

    _elapsedSeconds = 0;
    _pauseSeconds = 0;
    _pointIndex = 0;
    _lastProcessedPointIndex = -1;
    _rejectedPointCount = 0;

    _distanceMeters = 0;
    _currentSpeedMps = 0;
    _maxSpeedMps = 0;
    _accuracy = previewAccuracy;
    _heading = previewHeading;

    _movementBearingDegrees = previewHeading;
    _hasMovementBearing = false;
    _lastMovementAt = null;
    _lastGpsFixAt = previewFixAt;
    _liveSpeedWindow.clear();

    _currentPosition = previewPosition;
    _lastLiveTrackPoint = previewPosition == null
        ? null
        : _TrackPoint(previewPosition.latitude, previewPosition.longitude);

    _currentAltitudeMeters = previewAltitude;
    _smoothedAltitudeMeters = null;
    _elevationReferenceMeters = null;
    _elevationGainMeters = 0;

    _routeSegments.clear();
    _laps.clear();

    _autoLapStartDistanceMeters = 0;
    _autoLapStartElapsedSeconds = 0;
    _autoLapStartElevationGainMeters = 0;
    _manualLapStartDistanceMeters = 0;
    _manualLapStartElapsedSeconds = 0;
    _manualLapStartElevationGainMeters = 0;
    _nextAutoLapKm = 1;

    _gpsLocked = false;
    _followUser = true;

    _finishedAverageBpm = null;
    _finishedMaxBpm = null;
    _finishedHeartRateSampleCount = 0;
    _finishedHeartRateDeviceName = null;

    _createGpsFilter();
  }

  Future<void> _runCountdown() async {
    for (final value in <int>[3, 2, 1]) {
      if (!mounted) return;
      setState(() => _countdownValue = value);
      unawaited(HapticFeedback.mediumImpact());
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return;
    setState(() => _countdownValue = null);
    unawaited(HapticFeedback.heavyImpact());
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  Future<void> _startWorkout() async {
    if (_isRestoring || _isStarting || _isTracking) return;

    setState(() {
      _isStarting = true;
      _errorText = null;
    });

    KlsOfflineWorkout? localWorkout;

    try {
      final userId = widget.currentUserId?.trim() ?? '';
      if (userId.isEmpty) throw Exception('Не передан currentUserId');

      if (!await _checkLocationPermission()) {
        throw Exception(
          'Включите геолокацию и разрешите приложению точный доступ к GPS',
        );
      }

      if (!_backgroundGpsCapable) {
        throw Exception(
          'Фоновая запись GPS не настроена. Без неё маршрут остановится при блокировке экрана.',
        );
      }

      await _ensureGpsStream();

      if (!_gpsReadyForStart) {
        throw Exception(
          'GPS ещё не готов. Подождите, пока точность станет лучше 50 м',
        );
      }

      await _stopPreviewSession();

      setState(() {
        _resetLocalWorkout(preserveCurrentLocation: true);
      });

      final title =
          _hasPlanContext && (widget.plannedTitle?.trim().isNotEmpty ?? false)
              ? widget.plannedTitle!.trim()
              : _selectedSport.diaryType;

      await _runCountdown();
      if (!mounted) return;

      KlsHeartRateDeviceWidget.startWorkoutSession();

      final localStart = DateTime.now();
      localWorkout = await _offlineManager.createWorkout(
        userId: userId,
        sportType: _sportType,
        title: title,
        diaryType: _selectedSport.diaryType,
        usesGps: true,
        isInterval: false,
        endpoints: _endpoints,
        startedAt: localStart,
        diaryData: _initialDiaryData(),
      );

      final workoutId = localWorkout.workoutId;
      _workoutId = workoutId;
      _startedAt = localWorkout.startedAtUtc.toLocal();
      _lastProcessedPointIndex = -1;

      _autoLapStartElapsedSeconds = 0;
      _autoLapStartDistanceMeters = 0;
      _autoLapStartElevationGainMeters = 0;
      _manualLapStartElapsedSeconds = 0;
      _manualLapStartDistanceMeters = 0;
      _manualLapStartElevationGainMeters = 0;

      if (mounted) {
        setState(() {
          _isTracking = true;
          _isPaused = false;
          _gpsLocked = false;
        });
      }

      _startTimer();
      await _startGpsStream();

      unawaited(
        _trackEvent(
          'started_workout',
          metadata: {
            'workout_id': workoutId,
            'sport_type': _sportType,
            'training_type': _selectedSport.diaryType,
            'uses_gps': true,
            'offline_first': true,
            'background_gps_capable': _backgroundGpsCapable,
            'heart_rate_sensor_connected':
                KlsHeartRateDeviceWidget.sensorConnected,
            'heart_rate_sensor_name': KlsHeartRateDeviceWidget.sensorName,
            'plan_key': widget.planKey,
            'plan_day_id': widget.planDayId,
          },
        ),
      );
    } catch (error) {
      KlsHeartRateDeviceWidget.cancelWorkoutSession();
      await _positionSub?.cancel();
      _positionSub = null;

      try {
        await _gpsTracker.stop(finishWorkout: true);
      } catch (_) {}
      _gpsNativeRunning = false;

      if (localWorkout != null) {
        await _offlineManager.cancelWorkout(localWorkout.workoutId);
      }

      if (mounted) {
        setState(() {
          _isTracking = false;
          _isPaused = false;
          _countdownValue = null;
          _errorText = _cleanError(error);
        });
        unawaited(_startLocationPreview());
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<bool> _checkLocationPermission() async {
    var readiness = await _gpsTracker.checkReadiness();
    _backgroundGpsCapable = readiness.backgroundCapable;
    _backgroundGpsChecked = true;

    if (readiness.serviceStatus == KlsLocationServiceStatus.disabled) {
      return false;
    }

    if (!readiness.canStart) {
      await _gpsTracker.requestPermission();
      readiness = await _gpsTracker.checkReadiness();
      _backgroundGpsCapable = readiness.backgroundCapable;
      _backgroundGpsChecked = true;
    }

    return readiness.canStart;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!_isTracking || _isPaused || _startedAt == null || !mounted) {
          return;
        }

        setState(() {
          _elapsedSeconds =
              DateTime.now().difference(_startedAt!).inSeconds - _pauseSeconds;
          if (_elapsedSeconds < 0) _elapsedSeconds = 0;
        });
      },
    );
  }

  Future<void> _startLocationPreview() async {
    if (_isTracking) return;

    if (mounted) {
      setState(() => _isLocating = _currentPosition == null);
    }

    try {
      if (!await _checkLocationPermission()) {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _errorText =
                'Включите геолокацию и разрешите приложению точный доступ к GPS';
          });
        }
        return;
      }

      await _ensureGpsStream();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _errorText =
              'Не удалось определить местоположение: ${_cleanError(error)}';
        });
      }
    }
  }

  Future<void> _ensureGpsStream() async {
    _positionSub ??= _gpsTracker.positionStream.listen(
      (point) {
        if (!mounted) return;
        if (_isTracking) {
          if (!_isPaused) _handlePosition(point);
        } else {
          _handlePreviewPosition(point);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _isLocating = false;
          _errorText = 'Ошибка GPS: ${_cleanError(error)}';
        });
      },
    );

    if (_gpsNativeRunning) return;

    final runningStart = _gpsStartFuture;
    if (runningStart != null) {
      await runningStart;
      return;
    }

    final startFuture = _gpsTracker.start(
      workoutId: _isTracking ? _workoutId : null,
    );
    _gpsStartFuture = startFuture;

    try {
      final startedWorkoutId = await startFuture;
      _gpsNativeRunning = true;

      if (_isTracking) {
        final expected = _workoutId ?? '';
        if (expected.isNotEmpty && startedWorkoutId != expected) {
          throw StateError('Native GPS вернул другой workoutId');
        }
      } else {
        _previewWorkoutId = startedWorkoutId;
      }
    } finally {
      if (identical(_gpsStartFuture, startFuture)) _gpsStartFuture = null;
    }
  }

  void _handlePreviewPosition(KlsGpsPoint position) {
    final age = DateTime.now().difference(position.timestamp).inSeconds.abs();

    final validCoordinates = position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180 &&
        !(position.latitude == 0 && position.longitude == 0);

    final validAccuracy = position.accuracyMeters.isFinite &&
        position.accuracyMeters > 0 &&
        position.accuracyMeters <= 200;

    if (!validCoordinates || !validAccuracy || age > 30) return;

    _currentPosition = position;
    _accuracy = position.accuracyMeters;
    _lastGpsFixAt = position.timestamp.toLocal();

    if (position.altitudeMeters != null && position.altitudeMeters!.isFinite) {
      _currentAltitudeMeters = position.altitudeMeters;
    }

    if (position.headingDegrees != null &&
        position.headingDegrees!.isFinite &&
        position.headingDegrees! >= 0) {
      _heading = position.headingDegrees!;
      if (!_hasMovementBearing) _movementBearingDegrees = _heading;
    }

    _lastLiveTrackPoint = _TrackPoint(position.latitude, position.longitude);
    _isLocating = false;
    _errorText = null;

    _followCurrentPoint();
    if (mounted) setState(() {});
  }

  Future<void> _stopGpsNative({bool finishWorkout = true}) async {
    final runningStart = _gpsStartFuture;
    if (runningStart != null) {
      try {
        await runningStart;
      } catch (_) {}
    }

    if (!_gpsNativeRunning) return;
    _gpsNativeRunning = false;
    await _gpsTracker.stop(finishWorkout: finishWorkout);
  }

  Future<void> _stopPreviewSession() async {
    final previewWorkoutId = _previewWorkoutId;
    await _stopGpsNative(finishWorkout: true);
    _previewWorkoutId = null;

    if (previewWorkoutId != null && previewWorkoutId.isNotEmpty) {
      try {
        await _gpsTracker.deleteStoredWorkout(previewWorkoutId);
      } catch (_) {}
    }
  }

  void _selectSport(_SportOption sport) {
    if (_isTracking || _isStarting || sport.key == _sportType) return;

    setState(() {
      _sportType = sport.key;
      _gpsLocked = false;
      _isLocating = _currentPosition == null;
      _createGpsFilter();
    });

    unawaited(_startLocationPreview());
  }

  Future<void> _startGpsStream() async {
    await _ensureGpsStream();
  }

  bool _isDuplicateWorkoutPoint(KlsGpsPoint position) {
    final index = position.pointIndex;
    if (index == null) return false;

    final pointWorkoutId = position.workoutId;
    if (pointWorkoutId != null &&
        _workoutId != null &&
        pointWorkoutId != _workoutId) {
      return true;
    }

    return index <= _lastProcessedPointIndex;
  }

  void _markWorkoutPointProcessed(KlsGpsPoint position) {
    final index = position.pointIndex;
    if (index != null && index > _lastProcessedPointIndex) {
      _lastProcessedPointIndex = index;
      _pointIndex = max(_pointIndex, index + 1);
    }
  }

  void _rememberGpsFix(KlsGpsPoint position) {
    final localTimestamp = position.timestamp.toLocal();
    final previous = _lastGpsFixAt;
    if (previous == null || localTimestamp.isAfter(previous)) {
      _lastGpsFixAt = localTimestamp;
    }
  }

  void _handlePosition(
    KlsGpsPoint position, {
    bool notify = true,
  }) {
    if (_isDuplicateWorkoutPoint(position)) return;

    final filter = _gpsFilter;
    if (filter == null) return;

    _rememberGpsFix(position);

    try {
      _accuracy = position.accuracyMeters.isFinite
          ? max(0.0, position.accuracyMeters)
          : 0;

      final result = filter.add(position);
      _gpsLocked = result.gpsLocked;

      if (result.decision == KlsGpsPointDecision.gapReset) {
        final resumedPoint = _TrackPoint(position.latitude, position.longitude);

        // Never draw a straight line across an interval in which no trustworthy
        // GPS points exist. Start a fresh visual segment instead.
        if (_allRoutePoints.isEmpty) {
          _activeSegment.add(resumedPoint);
        } else {
          _routeSegments.add(<_TrackPoint>[resumedPoint]);
        }

        _currentPosition = position;
        _lastLiveTrackPoint = resumedPoint;

        if (position.altitudeMeters != null &&
            position.altitudeMeters!.isFinite) {
          _currentAltitudeMeters = position.altitudeMeters;
        }

        _currentSpeedMps = 0;
        _liveSpeedWindow.clear();

        if (notify) _followCurrentPoint();
        if (notify && mounted) setState(() {});
        return;
      }

      if (!result.shouldRecord) {
        if (result.decision == KlsGpsPointDecision.warmingUp ||
            result.decision == KlsGpsPointDecision.stationary) {
          _currentPosition = position;
          if (notify) _followCurrentPoint();
        }

        if (result.decision == KlsGpsPointDecision.stationary) {
          final lastMovement = _lastMovementAt;
          if (lastMovement == null ||
              DateTime.now().difference(lastMovement).inSeconds >= 6) {
            _currentSpeedMps = 0;
            _liveSpeedWindow.clear();
          }
        }

        if (result.decision != KlsGpsPointDecision.warmingUp &&
            result.decision != KlsGpsPointDecision.stationary) {
          _rejectedPointCount++;
        }

        if (notify && mounted) setState(() {});
        return;
      }

      final trackPoint = _TrackPoint(position.latitude, position.longitude);
      final previousLivePoint = _lastLiveTrackPoint;

      if (previousLivePoint != null && result.segmentMeters >= 2.5) {
        _updateMovementBearing(previousLivePoint, trackPoint);
      } else if (!_hasMovementBearing &&
          position.headingDegrees != null &&
          position.headingDegrees!.isFinite &&
          position.headingDegrees! >= 0) {
        _movementBearingDegrees = position.headingDegrees!;
      }

      _currentPosition = position;
      _lastLiveTrackPoint = trackPoint;
      _distanceMeters += max(0.0, result.segmentMeters);

      _updateLiveSpeed(max(0.0, result.currentSpeedMetersPerSecond));
      _maxSpeedMps = max(_maxSpeedMps, _currentSpeedMps);

      if (position.headingDegrees != null &&
          position.headingDegrees!.isFinite &&
          position.headingDegrees! >= 0) {
        _heading = position.headingDegrees!;
      }

      _updateElevation(position.altitudeMeters);
      _activeSegment.add(trackPoint);
      _registerAutomaticLaps();

      if (notify) _followCurrentPoint();
      if (notify && mounted) setState(() {});
    } finally {
      _markWorkoutPointProcessed(position);
    }
  }

  void _updateLiveSpeed(double candidateMetersPerSecond) {
    if (!candidateMetersPerSecond.isFinite || candidateMetersPerSecond < 0.5) {
      return;
    }

    _lastMovementAt = DateTime.now();
    _liveSpeedWindow.add(candidateMetersPerSecond);
    if (_liveSpeedWindow.length > 7) _liveSpeedWindow.removeAt(0);

    final sorted = List<double>.from(_liveSpeedWindow)..sort();
    final middle = sorted.length ~/ 2;
    _currentSpeedMps = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  void _updateMovementBearing(_TrackPoint from, _TrackPoint to) {
    final distance = _distanceBetweenTrackPoints(from, to);
    if (!distance.isFinite || distance < 2.5 || distance > 120) return;

    final nextBearing = _bearingBetweenTrackPoints(from, to);
    if (!_hasMovementBearing) {
      _movementBearingDegrees = nextBearing;
      _hasMovementBearing = true;
      return;
    }

    var delta = ((nextBearing - _movementBearingDegrees + 540.0) % 360.0) - 180.0;
    if (delta > 80) delta = 80;
    if (delta < -80) delta = -80;

    _movementBearingDegrees =
        (_movementBearingDegrees + delta * 0.28 + 360.0) % 360.0;
  }

  double _bearingBetweenTrackPoints(_TrackPoint from, _TrackPoint to) {
    final phi1 = from.lat * pi / 180;
    final phi2 = to.lat * pi / 180;
    final deltaLambda = (to.lng - from.lng) * pi / 180;
    final y = sin(deltaLambda) * cos(phi2);
    final x = cos(phi1) * sin(phi2) -
        sin(phi1) * cos(phi2) * cos(deltaLambda);
    return (atan2(y, x) * 180 / pi + 360.0) % 360.0;
  }

  double _distanceBetweenTrackPoints(_TrackPoint a, _TrackPoint b) {
    const radius = 6371000.0;
    final phi1 = a.lat * pi / 180;
    final phi2 = b.lat * pi / 180;
    final dPhi = (b.lat - a.lat) * pi / 180;
    final dLambda = (b.lng - a.lng) * pi / 180;
    final h = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return radius *
        2 *
        atan2(sqrt(h), sqrt(max(0.0, 1.0 - h)));
  }

  void _updateElevation(double? rawAltitude) {
    if (rawAltitude == null ||
        !rawAltitude.isFinite ||
        rawAltitude < -500 ||
        rawAltitude > 9000) {
      return;
    }

    _currentAltitudeMeters = rawAltitude;
    final previousSmooth = _smoothedAltitudeMeters;
    final smooth = previousSmooth == null
        ? rawAltitude
        : previousSmooth * 0.75 + rawAltitude * 0.25;
    _smoothedAltitudeMeters = smooth;

    final reference = _elevationReferenceMeters;
    if (reference == null) {
      _elevationReferenceMeters = smooth;
      return;
    }

    final delta = smooth - reference;
    if (delta >= 1.5) {
      _elevationGainMeters += delta;
      _elevationReferenceMeters = smooth;
    } else if (delta <= -1.5) {
      _elevationReferenceMeters = smooth;
    }
  }

  void _registerAutomaticLaps() {
    while (_distanceMeters >= _nextAutoLapKm * 1000) {
      final boundaryMeters = _nextAutoLapKm * 1000.0;

      _appendLap(
        startDistanceMeters: _autoLapStartDistanceMeters,
        endDistanceMeters: boundaryMeters,
        startElapsedSeconds: _autoLapStartElapsedSeconds,
        startElevationGainMeters: _autoLapStartElevationGainMeters,
        isAutomatic: true,
      );

      _autoLapStartDistanceMeters = boundaryMeters;
      _autoLapStartElapsedSeconds = _elapsedSeconds;
      _autoLapStartElevationGainMeters = _elevationGainMeters;
      _nextAutoLapKm++;
    }
  }

  void _appendLap({
    required double startDistanceMeters,
    required double endDistanceMeters,
    required int startElapsedSeconds,
    required double startElevationGainMeters,
    required bool isAutomatic,
  }) {
    final lapDistance = endDistanceMeters - startDistanceMeters;
    final lapDuration = _elapsedSeconds - startElapsedSeconds;
    final lapElevation = _elevationGainMeters - startElevationGainMeters;

    if (lapDistance < 1 || lapDuration < 1) return;

    _laps.add(
      _WorkoutLap(
        number: _laps.length + 1,
        distanceMeters: lapDistance,
        durationSeconds: lapDuration,
        elevationGainMeters: max(0.0, lapElevation),
        isAutomatic: isAutomatic,
      ),
    );
  }

  void _addManualLap() {
    if (!_isTracking || _isPaused) return;

    final distance = _distanceMeters - _manualLapStartDistanceMeters;
    final duration = _elapsedSeconds - _manualLapStartElapsedSeconds;

    if (distance < 50 || duration < 10) {
      _showSavedSnack('Для отсечки нужно хотя бы 50 м и 10 секунд');
      return;
    }

    setState(() {
      _appendLap(
        startDistanceMeters: _manualLapStartDistanceMeters,
        endDistanceMeters: _distanceMeters,
        startElapsedSeconds: _manualLapStartElapsedSeconds,
        startElevationGainMeters: _manualLapStartElevationGainMeters,
        isAutomatic: false,
      );

      _manualLapStartDistanceMeters = _distanceMeters;
      _manualLapStartElapsedSeconds = _elapsedSeconds;
      _manualLapStartElevationGainMeters = _elevationGainMeters;
    });

    unawaited(HapticFeedback.selectionClick());
    _showSavedSnack('Круг ${_laps.length} сохранён');
  }

  void _completeTrailingLap() {
    final remainingDistance = _distanceMeters - _autoLapStartDistanceMeters;
    final remainingDuration = _elapsedSeconds - _autoLapStartElapsedSeconds;

    // Keep the final partial kilometre as an automatic split when it is large
    // enough to be meaningful. This fixes 8.43 km ending with only 8 splits.
    if (remainingDistance < 50 || remainingDuration < 10) return;

    _appendLap(
      startDistanceMeters: _autoLapStartDistanceMeters,
      endDistanceMeters: _distanceMeters,
      startElapsedSeconds: _autoLapStartElapsedSeconds,
      startElevationGainMeters: _autoLapStartElevationGainMeters,
      isAutomatic: true,
    );

    _autoLapStartDistanceMeters = _distanceMeters;
    _autoLapStartElapsedSeconds = _elapsedSeconds;
    _autoLapStartElevationGainMeters = _elevationGainMeters;
  }

  void _followCurrentPoint() {
    if (!_mapReady || !_followUser || _currentPosition == null) return;

    final target = ll.LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || !_followUser) return;

      final zoom = max(16.5, _mapController.camera.zoom);
      _mapController.move(target, zoom);

      if (_isTracking &&
          !_isPaused &&
          _hasMovementBearing &&
          _currentSpeedMps >= 0.8) {
        final rotation = (360.0 - _movementBearingDegrees) % 360.0;
        _mapController.rotate(rotation);
      }
    });
  }

  Future<void> _pauseWorkout() async {
    if (!_isTracking || _isPaused) return;

    final workoutId = _workoutId;
    final pausedAt = DateTime.now();

    setState(() {
      _isPaused = true;
      _pausedAt = pausedAt;
      _currentSpeedMps = 0;
      _liveSpeedWindow.clear();
      _lastMovementAt = null;
    });

    // Stop native acquisition first, then consume every fix already persisted
    // to disk before resetting the trusted filter.
    await _stopGpsNative(finishWorkout: false);
    await _replayNewJournalPoints();

    _gpsFilter?.reset();
    _gpsLocked = false;

    if (workoutId != null && workoutId.isNotEmpty) {
      await _offlineManager.pauseWorkout(workoutId, pausedAt);
    }

    if (mounted) setState(() {});
  }

  Future<void> _resumeWorkout() async {
    if (!_isTracking || !_isPaused) return;

    final workoutId = _workoutId;
    if (workoutId == null || workoutId.isEmpty) return;

    final resumedAt = DateTime.now();
    _pauseSeconds = await _offlineManager.resumeWorkout(workoutId, resumedAt);

    _routeSegments.add(<_TrackPoint>[]);
    _gpsFilter?.reset();

    setState(() {
      _isPaused = false;
      _pausedAt = null;
      _currentSpeedMps = 0;
      _liveSpeedWindow.clear();
      _lastMovementAt = null;
      _lastLiveTrackPoint = _currentPosition == null
          ? null
          : _TrackPoint(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            );
      _gpsLocked = false;
    });

    try {
      await _startGpsStream();
      await _replayNewJournalPoints();
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = 'Ошибка GPS: ${_cleanError(error)}';
        });
      }
    }
  }

  bool _isWorkoutTooShort() => _elapsedSeconds < 30 || _distanceMeters < 20;

  Future<void> _cancelWorkout({bool goBack = false}) async {
    final workoutId = _workoutId;
    KlsHeartRateDeviceWidget.cancelWorkoutSession();

    await _positionSub?.cancel();
    _positionSub = null;
    await _stopGpsNative(finishWorkout: true);

    if (workoutId != null && workoutId.isNotEmpty) {
      await _offlineManager.cancelWorkout(workoutId);
    }

    _timer?.cancel();
    if (!mounted) return;

    setState(() {
      _isTracking = false;
      _isPaused = false;
      _isFinishing = false;
      _isStarting = false;
      _resetLocalWorkout();
      _errorText = null;
    });

    _showSavedSnack('Тренировка не сохранена');
    if (goBack && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _handleBackPressed() async {
    if (!_isTracking) {
      Navigator.of(context).maybePop();
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _klsNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Выйти из записи?',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Текущая тренировка не будет сохранена в дневник.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontFamily: 'Montserrat',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Выйти без сохранения',
              style: TextStyle(color: Color(0xFFFF7D7D)),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) await _cancelWorkout(goBack: true);
  }

  Future<void> _finishWorkout() async {
    if (!_isTracking || _isFinishing) return;

    // Critical for lock-screen recording: before deciding that a workout is too
    // short, import every RAW point native code recorded while Flutter could be
    // suspended.
    try {
      await _replayNewJournalPoints();
    } catch (error) {
      debugPrint('Не удалось перечитать GPS-журнал перед финишем: $error');
    }

    if (!mounted) return;

    if (_isWorkoutTooShort()) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _klsNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Слишком короткая тренировка',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Для сохранения нужно хотя бы 30 секунд и 20 метров корректного маршрута.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontFamily: 'Montserrat',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _klsNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Завершить тренировку?',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Запись маршрута остановится, после чего откроется сводка.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontFamily: 'Montserrat',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Завершить',
              style: TextStyle(color: Color(0xFFFF7D7D)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isFinishing = true;
      _errorText = null;
    });

    try {
      final finishedAt = DateTime.now();

      KlsHeartRateDeviceWidget.stopWorkoutSession();
      _captureHeartRateSummary();
      _timer?.cancel();

      if (_isPaused && _pausedAt != null) {
        _pauseSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
        _pausedAt = null;
      }

      final workoutId = _workoutId ?? '';
      if (workoutId.isEmpty) throw Exception('Нет workoutId');

      // Stop native acquisition, then read the journal one final time. No point
      // can arrive after this replay, so local finish totals are stable.
      try {
        await _stopGpsNative(finishWorkout: true);
      } catch (error) {
        debugPrint('Не удалось сразу остановить native GPS: $error');
      }

      await _positionSub?.cancel();
      _positionSub = null;

      await _replayNewJournalPoints();

      if (_startedAt != null) {
        _elapsedSeconds = max(
          0,
          finishedAt.difference(_startedAt!).inSeconds - _pauseSeconds,
        );
      }

      _completeTrailingLap();

      final distanceKm = _distanceMeters / 1000;
      final avgSpeedMps =
          _elapsedSeconds > 0 ? _distanceMeters / _elapsedSeconds : 0.0;

      final localResult = <String, dynamic>{
        'success': true,
        'workout_id': workoutId,
        'status': 'pending_sync',
        'distance_meters': _distanceMeters,
        'distance_km': distanceKm,
        'duration_seconds': _elapsedSeconds,
        'pause_seconds': _pauseSeconds,
        'avg_speed_mps': avgSpeedMps,
        'avg_speed_kmh': avgSpeedMps * 3.6,
        'max_speed_mps': _maxSpeedMps,
        'max_speed_kmh': _maxSpeedMps * 3.6,
        'avg_pace_seconds_per_km':
            distanceKm > 0 ? _elapsedSeconds / distanceKm : 0.0,
        'elevation_gain_meters': _elevationGainMeters,
      };

      await _offlineManager.updateDiaryData(
        workoutId: workoutId,
        diaryData: _buildDiaryData(localResult),
      );

      await _offlineManager.finishWorkout(
        workoutId: workoutId,
        durationSeconds: _elapsedSeconds,
        pauseSeconds: _pauseSeconds,
        finishedAt: finishedAt,
      );

      if (mounted) {
        setState(() {
          _isTracking = false;
          _isPaused = false;
          _currentSpeedMps = 0;
          _awaitingDiarySave = true;
        });

        _showSavedSnack(
          'Тренировка сохранена на телефоне. Интернет для завершения не нужен.',
        );
        _showFinishSheet(localResult);
      }

      unawaited(
        _trackEvent(
          'finished_workout',
          metadata: {
            'workout_id': workoutId,
            'sport_type': _sportType,
            'training_type': _selectedSport.diaryType,
            'duration_seconds': _elapsedSeconds,
            'pause_seconds': _pauseSeconds,
            'distance_meters': _distanceMeters,
            'max_speed_mps': _maxSpeedMps,
            'elevation_gain_meters': _elevationGainMeters,
            'lap_count': _laps.length,
            'rejected_gps_points': _rejectedPointCount,
            'last_native_point_index': _lastProcessedPointIndex,
            'heart_rate_samples': _finishedHeartRateSampleCount,
            if (_finishedAverageBpm != null) 'avg_pulse': _finishedAverageBpm,
            if (_finishedMaxBpm != null) 'max_pulse': _finishedMaxBpm,
            'plan_key': widget.planKey,
            'plan_day_id': widget.planDayId,
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = _cleanError(error));
      }
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  Map<String, dynamic> _buildDiaryData(Map<String, dynamic> data) {
    final userId = widget.currentUserId?.trim() ?? '';
    if (userId.isEmpty) throw Exception('Не передан currentUserId');

    final durationSeconds = _asInt(data['duration_seconds']);
    final now = DateTime.now();
    final actualDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final plannedDate = widget.plannedDate?.trim() ?? '';
    final date =
        _hasPlanContext && plannedDate.isNotEmpty ? plannedDate : actualDate;
    final plannedTitle = widget.plannedTitle?.trim() ?? '';
    final plannedDescription = widget.plannedDescription?.trim() ?? '';

    final title = _hasPlanContext && plannedTitle.isNotEmpty
        ? plannedTitle
        : _selectedSport.diaryType;
    final description = _hasPlanContext && plannedDescription.isNotEmpty
        ? plannedDescription
        : 'GPS-тренировка КЛС';

    return <String, dynamic>{
      'training_id': _workoutId,
      'user_id': userId,
      'date': date,
      'title': title,
      'description': description,
      'training_type': _selectedSport.diaryType,
      'activity_type_code': _sportType,
      'duration_minutes': max(1, (durationSeconds / 60).round()),
      'distance_km': _asDouble(data['distance_km']),
      if (_finishedAverageBpm != null) 'avg_pulse': _finishedAverageBpm,
      if (_finishedMaxBpm != null) 'max_pulse': _finishedMaxBpm,
      'wellbeing': _wellbeing,
      'comment': _commentController.text.trim(),
      'rpe': _rpe,
      'sleep_hours': _sleepHours,
      'fatigue': _fatigue,
      'stress': 2,
      'muscle_pain': 2,
      'motivation': 4,
      'source': 'kls_gps',
      'gps_workout_id': _workoutId,
      'is_interval': false,
      'elevation_gain_m': _elevationGainMeters.round(),
      'lap_count': _laps.length,
      'laps_json': jsonEncode(_laps.map((lap) => lap.toJson()).toList()),
      if (_hasPlanContext) 'plan_key': widget.planKey?.trim(),
      if (_hasPlanContext) 'plan_day_id': widget.planDayId?.trim(),
      if (_hasPlanContext) 'planned_date': date,
      if (_hasPlanContext) 'planned_title': widget.plannedTitle?.trim() ?? '',
      if (_hasPlanContext)
        'planned_description': widget.plannedDescription?.trim() ?? '',
      if (_hasPlanContext)
        'planned_duration_minutes': widget.plannedDurationMinutes ?? 0,
      if (_hasPlanContext)
        'planned_activity_type': widget.plannedActivityType?.trim() ?? '',
      if (_hasPlanContext)
        'plan_completion_status':
            widget.planCompletionStatus?.trim().isNotEmpty == true
                ? widget.planCompletionStatus!.trim()
                : 'completed',
    };
  }

  Map<String, dynamic> _initialDiaryData() {
    return _buildDiaryData(const <String, dynamic>{
      'duration_seconds': 0,
      'distance_km': 0.0,
    });
  }

  Future<KlsWorkoutSyncResult> _saveFinishedWorkoutToDiary(
    Map<String, dynamic> data,
  ) async {
    final workoutId = _workoutId;
    if (workoutId == null || workoutId.isEmpty) {
      throw Exception('Нет workoutId');
    }

    await _offlineManager.updateFeedback(
      workoutId: workoutId,
      wellbeing: _wellbeing,
      rpe: _rpe,
      fatigue: _fatigue,
      sleepHours: _sleepHours,
      comment: _commentController.text,
    );

    await _offlineManager.updateDiaryData(
      workoutId: workoutId,
      diaryData: _buildDiaryData(data),
    );

    return _offlineManager.syncWorkout(workoutId);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatPaceFromSeconds(double secondsPerKm) {
    if (secondsPerKm <= 0 || secondsPerKm.isNaN || secondsPerKm.isInfinite) {
      return '—';
    }
    final total = secondsPerKm.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String _formatAveragePace() {
    if (_distanceMeters < 50 || _elapsedSeconds <= 0) return '—';
    final pace = _elapsedSeconds / (_distanceMeters / 1000);
    return '${_formatPaceFromSeconds(pace.toDouble())} /км';
  }

  String _formatCurrentPace() {
    if (_currentSpeedMps < 0.5) return '—';
    return '${_formatPaceFromSeconds(1000 / _currentSpeedMps)} /км';
  }

  String _formatAverageSpeedKmh() {
    if (_elapsedSeconds <= 0) return '0,0 км/ч';
    final value = (_distanceMeters / _elapsedSeconds) * 3.6;
    return '${value.isFinite ? value.toStringAsFixed(1).replaceAll('.', ',') : '0,0'} км/ч';
  }

  String _formatCurrentSpeedKmh() {
    final value = _currentSpeedMps * 3.6;
    return '${value.isFinite ? value.toStringAsFixed(1).replaceAll('.', ',') : '0,0'} км/ч';
  }

  String _formatMaxSpeedKmh() {
    final value = _maxSpeedMps * 3.6;
    return '${value.isFinite ? value.toStringAsFixed(1).replaceAll('.', ',') : '0,0'} км/ч';
  }

  String _formatDistancePrimary() {
    final km = _distanceMeters / 1000;
    if (km < 1) return km.toStringAsFixed(3).replaceAll('.', ',');
    return km.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatDistanceShort(double meters) {
    if (meters < 1000) return '${meters.round()} м';
    return '${(meters / 1000).toStringAsFixed(2).replaceAll('.', ',')} км';
  }

  String _formatLapMetric(_WorkoutLap lap) {
    if (_usesPace) {
      final pace = lap.distanceMeters <= 0
          ? 0.0
          : lap.durationSeconds / (lap.distanceMeters / 1000);
      return '${_formatPaceFromSeconds(pace.toDouble())} /км';
    }

    if (lap.durationSeconds <= 0) return '—';
    final speed = lap.distanceMeters / lap.durationSeconds * 3.6;
    return '${speed.toStringAsFixed(1).replaceAll('.', ',')} км/ч';
  }

  String get _gpsStatus {
    if (_isPaused) return 'Запись на паузе';

    if (!_isTracking) {
      if (_isLocating) return 'Ищем местоположение';
      if (_currentPosition == null) return 'GPS пока не найден';
      if (_backgroundGpsChecked && !_backgroundGpsCapable) {
        return 'Фоновая GPS-запись не настроена';
      }
      if (_accuracy > 50) return 'Слабый GPS · ±${_accuracy.round()} м';
      return 'GPS готов · ±${_accuracy.round()} м';
    }

    final age = _gpsFixAgeSeconds;
    if (age != null && age > 12) {
      return 'GPS сигнал потерян · последняя точка ${age}с назад';
    }
    if (age != null && age > 6) {
      return 'GPS сигнал нестабилен';
    }
    if (!_gpsLocked) return 'Стабилизируем GPS';
    if (_accuracy > 25) return 'Слабый GPS · ±${_accuracy.round()} м';
    return 'GPS записывает маршрут · ±${_accuracy.round()} м';
  }

  Color get _gpsStatusColor {
    if (_isPaused) return _klsGold;

    if (_backgroundGpsChecked && !_backgroundGpsCapable) {
      return const Color(0xFFFF7D7D);
    }

    if (_currentPosition == null || _accuracy > 50) {
      return const Color(0xFFFF7D7D);
    }

    if (_isTracking) {
      final age = _gpsFixAgeSeconds;
      if (age != null && age > 12) return const Color(0xFFFF7D7D);
      if (age != null && age > 6) return _klsGold;
      if (!_gpsLocked) return _klsGold;
    }

    return _klsGreen;
  }

  String get _mapStatusLabel {
    if (_isTracking) {
      final age = _gpsFixAgeSeconds;
      if (age != null && age > 12) return 'GPS потерян';
      if (age != null && age > 6) return 'GPS нестабилен';
      return _gpsLocked ? 'Маршрут' : 'Стабилизация GPS';
    }
    return _currentPosition == null ? 'Ищем GPS' : 'Вы здесь';
  }

  IconData get _mapStatusIcon {
    if (_isTracking) {
      final age = _gpsFixAgeSeconds;
      if (age != null && age > 6) return Icons.gps_off_rounded;
      return _gpsLocked ? Icons.route_rounded : Icons.gps_not_fixed_rounded;
    }
    return Icons.my_location_rounded;
  }

  void _showSavedSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0E1D36),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF030B16),
            Color(0xFF061B34),
            Color(0xFF031326),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: _isTracking
                    ? _buildTrackingScreen()
                    : _buildPreparationScreen(),
              ),
            ),
            if (_countdownValue != null) _countdownOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreparationScreen() {
    return Column(
      children: [
        _header(),
        const SizedBox(height: 12),
        if (_hasPlanContext) ...[
          _planContextCard(),
          const SizedBox(height: 10),
        ],
        _sportSelector(),
        const SizedBox(height: 10),
        _connectionPanel(),
        const SizedBox(height: 10),
        Expanded(child: _mapCard()),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          _errorBox(),
        ],
        const SizedBox(height: 10),
        _startButton(),
      ],
    );
  }

  Widget _buildTrackingScreen() {
    final showHeartRate = _heartRateConnected && _currentHeartRateBpm != null;

    return Column(
      children: [
        _header(),
        const SizedBox(height: 10),
        _recordingStatusBar(),
        if (showHeartRate) ...[
          const SizedBox(height: 8),
          _liveHeartRateBar(),
        ],
        const SizedBox(height: 10),
        _activeMetricsCard(),
        const SizedBox(height: 10),
        _activeMetricsRow(),
        const SizedBox(height: 10),
        Expanded(child: _mapCard()),
        if (_laps.isNotEmpty) ...[
          const SizedBox(height: 8),
          _lastLapBar(),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          _errorBox(),
        ],
        const SizedBox(height: 10),
        _trackingControls(),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: _handleBackPressed,
          child: _iconSurface(Icons.arrow_back_ios_new_rounded, size: 38),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            _isTracking ? _selectedSport.title : 'Тренировка',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_isTracking)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_isPaused ? _klsGold : _klsGreen).withOpacity(0.10),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: (_isPaused ? _klsGold : _klsGreen).withOpacity(0.32),
              ),
            ),
            child: Text(
              _isPaused ? 'Пауза' : 'Запись',
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: _isPaused ? _klsGold : _klsGreen,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _planContextCard() {
    final title = widget.plannedTitle?.trim().isNotEmpty == true
        ? widget.plannedTitle!.trim()
        : 'Задание по плану';
    final description = widget.plannedDescription?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _klsGold.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _klsGold.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _klsGold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.assignment_turned_in_outlined,
              color: _klsGold,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ПО ПЛАНУ НА СЕГОДНЯ',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: _klsGold,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      color: Colors.white.withOpacity(0.54),
                      fontSize: 9.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((widget.plannedDurationMinutes ?? 0) > 0)
            Text(
              '${widget.plannedDurationMinutes} мин',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: _klsGold,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sportSelector() {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _sports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sport = _sports[index];
          final selected = sport.key == _sportType;

          return GestureDetector(
            onTap: _isStarting ? null : () => _selectSport(sport),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                color: selected
                    ? _klsGold.withOpacity(0.12)
                    : Colors.white.withOpacity(0.045),
                border: Border.all(
                  color: selected
                      ? _klsGold
                      : Colors.white.withOpacity(0.08),
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    sport.icon,
                    color: selected
                        ? _klsGold
                        : Colors.white.withOpacity(0.45),
                    size: 19,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      sport.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: selected
                            ? _klsGold
                            : Colors.white.withOpacity(0.58),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _connectionPanel() {
    final connected = _heartRateConnected;
    final bpm = _currentHeartRateBpm;
    final pulseStatus = connected
        ? bpm != null
            ? '$bpm уд/мин'
            : 'Подключено'
        : 'Подключить';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _surfaceDecoration(radius: 18),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _gpsReadyForStart
                    ? Icons.gps_fixed_rounded
                    : Icons.gps_not_fixed_rounded,
                color: _gpsStatusColor,
                size: 18,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'GPS',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  _gpsStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: _gpsStatusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openHeartRateDevice,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      connected
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: connected
                          ? _klsGreen
                          : Colors.white.withOpacity(0.42),
                      size: 18,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Пульсометр',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (connected)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _heartRateDeviceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  color: Colors.white.withOpacity(0.40),
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      pulseStatus,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: connected ? _klsGreen : _klsGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.28),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordingStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _gpsStatusColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _gpsStatusColor.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(
            _gpsLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
            size: 15,
            color: _gpsStatusColor,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _gpsStatus,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: _gpsStatusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_currentAltitudeMeters != null)
            Text(
              '${_currentAltitudeMeters!.round()} м над ур. моря',
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: Colors.white.withOpacity(0.46),
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  Widget _liveHeartRateBar() {
    final bpm = _currentHeartRateBpm;
    if (!_heartRateConnected || bpm == null) return const SizedBox.shrink();

    final avg = KlsHeartRateDeviceWidget.workoutAverageBpm;
    final maxBpm = KlsHeartRateDeviceWidget.workoutMaxBpm;

    return GestureDetector(
      onTap: _openHeartRateDevice,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _klsRed.withOpacity(0.06),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _klsRed.withOpacity(0.16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: _klsRed, size: 17),
            const SizedBox(width: 8),
            Text(
              '$bpm',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'уд/мин',
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: Colors.white.withOpacity(0.44),
                fontSize: 9,
              ),
            ),
            const Spacer(),
            if (avg != null)
              Text(
                'ср. $avg',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (avg != null && maxBpm != null)
              Text('  ·  ', style: TextStyle(color: Colors.white.withOpacity(0.20))),
            if (maxBpm != null)
              Text(
                'макс. $maxBpm',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.26),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeMetricsCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: _surfaceDecoration(radius: 24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ВРЕМЯ', style: _metricLabel()),
                    const SizedBox(height: 3),
                    Text(
                      _formatDuration(_elapsedSeconds),
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 58,
                color: Colors.white.withOpacity(0.08),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ДИСТАНЦИЯ', style: _metricLabel()),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            _formatDistancePrimary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              color: _klsGold,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            'км',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              color: _klsGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeMetricsRow() {
    late final String firstLabel;
    late final String firstValue;
    late final IconData firstIcon;
    late final String secondLabel;
    late final String secondValue;
    late final IconData secondIcon;

    if (_isRun) {
      firstLabel = 'Текущий темп';
      firstValue = _formatCurrentPace();
      firstIcon = Icons.speed_rounded;
      secondLabel = 'Макс. скорость';
      secondValue = _formatMaxSpeedKmh();
      secondIcon = Icons.bolt_rounded;
    } else if (_isSkiLike) {
      firstLabel = 'Скорость сейчас';
      firstValue = _formatCurrentSpeedKmh();
      firstIcon = Icons.bolt_rounded;
      secondLabel = 'Текущий темп';
      secondValue = _formatCurrentPace();
      secondIcon = Icons.speed_rounded;
    } else {
      // Bike
      firstLabel = 'Скорость сейчас';
      firstValue = _formatCurrentSpeedKmh();
      firstIcon = Icons.bolt_rounded;
      secondLabel = 'Макс. скорость';
      secondValue = _formatMaxSpeedKmh();
      secondIcon = Icons.flash_on_rounded;
    }

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _showLapsSheet,
            child: _metricTile(
              icon: firstIcon,
              label: firstLabel,
              value: firstValue,
              footer: 'Нажмите: круги',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricTile(
            icon: secondIcon,
            label: secondLabel,
            value: secondValue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricTile(
            icon: Icons.terrain_rounded,
            label: 'Набор',
            value: '${_elevationGainMeters.round()} м',
          ),
        ),
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    String? footer,
  }) {
    return Container(
      height: 82,
      padding: const EdgeInsets.all(10),
      decoration: _surfaceDecoration(radius: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _klsGold, size: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mutedTextStyle(9),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 2),
            Text(
              footer,
              style: TextStyle(
                color: Colors.white.withOpacity(0.32),
                fontFamily: 'Montserrat',
                fontSize: 7.8,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mapCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07182D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: _KlsRouteMap(
                controller: _mapController,
                segments: _routeSegments,
                currentPoint: _currentPosition == null
                    ? null
                    : _TrackPoint(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                accuracyMeters: _accuracy,
                headingDegrees:
                    _hasMovementBearing ? _movementBearingDegrees : _heading,
                fitWholeRoute: false,
                showFinishMarker: false,
                onReady: () {
                  _mapReady = true;
                  _followCurrentPoint();
                },
                onUserGesture: () {
                  if (_followUser && mounted) {
                    setState(() => _followUser = false);
                  }
                },
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _mapChip(_mapStatusLabel, _mapStatusIcon),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Column(
                children: [
                  _mapAction(
                    icon: Icons.fullscreen_rounded,
                    onTap: _openFullMap,
                  ),
                  const SizedBox(height: 7),
                  _mapAction(
                    icon: Icons.my_location_rounded,
                    active: _followUser,
                    onTap: () {
                      setState(() => _followUser = true);
                      _followCurrentPoint();
                    },
                  ),
                ],
              ),
            ),
            if (_currentPosition == null)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xDD061326),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _isLocating
                        ? 'Определяем ваше местоположение…'
                        : 'Включите геолокацию и точный доступ к GPS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontFamily: 'Montserrat',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lastLapBar() {
    final lap = _laps.last;
    return GestureDetector(
      onTap: _showLapsSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _klsGold.withOpacity(0.07),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _klsGold.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: _klsGold, size: 16),
            const SizedBox(width: 7),
            Text(
              'Круг ${lap.number}',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '${_formatDistanceShort(lap.distanceMeters)} · ${_formatDuration(lap.durationSeconds)} · ${_formatLapMetric(lap)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 9.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startButton() {
    final enabled = !_isRestoring && !_isStarting && _gpsReadyForStart;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: enabled ? _startWorkout : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _klsGold,
          disabledBackgroundColor: _klsGold.withOpacity(0.22),
          foregroundColor: const Color(0xFF08111F),
          disabledForegroundColor: Colors.white.withOpacity(0.42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: Text(
          _isRestoring
              ? 'Проверяем сохранённую тренировку…'
              : _isStarting
                  ? 'Подготавливаем тренировку…'
                  : (_backgroundGpsChecked && !_backgroundGpsCapable)
                      ? 'Нужно включить фоновый GPS'
                      : _gpsReadyForStart
                          ? 'Начать тренировку'
                          : 'Ожидаем GPS',
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _trackingControls() {
    return Row(
      children: [
        Expanded(
          child: _controlButton(
            label: 'Круг',
            icon: Icons.flag_outlined,
            onTap: _isPaused || _isFinishing ? null : _addManualLap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _controlButton(
            label: _isPaused ? 'Продолжить' : 'Пауза',
            icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: _isFinishing
                ? null
                : (_isPaused ? _resumeWorkout : _pauseWorkout),
            accent: _klsGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _controlButton(
            label: _isFinishing ? 'Сохраняем' : 'Завершить',
            icon: Icons.stop_rounded,
            onTap: _isFinishing ? null : _finishWorkout,
            accent: const Color(0xFFFF6B5A),
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _controlButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color accent = Colors.white,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: filled ? accent : accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withOpacity(filled ? 0.90 : 0.24),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : accent),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: filled ? Colors.white : accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xE6030B16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _klsGold.withOpacity(0.10),
                  border: Border.all(color: _klsGold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _klsGold.withOpacity(0.26),
                      blurRadius: 38,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${_countdownValue ?? ''}',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      color: _klsGold,
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Приготовьтесь',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Запись начнётся после отсчёта',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFullMap() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _KlsFullMapPage(
          segments: _routeSegments
              .map((segment) => List<_TrackPoint>.from(segment))
              .toList(),
          currentPoint: _currentPosition == null
              ? null
              : _TrackPoint(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
          accuracyMeters: _accuracy,
          headingDegrees:
              _hasMovementBearing ? _movementBearingDegrees : _heading,
        ),
      ),
    );
  }

  void _showLapsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: Container(
            decoration: const BoxDecoration(
              color: _klsNavy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Круги и отсечки',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded, color: _klsGold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _laps.isEmpty
                        ? Center(
                            child: Text(
                              'Первая автоматическая отсечка появится на 1 км.\nВо время записи можно нажать «Круг».',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                color: Colors.white.withOpacity(0.54),
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                            itemCount: _laps.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _lapRow(_laps[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _lapRow(_WorkoutLap lap) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _surfaceDecoration(radius: 17),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _klsGold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                '${lap.number}',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  color: _klsGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDistanceShort(lap.distanceMeters),
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lap.isAutomatic ? 'Автоматическая отсечка' : 'Ручной круг',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 8.8,
                  ),
                ),
              ],
            ),
          ),
          _lapValue('Время', _formatDuration(lap.durationSeconds)),
          const SizedBox(width: 12),
          _lapValue(
            _usesPace ? 'Темп' : 'Скорость',
            _formatLapMetric(lap),
          ),
          const SizedBox(width: 12),
          _lapValue('Набор', '${lap.elevationGainMeters.round()} м'),
        ],
      ),
    );
  }

  Widget _lapValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Montserrat',
            color: Colors.white.withOpacity(0.38),
            fontSize: 7.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            color: Colors.white,
            fontSize: 9.7,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _klsRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _klsRed.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFFB3B3),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFB3B3),
                fontFamily: 'Montserrat',
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _surfaceDecoration({required double radius}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.055),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.09)),
    );
  }

  TextStyle _mutedTextStyle(double size) {
    return TextStyle(
      color: Colors.white.withOpacity(0.50),
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle _metricLabel() {
    return TextStyle(
      color: Colors.white.withOpacity(0.42),
      fontFamily: 'Montserrat',
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
  }

  Widget _iconSurface(IconData icon, {double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: _surfaceDecoration(radius: 14),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }

  Widget _mapChip(String label, IconData icon) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xDD061326),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _gpsStatusColor, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Montserrat',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapAction({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? _klsGold : const Color(0xDD061326),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFF08111F) : Colors.white,
          size: 19,
        ),
      ),
    );
  }

  void _showFinishSheet(Map<String, dynamic> data) {
    _wellbeing = 4;
    _rpe = 5;
    _fatigue = 2;
    _sleepHours = 8;
    _commentController.clear();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final distanceKm = _asDouble(data['distance_km']);
            final duration = _asInt(data['duration_seconds']);
            final pace = _asDouble(data['avg_pace_seconds_per_km']);
            final speed = _asDouble(data['avg_speed_kmh']);

            return Container(
              height: MediaQuery.of(context).size.height * 0.94,
              decoration: const BoxDecoration(
                color: _klsNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedSport.title,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Тренировка завершена',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: Colors.white.withOpacity(0.46),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isSavingDiary
                                ? null
                                : () {
                                    _awaitingDiarySave = false;
                                    Navigator.pop(sheetContext);
                                    unawaited(
                                      _offlineManager.syncPendingWorkouts(),
                                    );
                                  },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _klsGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _finishHeroCard(
                              distanceKm,
                              duration,
                              pace,
                              speed,
                            ),
                            if (_finishedHeartRateSampleCount > 0) ...[
                              const SizedBox(height: 10),
                              _finishHeartRateCard(),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 190,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: _KlsStaticRouteMap(
                                  segments: _routeSegments,
                                  showFinishMarker: true,
                                  currentPoint: null,
                                  accuracyMeters: 0,
                                  headingDegrees: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Круги и отсечки',
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_laps.length}',
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: _klsGold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_laps.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: _surfaceDecoration(radius: 17),
                                child: Text(
                                  'Отсечки не созданы.',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: Colors.white.withOpacity(0.50),
                                    fontSize: 10.5,
                                  ),
                                ),
                              )
                            else
                              ..._laps.map(
                                (lap) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _lapRow(lap),
                                ),
                              ),
                            const SizedBox(height: 10),
                            const Text(
                              'Оценка тренировки',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _sheetSlider(
                              'Самочувствие',
                              _wellbeing.toDouble(),
                              1,
                              5,
                              4,
                              '$_wellbeing / 5',
                              (value) => setSheetState(
                                () => _wellbeing = value.round(),
                              ),
                            ),
                            _sheetSlider(
                              'RPE / сложность',
                              _rpe.toDouble(),
                              1,
                              10,
                              9,
                              '$_rpe / 10',
                              (value) => setSheetState(
                                () => _rpe = value.round(),
                              ),
                            ),
                            _sheetSlider(
                              'Усталость',
                              _fatigue.toDouble(),
                              1,
                              5,
                              4,
                              '$_fatigue / 5',
                              (value) => setSheetState(
                                () => _fatigue = value.round(),
                              ),
                            ),
                            _sheetSlider(
                              'Сон',
                              _sleepHours,
                              0,
                              12,
                              24,
                              '${_sleepHours.toStringAsFixed(1)} ч',
                              (value) => setSheetState(
                                () => _sleepHours = double.parse(
                                  value.toStringAsFixed(1),
                                ),
                              ),
                            ),
                            TextField(
                              controller: _commentController,
                              maxLines: 3,
                              cursorColor: _klsGold,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Montserrat',
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Комментарий к тренировке',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.34),
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                onPressed: _isSavingDiary
                                    ? null
                                    : () {
                                        _awaitingDiarySave = false;
                                        Navigator.pop(sheetContext);
                                        unawaited(
                                          _offlineManager.syncPendingWorkouts(),
                                        );
                                      },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  'Позже',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isSavingDiary
                                    ? null
                                    : () async {
                                        setState(() => _isSavingDiary = true);
                                        setSheetState(() {});

                                        try {
                                          final syncResult =
                                              await _saveFinishedWorkoutToDiary(
                                            data,
                                          );

                                          _awaitingDiarySave = false;
                                          if (!mounted) return;

                                          Navigator.pop(sheetContext);

                                          _showSavedSnack(
                                            syncResult.synced
                                                ? (_hasPlanContext
                                                    ? 'Тренировка сохранена и связана с планом'
                                                    : 'Тренировка добавлена в дневник')
                                                : 'Тренировка сохранена на телефоне и отправится автоматически',
                                          );

                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 250),
                                          );

                                          if (mounted) {
                                            Navigator.of(this.context).pop(true);
                                          }
                                        } catch (error) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  _cleanError(error),
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _isSavingDiary = false,
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _klsGold,
                                  foregroundColor: const Color(0xFF08111F),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  _isSavingDiary
                                      ? 'Сохраняем…'
                                      : 'Сохранить в дневник',
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _finishHeartRateCard() {
    final avg = _finishedAverageBpm;
    final maxBpm = _finishedMaxBpm;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _klsRed.withOpacity(0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _klsRed.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: _klsRed, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Пульс',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if ((_finishedHeartRateDeviceName ?? '').isNotEmpty)
                Flexible(
                  child: Text(
                    _finishedHeartRateDeviceName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 8.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _finishMetric(
                  'Средний пульс',
                  avg != null ? '$avg уд/мин' : '—',
                  Icons.favorite_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _finishMetric(
                  'Макс. пульс',
                  maxBpm != null ? '$maxBpm уд/мин' : '—',
                  Icons.favorite_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _finishHeroCard(
    double distanceKm,
    int duration,
    double pace,
    double speed,
  ) {
    final avgPaceText = '${_formatPaceFromSeconds(pace)} /км';
    final avgSpeedText = '${speed.toStringAsFixed(1).replaceAll('.', ',')} км/ч';
    final maxSpeedText =
        '${(_maxSpeedMps * 3.6).toStringAsFixed(1).replaceAll('.', ',')} км/ч';

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: _finishMetric(
              'Время',
              _formatDuration(duration),
              Icons.schedule_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _finishMetric(
              'Дистанция',
              '${distanceKm.toStringAsFixed(2).replaceAll('.', ',')} км',
              Icons.route_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];

    if (_isSkiLike) {
      children.addAll([
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Средняя скорость',
                avgSpeedText,
                Icons.bolt_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Средний темп',
                avgPaceText,
                Icons.speed_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Макс. скорость',
                maxSpeedText,
                Icons.flash_on_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Набор высоты',
                '${_elevationGainMeters.round()} м',
                Icons.terrain_rounded,
              ),
            ),
          ],
        ),
        if (_pauseSeconds > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _finishMetric(
                  'Пауза',
                  _formatDuration(_pauseSeconds),
                  Icons.pause_circle_outline_rounded,
                ),
              ),
            ],
          ),
        ],
      ]);
    } else if (_isRun) {
      children.addAll([
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Средний темп',
                avgPaceText,
                Icons.speed_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Набор высоты',
                '${_elevationGainMeters.round()} м',
                Icons.terrain_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Макс. скорость',
                maxSpeedText,
                Icons.flash_on_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Пауза',
                _formatDuration(_pauseSeconds),
                Icons.pause_circle_outline_rounded,
              ),
            ),
          ],
        ),
      ]);
    } else {
      children.addAll([
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Средняя скорость',
                avgSpeedText,
                Icons.speed_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Набор высоты',
                '${_elevationGainMeters.round()} м',
                Icons.terrain_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _finishMetric(
                'Макс. скорость',
                maxSpeedText,
                Icons.flash_on_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _finishMetric(
                'Пауза',
                _formatDuration(_pauseSeconds),
                Icons.pause_circle_outline_rounded,
              ),
            ),
          ],
        ),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _surfaceDecoration(radius: 22),
      child: Column(children: children),
    );
  }

  Widget _finishMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF081B33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: _klsGold, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _mutedTextStyle(8.5)),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetSlider(
    String title,
    double value,
    double min,
    double max,
    int divisions,
    String label,
    ValueChanged<double> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 5),
      decoration: _surfaceDecoration(radius: 17),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: _klsGold,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _klsGold,
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              thumbColor: const Color(0xFFFFE3A7),
              overlayColor: _klsGold.withOpacity(0.10),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _KlsRouteMap extends StatelessWidget {
  const _KlsRouteMap({
    required this.controller,
    required this.segments,
    required this.currentPoint,
    required this.accuracyMeters,
    required this.headingDegrees,
    required this.fitWholeRoute,
    required this.showFinishMarker,
    this.onReady,
    this.onUserGesture,
  });

  final MapController controller;
  final List<List<_TrackPoint>> segments;
  final _TrackPoint? currentPoint;
  final double accuracyMeters;
  final double headingDegrees;
  final bool fitWholeRoute;
  final bool showFinishMarker;
  final VoidCallback? onReady;
  final VoidCallback? onUserGesture;

  List<_TrackPoint> get _all =>
      segments.expand((segment) => segment).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final hasMapPosition = currentPoint != null || all.isNotEmpty;

    if (!hasMapPosition) return const ColoredBox(color: _klsNavy);

    final initial = currentPoint?.latLng ?? all.last.latLng;
    final coordinates = all.map((point) => point.latLng).toList();

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initial,
        initialZoom: 16.5,
        initialCameraFit: fitWholeRoute && coordinates.length >= 2
            ? CameraFit.coordinates(
                coordinates: coordinates,
                padding: const EdgeInsets.all(42),
                maxZoom: 17.5,
              )
            : null,
        minZoom: 3,
        maxZoom: 19,
        backgroundColor: _klsNavy,
        keepAlive: true,
        onMapReady: onReady,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) onUserGesture?.call();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kls.app',
        ),
        if (currentPoint != null && accuracyMeters > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: currentPoint!.latLng,
                radius: accuracyMeters.clamp(3, 50).toDouble(),
                useRadiusInMeter: true,
                color: _klsIce.withOpacity(0.14),
                borderColor: _klsIce.withOpacity(0.42),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            for (final segment in segments)
              if (segment.length >= 2)
                Polyline(
                  points: segment.map((point) => point.latLng).toList(),
                  strokeWidth: 5,
                  color: _klsGold,
                  borderStrokeWidth: 3,
                  borderColor: _klsNavy.withOpacity(0.72),
                ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (all.isNotEmpty)
              Marker(
                point: all.first.latLng,
                width: 34,
                height: 34,
                child: _mapMarker(
                  Icons.flag_rounded,
                  _klsGold,
                  const Color(0xFF08111F),
                ),
              ),
            if (showFinishMarker && all.length >= 2)
              Marker(
                point: all.last.latLng,
                width: 34,
                height: 34,
                child: _mapMarker(
                  Icons.sports_score_rounded,
                  Colors.white,
                  const Color(0xFF08111F),
                ),
              ),
            if (!showFinishMarker && currentPoint != null)
              Marker(
                point: currentPoint!.latLng,
                width: 42,
                height: 42,
                child: Transform.rotate(
                  angle: headingDegrees * pi / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F8FFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.32),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  static Widget _mapMarker(
    IconData icon,
    Color background,
    Color foreground,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(icon, color: foreground, size: 18),
    );
  }
}

class _KlsStaticRouteMap extends StatefulWidget {
  const _KlsStaticRouteMap({
    required this.segments,
    required this.showFinishMarker,
    required this.currentPoint,
    required this.accuracyMeters,
    required this.headingDegrees,
  });

  final List<List<_TrackPoint>> segments;
  final bool showFinishMarker;
  final _TrackPoint? currentPoint;
  final double accuracyMeters;
  final double headingDegrees;

  @override
  State<_KlsStaticRouteMap> createState() => _KlsStaticRouteMapState();
}

class _KlsStaticRouteMapState extends State<_KlsStaticRouteMap> {
  final MapController _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _KlsRouteMap(
      controller: _controller,
      segments: widget.segments,
      currentPoint: widget.currentPoint,
      accuracyMeters: widget.accuracyMeters,
      headingDegrees: widget.headingDegrees,
      fitWholeRoute: true,
      showFinishMarker: widget.showFinishMarker,
    );
  }
}

class _KlsFullMapPage extends StatelessWidget {
  const _KlsFullMapPage({
    required this.segments,
    required this.currentPoint,
    required this.accuracyMeters,
    required this.headingDegrees,
  });

  final List<List<_TrackPoint>> segments;
  final _TrackPoint? currentPoint;
  final double accuracyMeters;
  final double headingDegrees;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _klsNavy,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _KlsStaticRouteMap(
                segments: segments,
                showFinishMarker: false,
                currentPoint: currentPoint,
                accuracyMeters: accuracyMeters,
                headingDegrees: headingDegrees,
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _klsNavy.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 72,
              top: 16,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _klsNavy.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: const Text(
                  'Маршрут тренировки',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
