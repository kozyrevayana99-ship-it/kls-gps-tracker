import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../kls_gps_tracker_platform_interface.dart';
import 'gps_models.dart';

/// Network endpoints used after a workout has already been saved locally.
class KlsWorkoutEndpoints {
  const KlsWorkoutEndpoints({
    required this.startWorkoutUrl,
    required this.saveWorkoutBatchUrl,
    required this.finishWorkoutUrl,
    required this.addTrainingUrl,
  });

  final String startWorkoutUrl;
  final String saveWorkoutBatchUrl;
  final String finishWorkoutUrl;
  final String addTrainingUrl;

  void validate({required bool usesGps}) {
    final requiredUrls = <String, String>{
      'startWorkoutUrl': startWorkoutUrl,
      'finishWorkoutUrl': finishWorkoutUrl,
      'addTrainingUrl': addTrainingUrl,
      if (usesGps) 'saveWorkoutBatchUrl': saveWorkoutBatchUrl,
    };
    for (final entry in requiredUrls.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError('${entry.key} is required');
      }
      final uri = Uri.tryParse(entry.value.trim());
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw ArgumentError('${entry.key} is not a valid URL');
      }
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startWorkoutUrl': startWorkoutUrl,
    'saveWorkoutBatchUrl': saveWorkoutBatchUrl,
    'finishWorkoutUrl': finishWorkoutUrl,
    'addTrainingUrl': addTrainingUrl,
  };

  factory KlsWorkoutEndpoints.fromJson(Map<String, dynamic> json) {
    return KlsWorkoutEndpoints(
      startWorkoutUrl: json['startWorkoutUrl']?.toString() ?? '',
      saveWorkoutBatchUrl: json['saveWorkoutBatchUrl']?.toString() ?? '',
      finishWorkoutUrl: json['finishWorkoutUrl']?.toString() ?? '',
      addTrainingUrl: json['addTrainingUrl']?.toString() ?? '',
    );
  }
}

/// Durable metadata for one local-first workout.
class KlsOfflineWorkout {
  const KlsOfflineWorkout({
    required this.workoutId,
    required this.userId,
    required this.sportType,
    required this.title,
    required this.diaryType,
    required this.usesGps,
    required this.isInterval,
    required this.startedAtUtc,
    required this.localDate,
    required this.endpoints,
    required this.status,
    required this.pauseSeconds,
    required this.isPaused,
    required this.lastUploadedPointIndex,
    required this.serverCreated,
    required this.serverFinished,
    required this.feedback,
    this.pausedAtUtc,
    this.finishedAtUtc,
    this.durationSeconds = 0,
    this.serverResult,
    this.lastError,
  });

  static const recordingStatus = 'recording';
  static const pendingSyncStatus = 'pending_sync';
  static const syncingStatus = 'syncing';
  static const failedStatus = 'failed';

  final String workoutId;
  final String userId;
  final String sportType;
  final String title;
  final String diaryType;
  final bool usesGps;
  final bool isInterval;
  final DateTime startedAtUtc;
  final String localDate;
  final KlsWorkoutEndpoints endpoints;
  final String status;
  final DateTime? pausedAtUtc;
  final DateTime? finishedAtUtc;
  final int durationSeconds;
  final int pauseSeconds;
  final bool isPaused;
  final int lastUploadedPointIndex;
  final bool serverCreated;
  final bool serverFinished;
  final Map<String, dynamic> feedback;
  final Map<String, dynamic>? serverResult;
  final String? lastError;

  bool get isRecording => status == recordingStatus;
  bool get isPendingSync =>
      status == pendingSyncStatus ||
      status == syncingStatus ||
      status == failedStatus;

  int activeElapsedSeconds([DateTime? nowUtc]) {
    final end =
        finishedAtUtc ??
        (isPaused ? pausedAtUtc : null) ??
        nowUtc ??
        DateTime.now().toUtc();
    return max(0, end.difference(startedAtUtc).inSeconds - pauseSeconds);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'workoutId': workoutId,
    'userId': userId,
    'sportType': sportType,
    'title': title,
    'diaryType': diaryType,
    'usesGps': usesGps,
    'isInterval': isInterval,
    'startedAtUtc': startedAtUtc.toIso8601String(),
    'localDate': localDate,
    'endpoints': endpoints.toJson(),
    'status': status,
    'pausedAtUtc': pausedAtUtc?.toIso8601String(),
    'finishedAtUtc': finishedAtUtc?.toIso8601String(),
    'durationSeconds': durationSeconds,
    'pauseSeconds': pauseSeconds,
    'isPaused': isPaused,
    'lastUploadedPointIndex': lastUploadedPointIndex,
    'serverCreated': serverCreated,
    'serverFinished': serverFinished,
    'feedback': feedback,
    'serverResult': serverResult,
    'lastError': lastError,
  };

  factory KlsOfflineWorkout.fromJson(Map<String, dynamic> json) {
    DateTime requiredDate(String key) {
      final value = DateTime.tryParse(json[key]?.toString() ?? '');
      if (value == null) throw FormatException('Invalid $key');
      return value.toUtc();
    }

    DateTime? optionalDate(String key) {
      final raw = json[key]?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    int asInt(dynamic value, [int fallback = 0]) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return KlsOfflineWorkout(
      workoutId: json['workoutId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      sportType: json['sportType']?.toString() ?? 'other',
      title: json['title']?.toString() ?? 'Тренировка',
      diaryType: json['diaryType']?.toString() ?? 'Другое',
      usesGps: json['usesGps'] == true,
      isInterval: json['isInterval'] == true,
      startedAtUtc: requiredDate('startedAtUtc'),
      localDate: json['localDate']?.toString() ?? '',
      endpoints: KlsWorkoutEndpoints.fromJson(
        Map<String, dynamic>.from(json['endpoints'] as Map? ?? const {}),
      ),
      status: json['status']?.toString() ?? recordingStatus,
      pausedAtUtc: optionalDate('pausedAtUtc'),
      finishedAtUtc: optionalDate('finishedAtUtc'),
      durationSeconds: asInt(json['durationSeconds']),
      pauseSeconds: asInt(json['pauseSeconds']),
      isPaused: json['isPaused'] == true,
      lastUploadedPointIndex: asInt(json['lastUploadedPointIndex'], -1),
      serverCreated: json['serverCreated'] == true,
      serverFinished: json['serverFinished'] == true,
      feedback: Map<String, dynamic>.from(json['feedback'] as Map? ?? const {}),
      serverResult: json['serverResult'] is Map
          ? Map<String, dynamic>.from(json['serverResult'] as Map)
          : null,
      lastError: json['lastError']?.toString(),
    );
  }
}

class KlsWorkoutSyncResult {
  const KlsWorkoutSyncResult({
    required this.workoutId,
    required this.synced,
    this.serverResult,
    this.error,
  });

  final String workoutId;
  final bool synced;
  final Map<String, dynamic>? serverResult;
  final String? error;
}

/// Stores workout metadata separately from the native RAW GPS journal.
class KlsOfflineWorkoutStore {
  static const _indexKey = 'kls_offline_workout_ids_v1';
  static const _recordPrefix = 'kls_offline_workout_v1_';
  static Future<void> _tail = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> put(KlsOfflineWorkout workout) {
    return _exclusive(() async {
      final preferences = await SharedPreferences.getInstance();
      final ids = preferences.getStringList(_indexKey) ?? <String>[];
      if (!ids.contains(workout.workoutId)) {
        ids.add(workout.workoutId);
        await preferences.setStringList(_indexKey, ids);
      }
      await preferences.setString(
        '$_recordPrefix${workout.workoutId}',
        jsonEncode(workout.toJson()),
      );
    });
  }

  Future<KlsOfflineWorkout?> get(String workoutId) {
    return _exclusive(() async {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('$_recordPrefix$workoutId');
      if (raw == null || raw.isEmpty) return null;
      try {
        return KlsOfflineWorkout.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        return null;
      }
    });
  }

  Future<List<KlsOfflineWorkout>> list() {
    return _exclusive(() async {
      final preferences = await SharedPreferences.getInstance();
      final ids = preferences.getStringList(_indexKey) ?? const <String>[];
      final result = <KlsOfflineWorkout>[];
      for (final id in ids) {
        final raw = preferences.getString('$_recordPrefix$id');
        if (raw == null || raw.isEmpty) continue;
        try {
          result.add(
            KlsOfflineWorkout.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            ),
          );
        } catch (_) {
          // A damaged metadata row must not block every other workout.
        }
      }
      return result;
    });
  }

  Future<KlsOfflineWorkout?> patch(
    String workoutId,
    Map<String, dynamic> values,
  ) {
    return _exclusive(() async {
      final preferences = await SharedPreferences.getInstance();
      final key = '$_recordPrefix$workoutId';
      final raw = preferences.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map)
        ..addAll(values);
      final updated = KlsOfflineWorkout.fromJson(json);
      await preferences.setString(key, jsonEncode(updated.toJson()));
      return updated;
    });
  }

  Future<void> remove(String workoutId) {
    return _exclusive(() async {
      final preferences = await SharedPreferences.getInstance();
      final ids = preferences.getStringList(_indexKey) ?? <String>[];
      ids.remove(workoutId);
      await preferences.setStringList(_indexKey, ids);
      await preferences.remove('$_recordPrefix$workoutId');
    });
  }
}

/// Creates local workouts and synchronizes the durable outbox with Yandex.
class KlsOfflineWorkoutManager {
  KlsOfflineWorkoutManager({
    KlsGpsTrackerPlatform? gpsPlatform,
    http.Client? httpClient,
    KlsOfflineWorkoutStore? store,
  }) : _gpsPlatform = gpsPlatform ?? KlsGpsTrackerPlatform.instance,
       _httpClient = httpClient ?? http.Client(),
       _store = store ?? KlsOfflineWorkoutStore();

  final KlsGpsTrackerPlatform _gpsPlatform;
  final http.Client _httpClient;
  final KlsOfflineWorkoutStore _store;
  static final Set<String> _syncingIds = <String>{};

  Future<KlsOfflineWorkout> createWorkout({
    required String userId,
    required String sportType,
    required String title,
    required String diaryType,
    required bool usesGps,
    required bool isInterval,
    required KlsWorkoutEndpoints endpoints,
    DateTime? startedAt,
  }) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) throw ArgumentError('userId is required');
    endpoints.validate(usesGps: usesGps);
    final localStart = startedAt ?? DateTime.now();
    final workout = KlsOfflineWorkout(
      workoutId: _newUuid(),
      userId: cleanUserId,
      sportType: sportType.trim().isEmpty ? 'other' : sportType.trim(),
      title: title.trim().isEmpty ? 'Тренировка' : title.trim(),
      diaryType: diaryType.trim().isEmpty ? 'Другое' : diaryType.trim(),
      usesGps: usesGps,
      isInterval: isInterval,
      startedAtUtc: localStart.toUtc(),
      localDate: _localDate(localStart),
      endpoints: endpoints,
      status: KlsOfflineWorkout.recordingStatus,
      pauseSeconds: 0,
      isPaused: false,
      lastUploadedPointIndex: -1,
      serverCreated: false,
      serverFinished: false,
      feedback: _defaultFeedback,
    );
    await _store.put(workout);
    return workout;
  }

  Future<KlsOfflineWorkout?> getWorkout(String workoutId) =>
      _store.get(workoutId);

  Future<List<KlsOfflineWorkout>> listRecordingWorkouts() async =>
      (await _store.list()).where((item) => item.isRecording).toList();

  Future<List<KlsOfflineWorkout>> listPendingWorkouts() async =>
      (await _store.list()).where((item) => item.isPendingSync).toList();

  Future<void> pauseWorkout(String workoutId, DateTime pausedAt) async {
    await _store.patch(workoutId, <String, dynamic>{
      'isPaused': true,
      'pausedAtUtc': pausedAt.toUtc().toIso8601String(),
    });
  }

  Future<int> resumeWorkout(String workoutId, DateTime resumedAt) async {
    final workout = await _store.get(workoutId);
    if (workout == null) throw StateError('Local workout not found');
    final extraPause = workout.pausedAtUtc == null
        ? 0
        : max(0, resumedAt.toUtc().difference(workout.pausedAtUtc!).inSeconds);
    final pauseSeconds = workout.pauseSeconds + extraPause;
    await _store.patch(workoutId, <String, dynamic>{
      'isPaused': false,
      'pausedAtUtc': null,
      'pauseSeconds': pauseSeconds,
    });
    return pauseSeconds;
  }

  Future<KlsOfflineWorkout> finishWorkout({
    required String workoutId,
    required int durationSeconds,
    required int pauseSeconds,
    DateTime? finishedAt,
  }) async {
    final updated = await _store.patch(workoutId, <String, dynamic>{
      'status': KlsOfflineWorkout.pendingSyncStatus,
      'finishedAtUtc': (finishedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'durationSeconds': max(0, durationSeconds),
      'pauseSeconds': max(0, pauseSeconds),
      'isPaused': false,
      'pausedAtUtc': null,
      'lastError': null,
    });
    if (updated == null) throw StateError('Local workout not found');
    return updated;
  }

  Future<void> updateFeedback({
    required String workoutId,
    required int wellbeing,
    required int rpe,
    required int fatigue,
    required double sleepHours,
    required String comment,
  }) async {
    final workout = await _store.get(workoutId);
    if (workout == null) throw StateError('Local workout not found');
    final feedback = Map<String, dynamic>.from(workout.feedback)
      ..addAll(<String, dynamic>{
        'wellbeing': wellbeing.clamp(0, 5),
        'rpe': rpe.clamp(0, 10),
        'fatigue': fatigue.clamp(0, 5),
        'sleep_hours': sleepHours.clamp(0, 24),
        'comment': comment.trim(),
      });
    await _store.patch(workoutId, <String, dynamic>{'feedback': feedback});
  }

  Future<void> cancelWorkout(String workoutId) async {
    try {
      await _gpsPlatform.deleteStoredWorkout(workoutId);
    } catch (_) {
      // A non-GPS workout has no native journal; metadata still needs removal.
    }
    await _store.remove(workoutId);
  }

  Future<KlsWorkoutSyncResult> syncWorkout(String workoutId) async {
    if (!_syncingIds.add(workoutId)) {
      return KlsWorkoutSyncResult(
        workoutId: workoutId,
        synced: false,
        error: 'sync_already_running',
      );
    }

    try {
      final loadedWorkout = await _store.get(workoutId);
      if (loadedWorkout == null) {
        return KlsWorkoutSyncResult(workoutId: workoutId, synced: true);
      }
      var workout = loadedWorkout;
      if (!workout.isPendingSync) {
        return KlsWorkoutSyncResult(
          workoutId: workoutId,
          synced: false,
          error: 'workout_is_still_recording',
        );
      }

      await _store.patch(workoutId, <String, dynamic>{
        'status': KlsOfflineWorkout.syncingStatus,
        'lastError': null,
      });

      if (!workout.serverCreated) {
        final startResult = await _postJson(
          workout.endpoints.startWorkoutUrl,
          <String, dynamic>{
            'workout_id': workout.workoutId,
            'user_id': workout.userId,
            'sport_type': workout.sportType,
            'title': workout.title,
            'started_at': workout.startedAtUtc.toIso8601String(),
          },
        );
        final returnedId = startResult['workout_id']?.toString() ?? '';
        if (returnedId != workout.workoutId) {
          throw StateError('Backend returned a different workout_id');
        }
        workout = (await _store.patch(workoutId, <String, dynamic>{
          'serverCreated': true,
        }))!;
      }

      if (workout.usesGps) {
        var after = workout.lastUploadedPointIndex;
        while (true) {
          final points = await _gpsPlatform.getStoredPoints(
            workoutId: workout.workoutId,
            afterPointIndex: after,
            limit: 500,
          );
          if (points.isEmpty) break;
          final payload = points.map(_pointToJson).toList(growable: false);
          await _postJson(
            workout.endpoints.saveWorkoutBatchUrl,
            <String, dynamic>{
              'workout_id': workout.workoutId,
              'user_id': workout.userId,
              'points': payload,
            },
          );
          final indices = points
              .map((point) => point.pointIndex ?? -1)
              .where((index) => index >= 0);
          if (indices.isEmpty) {
            throw StateError('Native GPS points have no point_index');
          }
          after = indices.reduce(max);
          workout = (await _store.patch(workoutId, <String, dynamic>{
            'lastUploadedPointIndex': after,
          }))!;
          if (points.length < 500) break;
        }
      }

      Map<String, dynamic> finishResult =
          workout.serverResult ?? const <String, dynamic>{};
      if (!workout.serverFinished) {
        finishResult = await _postJson(
          workout.endpoints.finishWorkoutUrl,
          <String, dynamic>{
            'workout_id': workout.workoutId,
            'user_id': workout.userId,
            'started_at': workout.startedAtUtc.toIso8601String(),
            'finished_at': workout.finishedAtUtc?.toIso8601String(),
            'duration_seconds': workout.durationSeconds,
            'pause_seconds': workout.pauseSeconds,
          },
        );
        workout = (await _store.patch(workoutId, <String, dynamic>{
          'serverFinished': true,
          'serverResult': finishResult,
        }))!;
      }

      await _postJson(
        workout.endpoints.addTrainingUrl,
        _diaryPayload(workout, finishResult),
      );

      if (workout.usesGps) {
        await _gpsPlatform.deleteStoredWorkout(workout.workoutId);
      }
      await _store.remove(workout.workoutId);
      return KlsWorkoutSyncResult(
        workoutId: workout.workoutId,
        synced: true,
        serverResult: finishResult,
      );
    } catch (error) {
      final message = error.toString();
      await _store.patch(workoutId, <String, dynamic>{
        'status': KlsOfflineWorkout.failedStatus,
        'lastError': message,
      });
      return KlsWorkoutSyncResult(
        workoutId: workoutId,
        synced: false,
        error: message,
      );
    } finally {
      _syncingIds.remove(workoutId);
    }
  }

  Future<int> syncPendingWorkouts() async {
    final pending = await listPendingWorkouts();
    var synced = 0;
    for (final workout in pending) {
      final result = await syncWorkout(workout.workoutId);
      if (result.synced) synced++;
    }
    return synced;
  }

  Future<Map<String, dynamic>> _postJson(
    String rawUrl,
    Map<String, dynamic> body,
  ) async {
    final response = await _httpClient
        .post(
          Uri.parse(rawUrl.trim()),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = _decodeFunctionBody(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw StateError(
        decoded['error']?.toString() ??
            'HTTP ${response.statusCode}: synchronization failed',
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decodeFunctionBody(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) throw const FormatException('Invalid server JSON');
    final outer = Map<String, dynamic>.from(decoded);
    final inner = outer['body'];
    if (inner is String) {
      return Map<String, dynamic>.from(jsonDecode(inner) as Map);
    }
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return outer;
  }

  Map<String, dynamic> _pointToJson(KlsGpsPoint point) => <String, dynamic>{
    'point_index': point.pointIndex,
    'lat': point.latitude,
    'lng': point.longitude,
    'altitude': point.altitudeMeters ?? 0,
    'accuracy': max(0, point.accuracyMeters),
    'speed_mps': max(0, point.speedMetersPerSecond ?? 0),
    'heading': max(0, point.headingDegrees ?? 0),
    'timestamp': point.timestamp.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _diaryPayload(
    KlsOfflineWorkout workout,
    Map<String, dynamic> finishResult,
  ) {
    final feedback = workout.feedback;
    final duration = _asInt(
      finishResult['duration_seconds'],
      workout.durationSeconds,
    );
    return <String, dynamic>{
      'training_id': workout.workoutId,
      'user_id': workout.userId,
      'date': workout.localDate,
      'local_date': workout.localDate,
      'title': workout.title,
      'description': 'GPS-тренировка КЛС',
      'training_type': workout.diaryType,
      'duration_minutes': max(1, (duration / 60).round()),
      'distance_km': _asDouble(finishResult['distance_km']),
      'avg_pulse': 0,
      'max_pulse': 0,
      'wellbeing': _asInt(feedback['wellbeing'], 4),
      'comment': feedback['comment']?.toString() ?? '',
      'rpe': _asInt(feedback['rpe'], 5),
      'sleep_hours': _asDouble(feedback['sleep_hours'], 8),
      'fatigue': _asInt(feedback['fatigue'], 2),
      'stress': _asInt(feedback['stress'], 2),
      'muscle_pain': _asInt(feedback['muscle_pain'], 2),
      'motivation': _asInt(feedback['motivation'], 4),
      'source': 'kls_gps',
      'gps_workout_id': workout.workoutId,
      'started_at_utc': workout.startedAtUtc.toIso8601String(),
      'finished_at_utc': workout.finishedAtUtc?.toIso8601String(),
      'is_interval': workout.isInterval,
    };
  }

  static const Map<String, dynamic> _defaultFeedback = <String, dynamic>{
    'wellbeing': 4,
    'rpe': 5,
    'fatigue': 2,
    'sleep_hours': 8.0,
    'comment': '',
    'stress': 2,
    'muscle_pain': 2,
    'motivation': 4,
  };

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _asDouble(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _localDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final text = hex.join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }
}
