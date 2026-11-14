package com.debrify.app.sports

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Kick-off reminders: one exact alarm per game, fired at the time Dart
 * planned (15 minutes before kick-off), each posting one notification.
 *
 * Dart owns the plan and always sends the complete set (`replaceAll`); this
 * side cancels what it scheduled before, stores the new set so a reboot or
 * app update can re-arm it, and arms it.
 */
object SportsReminders {
	const val CHANNEL = "com.debrify.app/sports_reminders"
	const val ACTION_FIRE = "com.debrify.app.SPORTS_REMINDER"
	const val EXTRA_ID = "id"

	private const val PREFS = "debrify_sports_reminders"
	private const val KEY_ALERTS = "alerts"

	/** Dart's lead time (sportsReminderLead): an alert this recently due
	 *  still precedes kick-off. */
	private const val LEAD_MS = 15 * 60 * 1000L

	data class Alert(val id: String, val title: String, val body: String, val fireAtMs: Long)

	fun register(context: Context, messenger: BinaryMessenger) {
		val app = context.applicationContext
		MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"replaceAll" -> {
					val raw = call.argument<List<Map<String, Any?>>>("alerts") ?: emptyList()
					replaceAll(app, raw.mapNotNull(::parse))
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun parse(map: Map<String, Any?>): Alert? {
		val id = map["id"] as? String ?: return null
		val fireAt = (map["fireAtMs"] as? Number)?.toLong() ?: return null
		return Alert(
			id = id,
			title = map["title"] as? String ?: "",
			body = map["body"] as? String ?: "",
			fireAtMs = fireAt,
		)
	}

	fun replaceAll(context: Context, alerts: List<Alert>) {
		val alarms = context.getSystemService(AlarmManager::class.java) ?: return
		for (old in load(context)) {
			alarms.cancel(pendingIntent(context, old.id))
		}
		save(context, alerts)
		arm(context, alerts)
	}

	/**
	 * Re-arms the stored set; alarms do not survive a reboot or an update.
	 * An alert that came due while the phone was off fires now if its game
	 * has not kicked off; older ones are dropped.
	 */
	fun rearm(context: Context) {
		val now = System.currentTimeMillis()
		val alerts = load(context)
			.filter { it.fireAtMs + LEAD_MS > now }
			.map { if (it.fireAtMs <= now) it.copy(fireAtMs = now + 2_000) else it }
		save(context, alerts)
		arm(context, alerts)
	}

	/** The alert that just fired leaves the stored set. */
	fun remove(context: Context, id: String): Alert? {
		val alerts = load(context)
		val fired = alerts.firstOrNull { it.id == id }
		save(context, alerts.filter { it.id != id })
		return fired
	}

	private fun arm(context: Context, alerts: List<Alert>) {
		val alarms = context.getSystemService(AlarmManager::class.java) ?: return
		val now = System.currentTimeMillis()
		for (alert in alerts) {
			if (alert.fireAtMs <= now) continue
			val pending = pendingIntent(context, alert.id)
			// Android 13+ grants USE_EXACT_ALARM and 12 grants
			// SCHEDULE_EXACT_ALARM by default, so this fallback is for a user
			// who revoked "Alarms & reminders": the alert may then come late.
			val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
				alarms.canScheduleExactAlarms()
			if (exact) {
				alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.fireAtMs, pending)
			} else {
				alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.fireAtMs, pending)
			}
		}
	}

	/** One PendingIntent per game: the data URI makes each distinct. */
	private fun pendingIntent(context: Context, id: String): PendingIntent {
		val intent = Intent(context, SportsReminderReceiver::class.java)
			.setAction(ACTION_FIRE)
			.setData(Uri.parse("debrify-sports-reminder://" + Uri.encode(id)))
			.putExtra(EXTRA_ID, id)
		return PendingIntent.getBroadcast(
			context,
			0,
			intent,
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
		)
	}

	private fun load(context: Context): List<Alert> {
		val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			.getString(KEY_ALERTS, null) ?: return emptyList()
		return try {
			val array = JSONArray(raw)
			(0 until array.length()).mapNotNull { index ->
				val item = array.optJSONObject(index) ?: return@mapNotNull null
				val id = item.optString("id")
				if (id.isEmpty()) null else Alert(
					id = id,
					title = item.optString("title"),
					body = item.optString("body"),
					fireAtMs = item.optLong("fireAtMs"),
				)
			}
		} catch (_: Exception) {
			emptyList()
		}
	}

	private fun save(context: Context, alerts: List<Alert>) {
		val array = JSONArray()
		for (alert in alerts) {
			array.put(
				JSONObject()
					.put("id", alert.id)
					.put("title", alert.title)
					.put("body", alert.body)
					.put("fireAtMs", alert.fireAtMs),
			)
		}
		context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString(KEY_ALERTS, array.toString())
			.apply()
	}
}
