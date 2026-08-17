package com.animenotify.app;

import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** A single upcoming episode returned by AniList. */
public final class AnimeItem {
    public final long scheduleId;
    public final int mediaId;
    public final String title;
    public final String imageUrl;
    public final String accentColor;
    public final int score;
    public final String format;
    public final int episode;
    public final long airingAt;
    public final boolean preview;

    public AnimeItem(long scheduleId, int mediaId, String title, String imageUrl,
                     String accentColor, int score, String format, int episode,
                     long airingAt, boolean preview) {
        this.scheduleId = scheduleId;
        this.mediaId = mediaId;
        this.title = title;
        this.imageUrl = imageUrl;
        this.accentColor = accentColor;
        this.score = score;
        this.format = format;
        this.episode = episode;
        this.airingAt = airingAt;
        this.preview = preview;
    }

    public static AnimeItem fromJson(JSONObject value) throws Exception {
        JSONObject media = value.getJSONObject("media");
        JSONObject titles = media.getJSONObject("title");
        String english = titles.optString("english", "");
        String romaji = titles.optString("romaji", "Untitled anime");
        String title = english.length() > 0 && !"null".equals(english) ? english : romaji;
        JSONObject cover = media.optJSONObject("coverImage");
        String image = cover == null ? "" : cover.optString("large", "");
        String accent = cover == null ? "" : cover.optString("color", "");
        return new AnimeItem(
                value.optLong("id"),
                media.optInt("id"),
                title,
                image,
                accent,
                media.optInt("averageScore", 0),
                friendlyFormat(media.optString("format", "TV")),
                value.optInt("episode", 0),
                value.optLong("airingAt"),
                false
        );
    }

    private static String friendlyFormat(String raw) {
        if (raw == null || raw.length() == 0 || "null".equals(raw)) return "TV";
        if ("TV_SHORT".equals(raw)) return "TV SHORT";
        if ("ONA".equals(raw) || "OVA".equals(raw)) return raw;
        return raw.replace('_', ' ');
    }

    public String timeLabel() {
        return new SimpleDateFormat("h:mm a", Locale.getDefault())
                .format(new Date(airingAt * 1000L));
    }

    public String episodeLabel() {
        return episode > 0 ? "EP " + episode : "NEW EP";
    }
}
