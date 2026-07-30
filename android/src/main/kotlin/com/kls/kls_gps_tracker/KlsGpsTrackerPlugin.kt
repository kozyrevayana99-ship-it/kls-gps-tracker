package com.kls.kls_gps_tracker

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
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
    PluginRegistry.RequestPermissionsResultListener,
    LocationListener {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var locationManager: LocationManager
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var hasRequestedPermission = false
    private var isTracking = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        locationManager =
            applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, POSITION_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "checkReadiness" -> result.success(readiness())
            "start" -> startTracking(result)
            "stop" -> {
                stopTracking()
                result.success(null)
            }
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

    private fun startTracking(result: MethodChannel.Result) {
        if (!isLocationServiceEnabled()) {
            result.error("location_service_disabled", "Location services are disabled.", null)
            return
        }
        if (!hasLocationPermission()) {
            result.error("permission_denied", "Location permission has not been granted.", null)
            return
        }
        if (isTracking) {
            result.success(null)
            return
        }

        try {
            val useGps =
                permissionStatus() == "precise" &&
                    locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)

            if (useGps) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    UPDATE_INTERVAL_MILLIS,
                    MIN_DISTANCE_METERS,
                    this,
                )
            }

            // Do not mix GPS and cell/network fixes during a precise workout:
            // alternating providers is a common source of large false jumps.
            if (!useGps && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    UPDATE_INTERVAL_MILLIS,
                    MIN_DISTANCE_METERS,
                    this,
                )
            }
            isTracking = true
            result.success(null)
        } catch (error: SecurityException) {
            result.error("permission_denied", error.message, null)
        }
    }

    private fun stopTracking() {
        if (!isTracking) return
        locationManager.removeUpdates(this)
        isTracking = false
    }

    private fun readiness(): Map<String, Any> =
        mapOf(
            "permission" to permissionStatus(),
            "serviceEnabled" to isLocationServiceEnabled(),
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

    override fun onLocationChanged(location: Location) {
        if (location.accuracy <= 0f || location.accuracy > 100f) return

        val point =
            mutableMapOf<String, Any>(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "altitude" to location.altitude,
                "timestampMillis" to location.time,
            )
        if (location.hasSpeed()) point["speed"] = location.speed.toDouble()
        if (location.hasBearing()) point["heading"] = location.bearing.toDouble()
        eventSink?.success(point)
    }

    @Deprecated("Deprecated in Android")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) = Unit

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
        stopTracking()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    private companion object {
        const val METHOD_CHANNEL = "kls_gps_tracker"
        const val POSITION_CHANNEL = "kls_gps_tracker/positions"
        const val LOCATION_PERMISSION_REQUEST = 8417
        const val UPDATE_INTERVAL_MILLIS = 1000L
        const val MIN_DISTANCE_METERS = 1f
    }
}
