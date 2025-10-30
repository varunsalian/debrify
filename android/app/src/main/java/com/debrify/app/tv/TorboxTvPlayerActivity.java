package com.debrify.app.tv;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.View;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
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

import com.debrify.app.MainActivity;
import com.debrify.app.R;

import java.util.ArrayList;
import java.util.Collections;
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
    
    private static final long SEEK_STEP_MS = 10_000L;
    private static final long DEFAULT_TARGET_BUFFER_MS = 12_000L;
    private static final long HIGH_TARGET_BUFFER_MS = 22_000L;
    private static final long MAX_TARGET_BUFFER_MS = 32_000L;
    private static final long BACK_BUFFER_MS = 15_000L;
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
    private TextView watermarkView;
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
    private SubtitleView subtitleOverlay;
    private android.animation.ValueAnimator staticAnimator;
    private Handler staticHandler = new Handler(Looper.getMainLooper());
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
    private boolean showWatermark;
    private boolean hideBackButton;

    private boolean randomApplied = false;
    private boolean requestingNext = false;
    private boolean finishedNotified = false;
    private boolean longPressHandled = false;
    private int playedCount = 0;

    private final Random random = new Random();
    private final Runnable hideTitleRunnable = this::fadeOutTitle;
    private final Runnable hideNextOverlayRunnable = this::performHideNextOverlay;
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
        watermarkView = findViewById(R.id.player_watermark);
        nextOverlay = findViewById(R.id.player_next_overlay);
        nextText = findViewById(R.id.player_next_text);
        nextSubtext = findViewById(R.id.player_next_subtext);
        tvStaticView = findViewById(R.id.tv_static_view);
        tvScanlines = findViewById(R.id.tv_scanlines);
        subtitleOverlay = findViewById(R.id.player_subtitles);

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
        playerView.setKeepScreenOn(true);
        playerView.setUseController(true);
        playerView.setControllerAutoShow(true);
        playerView.setControllerShowTimeoutMs(4000);
        playerView.setResizeMode(resizeModes[resizeModeIndex]);
        if (subtitleOverlay != null) {
            subtitleOverlay.setApplyEmbeddedStyles(true);
            subtitleOverlay.setApplyEmbeddedFontSizes(true);
            subtitleOverlay.setBottomPaddingFraction(0.01f);
            subtitleOverlay.setPadding(24, 0, 24, 0);
            subtitleOverlay.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, 18f);
            subtitleOverlay.setStyle(new CaptionStyleCompat(
                    Color.WHITE,
                    Color.TRANSPARENT,
                    Color.TRANSPARENT,
                    CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                    Color.BLACK,
                    Typeface.create("sans-serif-medium", Typeface.NORMAL)));
        }
        playerView.requestFocus();
    }

    private LoadControl buildLoadControl(long estimatedBitrate) {
        long targetBufferMs = selectTargetBufferMs(estimatedBitrate);
        long minBufferMs = Math.min(targetBufferMs / 2, 7_500L);
        currentTargetBufferMs = targetBufferMs;
        return new DefaultLoadControl.Builder()
                .setBufferDurationsMs((int) minBufferMs, (int) targetBufferMs, 1_000, 2_000)
                .setBackBuffer((int) BACK_BUFFER_MS, true)
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

        if (showWatermark) {
            watermarkView.setVisibility(View.VISIBLE);
        } else {
            watermarkView.setVisibility(View.GONE);
        }

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

    private void showNextOverlay(@Nullable String headline, @Nullable String subline) {
        if (nextOverlay == null || player == null) {
            return;
        }
        
        runOnUiThread(() -> {
            // Pause the current video
            if (player.isPlaying()) {
                player.pause();
            }
            
            nextOverlay.removeCallbacks(hideNextOverlayRunnable);
            
            // Set retro TV message
            String displayHeadline = getRandomTvStaticMessage();
            if (nextText != null) {
                nextText.setText(displayHeadline);
            }
            
            // Show next video title if available
            if (nextSubtext != null) {
                if (subline != null && !subline.isEmpty()) {
                    nextSubtext.setVisibility(View.VISIBLE);
                    nextSubtext.setText("▶ " + subline.toUpperCase());
                } else {
                    nextSubtext.setVisibility(View.GONE);
                }
            }
            
            // Start TV static animation
            startTvStaticEffect();
            
            // Animate overlay in
            nextOverlay.setVisibility(View.VISIBLE);
            nextOverlay.setAlpha(0f);
            nextOverlay.animate()
                .alpha(1f)
                .setDuration(150L)
                .start();
        });
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
        scheduleHideNextOverlay(0L);
    }

    private void scheduleHideNextOverlay(long delayMs) {
        if (nextOverlay == null) {
            return;
        }
        runOnUiThread(() -> {
            nextOverlay.removeCallbacks(hideNextOverlayRunnable);
            nextOverlay.postDelayed(hideNextOverlayRunnable, delayMs);
        });
    }

    private void performHideNextOverlay() {
        if (nextOverlay == null) {
            return;
        }
        if (nextOverlay.getVisibility() != View.VISIBLE) {
            nextOverlay.setAlpha(1f);
            return;
        }
        
        // Stop TV static effect
        stopTvStaticEffect();
        
        // Fade out the overlay
        nextOverlay.animate().cancel();
        nextOverlay.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction(() -> {
                    if (nextOverlay != null) {
                        nextOverlay.setVisibility(View.GONE);
                        nextOverlay.setAlpha(1f);
                    }
                })
                .start();
    }

    private void playMedia(String url, @Nullable String title) {
        if (player == null || url == null || url.isEmpty()) {
            return;
        }
        randomApplied = false;
        maybeRecreatePlayerForBandwidth();
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
        // Clean up TV static effect
        stopTvStaticEffect();
        if (staticHandler != null) {
            staticHandler.removeCallbacksAndMessages(null);
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
}
