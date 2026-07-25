import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kls_gps_tracker/kls_gps_tracker.dart';

void main() {
  runApp(const KlsGpsExampleApp());
}

class KlsGpsExampleApp extends StatelessWidget {
  const KlsGpsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE9C18A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF08111F),
      ),
      home: const GpsDiagnosticsPage(),
    );
  }
}

class GpsDiagnosticsPage extends StatefulWidget {
  const GpsDiagnosticsPage({super.key});

  @override
  State<GpsDiagnosticsPage> createState() => _GpsDiagnosticsPageState();
}

class _GpsDiagnosticsPageState extends State<GpsDiagnosticsPage> {
  final KlsGpsTracker _tracker = KlsGpsTracker();
  StreamSubscription<KlsGpsPoint>? _subscription;
  KlsGpsReadiness? _readiness;
  KlsGpsPoint? _lastPoint;
  String? _error;
  int _pointCount = 0;
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshReadiness());
  }

  Future<void> _refreshReadiness() async {
    try {
      final readiness = await _tracker.checkReadiness();
      if (!mounted) return;
      setState(() {
        _readiness = readiness;
        _error = null;
      });
    } on PlatformException catch (error) {
      _showError(error);
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _tracker.requestPermission();
      await _refreshReadiness();
    } on PlatformException catch (error) {
      _showError(error);
    }
  }

  Future<void> _start() async {
    try {
      final readiness = await _tracker.checkReadiness();
      if (!readiness.canStart) {
        setState(() => _readiness = readiness);
        return;
      }
      await _subscription?.cancel();
      _subscription = _tracker.positionStream.listen(
        (point) {
          if (!mounted) return;
          setState(() {
            _lastPoint = point;
            _pointCount += 1;
            _error = null;
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() => _error = error.toString());
        },
      );
      await _tracker.start();
      if (!mounted) return;
      setState(() {
        _isTracking = true;
        _error = null;
      });
    } on PlatformException catch (error) {
      _showError(error);
    }
  }

  Future<void> _stop() async {
    await _tracker.stop();
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() => _isTracking = false);
  }

  void _showError(PlatformException error) {
    if (!mounted) return;
    setState(() => _error = '${error.code}: ${error.message ?? 'Ошибка GPS'}');
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_tracker.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    final point = _lastPoint;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KLS · Диагностика GPS'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusCard(
            label: 'Геолокация',
            value: readiness == null
                ? 'Проверяем…'
                : _serviceLabel(readiness.serviceStatus),
          ),
          const SizedBox(height: 12),
          _StatusCard(
            label: 'Разрешение',
            value: readiness == null
                ? 'Проверяем…'
                : _permissionLabel(readiness.permission),
          ),
          const SizedBox(height: 12),
          _StatusCard(label: 'Получено точек', value: '$_pointCount'),
          const SizedBox(height: 24),
          if (_error != null)
            Card(
              color: const Color(0xFF4A1720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          if (point != null) ...[
            Text(
              'Последняя точка',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _MetricRow('Широта', point.latitude.toStringAsFixed(6)),
            _MetricRow('Долгота', point.longitude.toStringAsFixed(6)),
            _MetricRow(
              'Точность',
              '${point.accuracyMeters.toStringAsFixed(1)} м',
            ),
            _MetricRow(
              'Скорость',
              point.speedMetersPerSecond == null
                  ? '—'
                  : '${point.speedMetersPerSecond!.toStringAsFixed(2)} м/с',
            ),
            _MetricRow('Время', point.timestamp.toLocal().toIso8601String()),
            const SizedBox(height: 24),
          ],
          if (readiness?.permission != KlsLocationPermission.precise &&
              readiness?.permission != KlsLocationPermission.approximate)
            FilledButton(
              onPressed: _requestPermission,
              child: const Text('Разрешить геолокацию'),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isTracking ? _stop : _start,
            child: Text(_isTracking ? 'Остановить тест' : 'Начать тест GPS'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _refreshReadiness,
            child: const Text('Обновить состояние'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE9C18A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

String _serviceLabel(KlsLocationServiceStatus status) {
  return status == KlsLocationServiceStatus.enabled ? 'Включена' : 'Выключена';
}

String _permissionLabel(KlsLocationPermission permission) {
  return switch (permission) {
    KlsLocationPermission.notDetermined => 'Не запрошено',
    KlsLocationPermission.denied => 'Отклонено',
    KlsLocationPermission.deniedForever => 'Запрещено',
    KlsLocationPermission.approximate => 'Приблизительное',
    KlsLocationPermission.precise => 'Точное',
  };
}
