package com.debrify.app.recording

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Fires at a schedule's start time and hands it to [LiveRecordingService].
 *
 * EVERY scheduled start goes through an alarm fire — including "late joins"
 * (schedules already inside their window when [registerAll] runs, e.g. the
 * device was off at start time), which get an alarm a few seconds out instead
 * of a direct service start. Two reasons: the alarm-fire path carries the
 * foreground-service background-start exemption on every Android version, and
 * Android 15 explicitly forbids starting a dataSync FGS from a BOOT_COMPLETED
 * receiver — so the boot receiver must never start the service itself.
 */
class RecordingAlarmReceiver : BroadcastReceiver() {

	companion object {
		const val EXTRA_SCHEDULE_ID = "extra_schedule_id"

		/** Don't bother starting a recording with less than this left. */
		private const val MIN_REMAINING_MS = 60_000L

		/** EPG stop times are approximate; run past them a little. */
		private const val END_PAD_MS = 2L * 60 * 1000

		/** Late-join alarms fire this far out — effectively "now", but through
		 *  the exemption-carrying alarm path. */
		private const val LATE_JOIN_DELAY_MS = 5_000L

		fun exactAlarmsGranted(context: Context): Boolean {
			if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
			val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
			return try { am.canScheduleExactAlarms() } catch (_: Exception) { false }
		}

		private fun alarmPendingIntent(context: Context, scheduleId: String): PendingIntent {
			val intent = Intent(context, RecordingAlarmReceiver::class.java).apply {
				putExtra(EXTRA_SCHEDULE_ID, scheduleId)
			}
			return PendingIntent.getBroadcast(
				context,
				("rec-sched-$scheduleId").hashCode(),
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
		}

		/**
		 * (Re-)arm alarms for every stored schedule. Idempotent — re-setting an
		 * alarm with the same PendingIntent replaces it. Called from: schedule
		 * creation, boot, app update, and engine setup in MainActivity (which
		 * also revives schedules after a force-stop, the one state where no
		 * alarm and no broadcast can reach us).
		 */
		fun registerAll(context: Context) {
			val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
			val now = System.currentTimeMillis()
			val exact = exactAlarmsGranted(context)
			for ((id, schedule) in RecordingScheduleStore.all(context)) {
				if (schedule.endMs - MIN_REMAINING_MS <= now) {
					// Fully missed: nothing recordable remains.
					RecordingScheduleStore.remove(context, id)
					cancelAlarm(context, id)
					continue
				}
				val triggerAt = if (schedule.startMs <= now) {
					now + LATE_JOIN_DELAY_MS
				} else {
					schedule.startMs
				}
				val pi = alarmPendingIntent(context, id)
				// New schedules are only ACCEPTED while the exact-alarm grant is
				// held (MainActivity / the TV guide refuse otherwise), so the
				// setWindow branch exists solely for schedules stranded by a
				// LATER revocation. An inexact fire cannot legally start the
				// service from the background — but it costs nothing, sometimes
				// lands while the app is foreground, and onReceive re-stores the
				// schedule on failure so the next app open (or the permission
				// coming back, see RecordingBootReceiver) can still record the
				// remainder.
				try {
					when {
						exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
							am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
						exact ->
							am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
						else ->
							am.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, 10L * 60 * 1000, pi)
					}
				} catch (_: Exception) {
					// SecurityException from a revoked grant mid-flight.
					try {
						am.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, 10L * 60 * 1000, pi)
					} catch (_: Exception) {}
				}
			}
		}

		fun cancelAlarm(context: Context, scheduleId: String) {
			val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
			try { am.cancel(alarmPendingIntent(context, scheduleId)) } catch (_: Exception) {}
		}

		fun sanitizeName(raw: String): String {
			val cleaned = raw.replace(Regex("[^A-Za-z0-9 _-]"), "")
				.trim()
				.replace(Regex("\\s+"), "_")
			return cleaned.take(60).ifEmpty { "recording" }
		}
	}

	override fun onReceive(context: Context, intent: Intent) {
		val scheduleId = intent.getStringExtra(EXTRA_SCHEDULE_ID) ?: return
		val schedule = RecordingScheduleStore.get(context, scheduleId) ?: return
		// One-shot: fired is fired, whatever happens next. Deleting first also
		// makes a double-delivered alarm harmless (second load finds nothing).
		RecordingScheduleStore.remove(context, scheduleId)

		val now = System.currentTimeMillis()
		if (schedule.endMs - MIN_REMAINING_MS <= now) return // missed

		val stamp = java.text.SimpleDateFormat("yyyyMMdd_HHmm", java.util.Locale.US)
			.format(java.util.Date(schedule.startMs))
		val base = sanitizeName(
			schedule.programmeTitle.ifBlank { schedule.channelName },
		)
		val fileName = "${base}_$stamp.ts"
		val maxDuration = (schedule.endMs - now + END_PAD_MS)
			.coerceAtMost(LiveRecordingService.MAX_DURATION_DEFAULT_MS)

		val start = LiveRecordingService.buildStartIntent(
			context = context,
			taskId = scheduleId,
			url = schedule.url,
			fileName = fileName,
			channelName = schedule.channelName,
			headers = schedule.headers,
			maxDurationMs = maxDuration,
			fromSchedule = true,
			ownerProfileId = schedule.ownerProfileId,
			connectionResourceId = schedule.connectionResourceId,
			profileAuthorizationRevision = schedule.profileAuthorizationRevision,
			resourceAuthorizationRevision = schedule.resourceAuthorizationRevision,
		)
		try {
			ContextCompat.startForegroundService(context, start)
		} catch (e: Exception) {
			// The background-start exemption belongs to EXACT alarms; a
			// setWindow fallback alarm (no exact-alarm grant) firing while the
			// app is backgrounded lands here. Put the schedule BACK so the next
			// registerAll (app open, boot) can late-join what remains of the
			// programme — and say it out loud, because silent loss is the one
			// outcome that is never acceptable.
			runCatching { RecordingScheduleStore.put(context, schedule) }
			try {
				LiveRecordingService.ensureNotificationChannel(context)
				val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
					as NotificationManager
				manager.notify(
					("rec-sched-fail-$scheduleId").hashCode(),
					NotificationCompat.Builder(context, LiveRecordingService.NOTIFICATION_CHANNEL_ID)
						.setContentTitle("Scheduled recording couldn't start")
						.setContentText(
							"${schedule.channelName} — ${schedule.programmeTitle}".trim(' ', '—'),
						)
						.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
						.setPriority(NotificationCompat.PRIORITY_DEFAULT)
						.build(),
				)
			} catch (_: Exception) {}
		}
	}
}

/**
 * Re-arms schedule alarms after the events that invalidate them: a reboot and
 * an app update (both silently clear every alarm), and the exact-alarm
 * permission being granted (Android sends
 * ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED and expects apps to
 * reschedule — without this, schedules armed while the grant was missing
 * would stay as inexact setWindow alarms that can't start the service).
 * Never starts the service itself (see [RecordingAlarmReceiver] for why).
 */
class RecordingBootReceiver : BroadcastReceiver() {
	override fun onReceive(context: Context, intent: Intent) {
		when (intent.action) {
			Intent.ACTION_BOOT_COMPLETED,
			Intent.ACTION_MY_PACKAGE_REPLACED,
			AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
			-> RecordingAlarmReceiver.registerAll(context)
		}
	}
}
