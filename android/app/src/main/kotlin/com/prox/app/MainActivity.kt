package com.prox.app

import android.Manifest
import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationManager
import android.content.DialogInterface
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
	private val methodChannelName = "prox/system_health"
	private val eventChannelName = "prox/system_health/events"
	private val matchSoundChannelName = "prox/match_sound"

	private var eventSink: EventChannel.EventSink? = null
	private var powerReceiver: BroadcastReceiver? = null
	private var networkCallback: ConnectivityManager.NetworkCallback? = null

	private var streamUpdatesChannelId: String = "updates"
	private var streamFgsChannelId: String = "fgs"
	private var activeTextInputDialog: AlertDialog? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
			.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
				when (call.method) {
					"getSystemHealth" -> {
						val updatesChannelId = call.argument<String>("updatesChannelId") ?: "updates"
						val fgsChannelId = call.argument<String>("fgsChannelId") ?: "fgs"
						result.success(buildHealthPayload(updatesChannelId, fgsChannelId))
					}

					"openSettings" -> {
						val action = call.argument<String>("action") ?: ""
						result.success(openSettingsAction(action))
					}

					"forceShowKeyboard" -> {
						result.success(forceShowKeyboard())
					}

					"promptNativeTextInput" -> {
						val title = call.argument<String>("title") ?: "Edit"
						val initialValue = call.argument<String>("initialValue") ?: ""
						val minLines = call.argument<Int>("minLines") ?: 1
						val maxLines = call.argument<Int>("maxLines") ?: 1
						showNativeTextInputDialog(
							title = title,
							initialValue = initialValue,
							minLines = minLines,
							maxLines = maxLines,
							result = result,
						)
					}

					else -> result.notImplemented()
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, matchSoundChannelName)
			.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
				when (call.method) {
					"play" -> {
						val rare = call.argument<Boolean>("rare") ?: false
						val volume = call.argument<Double>("volume") ?: 0.72
						result.success(playMatchSound(rare, volume))
					}

					else -> result.notImplemented()
				}
			}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					eventSink = events
					val args = arguments as? Map<*, *>
					streamUpdatesChannelId = (args?.get("updatesChannelId") as? String) ?: "updates"
					streamFgsChannelId = (args?.get("fgsChannelId") as? String) ?: "fgs"
					startSystemObservers()
					pushCurrentSnapshot()
				}

				override fun onCancel(arguments: Any?) {
					stopSystemObservers()
					eventSink = null
				}
			})
	}

	override fun onDestroy() {
		stopSystemObservers()
		eventSink = null
		super.onDestroy()
	}

	private fun pushCurrentSnapshot() {
		val sink = eventSink ?: return
		try {
			sink.success(buildHealthPayload(streamUpdatesChannelId, streamFgsChannelId))
		} catch (_: Throwable) {
			// Ignore sink failures from detached Flutter listeners.
		}
	}

	private fun forceShowKeyboard(): Boolean {
		return try {
			runOnUiThread {
				val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
				val target = currentFocus ?: window?.decorView?.findViewById(android.R.id.content)
				target?.requestFocus()
				if (imm != null && target != null) {
					imm.showSoftInput(target, InputMethodManager.SHOW_FORCED)
					imm.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
				}
			}
			true
		} catch (_: Throwable) {
			false
		}
	}

	private fun showNativeTextInputDialog(
		title: String,
		initialValue: String,
		minLines: Int,
		maxLines: Int,
		result: MethodChannel.Result,
	) {
		try {
			runOnUiThread {
				activeTextInputDialog?.let { existing ->
					if (existing.isShowing) {
						result.success(null)
						return@runOnUiThread
					}
				}

				var completed = false
				val input = EditText(this).apply {
					setText(initialValue)
					setSelection(initialValue.length)
					isFocusable = true
					isFocusableInTouchMode = true
					isClickable = true
					isCursorVisible = true
					setTextIsSelectable(false)
					importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
					isLongClickable = false
					setMinLines(minLines.coerceAtLeast(1))
					setMaxLines(maxLines.coerceAtLeast(minLines.coerceAtLeast(1)))
					imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_FULLSCREEN
					inputType = if (maxLines > 1) {
						InputType.TYPE_CLASS_TEXT or
							InputType.TYPE_TEXT_FLAG_MULTI_LINE or
							InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
							InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
					} else {
						InputType.TYPE_CLASS_TEXT or
							InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
							InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
					}
				}

				val container = FrameLayout(this).apply {
					val margin = (24 * resources.displayMetrics.density).toInt()
					setPadding(margin, 0, margin, 0)
					addView(
						input,
						FrameLayout.LayoutParams(
							ViewGroup.LayoutParams.MATCH_PARENT,
							ViewGroup.LayoutParams.WRAP_CONTENT,
						)
					)
				}

				val dialog = AlertDialog.Builder(this)
					.setTitle(title)
					.setView(container)
					.setNegativeButton("Cancel") { d: DialogInterface, _: Int ->
						if (completed) return@setNegativeButton
						completed = true
						d.dismiss()
						result.success(null)
					}
					.setPositiveButton("Use") { d: DialogInterface, _: Int ->
						if (completed) return@setPositiveButton
						completed = true
						val out = input.text?.toString() ?: ""
						d.dismiss()
						result.success(out)
					}
					.setOnCancelListener {
						if (completed) return@setOnCancelListener
						completed = true
						result.success(null)
					}
					.create()

				dialog.setOnDismissListener {
					if (activeTextInputDialog === dialog) {
						activeTextInputDialog = null
					}
				}

				dialog.setOnShowListener {
					dialog.window?.setSoftInputMode(
						WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
							WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
					)
					input.post {
						input.requestFocus()
						input.setSelection(input.text?.length ?: 0)
						val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
						imm?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
					}
				}

				dialog.show()
				activeTextInputDialog = dialog
			}
		} catch (t: Throwable) {
			result.error("native_text_input_failed", t.message, null)
		}
	}

	private fun playMatchSound(rare: Boolean, volume: Double): Boolean {
		return try {
			Thread {
				val level = (volume.coerceIn(0.0, 1.0) * 100).toInt()
				if (level == 0) return@Thread
				val toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, level)
				try {
					if (rare) {
						playTone(toneGenerator, ToneGenerator.TONE_PROP_ACK, 90, 70)
						playTone(toneGenerator, ToneGenerator.TONE_PROP_BEEP2, 120, 80)
						playTone(toneGenerator, ToneGenerator.TONE_PROP_ACK, 140, 0)
					} else {
						playTone(toneGenerator, ToneGenerator.TONE_PROP_BEEP, 110, 0)
					}
				} finally {
					toneGenerator.release()
				}
			}.start()
			true
		} catch (_: Throwable) {
			false
		}
	}

	private fun playTone(
		toneGenerator: ToneGenerator,
		toneType: Int,
		durationMs: Int,
		pauseAfterMs: Long,
	) {
		toneGenerator.startTone(toneType, durationMs)
		try {
			Thread.sleep(durationMs.toLong() + pauseAfterMs)
		} catch (_: InterruptedException) {
			Thread.currentThread().interrupt()
		}
	}

	private fun startSystemObservers() {
		if (powerReceiver == null) {
			val filter = IntentFilter().apply {
				addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
				addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
			}
			powerReceiver = object : BroadcastReceiver() {
				override fun onReceive(context: Context?, intent: Intent?) {
					pushCurrentSnapshot()
				}
			}
			registerReceiver(powerReceiver, filter)
		}

		if (networkCallback == null) {
			val cm = getSystemService(ConnectivityManager::class.java)
			if (cm != null) {
				val cb = object : ConnectivityManager.NetworkCallback() {
					override fun onAvailable(network: android.net.Network) {
						pushCurrentSnapshot()
					}

					override fun onLost(network: android.net.Network) {
						pushCurrentSnapshot()
					}

					override fun onCapabilitiesChanged(
						network: android.net.Network,
						networkCapabilities: NetworkCapabilities
					) {
						pushCurrentSnapshot()
					}
				}
				try {
					cm.registerDefaultNetworkCallback(cb)
					networkCallback = cb
				} catch (_: Throwable) {
					networkCallback = null
				}
			}
		}
	}

	private fun stopSystemObservers() {
		powerReceiver?.let {
			try {
				unregisterReceiver(it)
			} catch (_: Throwable) {
				// Receiver may already be unregistered.
			}
		}
		powerReceiver = null

		val cm = getSystemService(ConnectivityManager::class.java)
		networkCallback?.let { cb ->
			if (cm != null) {
				try {
					cm.unregisterNetworkCallback(cb)
				} catch (_: Throwable) {
					// Callback may already be unregistered.
				}
			}
		}
		networkCallback = null
	}

	private fun buildHealthPayload(updatesChannelId: String, fgsChannelId: String): Map<String, Any> {
		val badges = mutableListOf<Map<String, String>>()

		badges.add(notificationBadge(updatesChannelId))
		badges.add(batterySaverBadge())
		badges.add(dozeBadge())
		badges.add(foregroundServiceBadge(fgsChannelId))
		badges.add(networkBadge())
		badges.add(backgroundLocationBadge())

		return mapOf(
			"timestampMs" to System.currentTimeMillis(),
			"badges" to badges
		)
	}

	private fun notificationBadge(updatesChannelId: String): Map<String, String> {
		val nm = getSystemService(NotificationManager::class.java)
		val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
		val channelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			nm?.getNotificationChannel(updatesChannelId)?.importance ?: NotificationManager.IMPORTANCE_UNSPECIFIED
		} else {
			NotificationManager.IMPORTANCE_DEFAULT
		}

		return when {
			!enabled -> badge(
				id = "notifications",
				label = "Notifications -> OFF (updates muted)",
				severity = "error",
				action = "open_notifications"
			)

			Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelImportance == NotificationManager.IMPORTANCE_NONE -> badge(
				id = "notifications",
				label = "Notifications -> Channel MUTED",
				severity = "warn",
				action = "open_notification_channel"
			)

			else -> badge(
				id = "notifications",
				label = "Notifications -> ON",
				severity = "ok",
				action = "open_notifications"
			)
		}
	}

	private fun batterySaverBadge(): Map<String, String> {
		val pm = getSystemService(PowerManager::class.java)
		val saverOn = pm?.isPowerSaveMode == true
		return if (saverOn) {
			badge(
				id = "battery_saver",
				label = "Battery Saver -> ON - background jobs paused",
				severity = "warn",
				action = "open_battery_saver"
			)
		} else {
			badge(
				id = "battery_saver",
				label = "Battery Saver -> OFF",
				severity = "ok",
				action = "open_battery_saver"
			)
		}
	}

	private fun dozeBadge(): Map<String, String> {
		val pm = getSystemService(PowerManager::class.java)
		val idleOn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			pm?.isDeviceIdleMode == true
		} else {
			false
		}

		return if (idleOn) {
			badge(
				id = "doze",
				label = "Doze -> DEVICE IDLE - network deferred",
				severity = "warn",
				action = "open_battery_optimization"
			)
		} else {
			badge(
				id = "doze",
				label = "Doze -> ACTIVE",
				severity = "ok",
				action = "open_battery_optimization"
			)
		}
	}

	private fun foregroundServiceBadge(fgsChannelId: String): Map<String, String> {
		val nm = getSystemService(NotificationManager::class.java)
		return try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
				val active = nm?.activeNotifications ?: emptyArray()
				val hasOngoing = active.any {
					val isOngoing = (it.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
					val sameChannel = it.notification.channelId == fgsChannelId
					isOngoing && sameChannel
				}
				if (hasOngoing) {
					badge(
						id = "fgs",
						label = "FGS -> RUNNING",
						severity = "ok",
						action = "open_notifications"
					)
				} else {
					badge(
						id = "fgs",
						label = "FGS -> NOT RUNNING (needs Live session)",
						severity = "warn",
						action = "open_app_details"
					)
				}
			} else {
				badge(
					id = "fgs",
					label = "FGS -> status unknown (API <23)",
					severity = "info",
					action = "open_app_details"
				)
			}
		} catch (_: Throwable) {
			badge(
				id = "fgs",
				label = "FGS -> status unknown (inspection failed)",
				severity = "info",
				action = "open_app_details"
			)
		}
	}

	private fun networkBadge(): Map<String, String> {
		val cm = getSystemService(ConnectivityManager::class.java)
		val capabilities = cm?.getNetworkCapabilities(cm.activeNetwork)
		val validated = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
		val captive = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true
		val internet = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

		return when {
			captive -> badge(
				id = "network",
				label = "Network -> CAPTIVE PORTAL - login required",
				severity = "warn",
				action = "open_wifi"
			)

			!internet -> badge(
				id = "network",
				label = "Network -> NO INTERNET",
				severity = "error",
				action = "open_wifi"
			)

			internet && !validated -> badge(
				id = "network",
				label = "Network -> LIMITED (not validated)",
				severity = "warn",
				action = "open_wifi"
			)

			else -> badge(
				id = "network",
				label = "Network -> OK",
				severity = "ok",
				action = "open_wifi"
			)
		}
	}

	private fun backgroundLocationBadge(): Map<String, String> {
		val bgGranted = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
			true
		} else {
			checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
		}

		return if (bgGranted) {
			badge(
				id = "background_location",
				label = "Location -> Background ALLOWED",
				severity = "ok",
				action = "open_app_details"
			)
		} else {
			badge(
				id = "background_location",
				label = "Location -> Background NOT ALLOWED - tap to open Settings",
				severity = "warn",
				action = "open_app_details"
			)
		}
	}

	private fun badge(id: String, label: String, severity: String, action: String): Map<String, String> {
		return mapOf(
			"id" to id,
			"label" to label,
			"severity" to severity,
			"action" to action
		)
	}

	private fun openSettingsAction(action: String): Boolean {
		val intent = when (action) {
			"open_notifications" -> {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
					Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
						putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
					}
				} else {
					appDetailsIntent()
				}
			}

			"open_notification_channel" -> {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
					Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
						putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
						putExtra(Settings.EXTRA_CHANNEL_ID, streamUpdatesChannelId)
					}
				} else {
					appDetailsIntent()
				}
			}

			"open_battery_saver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
			"open_battery_optimization" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
			"open_wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
			"open_location_settings" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
			"open_app_details" -> appDetailsIntent()
			else -> appDetailsIntent()
		}

		return try {
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			startActivity(intent)
			true
		} catch (_: Throwable) {
			try {
				val fallback = appDetailsIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
				startActivity(fallback)
				true
			} catch (_: Throwable) {
				false
			}
		}
	}

	private fun appDetailsIntent(): Intent {
		return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
			data = android.net.Uri.fromParts("package", packageName, null)
		}
	}
}
