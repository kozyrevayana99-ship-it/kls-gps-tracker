package com.kls.kls_gps_tracker

import android.content.Context
import android.location.Location
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.util.UUID

internal class KlsGpsStorage(context: Context) {
    private val appContext = context.applicationContext
    private val preferences =
        appContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val storageDirectory = File(appContext.filesDir, STORAGE_DIRECTORY).apply { mkdirs() }

    @Synchronized
    fun beginWorkout(requestedWorkoutId: String?): String {
        val requested = requestedWorkoutId?.trim()?.takeIf { it.isNotEmpty() }
        if (requested != null) validateWorkoutId(requested)

        val active = activeWorkoutId()
        if (active != null && requested != null && active != requested) {
            throw IllegalStateException("Workout $active is already being recorded.")
        }

        val workoutId = active ?: requested ?: UUID.randomUUID().toString()
        preferences
            .edit()
            .putString(KEY_ACTIVE_WORKOUT_ID, workoutId)
            .putBoolean(KEY_SHOULD_AUTO_RESUME, true)
            .apply()
        ensureNextPointIndex(workoutId)
        return workoutId
    }

    fun activeWorkoutId(): String? =
        preferences.getString(KEY_ACTIVE_WORKOUT_ID, null)?.takeIf { it.isNotBlank() }

    fun isTracking(): Boolean = preferences.getBoolean(KEY_IS_TRACKING, false)

    fun setTracking(value: Boolean) {
        preferences.edit().putBoolean(KEY_IS_TRACKING, value).apply()
    }

    fun shouldAutoResume(): Boolean =
        preferences.getBoolean(KEY_SHOULD_AUTO_RESUME, false)

    fun pauseWorkout() {
        preferences
            .edit()
            .putBoolean(KEY_IS_TRACKING, false)
            .putBoolean(KEY_SHOULD_AUTO_RESUME, false)
            .apply()
    }

    @Synchronized
    fun finishWorkout(workoutId: String?) {
        val active = activeWorkoutId()
        val editor =
            preferences
                .edit()
                .putBoolean(KEY_IS_TRACKING, false)
                .putBoolean(KEY_SHOULD_AUTO_RESUME, false)
        if (workoutId == null || active == workoutId) {
            editor.remove(KEY_ACTIVE_WORKOUT_ID)
        }
        editor.apply()
    }

    @Synchronized
    fun appendLocation(workoutId: String, location: Location): Map<String, Any> {
        validateWorkoutId(workoutId)
        val pointIndex = ensureNextPointIndex(workoutId)
        val point = linkedMapOf<String, Any>(
            "workoutId" to workoutId,
            "pointIndex" to pointIndex,
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else -1.0,
            "timestampMillis" to location.time,
            "provider" to (location.provider ?: "unknown"),
            "isMock" to location.isFromMockProvider,
            "elapsedRealtimeNanos" to location.elapsedRealtimeNanos,
        )

        if (location.hasAltitude()) point["altitude"] = location.altitude
        if (location.hasSpeed()) point["speed"] = location.speed.toDouble()
        if (location.hasBearing()) point["heading"] = location.bearing.toDouble()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            if (location.hasVerticalAccuracy()) {
                point["verticalAccuracy"] = location.verticalAccuracyMeters.toDouble()
            }
            if (location.hasSpeedAccuracy()) {
                point["speedAccuracy"] = location.speedAccuracyMetersPerSecond.toDouble()
            }
            if (location.hasBearingAccuracy()) {
                point["headingAccuracy"] = location.bearingAccuracyDegrees.toDouble()
            }
        }

        val encoded = JSONObject(point as Map<*, *>).toString() + "\n"
        FileOutputStream(fileFor(workoutId), true).use { stream ->
            stream.write(encoded.toByteArray(StandardCharsets.UTF_8))
            stream.flush()
            stream.fd.sync()
        }

        preferences.edit().putInt(nextIndexKey(workoutId), pointIndex + 1).apply()
        return point
    }

    @Synchronized
    fun readPoints(
        workoutId: String,
        afterPointIndex: Int,
        limit: Int,
    ): List<Map<String, Any>> {
        validateWorkoutId(workoutId)
        val file = fileFor(workoutId)
        if (!file.exists()) return emptyList()

        val result = ArrayList<Map<String, Any>>(limit.coerceAtMost(5000))
        file.bufferedReader(StandardCharsets.UTF_8).useLines { lines ->
            for (line in lines) {
                if (line.isBlank()) continue
                val json = runCatching { JSONObject(line) }.getOrNull() ?: continue
                val pointIndex = json.optInt("pointIndex", -1)
                if (pointIndex <= afterPointIndex) continue

                val point = linkedMapOf<String, Any>()
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val value = json.opt(key)
                    if (value != null && value !== JSONObject.NULL) point[key] = value
                }
                result.add(point)
                if (result.size >= limit.coerceIn(1, 5000)) break
            }
        }
        return result
    }

    fun pointCount(workoutId: String): Int {
        validateWorkoutId(workoutId)
        return ensureNextPointIndex(workoutId)
    }

    fun listStoredWorkoutIds(): List<String> =
        storageDirectory
            .listFiles { file -> file.isFile && file.extension == FILE_EXTENSION }
            ?.map { it.nameWithoutExtension }
            ?.sorted()
            ?: emptyList()

    @Synchronized
    fun deleteWorkout(workoutId: String) {
        validateWorkoutId(workoutId)
        if (activeWorkoutId() == workoutId) {
            throw IllegalStateException("The active workout cannot be deleted.")
        }
        fileFor(workoutId).delete()
        preferences.edit().remove(nextIndexKey(workoutId)).apply()
    }

    private fun ensureNextPointIndex(workoutId: String): Int {
        val key = nextIndexKey(workoutId)
        if (preferences.contains(key)) return preferences.getInt(key, 0)

        val file = fileFor(workoutId)
        val count = if (file.exists()) {
            file.bufferedReader(StandardCharsets.UTF_8).useLines { lines ->
                lines.count { it.isNotBlank() }
            }
        } else {
            0
        }
        preferences.edit().putInt(key, count).apply()
        return count
    }

    private fun fileFor(workoutId: String): File =
        File(storageDirectory, "$workoutId.$FILE_EXTENSION")

    private fun nextIndexKey(workoutId: String): String = "next_index_$workoutId"

    private fun validateWorkoutId(workoutId: String) {
        require(WORKOUT_ID_PATTERN.matches(workoutId)) {
            "workoutId must contain only letters, digits, dots, underscores, or hyphens."
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "kls_gps_tracker"
        const val STORAGE_DIRECTORY = "kls_gps_tracker"
        const val FILE_EXTENSION = "jsonl"
        const val KEY_ACTIVE_WORKOUT_ID = "active_workout_id"
        const val KEY_IS_TRACKING = "is_tracking"
        const val KEY_SHOULD_AUTO_RESUME = "should_auto_resume"
        val WORKOUT_ID_PATTERN = Regex("[A-Za-z0-9._-]{1,128}")
    }
}
