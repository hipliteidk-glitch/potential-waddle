package com.animenotify.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Build;

/** Delivers a reminder and rolls the locally scheduled show forward one week. */
public final class ReminderReceiver extends BroadcastReceiver {
    public static final String CHANNEL_ID = "anime_airing_reminders";

    @Override public void onReceive(Context context, Intent intent) {
        int mediaId = intent.getIntExtra("media_id", 1001);
        String title = intent.getStringExtra("title");
        int episode = intent.getIntExtra("episode", 0);
        showNotification(context, mediaId, title == null ? "Your anime" : title, episode, false);
        ReminderStore.SavedReminder next = ReminderStore.advance(context, mediaId);
        if (next != null) AlarmScheduler.schedule(context, next);
    }

    public static void createChannel(Context context) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager manager = (NotificationManager)
                    context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager == null) return;
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                    context.getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription(context.getString(R.string.notification_channel_description));
            channel.enableVibration(true);
            manager.createNotificationChannel(channel);
        }
    }

    public static void showNotification(Context context, int mediaId, String title,
                                        int episode, boolean test) {
        createChannel(context);
        Intent open = new Intent(context, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        open.putExtra("open_reminders", true);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent contentIntent = PendingIntent.getActivity(context, 90, open, flags);
        String line = test ? "Notifications are ready to go."
                : (episode > 0 ? "Episode " + episode + " airs soon" : "A new episode airs soon");

        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL_ID)
                : new Notification.Builder(context);
        builder.setSmallIcon(R.drawable.ic_notification)
                .setColor(Color.rgb(255, 50, 104))
                .setContentTitle(test ? "AnimeNotify test" : title)
                .setContentText(line)
                .setStyle(new Notification.BigTextStyle().bigText(line +
                        (test ? " Follow a title to get an alert before it airs."
                                : " — grab a snack and get ready.")))
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_REMINDER)
                .setPriority(Notification.PRIORITY_HIGH);
        NotificationManager manager = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager != null) manager.notify(test ? 90001 : Math.abs(mediaId), builder.build());
    }
}
