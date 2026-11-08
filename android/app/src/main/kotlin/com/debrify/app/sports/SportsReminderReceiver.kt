package com.debrify.app.sports

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Posts a kick-off reminder when its alarm fires, and re-arms the stored
 * reminders after a reboot, an app update, or an exact-alarm grant.
 */
class SportsReminderReceiver : BroadcastReceiver() {
	override fun onReceive(context: Context, intent: Intent) {
		when (intent.action) {
			SportsReminders.ACTION_FIRE -> {
				val id = intent.getStringExtra(SportsReminders.EXTRA_ID) ?: return
				val alert = SportsReminders.remove(context, id) ?: return
				post(context, alert)
			}
			Intent.ACTION_BOOT_COMPLETED,
			Intent.ACTION_MY_PACKAGE_REPLACED,
			"android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
			-> SportsReminders.rearm(context)
		}
	}

	private fun post(context: Context, alert: SportsReminders.Alert) {
		val manager = NotificationManagerCompat.from(context)
		// Declined or switched off: nothing to show, and nothing to retry.
		if (!manager.areNotificationsEnabled()) return
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(
				NotificationChannel(
					CHANNEL_ID,
					"Sports reminders",
					NotificationManager.IMPORTANCE_HIGH,
				).apply { description = "Kick-off reminders for games you chose" },
			)
		}
		val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
			?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
		val open = launch?.let {
			PendingIntent.getActivity(
				context,
				alert.id.hashCode(),
				it,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
		}
		val notification = NotificationCompat.Builder(context, CHANNEL_ID)
			.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
			.setContentTitle(alert.title)
			.setContentText(alert.body)
			.setCategory(NotificationCompat.CATEGORY_REMINDER)
			.setPriority(NotificationCompat.PRIORITY_HIGH)
			.setAutoCancel(true)
			.apply { if (open != null) setContentIntent(open) }
			.build()
		try {
			manager.notify(NOTIFICATION_TAG, alert.id.hashCode(), notification)
		} catch (_: SecurityException) {
			// Permission revoked between the check and the post.
		}
	}

	private companion object {
		const val CHANNEL_ID = "sports_reminders"
		const val NOTIFICATION_TAG = "sports_reminder"
	}
}
