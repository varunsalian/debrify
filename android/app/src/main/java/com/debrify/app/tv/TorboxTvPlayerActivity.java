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
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import android.media.audiofx.LoudnessEnhancer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AlertDialog;
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
import com.debrify.app.util.SubtitleSettings;

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
    private static final String PROVIDER_PIKPAK = "pikpak";

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
    private static final long CONTROLS_AUTO_HIDE_DELAY_MS = 4000L;
    private static final int CHANNEL_JUMP_MAX_DIGITS = 10; // Support up to 10 digits

    // PikPak cold storage retry constants
    private static final int PIKPAK_MAX_RETRIES = 5;
    private static final int PIKPAK_METADATA_TIMEOUT_MS = 10000; // 10 seconds to wait for metadata
    private static final int PIKPAK_BASE_DELAY_MS = 2000; // 2 seconds base delay
    private static final int PIKPAK_MAX_DELAY_MS = 18000; // 18 seconds max delay

    private String provider;
    private PlayerView playerView;
    private ExoPlayer player;
    private DefaultTrackSelector trackSelector;
    private RenderersFactory renderersFactory;
    private DefaultBandwidthMeter bandwidthMeter;
    private Player.Listener subtitleListener; // Track subtitle listener for proper cleanup
    private Player.Listener trackChangeListener; // Track listener for proper cleanup on channel switch
    private long currentTargetBufferMs = DEFAULT_TARGET_BUFFER_MS;
    private TextView titleView;
    private TextView hintView;
    private View broadcastLowerThird;
    private TextView titleBadgeText;
    private TextView channelNumberView;
    private TextView channelNameView;
    private Runnable broadcastLowerThirdFadeOutRunnable;
    private TextView qualityWatermark;
    private View controlsOverlay;
    private TextView debrifyTimeDisplay;
    private View debrifyProgressLine;
    private View buttonsRow;
    private View pauseButton;
    private View audioButton;
    private View subtitleButton;
    private View aspectButton;
    private View nightModeButton;
    private View speedButton;
    private int nightModeIndex = 2;  // Medium by default
    private LoudnessEnhancer loudnessEnhancer = null;
    private View guideButton;
    private View channelNextButton;
    private TextView debrifyTimeCurrent;
    private TextView debrifyTimeTotal;
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
    // Unified Channel Guide
    private View unifiedGuideOverlay;
    private View unifiedGuidePanel;
    private EditText unifiedGuideSearch;
    private RecyclerView unifiedGuideList;
    private ChannelSearchAdapter unifiedGuideAdapter;
    private TextView unifiedGuideCurrentNumber;
    private TextView unifiedGuideChannelCount;
    private TextWatcher unifiedGuideTextWatcher;
    private boolean unifiedGuideVisible = false;
    private View loadingBarContainer;
    private View loadingBar;
    private android.animation.ValueAnimator loadingBarAnimator;
    private View loadingIndicator;
    private TextView loadingText;
    private View loadingDot1;
    private View loadingDot2;
    private View loadingDot3;
    private android.animation.ValueAnimator dotsAnimator;

    private boolean controlsMenuVisible = false;
    private final Handler controlsMenuHandler = new Handler(Looper.getMainLooper());
    private final Runnable hideControlsMenuRunnable = () -> {
        // Don't hide if user is actively navigating the controls
        if (isFocusInControlsOverlay()) {
            // Reschedule hide for later since user is still navigating
            scheduleHideControlsMenu();
        } else {
            hideControlsMenu();
        }
    };
    private final Runnable updateProgressBarRunnable = new Runnable() {
        @Override
        public void run() {
            updateControlsMenuProgressBar();
            if (controlsMenuVisible) {
                controlsMenuHandler.postDelayed(this, 100); // Update every 100ms
            }
        }
    };
    private boolean reopenControlsMenuAfterSeek = false;
    private boolean resumePlaybackOnSeekbarClose = false;

    // Custom Seekbar Views
    private View seekbarOverlay;
    private View seekbarProgress;
    private View seekbarHandle;
    private TextView seekbarCurrentTime;
    private TextView seekbarTotalTime;
    private TextView seekbarSpeedIndicator;
    private long seekbarPosition = 0;
    private long videoDuration = 0;
    private boolean seekbarVisible = false;
    private float currentSeekSpeed = 1.0f;
    private int playbackSpeedIndex = 2; // Default to 1.0x
    private final float[] playbackSpeeds = new float[] {0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f};
    private final String[] playbackSpeedLabels = new String[] {"0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x"};
    private final int[] nightModeGains = new int[] {0, 500, 1000, 1500, 2000, 2500, 3000, 5000};  // millibels
    private final String[] nightModeLabels = new String[] {"Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby"};

    private final ArrayList<ChannelEntry> channelDirectoryEntries = new ArrayList<>();
    private final ArrayList<ChannelEntry> filteredChannelEntries = new ArrayList<>();
    private android.animation.ValueAnimator staticAnimator;
    private Handler staticHandler = new Handler(Looper.getMainLooper());

    // Seek feedback manager
    private SeekFeedbackManager seekFeedbackManager;
    private final Handler keyPressHandler = new Handler(Looper.getMainLooper());

    // Double-back to exit
    private long lastBackPressTime = 0;
    private static final long BACK_PRESS_INTERVAL_MS = 2000; // 2 seconds
    private final Handler channelOverlayHandler = new Handler(Looper.getMainLooper());
    private ArrayList<Bundle> magnetQueue = new ArrayList<>();
    private int resizeModeIndex = 1;  // Fill by default
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
    private int playedCount = 0;
    private long lastChannelSwitchTime = 0;
    private static final long CHANNEL_SWITCH_COOLDOWN_MS = 2000L; // 2 second cooldown
    private static final int SEEK_LONG_PRESS_THRESHOLD = 3;

    // PikPak cold storage retry state
    private boolean isPikPakRetrying = false;
    private int pikPakRetryCount = 0;
    private int pikPakRetryId = 0; // Cancellation token
    private String currentStreamProvider = null; // Track provider of current stream
    private String currentStreamUrl = null;
    private String currentStreamTitle = null;
    private final Handler pikPakRetryHandler = new Handler(Looper.getMainLooper());
    private View pikPakRetryOverlay;
    private TextView pikPakRetryText;

    // Subtitle Settings Panel
    private View subtitleSettingsRoot;
    private boolean subtitleSettingsVisible = false;
    private View subtitleColumnTrack;
    private View subtitleColumnSize;
    private View subtitleColumnStyle;
    private View subtitleColumnColor;
    private View subtitleColumnBg;
    private View subtitleResetButton;
    private TextView subtitleValueTrack;
    private TextView subtitleValueSize;
    private TextView subtitleValueStyle;
    private TextView subtitleValueColor;
    private TextView subtitleValueBg;
    private View subtitleColorSwatch;
    private TextView subtitlePreviewText;
    private final ArrayList<TrackOption> subtitleTrackOptions = new ArrayList<>();
    private int currentSubtitleTrackIndex = 0;

    private final Random random = new Random();
    private final Runnable hideTitleRunnable = this::fadeOutTitle;
    private final Runnable hideNextOverlayRunnable = this::performHideNextOverlay;
    private final Runnable hideChannelOverlayRunnable = this::performHideChannelOverlay;
    private final Player.Listener playbackListener = new Player.Listener() {
        @Override
        public void onPlaybackStateChanged(int playbackState) {
            if (playbackState == Player.STATE_READY) {
                if (startFromRandom && !randomApplied) {
                    maybeSeekRandomly();
                }
                // Initialize night mode if needed
                if (loudnessEnhancer == null && nightModeIndex > 0) {
                    initializeLoudnessEnhancer();
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

        @Override
        public void onAudioSessionIdChanged(int audioSessionId) {
            // Reinitialize night mode effect when audio session changes
            if (nightModeIndex > 0 && audioSessionId != 0) {
                releaseLoudnessEnhancer();
                initializeLoudnessEnhancer();
            }
        }
    };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_torbox_tv_player);

        // Load default player settings from Flutter's SharedPreferences
        loadPlayerDefaults();

        playerView = findViewById(R.id.player_view);
        titleView = findViewById(R.id.player_title);
        hintView = findViewById(R.id.player_hint);
        broadcastLowerThird = findViewById(R.id.player_broadcast_lower_third);
        titleBadgeText = findViewById(R.id.player_title_badge_text);
        channelNumberView = findViewById(R.id.player_channel_number);
        channelNameView = findViewById(R.id.player_channel_name);
        qualityWatermark = findViewById(R.id.player_quality_watermark);
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
        // Unified Channel Guide views
        unifiedGuideOverlay = findViewById(R.id.unified_guide_overlay);
        unifiedGuidePanel = findViewById(R.id.unified_guide_panel);
        unifiedGuideSearch = findViewById(R.id.unified_guide_search);
        unifiedGuideList = findViewById(R.id.unified_guide_list);
        unifiedGuideCurrentNumber = findViewById(R.id.unified_guide_current_number);
        unifiedGuideChannelCount = findViewById(R.id.unified_guide_channel_count);
        loadingBarContainer = findViewById(R.id.player_loading_bar_container);
        loadingBar = findViewById(R.id.player_loading_bar);
        loadingIndicator = findViewById(R.id.player_loading_indicator);
        loadingText = findViewById(R.id.player_loading_text);
        loadingDot1 = findViewById(R.id.loading_dot_1);
        loadingDot2 = findViewById(R.id.loading_dot_2);
        loadingDot3 = findViewById(R.id.loading_dot_3);

        // Initialize PikPak retry overlay (reuse loading indicator for now)
        setupPikPakRetryOverlay();

        // Initialize Custom Seekbar Views
        seekbarOverlay = findViewById(R.id.seekbar_overlay);
        seekbarProgress = findViewById(R.id.seekbar_progress);
        seekbarHandle = findViewById(R.id.seekbar_handle);
        seekbarCurrentTime = findViewById(R.id.seekbar_current_time);
        seekbarTotalTime = findViewById(R.id.seekbar_total_time);
        seekbarSpeedIndicator = findViewById(R.id.seekbar_speed_indicator);

        // Initialize Subtitle Settings Panel Views
        subtitleSettingsRoot = findViewById(R.id.subtitle_settings_root);
        subtitleColumnTrack = findViewById(R.id.subtitle_column_track);
        subtitleColumnSize = findViewById(R.id.subtitle_column_size);
        subtitleColumnStyle = findViewById(R.id.subtitle_column_style);
        subtitleColumnColor = findViewById(R.id.subtitle_column_color);
        subtitleColumnBg = findViewById(R.id.subtitle_column_bg);
        subtitleValueTrack = findViewById(R.id.subtitle_value_track);
        subtitleValueSize = findViewById(R.id.subtitle_value_size);
        subtitleValueStyle = findViewById(R.id.subtitle_value_style);
        subtitleValueColor = findViewById(R.id.subtitle_value_color);
        subtitleValueBg = findViewById(R.id.subtitle_value_bg);
        subtitleColorSwatch = findViewById(R.id.subtitle_color_swatch);
        subtitlePreviewText = findViewById(R.id.subtitle_preview_text);
        subtitleResetButton = findViewById(R.id.subtitle_reset_button);

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

        setupUnifiedGuide(intent);
        runOnUiThread(() -> {
            updateChannelBadge(currentChannelName);
            updateTitleBadge(initialTitle);
            updateQualityBadge(initialTitle);
        });

        setupBackPressHandler();

        // Initialize seek feedback manager
        seekFeedbackManager = new SeekFeedbackManager(findViewById(android.R.id.content));

        initialisePlayer();
        applyUiPreferences(initialTitle);
        setupControllerUi();
        setupCustomSeekbar();
        // Pass provider to enable PikPak cold storage retry for first video
        playMedia(initialUrl, initialTitle, provider);
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
                .setPreferredTextLanguage("en")
                .setPreferredAudioMimeType("audio/opus")
                .build());

        LoadControl loadControl = buildLoadControl(bandwidthMeter.getBitrateEstimate());
        createPlayer(loadControl);
    }

    @OptIn(markerClass = UnstableApi.class)
    private void createPlayer(LoadControl loadControl) {
        // Release night mode effect before releasing player to prevent memory leak
        releaseLoudnessEnhancer();

        if (player != null) {
            player.removeListener(playbackListener);
            // Clear track change listener reference (old player is being released)
            trackChangeListener = null;
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
            // Remove previous subtitle listener if it exists
            if (subtitleListener != null) {
                player.removeListener(subtitleListener);
            }
            // Create and store new subtitle listener
            subtitleListener = new Player.Listener() {
                @Override
                public void onCues(androidx.media3.common.text.CueGroup cueGroup) {
                    if (subtitleOverlay != null) {
                        subtitleOverlay.setCues(cueGroup.cues);
                    }
                }
            };
            player.addListener(subtitleListener);
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
            // Apply subtitle settings from preferences
            applySubtitleSettings();
        }
        playerView.requestFocus();

        // Reinitialize night mode effect with new audio session if it was active
        if (nightModeIndex > 0) {
            initializeLoudnessEnhancer();
        }
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
        // Old centered title is replaced by the new badge, always hide it
        if (titleView != null) {
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
        debrifyTimeDisplay = playerView.findViewById(R.id.debrify_time_display);
        debrifyTimeCurrent = playerView.findViewById(R.id.debrify_time_current);
        debrifyTimeTotal = playerView.findViewById(R.id.debrify_time_total);
        debrifyProgressLine = playerView.findViewById(R.id.debrify_progress_line);
        buttonsRow = playerView.findViewById(R.id.debrify_controls_buttons);
        pauseButton = playerView.findViewById(R.id.debrify_pause_button);
        nightModeButton = playerView.findViewById(R.id.debrify_night_mode_button);
        audioButton = playerView.findViewById(R.id.debrify_audio_button);
        subtitleButton = playerView.findViewById(R.id.debrify_subtitle_button);
        aspectButton = playerView.findViewById(R.id.debrify_aspect_button);
        speedButton = playerView.findViewById(R.id.debrify_speed_button);
        guideButton = playerView.findViewById(R.id.debrify_guide_button);
        channelNextButton = playerView.findViewById(R.id.debrify_channel_next_button);
        DefaultTimeBar timeBar = playerView.findViewById(androidx.media3.ui.R.id.exo_progress);
        View nextButton = playerView.findViewById(R.id.debrify_next_button);

        if (controlsOverlay != null) {
            controlsOverlay.setVisibility(View.GONE);
            controlsOverlay.setAlpha(0f);
            // Ensure broadcast lower-third starts hidden
            if (broadcastLowerThird != null) {
                broadcastLowerThird.setVisibility(View.GONE);
            }
        }

        if (buttonsRow != null) {
            buttonsRow.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
        }

        if (debrifyTimeDisplay != null) {
            if (hideSeekbar) {
                debrifyTimeDisplay.setVisibility(View.GONE);
            } else if (hideOptions) {
                debrifyTimeDisplay.setVisibility(View.VISIBLE);
            }
        }

        // Focus listener to extend timer when navigating
        View.OnFocusChangeListener extendTimerOnFocus = (v, hasFocus) -> {
            if (hasFocus && controlsMenuVisible) {
                // Reset timer when user navigates to a button
                scheduleHideControlsMenu();
            }
        };

        if (pauseButton != null) {
            pauseButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            pauseButton.setOnClickListener(v -> {
                togglePlayPause();
                if (player != null && player.isPlaying()) {
                    scheduleHideControlsMenu();
                } else {
                    cancelScheduledHideControlsMenu();
                }
            });
            pauseButton.setOnFocusChangeListener(extendTimerOnFocus);
            updatePauseButtonLabel();
        }

        if (nightModeButton != null) {
            nightModeButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            nightModeButton.setOnClickListener(v -> {
                showNightModeDialog();
            });
            nightModeButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (audioButton != null) {
            audioButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            audioButton.setOnClickListener(v -> {
                showAudioSelectionDialog();
                scheduleHideControlsMenu();
            });
            audioButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (subtitleButton != null) {
            subtitleButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            subtitleButton.setOnClickListener(v -> {
                hideControlsMenu();
                showSubtitleSettingsPanel();
            });
            subtitleButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (aspectButton != null) {
            aspectButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            aspectButton.setOnClickListener(v -> {
                cycleAspectRatio();
                scheduleHideControlsMenu();
            });
            aspectButton.setOnFocusChangeListener(extendTimerOnFocus);
            updateAspectButtonLabel();
        }

        if (speedButton != null) {
            speedButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            speedButton.setOnClickListener(v -> {
                cyclePlaybackSpeed();
                scheduleHideControlsMenu();
            });
            speedButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (guideButton != null) {
            guideButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            guideButton.setOnClickListener(v -> handleControlAction("guide"));
            guideButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (channelNextButton != null) {
            channelNextButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            channelNextButton.setOnClickListener(v -> handleControlAction("channel_next"));
            channelNextButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (nextButton != null) {
            nextButton.setVisibility(hideOptions ? View.GONE : View.VISIBLE);
            nextButton.setOnClickListener(v -> handleControlAction("stream_next"));
            nextButton.setOnFocusChangeListener(extendTimerOnFocus);
        }

        if (timeBar != null) {
            timeBar.setVisibility(View.GONE);
        }

        // Keep controller enabled but disable auto-show - we'll manage visibility manually
        playerView.setControllerAutoShow(false);
    }

    private void updatePauseButtonLabel() {
        if (pauseButton == null) {
            return;
        }
        boolean playing = player != null && player.isPlaying();
        int iconRes = playing ? R.drawable.ic_pause : R.drawable.ic_play;
        String labelText = playing ? "PAUSE" : "PLAY";

        // TV broadcast style: button is a LinearLayout with ImageView and TextView children
        ImageView pauseIcon = pauseButton.findViewById(R.id.debrify_pause_icon);
        TextView pauseLabel = pauseButton.findViewById(R.id.debrify_pause_label);

        if (pauseIcon != null) {
            pauseIcon.setImageResource(iconRes);
        }
        if (pauseLabel != null) {
            pauseLabel.setText(labelText);
        }
    }

    private void updateAspectButtonLabel() {
        // Icon-only design: no text label to update
        // State is visual only through cycling
    }

    private void updateControlsMenuProgressBar() {
        if (player == null) {
            return;
        }

        long currentPosition = player.getCurrentPosition();
        long duration = player.getDuration();

        if (duration <= 0) {
            return;
        }

        // Update time displays (TV broadcast style: separate current and total)
        if (debrifyTimeCurrent != null) {
            debrifyTimeCurrent.setText(formatTime(currentPosition));
        }
        if (debrifyTimeTotal != null) {
            debrifyTimeTotal.setText(formatTime(duration));
        }
        // Fallback for old combined display
        if (debrifyTimeDisplay != null) {
            debrifyTimeDisplay.setText(formatTime(currentPosition) + " / " + formatTime(duration));
        }

        // Update progress line width
        if (debrifyProgressLine != null) {
            float progressPercentage = (float) currentPosition / (float) duration;
            View parent = (View) debrifyProgressLine.getParent();
            if (parent != null) {
                int parentWidth = parent.getWidth();
                if (parentWidth > 0) {
                    int progressWidth = (int) (parentWidth * progressPercentage);
                    ViewGroup.LayoutParams layoutParams = debrifyProgressLine.getLayoutParams();
                    layoutParams.width = progressWidth;
                    debrifyProgressLine.setLayoutParams(layoutParams);
                }
            }
        }
    }

    private void startProgressBarUpdates() {
        stopProgressBarUpdates(); // Stop any existing updates
        controlsMenuHandler.post(updateProgressBarRunnable);
    }

    private void stopProgressBarUpdates() {
        controlsMenuHandler.removeCallbacks(updateProgressBarRunnable);
    }

    private void handleControlAction(String action) {
        switch (action) {
            case "seek":
                hideControlsMenu();
                showSeekbar(true, true);
                break;
            case "guide":
                hideControlsMenu();
                if (!channelDirectoryEntries.isEmpty()) {
                    showUnifiedGuide(true); // Focus search bar
                } else {
                    Toast.makeText(this, "Channel guide unavailable", Toast.LENGTH_SHORT).show();
                }
                break;
            case "channel_next":
                hideControlsMenu();
                requestNextChannel();
                break;
            case "stream_next":
                hideControlsMenu();
                requestNextStream();
                break;
            default:
                break;
        }
    }

    private void showControlsMenu() {
        if (controlsOverlay == null) {
            return;
        }
        cancelScheduledHideControlsMenu();

        // Hide subtitles when controls menu is shown
        if (subtitleOverlay != null) {
            subtitleOverlay.setVisibility(View.GONE);
        }

        // Cancel any ongoing animations to prevent race conditions
        controlsOverlay.animate().cancel();

        if (!controlsMenuVisible) {
            controlsMenuVisible = true;
            setControlsMenuChildrenVisible(true);
            controlsOverlay.setVisibility(View.VISIBLE);
            controlsOverlay.setAlpha(0f);
            controlsOverlay.animate()
                    .alpha(1f)
                    .setDuration(180L)
                    .withEndAction(() -> {
                        if (controlsOverlay != null) {
                            controlsOverlay.setAlpha(1f);
                        }
                    })
                    .start();
            if (pauseButton != null) {
                pauseButton.post(() -> {
                    if (pauseButton != null) {
                        pauseButton.requestFocus();
                    }
                });
            }
        } else {
            // Menu already visible, just make sure it's fully visible and focused
            controlsOverlay.setAlpha(1f);
            controlsOverlay.setVisibility(View.VISIBLE);
            if (pauseButton != null) {
                pauseButton.post(() -> {
                    if (pauseButton != null) {
                        pauseButton.requestFocus();
                    }
                });
            }
        }
        updatePauseButtonLabel();

        // Show channel badge when controls appear (if enabled and has valid channel info)
        if (showChannelName && (currentChannelNumber > 0 || !currentChannelName.isEmpty())) {
            showChannelBadgeWithAnimation();
        }

        // Show title badge when controls appear (if enabled and has valid title)
        if (showVideoTitle && titleBadgeText != null && titleBadgeText.getText() != null
                && !titleBadgeText.getText().toString().isEmpty()) {
            showTitleBadgeWithAnimation();
        }

        // Start updating the progress bar
        startProgressBarUpdates();
    }

    private void hideControlsMenu() {
        if (controlsOverlay == null) {
            cancelScheduledHideControlsMenu();
            return;
        }

        // Cancel any ongoing animations to prevent race conditions
        controlsOverlay.animate().cancel();

        if (!controlsMenuVisible) {
            // Already hidden, just make sure state is consistent
            controlsOverlay.setVisibility(View.GONE);
            controlsOverlay.setAlpha(0f);
            // Ensure broadcast lower-third is also hidden
            hideBroadcastLowerThird();
            cancelScheduledHideControlsMenu();
            return;
        }

        cancelScheduledHideControlsMenu();
        controlsMenuVisible = false;

        // Stop updating the progress bar
        stopProgressBarUpdates();

        // Hide broadcast lower-third IMMEDIATELY (synchronous)
        hideBroadcastLowerThird();

        controlsOverlay.animate()
                .alpha(0f)
                .setDuration(140L)
                .withEndAction(() -> {
                    if (controlsOverlay != null && !controlsMenuVisible) {
                        controlsOverlay.setVisibility(View.GONE);
                        controlsOverlay.setAlpha(0f);
                        setControlsMenuChildrenVisible(false);
                        // Redundant safety call (already called above)
                        hideBroadcastLowerThird();
                        // Show subtitles when controls menu is hidden
                        if (subtitleOverlay != null) {
                            subtitleOverlay.setVisibility(View.VISIBLE);
                        }
                    }
                })
                .start();
    }

    private void scheduleHideControlsMenu() {
        if (!controlsMenuVisible) {
            return;
        }
        controlsMenuHandler.removeCallbacks(hideControlsMenuRunnable);
        if (player != null && player.isPlaying()) {
            controlsMenuHandler.postDelayed(hideControlsMenuRunnable, CONTROLS_AUTO_HIDE_DELAY_MS);
        }
    }

    private void cancelScheduledHideControlsMenu() {
        controlsMenuHandler.removeCallbacks(hideControlsMenuRunnable);
    }

    private void handlePlayPauseToggleFromCenter() {
        boolean wasPlaying = player != null && player.isPlaying();
        showControlsMenu();
        togglePlayPause();
        if (player != null && player.isPlaying()) {
            scheduleHideControlsMenu();
        } else if (wasPlaying) {
            cancelScheduledHideControlsMenu();
        }
    }

    private void setControlsMenuChildrenVisible(boolean visible) {
        int target = visible ? View.VISIBLE : View.GONE;
        if (buttonsRow != null) {
            buttonsRow.setVisibility(target);
        }
        if (!hideSeekbar && debrifyTimeDisplay != null) {
            debrifyTimeDisplay.setVisibility(target);
        }
        if (pauseButton != null) {
            pauseButton.setVisibility(target);
        }
        if (nightModeButton != null) {
            nightModeButton.setVisibility(target);
        }
        if (audioButton != null) {
            audioButton.setVisibility(target);
        }
        if (subtitleButton != null) {
            subtitleButton.setVisibility(target);
        }
        if (aspectButton != null) {
            aspectButton.setVisibility(target);
        }
        if (speedButton != null) {
            speedButton.setVisibility(target);
        }
        if (guideButton != null) {
            guideButton.setVisibility(target);
        }
        if (channelNextButton != null) {
            channelNextButton.setVisibility(target);
        }
        View nextButton = playerView != null ? playerView.findViewById(R.id.debrify_next_button) : null;
        if (nextButton != null) {
            nextButton.setVisibility(target);
        }
    }

    private void cyclePlaybackSpeed() {
        if (player == null) {
            return;
        }
        playbackSpeedIndex = (playbackSpeedIndex + 1) % playbackSpeeds.length;
        float speed = playbackSpeeds[playbackSpeedIndex];
        player.setPlaybackSpeed(speed);
        Toast.makeText(this, "Speed: " + playbackSpeedLabels[playbackSpeedIndex], Toast.LENGTH_SHORT).show();
    }

    // Night mode (dynamic range compression)
    private void initializeLoudnessEnhancer() {
        if (player == null) {
            return;
        }

        try {
            int audioSessionId = player.getAudioSessionId();
            if (audioSessionId == 0) {
                return;  // Invalid session
            }

            releaseLoudnessEnhancer();  // Clean up any existing instance

            loudnessEnhancer = new LoudnessEnhancer(audioSessionId);
            loudnessEnhancer.setEnabled(nightModeIndex > 0);
            if (nightModeIndex > 0) {
                loudnessEnhancer.setTargetGain(nightModeGains[nightModeIndex]);
            }
        } catch (Exception e) {
            android.util.Log.e("TorboxTvPlayer", "Failed to initialize LoudnessEnhancer", e);
            loudnessEnhancer = null;
        }
    }

    private void releaseLoudnessEnhancer() {
        if (loudnessEnhancer != null) {
            try {
                loudnessEnhancer.release();
            } catch (Exception e) {
                android.util.Log.e("TorboxTvPlayer", "Error releasing LoudnessEnhancer", e);
            }
            loudnessEnhancer = null;
        }
    }

    /**
     * Load default player settings from Flutter's SharedPreferences.
     * Keys are prefixed with "flutter." as per flutter shared_preferences package.
     */
    private void loadPlayerDefaults() {
        try {
            android.content.SharedPreferences prefs = getSharedPreferences(
                "FlutterSharedPreferences", android.content.Context.MODE_PRIVATE);

            // Load aspect index for TV (separate from mobile)
            // TV only: 0=Fit, 1=Fill, 2=Zoom (default: 0=Fit)
            resizeModeIndex = (int) prefs.getLong("flutter.player_default_aspect_index_tv", 0);
            resizeModeIndex = Math.max(0, Math.min(resizeModeIndex, resizeModes.length - 1));

            // Load night mode index (default: 2 = Medium)
            nightModeIndex = (int) prefs.getLong("flutter.player_night_mode_index", 2);
            nightModeIndex = Math.max(0, Math.min(nightModeIndex, nightModeGains.length - 1));

            android.util.Log.d("TorboxTvPlayer", "Loaded defaults - aspect=" + resizeModeIndex + ", nightMode=" + nightModeIndex);
        } catch (Exception e) {
            android.util.Log.e("TorboxTvPlayer", "Error loading player defaults", e);
            // Keep default values
        }
    }

    private void showNightModeDialog() {
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Night Mode")
                .setSingleChoiceItems(nightModeLabels, nightModeIndex, (d, which) -> {
                    applyNightMode(which);
                    d.dismiss();
                })
                .setNegativeButton("Cancel", null)
                .create();

        dialog.show();
    }

    private void applyNightMode(int index) {
        nightModeIndex = index;

        if (nightModeIndex == 0) {
            // Turn off
            if (loudnessEnhancer != null) {
                loudnessEnhancer.setEnabled(false);
            }
        } else {
            // Turn on or adjust
            if (loudnessEnhancer == null) {
                initializeLoudnessEnhancer();
            }
            // Check if initialization succeeded before using
            if (loudnessEnhancer != null) {
                loudnessEnhancer.setEnabled(true);
                loudnessEnhancer.setTargetGain(nightModeGains[nightModeIndex]);
            }
        }

        showToast("Night Mode: " + nightModeLabels[nightModeIndex]);
    }

    private void setupCustomSeekbar() {
        if (seekbarOverlay == null) {
            return;
        }
        seekbarOverlay.setVisibility(View.GONE);
        seekbarOverlay.setOnKeyListener((v, keyCode, event) -> {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_DOWN) {
                hideSeekbar();
                return true;
            }
            return false;
        });
    }

    private void showSeekbar(boolean pauseVideo, boolean reopenMenu) {
        if (seekbarOverlay == null || player == null || seekbarVisible) {
            return;
        }

        // Get current position and duration
        seekbarPosition = player.getCurrentPosition();
        videoDuration = player.getDuration();

        if (videoDuration <= 0) {
            Toast.makeText(this, "Seeking not available", Toast.LENGTH_SHORT).show();
            return;
        }

        reopenControlsMenuAfterSeek = reopenMenu;
        boolean wasPlaying = player.isPlaying();
        resumePlaybackOnSeekbarClose = false;

        // Hide controls overlay while seek UI is open
        if (controlsMenuVisible) {
            hideControlsMenu();
        }

        // Reset seek speed indicator
        currentSeekSpeed = 1.0f;
        seekbarSpeedIndicator.setVisibility(View.GONE);

        // Update UI
        updateSeekbarUI();

        // Show seekbar overlay with fade-in
        seekbarVisible = true;
        seekbarOverlay.setVisibility(View.VISIBLE);
        seekbarOverlay.setAlpha(0f);
        seekbarOverlay.animate()
                .alpha(1f)
                .setDuration(200)
                .start();

        // Pause the video if required
        if (pauseVideo && wasPlaying) {
            resumePlaybackOnSeekbarClose = true;
            player.pause();
        }
    }

    private void hideSeekbar() {
        if (seekbarOverlay == null || !seekbarVisible) {
            return;
        }

        seekbarVisible = false;
        seekbarSpeedIndicator.setVisibility(View.GONE);
        final boolean reopenMenu = reopenControlsMenuAfterSeek;
        final boolean resumePlayback = resumePlaybackOnSeekbarClose;

        seekbarOverlay.animate()
                .alpha(0f)
                .setDuration(150)
                .withEndAction(() -> {
                    if (seekbarOverlay != null) {
                        seekbarOverlay.setVisibility(View.GONE);
                    }
                    if (resumePlayback && player != null && !player.isPlaying()) {
                        player.play();
                    }
                    if (reopenMenu) {
                        showControlsMenu();
                        scheduleHideControlsMenu();
                    }
                    resumePlaybackOnSeekbarClose = false;
                    reopenControlsMenuAfterSeek = false;
                })
                .start();
    }

    private void confirmSeekPosition() {
        if (player == null || !seekbarVisible) {
            return;
        }

        // Seek to the position
        player.seekTo(seekbarPosition);

        // Hide seekbar overlay
        hideSeekbar();
    }

    private void updateSeekbarUI() {
        if (seekbarProgress == null || seekbarHandle == null || seekbarCurrentTime == null || seekbarTotalTime == null) {
            return;
        }

        // Update time displays
        seekbarCurrentTime.setText(formatTime(seekbarPosition));
        seekbarTotalTime.setText(formatTime(videoDuration));

        // Update progress bar and handle position
        float progressPercent = (float) seekbarPosition / videoDuration;

        // Get the width of the seekbar background to calculate positions
        View seekbarBackground = findViewById(R.id.seekbar_background);
        if (seekbarBackground != null) {
            int totalWidth = seekbarBackground.getWidth();
            if (totalWidth > 0) {
                int progressWidth = (int) (totalWidth * progressPercent);

                ViewGroup.LayoutParams progressParams = seekbarProgress.getLayoutParams();
                progressParams.width = progressWidth;
                seekbarProgress.setLayoutParams(progressParams);

                // Position the handle
                int handleSize = seekbarHandle.getWidth();
                float handleX = progressWidth - (handleSize / 2f);
                seekbarHandle.setTranslationX(handleX);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UNIFIED CHANNEL GUIDE - Modern Streaming Style
    // Combines channel number pad and channel scanner into one elegant overlay
    // ═══════════════════════════════════════════════════════════════════════════════════

    private void setupUnifiedGuide(Intent intent) {
        if (unifiedGuideOverlay == null || unifiedGuideSearch == null || unifiedGuideList == null) {
            return;
        }

        unifiedGuideOverlay.setVisibility(View.GONE);
        unifiedGuideOverlay.setAlpha(0f);
        unifiedGuideOverlay.setFocusable(true);
        unifiedGuideOverlay.setFocusableInTouchMode(true);
        unifiedGuideOverlay.setOnClickListener(v -> hideUnifiedGuide());

        if (unifiedGuidePanel != null) {
            // Consume clicks on panel to prevent propagation to overlay (which dismisses)
            unifiedGuidePanel.setOnClickListener(v -> { /* consume click */ });
        }

        // Load channel directory from intent
        ArrayList<Bundle> directoryBundles;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            directoryBundles = intent.getParcelableArrayListExtra("channelDirectory", Bundle.class);
        } else {
            directoryBundles = intent.getParcelableArrayListExtra("channelDirectory");
        }

        if (directoryBundles != null) {
            for (int index = 0; index < directoryBundles.size(); index++) {
                Bundle bundle = directoryBundles.get(index);
                if (bundle == null) continue;
                String id = safeString(bundle.get("id"));
                if (id == null || id.isEmpty()) continue;
                String name = safeString(bundle.get("name"));
                int number = bundle.containsKey("channelNumber") ? bundle.getInt("channelNumber", -1) : -1;
                boolean isCurrent = bundle.getBoolean("isCurrent", false);
                if (currentChannelId != null && currentChannelId.equals(id)) {
                    isCurrent = true;
                    if (number > 0) currentChannelNumber = number;
                }
                channelDirectoryEntries.add(new ChannelEntry(id, name != null ? name : "", number, isCurrent, index));
            }
        }

        if (currentChannelNumber <= 0 && currentChannelId != null) {
            int lookedUp = resolveChannelNumberFromDirectory(currentChannelId);
            if (lookedUp > 0) currentChannelNumber = lookedUp;
        }

        if (channelDirectoryEntries.isEmpty()) return;

        filteredChannelEntries.clear();
        filteredChannelEntries.addAll(channelDirectoryEntries);

        // Setup adapter with new modern layout
        unifiedGuideAdapter = new ChannelSearchAdapter(filteredChannelEntries, this::requestChannelByEntry);
        unifiedGuideList.setLayoutManager(new LinearLayoutManager(this));
        unifiedGuideList.setHasFixedSize(false);
        unifiedGuideList.setItemAnimator(null);
        unifiedGuideList.setAdapter(unifiedGuideAdapter);

        // Setup search text watcher (store as field for cleanup in onDestroy)
        if (unifiedGuideTextWatcher != null) {
            unifiedGuideSearch.removeTextChangedListener(unifiedGuideTextWatcher);
        }
        unifiedGuideTextWatcher = new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { }
            @Override
            public void afterTextChanged(Editable s) {
                filterChannels(s != null ? s.toString() : "");
            }
        };
        unifiedGuideSearch.addTextChangedListener(unifiedGuideTextWatcher);

        // Update channel count display
        if (unifiedGuideChannelCount != null) {
            unifiedGuideChannelCount.setText(channelDirectoryEntries.size() + " channels");
        }

        markUnifiedGuideCurrentChannel(currentChannelId);
        if (unifiedGuideAdapter != null) {
            unifiedGuideAdapter.notifyDataSetChanged();
        }
    }

    private void showUnifiedGuide(boolean focusSearch) {
        if (unifiedGuideOverlay == null || unifiedGuideSearch == null || unifiedGuideList == null) {
            return;
        }
        if (channelDirectoryEntries.isEmpty()) {
            Toast.makeText(this, "Channel guide unavailable", Toast.LENGTH_SHORT).show();
            return;
        }
        if (unifiedGuideVisible) return;

        unifiedGuideVisible = true;
        hideControlsMenu();

        // Update current channel display
        if (unifiedGuideCurrentNumber != null) {
            unifiedGuideCurrentNumber.setText(currentChannelNumber > 0 ? String.valueOf(currentChannelNumber) : "--");
        }

        // Filter/reset list
        filterChannels(unifiedGuideSearch.getText() != null ? unifiedGuideSearch.getText().toString() : "");

        // Cancel any ongoing animations to prevent race conditions
        unifiedGuideOverlay.animate().cancel();
        if (unifiedGuidePanel != null) {
            unifiedGuidePanel.animate().cancel();
        }

        // Show with animation
        unifiedGuideOverlay.setVisibility(View.VISIBLE);
        unifiedGuideOverlay.setAlpha(0f);
        unifiedGuideOverlay.bringToFront();
        unifiedGuideOverlay.animate().alpha(1f).setDuration(200L).start();

        if (unifiedGuidePanel != null) {
            unifiedGuidePanel.setScaleX(0.95f);
            unifiedGuidePanel.setScaleY(0.95f);
            unifiedGuidePanel.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(200L)
                    .start();
        }

        if (focusSearch) {
            // Focus search bar (guide button triggered)
            unifiedGuideSearch.requestFocus();
            unifiedGuideSearch.post(() -> {
                unifiedGuideSearch.selectAll();
                showKeyboard(unifiedGuideSearch);
            });
        } else {
            // Focus first list item (DPAD_UP triggered)
            // Use post to ensure layout is complete before focusing
            final RecyclerView listRef = unifiedGuideList;
            listRef.post(() -> {
                RecyclerView.LayoutManager lm = listRef.getLayoutManager();
                if (lm != null && listRef.getAdapter() != null && listRef.getAdapter().getItemCount() > 0) {
                    // Scroll to position 0 first, then focus the view
                    lm.scrollToPosition(0);
                    listRef.post(() -> {
                        View first = lm.findViewByPosition(0);
                        if (first != null) {
                            first.requestFocus();
                        } else if (listRef.getChildCount() > 0) {
                            // Fallback: focus first visible child
                            listRef.getChildAt(0).requestFocus();
                        }
                    });
                }
            });
        }
    }

    private void hideUnifiedGuide() {
        if (unifiedGuideOverlay == null || !unifiedGuideVisible) {
            return;
        }
        // Guard against multiple calls during fade-out animation
        if (unifiedGuideOverlay.getAlpha() < 1f) {
            return;
        }

        hideKeyboard(unifiedGuideSearch);

        // Cancel any ongoing animations to prevent race conditions
        unifiedGuideOverlay.animate().cancel();
        if (unifiedGuidePanel != null) {
            unifiedGuidePanel.animate().cancel();
        }

        // Use final reference to avoid lambda capture issues
        final View overlayRef = unifiedGuideOverlay;
        overlayRef.animate()
                .alpha(0f)
                .setDuration(150L)
                .withEndAction(() -> {
                    // Only set flag to false after animation completes to prevent race condition
                    unifiedGuideVisible = false;
                    overlayRef.setVisibility(View.GONE);
                    overlayRef.setAlpha(1f);
                    // Restore focus to player view for proper TV D-pad navigation
                    if (playerView != null) {
                        playerView.requestFocus();
                    }
                })
                .start();
    }

    private boolean isUnifiedGuideVisible() {
        return unifiedGuideVisible && unifiedGuideOverlay != null && unifiedGuideOverlay.getVisibility() == View.VISIBLE;
    }

    private void markUnifiedGuideCurrentChannel(@Nullable String channelId) {
        if (channelId == null) return;
        for (ChannelEntry entry : channelDirectoryEntries) {
            entry.isCurrent = channelId.equals(entry.id);
        }
    }

    @Nullable
    private ChannelEntry findChannelEntryByNumber(int number) {
        if (number <= 0 || channelDirectoryEntries.isEmpty()) {
            return null;
        }
        for (ChannelEntry entry : channelDirectoryEntries) {
            if (entry.number == number) {
                return entry;
            }
        }
        return null;
    }

    private long getAcceleratedSeekStep(int repeatCount) {
        final long baseStep = 10_000L;          // 10 seconds
        final long acceleration = 2_000L;       // 2 seconds per repeat
        final long maxStep = 120_000L;          // 2 minutes cap

        long calculatedStep = baseStep + (repeatCount * acceleration);
        return Math.min(calculatedStep, maxStep);
    }

    private void seekForward(long stepMs) {
        if (player == null) {
            return;
        }
        seekbarPosition = Math.min(seekbarPosition + stepMs, videoDuration);
        updateSeekSpeed(stepMs);
        updateSeekbarUI();

        // NO visual feedback here - this is only called during long-press seekbar mode
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    private void seekBackward(long stepMs) {
        if (player == null) {
            return;
        }
        seekbarPosition = Math.max(seekbarPosition - stepMs, 0);
        updateSeekSpeed(stepMs);
        updateSeekbarUI();

        // NO visual feedback here - this is only called during long-press seekbar mode
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    private void updateSeekSpeed(long stepMs) {
        currentSeekSpeed = stepMs / 10_000f;  // Base is 10s = 1x

        if (currentSeekSpeed > 1.0f) {
            seekbarSpeedIndicator.setText(String.format(Locale.US, "→ %.1fx", currentSeekSpeed));
            seekbarSpeedIndicator.setVisibility(View.VISIBLE);
        } else {
            seekbarSpeedIndicator.setVisibility(View.GONE);
        }
    }

    private String formatTime(long timeMs) {
        if (timeMs <= 0) {
            return "00:00";
        }
        long totalSeconds = timeMs / 1000;
        long hours = totalSeconds / 3600;
        long minutes = (totalSeconds % 3600) / 60;
        long seconds = totalSeconds % 60;

        if (hours > 0) {
            return String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds);
        } else {
            return String.format(Locale.US, "%02d:%02d", minutes, seconds);
        }
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
        showLoadingBar(type, null, null);
    }

    private void showLoadingBar(LoadingType type, @Nullable Integer channelNum, @Nullable String channelName) {
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
            showBottomLoadingIndicator(type, channelNum, channelName);
            
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
    
    private void showBottomLoadingIndicator(LoadingType type, @Nullable Integer channelNum, @Nullable String channelName) {
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
                if (channelNum != null && channelName != null) {
                    text = String.format(Locale.US, "Loading channel %02d : %s", channelNum, channelName.toUpperCase());
                } else if (channelNum != null) {
                    text = String.format(Locale.US, "Loading channel %02d", channelNum);
                } else {
                    text = "Loading channel";
                }
            } else {
                textColor = Color.parseColor("#00FF00"); // Green
                dotColor = Color.parseColor("#00FF00");
                text = "Loading Stream";
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
        playMedia(url, title, null);
    }

    private void playMedia(String url, @Nullable String title, @Nullable String providerHint) {
        if (player == null || url == null || url.isEmpty()) {
            return;
        }

        // Clean up from previous channel/stream
        cancelPikPakRetry(); // Cancel any ongoing PikPak retry operations

        // Remove old track change listener to prevent accumulation
        if (trackChangeListener != null) {
            player.removeListener(trackChangeListener);
            trackChangeListener = null;
        }

        // Store current stream info for retry logic
        currentStreamUrl = url;
        currentStreamTitle = title;
        currentStreamProvider = providerHint;

        // Check if this is a PikPak stream and apply retry logic
        boolean isPikPak = PROVIDER_PIKPAK.equalsIgnoreCase(currentStreamProvider);

        android.util.Log.d("TorboxTvPlayer", "playMedia: url=" + url.substring(0, Math.min(50, url.length())) +
                ", title=" + title + ", provider=" + currentStreamProvider + ", isPikPak=" + isPikPak);

        if (isPikPak) {
            // Use PikPak retry logic for cold storage handling
            playPikPakVideoWithRetry(url, title);
        } else {
            // Standard playback for non-PikPak providers
            playMediaDirect(url, title);
        }
    }

    private void playMediaDirect(String url, @Nullable String title) {
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

        // Store listener reference for cleanup on channel switch
        trackChangeListener = new Player.Listener() {
            @Override
            public void onTracksChanged(Tracks tracks) {
                // Self-remove after first track change
                if (trackChangeListener == this) {
                    player.removeListener(this);
                    trackChangeListener = null;
                }
                ensureDefaultSubtitleSelected();
            }
        };
        player.addListener(trackChangeListener);
    }

    private void updateTitle(@Nullable String title) {
        // Don't show the old centered title anymore, only use the new badge
        // showTitleTemporarily(title);
        updateTitleBadge(title);
        updateQualityBadge(title);
    }

    /**
     * PikPak Cold Storage Retry Logic
     * PikPak uses "cold storage" where files that haven't been accessed recently need 10-30 seconds
     * to reactivate. This method implements retry logic with exponential backoff.
     */
    private void playPikPakVideoWithRetry(String url, @Nullable String title) {
        android.util.Log.d("TorboxTvPlayer", "PikPak: Starting retry logic for cold storage handling");

        // Cancel any previous retry loops
        pikPakRetryId++;
        final int myRetryId = pikPakRetryId;

        // Reset retry state
        pikPakRetryCount = 0;
        isPikPakRetrying = false;
        hidePikPakRetryOverlay();

        // Null safety check for player
        if (player == null) {
            android.util.Log.e("TorboxTvPlayer", "PikPak: Player is null, cannot attempt playback");
            return;
        }

        // Clear previous video's subtitles
        if (subtitleOverlay != null) {
            subtitleOverlay.setCues(java.util.Collections.emptyList());
        }

        // Prepare and play the media ONCE before retry loop
        MediaMetadata metadata = new MediaMetadata.Builder()
                .setTitle(title != null ? title : "")
                .build();
        final MediaItem item = new MediaItem.Builder()
                .setUri(url)
                .setMediaMetadata(metadata)
                .build();

        player.setMediaItem(item);
        player.prepare();
        player.play();

        playedCount += 1;
        updateTitle(title);

        // Start retry loop with attempt 0
        attemptPikPakPlaybackLoop(url, title, 0, myRetryId, item);
    }

    private void attemptPikPakPlaybackLoop(String url, @Nullable String title, int attemptNumber, int retryId, MediaItem mediaItem) {
        // Check if this retry has been cancelled
        if (pikPakRetryId != retryId) {
            android.util.Log.d("TorboxTvPlayer", "PikPak: Retry cancelled (token mismatch)");
            isPikPakRetrying = false;
            pikPakRetryCount = 0;
            hidePikPakRetryOverlay();
            return;
        }

        // Null safety check for player
        if (player == null) {
            android.util.Log.e("TorboxTvPlayer", "PikPak: Player is null, cannot continue playback");
            isPikPakRetrying = false;
            pikPakRetryCount = 0;
            hidePikPakRetryOverlay();
            return;
        }

        android.util.Log.d("TorboxTvPlayer", "PikPak: Playback attempt " + (attemptNumber + 1) + "/" + (PIKPAK_MAX_RETRIES + 1));

        // Calculate delay for this attempt (0 for first attempt, exponential backoff for subsequent)
        long delayMs;
        if (attemptNumber == 0) {
            delayMs = 0;
        } else {
            int calculatedDelay = PIKPAK_BASE_DELAY_MS * (1 << (attemptNumber - 1));
            delayMs = Math.min(calculatedDelay, PIKPAK_MAX_DELAY_MS);
        }

        // Monitor during BOTH the timeout period AND the delay period
        waitForPikPakMetadata(url, title, attemptNumber, retryId, delayMs, success -> {
            // Check if retry was cancelled during monitoring
            if (pikPakRetryId != retryId) {
                android.util.Log.d("TorboxTvPlayer", "PikPak: Retry cancelled during monitoring");
                return;
            }

            if (success) {
                // Video loaded successfully, exit retry loop
                android.util.Log.d("TorboxTvPlayer", "PikPak: Video loaded successfully, exiting retry loop");
                return;
            }

            // Check if this was the last attempt
            if (attemptNumber >= PIKPAK_MAX_RETRIES) {
                // All retries exhausted
                android.util.Log.e("TorboxTvPlayer", "PikPak: All retry attempts exhausted. Video failed to load.");

                // Clear state synchronously
                isPikPakRetrying = false;
                pikPakRetryCount = 0;
                hidePikPakRetryOverlay();

                if (!isFinishing()) {
                    runOnUiThread(() -> {
                        Toast.makeText(TorboxTvPlayerActivity.this,
                                "Video failed to load. Skipping to next...",
                                Toast.LENGTH_SHORT).show();

                        // Auto-advance to next video
                        pikPakRetryHandler.postDelayed(() -> requestNextStream(), 1500);
                    });
                }
                return;
            }

            // Video didn't load, need to retry
            // Update retry UI
            pikPakRetryCount = attemptNumber + 1;
            isPikPakRetrying = true;
            if (!isFinishing()) {
                showPikPakRetryOverlay("Reactivating video... (Attempt " + (attemptNumber + 2) + "/" + (PIKPAK_MAX_RETRIES + 1) + ")");
            }

            android.util.Log.d("TorboxTvPlayer", "PikPak: Video didn't load, monitoring for next attempt");

            // Continue to next attempt
            attemptPikPakPlaybackLoop(url, title, attemptNumber + 1, retryId, mediaItem);
        });
    }

    private void waitForPikPakMetadata(String url, @Nullable String title, int attemptNumber, int retryId,
                                       long additionalMonitoringMs, java.util.function.Consumer<Boolean> onComplete) {
        final long startTime = System.currentTimeMillis();
        final long totalTimeoutMs = PIKPAK_METADATA_TIMEOUT_MS + additionalMonitoringMs;

        final Runnable[] checkRunnable = new Runnable[1];
        checkRunnable[0] = new Runnable() {
            @Override
            public void run() {
                // Check if retry was cancelled
                if (pikPakRetryId != retryId) {
                    android.util.Log.d("TorboxTvPlayer", "PikPak: Metadata check cancelled");
                    // Clean up handler callbacks to prevent memory leaks
                    pikPakRetryHandler.removeCallbacks(this);
                    onComplete.accept(false);
                    return;
                }

                long elapsed = System.currentTimeMillis() - startTime;

                // Check if player state is ready or has duration (with null safety)
                final ExoPlayer currentPlayer = player;
                if (currentPlayer != null && (currentPlayer.getPlaybackState() == Player.STATE_READY || currentPlayer.getDuration() > 0)) {
                    android.util.Log.d("TorboxTvPlayer", "PikPak: Video metadata loaded successfully - file is ready!");

                    // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
                    // This prevents race conditions and ensures UI updates instantly
                    isPikPakRetrying = false;
                    pikPakRetryCount = 0;
                    hidePikPakRetryOverlay();

                    // Clean up handler callbacks
                    pikPakRetryHandler.removeCallbacks(this);

                    // Ensure subtitles are selected after successful load
                    // Use self-removing listener with timeout to prevent memory leaks
                    final Player.Listener trackListener = new Player.Listener() {
                        @Override
                        public void onTracksChanged(Tracks tracks) {
                            // Null check before removing listener
                            final ExoPlayer p = player;
                            if (p != null) {
                                p.removeListener(this);
                            }
                            ensureDefaultSubtitleSelected();
                        }
                    };
                    currentPlayer.addListener(trackListener);

                    // Ensure removal after timeout to prevent memory leak
                    pikPakRetryHandler.postDelayed(() -> {
                        if (player != null) {
                            player.removeListener(trackListener);
                        }
                    }, 5000);  // Remove after 5 seconds if onTracksChanged hasn't fired

                    onComplete.accept(true);
                    return;
                }

                // Check timeout (now includes additional monitoring period)
                if (elapsed >= totalTimeoutMs) {
                    android.util.Log.d("TorboxTvPlayer", "PikPak: Timeout waiting for metadata after " + totalTimeoutMs + "ms - file likely in cold storage");
                    // Clean up handler callbacks before timeout handling
                    pikPakRetryHandler.removeCallbacks(this);
                    onComplete.accept(false);
                    return;
                }

                // Continue checking
                pikPakRetryHandler.postDelayed(checkRunnable[0], 500);
            }
        };

        // Start checking
        pikPakRetryHandler.postDelayed(checkRunnable[0], 500);
    }


    private void showPikPakRetryOverlay(String message) {
        runOnUiThread(() -> {
            if (pikPakRetryOverlay != null) {
                pikPakRetryOverlay.setVisibility(View.VISIBLE);
            }
            if (pikPakRetryText != null) {
                pikPakRetryText.setText(message);
            }
        });
    }

    private void hidePikPakRetryOverlay() {
        runOnUiThread(() -> {
            if (pikPakRetryOverlay != null) {
                pikPakRetryOverlay.setVisibility(View.GONE);
            }
        });
    }

    private void setupPikPakRetryOverlay() {
        // Reuse the existing loading indicator for PikPak retry messages
        pikPakRetryOverlay = loadingIndicator;
        pikPakRetryText = loadingText;
    }

    private void cancelPikPakRetry() {
        // Increment retry ID to invalidate any ongoing retry operations
        pikPakRetryId++;
        isPikPakRetrying = false;
        pikPakRetryCount = 0;

        // Remove any pending retry callbacks
        if (pikPakRetryHandler != null) {
            pikPakRetryHandler.removeCallbacksAndMessages(null);
        }

        hidePikPakRetryOverlay();
        android.util.Log.d("TorboxTvPlayer", "PikPak: Retry operations cancelled");
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
                String nextProvider = safeString(payload.get("provider")); // Extract provider info

                if (nextUrl == null || nextUrl.isEmpty()) {
                    handleNoMoreStreams();
                    return;
                }

                android.util.Log.d("TorboxTvPlayer", "requestNextStream: received provider=" + nextProvider);

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

                playMedia(nextUrl, nextTitle, nextProvider); // Pass provider hint
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
                final String playProvider = switchData.provider;

                android.util.Log.d("TorboxTvPlayer", "requestNextChannel: received provider=" + playProvider);

                // Play the first video from the new channel
                playMedia(playUrl, playTitle, playProvider);
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

    private void showAudioSelectionDialog() {
        if (player == null || trackSelector == null) {
            return;
        }
        List<TrackOption> audioTracks = collectTrackOptions(C.TRACK_TYPE_AUDIO);
        if (audioTracks.isEmpty()) {
            showToast("No alternate audio tracks");
            return;
        }

        int checkedItem = -1;
        for (int i = 0; i < audioTracks.size(); i++) {
            TrackOption option = audioTracks.get(i);
            if (option.group.isTrackSelected(option.trackIndex)) {
                checkedItem = i;
                break;
            }
        }

        String[] labels = new String[audioTracks.size()];
        for (int i = 0; i < audioTracks.size(); i++) {
            labels[i] = audioTracks.get(i).label;
        }

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Audio Tracks")
                .setSingleChoiceItems(labels, checkedItem, (d, which) -> {
                    applyAudioTrack(audioTracks.get(which));
                    d.dismiss();
                })
                .setNegativeButton("Cancel", null)
                .create();

        dialog.show();
    }

    private void applyAudioTrack(TrackOption option) {
        if (trackSelector == null || option == null) {
            return;
        }
        DefaultTrackSelector.Parameters.Builder builder = trackSelector.buildUponParameters()
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .addOverride(new TrackSelectionOverride(
                        option.group.getMediaTrackGroup(),
                        Collections.singletonList(option.trackIndex)));
        trackSelector.setParameters(builder.build());
        showToast("Audio: " + option.label);
    }

    private void showSubtitleSelectionDialog() {
        if (player == null || trackSelector == null) {
            return;
        }
        List<TrackOption> subtitleTracks = collectTrackOptions(C.TRACK_TYPE_TEXT);
        if (subtitleTracks.isEmpty()) {
            showToast("No subtitles available");
            return;
        }

        String[] labels = new String[subtitleTracks.size() + 1];
        labels[0] = "Off";
        for (int i = 0; i < subtitleTracks.size(); i++) {
            labels[i + 1] = subtitleTracks.get(i).label;
        }

        int checkedItem = 0;
        for (int i = 0; i < subtitleTracks.size(); i++) {
            TrackOption option = subtitleTracks.get(i);
            if (option.group.isTrackSelected(option.trackIndex)) {
                checkedItem = i + 1;
                break;
            }
        }

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Subtitles")
                .setSingleChoiceItems(labels, checkedItem, (d, which) -> {
                    if (which == 0) {
                        applySubtitleTrack(null);
                    } else {
                        applySubtitleTrack(subtitleTracks.get(which - 1));
                    }
                    d.dismiss();
                })
                .setNegativeButton("Cancel", null)
                .create();

        dialog.show();
    }

    private void applySubtitleTrack(@Nullable TrackOption option) {
        if (trackSelector == null) {
            return;
        }
        DefaultTrackSelector.Parameters.Builder builder =
                trackSelector.buildUponParameters().clearOverridesOfType(C.TRACK_TYPE_TEXT);
        if (option == null) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true);
            trackSelector.setParameters(builder.build());
            showToast("Subtitles off");
            return;
        }

        builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .addOverride(new TrackSelectionOverride(
                        option.group.getMediaTrackGroup(),
                        Collections.singletonList(option.trackIndex)));
        trackSelector.setParameters(builder.build());
        showToast("Subtitles: " + option.label);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUBTITLE SETTINGS PANEL
    // ═══════════════════════════════════════════════════════════════════════════

    private void showSubtitleSettingsPanel() {
        // Collect available subtitle tracks
        subtitleTrackOptions.clear();
        currentSubtitleTrackIndex = 0;

        List<TrackOption> tracks = collectTrackOptions(C.TRACK_TYPE_TEXT);
        subtitleTrackOptions.addAll(tracks);

        // Determine currently selected track index
        boolean hasSelectedSubtitle = false;
        if (!tracks.isEmpty()) {
            Tracks currentTracks = player != null ? player.getCurrentTracks() : null;
            if (currentTracks != null) {
                for (int i = 0; i < tracks.size(); i++) {
                    TrackOption opt = tracks.get(i);
                    if (opt.group.isTrackSelected(opt.trackIndex)) {
                        currentSubtitleTrackIndex = i;
                        hasSelectedSubtitle = true;
                        break;
                    }
                }
            }
        }
        // If no track selected, set to -1 (Off)
        if (!hasSelectedSubtitle) {
            currentSubtitleTrackIndex = -1;
        }

        // Update UI values
        updateSubtitlePanelValues();

        // Show panel
        if (subtitleSettingsRoot != null) {
            subtitleSettingsRoot.setVisibility(View.VISIBLE);
        }
        subtitleSettingsVisible = true;

        // Focus first column
        if (subtitleColumnTrack != null) {
            subtitleColumnTrack.requestFocus();
        }
    }

    private void hideSubtitleSettingsPanel() {
        if (subtitleSettingsRoot != null) {
            subtitleSettingsRoot.setVisibility(View.GONE);
        }
        subtitleSettingsVisible = false;
        if (playerView != null) {
            playerView.requestFocus();
        }
    }

    private void updateSubtitlePanelValues() {
        // Track
        if (subtitleValueTrack != null) {
            if (currentSubtitleTrackIndex < 0 || subtitleTrackOptions.isEmpty()) {
                subtitleValueTrack.setText("Off");
            } else if (currentSubtitleTrackIndex < subtitleTrackOptions.size()) {
                subtitleValueTrack.setText(subtitleTrackOptions.get(currentSubtitleTrackIndex).label);
            } else {
                subtitleValueTrack.setText("Off");
            }
        }

        // Size
        if (subtitleValueSize != null) {
            subtitleValueSize.setText(SubtitleSettings.getCurrentSize(this).getLabel());
        }

        // Style
        if (subtitleValueStyle != null) {
            subtitleValueStyle.setText(SubtitleSettings.getCurrentStyle(this).getLabel());
        }

        // Color
        SubtitleSettings.ColorOption colorOption = SubtitleSettings.getCurrentColor(this);
        if (subtitleValueColor != null) {
            subtitleValueColor.setText(colorOption.getLabel());
        }
        if (subtitleColorSwatch != null) {
            subtitleColorSwatch.setBackgroundTintList(
                    android.content.res.ColorStateList.valueOf(colorOption.getColor()));
        }

        // Background
        if (subtitleValueBg != null) {
            subtitleValueBg.setText(SubtitleSettings.getCurrentBg(this).getLabel());
        }

        // Update preview
        updateSubtitlePreview();
    }

    private void updateSubtitlePreview() {
        if (subtitlePreviewText == null) return;

        SubtitleSettings.ColorOption colorOption = SubtitleSettings.getCurrentColor(this);
        SubtitleSettings.StyleOption styleOption = SubtitleSettings.getCurrentStyle(this);
        SubtitleSettings.SizeOption sizeOption = SubtitleSettings.getCurrentSize(this);
        SubtitleSettings.BgOption bgOption = SubtitleSettings.getCurrentBg(this);

        subtitlePreviewText.setTextColor(colorOption.getColor());
        subtitlePreviewText.setTextSize(sizeOption.getSizeSp());

        // Apply shadow based on edge style
        switch (styleOption.getEdgeType()) {
            case CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW:
                subtitlePreviewText.setShadowLayer(4f, 2f, 2f, Color.BLACK);
                break;
            case CaptionStyleCompat.EDGE_TYPE_OUTLINE:
                subtitlePreviewText.setShadowLayer(2f, 1f, 1f, Color.BLACK);
                break;
            default:
                subtitlePreviewText.setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT);
                break;
        }

        // Background
        if (bgOption.getColor() != Color.TRANSPARENT) {
            subtitlePreviewText.setBackgroundColor(bgOption.getColor());
            subtitlePreviewText.setPadding(8, 4, 8, 4);
        } else {
            subtitlePreviewText.setBackgroundColor(Color.TRANSPARENT);
            subtitlePreviewText.setPadding(0, 0, 0, 0);
        }
    }

    private void cycleSubtitleValueUp() {
        View focusedView = getCurrentFocus();
        if (focusedView == null) return;

        int viewId = focusedView.getId();
        if (viewId == R.id.subtitle_column_track) {
            // Track uses dialog, no cycling
            return;
        } else if (viewId == R.id.subtitle_column_size) {
            SubtitleSettings.cycleSizeUp(this);
        } else if (viewId == R.id.subtitle_column_style) {
            SubtitleSettings.cycleStyleUp(this);
        } else if (viewId == R.id.subtitle_column_color) {
            SubtitleSettings.cycleColorUp(this);
        } else if (viewId == R.id.subtitle_column_bg) {
            SubtitleSettings.cycleBgUp(this);
        } else if (viewId == R.id.subtitle_reset_button) {
            // Reset button doesn't cycle
            return;
        }

        updateSubtitlePanelValues();
        applySubtitleSettings();
    }

    private void cycleSubtitleValueDown() {
        View focusedView = getCurrentFocus();
        if (focusedView == null) return;

        int viewId = focusedView.getId();
        if (viewId == R.id.subtitle_column_track) {
            // Track uses dialog, no cycling
            return;
        } else if (viewId == R.id.subtitle_column_size) {
            SubtitleSettings.cycleSizeDown(this);
        } else if (viewId == R.id.subtitle_column_style) {
            SubtitleSettings.cycleStyleDown(this);
        } else if (viewId == R.id.subtitle_column_color) {
            SubtitleSettings.cycleColorDown(this);
        } else if (viewId == R.id.subtitle_column_bg) {
            SubtitleSettings.cycleBgDown(this);
        } else if (viewId == R.id.subtitle_reset_button) {
            // Reset button doesn't cycle
            return;
        }

        updateSubtitlePanelValues();
        applySubtitleSettings();
    }

    private void handleSubtitlePanelSelect() {
        View focusedView = getCurrentFocus();
        if (focusedView == null) return;

        int viewId = focusedView.getId();
        if (viewId == R.id.subtitle_column_track) {
            showSubtitleTrackSelectionDialogFromPanel();
        } else if (viewId == R.id.subtitle_reset_button) {
            resetSubtitleSettingsFromPanel();
        }
    }

    private void showSubtitleTrackSelectionDialogFromPanel() {
        // Build labels array including "Off" option
        List<String> labels = new ArrayList<>();
        labels.add("Off");
        for (TrackOption opt : subtitleTrackOptions) {
            labels.add(opt.label);
        }

        // Adjust selected index (+1 because "Off" is at index 0)
        int selectedIndex = currentSubtitleTrackIndex + 1;
        if (selectedIndex < 0) selectedIndex = 0;

        String[] labelsArray = labels.toArray(new String[0]);
        new AlertDialog.Builder(this)
                .setTitle("Select Subtitle Track")
                .setSingleChoiceItems(labelsArray, selectedIndex, (dialog, which) -> {
                    if (which == 0) {
                        currentSubtitleTrackIndex = -1; // Off
                    } else {
                        currentSubtitleTrackIndex = which - 1;
                    }
                    applySelectedSubtitleTrackFromPanel();
                    updateSubtitlePanelValues();
                    dialog.dismiss();
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void resetSubtitleSettingsFromPanel() {
        SubtitleSettings.resetToDefaults(this);
        updateSubtitlePanelValues();
        applySubtitleSettings();
        showToast("Subtitle settings reset to defaults");
    }

    private void applySelectedSubtitleTrackFromPanel() {
        if (currentSubtitleTrackIndex < 0 || currentSubtitleTrackIndex >= subtitleTrackOptions.size()) {
            applySubtitleTrack(null); // Off
        } else {
            applySubtitleTrack(subtitleTrackOptions.get(currentSubtitleTrackIndex));
        }
    }

    private void applySubtitleSettings() {
        if (subtitleOverlay != null) {
            subtitleOverlay.setFixedTextSize(
                    TypedValue.COMPLEX_UNIT_SP,
                    SubtitleSettings.getFontSizeSp(this));
            subtitleOverlay.setStyle(SubtitleSettings.buildCaptionStyle(this));
        }
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
        if (unifiedGuideAdapter != null) {
            unifiedGuideAdapter.notifyDataSetChanged();
        }
        // Scroll to top after filter - capture reference for lambda safety
        final RecyclerView listRef = unifiedGuideList;
        if (!filteredChannelEntries.isEmpty() && listRef != null) {
            listRef.post(() -> {
                if (listRef.getAdapter() != null && listRef.getAdapter().getItemCount() > 0) {
                    listRef.scrollToPosition(0);
                }
            });
        }
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
        String provider = safeString(payload.get("provider")); // Extract provider info

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
        markUnifiedGuideCurrentChannel(currentChannelId);

        final String badgeName = currentChannelName;
        final boolean hasAdapter = unifiedGuideAdapter != null;
        runOnUiThread(() -> {
            updateChannelBadge(badgeName);
            if (hasAdapter) {
                unifiedGuideAdapter.notifyDataSetChanged();
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

        return new ChannelSwitchData(firstUrl, resolvedTitle, resolvedNumber, resolvedName, provider);
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

        hideUnifiedGuide();
        showLoadingBar(LoadingType.CHANNEL, entry.number > 0 ? entry.number : null, entry.name);

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
                final String playProvider = switchData.provider;

                android.util.Log.d("TorboxTvPlayer", "requestChannelByEntry: received provider=" + playProvider);

                // Play the new channel video
                playMedia(playUrl, playTitle, playProvider);
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
                    .inflate(R.layout.item_unified_channel, parent, false);
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
            private final TextView subtitleView;
            private final TextView nowBadge;
            // Store current entry and listener to avoid creating new listeners on every bind
            private ChannelEntry currentEntry;
            private OnChannelClickListener currentListener;

            ChannelViewHolder(@NonNull View itemView) {
                super(itemView);
                numberView = itemView.findViewById(R.id.unified_channel_number);
                nameView = itemView.findViewById(R.id.unified_channel_name);
                subtitleView = itemView.findViewById(R.id.unified_channel_subtitle);
                nowBadge = itemView.findViewById(R.id.unified_channel_now_badge);

                // Set listeners once in constructor to prevent accumulation
                itemView.setOnClickListener(v -> {
                    if (currentEntry != null && currentListener != null) {
                        currentListener.onChannelClicked(currentEntry);
                    }
                });
                itemView.setOnFocusChangeListener((v, hasFocus) -> {
                    v.animate().cancel(); // Cancel any ongoing animation
                    if (hasFocus) {
                        v.animate().scaleX(1.02f).scaleY(1.02f).setDuration(100L).start();
                    } else {
                        v.animate().scaleX(1f).scaleY(1f).setDuration(100L).start();
                    }
                });
            }

            void bind(ChannelEntry entry, OnChannelClickListener listener) {
                this.currentEntry = entry;
                this.currentListener = listener;

                // Modern clean format: just the number, no "CH" prefix
                String numberText = entry.number > 0
                        ? String.format(Locale.US, "%02d", entry.number)
                        : "--";

                // Null-safe view updates
                if (numberView != null) {
                    numberView.setText(numberText);
                }
                if (nameView != null) {
                    nameView.setText(entry.nameUpper);
                }
                if (subtitleView != null) {
                    subtitleView.setText(entry.isCurrent ? "Currently playing" : "Press OK to tune");
                }
                if (nowBadge != null) {
                    nowBadge.setVisibility(entry.isCurrent ? View.VISIBLE : View.GONE);
                }

                // Background handled by drawable selector (unified_guide_item_bg.xml)
                itemView.setAlpha(1f);
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
        @Nullable
        final String provider;

        ChannelSwitchData(String url, String title, @Nullable Integer channelNumber, @Nullable String channelName, @Nullable String provider) {
            this.url = url;
            this.title = title;
            this.channelNumber = channelNumber;
            this.channelName = channelName;
            this.provider = provider;
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

        // Show visual feedback for quick seek
        String seekSeconds = String.valueOf(Math.abs(offsetMs) / 1000) + "s";
        if (offsetMs > 0) {
            seekFeedbackManager.showSeekForward(seekSeconds);
        } else {
            seekFeedbackManager.showSeekBackward(seekSeconds);
        }

        if (playerView != null) {
            playerView.hideController();
        }
    }

    private void setupBackPressHandler() {
        // Use modern OnBackPressedDispatcher API instead of deprecated onBackPressed()
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (isUnifiedGuideVisible()) {
                    hideUnifiedGuide();
                    return;
                }

                // Double-back to exit confirmation
                long currentTime = System.currentTimeMillis();
                if (currentTime - lastBackPressTime < BACK_PRESS_INTERVAL_MS) {
                    // Second back press within time window - exit
                    setEnabled(false);
                    getOnBackPressedDispatcher().onBackPressed();
                } else {
                    // First back press - show message
                    lastBackPressTime = currentTime;
                    Toast.makeText(TorboxTvPlayerActivity.this,
                        "Press back again to exit",
                        Toast.LENGTH_SHORT).show();
                }
            }
        });
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int keyCode = event.getKeyCode();

        // Unified Channel Guide is visible - handle keys
        if (isUnifiedGuideVisible()) {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_DOWN) {
                hideUnifiedGuide();
                return true;
            }
            // Number keys go to search bar
            if (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) {
                if (event.getAction() == KeyEvent.ACTION_DOWN && unifiedGuideSearch != null) {
                    // Send key to search EditText
                    unifiedGuideSearch.requestFocus();
                    return unifiedGuideSearch.dispatchKeyEvent(event);
                }
            }
            return super.dispatchKeyEvent(event);
        }

        // Subtitle Settings Panel is visible - handle keys
        if (subtitleSettingsVisible) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                if (keyCode == KeyEvent.KEYCODE_BACK) {
                    hideSubtitleSettingsPanel();
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
                    cycleSubtitleValueUp();
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
                    cycleSubtitleValueDown();
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
                    handleSubtitlePanelSelect();
                    return true;
                }
            }
            // Let left/right navigation work normally for focus
            return super.dispatchKeyEvent(event);
        }

        if (seekbarVisible) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
                    long step = getAcceleratedSeekStep(event.getRepeatCount());
                    seekBackward(step);
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
                    long step = getAcceleratedSeekStep(event.getRepeatCount());
                    seekForward(step);
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
                    confirmSeekPosition();
                    return true;
                } else if (keyCode == KeyEvent.KEYCODE_BACK) {
                    hideSeekbar();
                    return true;
                }
            }
            return true;
        }

        // If controls menu is visible and back is pressed, hide the menu first
        if (controlsMenuVisible && keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_DOWN) {
            hideControlsMenu();
            return true;
        }

        boolean focusInControls = isFocusInControlsOverlay();

        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event);
            }
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                handlePlayPauseToggleFromCenter();
            }
            return true;
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                if (!controlsMenuVisible) {
                    // Menu is hidden, show it
                    showControlsMenu();
                    scheduleHideControlsMenu();
                    return true;
                } else if (!focusInControls) {
                    // Menu is visible but focus is not in controls, refocus it
                    showControlsMenu();
                    scheduleHideControlsMenu();
                    return true;
                }
            }
            // Menu is visible and has focus, let normal navigation happen
            return super.dispatchKeyEvent(event);
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                showUnifiedGuide(false); // Open guide with list focused (not search)
            }
            return true;
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
            if (focusInControls) {
                // Focus is in menu, let normal navigation happen
                return super.dispatchKeyEvent(event);
            }
            // Not in menu, handle seeking
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                int repeat = event.getRepeatCount();
                if (repeat >= SEEK_LONG_PRESS_THRESHOLD) {
                    if (!seekbarVisible) {
                        showSeekbar(false, false);
                    }
                } else if (repeat == 0) {
                    seekBy(SEEK_STEP_MS);
                }
            }
            return true;
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
            if (focusInControls) {
                // Focus is in menu, let normal navigation happen
                return super.dispatchKeyEvent(event);
            }
            // Not in menu, handle seeking
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                int repeat = event.getRepeatCount();
                if (repeat >= SEEK_LONG_PRESS_THRESHOLD) {
                    if (!seekbarVisible) {
                        showSeekbar(false, false);
                    }
                } else if (repeat == 0) {
                    seekBy(-SEEK_STEP_MS);
                }
            }
            return true;
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

    @Override
    protected void onPause() {
        super.onPause();
        if (player != null && player.isPlaying()) {
            player.pause();
        }

        // Cancel any ongoing PikPak retry operations
        cancelPikPakRetry();
    }

    @Override
    protected void onDestroy() {
        // Clean up unified guide text watcher to prevent memory leak
        if (unifiedGuideSearch != null && unifiedGuideTextWatcher != null) {
            unifiedGuideSearch.removeTextChangedListener(unifiedGuideTextWatcher);
            unifiedGuideTextWatcher = null;
        }

        // Clean up seek feedback manager
        if (seekFeedbackManager != null) {
            seekFeedbackManager.destroy();
        }

        // Cancel PikPak retry operations
        cancelPikPakRetry();

        // Clean up TV static effect
        stopTvStaticEffect();
        if (staticHandler != null) {
            staticHandler.removeCallbacksAndMessages(null);
        }

        // Clean up PikPak retry handler
        if (pikPakRetryHandler != null) {
            pikPakRetryHandler.removeCallbacksAndMessages(null);
        }

        // Stop progress bar updates
        stopProgressBarUpdates();

        // Clean up loading bar animation
        if (loadingBarAnimator != null && loadingBarAnimator.isRunning()) {
            loadingBarAnimator.cancel();
        }

        // Clean up dots animation
        if (dotsAnimator != null && dotsAnimator.isRunning()) {
            dotsAnimator.cancel();
        }

        // Release night mode audio effect
        releaseLoudnessEnhancer();

        if (player != null) {
            player.removeListener(playbackListener);
            // Remove subtitle listener to prevent memory leaks
            if (subtitleListener != null) {
                player.removeListener(subtitleListener);
                subtitleListener = null;
            }
            // Remove track change listener to prevent memory leaks
            if (trackChangeListener != null) {
                player.removeListener(trackChangeListener);
                trackChangeListener = null;
            }
            player.stop();
            player.release();
            player = null;
        }
        hideNextOverlay();
        cancelTitleFade();
        notifyFlutterPlaybackFinished();
        keyPressHandler.removeCallbacksAndMessages(null);
        controlsMenuHandler.removeCallbacks(hideControlsMenuRunnable);
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
        if (channelNumberView == null || channelNameView == null) {
            return;
        }

        if (!showChannelName) {
            hideChannelBadge();
            return;
        }

        String displayName = name != null ? name.trim() : "";
        boolean hasNumber = currentChannelNumber > 0;

        if (!hasNumber && displayName.isEmpty()) {
            hideChannelBadge();
            return;
        }

        // Set channel number with zero-padding for professional look
        if (hasNumber) {
            String formattedNumber = String.format(java.util.Locale.US, "%02d", currentChannelNumber);
            channelNumberView.setText(formattedNumber);
        } else {
            channelNumberView.setText("");
        }

        // Set channel name in uppercase for broadcast aesthetic
        if (!displayName.isEmpty()) {
            channelNameView.setText(displayName.toUpperCase(java.util.Locale.US));
        } else {
            channelNameView.setText("");
        }

        // Update content only - visibility controlled by menu
        // If menu is visible, ensure broadcast lower-third is shown
        if (controlsMenuVisible) {
            showChannelBadgeWithAnimation();
        }
    }

    private void showChannelBadgeWithAnimation() {
        // Now handled by unified broadcast lower-third
        showBroadcastLowerThirdWithAnimation();
    }

    private void fadeOutChannelBadge() {
        // Now handled by unified broadcast lower-third
        fadeOutBroadcastLowerThird();
    }

    private void hideChannelBadge() {
        // Now handled by unified broadcast lower-third
        hideBroadcastLowerThird();
    }

    private void updateTitleBadge(@Nullable String videoTitle) {
        if (titleBadgeText == null) {
            return;
        }

        if (!showVideoTitle) {
            hideTitleBadge();
            return;
        }

        String displayTitle = videoTitle != null ? videoTitle.trim() : "";

        // Remove file extensions (case-insensitive)
        if (!displayTitle.isEmpty()) {
            displayTitle = displayTitle.replaceAll("(?i)\\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|ts|m2ts|vob|3gp|ogv|divx)$", "");
            displayTitle = displayTitle.trim();
        }

        if (displayTitle.isEmpty()) {
            hideTitleBadge();
            return;
        }

        // Set title text
        titleBadgeText.setText(displayTitle);

        // Enable marquee scrolling for long titles
        titleBadgeText.setSelected(true);

        // Update content only - visibility controlled by menu
        // If menu is visible, ensure broadcast lower-third is shown
        if (controlsMenuVisible) {
            showTitleBadgeWithAnimation();
        }
    }

    private void showTitleBadgeWithAnimation() {
        // Now handled by unified broadcast lower-third
        showBroadcastLowerThirdWithAnimation();
    }

    private void fadeOutTitleBadge() {
        // Now handled by unified broadcast lower-third
        fadeOutBroadcastLowerThird();
    }

    private void hideTitleBadge() {
        // Now handled by unified broadcast lower-third
        hideBroadcastLowerThird();
    }

    private void showBroadcastLowerThirdWithAnimation() {
        if (broadcastLowerThird == null) {
            return;
        }

        // Cancel any pending fade-out
        if (broadcastLowerThirdFadeOutRunnable != null) {
            broadcastLowerThird.removeCallbacks(broadcastLowerThirdFadeOutRunnable);
            broadcastLowerThirdFadeOutRunnable = null;
        }

        // Only show if controls menu is visible AND controls overlay is actually visible
        if (controlsMenuVisible && controlsOverlay != null
                && controlsOverlay.getVisibility() == View.VISIBLE) {
            broadcastLowerThird.setVisibility(View.VISIBLE);
        }

        // NO independent auto-hide timer - synchronized with menu visibility
    }

    private void fadeOutBroadcastLowerThird() {
        if (broadcastLowerThird == null) {
            return;
        }

        // Just hide instantly - no animation
        broadcastLowerThird.setVisibility(View.GONE);
    }

    private void hideBroadcastLowerThird() {
        if (broadcastLowerThird == null) {
            return;
        }

        // Cancel any pending animations/callbacks
        if (broadcastLowerThirdFadeOutRunnable != null) {
            broadcastLowerThird.removeCallbacks(broadcastLowerThirdFadeOutRunnable);
            broadcastLowerThirdFadeOutRunnable = null;
        }
        broadcastLowerThird.animate().cancel();
        broadcastLowerThird.setVisibility(View.GONE);
    }

    /**
     * Extract quality tier from filename/title
     * Returns: "4K", "FHD", "HD", "SD", or null
     */
    private String extractQuality(String title) {
        if (title == null || title.isEmpty()) {
            return null;
        }

        String upperTitle = title.toUpperCase();

        // Check for 4K/UHD (2160p)
        if (upperTitle.contains("2160P") || upperTitle.contains("4K") || upperTitle.contains("UHD")) {
            return "4K";
        }

        // Check for 1080p (Full HD)
        if (upperTitle.contains("1080P") || upperTitle.contains("FHD") || upperTitle.contains("FULL HD")) {
            return "FHD";
        }

        // Check for 720p (HD)
        if (upperTitle.contains("720P") || upperTitle.matches(".*\\bHD\\b.*")) {
            return "HD";
        }

        // Check for SD (480p and below)
        if (upperTitle.contains("480P") || upperTitle.contains("360P") || upperTitle.contains("SD")) {
            return "SD";
        }

        // Default to null if no quality info found
        return null;
    }

    /**
     * Update quality watermark - simple, static, subtle
     */
    private void updateQualityBadge(String title) {
        if (qualityWatermark == null) {
            return;
        }

        // Extract quality only (no codec)
        String quality = extractQuality(title);

        // If no quality info found, hide watermark
        if (quality == null) {
            qualityWatermark.setVisibility(View.GONE);
            return;
        }

        // Set quality text and show (no animation, just static)
        qualityWatermark.setText(quality);
        qualityWatermark.setVisibility(View.VISIBLE);
    }
}
