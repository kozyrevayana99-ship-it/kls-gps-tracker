package com.kls.kls_gps_tracker

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.util.concurrent.CopyOnWriteArraySet


internal object KlsGpsEventBus {
    private val listeners =
        CopyOnWriteArraySet<(Map<String, Any>) -> Unit>()

    fun add(
        listener: (Map<String, Any>) -> Unit,
    ) {
        listeners.add(listener)
    }

    fun remove(
        listener: (Map<String, Any>) -> Unit,
    ) {
        listeners.remove(listener)
    }

    fun emit(
        point: Map<String, Any>,
    ) {
        listeners.forEach { listener ->
            listener(point)
        }
    }
}


class KlsGpsTrackingService : Service() {

    private lateinit var fusedLocationClient:
        FusedLocationProviderClient

    private lateinit var storage:
        KlsGpsStorage

    private var workoutId: String? = null

    private var stopRequested = false

    private var finishWorkoutOnStop = true


    // =========================================================================
    // LOCATION CALLBACK
    // =========================================================================

    private val locationCallback =
        object : LocationCallback() {

            override fun onLocationResult(
                locationResult: LocationResult,
            ) {
                super.onLocationResult(
                    locationResult,
                )

                /*
                 * Fused Location Provider иногда может
                 * вернуть несколько накопленных точек.
                 *
                 * Не берём только последнюю:
                 * сохраняем каждую точку в RAW journal.
                 *
                 * Дальше Flutter / KlsGpsFilter уже решает,
                 * какая точка является доверенной.
                 */
                for (location in locationResult.locations) {
                    handleLocation(
                        location,
                    )
                }
            }
        }


    // =========================================================================
    // SERVICE LIFECYCLE
    // =========================================================================

    override fun onCreate() {
        super.onCreate()

        fusedLocationClient =
            LocationServices.getFusedLocationProviderClient(
                this,
            )

        storage =
            KlsGpsStorage(
                applicationContext,
            )

        createNotificationChannel()
    }


    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {

        if (intent?.action == ACTION_STOP) {
            stopRequested = true

            finishWorkoutOnStop =
                intent.getBooleanExtra(
                    EXTRA_FINISH_WORKOUT,
                    true,
                )

            stopRecording()

            return START_NOT_STICKY
        }


        val requestedId =
            intent?.getStringExtra(
                EXTRA_WORKOUT_ID,
            )
                ?: storage.activeWorkoutId()


        if (requestedId == null) {
            stopSelf()

            return START_NOT_STICKY
        }


        workoutId =
            try {
                storage.beginWorkout(
                    requestedId,
                )
            } catch (_: Exception) {
                stopSelf()

                return START_NOT_STICKY
            }


        startAsForeground(
            workoutId!!,
        )


        if (!hasLocationPermission()) {
            storage.setTracking(
                false,
            )

            stopSelf()

            return START_NOT_STICKY
        }


        return try {

            startLocationUpdates()

            storage.setTracking(
                true,
            )

            START_STICKY

        } catch (_: Exception) {

            storage.setTracking(
                false,
            )

            stopSelf()

            START_NOT_STICKY
        }
    }


    // =========================================================================
    // LOCATION
    // =========================================================================

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {

        /*
         * На всякий случай снимаем предыдущую подписку,
         * чтобы при повторном старте сервиса
         * не получить два параллельных GPS-потока.
         */
        runCatching {
            fusedLocationClient.removeLocationUpdates(
                locationCallback,
            )
        }


        if (!hasLocationPermission()) {
            throw SecurityException(
                "Location permission is not granted.",
            )
        }


        /*
         * ВАЖНО:
         *
         * Больше НЕ используем напрямую:
         *
         * LocationManager.GPS_PROVIDER
         *
         * Android сам получает максимально подходящие
         * координаты через Fused Location Provider:
         *
         * - GNSS / GPS;
         * - Wi-Fi;
         * - мобильную сеть;
         * - другие системные источники.
         *
         * PRIORITY_HIGH_ACCURACY означает, что
         * во время тренировки мы всё равно просим
         * максимально точную геолокацию.
         *
         * setWaitForAccurateLocation(false):
         *
         * не заставляем экран тренировки ждать
         * идеальный спутниковый lock.
         *
         * Сначала может прийти менее точная точка,
         * затем координаты улучшатся.
         *
         * Flutter-виджет и KlsGpsFilter уже умеют
         * отбрасывать плохую точность.
         */
        val locationRequest =
            LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                UPDATE_INTERVAL_MILLIS,
            )
                .setMinUpdateIntervalMillis(
                    MIN_UPDATE_INTERVAL_MILLIS,
                )
                .setMinUpdateDistanceMeters(
                    MIN_DISTANCE_METERS,
                )
                .setWaitForAccurateLocation(
                    false,
                )
                .build()


        fusedLocationClient.requestLocationUpdates(
            locationRequest,
            locationCallback,
            Looper.getMainLooper(),
        )
    }


    private fun handleLocation(
        location: Location,
    ) {
        val currentWorkoutId =
            workoutId ?: return


        /*
         * RAW точка сохраняется нативно.
         *
         * Здесь специально НЕ делаем фильтрацию:
         *
         * - accuracy;
         * - скорость;
         * - скачки координат;
         * - stationary drift.
         *
         * Это ответственность KlsGpsFilter.
         *
         * Поэтому RAW journal остаётся полным,
         * что важно для восстановления после
         * блокировки экрана.
         */
        val point =
            runCatching {
                storage.appendLocation(
                    currentWorkoutId,
                    location,
                )
            }.getOrNull()
                ?: return


        /*
         * Если Flutter сейчас активен,
         * сразу отдаём точку в приложение.
         *
         * Если Flutter приостановлен,
         * RAW journal всё равно сохраняется
         * и будет восстановлен после resume.
         */
        KlsGpsEventBus.emit(
            point,
        )
    }


    // =========================================================================
    // STOP
    // =========================================================================

    private fun stopRecording() {

        runCatching {
            fusedLocationClient.removeLocationUpdates(
                locationCallback,
            )
        }


        if (finishWorkoutOnStop) {
            storage.finishWorkout(
                workoutId,
            )
        } else {
            storage.pauseWorkout()
        }


        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.N
        ) {
            stopForeground(
                STOP_FOREGROUND_REMOVE,
            )
        } else {
            @Suppress("DEPRECATION")
            stopForeground(
                true,
            )
        }


        stopSelf()
    }


    override fun onDestroy() {

        runCatching {
            fusedLocationClient.removeLocationUpdates(
                locationCallback,
            )
        }


        storage.setTracking(
            false,
        )


        if (!stopRequested) {
            /*
             * Намеренно НЕ удаляем activeWorkoutId.
             *
             * Если Android уничтожил сервис,
             * приложение сможет восстановить
             * ту же durable GPS-сессию,
             * а не создать новую тренировку.
             */
        }


        super.onDestroy()
    }


    override fun onBind(
        intent: Intent?,
    ): IBinder? = null


    // =========================================================================
    // PERMISSIONS
    // =========================================================================

    private fun hasLocationPermission(): Boolean {

        val fineGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED


        val coarseGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED


        return fineGranted || coarseGranted
    }


    // =========================================================================
    // FOREGROUND SERVICE
    // =========================================================================

    private fun startAsForeground(
        workoutId: String,
    ) {

        val launchIntent =
            packageManager.getLaunchIntentForPackage(
                packageName,
            )


        val contentIntent =
            launchIntent?.let {

                PendingIntent.getActivity(
                    this,
                    0,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE,
                )
            }


        val notification =
            NotificationCompat.Builder(
                this,
                NOTIFICATION_CHANNEL_ID,
            )
                .setSmallIcon(
                    android.R.drawable.ic_menu_mylocation,
                )
                .setContentTitle(
                    "КЛС записывает тренировку",
                )
                .setContentText(
                    "GPS работает в фоне · ${workoutId.take(8)}",
                )
                .setContentIntent(
                    contentIntent,
                )
                .setOnlyAlertOnce(
                    true,
                )
                .setOngoing(
                    true,
                )
                .setCategory(
                    NotificationCompat.CATEGORY_SERVICE,
                )
                .setPriority(
                    NotificationCompat.PRIORITY_LOW,
                )
                .build()


        val foregroundType =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {
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


    // =========================================================================
    // NOTIFICATION CHANNEL
    // =========================================================================

    private fun createNotificationChannel() {

        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }


        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Запись GPS-тренировки",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {

                description =
                    "Показывает, что КЛС продолжает записывать маршрут в фоне."

                setSound(
                    null,
                    null,
                )
            }


        getSystemService(
            NotificationManager::class.java,
        ).createNotificationChannel(
            channel,
        )
    }


    // =========================================================================
    // CONSTANTS
    // =========================================================================

    companion object {

        const val ACTION_START =
            "com.kls.kls_gps_tracker.action.START"

        const val ACTION_STOP =
            "com.kls.kls_gps_tracker.action.STOP"

        const val EXTRA_WORKOUT_ID =
            "workout_id"

        const val EXTRA_FINISH_WORKOUT =
            "finish_workout"


        private const val NOTIFICATION_CHANNEL_ID =
            "kls_gps_tracking"

        private const val NOTIFICATION_ID =
            8417


        /*
         * Хотим получать нормальный live GPS
         * примерно раз в секунду.
         */
        private const val UPDATE_INTERVAL_MILLIS =
            1000L


        /*
         * Android может дать новую точку немного раньше,
         * если она уже доступна.
         */
        private const val MIN_UPDATE_INTERVAL_MILLIS =
            500L


        /*
         * Не заставляем Android ждать,
         * пока пользователь сместится далеко.
         */
        private const val MIN_DISTANCE_METERS =
            1f
    }
}
