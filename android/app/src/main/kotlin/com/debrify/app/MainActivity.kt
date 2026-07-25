package com.debrify.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.util.DisplayMetrics
import android.util.Rational
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.core.view.WindowCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterJNI
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import org.json.JSONObject
import org.json.JSONArray

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.debrify.app/downloader"
	private val EVENTS = "com.debrify.app/downloader_events"
    private val ANDROID_TV_CHANNEL = "com.debrify.app/android_tv_player"
    private val REMOTE_CONTROL_CHANNEL = "com.debrify.app/remote_control"
    private val PIP_CHANNEL = "com.debrify.app/pip"

    // ── Picture-in-Picture (phone media_kit player) ─────────────────────────
    // PiP shrinks THIS activity into a floating window; the media_kit Flutter
    // texture keeps rendering as long as the activity/engine survives. Armed by
    // the Dart player screen while it's on top (see onUserLeaveHint). Phone
    // only — TV has its own native player and never uses phone-style PiP.
    private val PIP_ACTION = "com.debrify.app.PIP_ACTION"
    private var pipChannel: MethodChannel? = null
    private var pipAutoEnterArmed = false
    private var pipAspectW = 0
    private var pipAspectH = 0
    private var pipIsPlaying = false
    private var pipHasNext = false
    private var pipReceiverRegistered = false

    /** Receives taps on the PiP window's action buttons and forwards them to
     *  the Dart player over [pipChannel]. Registered lazily on first PiP entry
     *  (see registerPipReceiver), unregistered in onDestroy. */
    private val pipActionReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != PIP_ACTION) return
            val action = intent.getStringExtra("pipAction") ?: return
            try {
                pipChannel?.invokeMethod("onPipAction", action)
            } catch (e: Exception) {
                android.util.Log.e("DebrifyPiP", "action dispatch failed: ${e.message}")
            }
        }
    }

    // Inline ExoPlayer for the ambient trailer backdrop on TV.
    private var tvTrailerPlayer: com.debrify.app.tv.TvTrailerTexturePlayer? = null

    // Full-window layer UNDER the FlutterView hosting the trailer underlay
    // SurfaceView(s). See trailerUnderlayContainer().
    private var trailerUnderlayContainer: FrameLayout? = null

    private fun isTelevision(): Boolean = try {
        (getSystemService(UI_MODE_SERVICE) as UiModeManager)
            .currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    } catch (e: Exception) {
        false
    }

    /** The Dart-owned setting (Settings → Home Page → Native Trailer Surface),
     *  read from the shared_preferences plugin's store. Must be checked here
     *  too: the transparency mode is fixed at activity creation, so flipping
     *  the toggle takes effect on the next app start. */
    private fun trailerUnderlayEnabled(): Boolean =
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.tv_trailer_underlay_enabled", true)

    /** Whether this device's GPU can AFFORD the underlay's permanently
     *  translucent Flutter surface. A translucent full-screen surface can never
     *  be marked opaque, so SurfaceFlinger alpha-blends two full-1080p layers
     *  on every frame the app draws — measured on a Mi Box (Mali-450, GLES 2.0)
     *  that standing tax janks the whole app, spinners included, trailer or no
     *  trailer. GLES 3.0+ devices have the fill-rate headroom; ES2-class
     *  boxes compensate with low-res rendering (computeRenderScale), which
     *  the onCreate interlock requires before granting them the translucent
     *  surface. */
    private fun underlaySurfaceAffordable(): Boolean = try {
        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        am.deviceConfigurationInfo.reqGlEsVersion >= 0x30000
    } catch (e: Exception) {
        false
    }

    /** The EFFECTIVE underlay decision for this activity's whole life — user
     *  toggle AND device capability — made once in [onCreate] BEFORE the
     *  FlutterView exists, and persisted for the Dart side (see onCreate). */
    private var trailerUnderlayEffective = false

    // ── Low-res render scale (weak-GPU TVs) ─────────────────────────────────
    // GLES2-class boxes (Mi Box: Mali-450) are FILL-RATE bound: rendering the
    // Flutter UI at full 1080p is what makes the whole app feel heavy, no
    // matter how lean the widget tree is (verified on-device: the same build
    // at 720p feels near native). The games technique: give the Flutter
    // surface a FIXED ~720p buffer (the hardware scaler upscales for free)
    // and scale the viewport metrics by the same factor so the LOGICAL layout
    // is pixel-for-pixel identical — every frame just costs ~2.25x fewer
    // pixels. Scoped to this activity's Flutter surface only: video playback
    // (movies in the native player activity, trailer underlays) renders on
    // its own decoder-sized surfaces and stays full resolution.

    /** <1.0 when low-res rendering is active (e.g. 720/1080 = 0.667). */
    private var renderScale = 1.0f

    private fun computeRenderScale(gpuCapable: Boolean) {
        renderScale = 1.0f
        val auto = isTelevision() && !gpuCapable
        // Pref = future Settings escape hatch ("sharper picture vs faster
        // navigation"); absent → the automatic weak-GPU decision.
        val enabled = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.tv_low_res_render", auto)
        if (!enabled) return
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(dm)
        // Already ~720p-class (or unknown) → nothing to win, don't downscale.
        if (dm.heightPixels <= 736 || dm.widthPixels <= 0) return
        renderScale = 720f / dm.heightPixels
    }

    /** Rewrites the viewport metrics Flutter receives so the engine lays out
     *  and rasters at the scaled size while logical geometry is unchanged:
     *  physical w/h/insets × scale, devicePixelRatio × scale. MUST round
     *  exactly like [applyFixedSurfaceSize] — the engine discards frames
     *  whose size doesn't match the surface buffer.
     *
     *  Known limitations (accepted; TV is DPAD-driven): pointer coordinates
     *  and accessibility-node bounds are NOT rescaled, so an air-mouse remote
     *  or TalkBack on a scaled device would see ~2/3-offset hit targets. The
     *  `flutter.tv_low_res_render=false` pref is the escape hatch. */
    private class ScaledFlutterJNI(private val scale: Float) : FlutterJNI() {
        private fun s(v: Int): Int = Math.round(v * scale)

        override fun setViewportMetrics(
            devicePixelRatio: Float,
            physicalWidth: Int,
            physicalHeight: Int,
            physicalPaddingTop: Int,
            physicalPaddingRight: Int,
            physicalPaddingBottom: Int,
            physicalPaddingLeft: Int,
            physicalViewInsetTop: Int,
            physicalViewInsetRight: Int,
            physicalViewInsetBottom: Int,
            physicalViewInsetLeft: Int,
            systemGestureInsetTop: Int,
            systemGestureInsetRight: Int,
            systemGestureInsetBottom: Int,
            systemGestureInsetLeft: Int,
            physicalTouchSlop: Int,
            displayFeaturesBounds: IntArray,
            displayFeaturesType: IntArray,
            displayFeaturesState: IntArray,
        ) {
            super.setViewportMetrics(
                devicePixelRatio * scale,
                s(physicalWidth),
                s(physicalHeight),
                s(physicalPaddingTop),
                s(physicalPaddingRight),
                s(physicalPaddingBottom),
                s(physicalPaddingLeft),
                s(physicalViewInsetTop),
                s(physicalViewInsetRight),
                s(physicalViewInsetBottom),
                s(physicalViewInsetLeft),
                s(systemGestureInsetTop),
                s(systemGestureInsetRight),
                s(systemGestureInsetBottom),
                s(systemGestureInsetLeft),
                s(physicalTouchSlop),
                IntArray(displayFeaturesBounds.size) { i -> s(displayFeaturesBounds[i]) },
                displayFeaturesType,
                displayFeaturesState,
            )
        }
    }

    /** Low-res mode builds the engine around [ScaledFlutterJNI]; default path
     *  (null) lets FlutterActivity create its own stock engine. */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (renderScale >= 0.999f) return null
        return FlutterEngine(
            context,
            FlutterInjector.instance().flutterLoader(),
            ScaledFlutterJNI(renderScale),
            /* dartVmArgs = */ null,
            /* automaticallyRegisterPlugins = */ true,
        )
    }

    /** Our provided engine must die with the activity like a stock one would —
     *  otherwise every recreation would leak a running Dart isolate. */
    override fun shouldDestroyEngineWithHost(): Boolean = true

    /** Pins the Flutter SurfaceView's buffer to the scaled size, keyed off the
     *  FlutterView's OWN layout size with the SAME rounding as the metrics
     *  rewrite, so buffer and viewport can never disagree. */
    private fun applyFixedSurfaceSize() {
        if (renderScale >= 0.999f) return
        val flutterView = findViewById<ViewGroup>(FLUTTER_VIEW_ID) ?: return
        var surfaceView: SurfaceView? = null
        for (i in 0 until flutterView.childCount) {
            (flutterView.getChildAt(i) as? SurfaceView)?.let { surfaceView = it }
        }
        val sv = surfaceView ?: return
        val scale = renderScale
        fun apply() {
            val w = flutterView.width
            val h = flutterView.height
            if (w > 0 && h > 0) {
                sv.holder.setFixedSize(Math.round(w * scale), Math.round(h * scale))
            }
        }
        apply()
        flutterView.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, orr, ob ->
            if (r - l != orr - ol || b - t != ob - ot) apply()
        }
    }

    /**
     * TV: make the Flutter surface translucent so the ambient trailer can play
     * on a native SurfaceView *behind* it (its own hardware overlay plane —
     * Flutter never composites the video frames; see TvTrailerTexturePlayer's
     * underlay mode). This keeps the fast SurfaceView render path — RenderMode
     * stays `surface` because the background mode is untouched — the Flutter
     * surface just gets a TRANSLUCENT format and sits Z-above the window. The
     * window, launch theme and every non-TV platform are unchanged, and the app
     * paints opaque UI everywhere except the trailer hole, so nothing else is
     * visibly different. Weak GPUs get this too, but ONLY while low-res
     * rendering offsets the blend tax — see the interlock in [onCreate].
     */
    override fun getTransparencyMode(): TransparencyMode =
        if (trailerUnderlayEffective) TransparencyMode.transparent
        else super.getTransparencyMode()

    /** Lazily creates the underlay container at content-view index 0 (below the
     *  FlutterView). Called from the platform thread on first underlay create. */
    private fun trailerUnderlayContainer(): FrameLayout? {
        trailerUnderlayContainer?.let { return it }
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return null
        val container = FrameLayout(this)
        content.addView(
            container,
            0,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        trailerUnderlayContainer = container
        return container
    }

    companion object {
        @JvmStatic
        private var androidTvPlayerChannel: MethodChannel? = null

        @JvmStatic
        fun getAndroidTvPlayerChannel(): MethodChannel? = androidTvPlayerChannel

        @JvmStatic
        fun setAndroidTvPlayerChannel(channel: MethodChannel?) {
            androidTvPlayerChannel = channel
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Decide the surface mode BEFORE super.onCreate builds the FlutterView
        // (which consults getTransparencyMode exactly once), and persist the
        // EFFECTIVE decision where Dart's launch snapshot reads it — both
        // sides must agree, or the Dart underlay hole would punch through an
        // opaque surface as a black rectangle. commit() (not apply) so the
        // value is on disk before the Dart isolate starts reading prefs.
        val gpuCapable = underlaySurfaceAffordable()
        // Must run before super.onCreate (provideFlutterEngine, called from
        // within it, reads renderScale) AND before the underlay decision
        // below, which depends on the outcome.
        computeRenderScale(gpuCapable)
        // Underlay trailers are back ON for weak GPUs too: with low-res
        // rendering the Flutter raster cost sits well under the pre-redesign
        // level that co-existed happily with the underlay's full-screen blend
        // tax — the charm-era playback architecture, at a UI cost the GPU can
        // afford. The parenthesised clause is the safety interlock: a weak
        // GPU gets the translucent surface ONLY while low-res rendering is
        // actually paying for it — if a future Settings row turns low-res
        // off (`tv_low_res_render=false`), the underlay drops with it rather
        // than recreating the measured full-1080p-plus-blend jank.
        trailerUnderlayEffective = isTelevision() && trailerUnderlayEnabled() &&
            (gpuCapable || renderScale < 0.999f)
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .putBoolean(
                "flutter.tv_trailer_underlay_effective",
                trailerUnderlayEffective,
            )
            // Surfaced for a future Settings row ("performance rendering").
            .putBoolean("flutter.tv_low_res_render_active", renderScale < 0.999f)
            .commit()
        super.onCreate(savedInstanceState)
        applyFixedSurfaceSize()
        // Enable edge-to-edge display to properly handle system navigation bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun onResume() {
        super.onResume()
        ActivityTracker.currentActivity = this
    }

    override fun onDestroy() {
        tvTrailerPlayer?.releaseAll()
        tvTrailerPlayer = null
        // Safety net for the phone player: the Dart screen closes its own
        // session in dispose(), but an activity torn down without that (task
        // swipe, recreation) would otherwise leave effect apps attached to a
        // session that no longer plays. No-op if nothing is open.
        com.debrify.app.audio.AudioEffectSession.closeCurrent(this)
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipActionReceiver)
            } catch (e: Exception) {
                // Already unregistered / never fully registered — ignore.
            }
            pipReceiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onPause() {
        super.onPause()
        if (ActivityTracker.currentActivity == this) {
            ActivityTracker.currentActivity = null
        }
    }

    /** Auto-enter PiP when the user leaves the app (Home / Recents) while the
     *  Dart player screen has armed it. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipAutoEnterArmed) return
        // Don't re-enter if the window is already in PiP.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            isInPictureInPictureMode
        ) {
            return
        }
        enterPipInternal(pipAspectW, pipAspectH)
    }

    /** Tell the Dart side so it can collapse chrome in the tiny window. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        try {
            pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "notify failed: ${e.message}")
        }
    }

    private fun pipSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isTelevision()) return false
        return packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )
    }

    private fun enterPipInternal(aspectW: Int, aspectH: Int): Boolean {
        // Inline SDK guard (not just pipSupported()) so the NewApi lint's flow
        // analysis can see it before the API-26 calls below.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!pipSupported()) return false
        return try {
            registerPipReceiver()
            enterPictureInPictureMode(buildPipParams(aspectW, aspectH))
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "enterPip failed: ${e.message}")
            false
        }
    }

    private fun registerPipReceiver() {
        if (pipReceiverRegistered) return
        val filter = android.content.IntentFilter(PIP_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipActionReceiver, filter)
        }
        pipReceiverRegistered = true
    }

    /** Push updated action buttons (play/pause icon, Next) to a PiP window
     *  that's already open — no-op otherwise. */
    private fun updatePipParamsIfActive() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!isInPictureInPictureMode) return
        try {
            setPictureInPictureParams(buildPipParams(pipAspectW, pipAspectH))
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "updateParams failed: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipParams(aspectW: Int, aspectH: Int): PictureInPictureParams {
        // Android rejects aspect ratios outside [1/2.39, 2.39] with
        // IllegalArgumentException — clamp ultrawide/portrait sources to just
        // INSIDE those bounds (0.42 / 2.39; note 1/2.39 ≈ 0.41841, so a 0.4184
        // clamp target would itself still be rejected).
        var w = if (aspectW > 0) aspectW else 16
        var h = if (aspectH > 0) aspectH else 9
        val ratio = w.toDouble() / h.toDouble()
        if (ratio > 2.39) {
            w = 239; h = 100
        } else if (ratio < 0.42) {
            w = 42; h = 100
        }
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(w, h))
            .setActions(buildPipActions())
            .build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipActions(): ArrayList<android.app.RemoteAction> {
        val actions = ArrayList<android.app.RemoteAction>()
        val icon = if (pipIsPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val title = if (pipIsPlaying) "Pause" else "Play"
        actions.add(makePipAction(icon, title, "playpause", 1))
        if (pipHasNext) {
            actions.add(
                makePipAction(android.R.drawable.ic_media_next, "Next", "next", 2),
            )
        }
        return actions
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun makePipAction(
        iconRes: Int,
        title: String,
        action: String,
        requestCode: Int,
    ): android.app.RemoteAction {
        val intent = Intent(PIP_ACTION).apply {
            setPackage(packageName)
            putExtra("pipAction", action)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        val pi = PendingIntent.getBroadcast(this, requestCode, intent, flags)
        val icon = android.graphics.drawable.Icon.createWithResource(this, iconRes)
        return android.app.RemoteAction(icon, title, title, pi)
    }

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		// Lets system audio-effect apps (Wavelet, OEM equalizers) attach to the
		// phone player's audio session — see AudioEffectSession.
		com.debrify.app.audio.AudioEffectSession.register(flutterEngine, this)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"startMediaStoreDownload" -> {
					val url = call.argument<String>("url")
					val fileName = call.argument<String>("fileName") ?: "download"
					val subDir = call.argument<String>("subDir") ?: "Debrify"
					val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
					val markAsUpdate = call.argument<Boolean>("markAsUpdate") ?: false
					@Suppress("UNCHECKED_CAST")
					val headers = call.argument<HashMap<String, String>>("headers") ?: hashMapOf()

					if (url.isNullOrEmpty()) {
						result.error("bad_args", "url is required", null)
						return@setMethodCallHandler
					}

					val baseId = System.currentTimeMillis().toString()
					val taskId = if (markAsUpdate) "update-$baseId" else baseId
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_START
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_URL, url)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_FILE_NAME, fileName)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_RELATIVE_SUBDIR, subDir)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_MIME_TYPE, mimeType)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_HEADERS, headers)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(taskId)
					} catch (e: Exception) {
						// Android 12+ forbids foreground-service starts from the
						// background (ForegroundServiceStartNotAllowedException).
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"pause" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_PAUSE
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"resume" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_RESUME
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"cancel" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_CANCEL
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"openContentUri" -> {
					val uriStr = call.argument<String>("uri")
					val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
					if (uriStr.isNullOrEmpty()) {
						result.error("bad_args", "uri required", null)
						return@setMethodCallHandler
					}
					try {
						val u = Uri.parse(uriStr)
						val view = Intent(Intent.ACTION_VIEW).apply {
							setDataAndType(u, mime)
							addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(view)
						result.success(true)
					} catch (e: ActivityNotFoundException) {
						try {
							val downloads = Intent("android.intent.action.VIEW_DOWNLOADS")
							downloads.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(downloads)
							result.success(false)
						} catch (e2: Exception) {
							result.error("open_failed", e2.message, null)
						}
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
				}
				"openBatteryOptimizationSettings" -> {
					try {
						val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
				}
				"requestIgnoreBatteryOptimizationForApp" -> {
					try {
						val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
							data = Uri.parse("package:" + packageName)
						}
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("request_failed", e.message, null)
					}
				}
				"isTelevision" -> {
					try {
						val uiModeManager = getSystemService(UI_MODE_SERVICE) as UiModeManager
						val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
						result.success(isTv)
					} catch (e: Exception) {
						result.success(false)
					}
				}
				"getDeviceName" -> {
					try {
						// Try to get the user-set device name first (Bluetooth name)
						val bluetoothName = Settings.Global.getString(contentResolver, "device_name")
						if (!bluetoothName.isNullOrBlank()) {
							result.success(bluetoothName)
							return@setMethodCallHandler
						}
						// Fall back to manufacturer + model
						val manufacturer = Build.MANUFACTURER?.replaceFirstChar { it.uppercase() } ?: ""
						val model = Build.MODEL ?: ""
						val deviceName = if (manufacturer.isNotEmpty() && model.isNotEmpty() && !model.startsWith(manufacturer, ignoreCase = true)) {
							"$manufacturer $model"
						} else if (model.isNotEmpty()) {
							model
						} else {
							"Android TV"
						}
						result.success(deviceName)
					} catch (e: Exception) {
						result.success("Android TV")
					}
				}
			else -> result.notImplemented()
			}
		}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(object: EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				com.debrify.app.download.ChannelBridge.setSink(events)
			}

			override fun onCancel(arguments: Any?) {
				com.debrify.app.download.ChannelBridge.setSink(null)
			}
		})

        val tvChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANDROID_TV_CHANNEL
        )
        setAndroidTvPlayerChannel(tvChannel)
        tvChannel.setMethodCallHandler { call, result ->
            android.util.Log.d("DebrifyTV", "MainActivity: Method channel received: ${call.method}")
            when (call.method) {
                "launchTorboxPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorboxPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "torbox")
                }
                "launchRealDebridPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchRealDebridPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "real_debrid")
                }
                "launchTorrentPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorrentPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing torrent payload", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTorrentPlayback(args, result)
                }
                "updateEpisodeMetadata" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling updateEpisodeMetadata")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing metadata updates", null)
                        return@setMethodCallHandler
                    }
                    handleUpdateEpisodeMetadata(args, result)
                }
                else -> {
                    android.util.Log.w("DebrifyTV", "MainActivity: Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        // Inline ExoPlayer texture surface for the ambient trailer backdrop —
        // TV only (the Dart side only selects the Exo engine on Android TV, so
        // there's no reason to stand up the native player + channel elsewhere).
        // Release any prior instance first in case configureFlutterEngine runs
        // again on a reused engine without an intervening onDestroy.
        tvTrailerPlayer?.releaseAll()
        tvTrailerPlayer = null
        if (isTelevision()) {
            tvTrailerPlayer = com.debrify.app.tv.TvTrailerTexturePlayer(
                this,
                flutterEngine.renderer,
                flutterEngine.dartExecutor.binaryMessenger,
                { trailerUnderlayContainer() },
            )
        }

        // Remote control channel for injecting key events and text
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMOTE_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "injectKeyEvent" -> {
                    val keyCode = call.argument<Int>("keyCode")
                    if (keyCode == null) {
                        result.error("bad_args", "keyCode is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // Get the currently active activity (could be MainActivity or a video player)
                        val targetActivity = ActivityTracker.currentActivity
                        if (targetActivity == null) {
                            android.util.Log.w("RemoteControl", "No active activity to receive key event")
                            result.error("no_activity", "No active activity", null)
                            return@setMethodCallHandler
                        }
                        // Dispatch key down event
                        val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                        targetActivity.dispatchKeyEvent(downEvent)
                        // Dispatch key up event
                        val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
                        targetActivity.dispatchKeyEvent(upEvent)
                        android.util.Log.d("RemoteControl", "Injected key event $keyCode to ${targetActivity.javaClass.simpleName}")
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("RemoteControl", "Failed to inject key event: ${e.message}")
                        result.error("inject_failed", e.message, null)
                    }
                }
                "injectText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val clear = call.argument<Boolean>("clear") ?: false
                    try {
                        val targetActivity = ActivityTracker.currentActivity
                        if (targetActivity == null) {
                            android.util.Log.w("RemoteControl", "No active activity to receive text")
                            result.error("no_activity", "No active activity", null)
                            return@setMethodCallHandler
                        }

                        if (clear) {
                            // Select all and delete to clear the field
                            // Send Ctrl+A to select all
                            val metaState = KeyEvent.META_CTRL_ON
                            val downA = KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A, 0, metaState)
                            val upA = KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_A, 0, metaState)
                            targetActivity.dispatchKeyEvent(downA)
                            targetActivity.dispatchKeyEvent(upA)
                            // Then send delete
                            val downDel = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL)
                            val upDel = KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL)
                            targetActivity.dispatchKeyEvent(downDel)
                            targetActivity.dispatchKeyEvent(upDel)
                            android.util.Log.d("RemoteControl", "Cleared text field")
                        } else if (text.isNotEmpty()) {
                            // Use KeyCharacterMap to dispatch key events for each character
                            // This is the most reliable way to inject text into Flutter TextFields
                            // as it uses the same mechanism as physical keyboards
                            val keyCharMap = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD)
                            for (char in text) {
                                val events = keyCharMap.getEvents(charArrayOf(char))
                                if (events != null) {
                                    for (event in events) {
                                        targetActivity.dispatchKeyEvent(event)
                                    }
                                } else {
                                    android.util.Log.w("RemoteControl", "No key events for char: $char")
                                }
                            }
                            android.util.Log.d("RemoteControl", "Injected text via key events: $text")
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("RemoteControl", "Failed to inject text: ${e.message}")
                        result.error("inject_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Picture-in-Picture channel — driven by the phone media_kit player.
        val pipCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel = pipCh
        pipCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(pipSupported())
                "enterPip" -> {
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    result.success(enterPipInternal(aw, ah))
                }
                "setAutoEnter" -> {
                    pipAutoEnterArmed = call.argument<Boolean>("enabled") ?: false
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    pipIsPlaying = call.argument<Boolean>("isPlaying") ?: pipIsPlaying
                    pipHasNext = call.argument<Boolean>("hasNext") ?: pipHasNext
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    updatePipParamsIfActive()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
	}

    private fun handleLaunchTvPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
        provider: String
    ) {
        android.util.Log.d("DebrifyTV", "MainActivity: handleLaunchTvPlayback() called with provider=$provider")
        
        val initialUrl = (args["initialUrl"] as? String)?.trim()
        android.util.Log.d("DebrifyTV", "MainActivity: initialUrl=${initialUrl?.take(50)}...")
        
        if (initialUrl.isNullOrEmpty()) {
            android.util.Log.e("DebrifyTV", "MainActivity: initialUrl is null or empty")
            result.error("bad_args", "initialUrl is required", null)
            return
        }
        
        val initialTitleRaw = (args["initialTitle"] as? String)?.trim()
        val initialTitle = if (initialTitleRaw.isNullOrEmpty()) "Debrify TV" else initialTitleRaw
        android.util.Log.d("DebrifyTV", "MainActivity: title=$initialTitle")

        @Suppress("UNCHECKED_CAST")
        val config = args["config"] as? Map<String, Any?>
        android.util.Log.d("DebrifyTV", "MainActivity: config=$config")

        android.util.Log.d("DebrifyTV", "MainActivity: Creating intent for TorboxTvPlayerActivity")
        val intent = Intent().apply {
            setClassName(this@MainActivity, "com.debrify.app.tv.TorboxTvPlayerActivity")
            putExtra("initialUrl", initialUrl)
            putExtra("initialTitle", initialTitle)
            putExtra("provider", provider)
            putExtra("channelName", (args["channelName"] as? String)?.trim())
            putExtra("currentChannelId", (args["currentChannelId"] as? String)?.trim())
            (args["currentChannelNumber"] as? Number)?.toInt()?.let { number ->
                putExtra("currentChannelNumber", number)
            }

            @Suppress("UNCHECKED_CAST")
            val channelsRaw = args["channels"] as? List<Map<String, Any?>>
            if (!channelsRaw.isNullOrEmpty()) {
                android.util.Log.d(
                    "DebrifyTV",
                    "MainActivity: Preparing ${channelsRaw.size} channel directory entries",
                )
                val channelBundles = ArrayList<Bundle>(channelsRaw.size)
                channelsRaw.forEach { entry ->
                    val bundle = Bundle()
                    (entry["id"] as? String)?.trim()?.let { bundle.putString("id", it) }
                    (entry["name"] as? String)?.trim()?.let { bundle.putString("name", it) }
                    (entry["channelNumber"] as? Number)?.toInt()
                        ?.let { bundle.putInt("channelNumber", it) }
                    (entry["isCurrent"] as? Boolean)?.let { bundle.putBoolean("isCurrent", it) }
                    channelBundles.add(bundle)
                }
                if (channelBundles.isNotEmpty()) {
                    putParcelableArrayListExtra("channelDirectory", channelBundles)
                }
            }

            // For Torbox: magnets are required. For Real-Debrid: magnets are optional
            @Suppress("UNCHECKED_CAST")
            val magnetsRaw = args["magnets"] as? List<Map<String, Any?>>
            if (magnetsRaw != null && magnetsRaw.isNotEmpty()) {
                android.util.Log.d("DebrifyTV", "MainActivity: Processing ${magnetsRaw.size} magnets")
                val magnetBundles = ArrayList<Bundle>()
                magnetsRaw.forEach { entry ->
                    val magnet = (entry["magnet"] as? String)?.trim()
                    if (!magnet.isNullOrEmpty()) {
                        val bundle = Bundle()
                        bundle.putString("magnet", magnet)
                        bundle.putString("hash", (entry["hash"] as? String)?.trim() ?: "")
                        bundle.putString("name", (entry["name"] as? String)?.trim() ?: "")
                        (entry["sizeBytes"] as? Number)?.let { bundle.putLong("sizeBytes", it.toLong()) }
                        (entry["seeders"] as? Number)?.let { bundle.putInt("seeders", it.toInt()) }
                        magnetBundles.add(bundle)
                    }
                }
                if (magnetBundles.isNotEmpty()) {
                    android.util.Log.d("DebrifyTV", "MainActivity: Added ${magnetBundles.size} magnet bundles")
                    putParcelableArrayListExtra("magnetList", magnetBundles)
                }
            } else {
                android.util.Log.d("DebrifyTV", "MainActivity: No magnets provided (OK for Real-Debrid)")
            }
            
            putExtra("startFromRandom", config?.get("startFromRandom") as? Boolean ?: false)
            putExtra("randomStartMaxPercent", (config?.get("randomStartMaxPercent") as? Number)?.toInt() ?: 40)
            putExtra("startAtPercent", (config?.get("startAtPercent") as? Number)?.toDouble() ?: 0.0)
            putExtra("hideSeekbar", config?.get("hideSeekbar") as? Boolean ?: false)
            putExtra("hideOptions", config?.get("hideOptions") as? Boolean ?: false)
            putExtra("showVideoTitle", config?.get("showVideoTitle") as? Boolean ?: true)
            putExtra("showChannelName", config?.get("showChannelName") as? Boolean ?: false)

            // Custom font from Flutter settings
            (args["customFontPath"] as? String)?.trim()?.let { fontPath ->
                putExtra("customFontPath", fontPath)
                (args["customFontName"] as? String)?.trim()?.let { fontName ->
                    putExtra("customFontName", fontName)
                }
                android.util.Log.d("DebrifyTV", "MainActivity: Passing custom font: $fontPath")
            }
        }

        try {
            android.util.Log.d("DebrifyTV", "MainActivity: Starting TorboxTvPlayerActivity")
            startActivity(intent)
            android.util.Log.d("DebrifyTV", "MainActivity: ✅ Activity started successfully")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: ❌ Failed to start activity: ${e.message}")
            e.printStackTrace()
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleUpdateEpisodeMetadata(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        android.util.Log.d("TVMazeUpdate", "MainActivity: handleUpdateEpisodeMetadata CALLED")
        @Suppress("UNCHECKED_CAST")
        val updates = args["updates"] as? List<Map<String, Any?>> ?: emptyList()
        val imdbId = args["imdbId"] as? String

        if (updates.isEmpty() && imdbId.isNullOrEmpty()) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: updates is empty and no imdbId")
            result.error("bad_args", "updates or imdbId is required", null)
            return
        }
        android.util.Log.d("TVMazeUpdate", "MainActivity: received ${updates.size} updates, imdbId=$imdbId")

        try {
            // Broadcast intent to the active player activity
            val intent = Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA").apply {
                setPackage(packageName)
                val updatesJson = listToJson(updates).toString()
                android.util.Log.d("TVMazeUpdate", "MainActivity: updatesJson length=${updatesJson.length}")
                putExtra("metadataUpdates", updatesJson)
                // Include discovered IMDB ID for Stremio subtitle fetching
                if (!imdbId.isNullOrEmpty()) {
                    putExtra("imdbId", imdbId)
                    android.util.Log.d("TVMazeUpdate", "MainActivity: Including imdbId=$imdbId")
                }
            }
            sendBroadcast(intent)
            android.util.Log.d("TVMazeUpdate", "MainActivity: Broadcast SENT with ${updates.size} updates, imdbId=$imdbId")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: Failed to send metadata update: ${e.message}", e)
            result.error("update_failed", e.message, null)
        }
    }

    private fun handleLaunchTorrentPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        val payload = args["payload"]
        if (payload !is Map<*, *>) {
            result.error("bad_args", "payload is required", null)
            return
        }

        try {
            val payloadJson = mapToJson(payload).toString()

            // Write payload to temp file to avoid Android's Intent size limit (~1MB)
            // This allows playlists with 500+ items without TransactionTooLargeException
            val tempFile = java.io.File(cacheDir, "torrent_payload_${System.currentTimeMillis()}.json")
            tempFile.writeText(payloadJson)
            android.util.Log.d("DebrifyTV", "MainActivity: Wrote payload to temp file: ${tempFile.absolutePath} (${payloadJson.length} bytes)")

            val intent = Intent().apply {
                setClassName(
                    this@MainActivity,
                    "com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
                )
                putExtra("payloadPath", tempFile.absolutePath)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: Failed to launch torrent playback", e)
            result.error("launch_failed", e.message, null)
        }
    }

    private fun mapToJson(map: Map<*, *>): org.json.JSONObject {
        val json = org.json.JSONObject()
        for ((key, value) in map) {
            if (key == null) continue
            json.put(key.toString(), valueToJson(value))
        }
        return json
    }

    private fun listToJson(list: List<*>): org.json.JSONArray {
        val array = org.json.JSONArray()
        for (value in list) {
            array.put(valueToJson(value))
        }
        return array
    }

    private fun valueToJson(value: Any?): Any? {
        return when (value) {
            null -> org.json.JSONObject.NULL
            is Map<*, *> -> mapToJson(value)
            is List<*> -> listToJson(value)
            is Number, is Boolean, is String -> value
            else -> value.toString()
        }
    }
}
