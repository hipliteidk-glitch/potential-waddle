package com.animenotify.app;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.Window;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;

/**
 * A small, dependency-free native Android airing calendar.
 * The interface is assembled in Java so the release APK stays lightweight.
 */
public final class MainActivity extends Activity {
    private static final int BG = Color.rgb(9, 10, 18);
    private static final int SURFACE = Color.rgb(20, 22, 33);
    private static final int SURFACE_2 = Color.rgb(27, 29, 43);
    private static final int PINK = Color.rgb(255, 50, 104);
    private static final int WHITE = Color.rgb(248, 248, 252);
    private static final int MUTED = Color.rgb(157, 159, 177);
    private static final int FAINT = Color.rgb(103, 105, 124);

    private final List<AnimeItem> schedule = new ArrayList<AnimeItem>();
    private final TextView[] navButtons = new TextView[3];
    private AniListClient client;
    private LinearLayout body;
    private LinearLayout cards;
    private EditText search;
    private TextView status;
    private TextView heroSummary;
    private int selectedDay = 0;
    private int page = 0;
    private int requestNumber = 0;
    private String currentStatus = "Live schedule • AniList";

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        Window window = getWindow();
        window.setStatusBarColor(BG);
        window.setNavigationBarColor(BG);
        if (Build.VERSION.SDK_INT >= 23) {
            window.getDecorView().setSystemUiVisibility(0);
        }
        client = new AniListClient(this);
        ReminderReceiver.createChannel(this);
        setContentView(buildAppShell());
        if (getIntent().getBooleanExtra("open_reminders", false)) {
            navigate(1);
        } else {
            navigate(0);
        }
    }

    private View buildAppShell() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.addView(buildHeader(), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(74)));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(18), dp(8), dp(18), dp(28));
        scroll.addView(body, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        root.addView(buildBottomNav(), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(68)));
        if (Build.VERSION.SDK_INT >= 21) {
            root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
                @Override public android.view.WindowInsets onApplyWindowInsets(
                        View view, android.view.WindowInsets insets) {
                    view.setPadding(0, insets.getSystemWindowInsetTop(), 0,
                            insets.getSystemWindowInsetBottom());
                    return insets;
                }
            });
        }
        return root;
    }

    private View buildHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(18), dp(6), dp(12), 0);

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.ic_launcher);
        logo.setContentDescription("AnimeNotify logo");
        header.addView(logo, new LinearLayout.LayoutParams(dp(45), dp(45)));

        LinearLayout names = new LinearLayout(this);
        names.setOrientation(LinearLayout.VERTICAL);
        names.setPadding(dp(10), 0, 0, 0);
        TextView title = text("AnimeNotify", 20, WHITE, true);
        title.setLetterSpacing(-0.02f);
        names.addView(title);
        TextView subtitle = text("AIRING CALENDAR", 9, PINK, true);
        subtitle.setLetterSpacing(0.18f);
        names.addView(subtitle);
        header.addView(names, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView settingsButton = text("•••", 18, WHITE, true);
        settingsButton.setGravity(Gravity.CENTER);
        settingsButton.setContentDescription("Reminder settings");
        settingsButton.setBackground(round(SURFACE, 18));
        settingsButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { showSettings(); }
        });
        header.addView(settingsButton, new LinearLayout.LayoutParams(dp(44), dp(38)));
        return header;
    }

    private View buildBottomNav() {
        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER);
        bar.setPadding(dp(12), dp(6), dp(12), dp(8));
        bar.setBackgroundColor(Color.rgb(12, 13, 22));
        String[] labels = {"SCHEDULE", "MY ALERTS", "ABOUT"};
        String[] symbols = {"▦", "●", "✦"};
        for (int i = 0; i < labels.length; i++) {
            final int destination = i;
            TextView button = text(symbols[i] + "\n" + labels[i], 10, FAINT, true);
            button.setGravity(Gravity.CENTER);
            button.setLetterSpacing(0.08f);
            button.setContentDescription(labels[i]);
            button.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) { navigate(destination); }
            });
            navButtons[i] = button;
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(52), 1f);
            params.setMargins(dp(3), 0, dp(3), 0);
            bar.addView(button, params);
        }
        return bar;
    }

    private void navigate(int destination) {
        page = destination;
        for (int i = 0; i < navButtons.length; i++) {
            boolean selected = i == destination;
            navButtons[i].setTextColor(selected ? PINK : FAINT);
            navButtons[i].setBackground(selected ? round(Color.rgb(32, 20, 36), 16) : null);
        }
        if (destination == 0) buildSchedulePage();
        else if (destination == 1) buildRemindersPage();
        else buildAboutPage();
    }

    private void buildSchedulePage() {
        body.removeAllViews();
        body.addView(buildHero(), matchWrap(dp(194), dp(12)));

        LinearLayout heading = new LinearLayout(this);
        heading.setGravity(Gravity.CENTER_VERTICAL);
        TextView label = text("NEXT 7 DAYS", 12, WHITE, true);
        label.setLetterSpacing(0.12f);
        heading.addView(label, new LinearLayout.LayoutParams(0, dp(42), 1f));
        TextView local = text("LOCAL TIME", 10, FAINT, true);
        local.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
        heading.addView(local, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, dp(42)));
        body.addView(heading);
        body.addView(buildDayPicker(), matchWrap(dp(66), dp(14)));
        body.addView(buildSearch(), matchWrap(dp(50), dp(14)));

        LinearLayout statusRow = new LinearLayout(this);
        statusRow.setGravity(Gravity.CENTER_VERTICAL);
        status = text(currentStatus, 11, MUTED, false);
        statusRow.addView(status, new LinearLayout.LayoutParams(0, dp(36), 1f));
        TextView refresh = text("↻  REFRESH", 10, WHITE, true);
        refresh.setGravity(Gravity.CENTER);
        refresh.setBackground(round(SURFACE_2, 14));
        refresh.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { loadSchedule(); }
        });
        statusRow.addView(refresh, new LinearLayout.LayoutParams(dp(92), dp(32)));
        body.addView(statusRow);

        cards = new LinearLayout(this);
        cards.setOrientation(LinearLayout.VERTICAL);
        body.addView(cards, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        if (schedule.isEmpty()) loadSchedule();
        else renderCards();
    }

    private View buildHero() {
        FrameLayout hero = new FrameLayout(this);
        GradientDrawable background = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[]{Color.rgb(64, 18, 69), Color.rgb(22, 26, 59), Color.rgb(30, 17, 48)});
        background.setCornerRadius(dp(24));
        hero.setBackground(background);
        hero.setClipToOutline(true);
        hero.setOutlineProvider(new RoundedOutline(dp(24)));

        RingDecoration rings = new RingDecoration(this);
        FrameLayout.LayoutParams ringParams = new FrameLayout.LayoutParams(dp(210), dp(194));
        ringParams.gravity = Gravity.RIGHT | Gravity.CENTER_VERTICAL;
        hero.addView(rings, ringParams);

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setGravity(Gravity.CENTER_VERTICAL);
        copy.setPadding(dp(22), dp(18), dp(12), dp(18));
        TextView badge = text("✦  YOUR AIRING COMPANION", 9, Color.rgb(255, 173, 198), true);
        badge.setLetterSpacing(0.13f);
        copy.addView(badge);
        TextView title = text("Never miss a\nnew episode.", 27, WHITE, true);
        title.setLineSpacing(0, 0.94f);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(11);
        copy.addView(title, titleParams);
        heroSummary = text(reminderSummary(), 11, Color.rgb(205, 203, 218), false);
        LinearLayout.LayoutParams summaryParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        summaryParams.topMargin = dp(12);
        copy.addView(heroSummary, summaryParams);
        hero.addView(copy, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        return hero;
    }

    private String reminderSummary() {
        int count = ReminderStore.all(this).size();
        if (count == 0) return "Tap a bell to build your watchlist";
        return count + (count == 1 ? " show" : " shows") + " followed  •  " +
                ReminderStore.leadMinutes(this) + " min alerts";
    }

    private View buildDayPicker() {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout days = new LinearLayout(this);
        days.setOrientation(LinearLayout.HORIZONTAL);
        Calendar date = Calendar.getInstance();
        SimpleDateFormat nameFormat = new SimpleDateFormat("EEE", Locale.getDefault());
        SimpleDateFormat dateFormat = new SimpleDateFormat("dd", Locale.getDefault());
        for (int i = 0; i < 7; i++) {
            final int offset = i;
            boolean selected = i == selectedDay;
            String top = i == 0 ? "TODAY" : nameFormat.format(date.getTime()).toUpperCase(Locale.getDefault());
            TextView chip = text(top + "\n" + dateFormat.format(date.getTime()),
                    10, selected ? WHITE : MUTED, true);
            chip.setGravity(Gravity.CENTER);
            chip.setLineSpacing(0, 1.1f);
            chip.setBackground(round(selected ? PINK : SURFACE, 16));
            chip.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) {
                    selectedDay = offset;
                    schedule.clear();
                    buildSchedulePage();
                }
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(62), dp(60));
            params.setMargins(0, 0, dp(8), 0);
            days.addView(chip, params);
            date.add(Calendar.DAY_OF_MONTH, 1);
        }
        scroll.addView(days, new HorizontalScrollView.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT));
        return scroll;
    }

    private View buildSearch() {
        search = new EditText(this);
        search.setSingleLine(true);
        search.setTextSize(14);
        search.setTextColor(WHITE);
        search.setHintTextColor(FAINT);
        search.setHint("Search today's lineup");
        search.setPadding(dp(14), 0, dp(14), 0);
        search.setBackground(round(SURFACE, 16));
        search.setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0);
        search.setCompoundDrawablePadding(dp(10));
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { renderCards(); }
            @Override public void afterTextChanged(Editable editable) { }
        });
        return search;
    }

    private void loadSchedule() {
        if (cards == null) return;
        final int thisRequest = ++requestNumber;
        cards.removeAllViews();
        status.setText("Syncing the airing calendar…");
        status.setTextColor(MUTED);
        showLoadingRows();
        final Calendar date = Calendar.getInstance();
        date.add(Calendar.DAY_OF_MONTH, selectedDay);
        client.fetchDay(date, new AniListClient.Callback() {
            @Override public void onResult(final List<AnimeItem> items, final boolean live,
                                           final String message) {
                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        if (thisRequest != requestNumber || page != 0) return;
                        schedule.clear();
                        schedule.addAll(items);
                        currentStatus = message;
                        status.setText(message);
                        status.setTextColor(live ? Color.rgb(108, 213, 173) : Color.rgb(255, 187, 92));
                        renderCards();
                    }
                });
            }
        });
    }

    private void showLoadingRows() {
        for (int i = 0; i < 3; i++) {
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(12), dp(10), dp(12), dp(10));
            row.setBackground(round(SURFACE, 18));
            View cover = new View(this);
            cover.setBackground(round(Color.rgb(35, 37, 51), 12));
            row.addView(cover, new LinearLayout.LayoutParams(dp(78), dp(100)));
            LinearLayout lines = new LinearLayout(this);
            lines.setOrientation(LinearLayout.VERTICAL);
            lines.setPadding(dp(14), 0, 0, 0);
            for (int j = 0; j < 3; j++) {
                View line = new View(this);
                line.setBackground(round(Color.rgb(40, 42, 57), 4));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        j == 1 ? dp(150) : dp(90), dp(j == 1 ? 13 : 9));
                lp.setMargins(0, dp(6), 0, dp(6));
                lines.addView(line, lp);
            }
            row.addView(lines, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            LinearLayout.LayoutParams params = matchWrap(dp(120), dp(10));
            cards.addView(row, params);
        }
    }

    private void renderCards() {
        if (cards == null) return;
        cards.removeAllViews();
        String filter = search == null ? "" : search.getText().toString().trim().toLowerCase(Locale.getDefault());
        int shown = 0;
        for (AnimeItem item : schedule) {
            if (filter.length() > 0 && !item.title.toLowerCase(Locale.getDefault()).contains(filter)) continue;
            cards.addView(createAnimeCard(item), matchWrap(dp(142), dp(12)));
            shown++;
        }
        if (shown == 0) {
            LinearLayout empty = emptyState("No episodes found",
                    filter.length() > 0 ? "Try a different title." : "Check another day in the schedule.", "↻  REFRESH");
            if (filter.length() == 0) {
                empty.setOnClickListener(new View.OnClickListener() {
                    @Override public void onClick(View view) { loadSchedule(); }
                });
            }
            cards.addView(empty, matchWrap(dp(180), dp(16)));
        }
    }

    private View createAnimeCard(final AnimeItem item) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(8), dp(8), dp(9), dp(8));
        card.setBackground(round(SURFACE, 19));

        FrameLayout coverFrame = new FrameLayout(this);
        int coverColor = safeColor(item.accentColor, item.mediaId);
        coverFrame.setBackground(round(coverColor, 13));
        coverFrame.setClipToOutline(true);
        coverFrame.setOutlineProvider(new RoundedOutline(dp(13)));
        TextView monogram = text(item.preview ? "PREVIEW" : "AN", item.preview ? 8 : 16,
                Color.argb(205, 255, 255, 255), true);
        monogram.setGravity(Gravity.CENTER);
        coverFrame.addView(monogram, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        ImageView cover = new ImageView(this);
        cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
        cover.setContentDescription(item.title + " cover");
        coverFrame.addView(cover, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        if (!item.preview) ImageLoader.load(item.imageUrl, cover);
        card.addView(coverFrame, new LinearLayout.LayoutParams(dp(86), dp(126)));

        LinearLayout details = new LinearLayout(this);
        details.setOrientation(LinearLayout.VERTICAL);
        details.setGravity(Gravity.CENTER_VERTICAL);
        details.setPadding(dp(13), dp(2), dp(8), dp(2));
        TextView kind = text(item.preview ? "OFFLINE PREVIEW" : item.format, 9,
                item.preview ? Color.rgb(255, 187, 92) : PINK, true);
        kind.setLetterSpacing(0.12f);
        details.addView(kind);
        TextView title = text(item.title, 16, WHITE, true);
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.topMargin = dp(5);
        details.addView(title, titleParams);

        TextView metadata = text(item.timeLabel() + "  •  " + item.episodeLabel(), 11, MUTED, false);
        LinearLayout.LayoutParams metaParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        metaParams.topMargin = dp(8);
        details.addView(metadata, metaParams);
        String lower = timeUntil(item.airingAt);
        TextView countdown = text(lower, 10, FAINT, false);
        LinearLayout.LayoutParams countParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        countParams.topMargin = dp(5);
        details.addView(countdown, countParams);
        card.addView(details, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.MATCH_PARENT, 1f));

        boolean followed = !item.preview && ReminderStore.contains(this, item.mediaId);
        if (followed) {
            ReminderStore.SavedReminder before = ReminderStore.find(this, item.mediaId);
            if (before != null && item.airingAt > before.airingAt) {
                ReminderStore.refresh(this, item);
                AlarmScheduler.schedule(this, ReminderStore.find(this, item.mediaId));
            }
        }
        ImageView bell = new ImageView(this);
        bell.setImageResource(followed ? R.drawable.ic_bell_active : R.drawable.ic_bell);
        bell.setPadding(dp(12), dp(12), dp(12), dp(12));
        bell.setBackground(round(followed ? PINK : SURFACE_2, 19));
        bell.setContentDescription(followed ? "Remove reminder" : "Add reminder");
        bell.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { toggleReminder(item); }
        });
        card.addView(bell, new LinearLayout.LayoutParams(dp(42), dp(42)));

        if (!item.preview) {
            card.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) { openAniList(item.mediaId); }
            });
            bell.setClickable(true);
        }
        return card;
    }

    private void toggleReminder(AnimeItem item) {
        if (item.preview) {
            Toast.makeText(this, "Connect and refresh before following a title", Toast.LENGTH_SHORT).show();
            return;
        }
        if (ReminderStore.contains(this, item.mediaId)) {
            ReminderStore.remove(this, item.mediaId);
            AlarmScheduler.cancel(this, item.mediaId);
            Toast.makeText(this, "Reminder removed", Toast.LENGTH_SHORT).show();
        } else {
            ReminderStore.SavedReminder saved = ReminderStore.add(this, item);
            AlarmScheduler.schedule(this, saved);
            requestNotificationPermission();
            Toast.makeText(this, "We'll remind you " + ReminderStore.leadMinutes(this) +
                    " minutes before", Toast.LENGTH_SHORT).show();
        }
        if (heroSummary != null) heroSummary.setText(reminderSummary());
        if (page == 0) renderCards();
        else buildRemindersPage();
    }

    private void buildRemindersPage() {
        body.removeAllViews();
        TextView eyebrow = text("YOUR WATCHLIST", 10, PINK, true);
        eyebrow.setLetterSpacing(0.16f);
        body.addView(eyebrow, matchWrap(dp(27), 0));
        TextView title = text("My alerts", 29, WHITE, true);
        body.addView(title);
        TextView intro = text("A gentle nudge before every followed show airs.", 13, MUTED, false);
        LinearLayout.LayoutParams introParams = matchWrap(dp(42), dp(15));
        body.addView(intro, introParams);

        final List<ReminderStore.SavedReminder> reminders = ReminderStore.all(this);
        LinearLayout summary = new LinearLayout(this);
        summary.setGravity(Gravity.CENTER_VERTICAL);
        summary.setPadding(dp(16), 0, dp(16), 0);
        summary.setBackground(round(Color.rgb(31, 19, 39), 16));
        TextView count = text(reminders.size() + (reminders.size() == 1 ? " TITLE FOLLOWED" : " TITLES FOLLOWED"),
                10, Color.rgb(255, 173, 198), true);
        count.setLetterSpacing(0.1f);
        summary.addView(count, new LinearLayout.LayoutParams(0, dp(48), 1f));
        TextView timing = text(ReminderStore.leadMinutes(this) + " MIN BEFORE", 10, WHITE, true);
        summary.addView(timing);
        body.addView(summary, matchWrap(dp(48), dp(15)));

        if (reminders.isEmpty()) {
            LinearLayout empty = emptyState("No reminders yet",
                    "Open the schedule and tap a bell beside a show you love.", "BROWSE SCHEDULE");
            empty.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) { navigate(0); }
            });
            body.addView(empty, matchWrap(dp(230), dp(14)));
        } else {
            for (ReminderStore.SavedReminder saved : reminders) {
                long airing = saved.airingAt;
                int episode = saved.episode;
                long now = System.currentTimeMillis() / 1000L;
                while (airing <= now) {
                    airing += 7L * 24L * 60L * 60L;
                    if (episode > 0) episode++;
                }
                AnimeItem item = new AnimeItem(saved.mediaId, saved.mediaId, saved.title,
                        saved.imageUrl, "#8B5CF6", 0, "FOLLOWING", episode, airing, false);
                body.addView(createAnimeCard(item), matchWrap(dp(142), dp(12)));
            }
        }
        TextView note = text("Reminders are stored only on this device. Approximate delivery helps save battery.",
                11, FAINT, false);
        note.setGravity(Gravity.CENTER);
        note.setLineSpacing(dp(3), 1f);
        body.addView(note, matchWrap(dp(70), dp(10)));
    }

    private void buildAboutPage() {
        body.removeAllViews();
        LinearLayout logoRow = new LinearLayout(this);
        logoRow.setGravity(Gravity.CENTER_VERTICAL);
        logoRow.setPadding(dp(2), dp(12), dp(2), dp(20));
        ImageView mark = new ImageView(this);
        mark.setImageResource(R.drawable.ic_launcher);
        logoRow.addView(mark, new LinearLayout.LayoutParams(dp(72), dp(72)));
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(15), 0, 0, 0);
        copy.addView(text("AnimeNotify", 25, WHITE, true));
        copy.addView(text("Version 1.0.0  •  lightweight native app", 11, MUTED, false));
        logoRow.addView(copy);
        body.addView(logoRow);

        body.addView(infoPanel("MADE FOR FANS",
                "A focused weekly anime calendar with one-tap local reminders. No sign-in, no ads and no noisy social feed."),
                matchWrap(0, dp(12)));
        body.addView(infoPanel("HOW IT WORKS",
                "Public airing times and cover art come from AniList. Times are converted to your device timezone and cached for offline viewing."),
                matchWrap(0, dp(12)));
        body.addView(infoPanel("PRIVACY",
                "Your followed titles stay in local app storage. AnimeNotify sends only a public schedule request; it does not create a profile or collect analytics."),
                matchWrap(0, dp(12)));

        TextView source = text("OPEN ANILIST", 11, WHITE, true);
        source.setGravity(Gravity.CENTER);
        source.setBackground(round(PINK, 17));
        source.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { openUrl("https://anilist.co"); }
        });
        body.addView(source, matchWrap(dp(50), dp(18)));
        TextView legal = text("AnimeNotify is an independent fan utility and is not affiliated with AniList or any anime publisher.",
                10, FAINT, false);
        legal.setGravity(Gravity.CENTER);
        body.addView(legal, matchWrap(dp(62), dp(8)));
    }

    private View infoPanel(String titleValue, String description) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(18), dp(17), dp(18), dp(17));
        panel.setBackground(round(SURFACE, 18));
        TextView title = text(titleValue, 10, PINK, true);
        title.setLetterSpacing(0.13f);
        panel.addView(title);
        TextView copy = text(description, 13, Color.rgb(194, 195, 207), false);
        copy.setLineSpacing(dp(4), 1f);
        LinearLayout.LayoutParams lp = matchWrap(0, dp(8));
        panel.addView(copy, lp);
        return panel;
    }

    private LinearLayout emptyState(String titleValue, String description, String action) {
        LinearLayout empty = new LinearLayout(this);
        empty.setOrientation(LinearLayout.VERTICAL);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(24), dp(18), dp(24), dp(18));
        empty.setBackground(round(SURFACE, 20));
        TextView symbol = text("✦", 25, PINK, true);
        empty.addView(symbol);
        TextView title = text(titleValue, 18, WHITE, true);
        LinearLayout.LayoutParams titleParams = matchWrap(0, dp(7));
        empty.addView(title, titleParams);
        TextView copy = text(description, 12, MUTED, false);
        copy.setGravity(Gravity.CENTER);
        copy.setMaxLines(3);
        empty.addView(copy);
        TextView link = text(action, 10, PINK, true);
        link.setLetterSpacing(0.12f);
        LinearLayout.LayoutParams linkParams = matchWrap(0, dp(14));
        empty.addView(link, linkParams);
        return empty;
    }

    private void showSettings() {
        final AlertDialog dialog = new AlertDialog.Builder(this).create();
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(22), dp(22), dp(22), dp(20));
        panel.setBackground(round(Color.rgb(20, 22, 33), 24));
        panel.addView(text("Reminder settings", 22, WHITE, true));
        TextView subtitle = text("Choose how early AnimeNotify should tap you on the shoulder.", 12, MUTED, false);
        subtitle.setLineSpacing(dp(3), 1f);
        panel.addView(subtitle, matchWrap(dp(52), dp(6)));
        TextView label = text("NOTIFY ME", 9, PINK, true);
        label.setLetterSpacing(0.14f);
        panel.addView(label, matchWrap(dp(28), dp(4)));

        LinearLayout choices = new LinearLayout(this);
        int[] minutes = {5, 15, 30};
        for (int i = 0; i < minutes.length; i++) {
            final int value = minutes[i];
            boolean selected = ReminderStore.leadMinutes(this) == value;
            TextView choice = text(value + " min", 12, selected ? WHITE : MUTED, true);
            choice.setGravity(Gravity.CENTER);
            choice.setBackground(round(selected ? PINK : SURFACE_2, 15));
            choice.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) {
                    ReminderStore.setLeadMinutes(MainActivity.this, value);
                    AlarmScheduler.rescheduleAll(MainActivity.this);
                    dialog.dismiss();
                    showSettings();
                    if (page == 1) buildRemindersPage();
                }
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(46), 1f);
            lp.setMargins(i == 0 ? 0 : dp(4), 0, i == 2 ? 0 : dp(4), 0);
            choices.addView(choice, lp);
        }
        panel.addView(choices, matchWrap(dp(46), dp(7)));

        TextView test = text("●  SEND A TEST NOTIFICATION", 10, WHITE, true);
        test.setGravity(Gravity.CENTER);
        test.setBackground(round(Color.rgb(39, 31, 57), 16));
        test.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                if (requestNotificationPermission()) {
                    ReminderReceiver.showNotification(MainActivity.this, 90001,
                            "AnimeNotify", 0, true);
                    Toast.makeText(MainActivity.this, "Test notification sent", Toast.LENGTH_SHORT).show();
                }
            }
        });
        panel.addView(test, matchWrap(dp(48), dp(18)));

        TextView system = text("OPEN SYSTEM NOTIFICATION SETTINGS", 10, MUTED, true);
        system.setGravity(Gravity.CENTER);
        system.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
                try { startActivity(intent); } catch (Exception ignored) { }
            }
        });
        panel.addView(system, matchWrap(dp(42), dp(5)));
        dialog.setView(panel);
        dialog.setOnShowListener(new android.content.DialogInterface.OnShowListener() {
            @Override public void onShow(android.content.DialogInterface value) {
                if (dialog.getWindow() != null) {
                    dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
                    dialog.getWindow().setDimAmount(0.72f);
                }
            }
        });
        dialog.show();
    }

    /** Returns true when a notification can be posted immediately. */
    private boolean requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 47);
            Toast.makeText(this, "Allow notifications, then try again", Toast.LENGTH_SHORT).show();
            return false;
        }
        return true;
    }

    private void openAniList(int mediaId) {
        openUrl("https://anilist.co/anime/" + mediaId);
    }

    private void openUrl(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (ActivityNotFoundException error) {
            Toast.makeText(this, "No browser is available", Toast.LENGTH_SHORT).show();
        }
    }

    private String timeUntil(long seconds) {
        long difference = seconds - System.currentTimeMillis() / 1000L;
        if (difference <= 0) return "Airing now";
        long hours = difference / 3600L;
        if (hours < 1) return "In " + Math.max(1, difference / 60L) + " min";
        if (hours < 24) return "In " + hours + (hours == 1 ? " hour" : " hours");
        long days = hours / 24L;
        return "In " + days + (days == 1 ? " day" : " days");
    }

    private int safeColor(String value, int seed) {
        if (value != null && value.startsWith("#")) {
            try {
                int parsed = Color.parseColor(value);
                return Color.rgb((Color.red(parsed) + 20) / 2,
                        (Color.green(parsed) + 20) / 2,
                        (Color.blue(parsed) + 28) / 2);
            } catch (Exception ignored) { }
        }
        int[] colors = {Color.rgb(58, 30, 68), Color.rgb(24, 53, 72),
                Color.rgb(66, 38, 44), Color.rgb(42, 40, 78)};
        return colors[Math.abs(seed) % colors.length];
    }

    private TextView text(String value, float size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER_VERTICAL);
        view.setTypeface(Typeface.create("sans", bold ? Typeface.BOLD : Typeface.NORMAL));
        view.setIncludeFontPadding(false);
        return view;
    }

    private GradientDrawable round(int color, float radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private LinearLayout.LayoutParams matchWrap(int heightDp, int bottomDp) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                heightDp == 0 ? ViewGroup.LayoutParams.WRAP_CONTENT : heightDp);
        params.bottomMargin = bottomDp;
        return params;
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private final class RoundedOutline extends ViewOutlineProvider {
        private final int radius;
        RoundedOutline(int radius) { this.radius = radius; }
        @Override public void getOutline(View view, android.graphics.Outline outline) {
            outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
        }
    }

    /** Decorative O-shaped orbital mark used in the hero. */
    private static final class RingDecoration extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF oval = new RectF();
        RingDecoration(android.content.Context context) { super(context); }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float cx = getWidth() * 0.66f;
            float cy = getHeight() * 0.5f;
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setColor(Color.argb(95, 255, 50, 104));
            paint.setStrokeWidth(getWidth() * 0.055f);
            float r = getHeight() * 0.40f;
            oval.set(cx - r, cy - r, cx + r, cy + r);
            canvas.drawArc(oval, -62, 286, false, paint);
            paint.setColor(Color.argb(150, 139, 92, 246));
            paint.setStrokeWidth(getWidth() * 0.038f);
            r = getHeight() * 0.27f;
            oval.set(cx - r, cy - r, cx + r, cy + r);
            canvas.drawArc(oval, 30, 286, false, paint);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(Color.argb(60, 255, 255, 255));
            canvas.drawCircle(cx + getHeight() * .31f, cy - getHeight() * .26f,
                    getHeight() * .025f, paint);
        }
    }
}
