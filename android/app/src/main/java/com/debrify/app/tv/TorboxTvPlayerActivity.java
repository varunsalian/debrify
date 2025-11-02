package com.debrify.app.tv;

import android.content.Intent;
import android.os.Build;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatButton;
import androidx.core.content.ContextCompat;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.RenderersFactory;
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.CaptionStyleCompat;
import androidx.media3.ui.DefaultTimeBar;
import androidx.media3.ui.PlayerView;
import androidx.media3.ui.SubtitleView;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.debrify.app.MainActivity;
import com.debrify.app.R;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;

import io.flutter.plugin.common.MethodChannel;

/**
 * Android TV playback activity that streams debrid content through ExoPlayer.
 * Supports both Torbox and Real-Debrid providers.
 *
 * A long press on the center (OK) button requests the next stream from Flutter.
 */
public class TorboxTvPlayerActivity extends AppCompatActivity {

    private static final String PROVIDER_TORBOX = "torbox";
    private static final String PROVIDER_REAL_DEBRID = "real_debrid";
    
    private enum LoadingType {
        STREAM,   // Loading next stream (green)
        CHANNEL   // Switching channel (cyan)
    }
    
    private static final long SEEK_STEP_MS = 10_000L;
    private static final long DEFAULT_TARGET_BUFFER_MS = 12_000L;
    private static final long HIGH_TARGET_BUFFER_MS = 20_000L;
    private static final long MAX_TARGET_BUFFER_MS = 20_000L;
    private static final long LONG_PRESS_TIMEOUT_MS = 450L;
    private static final long TITLE_FADE_DELAY_MS = 4000L;
    private static final long TITLE_FADE_DURATION_MS = 220L;

    private String provider;
    private PlayerView playerView;
    private ExoPlayer player;
    private DefaultTrackSelector trackSelector;
    private RenderersFactory renderersFactory;
    private DefaultBandwidthMeter bandwidthMeter;
    private long currentTargetBufferMs = DEFAULT_TARGET_BUFFER_MS;
    private TextView titleView;
    private TextView hintView;
    private TextView channelBadgeView;
    private View controlsOverlay;
    private View timeContainer;
    private View buttonsRow;
    private AppCompatButton pauseButton;
    private AppCompatButton audioButton;
    private AppCompatButton subtitleButton;
    private AppCompatButton aspectButton;
    private View nextOverlay;
    private TextView nextText;
    private TextView nextSubtext;
    private View tvStaticView;
    private View tvScanlines;
    private View channelOverlay;
    private TextView channelNumberText;
    private TextView channelNameText;
    private TextView channelStatusText;
    private View channelSlideView;
    private View channelRgbBars;
    private SubtitleView subtitleOverlay;
    private View searchOverlay;
    private View searchPanel;
    private EditText searchInput;
    private RecyclerView searchResultsView;
    private ChannelSearchAdapter searchAdapter;
    private View loadingBarContainer;
    private View loadingBar;
    private android.animation.ValueAnimator loadingBarAnimator;
    private View loadingIndicator;
    private TextView loadingText;
    private View loadingDot1;
    private View loadingDot2;
    private View loadingDot3;
    private android.animation.ValueAnimator dotsAnimator;
    private final ArrayList<ChannelEntry> channelDirectoryEntries = new ArrayList<>();
    private final ArrayList<ChannelEntry> filteredChannelEntries = new ArrayList<>();
    private boolean searchOverlayVisible = false;
    private android.animation.ValueAnimator staticAnimator;
    private Handler staticHandler = new Handler(Looper.getMainLooper());
    private final Handler keyPressHandler = new Handler(Looper.getMainLooper());
    private final Handler channelOverlayHandler = new Handler(Looper.getMainLooper());
    private ArrayList<Bundle> magnetQueue = new ArrayList<>();
    private int resizeModeIndex = 0;
    private final int[] resizeModes = new int[] {
            AspectRatioFrameLayout.RESIZE_MODE_FIT,
            AspectRatioFrameLayout.RESIZE_MODE_FILL,
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    };
    private final String[] resizeModeLabels = new String[] {
            "Fit",
            "Fill",
            "Zoom"
    };

    private boolean startFromRandom;
    private int randomMaxPercent;
    private boolean hideSeekbar;
    private boolean hideOptions;
    private boolean showVideoTitle;
    private boolean showChannelName;
    private String currentChannelName = "";
    private String currentChannelId;
    private int currentChannelNumber = -1;

    private boolean randomApplied = false;
    private boolean requestingNext = false;
    private boolean finishedNotified = false;
    private boolean longPressHandled = false;
    private boolean longPressDownHandled = false;
    private boolean longPressRightHandled = false;
    private boolean longPressUpHandled = false;
    private boolean centerKeyDown = false;
    private boolean downKeyDown = false;
    private boolean rightKeyDown = false;
    private boolean upKeyDown = false;
    private int playedCount = 0;
    private long lastChannelSwitchTime = 0;
    private static final long CHANNEL_SWITCH_COOLDOWN_MS = 2000L; // 2 second cooldown

    private final Random random = new Random();
    private final Runnable hideTitleRunnable = this::fadeOutTitle;
    private final Runnable hideNextOverlayRunnable = this::performHideNextOverlay;
    private final Runnable hideChannelOverlayRunnable = this::performHideChannelOverlay;
    private final Runnable centerLongPressRunnable = new Runnable() {
        @Override
        public void run() {
            if (!centerKeyDown || longPressHandled) {
                return;
            }
            longPressHandled = true;
            requestNextStream();
            hideControllerIfVisible();
        }
    };
    private final Runnable downLongPressRunnable = new Runnable() {
        @Override
        public void run() {
            if (!downKeyDown || longPressDownHandled) {
                return;
            }
            longPressDownHandled = true;
            cycleAspectRatio();
            hideControllerIfVisible();
        }
    };
    private final Runnable rightLongPressRunnable = new Runnable() {
        @Override
        public void run() {
            if (!rightKeyDown || longPressRightHandled) {
                return;
            }
            longPressRightHandled = true;
            requestNextChannel();
            hideControllerIfVisible();
        }
    };
    private final Runnable upLongPressRunnable = new Runnable() {
        @Override
        public void run() {
            if (!upKeyDown || longPressUpHandled) {
                return;
            }
            longPressUpHandled = true;
            hideControllerIfVisible();
            if (!channelDirectoryEntries.isEmpty()) {
                showSearchOverlay();
            } else {
                runOnUiThread(() ->
                        Toast.makeText(TorboxTvPlayerActivity.this,
                                "Channel search unavailable",
                                Toast.LENGTH_SHORT).show());
            }
        }
    };
    private final Player.Listener playbackListener = new Player.Listener() {
        @Override
        public void onPlaybackStateChanged(int playbackState) {
            if (playbackState == Player.STATE_READY) {
                if (startFromRandom && !randomApplied) {
                    maybeSeekRandomly();
                }
            } else if (playbackState == Player.STATE_ENDED) {
                randomApplied = false;
                requestNextStream();
            }
            updatePauseButtonLabel();
        }

        @Override
        public void onIsPlayingChanged(boolean isPlaying) {
            updatePauseButtonLabel();
        }
    };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_torbox_tv_player);

        playerView = findViewById(R.id.player_view);
        titleView = findViewById(R.id.player_title);
        hintView = findViewById(R.id.player_hint);
        channelBadgeView = findViewById(R.id.player_channel_badge);
        nextOverlay = findViewById(R.id.player_next_overlay);
        nextText = findViewById(R.id.player_next_text);
        nextSubtext = findViewById(R.id.player_next_subtext);
        tvStaticView = findViewById(R.id.tv_static_view);
        tvScanlines = findViewById(R.id.tv_scanlines);
        channelOverlay = findViewById(R.id.player_channel_overlay);
        channelNumberText = findViewById(R.id.channel_number_text);
        channelNameText = findViewById(R.id.channel_name_text);
        channelStatusText = findViewById(R.id.channel_status_text);
        channelSlideView = findViewById(R.id.channel_slide_view);
        channelRgbBars = findViewById(R.id.channel_rgb_bars);
        // Use our custom SubtitleView that's positioned independently
        subtitleOverlay = findViewById(R.id.player_subtitles_custom);
        searchOverlay = findViewById(R.id.player_search_overlay);
        searchPanel = findViewById(R.id.player_search_panel);
        searchInput = findViewById(R.id.player_search_input);
        searchResultsView = findViewById(R.id.player_search_results);
        loadingBarContainer = findViewById(R.id.player_loading_bar_container);
        loadingBar = findViewById(R.id.player_loading_bar);
        loadingIndicator = findViewById(R.id.player_loading_indicator);
        loadingText = findViewById(R.id.player_loading_text);
        loadingDot1 = findViewById(R.id.loading_dot_1);
        loadingDot2 = findViewById(R.id.loading_dot_2);
        loadingDot3 = findViewById(R.id.loading_dot_3);

        Intent intent = getIntent();
        
        // Read provider type (default to torbox for backward compatibility)
        provider = intent.getStringExtra("provider");
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: onCreate() - received provider=" + provider);
        
        if (provider == null || provider.isEmpty()) {
            provider = PROVIDER_TORBOX;
            android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Provider was null/empty, defaulting to " + PROVIDER_TORBOX);
        }
        
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Final provider=" + provider);
        
        String initialUrl = intent.getStringExtra("initialUrl");
        String initialTitle = intent.getStringExtra("initialTitle");
        
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: initialUrl=" + (initialUrl != null ? initialUrl.substring(0, Math.min(50, initialUrl.length())) : "null") + "...");
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: initialTitle=" + initialTitle);
        
        // Read magnet list (optional for Real-Debrid)
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
        showChannelName = intent.getBooleanExtra("showChannelName", false);
        String initialChannelName = intent.getStringExtra("channelName");
        if (initialChannelName != null) {
            currentChannelName = initialChannelName;
        }
        currentChannelId = safeString(intent.getStringExtra("currentChannelId"));
        int providedChannelNumber = intent.getIntExtra("currentChannelNumber", -1);
        if (providedChannelNumber > 0) {
            currentChannelNumber = providedChannelNumber;
        }

        if (initialUrl == null || initialUrl.isEmpty()) {
            Toast.makeText(this, "Missing stream URL", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        setupSearchOverlay(intent);
        runOnUiThread(() -> updateChannelBadge(currentChannelName));
        
        setupBackPressHandler();

        initialisePlayer();
        applyUiPreferences(initialTitle);
        setupControllerUi();
        playMedia(initialUrl, initialTitle);
    }

    @OptIn(markerClass = UnstableApi.class)
    private void initialisePlayer() {
        renderersFactory = new DefaultRenderersFactory(this)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                .setEnableDecoderFallback(true)
                .setAllowedVideoJoiningTimeMs(300);

        bandwidthMeter = new DefaultBandwidthMeter.Builder(this).build();

        trackSelector = new DefaultTrackSelector(this, new AdaptiveTrackSelection.Factory());
        trackSelector.setParameters(trackSelector.buildUponParameters()
                .setPreferredAudioLanguage("en")
                .build());

        LoadControl loadControl = buildLoadControl(bandwidthMeter.getBitrateEstimate());
        createPlayer(loadControl);
    }

    @OptIn(markerClass = UnstableApi.class)
    private void createPlayer(LoadControl loadControl) {
        if (player != null) {
            player.removeListener(playbackListener);
            player.release();
        }
        player = new ExoPlayer.Builder(this, renderersFactory)
                .setTrackSelector(trackSelector)
                .setLoadControl(loadControl)
                .setBandwidthMeter(bandwidthMeter)
                .build();
        player.addListener(playbackListener);
        playerView.setPlayer(player);
        
        // Hide PlayerView's internal SubtitleView to use our custom one
        SubtitleView internalSubtitleView = playerView.getSubtitleView();
        if (internalSubtitleView != null) {
            internalSubtitleView.setVisibility(View.GONE);
        }
        
        // Connect player subtitle output to our custom SubtitleView
        if (subtitleOverlay != null) {
            player.addListener(new Player.Listener() {
                @Override
                public void onCues(androidx.media3.common.text.CueGroup cueGroup) {
                    if (subtitleOverlay != null) {
                        subtitleOverlay.setCues(cueGroup.cues);
                    }
                }
            });
        }
        
        playerView.setKeepScreenOn(true);
        playerView.setUseController(true);
        playerView.setControllerAutoShow(true);
        playerView.setControllerShowTimeoutMs(4000);
        playerView.setResizeMode(resizeModes[resizeModeIndex]);
        if (subtitleOverlay != null) {
            subtitleOverlay.setApplyEmbeddedStyles(false);
            subtitleOverlay.setApplyEmbeddedFontSizes(false);
            // No padding fraction - using XML padding for fixed screen-bottom positioning
            subtitleOverlay.setBottomPaddingFraction(0.0f);
            // Text size: 16sp for TV viewing (comfortable size)
            subtitleOverlay.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, 16f);
            subtitleOverlay.setStyle(new CaptionStyleCompat(
                    Color.WHITE,
                    Color.TRANSPARENT,
                    Color.TRANSPARENT,
                    CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                    Color.BLACK,
                    Typeface.create("sans-serif", Typeface.NORMAL)));
        }
        playerView.requestFocus();
    }

    private LoadControl buildLoadControl(long estimatedBitrate) {
        long targetBufferMs = selectTargetBufferMs(estimatedBitrate);
        long minBufferMs = Math.min(targetBufferMs / 2, 7_500L);
        currentTargetBufferMs = targetBufferMs;
        return new DefaultLoadControl.Builder()
                .setBufferDurationsMs((int) minBufferMs, (int) targetBufferMs, 1_000, 2_000)
                .setBackBuffer(0, false)
                .build();
    }

    private void maybeRecreatePlayerForBandwidth() {
        if (bandwidthMeter == null) {
            return;
        }
        long estimate = bandwidthMeter.getBitrateEstimate();
        long desiredTarget = selectTargetBufferMs(estimate);
        if (Math.abs(desiredTarget - currentTargetBufferMs) > 2_000L) {
            LoadControl tuned = buildLoadControl(estimate);
            createPlayer(tuned);
        }
    }

    private long selectTargetBufferMs(long estimatedBitrate) {
        if (estimatedBitrate <= 0) {
            return DEFAULT_TARGET_BUFFER_MS;
        }
        if (estimatedBitrate >= 12_000_000L) {
            return MAX_TARGET_BUFFER_MS;
        }
        if (estimatedBitrate >= 6_000_000L) {
            return HIGH_TARGET_BUFFER_MS;
        }
        if (estimatedBitrate >= 3_000_000L) {
            return 16_000L;
        }
        return DEFAULT_TARGET_BUFFER_MS;
    }

    private void applyUiPreferences(@Nullable String initialTitle) {
        if (showVideoTitle) {
            showTitleTemporarily(initialTitle);
        } else if (titleView != null) {
            cancelTitleFade();
            titleView.setVisibility(View.GONE);
        }

        updateChannelBadge(currentChannelName);

        if (hintView != null) {
            hintView.setVisibility(View.GONE);
        }
    }

    private void setupControllerUi() {
        controlsOverlay = playerView.findViewById(R.id.debrify_controls_root);
        timeContainer = playerView.findViewById(R.id.debrify_controls_time_container);
        buttonsRow = playerView.findViewById(R.id.debrify_controls_buttons);
        pauseButton = playerView.findViewById(R.id.debrify_pause_button);
        audioButton = playerView.findViewById(R.id.debrify_audio_button);
        subtitleButton = playerView.findViewById(R.id.debrify_subtitle_button);
        aspectButton = playerView.findViewById(R.id.debrify_aspect_button);
        DefaultTimeBar timeBar = playerView.findViewById(androidx.media3.ui.R.id.exo_progress);
        View nextButton = playerView.findViewById(R.id.debrify_next_button);

        if (controlsOverlay != null) {
            controlsOverlay.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
        }

        if (buttonsRow != null) {
            buttonsRow.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
        }

        if (timeContainer != null) {
            if (hideSeekbar) {
                timeContainer.setVisibility(View.GONE);
            } else if (hideOptions) {
                timeContainer.setVisibility(View.VISIBLE);
            }
        }

        if (pauseButton != null) {
            pauseButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            pauseButton.setOnClickListener(v -> {
                togglePlayPause();
                if (!hideOptions) {
                    playerView.showController();
                }
            });
            updatePauseButtonLabel();
        }

        if (audioButton != null) {
            audioButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            audioButton.setOnClickListener(v -> {
                cycleAudioTrack();
                if (!hideOptions) {
                    playerView.showController();
                }
            });
        }

        if (subtitleButton != null) {
            subtitleButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            subtitleButton.setOnClickListener(v -> {
                cycleSubtitleTrack();
                if (!hideOptions) {
                    playerView.showController();
                }
            });
        }

        if (aspectButton != null) {
            aspectButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            aspectButton.setOnClickListener(v -> {
                cycleAspectRatio();
                if (!hideOptions) {
                    playerView.showController();
                }
            });
            updateAspectButtonLabel();
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
            playerView.setControllerVisibilityListener(
                    (PlayerView.ControllerVisibilityListener) this::onControllerVisibilityChanged);
            onControllerVisibilityChanged(playerView.isControllerFullyVisible() ? View.VISIBLE : View.GONE);
            playerView.showController();
        }
    }

    private void onControllerVisibilityChanged(int visibility) {
        if (controlsOverlay == null) {
            return;
        }
        boolean visible = visibility == View.VISIBLE;
        controlsOverlay.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (!hideSeekbar && timeContainer != null) {
            timeContainer.animate().cancel();
            if (visible) {
                boolean alreadyVisible =
                        timeContainer.getVisibility() == View.VISIBLE && timeContainer.getAlpha() >= 0.95f;
                timeContainer.setVisibility(View.VISIBLE);
                if (!alreadyVisible) {
                    timeContainer.setAlpha(0f);
                    timeContainer.animate()
                            .alpha(1f)
                            .setDuration(150L)
                            .withEndAction(() -> {
                                if (timeContainer != null) {
                                    timeContainer.setAlpha(1f);
                                }
                            })
                            .start();
                } else {
                    timeContainer.setAlpha(1f);
                }
            } else if (timeContainer.getVisibility() == View.VISIBLE) {
                timeContainer.animate()
                        .alpha(0f)
                        .setDuration(150L)
                        .withEndAction(() -> {
                            if (timeContainer != null) {
                                timeContainer.setVisibility(View.GONE);
                                timeContainer.setAlpha(0f);
                            }
                        })
                        .start();
            }
        }
        if (!hideOptions && buttonsRow != null) {
            buttonsRow.setVisibility(visible ? View.VISIBLE : View.GONE);
        }
        if (visible) {
            updatePauseButtonLabel();
        }
    }

    private void updatePauseButtonLabel() {
        if (pauseButton == null) {
            return;
        }
        boolean playing = player != null && player.isPlaying();
        pauseButton.setText(getString(playing
                ? R.string.debrify_tv_control_pause_button
                : R.string.debrify_tv_control_play_button));
        pauseButton.setBackgroundResource(playing
                ? R.drawable.debrify_tv_button_pause_bg
                : R.drawable.debrify_tv_button_secondary_bg);
        updateAspectButtonLabel();
    }

    private void updateAspectButtonLabel() {
        if (aspectButton == null) {
            return;
        }
        aspectButton.setText(resizeModeLabels[resizeModeIndex]);
    }

    private void showTitleTemporarily(@Nullable String title) {
        if (!showVideoTitle || titleView == null) {
            return;
        }
        titleView.removeCallbacks(hideTitleRunnable);
        titleView.animate().cancel();
        String displayTitle = title != null ? title.trim() : "";
        if (displayTitle.isEmpty()) {
            titleView.setVisibility(View.GONE);
            return;
        }
        titleView.setText(displayTitle);
        titleView.setAlpha(0f);
        titleView.setVisibility(View.VISIBLE);
        titleView.animate().alpha(1f).setDuration(TITLE_FADE_DURATION_MS).start();
        titleView.postDelayed(hideTitleRunnable, TITLE_FADE_DELAY_MS);
    }

    private void cancelTitleFade() {
        if (titleView != null) {
            titleView.removeCallbacks(hideTitleRunnable);
            titleView.animate().cancel();
        }
    }

    private void fadeOutTitle() {
        if (titleView == null || titleView.getVisibility() != View.VISIBLE) {
            return;
        }
        titleView.removeCallbacks(hideTitleRunnable);
        titleView.animate().cancel();
        titleView.animate()
                .alpha(0f)
                .setDuration(TITLE_FADE_DURATION_MS)
                .withEndAction(() -> {
                    if (titleView != null) {
                        titleView.setVisibility(View.GONE);
                    }
                })
                .start();
    }

    private void showLoadingBar(LoadingType type) {
        if (loadingBarContainer == null || loadingBar == null) {
            return;
        }
        
        runOnUiThread(() -> {
            // Stop any existing animation
            if (loadingBarAnimator != null && loadingBarAnimator.isRunning()) {
                loadingBarAnimator.cancel();
            }
            
            // Set color based on type
            int barColor;
            int shadowColor;
            if (type == LoadingType.CHANNEL) {
                barColor = Color.parseColor("#CC00FFFF"); // Cyan for channel
                shadowColor = Color.parseColor("#AA00FFFF");
            } else {
                barColor = Color.parseColor("#CC00FF00"); // Green for stream
                shadowColor = Color.parseColor("#AA00FF00");
            }
            loadingBar.setBackgroundColor(barColor);
            
            // Show the container
            loadingBarContainer.setVisibility(View.VISIBLE);
            loadingBarContainer.setAlpha(1f);
            
            // Show bottom indicator
            showBottomLoadingIndicator(type);
            
            // Get the width of the container
            loadingBarContainer.post(() -> {
                int containerWidth = loadingBarContainer.getWidth();
                if (containerWidth <= 0) {
                    return;
                }
                
                // Create indeterminate loading animation (0% to 100%)
                loadingBarAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f);
                loadingBarAnimator.setDuration(1500L);
                loadingBarAnimator.setRepeatCount(android.animation.ValueAnimator.INFINITE);
                loadingBarAnimator.setRepeatMode(android.animation.ValueAnimator.RESTART);
                loadingBarAnimator.setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator());
                
                loadingBarAnimator.addUpdateListener(animation -> {
                    if (loadingBar == null) {
                        return;
                    }
                    float progress = (float) animation.getAnimatedValue();
                    
                    // Calculate width for indeterminate animation
                    // The bar will grow from 0% to 30% of width, then slide across
                    float barWidth;
                    float barPosition;
                    
                    if (progress < 0.3f) {
                        // Growing phase
                        barWidth = (progress / 0.3f) * 0.3f * containerWidth;
                        barPosition = 0;
                    } else {
                        // Sliding phase
                        barWidth = 0.3f * containerWidth;
                        float slideProgress = (progress - 0.3f) / 0.7f;
                        barPosition = slideProgress * containerWidth;
                    }
                    
                    android.view.ViewGroup.LayoutParams params = loadingBar.getLayoutParams();
                    params.width = (int) barWidth;
                    loadingBar.setLayoutParams(params);
                    loadingBar.setTranslationX(barPosition);
                });
                
                loadingBarAnimator.start();
            });
        });
    }
    
    private void showBottomLoadingIndicator(LoadingType type) {
        if (loadingIndicator == null || loadingText == null) {
            return;
        }
        
        runOnUiThread(() -> {
            // Stop any existing animation
            if (dotsAnimator != null && dotsAnimator.isRunning()) {
                dotsAnimator.cancel();
            }
            
            // Set text and color based on type
            int textColor;
            int dotColor;
            String text;
            
            if (type == LoadingType.CHANNEL) {
                textColor = Color.parseColor("#00FFFF"); // Cyan
                dotColor = Color.parseColor("#00FFFF");
                text = "CHANNEL";
            } else {
                textColor = Color.parseColor("#00FF00"); // Green
                dotColor = Color.parseColor("#00FF00");
                text = "STREAM";
            }
            
            loadingText.setText(text);
            loadingText.setTextColor(textColor);
            
            if (loadingDot1 != null) {
                loadingDot1.setBackgroundColor(dotColor);
            }
            if (loadingDot2 != null) {
                loadingDot2.setBackgroundColor(dotColor);
            }
            if (loadingDot3 != null) {
                loadingDot3.setBackgroundColor(dotColor);
            }
            
            // Show indicator
            loadingIndicator.setVisibility(View.VISIBLE);
            loadingIndicator.setAlpha(0f);
            loadingIndicator.animate()
                .alpha(1f)
                .setDuration(150L)
                .start();
            
            // Animate dots (wave effect)
            dotsAnimator = android.animation.ValueAnimator.ofInt(0, 1, 2, 3);
            dotsAnimator.setDuration(1200L);
            dotsAnimator.setRepeatCount(android.animation.ValueAnimator.INFINITE);
            dotsAnimator.setRepeatMode(android.animation.ValueAnimator.RESTART);
            
            dotsAnimator.addUpdateListener(animation -> {
                int step = (int) animation.getAnimatedValue();
                if (loadingDot1 != null && loadingDot2 != null && loadingDot3 != null) {
                    loadingDot1.setAlpha(step == 1 ? 1f : 0.3f);
                    loadingDot2.setAlpha(step == 2 ? 1f : 0.3f);
                    loadingDot3.setAlpha(step == 3 ? 1f : 0.3f);
                }
            });
            
            dotsAnimator.start();
        });
    }
    
    private void hideBottomLoadingIndicator() {
        if (loadingIndicator == null) {
            return;
        }
        
        runOnUiThread(() -> {
            // Stop animation
            if (dotsAnimator != null && dotsAnimator.isRunning()) {
                dotsAnimator.cancel();
            }
            
            // Fade out
            loadingIndicator.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction(() -> {
                    if (loadingIndicator != null) {
                        loadingIndicator.setVisibility(View.GONE);
                        loadingIndicator.setAlpha(1f);
                    }
                })
                .start();
        });
    }
    
    private void hideLoadingBar() {
        if (loadingBarContainer == null) {
            return;
        }
        
        runOnUiThread(() -> {
            // Stop top bar animation
            if (loadingBarAnimator != null && loadingBarAnimator.isRunning()) {
                loadingBarAnimator.cancel();
            }
            
            // Hide bottom indicator
            hideBottomLoadingIndicator();
            
            // Fade out top bar
            loadingBarContainer.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction(() -> {
                    if (loadingBarContainer != null) {
                        loadingBarContainer.setVisibility(View.GONE);
                        loadingBarContainer.setAlpha(1f);
                    }
                })
                .start();
        });
    }
    
    private void showNextOverlay(@Nullable String headline, @Nullable String subline) {
        // Now just show loading bar instead of full overlay - STREAM type (green)
        showLoadingBar(LoadingType.STREAM);
    }
    
    private String getRandomTvStaticMessage() {
        String[] messages = {
            "📺 BUFFERING... JUST KIDDING",
            "📺 RETICULATING SPLINES...",
            "📺 SUMMONING VIDEO GODS...",
            "📺 ENGAGING HYPERDRIVE...",
            "📺 CALIBRATING FLUX CAPACITOR",
            "📺 CONSULTING THE ALGORITHMS",
            "📺 WARMING UP THE PIXELS",
            "📺 BRIBING THE SERVERS..."
        };
        return messages[random.nextInt(messages.length)];
    }
    
    private void startTvStaticEffect() {
        if (tvStaticView == null) {
            return;
        }
        
        // Stop any existing animation
        stopTvStaticEffect();
        
        // Create random gray noise effect by rapidly changing background colors
        final Runnable staticRunnable = new Runnable() {
            @Override
            public void run() {
                if (tvStaticView != null && nextOverlay.getVisibility() == View.VISIBLE) {
                    // Generate random gray value for TV static
                    int grayValue = 20 + random.nextInt(80); // Random between 20-100
                    int color = Color.rgb(grayValue, grayValue, grayValue);
                    tvStaticView.setBackgroundColor(color);
                    
                    // Randomly flicker the text
                    if (nextText != null && random.nextInt(10) > 7) {
                        nextText.setAlpha(0.7f + random.nextFloat() * 0.3f);
                    }
                    
                    // Continue animation
                    staticHandler.postDelayed(this, 50); // Update every 50ms for smooth static
                }
            }
        };
        staticHandler.post(staticRunnable);
        
        // Animate scan lines slowly moving
        if (tvScanlines != null) {
            tvScanlines.animate()
                .translationY(20f)
                .setDuration(1000)
                .setInterpolator(new android.view.animation.LinearInterpolator())
                .withEndAction(() -> {
                    if (tvScanlines != null) {
                        tvScanlines.setTranslationY(-20f);
                        if (nextOverlay.getVisibility() == View.VISIBLE) {
                            startTvStaticEffect(); // Restart scan line animation
                        }
                    }
                })
                .start();
        }
    }
    
    private void stopTvStaticEffect() {
        staticHandler.removeCallbacksAndMessages(null);
        
        if (tvStaticView != null) {
            tvStaticView.setBackgroundColor(Color.BLACK);
        }
        
        if (tvScanlines != null) {
            tvScanlines.animate().cancel();
            tvScanlines.setTranslationY(0f);
        }
        
        if (nextText != null) {
            nextText.setAlpha(1f);
        }
    }

    private void hideNextOverlay() {
        // Now just hide loading bar
        hideLoadingBar();
    }

    private void scheduleHideNextOverlay(long delayMs) {
        // Schedule hiding the loading bar
        new Handler(Looper.getMainLooper()).postDelayed(this::hideLoadingBar, delayMs);
    }

    private void performHideNextOverlay() {
        // Now just hide loading bar
        hideLoadingBar();
    }

    private void playMedia(String url, @Nullable String title) {
        if (player == null || url == null || url.isEmpty()) {
            return;
        }
        randomApplied = false;
        maybeRecreatePlayerForBandwidth();
        
        // Clear previous video's subtitles before loading new video
        if (subtitleOverlay != null) {
            subtitleOverlay.setCues(java.util.Collections.emptyList());
        }
        
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
        player.addListener(new Player.Listener() {
            @Override
            public void onTracksChanged(Tracks tracks) {
                player.removeListener(this);
                ensureDefaultSubtitleSelected();
            }
        });
    }

    private void updateTitle(@Nullable String title) {
        showTitleTemporarily(title);
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

    private void ensureDefaultSubtitleSelected() {
        if (trackSelector == null) {
            return;
        }
        List<TrackOption> subtitleTracks = collectTrackOptions(C.TRACK_TYPE_TEXT);
        if (subtitleTracks.isEmpty()) {
            return;
        }
        
        // Search for English subtitle track using regex
        TrackOption englishTrack = null;
        for (TrackOption option : subtitleTracks) {
            String label = option.label != null ? option.label.toLowerCase() : "";
            
            // Get track format to extract language and id
            Format format = option.group.getMediaTrackGroup().getFormat(option.trackIndex);
            String language = format.language != null ? format.language.toLowerCase() : "";
            String id = format.id != null ? format.id.toLowerCase() : "";
            
            // Check if track is English using regex pattern
            if (isEnglishSubtitle(label) || isEnglishSubtitle(id) || isEnglishSubtitle(language)) {
                englishTrack = option;
                android.util.Log.d("TorboxTvPlayer", "Found English subtitle: label=" + option.label + " id=" + format.id + " lang=" + format.language);
                break;
            }
        }
        
        // Only enable subtitles if English track is found
        if (englishTrack != null) {
            DefaultTrackSelector.Parameters.Builder builder = trackSelector.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .addOverride(new TrackSelectionOverride(
                            englishTrack.group.getMediaTrackGroup(),
                            Collections.singletonList(englishTrack.trackIndex)));
            trackSelector.setParameters(builder.build());
            // Don't show toast for auto-selection, only for manual changes
            android.util.Log.d("TorboxTvPlayer", "Auto-enabled English subtitles: " + englishTrack.label);
        } else {
            // No English subtitle found, leave subtitles disabled
            android.util.Log.d("TorboxTvPlayer", "No English subtitle found, subtitles remain disabled");
        }
    }
    
    private boolean isEnglishSubtitle(String text) {
        if (text == null || text.isEmpty()) {
            return false;
        }
        // Regex patterns to match English subtitles
        // Matches: "en", "eng", "english", "en-us", "en-gb", etc.
        return text.matches(".*\\b(en|eng|english)\\b.*");
    }

    private void requestNextStream() {
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: requestNextStream() called");
        
        if (requestingNext) {
            android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Already requesting next, ignoring");
            return;
        }
        
        MethodChannel channel = MainActivity.getAndroidTvPlayerChannel();
        if (channel == null) {
            android.util.Log.e("DebrifyTV", "TorboxTvPlayerActivity: Method channel is null!");
            Toast.makeText(this, "Playback bridge unavailable", Toast.LENGTH_SHORT).show();
            return;
        }
        
        showNextOverlay(getString(R.string.debrify_tv_next_loading),
                getString(R.string.debrify_tv_next_hint));
        requestingNext = true;
        
        // Determine which method to call based on provider
        String methodName;
        if (PROVIDER_REAL_DEBRID.equals(provider)) {
            methodName = "requestRealDebridNext";
        } else {
            methodName = "requestTorboxNext";
        }
        
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Calling method channel: " + methodName);
        
        channel.invokeMethod(methodName, null, new MethodChannel.Result() {
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
                
                // Update TV static message to show video is ready
                if (nextTitle != null && !nextTitle.isEmpty()) {
                    runOnUiThread(() -> {
                        if (nextText != null) {
                            nextText.setText("📺 SIGNAL ACQUIRED");
                        }
                        if (nextSubtext != null) {
                            nextSubtext.setVisibility(View.VISIBLE);
                            nextSubtext.setText("▶ " + nextTitle.toUpperCase());
                        }
                    });
                }
                
                playMedia(nextUrl, nextTitle);
                scheduleHideNextOverlay(350L);
            }

            @Override
            public void error(String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
                requestingNext = false;
                String displayMsg = errorMessage != null ? errorMessage : "Failed to load next stream";
                Toast.makeText(TorboxTvPlayerActivity.this, displayMsg, Toast.LENGTH_SHORT).show();
                hideNextOverlay();
            }

            @Override
            public void notImplemented() {
                requestingNext = false;
                hideNextOverlay();
            }
        });
    }

    private void handleNoMoreStreams() {
        runOnUiThread(() -> {
            hideNextOverlay();
            String providerName = PROVIDER_REAL_DEBRID.equals(provider) ? "Real-Debrid" : "Torbox";
            Toast.makeText(TorboxTvPlayerActivity.this,
                    "No more " + providerName + " streams available",
                    Toast.LENGTH_SHORT).show();
            finish();
        });
    }

    @Nullable
    private String safeString(@Nullable Object value) {
        if (value == null) {
            return null;
        }
        String str = value.toString();
        return str != null ? str.trim() : null;
    }

    /**
     * Request the next channel from Flutter (with looping)
     */
    private void requestNextChannel() {
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: requestNextChannel() called");
        
        // Check cooldown
        long now = System.currentTimeMillis();
        if (now - lastChannelSwitchTime < CHANNEL_SWITCH_COOLDOWN_MS) {
            android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Channel switch on cooldown, ignoring");
            Toast.makeText(this, "Please wait...", Toast.LENGTH_SHORT).show();
            return;
        }
        
        if (requestingNext) {
            android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Already requesting next, ignoring");
            return;
        }
        
        MethodChannel channel = MainActivity.getAndroidTvPlayerChannel();
        if (channel == null) {
            android.util.Log.e("DebrifyTV", "TorboxTvPlayerActivity: Method channel is null!");
            Toast.makeText(this, "Playback bridge unavailable", Toast.LENGTH_SHORT).show();
            return;
        }
        
        // Show loading bar IMMEDIATELY before fetching - CHANNEL type (cyan)
        showLoadingBar(LoadingType.CHANNEL);
        
        lastChannelSwitchTime = now;
        requestingNext = true;
        
        android.util.Log.d("DebrifyTV", "TorboxTvPlayerActivity: Calling method channel: requestNextChannel");
        
        channel.invokeMethod("requestNextChannel", null, new MethodChannel.Result() {
            @Override
            public void success(@Nullable Object result) {
                requestingNext = false;
                
                if (!(result instanceof Map)) {
                    android.util.Log.e("DebrifyTV", "Channel switch failed: result is not a Map");
                    runOnUiThread(() -> {
                        Toast.makeText(TorboxTvPlayerActivity.this, "Channel switch failed. Check logs.", Toast.LENGTH_SHORT).show();
                        hideChannelOverlay();
                    });
                    return;
                }
                @SuppressWarnings("unchecked")
                Map<String, Object> payload = (Map<String, Object>) result;
                ChannelSwitchData switchData = parseChannelSwitchPayload(payload, null, null);
                if (switchData == null || switchData.url == null || switchData.url.isEmpty()) {
                    runOnUiThread(() -> {
                        Toast.makeText(TorboxTvPlayerActivity.this, "Channel has no streams", Toast.LENGTH_SHORT).show();
                        hideLoadingBar();
                    });
                    return;
                }
                final String playUrl = switchData.url;
                final String playTitle = switchData.title;
                
                // Play the first video from the new channel
                playMedia(playUrl, playTitle);
                scheduleHideNextOverlay(350L);
            }

            @Override
            public void error(String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
                requestingNext = false;
                String displayMsg = errorMessage != null ? errorMessage : "Failed to switch channel";
                runOnUiThread(() -> {
                    Toast.makeText(TorboxTvPlayerActivity.this, displayMsg, Toast.LENGTH_SHORT).show();
                    hideLoadingBar();
                });
            }

            @Override
            public void notImplemented() {
                requestingNext = false;
                runOnUiThread(() -> hideLoadingBar());
            }
        });
    }

    private void showChannelOverlay(@Nullable Integer channelNum, @Nullable String name) {
        if (channelOverlay == null || player == null) {
            return;
        }

        runOnUiThread(() -> {
            cancelScheduledChannelOverlayHide();
            
            // Set channel info
            if (channelNumberText != null) {
                String displayNum = channelNum != null ? 
                        String.format(Locale.US, "CH %02d", channelNum) : "CHANNEL";
                channelNumberText.setText(displayNum);
            }
            
            if (channelNameText != null) {
                String displayName = name != null && !name.isEmpty() ? name.toUpperCase() : "";
                channelNameText.setText(displayName);
                channelNameText.setVisibility(!displayName.isEmpty() ? View.VISIBLE : View.GONE);
            }
            
            // Make sure overlay is fully visible immediately (no partial rendering)
            channelOverlay.setVisibility(View.VISIBLE);
            channelOverlay.bringToFront(); // Ensure it's on top of everything
            channelOverlay.setTranslationX(getChannelOverlayTravelDistance());
            channelOverlay.setAlpha(0f);
            
            // Start awesome channel surf animation
            startChannelSurfAnimation();
            
            // Animate overlay in with horizontal slide
            channelOverlay.animate()
                .translationX(0f)
                .alpha(1f)
                .setDuration(200L)
                .start();
        });
    }

    private void startChannelSurfAnimation() {
        if (channelSlideView == null || channelRgbBars == null) {
            return;
        }
        
        // Animate background color cycling (cyan -> blue -> magenta -> cyan)
        final int[] colors = {
            Color.rgb(0, 17, 51),   // Dark blue
            Color.rgb(0, 34, 68),   // Lighter blue
            Color.rgb(17, 0, 51),   // Dark magenta
            Color.rgb(0, 17, 51)    // Back to dark blue
        };
        
        final int[] currentColorIndex = {0};
        final Handler animHandler = new Handler(Looper.getMainLooper());
        final Runnable colorCycleRunnable = new Runnable() {
            @Override
            public void run() {
                if (channelSlideView != null && channelOverlay != null && 
                    channelOverlay.getVisibility() == View.VISIBLE) {
                    channelSlideView.setBackgroundColor(colors[currentColorIndex[0]]);
                    currentColorIndex[0] = (currentColorIndex[0] + 1) % colors.length;
                    animHandler.postDelayed(this, 100); // Cycle every 100ms
                }
            }
        };
        animHandler.post(colorCycleRunnable);
        
        // Animate RGB bars with flicker effect
        if (channelRgbBars != null) {
            final Runnable rgbFlickerRunnable = new Runnable() {
                @Override
                public void run() {
                    if (channelRgbBars != null && channelOverlay != null && 
                        channelOverlay.getVisibility() == View.VISIBLE) {
                        // Random RGB color for chromatic aberration effect
                        int r = random.nextInt(256);
                        int g = random.nextInt(256);
                        int b = random.nextInt(256);
                        channelRgbBars.setBackgroundColor(Color.argb(51, r, g, b)); // 20% alpha
                        animHandler.postDelayed(this, 70); // Flicker every 70ms
                    }
                }
            };
            animHandler.post(rgbFlickerRunnable);
        }
        
        // Pulse the status text
        if (channelStatusText != null) {
            channelStatusText.animate()
                .alpha(0.5f)
                .setDuration(300)
                .withEndAction(() -> {
                    if (channelStatusText != null && channelOverlay != null && 
                        channelOverlay.getVisibility() == View.VISIBLE) {
                        channelStatusText.animate()
                            .alpha(1f)
                            .setDuration(300)
                            .withEndAction(this::startChannelSurfAnimation)
                            .start();
                    }
                })
                .start();
        }
    }

    private void scheduleHideChannelOverlay(long delayMs) {
        if (channelOverlay == null) {
            return;
        }
        cancelScheduledChannelOverlayHide();
        channelOverlayHandler.postDelayed(hideChannelOverlayRunnable, delayMs);
    }

    private void hideChannelOverlay() {
        cancelScheduledChannelOverlayHide();
        if (Looper.myLooper() == Looper.getMainLooper()) {
            performHideChannelOverlay();
        } else {
            channelOverlayHandler.post(hideChannelOverlayRunnable);
        }
    }

    private void performHideChannelOverlay() {
        if (channelOverlay == null) {
            return;
        }

        channelOverlay.animate()
            .translationX(-getChannelOverlayTravelDistance())
            .alpha(0f)
            .setDuration(200L)
            .withEndAction(() -> {
                if (channelOverlay != null) {
                    channelOverlay.setVisibility(View.GONE);
                }
            })
            .start();
    }

    private void cancelScheduledChannelOverlayHide() {
        channelOverlayHandler.removeCallbacks(hideChannelOverlayRunnable);
    }

    private float getChannelOverlayTravelDistance() {
        if (channelOverlay == null) {
            return 0f;
        }
        int width = channelOverlay.getWidth();
        if (width <= 0) {
            View root = channelOverlay.getRootView();
            if (root != null) {
                width = root.getWidth();
            }
        }
        if (width <= 0) {
            width = getResources().getDisplayMetrics().widthPixels;
        }
        return (float) width;
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
        updatePauseButtonLabel();
    }

    private void cycleAudioTrack() {
        if (player == null || trackSelector == null) {
            return;
        }
        List<TrackOption> audioTracks = collectTrackOptions(C.TRACK_TYPE_AUDIO);
        if (audioTracks.isEmpty()) {
            showToast("No alternate audio tracks");
            return;
        }
        int currentIndex = -1;
        for (int i = 0; i < audioTracks.size(); i++) {
            TrackOption option = audioTracks.get(i);
            if (option.group.isTrackSelected(option.trackIndex)) {
                currentIndex = i;
                break;
            }
        }
        int nextIndex = (currentIndex + 1) % audioTracks.size();
        TrackOption next = audioTracks.get(nextIndex);
        DefaultTrackSelector.Parameters.Builder builder = trackSelector.buildUponParameters()
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .addOverride(new TrackSelectionOverride(
                        next.group.getMediaTrackGroup(),
                        Collections.singletonList(next.trackIndex)));
        trackSelector.setParameters(builder.build());
        showToast("Audio: " + next.label);
    }

    private void cycleSubtitleTrack() {
        if (player == null || trackSelector == null) {
            return;
        }
        List<TrackOption> subtitleTracks = collectTrackOptions(C.TRACK_TYPE_TEXT);
        if (subtitleTracks.isEmpty()) {
            showToast("No subtitles available");
            return;
        }
        DefaultTrackSelector.Parameters parameters = trackSelector.getParameters();
        int currentIndex = -1;
        for (int i = 0; i < subtitleTracks.size(); i++) {
            TrackOption option = subtitleTracks.get(i);
            if (option.group.isTrackSelected(option.trackIndex)) {
                currentIndex = i;
                break;
            }
        }
        int nextIndex = currentIndex + 1;
        DefaultTrackSelector.Parameters.Builder builder =
                trackSelector.buildUponParameters().clearOverridesOfType(C.TRACK_TYPE_TEXT);
        if (nextIndex >= subtitleTracks.size()) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true);
            trackSelector.setParameters(builder.build());
            showToast("Subtitles off");
            return;
        }
        TrackOption next = subtitleTracks.get(nextIndex);
        builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .addOverride(new TrackSelectionOverride(
                        next.group.getMediaTrackGroup(),
                        Collections.singletonList(next.trackIndex)));
        trackSelector.setParameters(builder.build());
        showToast("Subtitles: " + next.label);
    }

    private void cycleAspectRatio() {
        resizeModeIndex = (resizeModeIndex + 1) % resizeModes.length;
        if (playerView != null) {
            playerView.setResizeMode(resizeModes[resizeModeIndex]);
        }
        updateAspectButtonLabel();
        showToast("Aspect: " + resizeModeLabels[resizeModeIndex]);
    }

    private List<TrackOption> collectTrackOptions(int trackType) {
        List<TrackOption> options = new ArrayList<>();
        if (player == null) {
            return options;
        }
        Tracks tracks = player.getCurrentTracks();
        int fallbackIndex = 1;
        for (Tracks.Group group : tracks.getGroups()) {
            if (group.getType() != trackType || !group.isSupported()) {
                continue;
            }
            for (int i = 0; i < group.length; i++) {
                if (!group.isTrackSupported(i)) {
                    continue;
                }
                Format format = group.getTrackFormat(i);
                String label = buildTrackLabel(format, fallbackIndex, trackType);
                options.add(new TrackOption(group, i, label));
                fallbackIndex++;
            }
        }
        return options;
    }

    private String buildTrackLabel(Format format, int fallbackIndex, int trackType) {
        List<String> parts = new ArrayList<>();
        if (format.label != null && !format.label.isEmpty()) {
            parts.add(format.label);
        }
        String languageLabel = formatLanguage(format.language);
        if (languageLabel != null && !languageLabel.isEmpty()) {
            parts.add(languageLabel);
        }
        if (trackType == C.TRACK_TYPE_AUDIO && format.channelCount != Format.NO_VALUE) {
            parts.add(format.channelCount + "ch");
        }
        if (parts.isEmpty()) {
            String prefix = trackType == C.TRACK_TYPE_AUDIO ? "Track" : "Subtitle";
            parts.add(prefix + " " + fallbackIndex);
        }
        return TextUtils.join(" • ", parts);
    }

    private String formatLanguage(@Nullable String languageTag) {
        if (languageTag == null || languageTag.isEmpty() || "und".equals(languageTag)) {
            return null;
        }
        Locale locale = Locale.forLanguageTag(languageTag);
        String display = locale.getDisplayLanguage(Locale.getDefault());
        if (display == null || display.isEmpty()) {
            return languageTag;
        }
        return display;
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private void setupSearchOverlay(Intent intent) {
        if (searchOverlay == null || searchInput == null || searchResultsView == null) {
            return;
        }

        searchOverlay.setVisibility(View.GONE);
        searchOverlay.setAlpha(0f);
        searchOverlay.setFocusable(true);
        searchOverlay.setFocusableInTouchMode(true);
        searchOverlay.setOnClickListener(v -> hideSearchOverlay());
        if (searchPanel != null) {
            searchPanel.setClickable(true);
        }

        ArrayList<Bundle> directoryBundles;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            directoryBundles = intent.getParcelableArrayListExtra("channelDirectory", Bundle.class);
        } else {
            directoryBundles = intent.getParcelableArrayListExtra("channelDirectory");
        }

        if (directoryBundles != null) {
            for (int index = 0; index < directoryBundles.size(); index++) {
                Bundle bundle = directoryBundles.get(index);
                if (bundle == null) {
                    continue;
                }
                String id = safeString(bundle.get("id"));
                if (id == null || id.isEmpty()) {
                    continue;
                }
                String name = safeString(bundle.get("name"));
                int number = bundle.containsKey("channelNumber")
                        ? bundle.getInt("channelNumber", -1)
                        : -1;
                boolean isCurrent = bundle.getBoolean("isCurrent", false);
                if (currentChannelId != null && currentChannelId.equals(id)) {
                    isCurrent = true;
                    if (number > 0) {
                        currentChannelNumber = number;
                    }
                }
                channelDirectoryEntries.add(new ChannelEntry(
                        id,
                        name != null ? name : "",
                        number,
                        isCurrent,
                        index));
            }
        }

        if (currentChannelNumber <= 0 && currentChannelId != null) {
            int lookedUp = resolveChannelNumberFromDirectory(currentChannelId);
            if (lookedUp > 0) {
                currentChannelNumber = lookedUp;
            }
        }

        if (channelDirectoryEntries.isEmpty()) {
            return;
        }

        filteredChannelEntries.clear();
        filteredChannelEntries.addAll(channelDirectoryEntries);

        searchAdapter = new ChannelSearchAdapter(filteredChannelEntries, this::requestChannelByEntry);
        searchResultsView.setLayoutManager(new LinearLayoutManager(this));
        searchResultsView.setHasFixedSize(false);
        searchResultsView.setItemAnimator(null);
        searchResultsView.setAdapter(searchAdapter);

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) { }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) { }

            @Override
            public void afterTextChanged(Editable s) {
                filterChannels(s != null ? s.toString() : "");
            }
        });

        searchInput.setOnKeyListener((v, keyCode, event) -> {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_UP) {
                hideSearchOverlay();
                return true;
            }
            return false;
        });

        markSearchCurrentChannelState(currentChannelId);
        if (searchAdapter != null) {
            searchAdapter.notifyDataSetChanged();
        }
    }

    private void filterChannels(@Nullable String query) {
        final String raw = query != null ? query.trim() : "";
        final String normalized = raw.toLowerCase(Locale.US);
        final String digitsOnly = raw.replaceAll("[^0-9]", "");
        filteredChannelEntries.clear();
        if (normalized.isEmpty()) {
            filteredChannelEntries.addAll(channelDirectoryEntries);
        } else {
            for (ChannelEntry entry : channelDirectoryEntries) {
                if (entry.matches(normalized, digitsOnly)) {
                    filteredChannelEntries.add(entry);
                }
            }
        }
        if (searchAdapter != null) {
            searchAdapter.notifyDataSetChanged();
        }
        if (!filteredChannelEntries.isEmpty() && searchResultsView != null) {
            searchResultsView.post(() -> searchResultsView.scrollToPosition(0));
        }
    }

    private void showSearchOverlay() {
        if (searchOverlay == null || searchInput == null || searchResultsView == null) {
            return;
        }
        if (channelDirectoryEntries.isEmpty()) {
            return;
        }
        keyPressHandler.removeCallbacks(upLongPressRunnable);
        searchOverlayVisible = true;
        filterChannels(searchInput.getText() != null ? searchInput.getText().toString() : "");

        searchOverlay.setVisibility(View.VISIBLE);
        searchOverlay.setAlpha(0f);
        searchOverlay.bringToFront();
        searchOverlay.animate().alpha(1f).setDuration(160L).start();

        if (searchPanel != null) {
            searchPanel.setScaleX(0.96f);
            searchPanel.setScaleY(0.96f);
            searchPanel.setAlpha(0.85f);
            searchPanel.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(200L)
                    .start();
        }

        searchInput.requestFocus();
        searchInput.post(() -> {
            searchInput.selectAll();
            showKeyboard(searchInput);
        });

        searchResultsView.post(() -> {
            if (searchResultsView.getChildCount() > 0) {
                View first = searchResultsView.getChildAt(0);
                if (first != null) {
                    first.requestFocus();
                }
            }
        });
    }

    private void hideSearchOverlay() {
        if (searchOverlay == null || !isSearchOverlayVisible()) {
            return;
        }
        searchOverlayVisible = false;
        hideKeyboard(searchInput);
        searchOverlay.animate()
                .alpha(0f)
                .setDuration(140L)
                .withEndAction(() -> {
                    if (searchOverlay != null) {
                        searchOverlay.setVisibility(View.GONE);
                        searchOverlay.setAlpha(1f);
                    }
                })
                .start();
        longPressUpHandled = false;
    }

    private boolean isSearchOverlayVisible() {
        return searchOverlayVisible && searchOverlay != null && searchOverlay.getVisibility() == View.VISIBLE;
    }

    private void showKeyboard(@Nullable View target) {
        if (target == null) {
            return;
        }
        target.post(() -> {
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null) {
                imm.showSoftInput(target, InputMethodManager.SHOW_IMPLICIT);
            }
        });
    }

    private void hideKeyboard(@Nullable View target) {
        if (target == null) {
            return;
        }
        InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm != null) {
            imm.hideSoftInputFromWindow(target.getWindowToken(), 0);
        }
    }

    private void markSearchCurrentChannelState(@Nullable String channelIdValue) {
        if (channelDirectoryEntries.isEmpty()) {
            return;
        }
        for (ChannelEntry entry : channelDirectoryEntries) {
            entry.isCurrent = channelIdValue != null && channelIdValue.equals(entry.id);
        }
    }

    private int resolveChannelNumberFromDirectory(@Nullable String channelIdValue) {
        if (channelIdValue == null || channelDirectoryEntries.isEmpty()) {
            return -1;
        }
        for (ChannelEntry entry : channelDirectoryEntries) {
            if (channelIdValue.equals(entry.id) && entry.number > 0) {
                return entry.number;
            }
        }
        return -1;
    }

    @Nullable
    private ChannelSwitchData parseChannelSwitchPayload(Map<String, Object> payload,
                                                        @Nullable Integer fallbackNumber,
                                                        @Nullable String fallbackName) {
        String channelName = safeString(payload.get("channelName"));
        Integer channelNumber = payload.get("channelNumber") instanceof Integer
                ? (Integer) payload.get("channelNumber")
                : null;
        String channelId = safeString(payload.get("channelId"));
        String firstUrl = safeString(payload.get("firstUrl"));
        String firstTitle = safeString(payload.get("firstTitle"));

        if (channelId != null && !channelId.isEmpty()) {
            currentChannelId = channelId;
        }

        String resolvedName;
        if (channelName != null && !channelName.isEmpty()) {
            resolvedName = channelName;
        } else if (fallbackName != null && !fallbackName.isEmpty()) {
            resolvedName = fallbackName;
        } else {
            resolvedName = currentChannelName;
        }
        if (resolvedName == null) {
            resolvedName = "";
        }

        Integer resolvedNumber = channelNumber;
        if (resolvedNumber == null || resolvedNumber <= 0) {
            if (fallbackNumber != null && fallbackNumber > 0) {
                resolvedNumber = fallbackNumber;
            } else if (currentChannelId != null) {
                int lookedUp = resolveChannelNumberFromDirectory(currentChannelId);
                if (lookedUp > 0) {
                    resolvedNumber = lookedUp;
                }
            }
        }

        currentChannelName = resolvedName;
        currentChannelNumber = resolvedNumber != null ? resolvedNumber : -1;
        markSearchCurrentChannelState(currentChannelId);

        final String badgeName = currentChannelName;
        final boolean hasAdapter = searchAdapter != null;
        runOnUiThread(() -> {
            updateChannelBadge(badgeName);
            if (hasAdapter) {
                searchAdapter.notifyDataSetChanged();
            }
        });

        if (firstUrl == null || firstUrl.isEmpty()) {
            return null;
        }

        String resolvedTitle;
        if (firstTitle != null && !firstTitle.isEmpty()) {
            resolvedTitle = firstTitle;
        } else if (!resolvedName.isEmpty()) {
            resolvedTitle = resolvedName;
        } else {
            resolvedTitle = "Debrify TV";
        }

        return new ChannelSwitchData(firstUrl, resolvedTitle, resolvedNumber, resolvedName);
    }

    private void requestChannelByEntry(ChannelEntry entry) {
        if (entry == null) {
            return;
        }

        long now = System.currentTimeMillis();
        if (now - lastChannelSwitchTime < CHANNEL_SWITCH_COOLDOWN_MS) {
            Toast.makeText(this, "Please wait...", Toast.LENGTH_SHORT).show();
            return;
        }

        if (requestingNext) {
            return;
        }

        MethodChannel channel = MainActivity.getAndroidTvPlayerChannel();
        if (channel == null) {
            Toast.makeText(this, "Playback bridge unavailable", Toast.LENGTH_SHORT).show();
            return;
        }

        hideSearchOverlay();
        showLoadingBar(LoadingType.CHANNEL);

        lastChannelSwitchTime = now;
        requestingNext = true;
        currentChannelId = entry.id;
        if (entry.number > 0) {
            currentChannelNumber = entry.number;
        }

        Map<String, Object> args = new HashMap<>();
        args.put("channelId", entry.id);

        channel.invokeMethod("requestChannelById", args, new MethodChannel.Result() {
            @Override
            public void success(@Nullable Object result) {
                requestingNext = false;

                if (!(result instanceof Map)) {
                    runOnUiThread(() -> {
                        Toast.makeText(TorboxTvPlayerActivity.this,
                                "Channel switch failed. Check logs.",
                                Toast.LENGTH_SHORT).show();
                        hideChannelOverlay();
                    });
                    return;
                }

                @SuppressWarnings("unchecked")
                Map<String, Object> payload = (Map<String, Object>) result;
                ChannelSwitchData switchData = parseChannelSwitchPayload(
                        payload,
                        entry.number > 0 ? entry.number : null,
                        entry.name);

                if (switchData == null || switchData.url == null || switchData.url.isEmpty()) {
                    runOnUiThread(() -> {
                        Toast.makeText(TorboxTvPlayerActivity.this,
                                "Channel has no streams",
                                Toast.LENGTH_SHORT).show();
                        hideLoadingBar();
                    });
                    return;
                }

                final String playUrl = switchData.url;
                final String playTitle = switchData.title;

                // Play the new channel video
                playMedia(playUrl, playTitle);
                scheduleHideNextOverlay(350L);
            }

            @Override
            public void error(String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
                requestingNext = false;
                runOnUiThread(() -> {
                    Toast.makeText(TorboxTvPlayerActivity.this,
                            errorMessage != null ? errorMessage : "Failed to switch channel",
                            Toast.LENGTH_SHORT).show();
                    hideLoadingBar();
                });
            }

            @Override
            public void notImplemented() {
                requestingNext = false;
                runOnUiThread(() -> hideLoadingBar());
            }
        });
    }

    private static class TrackOption {
        final Tracks.Group group;
        final int trackIndex;
        final String label;

        TrackOption(Tracks.Group group, int trackIndex, String label) {
            this.group = group;
            this.trackIndex = trackIndex;
            this.label = label;
        }
    }

    private static class ChannelEntry {
        final String id;
        final String name;
        final String nameUpper;
        final String nameLower;
        final int number;
        final int order;
        boolean isCurrent;

        ChannelEntry(String id, String name, int number, boolean isCurrent, int order) {
            this.id = id;
            this.name = name != null ? name : "";
            this.nameUpper = this.name.toUpperCase(Locale.US);
            this.nameLower = this.name.toLowerCase(Locale.US);
            this.number = number;
            this.isCurrent = isCurrent;
            this.order = order;
        }

        boolean matches(String normalizedQuery, String digitsQuery) {
            if (normalizedQuery.isEmpty()) {
                return true;
            }
            if (!nameLower.isEmpty() && nameLower.contains(normalizedQuery)) {
                return true;
            }
            if (!digitsQuery.isEmpty() && number > 0) {
                String plain = Integer.toString(number);
                String padded = String.format(Locale.US, "%02d", number);
                return plain.contains(digitsQuery) || padded.contains(digitsQuery);
            }
            return false;
        }
    }

    private static class ChannelSearchAdapter extends RecyclerView.Adapter<ChannelSearchAdapter.ChannelViewHolder> {
        interface OnChannelClickListener {
            void onChannelClicked(ChannelEntry entry);
        }

        private final List<ChannelEntry> items;
        private final OnChannelClickListener listener;

        ChannelSearchAdapter(List<ChannelEntry> items, OnChannelClickListener listener) {
            this.items = items;
            this.listener = listener;
        }

        @NonNull
        @Override
        public ChannelViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_tv_channel_search, parent, false);
            view.setFocusable(true);
            view.setFocusableInTouchMode(true);
            return new ChannelViewHolder(view);
        }

        @Override
        public void onBindViewHolder(@NonNull ChannelViewHolder holder, int position) {
            ChannelEntry entry = items.get(position);
            holder.bind(entry, listener);
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        static class ChannelViewHolder extends RecyclerView.ViewHolder {
            private final TextView numberView;
            private final TextView nameView;
            private final TextView keywordsView;
            private final TextView statusView;

            ChannelViewHolder(@NonNull View itemView) {
                super(itemView);
                numberView = itemView.findViewById(R.id.search_channel_number);
                nameView = itemView.findViewById(R.id.search_channel_name);
                keywordsView = itemView.findViewById(R.id.search_channel_keywords);
                statusView = itemView.findViewById(R.id.search_channel_status);
            }

            void bind(ChannelEntry entry, OnChannelClickListener listener) {
                String numberText = entry.number > 0
                        ? String.format(Locale.US, "CH %02d", entry.number)
                        : "AUTO";
                numberView.setText(numberText);
                nameView.setText(entry.nameUpper);
                if (entry.isCurrent) {
                    keywordsView.setText("Currently playing");
                } else {
                    keywordsView.setText("Press OK to tune instantly");
                }
                statusView.setVisibility(entry.isCurrent ? View.VISIBLE : View.INVISIBLE);
                itemView.setBackgroundResource(entry.isCurrent
                        ? R.drawable.tv_search_item_bg_active
                        : R.drawable.tv_search_item_bg);
                itemView.setAlpha(entry.isCurrent ? 1f : 0.86f);

                itemView.setOnClickListener(v -> listener.onChannelClicked(entry));
                itemView.setOnFocusChangeListener((v, hasFocus) -> {
                    if (hasFocus) {
                        v.animate().scaleX(1.04f).scaleY(1.04f).setDuration(120L).start();
                        v.setBackgroundResource(R.drawable.tv_search_item_bg_active);
                    } else {
                        v.animate().scaleX(1f).scaleY(1f).setDuration(120L).start();
                        v.setBackgroundResource(entry.isCurrent
                                ? R.drawable.tv_search_item_bg_active
                                : R.drawable.tv_search_item_bg);
                    }
                });
            }
        }
    }

    private static class ChannelSwitchData {
        final String url;
        final String title;
        @Nullable
        final Integer channelNumber;
        @Nullable
        final String channelName;

        ChannelSwitchData(String url, String title, @Nullable Integer channelNumber, @Nullable String channelName) {
            this.url = url;
            this.title = title;
            this.channelNumber = channelNumber;
            this.channelName = channelName;
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
        android.util.Log.d("TorboxTvPlayer", "Seeking from " + position + "ms to " + target + "ms (offset=" + offsetMs + "ms)");
        player.seekTo(target);
        if (playerView != null) {
            playerView.hideController();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (isSearchOverlayVisible()) {
            return super.onKeyDown(keyCode, event);
        }
        // Long press handling is done in dispatchKeyEvent
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            // Consume center/enter to prevent default behavior
            return true;
        }
        // Let down arrow pass through for navigation when controls are visible
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (isSearchOverlayVisible()) {
            return super.onKeyUp(keyCode, event);
        }
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (!longPressHandled) {
                if (playerView != null) {
                    playerView.showController();
                }
                togglePlayPause();
            }
            longPressHandled = false;
            return true;
        }
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            boolean wasLongPress = longPressDownHandled;
            longPressDownHandled = false;
            if (!wasLongPress && playerView != null && event.getAction() == KeyEvent.ACTION_UP) {
                playerView.showController();
            }
        }
        return super.onKeyUp(keyCode, event);
    }

    private void setupBackPressHandler() {
        // Use modern OnBackPressedDispatcher API instead of deprecated onBackPressed()
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (isSearchOverlayVisible()) {
                    hideSearchOverlay();
                    return;
                }
                // Allow back button to finish the activity and return to Flutter app
                setEnabled(false);
                getOnBackPressedDispatcher().onBackPressed();
            }
        });
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int keyCode = event.getKeyCode();
        
        if (isSearchOverlayVisible()) {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_DOWN) {
                hideSearchOverlay();
                return true;
            }
            return super.dispatchKeyEvent(event);
        }
        
        // Intercept center/enter button to manage long press without waking controller
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                if (!centerKeyDown) {
                    centerKeyDown = true;
                    longPressHandled = false;
                    keyPressHandler.removeCallbacks(centerLongPressRunnable);
                    keyPressHandler.postDelayed(centerLongPressRunnable, LONG_PRESS_TIMEOUT_MS);
                }
                return true;
            } else if (event.getAction() == KeyEvent.ACTION_UP) {
                keyPressHandler.removeCallbacks(centerLongPressRunnable);
                centerKeyDown = false;
            } else if (event.isCanceled()) {
                keyPressHandler.removeCallbacks(centerLongPressRunnable);
                centerKeyDown = false;
                longPressHandled = false;
                return true;
            }
        }
        
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                if (!upKeyDown) {
                    upKeyDown = true;
                    longPressUpHandled = false;
                    keyPressHandler.removeCallbacks(upLongPressRunnable);
                    keyPressHandler.postDelayed(upLongPressRunnable, LONG_PRESS_TIMEOUT_MS);
                }
                return super.dispatchKeyEvent(event);
            } else if (event.getAction() == KeyEvent.ACTION_UP) {
                keyPressHandler.removeCallbacks(upLongPressRunnable);
                upKeyDown = false;
                boolean handled = longPressUpHandled;
                longPressUpHandled = false;
                if (!handled && playerView != null) {
                    playerView.showController();
                }
                return super.dispatchKeyEvent(event);
            } else if (event.isCanceled()) {
                keyPressHandler.removeCallbacks(upLongPressRunnable);
                upKeyDown = false;
                longPressUpHandled = false;
                return super.dispatchKeyEvent(event);
            }
        }
        
        // Intercept down button to manage long press without waking controller
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            boolean controllerVisible = playerView != null && playerView.isControllerFullyVisible();

            if (!controllerVisible) {
                if (event.getAction() == KeyEvent.ACTION_DOWN) {
                    if (!downKeyDown) {
                        downKeyDown = true;
                        longPressDownHandled = false;
                        keyPressHandler.removeCallbacks(downLongPressRunnable);
                        keyPressHandler.postDelayed(downLongPressRunnable, LONG_PRESS_TIMEOUT_MS);
                    }
                    return true;
                } else if (event.getAction() == KeyEvent.ACTION_UP) {
                    keyPressHandler.removeCallbacks(downLongPressRunnable);
                    downKeyDown = false;
                } else if (event.isCanceled()) {
                    keyPressHandler.removeCallbacks(downLongPressRunnable);
                    downKeyDown = false;
                    longPressDownHandled = false;
                    return true;
                }
            }
        }
        
        // Handle Right arrow - seek OR long press for next channel
        if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
            boolean focusInControls = isFocusInControlsOverlay();

            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                if (!rightKeyDown) {
                    boolean controllerVisible = playerView != null && playerView.isControllerFullyVisible();

                    if (controllerVisible && focusInControls) {
                        View defaultFocus = playerView != null ? playerView.getRootView().findFocus() : null;
                        if (defaultFocus == null || defaultFocus == playerView) {
                            hideControllerIfVisible();
                        } else {
                            return super.dispatchKeyEvent(event);
                        }
                    } else {
                        hideControllerIfVisible();
                    }

                    // First key down - start timer and seek
                    rightKeyDown = true;
                    longPressRightHandled = false;
                    keyPressHandler.removeCallbacks(rightLongPressRunnable);
                    keyPressHandler.postDelayed(rightLongPressRunnable, LONG_PRESS_TIMEOUT_MS);
                    // Also seek forward on first press
                    seekBy(SEEK_STEP_MS);
                }
                return true;
            } else if (event.getAction() == KeyEvent.ACTION_UP) {
                keyPressHandler.removeCallbacks(rightLongPressRunnable);
                rightKeyDown = false;
                longPressRightHandled = false;
                return true;
            } else if (event.isCanceled()) {
                keyPressHandler.removeCallbacks(rightLongPressRunnable);
                rightKeyDown = false;
                longPressRightHandled = false;
                return true;
            }
        }
        
        // Handle Left arrow - always seek backward
        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
            boolean controllerVisible = playerView != null && playerView.isControllerFullyVisible();
            boolean focusInControls = isFocusInControlsOverlay();

            if (!controllerVisible && !focusInControls) {
                if (event.getAction() == KeyEvent.ACTION_DOWN) {
                    if (event.getRepeatCount() == 0) {
                        seekBy(-SEEK_STEP_MS);
                    }
                    return true;
                }
                if (event.getAction() == KeyEvent.ACTION_UP) {
                    return true;
                }
            }
        }
        return super.dispatchKeyEvent(event);
    }

    private boolean isFocusInControlsOverlay() {
        if (controlsOverlay == null) {
            return false;
        }
        View current = getCurrentFocus();
        while (current instanceof View) {
            if (current == controlsOverlay) {
                return true;
            }
            android.view.ViewParent parent = current.getParent();
            if (!(parent instanceof View)) {
                break;
            }
            current = (View) parent;
        }
        return false;
    }

    private void hideControllerIfVisible() {
        if (playerView != null && playerView.isControllerFullyVisible()) {
            playerView.hideController();
        }
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
        // Clean up TV static effect
        stopTvStaticEffect();
        if (staticHandler != null) {
            staticHandler.removeCallbacksAndMessages(null);
        }
        
        // Clean up loading bar animation
        if (loadingBarAnimator != null && loadingBarAnimator.isRunning()) {
            loadingBarAnimator.cancel();
        }
        
        // Clean up dots animation
        if (dotsAnimator != null && dotsAnimator.isRunning()) {
            dotsAnimator.cancel();
        }
        
        if (player != null) {
            player.removeListener(playbackListener);
            player.stop();
            player.release();
            player = null;
        }
        hideNextOverlay();
        cancelTitleFade();
        notifyFlutterPlaybackFinished();
        keyPressHandler.removeCallbacksAndMessages(null);
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
                String methodName;
                if (PROVIDER_REAL_DEBRID.equals(provider)) {
                    methodName = "realDebridPlaybackFinished";
                } else {
                    methodName = "torboxPlaybackFinished";
                }
                channel.invokeMethod(methodName, null);
            } catch (Exception ignored) {
            }
        }
    }

    private void updateChannelBadge(@Nullable String name) {
        if (channelBadgeView == null) {
            return;
        }

        if (!showChannelName) {
            channelBadgeView.setVisibility(View.GONE);
            return;
        }

        String displayName = name != null ? name.trim() : "";
        boolean hasNumber = currentChannelNumber > 0;

        if (!hasNumber && displayName.isEmpty()) {
            channelBadgeView.setVisibility(View.GONE);
            return;
        }

        StringBuilder builder = new StringBuilder();
        if (hasNumber) {
            builder.append(String.format(Locale.US, "CH %02d", currentChannelNumber));
            if (!displayName.isEmpty()) {
                builder.append("  •  ");
            }
        }
        if (!displayName.isEmpty()) {
            builder.append(displayName.toUpperCase(Locale.US));
        }

        channelBadgeView.setText(builder.toString());
        channelBadgeView.setVisibility(View.VISIBLE);
    }
}
