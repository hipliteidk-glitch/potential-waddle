package com.animenotify.app;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Schedules battery-friendly reminders. Exact-alarm access is deliberately not required. */
public final class AlarmScheduler {
    private static final long WEEK = 7L * 24L * 60L * 60L * 1000L;

    private AlarmScheduler() { }

    public static void schedule(Context context, ReminderStore.SavedReminder reminder) {
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null || reminder == null) return;
        long now = System.currentTimeMillis();
        long airing = reminder.airingAt * 1000L;
        while (airing <= now) airing += WEEK;
        long trigger = airing - ReminderStore.leadMinutes(context) * 60L * 1000L;
        if (trigger <= now) trigger = now + 3000L;
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, intent(context, reminder));
    }

    public static void cancel(Context context, int mediaId) {
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager != null) manager.cancel(intent(context,
                new ReminderStore.SavedReminder(mediaId, "", "", 0, 0)));
    }

    public static void rescheduleAll(Context context) {
        for (ReminderStore.SavedReminder reminder : ReminderStore.all(context)) {
            schedule(context, reminder);
        }
    }

    private static PendingIntent intent(Context context, ReminderStore.SavedReminder reminder) {
        Intent value = new Intent(context, ReminderReceiver.class);
        value.setAction("com.animenotify.app.REMIND." + reminder.mediaId);
        value.putExtra("media_id", reminder.mediaId);
        value.putExtra("title", reminder.title);
        value.putExtra("episode", reminder.episode);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getBroadcast(context, Math.abs(reminder.mediaId), value, flags);
    }
}
