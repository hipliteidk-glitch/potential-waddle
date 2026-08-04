/*
 * Aliucord Debug Bridge Plugin
 * ─────────────────────────────────────────────────────────────────────
 * Writes the current plugin registry state to a JSON file in
 * /sdcard/Aliucord/debug/ so Termux (or any file-access tool) can
 * inspect it without root or opening the Discord UI.
 *
 * On every start, this plugin:
 *   1. Dumps all loaded plugins (name, version, enabled, filename)
 *   2. Dumps any failed-to-load plugins with error details
 *   3. Writes basic environment info (Discord version, Aliucord path)
 *   4. Starts a tiny HTTP server on localhost:2273 (optional) so
 *      Termux can query it with `curl` without restarting Discord
 *
 * Output file: /sdcard/Aliucord/debug/plugin_registry.json
 * HTTP endpoint: http://localhost:2273/status
 * ─────────────────────────────────────────────────────────────────────
 */
package com.aliucord.plugins;

import android.content.Context;
import android.os.Build;

import com.aliucord.Constants;
import com.aliucord.Logger;
import com.aliucord.PluginManager;
import com.aliucord.entities.Plugin;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

public class DebugBridge extends Plugin {
    private static final Logger logger = new Logger("DebugBridge");
    private static final String DEBUG_DIR = Constants.BASE_PATH + "/debug";
    private static final String REGISTRY_FILE = DEBUG_DIR + "/plugin_registry.json";
    private static final int HTTP_PORT = 2273;

    private final AtomicBoolean httpRunning = new AtomicBoolean(false);
    private ServerSocket serverSocket;
    private Thread httpThread;

    @Override
    public void start(Context context) throws Throwable {
        logger.info("DebugBridge starting — dumping plugin registry");

        // Create debug directory if needed
        File debugDir = new File(DEBUG_DIR);
        if (!debugDir.exists()) {
            debugDir.mkdirs();
        }

        // Dump immediately on start
        dumpRegistry();

        // Start the optional HTTP status server
        startHttpServer();

        logger.info("DebugBridge ready. Registry at: " + REGISTRY_FILE);
        logger.info("HTTP status at: http://localhost:" + HTTP_PORT + "/status");
    }

    @Override
    public void stop(Context context) {
        stopHttpServer();
        logger.info("DebugBridge stopped");
    }

    /**
     * Dumps the full plugin registry to JSON file.
     * Call this from anywhere via DebugBridge.dumpRegistry() (static).
     */
    public void dumpRegistry() {
        try {
            JSONObject root = new JSONObject();

            // Environment info
            JSONObject env = new JSONObject();
            env.put("timestamp", System.currentTimeMillis());
            env.put("discordVersion", Constants.DISCORD_VERSION);
            env.put("basePath", Constants.BASE_PATH);
            env.put("pluginsPath", Constants.PLUGINS_PATH);
            env.put("androidVersion", Build.VERSION.RELEASE);
            env.put("sdkInt", Build.VERSION.SDK_INT);
            env.put("safeMode", PluginManager.isSafeModeEnabled());
            root.put("environment", env);

            // Loaded plugins
            JSONArray loaded = new JSONArray();
            for (Map.Entry<String, Plugin> entry : PluginManager.plugins.entrySet()) {
                String name = entry.getKey();
                Plugin p = entry.getValue();
                JSONObject pObj = new JSONObject();
                pObj.put("name", name);
                pObj.put("enabled", PluginManager.isPluginEnabled(name));
                pObj.put("version", p.manifest != null ? p.manifest.version : "unknown");
                pObj.put("filename", p.__filename != null ? p.__filename : "unknown");
                pObj.put("isCorePlugin", p.getClass().getName().startsWith("com.aliucord.coreplugins"));
                loaded.put(pObj);
            }
            root.put("loadedPlugins", loaded);
            root.put("loadedCount", loaded.length());

            // Failed plugins
            JSONArray failed = new JSONArray();
            for (Map.Entry<File, Object> entry : PluginManager.failedToLoad.entrySet()) {
                JSONObject fObj = new JSONObject();
                fObj.put("file", entry.getKey().getName());
                Object err = entry.getValue();
                if (err instanceof Throwable) {
                    fObj.put("error", ((Throwable) err).getMessage());
                    fObj.put("errorType", err.getClass().getSimpleName());
                } else {
                    fObj.put("error", String.valueOf(err));
                }
                failed.put(fObj);
            }
            root.put("failedPlugins", failed);
            root.put("failedCount", failed.length());

            // Summary
            root.put("summary", PluginManager.getPluginsInfo());

            // Write to file
            try (FileWriter writer = new FileWriter(REGISTRY_FILE)) {
                writer.write(root.toString(2));
            }

            logger.info("Registry dumped: " + loaded.length() + " loaded, " + failed.length() + " failed");

        } catch (Exception e) {
            logger.error("Failed to dump registry", e);
        }
    }

    /**
     * Starts a minimal HTTP server for Termux to query.
     * Binds to 127.0.0.1 only — accessible only from the same device.
     */
    private void startHttpServer() {
        if (httpRunning.get()) return;

        httpThread = new Thread(() -> {
            try {
                serverSocket = new ServerSocket(HTTP_PORT, 5, InetAddress.getLoopbackAddress());
                httpRunning.set(true);
                logger.info("HTTP server listening on port " + HTTP_PORT);

                while (httpRunning.get() && !serverSocket.isClosed()) {
                    try {
                        Socket client = serverSocket.accept();
                        handleHttpRequest(client);
                    } catch (IOException e) {
                        if (httpRunning.get()) {
                            logger.error("HTTP accept error", e);
                        }
                    }
                }
            } catch (IOException e) {
                logger.error("Failed to start HTTP server on port " + HTTP_PORT + " (port in use?)", e);
            }
        }, "DebugBridge-HTTP");
        httpThread.setDaemon(true);
        httpThread.start();
    }

    private void handleHttpRequest(Socket client) {
        try (client;
             var in = client.getInputStream();
             var out = client.getOutputStream()) {

            // Read request line (very basic HTTP parsing)
            byte[] buf = new byte[4096];
            int read = in.read(buf);
            String request = new String(buf, 0, Math.max(0, read));

            String responseBody;
            String status;

            if (request.startsWith("GET /status")) {
                // Refresh the dump before responding
                dumpRegistry();
                try {
                    responseBody = new String(java.nio.file.Files.readAllBytes(
                            java.nio.file.Paths.get(REGISTRY_FILE)));
                } catch (Exception e) {
                    responseBody = "{\"error\": \"Failed to read registry file\"}";
                }
                status = "200 OK";
            } else if (request.startsWith("GET /plugins")) {
                // Lightweight: just list plugin names
                StringBuilder sb = new StringBuilder();
                for (String name : PluginManager.plugins.keySet()) {
                    boolean enabled = PluginManager.isPluginEnabled(name);
                    sb.append(name).append(enabled ? " [enabled]" : " [disabled]").append("\n");
                }
                responseBody = sb.toString();
                status = "200 OK";
            } else if (request.startsWith("GET /health")) {
                responseBody = "ok";
                status = "200 OK";
            } else {
                responseBody = "Endpoints: GET /status, GET /plugins, GET /health";
                status = "404 Not Found";
            }

            String contentType = request.startsWith("GET /plugins") ? "text/plain" : "application/json";
            String httpResponse = "HTTP/1.1 " + status + "\r\n" +
                    "Content-Type: " + contentType + "; charset=utf-8\r\n" +
                    "Content-Length: " + responseBody.getBytes().length + "\r\n" +
                    "Connection: close\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "\r\n" +
                    responseBody;

            out.write(httpResponse.getBytes());
            out.flush();
        } catch (Exception e) {
            logger.error("HTTP request handling error", e);
        }
    }

    private void stopHttpServer() {
        httpRunning.set(false);
        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
        } catch (IOException ignored) {}
        if (httpThread != null) {
            httpThread.interrupt();
        }
    }
}
