package com.kls.kls_gps_tracker

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.CopyOnWriteArraySet

internal object KlsGpsEventBus {
    private val listeners = CopyOnWriteArraySet<(Map<String, Any>) -> Unit>()

    fun add(listener: (Map<String, Any>) -> Unit) {
        listeners.add(listener)
    }

    fun remove(listener: (Map<String, Any>) -> Unit) {
        listeners.remove(listener)
    }

    fun emit(point: Map<String, Any>) {
        listeners.forEach { listener -> listener(point) }
    }
}

class KlsGpsTrackingService : Service(), LocationListener {
    private lateinit var locationManager: LocationManager
    private lateinit var storage: KlsGpsStorage
    private var workoutId: String? = null
    private var stopRequested = false
    private var finishWorkoutOnStop = true

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        storage = KlsGpsStorage(applicationContext)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopRequested = true
            finishWorkoutOnStop = intent.getBooleanExtra(EXTRA_FINISH_WORKOUT, true)
            stopRecording()
            return START_NOT_STICKY
        }

        val requestedId = intent?.getStringExtra(EXTRA_WORKOUT_ID) ?: storage.activeWorkoutId()
        if (requestedId == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        workoutId = try {
            storage.beginWorkout(requestedId)
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground(workoutId!!)

        if (!hasLocationPermission()) {
            storage.setTracking(false)
            stopSelf()
            return START_NOT_STICKY
        }

        return try {
            startLocationUpdates()
            storage.setTracking(true)
            START_STICKY
        } catch (_: Exception) {
            storage.setTracking(false)
            stopSelf()
            START_NOT_STICKY
        }
    }

    private fun startLocationUpdates() {
        locationManager.removeUpdates(this)

        val hasFine =
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val useGps = hasFine && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)

        if (useGps) {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                UPDATE_INTERVAL_MILLIS,
                MIN_DISTANCE_METERS,
                this,
            )
            return
        }

        if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            locationManager.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                UPDATE_INTERVAL_MILLIS,
                MIN_DISTANCE_METERS,
                this,
            )
            return
        }

        throw IllegalStateException("No location provider is enabled.")
    }

    override fun onLocationChanged(location: Location) {
        val currentWorkoutId = workoutId ?: return
        val point = runCatching {
            storage.appendLocation(currentWorkoutId, location)
        }.getOrNull() ?: return
        KlsGpsEventBus.emit(point)
    }

    private fun stopRecording() {
        runCatching { locationManager.removeUpdates(this) }
        if (finishWorkoutOnStop) {
            storage.finishWorkout(workoutId)
        } else {
            storage.pauseWorkout()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        runCatching { locationManager.removeUpdates(this) }
        storage.setTracking(false)
        if (!stopRequested) {
            // Keep the active workout id so Android or the next app launch can
            // resume the same durable session instead of creating a new one.
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Deprecated("Deprecated in Android")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) = Unit

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun startAsForeground(workoutId: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification =
            NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle("КЛС записывает тренировку")
                .setContentText("GPS работает в фоне · ${workoutId.take(8)}")
                .setContentIntent(contentIntent)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

        val foregroundType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            }
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            foregroundType,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Запись GPS-тренировки",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Показывает, что КЛС продолжает записывать маршрут в фоне."
            setSound(null, null)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.kls.kls_gps_tracker.action.START"
        const val ACTION_STOP = "com.kls.kls_gps_tracker.action.STOP"
        const val EXTRA_WORKOUT_ID = "workout_id"
        const val EXTRA_FINISH_WORKOUT = "finish_workout"
        private const val NOTIFICATION_CHANNEL_ID = "kls_gps_tracking"
        private const val NOTIFICATION_ID = 8417
        private const val UPDATE_INTERVAL_MILLIS = 1000L
        private const val MIN_DISTANCE_METERS = 1f
    }
}
