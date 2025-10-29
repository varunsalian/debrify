package com.debrify.app.tv;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.DefaultTimeBar;
import androidx.media3.ui.PlayerView;

import com.debrify.app.MainActivity;
import com.debrify.app.R;

import java.util.ArrayList;
import java.util.Locale;
import java.util.Map;
import java.util.Random;

import io.flutter.plugin.common.MethodChannel;

/**
 * Android TV playback activity that streams Torbox content through ExoPlayer.
 *
 * A long press on the center (OK) button requests the next Torbox stream from Flutter.
 */
public class TorboxTvPlayerActivity extends AppCompatActivity {

    private static final String HINT_DEFAULT = "Long press OK to play next";
    private static final String HINT_LOADING = "Loading next stream...";
    private static final long SEEK_STEP_MS = 10_000L;

    private PlayerView playerView;
    private ExoPlayer player;
    private TextView titleView;
    private TextView hintView;
    private TextView watermarkView;
    private ArrayList<Bundle> magnetQueue = new ArrayList<>();

    private boolean startFromRandom;
    private int randomMaxPercent;
    private boolean hideSeekbar;
    private boolean hideOptions;
    private boolean showVideoTitle;
    private boolean showWatermark;
    private boolean hideBackButton;

    private boolean randomApplied = false;
    private boolean requestingNext = false;
    private boolean finishedNotified = false;
    private boolean longPressHandled = false;
    private int playedCount = 0;

    private final Random random = new Random();

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_torbox_tv_player);

        playerView = findViewById(R.id.player_view);
        titleView = findViewById(R.id.player_title);
        hintView = findViewById(R.id.player_hint);
        watermarkView = findViewById(R.id.player_watermark);

        Intent intent = getIntent();
        String initialUrl = intent.getStringExtra("initialUrl");
        String initialTitle = intent.getStringExtra("initialTitle");
        ArrayList<Bundle> extrasList;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extrasList = intent.getParcelableArrayListExtra("magnetList", Bundle.class);
        } else {
            extrasList = intent.getParcelableArrayListExtra("magnetList");
        }
        if (extrasList != null) {
            magnetQueue = extrasList;
        }

        startFromRandom = intent.getBooleanExtra("startFromRandom", false);
        randomMaxPercent = intent.getIntExtra("randomStartMaxPercent", 40);
        hideSeekbar = intent.getBooleanExtra("hideSeekbar", false);
        hideOptions = intent.getBooleanExtra("hideOptions", false);
        showVideoTitle = intent.getBooleanExtra("showVideoTitle", true);
        showWatermark = intent.getBooleanExtra("showWatermark", false);
        hideBackButton = intent.getBooleanExtra("hideBackButton", false);

        if (initialUrl == null || initialUrl.isEmpty()) {
            Toast.makeText(this, "Missing stream URL", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        initialisePlayer();
        applyUiPreferences(initialTitle);
        setupControllerUi();

        hintView.setText(buildDefaultHint());
        playMedia(initialUrl, initialTitle);
    }

    private void initialisePlayer() {
        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        playerView.setKeepScreenOn(true);
        playerView.setUseController(true);
        playerView.setControllerAutoShow(true);
        playerView.setControllerShowTimeoutMs(5000);
        playerView.requestFocus();

        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                if (playbackState == Player.STATE_READY) {
                    if (startFromRandom && !randomApplied) {
                        maybeSeekRandomly();
                    }
                    setHintDefault();
                } else if (playbackState == Player.STATE_ENDED) {
                    randomApplied = false;
                    requestNextStream();
                }
            }
        });
    }

    private void applyUiPreferences(@Nullable String initialTitle) {
        if (showVideoTitle) {
            titleView.setVisibility(View.VISIBLE);
            titleView.setText(initialTitle != null ? initialTitle : "");
        } else {
            titleView.setVisibility(View.GONE);
        }

        if (showWatermark) {
            watermarkView.setVisibility(View.VISIBLE);
        } else {
            watermarkView.setVisibility(View.GONE);
        }
    }

    private void setupControllerUi() {
        View controlsRoot = playerView.findViewById(R.id.debrify_controls_root);
        DefaultTimeBar timeBar = playerView.findViewById(androidx.media3.ui.R.id.exo_progress);
        View nextButton = playerView.findViewById(R.id.debrify_next_button);

        if (controlsRoot != null) {
            controlsRoot.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
        }

        View buttonsRow = playerView.findViewById(R.id.debrify_controls_buttons);
        if (buttonsRow != null) {
            buttonsRow.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
        }

        if (nextButton != null) {
            nextButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            nextButton.setOnClickListener(v -> {
                requestNextStream();
                if (!hideOptions) {
                    playerView.showController();
                }
            });
        }

        if (timeBar != null) {
            timeBar.setVisibility(hideSeekbar ? View.GONE : View.VISIBLE);
            int red = ContextCompat.getColor(this, R.color.debrify_red);
            int faded = ContextCompat.getColor(this, R.color.tv_seek_background);
            timeBar.setPlayedColor(red);
            timeBar.setScrubberColor(red);
            timeBar.setBufferedColor(faded);
            timeBar.setUnplayedColor(faded);
        }

        if (hideOptions) {
            playerView.setUseController(false);
            playerView.hideController();
        } else {
            playerView.setUseController(true);
            playerView.setControllerAutoShow(true);
            playerView.setControllerShowTimeoutMs(5000);
            playerView.showController();
        }
    }

    private void playMedia(String url, @Nullable String title) {
        if (player == null || url == null || url.isEmpty()) {
            return;
        }
        randomApplied = false;
        MediaMetadata metadata = new MediaMetadata.Builder()
                .setTitle(title != null ? title : "")
                .build();
        MediaItem item = new MediaItem.Builder()
                .setUri(url)
                .setMediaMetadata(metadata)
                .build();
        player.setMediaItem(item);
        player.prepare();
        player.play();
        playedCount += 1;
        updateTitle(title);
        setHintDefault();
    }

    private void updateTitle(@Nullable String title) {
        if (showVideoTitle && titleView != null) {
            titleView.setText(title != null ? title : "");
        }
    }

    private void maybeSeekRandomly() {
        if (player == null) {
            return;
        }
        long duration = player.getDuration();
        if (duration <= 0) {
            return;
        }
        int percent = Math.max(0, Math.min(randomMaxPercent, 90));
        long maxOffset = (duration * percent) / 100L;
        if (maxOffset <= 0) {
            return;
        }
        long offset = (long) (random.nextDouble() * (double) maxOffset);
        if (offset > 0) {
            player.seekTo(offset);
        }
        randomApplied = true;
    }

    private void requestNextStream() {
        if (requestingNext) {
            return;
        }
        MethodChannel channel = MainActivity.getAndroidTvPlayerChannel();
        if (channel == null) {
            Toast.makeText(this, "Playback bridge unavailable", Toast.LENGTH_SHORT).show();
            return;
        }
        requestingNext = true;
        runOnUiThread(() -> hintView.setText(HINT_LOADING));
        channel.invokeMethod("requestTorboxNext", null, new MethodChannel.Result() {
            @Override
            public void success(@Nullable Object result) {
                requestingNext = false;
                if (!(result instanceof Map)) {
                    handleNoMoreStreams();
                    return;
                }
                @SuppressWarnings("unchecked")
                Map<String, Object> payload = (Map<String, Object>) result;
                String nextUrl = safeString(payload.get("url"));
                String nextTitle = safeString(payload.get("title"));
                if (nextUrl == null || nextUrl.isEmpty()) {
                    handleNoMoreStreams();
                    return;
                }
                playMedia(nextUrl, nextTitle);
            }

            @Override
            public void error(String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
                requestingNext = false;
                Toast.makeText(TorboxTvPlayerActivity.this,
                        errorMessage != null ? errorMessage : "Failed to load next stream",
                        Toast.LENGTH_SHORT).show();
                setHintDefault();
            }

            @Override
            public void notImplemented() {
                requestingNext = false;
                setHintDefault();
            }
        });
    }

    private void handleNoMoreStreams() {
        runOnUiThread(() -> {
            Toast.makeText(TorboxTvPlayerActivity.this,
                    "No more Torbox streams available",
                    Toast.LENGTH_SHORT).show();
            finish();
        });
    }

    private void setHintDefault() {
        if (hintView == null) {
            return;
        }
        hintView.setText(buildDefaultHint());
    }

    private String buildDefaultHint() {
        int queueSize = magnetQueue != null ? magnetQueue.size() : 0;
        int remaining = Math.max(0, queueSize - playedCount);
        if (remaining > 0) {
            return String.format(Locale.US, "%s (%d left)", HINT_DEFAULT, remaining);
        }
        return HINT_DEFAULT;
    }

    @Nullable
    private String safeString(@Nullable Object value) {
        if (value == null) {
            return null;
        }
        String str = value.toString();
        return str != null ? str.trim() : null;
    }

    private void togglePlayPause() {
        if (player == null) {
            return;
        }
        if (player.isPlaying()) {
            player.pause();
        } else {
            player.play();
        }
    }

    private void seekBy(long offsetMs) {
        if (player == null) {
            return;
        }
        long position = player.getCurrentPosition();
        long duration = player.getDuration();
        long target = position + offsetMs;
        if (duration != C.TIME_UNSET) {
            target = Math.max(0L, Math.min(target, duration));
        } else {
            target = Math.max(0L, target);
        }
        player.seekTo(target);
        if (playerView != null) {
            playerView.hideController();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (event.getRepeatCount() >= 2) {
                if (!longPressHandled) {
                    longPressHandled = true;
                    requestNextStream();
                }
                return true;
            }
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (!longPressHandled) {
                togglePlayPause();
            }
            longPressHandled = false;
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int keyCode = event.getKeyCode();
        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
            if (playerView != null && playerView.isControllerFullyVisible()) {
                return super.dispatchKeyEvent(event);
            }
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                seekBy(keyCode == KeyEvent.KEYCODE_DPAD_RIGHT ? SEEK_STEP_MS : -SEEK_STEP_MS);
                return true;
            }
            if (event.getAction() == KeyEvent.ACTION_UP) {
                return true;
            }
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (player != null && player.isPlaying()) {
            player.pause();
        }
    }

    @Override
    protected void onDestroy() {
        if (player != null) {
            player.stop();
            player.release();
            player = null;
        }
        notifyFlutterPlaybackFinished();
        super.onDestroy();
    }

    private void notifyFlutterPlaybackFinished() {
        if (finishedNotified) {
            return;
        }
        finishedNotified = true;
        MethodChannel channel = MainActivity.getAndroidTvPlayerChannel();
        if (channel != null) {
            try {
                channel.invokeMethod("torboxPlaybackFinished", null);
            } catch (Exception ignored) {
            }
        }
    }
}
