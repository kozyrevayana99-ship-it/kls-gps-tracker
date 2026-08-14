package com.kls.kls_gps_tracker

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class KlsGpsTrackerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var locationManager: LocationManager
    private lateinit var storage: KlsGpsStorage
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var hasRequestedPermission = false

    private val gpsListener: (Map<String, Any>) -> Unit = { point ->
        eventSink?.success(point)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        locationManager =
            applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        storage = KlsGpsStorage(applicationContext)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, POSITION_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        KlsGpsEventBus.add(gpsListener)

        resumeActiveWorkoutIfPossible()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "checkReadiness" -> result.success(readiness())
            "start" -> startTracking(call, result)
            "stop" -> stopTracking(call, result)
            "getTrackingState" -> result.success(trackingState())
            "getStoredPoints" -> getStoredPoints(call, result)
            "listStoredWorkoutIds" -> result.success(storage.listStoredWorkoutIds())
            "deleteStoredWorkout" -> deleteStoredWorkout(call, result)
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val current = permissionStatus()
        if (current == "precise" || current == "approximate") {
            result.success(current)
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            result.error(
                "activity_unavailable",
                "Location permission can only be requested while the app is visible.",
                null,
            )
            return
        }
        if (permissionResult != null) {
            result.error("permission_request_in_progress", "A permission request is already active.", null)
            return
        }

        hasRequestedPermission = true
        permissionResult = result
        ActivityCompat.requestPermissions(
            currentActivity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            LOCATION_PERMISSION_REQUEST,
        )
    }

    private fun startTracking(call: MethodCall, result: MethodChannel.Result) {
        if (!isLocationServiceEnabled()) {
            result.error("location_service_disabled", "Location services are disabled.", null)
            return
        }
        if (!hasLocationPermission()) {
            result.error("permission_denied", "Location permission has not been granted.", null)
            return
        }

        val requestedWorkoutId = call.argument<String>("workoutId")
        val workoutId = try {
            storage.beginWorkout(requestedWorkoutId)
        } catch (error: Exception) {
            result.error("workout_already_active", error.message, null)
            return
        }

        val intent = Intent(applicationContext, KlsGpsTrackingService::class.java).apply {
            action = KlsGpsTrackingService.ACTION_START
            putExtra(KlsGpsTrackingService.EXTRA_WORKOUT_ID, workoutId)
        }
        try {
            ContextCompat.startForegroundService(applicationContext, intent)
            result.success(workoutId)
        } catch (error: Exception) {
            storage.setTracking(false)
            result.error("foreground_service_start_failed", error.message, null)
        }
    }

    private fun stopTracking(call: MethodCall, result: MethodChannel.Result) {
        val finishWorkout = call.argument<Boolean>("finishWorkout") ?: true
        if (finishWorkout) {
            storage.finishWorkout(storage.activeWorkoutId())
        } else {
            storage.pauseWorkout()
        }
        val intent = Intent(applicationContext, KlsGpsTrackingService::class.java).apply {
            action = KlsGpsTrackingService.ACTION_STOP
            putExtra(KlsGpsTrackingService.EXTRA_FINISH_WORKOUT, finishWorkout)
        }
        applicationContext.startService(intent)
        result.success(null)
    }

    private fun resumeActiveWorkoutIfPossible() {
        val workoutId = storage.activeWorkoutId() ?: return
        if (!storage.shouldAutoResume()) return
        if (!hasLocationPermission() || !isLocationServiceEnabled()) return
        val intent = Intent(applicationContext, KlsGpsTrackingService::class.java).apply {
            action = KlsGpsTrackingService.ACTION_START
            putExtra(KlsGpsTrackingService.EXTRA_WORKOUT_ID, workoutId)
        }
        runCatching { ContextCompat.startForegroundService(applicationContext, intent) }
    }

    private fun getStoredPoints(call: MethodCall, result: MethodChannel.Result) {
        val workoutId = call.argument<String>("workoutId")?.trim().orEmpty()
        if (workoutId.isEmpty()) {
            result.error("invalid_workout_id", "workoutId is required.", null)
            return
        }
        val afterPointIndex = call.argument<Number>("afterPointIndex")?.toInt() ?: -1
        val limit = (call.argument<Number>("limit")?.toInt() ?: 1000).coerceIn(1, 5000)
        try {
            result.success(storage.readPoints(workoutId, afterPointIndex, limit))
        } catch (error: Exception) {
            result.error("storage_error", error.message, null)
        }
    }

    private fun deleteStoredWorkout(call: MethodCall, result: MethodChannel.Result) {
        val workoutId = call.argument<String>("workoutId")?.trim().orEmpty()
        if (workoutId.isEmpty()) {
            result.error("invalid_workout_id", "workoutId is required.", null)
            return
        }
        try {
            storage.deleteWorkout(workoutId)
            result.success(null)
        } catch (error: Exception) {
            result.error("storage_error", error.message, null)
        }
    }

    private fun trackingState(): Map<String, Any?> {
        val workoutId = storage.activeWorkoutId()
        return mapOf(
            "isTracking" to storage.isTracking(),
            "workoutId" to workoutId,
            "pointCount" to if (workoutId == null) 0 else storage.pointCount(workoutId),
            "backgroundCapable" to true,
        )
    }

    private fun readiness(): Map<String, Any> =
        mapOf(
            "permission" to permissionStatus(),
            "serviceEnabled" to isLocationServiceEnabled(),
            "backgroundCapable" to true,
        )

    private fun permissionStatus(): String {
        if (
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return "precise"
        }
        if (
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return "approximate"
        }

        val currentActivity = activity
        val deniedForever =
            hasRequestedPermission &&
                currentActivity != null &&
                !ActivityCompat.shouldShowRequestPermissionRationale(
                    currentActivity,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                )
        return if (deniedForever) "deniedForever" else if (hasRequestedPermission) "denied" else "notDetermined"
    }

    private fun hasLocationPermission(): Boolean =
        permissionStatus() == "precise" || permissionStatus() == "approximate"

    private fun isLocationServiceEnabled(): Boolean =
        locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != LOCATION_PERMISSION_REQUEST) return false
        permissionResult?.success(permissionStatus())
        permissionResult = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        resumeActiveWorkoutIfPossible()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        KlsGpsEventBus.remove(gpsListener)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        // Deliberately do not stop KlsGpsTrackingService here. The workout must
        // continue when the Flutter Activity or engine is detached.
    }

    private companion object {
        const val METHOD_CHANNEL = "kls_gps_tracker"
        const val POSITION_CHANNEL = "kls_gps_tracker/positions"
        const val LOCATION_PERMISSION_REQUEST = 8417
    }
}
