package com.animenotify.app;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Persists followed shows locally; AnimeNotify has no account or cloud tracking. */
public final class ReminderStore {
    private static final String PREFS = "anime_reminders";
    private static final String ITEMS = "items";
    private static final String LEAD = "lead_minutes";

    private ReminderStore() { }

    public static final class SavedReminder {
        public int mediaId;
        public String title;
        public String imageUrl;
        public int episode;
        public long airingAt;

        SavedReminder(int mediaId, String title, String imageUrl, int episode, long airingAt) {
            this.mediaId = mediaId;
            this.title = title;
            this.imageUrl = imageUrl;
            this.episode = episode;
            this.airingAt = airingAt;
        }

        JSONObject json() throws Exception {
            JSONObject value = new JSONObject();
            value.put("mediaId", mediaId);
            value.put("title", title);
            value.put("imageUrl", imageUrl);
            value.put("episode", episode);
            value.put("airingAt", airingAt);
            return value;
        }

        static SavedReminder from(JSONObject value) {
            return new SavedReminder(value.optInt("mediaId"), value.optString("title", "Anime"),
                    value.optString("imageUrl", ""), value.optInt("episode"),
                    value.optLong("airingAt"));
        }
    }

    public static synchronized List<SavedReminder> all(Context context) {
        List<SavedReminder> result = new ArrayList<SavedReminder>();
        String raw = prefs(context).getString(ITEMS, "[]");
        try {
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                SavedReminder item = SavedReminder.from(array.getJSONObject(i));
                if (item.mediaId != 0) result.add(item);
            }
        } catch (Exception ignored) { }
        Collections.sort(result, new Comparator<SavedReminder>() {
            @Override public int compare(SavedReminder a, SavedReminder b) {
                return a.airingAt < b.airingAt ? -1 : (a.airingAt == b.airingAt ? 0 : 1);
            }
        });
        return result;
    }

    public static boolean contains(Context context, int mediaId) {
        return find(context, mediaId) != null;
    }

    public static SavedReminder find(Context context, int mediaId) {
        for (SavedReminder reminder : all(context)) {
            if (reminder.mediaId == mediaId) return reminder;
        }
        return null;
    }

    public static synchronized SavedReminder add(Context context, AnimeItem item) {
        List<SavedReminder> items = all(context);
        for (int i = items.size() - 1; i >= 0; i--) {
            if (items.get(i).mediaId == item.mediaId) items.remove(i);
        }
        SavedReminder saved = new SavedReminder(item.mediaId, item.title, item.imageUrl,
                item.episode, item.airingAt);
        items.add(saved);
        save(context, items);
        return saved;
    }

    public static synchronized void remove(Context context, int mediaId) {
        List<SavedReminder> items = all(context);
        for (int i = items.size() - 1; i >= 0; i--) {
            if (items.get(i).mediaId == mediaId) items.remove(i);
        }
        save(context, items);
    }

    public static synchronized void refresh(Context context, AnimeItem current) {
        SavedReminder existing = find(context, current.mediaId);
        if (existing == null || current.airingAt <= existing.airingAt) return;
        List<SavedReminder> items = all(context);
        for (SavedReminder item : items) {
            if (item.mediaId == current.mediaId) {
                item.airingAt = current.airingAt;
                item.episode = current.episode;
                item.title = current.title;
                item.imageUrl = current.imageUrl;
            }
        }
        save(context, items);
    }

    public static synchronized SavedReminder advance(Context context, int mediaId) {
        List<SavedReminder> items = all(context);
        SavedReminder advanced = null;
        for (SavedReminder item : items) {
            if (item.mediaId == mediaId) {
                item.airingAt += 7L * 24L * 60L * 60L;
                if (item.episode > 0) item.episode += 1;
                advanced = item;
            }
        }
        save(context, items);
        return advanced;
    }

    public static int leadMinutes(Context context) {
        return prefs(context).getInt(LEAD, 15);
    }

    public static void setLeadMinutes(Context context, int minutes) {
        prefs(context).edit().putInt(LEAD, minutes).apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static void save(Context context, List<SavedReminder> items) {
        JSONArray array = new JSONArray();
        try {
            for (SavedReminder item : items) array.put(item.json());
        } catch (Exception ignored) { }
        prefs(context).edit().putString(ITEMS, array.toString()).apply();
    }
}
