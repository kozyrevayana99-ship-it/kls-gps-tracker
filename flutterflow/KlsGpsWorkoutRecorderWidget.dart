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

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:kls_gps_tracker/kls_gps_tracker.dart';
import 'package:latlong2/latlong.dart' as ll;

bool _klsUseLightTheme = false;

Color _klsThemeColor(int darkValue, int lightValue) =>
    Color(_klsUseLightTheme ? lightValue : darkValue);

const _klsGold = Color(0xFFD6A85A);
const _klsIce = Color(0xFF9ED8FF);
const _klsNavy = Color(0xFF061326);
const _klsMapCenter = ll.LatLng(57.7679, 40.9269);

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
    required this.usesGps,
    required this.maxSpeedMps,
  });

  final String key;
  final String title;
  final IconData icon;
  final String diaryType;
  final bool usesGps;
  final double maxSpeedMps;
}

class _TrackPoint {
  const _TrackPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  ll.LatLng get latLng => ll.LatLng(lat, lng);
}

class _KlsGpsWorkoutRecorderWidgetState
    extends State<KlsGpsWorkoutRecorderWidget> {
  final List<_SportOption> _sports = const [
    _SportOption(
      key: 'ski',
      title: 'Лыжи',
      icon: Icons.downhill_skiing_rounded,
      diaryType: 'Лыжи',
      usesGps: true,
      maxSpeedMps: 35,
    ),
    _SportOption(
      key: 'run',
      title: 'Бег',
      icon: Icons.directions_run_rounded,
      diaryType: 'Бег',
      usesGps: true,
      maxSpeedMps: 12,
    ),
    _SportOption(
      key: 'rollerski',
      title: 'Роллеры',
      icon: Icons.directions_run_rounded,
      diaryType: 'Лыжероллеры',
      usesGps: true,
      maxSpeedMps: 20,
    ),
    _SportOption(
      key: 'bike',
      title: 'Вело',
      icon: Icons.directions_bike_rounded,
      diaryType: 'Велосипед',
      usesGps: true,
      maxSpeedMps: 30,
    ),
    _SportOption(
      key: 'strength',
      title: 'Силовая',
      icon: Icons.fitness_center_rounded,
      diaryType: 'Силовая',
      usesGps: false,
      maxSpeedMps: 1,
    ),
    _SportOption(
      key: 'ofp',
      title: 'ОФП',
      icon: Icons.sports_gymnastics_rounded,
      diaryType: 'ОФП',
      usesGps: false,
      maxSpeedMps: 1,
    ),
    _SportOption(
      key: 'sfp',
      title: 'СФП',
      icon: Icons.bolt_rounded,
      diaryType: 'СФП',
      usesGps: false,
      maxSpeedMps: 1,
    ),
  ];

  final KlsGpsTracker _gpsTracker = KlsGpsTracker();
  final MapController _mapController = MapController();
  final TextEditingController _commentController = TextEditingController();

  StreamSubscription<KlsGpsPoint>? _positionSub;
  Timer? _timer;
  KlsGpsFilter? _gpsFilter;

  String? _workoutId;
  String _sportType = 'rollerski';
  bool _isIntervalWorkout = false;

  bool _isStarting = false;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isFinishing = false;
  bool _isSavingDiary = false;
  bool _gpsLocked = false;
  bool _mapReady = false;
  bool _followUser = true;

  bool _isSendingPoints = false;
  bool _sendRequestedWhileBusy = false;

  String? _errorText;
  DateTime? _startedAt;
  DateTime? _pausedAt;

  int _elapsedSeconds = 0;
  int _pauseSeconds = 0;
  int _pointIndex = 0;
  int _rejectedPointCount = 0;

  double _distanceMeters = 0;
  double _currentSpeedMps = 0;
  double _maxSpeedMps = 0;
  double _accuracy = 0;
  double _heading = 0;

  KlsGpsPoint? _currentPosition;
  final List<Map<String, dynamic>> _pendingPoints = [];
  final List<List<_TrackPoint>> _routeSegments = [];

  int _wellbeing = 4;
  int _rpe = 5;
  int _fatigue = 2;
  double _sleepHours = 8;

  _SportOption get _selectedSport =>
      _sports.firstWhere((s) => s.key == _sportType, orElse: () => _sports[2]);

  List<_TrackPoint> get _allRoutePoints =>
      _routeSegments.expand((segment) => segment).toList(growable: false);

  List<_TrackPoint> get _activeSegment {
    if (_routeSegments.isEmpty) _routeSegments.add(<_TrackPoint>[]);
    return _routeSegments.last;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    unawaited(_gpsTracker.stop());
    _mapController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _resetLocalWorkout() {
    _workoutId = null;
    _startedAt = null;
    _pausedAt = null;
    _elapsedSeconds = 0;
    _pauseSeconds = 0;
    _pointIndex = 0;
    _rejectedPointCount = 0;
    _distanceMeters = 0;
    _currentSpeedMps = 0;
    _maxSpeedMps = 0;
    _accuracy = 0;
    _heading = 0;
    _currentPosition = null;
    _pendingPoints.clear();
    _routeSegments.clear();
    _isSendingPoints = false;
    _sendRequestedWhileBusy = false;
    _gpsLocked = !_selectedSport.usesGps;
    _followUser = true;
    _gpsFilter = _selectedSport.usesGps
        ? KlsGpsFilter(
            startupAccuracyMeters: 20,
            maxAccuracyMeters: 30,
            warmupPointCount: 3,
            minimumMovementMeters: 2.5,
            stationarySpeedMetersPerSecond: 0.8,
            maxSpeedMetersPerSecond: _selectedSport.maxSpeedMps,
          )
        : null;
  }

  Future<void> _startWorkout() async {
    if (_isStarting || _isTracking) return;

    setState(() {
      _isStarting = true;
      _errorText = null;
      _resetLocalWorkout();
    });

    try {
      final userId = widget.currentUserId?.trim() ?? '';
      final url = widget.startWorkoutUrl?.trim() ?? '';
      if (userId.isEmpty) throw Exception('Не передан currentUserId');
      if (url.isEmpty) throw Exception('Не передан startWorkoutUrl');

      if (_selectedSport.usesGps && !await _checkLocationPermission()) {
        throw Exception('Нет доступа к точной геолокации');
      }

      final title = _isIntervalWorkout
          ? '${_selectedSport.diaryType}: интервальная тренировка'
          : _selectedSport.diaryType;

      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'sport_type': _sportType,
          'title': title,
        }),
      );
      final decoded = _decodeFunctionBody(res.body);
      if (res.statusCode != 200 || decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Ошибка старта тренировки');
      }

      final workoutId = decoded['workout_id']?.toString() ?? '';
      if (workoutId.isEmpty) throw Exception('Backend не вернул workout_id');

      _workoutId = workoutId;
      _startedAt = DateTime.now();

      if (mounted) {
        setState(() {
          _isTracking = true;
          _isPaused = false;
        });
      }

      _startTimer();
      if (_selectedSport.usesGps) await _startGpsStream();
    } catch (error) {
      await _positionSub?.cancel();
      _positionSub = null;
      await _gpsTracker.stop();
      if (mounted) setState(() => _errorText = error.toString());
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<bool> _checkLocationPermission() async {
    var readiness = await _gpsTracker.checkReadiness();
    if (readiness.serviceStatus == KlsLocationServiceStatus.disabled) {
      return false;
    }
    if (!readiness.canStart) {
      await _gpsTracker.requestPermission();
      readiness = await _gpsTracker.checkReadiness();
    }
    return readiness.canStart;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isTracking || _isPaused || _startedAt == null || !mounted) return;
      setState(() {
        _elapsedSeconds =
            DateTime.now().difference(_startedAt!).inSeconds - _pauseSeconds;
        if (_elapsedSeconds < 0) _elapsedSeconds = 0;
      });
    });
  }

  Future<void> _startGpsStream() async {
    await _positionSub?.cancel();
    _positionSub = _gpsTracker.positionStream.listen(
      (point) {
        if (_isTracking && !_isPaused) _handlePosition(point);
      },
      onError: (Object error) {
        if (mounted) setState(() => _errorText = 'Ошибка GPS: $error');
      },
    );

    try {
      await _gpsTracker.start();
    } catch (_) {
      await _positionSub?.cancel();
      _positionSub = null;
      rethrow;
    }
  }

  void _handlePosition(KlsGpsPoint position) {
    final filter = _gpsFilter;
    if (filter == null) return;

    _accuracy = position.accuracyMeters.isFinite
        ? max(0, position.accuracyMeters)
        : 0;

    final result = filter.add(position);
    _gpsLocked = result.gpsLocked;

    if (result.decision == KlsGpsPointDecision.gapReset) {
      _currentPosition = position;
      _routeSegments.add(<_TrackPoint>[]);
      if (mounted) setState(() {});
      return;
    }

    if (!result.shouldRecord) {
      if (result.decision == KlsGpsPointDecision.stationary) {
        _currentSpeedMps = 0;
      }
      if (result.decision != KlsGpsPointDecision.warmingUp &&
          result.decision != KlsGpsPointDecision.stationary) {
        _rejectedPointCount++;
      }
      if (mounted) setState(() {});
      return;
    }

    _currentPosition = position;
    _distanceMeters += max(0, result.segmentMeters);
    _currentSpeedMps = max(0, result.currentSpeedMetersPerSecond);
    _maxSpeedMps = max(_maxSpeedMps, _currentSpeedMps);
    if (position.headingDegrees != null &&
        position.headingDegrees!.isFinite &&
        position.headingDegrees! >= 0) {
      _heading = position.headingDegrees!;
    }

    _activeSegment.add(_TrackPoint(position.latitude, position.longitude));
    _pendingPoints.add({
      'point_index': _pointIndex,
      'lat': position.latitude,
      'lng': position.longitude,
      'altitude': position.altitudeMeters ?? 0,
      'accuracy': position.accuracyMeters,
      'speed_mps': _currentSpeedMps,
      'heading': position.headingDegrees ?? 0,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
    });
    _pointIndex++;

    if (_pendingPoints.length >= 10) unawaited(_sendPendingPoints());
    _followCurrentPoint();
    if (mounted) setState(() {});
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
    });
  }

  Future<bool> _sendPendingPoints() async {
    if (_isSendingPoints) {
      _sendRequestedWhileBusy = true;
      return true;
    }

    _isSendingPoints = true;
    var success = true;
    try {
      do {
        _sendRequestedWhileBusy = false;
        if (_pendingPoints.isEmpty) break;

        final url = widget.saveWorkoutBatchUrl?.trim() ?? '';
        final userId = widget.currentUserId?.trim() ?? '';
        final workoutId = _workoutId ?? '';
        if (url.isEmpty) throw Exception('Не передан saveWorkoutBatchUrl');
        if (userId.isEmpty) throw Exception('Не передан currentUserId');
        if (workoutId.isEmpty) throw Exception('Нет workoutId');

        final points = List<Map<String, dynamic>>.from(_pendingPoints);
        _pendingPoints.clear();
        try {
          final res = await http.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'workout_id': workoutId,
              'user_id': userId,
              'points': points,
            }),
          );
          final decoded = _decodeFunctionBody(res.body);
          if (res.statusCode < 200 ||
              res.statusCode >= 300 ||
              decoded['success'] != true) {
            throw Exception(
              decoded['error'] ?? 'Не удалось сохранить GPS-точки',
            );
          }
        } catch (error) {
          _pendingPoints.insertAll(0, points);
          success = false;
          if (mounted) setState(() => _errorText = error.toString());
          break;
        }
      } while (_sendRequestedWhileBusy || _pendingPoints.length >= 10);
    } catch (error) {
      success = false;
      if (mounted) setState(() => _errorText = error.toString());
    } finally {
      _isSendingPoints = false;
    }
    return success;
  }

  Future<void> _flushAllPendingPoints() async {
    while (_isSendingPoints) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    var attempts = 0;
    while (_pendingPoints.isNotEmpty) {
      final sent = await _sendPendingPoints();
      while (_isSendingPoints) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (sent && _pendingPoints.isEmpty) return;
      attempts++;
      if (attempts >= 3) {
        throw Exception('Не удалось отправить последнюю пачку GPS-точек');
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * attempts));
    }
  }

  void _pauseWorkout() {
    if (!_isTracking || _isPaused) return;
    setState(() {
      _isPaused = true;
      _pausedAt = DateTime.now();
      _currentSpeedMps = 0;
      _gpsLocked = false;
    });
    _gpsFilter?.reset();
    unawaited(_gpsTracker.stop());
    unawaited(_sendPendingPoints());
  }

  void _resumeWorkout() {
    if (!_isTracking || !_isPaused) return;
    if (_pausedAt != null) {
      _pauseSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
    }
    _routeSegments.add(<_TrackPoint>[]);
    _gpsFilter?.reset();
    setState(() {
      _isPaused = false;
      _pausedAt = null;
      _currentSpeedMps = 0;
      _gpsLocked = !_selectedSport.usesGps;
    });
    if (_selectedSport.usesGps) {
      unawaited(
        _gpsTracker.start().catchError((Object error) {
          if (mounted) setState(() => _errorText = 'Ошибка GPS: $error');
        }),
      );
    }
  }

  bool _isWorkoutTooShort() {
    if (_elapsedSeconds < 30) return true;
    return _selectedSport.usesGps && _distanceMeters < 20;
  }

  Future<void> _cancelWorkout({bool goBack = false}) async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _gpsTracker.stop();
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
        backgroundColor: _klsThemeColor(0xFF061326, 0xFFEEF2F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Выйти из записи?',
          style: TextStyle(
            color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Текущая тренировка не будет сохранена в дневник.',
          style: TextStyle(
            color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.72),
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
            child: Text(
              'Выйти без сохранения',
              style: TextStyle(color: _klsThemeColor(0xFFFF6B5A, 0xFFD8514B)),
            ),
          ),
        ],
      ),
    );
    if (shouldExit == true) await _cancelWorkout(goBack: true);
  }

  Future<void> _finishWorkout() async {
    if (!_isTracking || _isFinishing) return;
    if (_isWorkoutTooShort()) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _klsThemeColor(0xFF061326, 0xFFEEF2F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            'Слишком короткая тренировка',
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            _selectedSport.usesGps
                ? 'Для сохранения нужно хотя бы 30 секунд и 20 метров корректного маршрута.'
                : 'Для сохранения нужно хотя бы 30 секунд записи.',
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.72),
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

    setState(() {
      _isFinishing = true;
      _errorText = null;
    });

    try {
      await _positionSub?.cancel();
      _positionSub = null;
      await _gpsTracker.stop();
      _timer?.cancel();

      if (_isPaused && _pausedAt != null) {
        _pauseSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
        _pausedAt = null;
      }
      await _flushAllPendingPoints();

      final url = widget.finishWorkoutUrl?.trim() ?? '';
      final userId = widget.currentUserId?.trim() ?? '';
      final workoutId = _workoutId ?? '';
      if (url.isEmpty) throw Exception('Не передан finishWorkoutUrl');
      if (userId.isEmpty) throw Exception('Не передан currentUserId');
      if (workoutId.isEmpty) throw Exception('Нет workoutId');

      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'workout_id': workoutId,
          'user_id': userId,
          'duration_seconds': _elapsedSeconds,
          'pause_seconds': _pauseSeconds,
        }),
      );
      final decoded = _decodeFunctionBody(res.body);
      if (res.statusCode < 200 ||
          res.statusCode >= 300 ||
          decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Ошибка завершения тренировки');
      }

      _applyServerRoute(decoded['route_points']);
      if (mounted) {
        setState(() {
          _isTracking = false;
          _isPaused = false;
          _distanceMeters = _asDouble(decoded['distance_meters']);
          _currentSpeedMps = 0;
          _maxSpeedMps = _asDouble(decoded['max_speed_mps']);
          _elapsedSeconds = _asInt(decoded['duration_seconds']);
        });
        _showFinishSheet(decoded);
      }
    } catch (error) {
      if (mounted) setState(() => _errorText = error.toString());
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  void _applyServerRoute(dynamic rawRoute) {
    if (rawRoute is! List || rawRoute.isEmpty) return;
    final rebuilt = <_TrackPoint>[];
    for (final item in rawRoute) {
      if (item is List && item.length >= 2) {
        final lat = _asDouble(item[0]);
        final lng = _asDouble(item[1]);
        if ((lat != 0 || lng != 0) && lat.isFinite && lng.isFinite) {
          rebuilt.add(_TrackPoint(lat, lng));
        }
      }
    }
    if (rebuilt.isNotEmpty) {
      _routeSegments
        ..clear()
        ..add(rebuilt);
    }
  }

  Future<void> _saveFinishedWorkoutToDiary(
    Map<String, dynamic> data,
  ) async {
    final url = widget.addTrainingUrl?.trim() ?? '';
    final userId = widget.currentUserId?.trim() ?? '';
    if (url.isEmpty) throw Exception('Не передан addTrainingUrl');
    if (userId.isEmpty) throw Exception('Не передан currentUserId');

    final durationSeconds = _asInt(data['duration_seconds']);
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final title = _isIntervalWorkout
        ? '${_selectedSport.diaryType}: интервальная тренировка'
        : _selectedSport.diaryType;

    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'training_id': _workoutId,
        'user_id': userId,
        'date': date,
        'title': title,
        'description': 'GPS-тренировка КЛС',
        'training_type': _selectedSport.diaryType,
        'duration_minutes': max(1, (durationSeconds / 60).round()),
        'distance_km': _asDouble(data['distance_km']),
        'avg_pulse': 0,
        'max_pulse': 0,
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
        'is_interval': _isIntervalWorkout,
      }),
    );
    final decoded = _decodeFunctionBody(res.body);
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(decoded['error'] ?? 'Не удалось сохранить в дневник');
    }
  }

  Map<String, dynamic> _decodeFunctionBody(String rawBody) {
    final data = jsonDecode(rawBody);
    if (data is Map && data['body'] != null) {
      final inner = data['body'];
      if (inner is String) {
        return Map<String, dynamic>.from(jsonDecode(inner) as Map);
      }
      if (inner is Map) return Map<String, dynamic>.from(inner);
    }
    return Map<String, dynamic>.from(data as Map);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(
          (value?.toString() ?? '').replaceAll(',', '.'),
        ) ??
        0;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatPaceFromSeconds(double secondsPerKm) {
    if (secondsPerKm <= 0 ||
        secondsPerKm.isNaN ||
        secondsPerKm.isInfinite) {
      return '—';
    }
    final total = secondsPerKm.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String _formatLivePace() {
    if (_distanceMeters < 100 || _elapsedSeconds <= 0) return '—';
    return _formatPaceFromSeconds(
      _elapsedSeconds / (_distanceMeters / 1000),
    );
  }

  String _formatAverageSpeedKmh() {
    if (_elapsedSeconds <= 0) return '0.0';
    final value = (_distanceMeters / _elapsedSeconds) * 3.6;
    return value.isFinite ? value.toStringAsFixed(1) : '0.0';
  }

  String _formatCurrentSpeedKmh() {
    final value = _currentSpeedMps * 3.6;
    return value.isFinite ? value.toStringAsFixed(1) : '0.0';
  }

  String _formatDistanceKm() {
    final km = _distanceMeters / 1000;
    return km < 1 ? km.toStringAsFixed(3) : km.toStringAsFixed(2);
  }

  String get _gpsStatus {
    if (!_selectedSport.usesGps) return 'Тренировка без GPS';
    if (!_isTracking) return 'GPS готов к подключению';
    if (_isPaused) return 'GPS на паузе';
    if (!_gpsLocked) return 'Стабилизируем GPS · не начинай движение';
    if (_accuracy > 25) return 'Слабый GPS · ±${_accuracy.round()} м';
    return 'GPS готов · ±${_accuracy.round()} м';
  }

  void _showSavedSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    _klsUseLightTheme = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _klsThemeColor(0xFF030B16, 0xFFEEF2F5),
            _klsThemeColor(0xFF061B34, 0xFFFFFFFF),
            _klsThemeColor(0xFF031326, 0xFFEEF2F5),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 12),
              _sportSelector(),
              const SizedBox(height: 10),
              _modeSelector(),
              const SizedBox(height: 12),
              _mainCard(),
              const SizedBox(height: 10),
              _statsGrid(),
              const SizedBox(height: 10),
              Expanded(
                child: _selectedSport.usesGps
                    ? _mapCard()
                    : _noGpsCard(),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                _errorBox(),
              ],
              const SizedBox(height: 12),
              _bottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: _handleBackPressed,
          child: _iconSurface(Icons.arrow_back_ios_new_rounded, size: 40),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Запись тренировки',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: _surfaceDecoration(radius: 999),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isTracking && !_isPaused
                      ? const Color(0xFF41E48A)
                      : _isPaused
                          ? _klsGold
                          : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                              .withOpacity(0.38),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                _isTracking ? (_isPaused ? 'Пауза' : 'Запись') : 'Готово',
                style: TextStyle(
                  color:
                      _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.86),
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sportSelector() {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _sports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sport = _sports[index];
          final selected = sport.key == _sportType;
          return GestureDetector(
            onTap: _isTracking
                ? null
                : () => setState(() => _sportType = sport.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected
                    ? _klsGold.withOpacity(0.13)
                    : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                        .withOpacity(0.055),
                border: Border.all(
                  color: selected
                      ? _klsGold
                      : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                          .withOpacity(0.08),
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    sport.icon,
                    color: selected
                        ? _klsGold
                        : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                            .withOpacity(0.45),
                    size: 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    sport.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      color: selected
                          ? _klsGold
                          : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                              .withOpacity(0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

  Widget _modeSelector() {
    return Row(
      children: [
        Expanded(child: _modePill('Обычная', !_isIntervalWorkout)),
        const SizedBox(width: 8),
        Expanded(child: _modePill('Интервальная', _isIntervalWorkout)),
      ],
    );
  }

  Widget _modePill(String title, bool selected) {
    return GestureDetector(
      onTap: _isTracking
          ? null
          : () => setState(() => _isIntervalWorkout = title == 'Интервальная'),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: selected
              ? _klsGold.withOpacity(0.15)
              : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.05),
          border: Border.all(
            color: selected
                ? _klsGold
                : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.08),
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Montserrat',
              color: selected
                  ? _klsGold
                  : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
          decoration: _surfaceDecoration(radius: 26),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _gpsLocked
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_not_fixed_rounded,
                    color: _gpsLocked ? const Color(0xFF41E48A) : _klsGold,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _gpsStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                            .withOpacity(0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_isTracking)
                    GestureDetector(
                      onTap: _isPaused ? _resumeWorkout : _pauseWorkout,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _klsGold),
                        ),
                        child: Icon(
                          _isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: _klsGold,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                _formatDuration(_elapsedSeconds),
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              Text(
                'Время тренировки',
                style: _mutedTextStyle(13),
              ),
              const SizedBox(height: 10),
              Text(
                '${_formatDistanceKm()} км',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  color: _klsGold,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text('Дистанция', style: _mutedTextStyle(13)),
              const SizedBox(height: 5),
              Text(
                'Средняя скорость ${_formatAverageSpeedKmh()} км/ч',
                style: TextStyle(
                  color:
                      _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.48),
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsGrid() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            Icons.timer_outlined,
            'Темп',
            _formatLivePace(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile(
            Icons.speed_rounded,
            'Сейчас',
            '${_formatCurrentSpeedKmh()} км/ч',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile(
            Icons.favorite_border_rounded,
            'Пульс',
            '—',
          ),
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, String label, String value) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(11),
      decoration: _surfaceDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _klsGold, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mutedTextStyle(10),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontFamily: 'Montserrat',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _klsThemeColor(0xFF07182D, 0xFFFFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.09),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
                headingDegrees: _heading,
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
              left: 12,
              top: 12,
              child: _mapChip(
                _gpsLocked ? 'Маршрут' : 'Ищем точный GPS',
                _gpsLocked ? Icons.route_rounded : Icons.gps_not_fixed_rounded,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Column(
                children: [
                  _mapAction(
                    icon: Icons.fullscreen_rounded,
                    onTap: _openFullMap,
                  ),
                  const SizedBox(height: 8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _klsThemeColor(0xDD061326, 0xDDFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _isTracking
                        ? 'Не двигайся несколько секунд\nGPS определяет точную позицию'
                        : 'Нажми «Начать тренировку»',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                          .withOpacity(0.78),
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noGpsCard() {
    return Container(
      width: double.infinity,
      decoration: _surfaceDecoration(radius: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fitness_center_rounded, color: _klsGold, size: 38),
          const SizedBox(height: 10),
          Text(
            'Для этой тренировки GPS не нужен',
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
          headingDegrees: _heading,
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D4D).withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        _errorText!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 11),
      ),
    );
  }

  Widget _bottomControls() {
    if (!_isTracking) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isStarting ? null : _startWorkout,
          style: ElevatedButton.styleFrom(
            backgroundColor: _klsGold,
            foregroundColor: const Color(0xFF08111F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            _isStarting ? 'Подключаем GPS...' : 'Начать тренировку',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: _isFinishing
                  ? null
                  : (_isPaused ? _resumeWorkout : _pauseWorkout),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color:
                      _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.18),
                ),
                foregroundColor: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _isPaused ? 'Продолжить' : 'Пауза',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isFinishing ? null : _finishWorkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A3D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _isFinishing ? 'Сохраняем...' : 'Финиш',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _surfaceDecoration({required double radius}) {
    return BoxDecoration(
      color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.06),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.1),
      ),
    );
  }

  TextStyle _mutedTextStyle(double size) {
    return TextStyle(
      color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A).withOpacity(0.52),
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: FontWeight.w700,
    );
  }

  Widget _iconSurface(IconData icon, {double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: _surfaceDecoration(radius: 15),
      child: Icon(
        icon,
        color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
        size: 18,
      ),
    );
  }

  Widget _mapChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _klsThemeColor(0xDD061326, 0xDDFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _klsGold, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active
              ? _klsGold
              : _klsThemeColor(0xDD061326, 0xDDFFFFFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(
          icon,
          color: active
              ? const Color(0xFF08111F)
              : _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
          size: 20,
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
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final distanceKm = _asDouble(data['distance_km']);
            final duration = _asInt(data['duration_seconds']);
            final pace = _asDouble(data['avg_pace_seconds_per_km']);
            final speed = _asDouble(data['avg_speed_kmh']);

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: _klsThemeColor(0xFF061326, 0xFFEEF2F5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(sheetContext),
                            child: _iconSurface(Icons.close_rounded, size: 38),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Тренировка завершена',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                color:
                                    _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _finishHeroCard(distanceKm, duration, pace, speed),
                      if (_selectedSport.usesGps) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 180,
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
                      ],
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _sheetSlider(
                                'Самочувствие',
                                _wellbeing.toDouble(),
                                1,
                                5,
                                4,
                                '$_wellbeing / 5',
                                (v) => setSheetState(
                                  () => _wellbeing = v.round(),
                                ),
                              ),
                              _sheetSlider(
                                'RPE / сложность',
                                _rpe.toDouble(),
                                1,
                                10,
                                9,
                                '$_rpe / 10',
                                (v) => setSheetState(() => _rpe = v.round()),
                              ),
                              _sheetSlider(
                                'Усталость',
                                _fatigue.toDouble(),
                                1,
                                5,
                                4,
                                '$_fatigue / 5',
                                (v) => setSheetState(
                                  () => _fatigue = v.round(),
                                ),
                              ),
                              _sheetSlider(
                                'Сон',
                                _sleepHours,
                                0,
                                12,
                                24,
                                '${_sleepHours.toStringAsFixed(1)} ч',
                                (v) => setSheetState(
                                  () => _sleepHours =
                                      double.parse(v.toStringAsFixed(1)),
                                ),
                              ),
                              TextField(
                                controller: _commentController,
                                maxLines: 3,
                                style: TextStyle(
                                  color:
                                      _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Комментарий к тренировке',
                                  filled: true,
                                  fillColor:
                                      _klsThemeColor(0xFFFFFFFF, 0xFF172A3A)
                                          .withOpacity(0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                onPressed: _isSavingDiary
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                child: const Text('Позже'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isSavingDiary
                                    ? null
                                    : () async {
                                        setState(() => _isSavingDiary = true);
                                        setSheetState(() {});
                                        try {
                                          await _saveFinishedWorkoutToDiary(
                                            data,
                                          );
                                          if (mounted) {
                                            Navigator.pop(sheetContext);
                                            _showSavedSnack(
                                              'Тренировка добавлена в дневник',
                                            );
                                            await Future<void>.delayed(
                                              const Duration(milliseconds: 250),
                                            );
                                            if (mounted) {
                                              Navigator.of(this.context)
                                                  .pop(true);
                                            }
                                          }
                                        } catch (error) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  error.toString(),
                                                ),
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
                                ),
                                child: Text(
                                  _isSavingDiary
                                      ? 'Сохраняем...'
                                      : 'Сохранить в дневник',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _finishHeroCard(
    double distanceKm,
    int duration,
    double pace,
    double speed,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _surfaceDecoration(radius: 24),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, color: _klsGold, size: 34),
          const SizedBox(height: 5),
          const Text(
            'Отличная работа!',
            style: TextStyle(
              fontFamily: 'Montserrat',
              color: _klsGold,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _finishMetric('Время', _formatDuration(duration)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _finishMetric(
                  'Дистанция',
                  '${distanceKm.toStringAsFixed(2)} км',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _finishMetric(
                  'Средняя',
                  '${speed.toStringAsFixed(1)} км/ч',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _finishMetric(
                  'Темп',
                  _formatPaceFromSeconds(pace),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _finishMetric(
                  'Максимальная',
                  '${(_maxSpeedMps * 3.6).toStringAsFixed(1)} км/ч',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _finishMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _klsThemeColor(0xFF081B33, 0xFFDCE7EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _mutedTextStyle(9)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFamily: 'Montserrat',
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
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: _surfaceDecoration(radius: 18),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _klsThemeColor(0xFFFFFFFF, 0xFF172A3A),
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: _klsGold,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _klsGold,
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              thumbColor: const Color(0xFFFFE3A7),
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
    final initial = currentPoint?.latLng ??
        (all.isNotEmpty ? all.last.latLng : _klsMapCenter);
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
          tileBuilder: _klsUseLightTheme ? null : darkModeTileBuilder,
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
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: _klsGold, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.32),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Color(0xFF08111F),
                      size: 23,
                    ),
                  ),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: const [
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
          BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 8),
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
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                  ),
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
