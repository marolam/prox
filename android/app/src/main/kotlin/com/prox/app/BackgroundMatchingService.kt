package com.prox.app

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.location.Location
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.Timestamp
import java.util.Date
import java.util.TimeZone
import kotlin.math.round

/** Native ownership keeps Flutter and profile queries asleep while the screen is off. */
class BackgroundMatchingService : Service() {
    companion object {
        private const val PREFS = "prox_background_matching"
        private const val NOTICE = 7301
        fun preferences(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        private fun clearDisabledBuild(context: Context) {
            // This is the dedicated background collector store, not app/auth data.
            preferences(context).edit().clear().commit()
            context.stopService(Intent(context, BackgroundMatchingService::class.java))
        }
        fun permitted(context: Context): Boolean {
            if (!BuildConfig.PROX_BACKGROUND_MATCHING_AVAILABLE) return false
            val foreground = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            return foreground && (Build.VERSION.SDK_INT < 29 || ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED)
        }
        fun configure(context: Context, uid: String, deviceId: String, enabled: Boolean, mode: String): Boolean {
            if (!BuildConfig.PROX_BACKGROUND_MATCHING_AVAILABLE) {
                clearDisabledBuild(context)
                return false
            }
            val allowed = enabled && permitted(context) && FirebaseAuth.getInstance().currentUser?.uid == uid
            preferences(context).edit().putBoolean("enabled", allowed).putString("uid", uid)
                .putString("deviceId", deviceId).putString("mode", mode).apply()
            if (!allowed) {
                context.stopService(Intent(context, BackgroundMatchingService::class.java))
                return false
            }
            return try {
                ContextCompat.startForegroundService(context, Intent(context, BackgroundMatchingService::class.java))
                true
            } catch (_: Exception) { false }
        }
        fun channels(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val manager = context.getSystemService(NotificationManager::class.java)
                val ongoing = NotificationChannel("fgs", "Background matching", NotificationManager.IMPORTANCE_LOW)
                ongoing.setSound(null, null)
                ongoing.enableVibration(false)
                manager.createNotificationChannel(ongoing)
                manager.createNotificationChannel(NotificationChannel("significant_matches", "Significant matches", NotificationManager.IMPORTANCE_HIGH))
                val quiet = NotificationChannel("significant_matches_silent", "Significant matches (silent)", NotificationManager.IMPORTANCE_LOW)
                quiet.setSound(null, null)
                quiet.enableVibration(false)
                manager.createNotificationChannel(quiet)
            }
        }
    }

    private lateinit var fused: FusedLocationProviderClient
    private val handler = Handler(Looper.getMainLooper())
    private var lastUploaded: Location? = null
    private var lastWriteElapsed = 0L
    private var pending = false
    private var generation = 0
    private var owner = ""
    private var deviceId = ""
    private var travel = false
    private var running = false
    private val authListener = FirebaseAuth.AuthStateListener { auth ->
        if (owner.isNotEmpty() && auth.currentUser?.uid != owner) stopSelf()
    }
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) { result.lastLocation?.let { upload(it) } }
    }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!current()) { stopSelf(); return }
            try {
                val request = CurrentLocationRequest.Builder().setPriority(Priority.PRIORITY_BALANCED_POWER_ACCURACY)
                    .setMaxUpdateAgeMillis(2 * 60_000L).setDurationMillis(20_000L).build()
                fused.getCurrentLocation(request, null).addOnSuccessListener { location -> location?.let { upload(it, true) } }
            } catch (_: SecurityException) { stopSelf() }
            handler.postDelayed(this, 15 * 60_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        fused = LocationServices.getFusedLocationProviderClient(this)
        channels(this)
        FirebaseAuth.getInstance().addAuthStateListener(authListener)
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!BuildConfig.PROX_BACKGROUND_MATCHING_AVAILABLE) {
            preferences(this).edit().clear().commit()
            stopSelf()
            return START_NOT_STICKY
        }
        val prefs = preferences(this)
        val nextOwner = prefs.getString("uid", "") ?: ""
        val nextTravel = prefs.getString("mode", "normal") == "travel"
        if (!prefs.getBoolean("enabled", false) || !permitted(this) || FirebaseAuth.getInstance().currentUser?.uid != nextOwner) {
            stopSelf(); return START_NOT_STICKY
        }
        val open = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, "fgs").setSmallIcon(R.drawable.ic_stat_prox_notification)
            .setContentTitle("Prox background matching is on")
            .setContentText("Looking quietly for meaningful connections. Manage in Sound & alerts.")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setSilent(true).build()
        startForeground(NOTICE, notification)
        if (running && owner == nextOwner && travel == nextTravel) return START_STICKY
        generation++
        fused.removeLocationUpdates(callback)
        handler.removeCallbacks(heartbeat)
        owner = nextOwner
        deviceId = prefs.getString("deviceId", "") ?: ""
        travel = nextTravel
        running = true
        lastUploaded = null
        lastWriteElapsed = 0
        pending = false
        try {
            val interval = if (travel) 60_000L else 5 * 60_000L
            val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, interval)
                .setMinUpdateIntervalMillis(interval).setMaxUpdateDelayMillis(if (travel) interval else 10 * 60_000L).build()
            fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
            handler.post(heartbeat)
        } catch (_: SecurityException) { stopSelf(); return START_NOT_STICKY }
        return START_STICKY
    }
    private fun current() = BuildConfig.PROX_BACKGROUND_MATCHING_AVAILABLE && running && permitted(this) && preferences(this).getBoolean("enabled", false) &&
        preferences(this).getString("uid", "") == owner && FirebaseAuth.getInstance().currentUser?.uid == owner

    private fun upload(location: Location, heartbeat: Boolean = false) {
        if (!current() || pending || deviceId.isEmpty()) return
        val now = System.currentTimeMillis()
        if (now - location.time !in 0..120_000 || location.accuracy !in 0f..220f) return
        val elapsed = SystemClock.elapsedRealtime()
        val gap = elapsed - lastWriteElapsed
        if (lastWriteElapsed > 0 && gap < (if (travel) 60_000L else 5 * 60_000L)) return
        if (!travel && !heartbeat && lastUploaded != null && location.distanceTo(lastUploaded!!) < 250 && gap < 15 * 60_000L) return
        val revision = generation
        val sampleOwner = owner
        pending = true
        // Approximate location only: no path history and no continuous GPS accuracy request.
        FirebaseFirestore.getInstance().document("users/$sampleOwner/backgroundPresence/current").set(mapOf(
            "enabled" to true, "deviceId" to deviceId,
            "latitude" to round(location.latitude * 1000) / 1000,
            "longitude" to round(location.longitude * 1000) / 1000,
            "locationAt" to Timestamp(Date(location.time)), "receivedAt" to FieldValue.serverTimestamp(),
            "accuracyMeters" to location.accuracy.toDouble() + 80,
            "speedMps" to if (location.hasSpeed()) location.speed.toDouble() else -1.0,
            "utcOffsetMinutes" to TimeZone.getDefault().getOffset(now) / 60000,
            "expiresAt" to Timestamp(Date(now + 30 * 60_000L))
        )).addOnCompleteListener { result ->
            if (revision == generation) {
                pending = false
                if (result.isSuccessful) { lastUploaded = location; lastWriteElapsed = elapsed }
                if (!current()) FirebaseFirestore.getInstance().document("users/$sampleOwner/backgroundPresence/current").delete()
            }
        }
    }
    override fun onDestroy() {
        running = false
        generation++
        handler.removeCallbacksAndMessages(null)
        fused.removeLocationUpdates(callback)
        FirebaseAuth.getInstance().removeAuthStateListener(authListener)
        super.onDestroy()
    }
}

class BackgroundMatchingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!BuildConfig.PROX_BACKGROUND_MATCHING_AVAILABLE) {
            BackgroundMatchingService.configure(context, "", "", false, "normal")
            return
        }
        val prefs = BackgroundMatchingService.preferences(context)
        if (prefs.getBoolean("enabled", false)) BackgroundMatchingService.configure(context,
            prefs.getString("uid", "") ?: "", prefs.getString("deviceId", "") ?: "", true, prefs.getString("mode", "normal") ?: "normal")
    }
}
