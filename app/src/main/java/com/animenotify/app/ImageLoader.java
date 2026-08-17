package com.animenotify.app;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;
import android.widget.ImageView;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Tiny dependency-free cover loader with an in-memory LRU cache. */
public final class ImageLoader {
    private static final ExecutorService POOL = Executors.newFixedThreadPool(3);
    private static final LruCache<String, Bitmap> CACHE = new LruCache<String, Bitmap>(20);

    private ImageLoader() { }

    public static void load(final String url, final ImageView target) {
        if (url == null || url.length() == 0) return;
        target.setTag(url);
        Bitmap cached = CACHE.get(url);
        if (cached != null) {
            target.setImageBitmap(cached);
            return;
        }
        POOL.execute(new Runnable() {
            @Override public void run() {
                HttpURLConnection connection = null;
                try {
                    connection = (HttpURLConnection) new URL(url).openConnection();
                    connection.setConnectTimeout(8000);
                    connection.setReadTimeout(10000);
                    connection.setRequestProperty("User-Agent", "AnimeNotify-Android/1.0");
                    InputStream input = connection.getInputStream();
                    final Bitmap bitmap = BitmapFactory.decodeStream(input);
                    input.close();
                    if (bitmap != null) {
                        CACHE.put(url, bitmap);
                        target.post(new Runnable() {
                            @Override public void run() {
                                if (url.equals(target.getTag())) target.setImageBitmap(bitmap);
                            }
                        });
                    }
                } catch (Exception ignored) {
                    // The coloured placeholder remains visible.
                } finally {
                    if (connection != null) connection.disconnect();
                }
            }
        });
    }
}
