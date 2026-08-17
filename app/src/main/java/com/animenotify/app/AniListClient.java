package com.animenotify.app;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Fetches public airing data from AniList. No API key or user account is required. */
public final class AniListClient {
    private static final String ENDPOINT = "https://graphql.anilist.co";
    private static final String QUERY =
            "query ($start: Int, $end: Int) { Page(page: 1, perPage: 50) { " +
            "airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) { " +
            "id airingAt episode media { id title { romaji english } " +
            "coverImage { large color } averageScore format } } } }";

    private final Context context;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    public interface Callback {
        void onResult(List<AnimeItem> items, boolean live, String message);
    }

    public AniListClient(Context context) {
        this.context = context.getApplicationContext();
    }

    public void fetchDay(final Calendar requestedDay, final Callback callback) {
        final Calendar day = (Calendar) requestedDay.clone();
        executor.execute(new Runnable() {
            @Override public void run() {
                String key = dayKey(day);
                try {
                    String raw = request(day);
                    List<AnimeItem> parsed = parse(raw);
                    if (parsed.isEmpty()) throw new IllegalStateException("No schedule returned");
                    context.getSharedPreferences("schedule_cache", Context.MODE_PRIVATE)
                            .edit().putString(key, raw).apply();
                    callback.onResult(parsed, true, "Live schedule • AniList");
                } catch (Exception onlineError) {
                    String cached = context.getSharedPreferences("schedule_cache", Context.MODE_PRIVATE)
                            .getString(key, "");
                    if (cached.length() > 0) {
                        try {
                            callback.onResult(parse(cached), false, "Saved schedule • offline");
                            return;
                        } catch (Exception ignored) { }
                    }
                    callback.onResult(previewLineup(day), false, "Preview lineup • connect to refresh");
                }
            }
        });
    }

    private String request(Calendar day) throws Exception {
        Calendar start = (Calendar) day.clone();
        start.set(Calendar.HOUR_OF_DAY, 0);
        start.set(Calendar.MINUTE, 0);
        start.set(Calendar.SECOND, 0);
        start.set(Calendar.MILLISECOND, 0);
        Calendar end = (Calendar) start.clone();
        end.add(Calendar.DAY_OF_MONTH, 1);

        JSONObject variables = new JSONObject();
        variables.put("start", start.getTimeInMillis() / 1000L - 1L);
        variables.put("end", end.getTimeInMillis() / 1000L);
        JSONObject body = new JSONObject();
        body.put("query", QUERY);
        body.put("variables", variables);
        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);

        HttpURLConnection connection = (HttpURLConnection) new URL(ENDPOINT).openConnection();
        connection.setRequestMethod("POST");
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(16000);
        connection.setDoOutput(true);
        connection.setRequestProperty("Content-Type", "application/json");
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("User-Agent", "AnimeNotify-Android/1.0");
        connection.setFixedLengthStreamingMode(bytes.length);
        OutputStream output = connection.getOutputStream();
        output.write(bytes);
        output.close();

        int status = connection.getResponseCode();
        InputStream input = status >= 200 && status < 300
                ? connection.getInputStream() : connection.getErrorStream();
        BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8));
        StringBuilder response = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) response.append(line);
        reader.close();
        connection.disconnect();
        if (status < 200 || status >= 300) throw new IllegalStateException("HTTP " + status);
        return response.toString();
    }

    private List<AnimeItem> parse(String raw) throws Exception {
        JSONObject root = new JSONObject(raw);
        JSONArray data = root.getJSONObject("data").getJSONObject("Page")
                .getJSONArray("airingSchedules");
        List<AnimeItem> result = new ArrayList<AnimeItem>();
        for (int i = 0; i < data.length(); i++) {
            AnimeItem item = AnimeItem.fromJson(data.getJSONObject(i));
            if (item.mediaId != 0 && item.airingAt != 0) result.add(item);
        }
        Collections.sort(result, new Comparator<AnimeItem>() {
            @Override public int compare(AnimeItem first, AnimeItem second) {
                return first.airingAt < second.airingAt ? -1 : (first.airingAt == second.airingAt ? 0 : 1);
            }
        });
        return result;
    }

    private static String dayKey(Calendar day) {
        return new SimpleDateFormat("yyyyMMdd", Locale.US).format(day.getTime());
    }

    /** A clearly labelled offline preview keeps the first launch useful without fabricating live data. */
    private static List<AnimeItem> previewLineup(Calendar requestedDay) {
        String[] names = {"Moonlit Vanguard", "Neon Ronin", "Starlight Academy",
                "The Last Alchemist", "Skybound Chronicles"};
        String[] formats = {"TV", "ONA", "TV", "TV SHORT", "TV"};
        int[] hours = {10, 13, 16, 19, 22};
        List<AnimeItem> result = new ArrayList<AnimeItem>();
        for (int i = 0; i < names.length; i++) {
            Calendar time = (Calendar) requestedDay.clone();
            time.set(Calendar.HOUR_OF_DAY, hours[i]);
            time.set(Calendar.MINUTE, i % 2 == 0 ? 0 : 30);
            time.set(Calendar.SECOND, 0);
            time.set(Calendar.MILLISECOND, 0);
            result.add(new AnimeItem(-1000L - i, -1000 - i, names[i], "", "#FF3268",
                    0, formats[i], i + 3, time.getTimeInMillis() / 1000L, true));
        }
        return result;
    }
}
