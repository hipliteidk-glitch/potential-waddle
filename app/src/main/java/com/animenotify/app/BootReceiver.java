package com.animenotify.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Restores followed-show alarms after reboot or app update. */
public final class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        AlarmScheduler.rescheduleAll(context);
    }
}
